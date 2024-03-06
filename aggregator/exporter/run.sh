#!/bin/bash

set -euo pipefail

rm -fr mnt/dataset/analysis
mkdir -p mnt/dataset/analysis

./aggregator/exporter/analysis/general.sh > mnt/dataset/analysis/general.md
./aggregator/exporter/analysis/versions-analyzed.sh > mnt/dataset/analysis/versions-analyzed.md
./aggregator/exporter/analysis/version-constraints.sh > mnt/dataset/analysis/version-constraints.md
./aggregator/exporter/analysis/packages.sh > mnt/dataset/analysis/packages.md
./aggregator/exporter/analysis/css-variable-names.sh > mnt/dataset/analysis/css-variable-names.md
./aggregator/exporter/analysis/config-file-duplication.sh > mnt/dataset/analysis/config-file-duplication.md
./aggregator/exporter/analysis/theme-kv-batch.sh mnt/dataset/analysis
./aggregator/exporter/analysis/theme-fontFamily.sh > mnt/dataset/analysis/theme-fontFamily.md

totalAttempted=$( sqlite3 mnt/dataset/aggregate/db.sqlite 'SELECT COUNT(context_analysisKey) FROM metadata' )
totalCompleted=$( sqlite3 mnt/dataset/aggregate/db.sqlite 'SELECT COUNT(context_analysisKey) FROM metadata WHERE extract_completed = 1' )
totalFailed=$( sqlite3 mnt/dataset/aggregate/db.sqlite 'SELECT COUNT(context_analysisKey) FROM metadata WHERE extract_failed = 1' )
totalPackagingSquash=$( sqlite3 mnt/dataset/aggregate/db.sqlite 'SELECT COUNT(context_analysisKey) FROM metadata WHERE timestamp_attempt_full_begin IS NULL' )
totalPackagingFull=$( sqlite3 mnt/dataset/aggregate/db.sqlite 'SELECT COUNT(context_analysisKey) FROM metadata WHERE timestamp_attempt_full_begin IS NOT NULL' )

(
  echo '# Tailwind Config Report'
  echo
  echo "Some mildly interesting details from analyzing ${totalCompleted} open source projects that rely on [Tailwind CSS](https://tailwindcss.com/). I am not affiliated with Tailwind Labs, just a casual user of their projects. Originally, [this post](https://twitter.com/adamwathan/status/1762597487443956083) got me curious about some of the practices, so I hacked together some past scripts and similar experiments to generate these results ([source code](https://github.com/dpb587/tailwind-config-reporter)). I have not spent too much time reviewing data quality, so there is still room for improvement."
  echo
  echo 'The following summaries use "Source Owners" to refer to unique organizations/users owning a repository and "Source" to refer to a Tailwind-related path within a repository. Some owners may have multiple repositories, and some repositories may have multiple sources. Gauging by source owners seemed like a slightly better indicator of usage. If only a single source owner makes a particular configuration change, it is generally excluded from the summary tables.'
  echo
  echo '* **[General Usage](./analysis/general.md)** - customized features, disabled core plugins, content file extensions, prefixes'
  echo '* **[Analyzed Versions](./analysis/versions-analyzed.md)** - related package versions which were resolved and used during analysis'
  echo '* **[Version Constraints](./analysis/version-constraints.md)** - related package version constraints documented in `package.json` files'
  echo '* **[All Packages](./analysis/packages.md)** - all packages referenced in `package.json` files'
  echo '* **[CSS Variable Names](./analysis/css-variable-names.md)** - common variable names found'
  echo '* **[Config File Duplication](./analysis/config-file-duplication.md)** - duplicate configs used across sources'
  echo -n '* Theme Properties - '

  prefix=

  while read -r file
  do
    property=$( basename "${file}" | sed -E 's/theme-(.+)\.md/\1/' )
    echo -n "${prefix}**[${property}](./analysis/$( basename "${file}" ))**"
    prefix=', '
  done < <( find mnt/dataset/analysis -name 'theme-*.md' | sort --ignore-case )

  echo
  echo '  * Updated Names - shows built-in names where users overwrite default values'
  echo '  * Additional Names - shows user-introduced names and their values'
  echo '  * Value Conventions - shows basic usage of units (e.g. rem, px), CSS functions, and standard keywords *(only supported for some properties)*'
  echo '  * Deleted Names - shows built-in names where users disabled them'

  echo
  echo '## Data'
  echo
  echo "In total, ${totalAttempted} analysis tasks were executed (${totalCompleted} completed successfully, ${totalFailed} failed; ${totalPackagingSquash} used dependency squashing, ${totalPackagingFull} full installation). Tasks can fail for a number of reasons including: wide range of expected Node build runtimes, outdated package managers, restricted network access and build runtime, and occasional bugs."
  echo
  echo 'The following raw data files are included in this branch for each task:'
  echo
  echo '* `extract-completed` (or `extract-failed`) is an empty marker file which indicates the job completed successfully'
  echo '* `extract-installed-packages.jsonl` contains the packages and versions used during the analysis (which may be a subset of the original `package.json` file)'
  echo '* `extract-metadata.jsonl` contains some metadata about the analysis such as project source, times, and analysis behaviors'
  echo '* `extract-raw-package.json` contains the original contents of the `package.json` file from the source'
  echo '* `extract-raw-tailwind-config.js` contains the original contents of the `tailwind.config.*` file from the source'
  echo '* `extract-tailwind-config-baseline.json` contains the baseline tailwind configuration with common, default plugins and no customization'
  echo '* `extract-tailwind-config-effective.json` contains the effective tailwind configuration with any customizations'
  echo '* `extract.log` contains the console output generated during analysis'
  echo
  echo 'These public sources were discovered primarily via GitHub API based on code search and tailwind-tagged repositories. Some additional requirements were applied, too, such as semi-recent commits, stars, and not being forks. The following are included in this dataset, although this is a small subset of the potential sources which could be analyzed.'
  echo
  echo '|  ?  | Source | Duration | Data |'
  echo '| :-: | ------ | -------: | ---- |'

  sqlite3 --json mnt/dataset/aggregate/db.sqlite \
    '
      SELECT *
      FROM metadata
      ORDER BY input_repo_name ASC, input_repo_path ASC
    ' \
    | jq -r \
      '
        map("| " + (
          [
            ( if .extract_completed == 1 then "✅" else "❌" end ),
            ([
              " [**",
              .input_repo_name,
              "**",
              "](https://",
              .input_repo_name,
              "/tree/",
              ( @uri "\(.input_repo_ref)" ),
              "/",
              ( @uri "\( .input_repo_path | ltrimstr("./") )" ),
              ")",
              ( if .input_repo_path != "./" then ( " (`" + ( .input_repo_path | ltrimstr("./") ) + "`)" ) else "" end )
            ] | join("") ),
            ( if .timestamp_end then ( ( ( .timestamp_end | fromdateiso8601 ) - ( .timestamp_begin | fromdateiso8601 ) ) | "\(. / 60 | floor )m \(. - ( . - . % 60 ) )s" | gsub("0m "; "") | gsub(" 0s"; "") ) else "*n/a*" end),
            ( "[Data](./" + ( .extract_datadir | ltrimstr("mnt/dataset/") ) + ")" )
          ] | join(" | ")
        ) + " |")[]
      '
) > mnt/dataset/README.md

exit
 |