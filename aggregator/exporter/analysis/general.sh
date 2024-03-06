#!/bin/bash

set -euo pipefail

echo '# General Settings'
echo

echo '## Disabled Core Plugins'
echo
echo '| Core Plugin | Source Owners | Sources |'
echo '| :---------- | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner,
          corePlugin_plugin AS plugin
        FROM tailwind_changes
        WHERE corePlugin_plugin IS NOT NULL
      )
      SELECT
        plugin,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY plugin
    )
    SELECT * FROM q
    ORDER BY plugin
EOF
  )" \
  | jq -r '
    map("| **\(.plugin)** | \(.sourceOwners) | \(.sources) |")[]
  '

echo
echo '## Content File Extensions'
echo
echo '| Extension | Source Owners | Sources |'
echo '| :-------- | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          contentFilesPathExt_ext AS ext,
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner
        FROM tailwind_changes
        WHERE contentFilesPathExt_ext IS NOT NULL
      )
      SELECT
        ext,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY ext
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY sourceOwners DESC, sources DESC, ext ASC
EOF
  )" \
  | jq -r '
    map("| **\(.ext)** | \(.sourceOwners) | \(.sources) |")[]
  '

echo
echo '## Prefix'
echo
echo '| Prefix | Source Owners | Sources |'
echo '| :----- | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          metadata.context_analysisKey AS source,
          metadata.context_repositorySourceOwner AS sourceOwner,
          tailwind_changes.prefix_configValue AS configValue
        FROM metadata
        LEFT JOIN tailwind_changes
          ON tailwind_changes.context_analysisKey = metadata.context_analysisKey
          AND tailwind_changes.prefix_configValue IS NOT NULL
      )
      SELECT
        configValue,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY configValue
    )
    SELECT * FROM q
    ORDER BY configValue NULLS FIRST
EOF
  )" \
  | jq -r '
    map("| \( if .configValue == null then "*(none)*" else "**`\(.configValue | fromjson)`**" end ) | \(.sourceOwners) | \(.sources) |")[]
  '
