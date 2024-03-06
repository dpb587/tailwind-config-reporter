#!/bin/bash

set -euo pipefail

echo "# Theme (fontFamily)"

echo
echo '## Custom Fonts'
echo
echo ' Font | Source Owners | Sources |'
echo ' ---- | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT DISTINCT
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner,
          font
        FROM (
          SELECT DISTINCT context_analysisKey, context_repositorySourceOwner, addedValues.value AS font
          FROM tailwind_changes, json_each(themeFontFamily_valueProfile_addedValues) AS addedValues
          WHERE themeFontFamily_valueProfile_addedValues IS NOT NULL
          UNION
          SELECT *
          FROM (
            SELECT DISTINCT context_analysisKey, context_repositorySourceOwner, createdValues.value AS font
            FROM tailwind_changes, json_each(themeFontFamily_valueProfile_createdValues) AS createdValues
            WHERE themeFontFamily_valueProfile_createdValues IS NOT NULL
          )
          WHERE font NOT IN (
            -- baseline fonts are not recorded, so assuming they were removed at some point so we can exclude them
            SELECT DISTINCT removedValues.value AS font
            FROM tailwind_changes, json_each(themeFontFamily_valueProfile_removedValues) AS removedValues
            WHERE themeFontFamily_valueProfile_removedValues IS NOT NULL
          )
        )
      )
      SELECT
        font,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      WHERE font IS NOT NULL
      GROUP BY font
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY sourceOwners DESC, font ASC
EOF
  )" \
  | jq -r '
    map("| **`\(.font)`** | \(.sourceOwners) | \(.sources) |")[]
  '

echo
echo '## Deleted Names'
echo

./aggregator/exporter/common/kv-config-delete-names.sh fontFamily
