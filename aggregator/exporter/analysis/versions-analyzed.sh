#!/bin/bash

set -euo pipefail

echo
echo '# Analyzed Versions'
echo
echo "These are the versions that were resolved during analysis. Due to the analysis process, these versions may have been resolved using a subset of the source's dependencies, so it is not fully representative. The [version constraints](./version-constraints.md) page has more details about the actual constraints recorded in" '`package.json`.'
echo
echo '## Summary'

echo '| Package | Source Owners | Sources |'
echo '| ------- | ------------: | ------: |'
sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          packageName,
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner
        FROM installed_packages
        WHERE
          (
            packageName LIKE 'tailwindcss'
            OR packageName LIKE '@tailwindcss/%'
            OR packageName LIKE '@heroicons/%'
            OR PackageName LIKE '@headlessui/%'
          )
      )
      SELECT
        packageName,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY packageName
    )
    SELECT * FROM q
    ORDER BY packageName ASC, sourceOwners DESC
EOF
  )" \
  | jq -r '
    map("| **`\(.packageName)`** | \(.sourceOwners) | \(.sources) |")[]
  '

echo '## Version Details'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          packageName,
          packageVersion,
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner
        FROM installed_packages
        WHERE
          (
            packageName LIKE 'tailwindcss'
            OR packageName LIKE '@tailwindcss/%'
            OR packageName LIKE '@heroicons/%'
            OR PackageName LIKE '@headlessui/%'
          )
          AND packageVersion IS NOT NULL
      )
      SELECT
        packageName,
        packageVersion,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY packageName, packageVersion
    )
    SELECT * FROM q
    ORDER BY packageName ASC, sourceOwners DESC
EOF
  )" \
  | jq -r '
    (group_by(.packageName) | map([
      "",
      "### \(.[0].packageName)",
      "",
      "| Version | Source Owners | Sources |",
      "| ------- | ------------: | ------: |",
      map("| **`\(.packageVersion)`** | \(.sourceOwners) | \(.sources) |")[]
    ])[])[]
  '
