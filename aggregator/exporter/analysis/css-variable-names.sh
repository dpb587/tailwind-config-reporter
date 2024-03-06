#!/bin/bash

set -euo pipefail

echo
echo '# CSS Variable Names'
echo
echo ' Variable Name | Source Owners | Sources |'
echo ' :------------ | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT DISTINCT
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner,
          cssVariableName
        FROM (
          $(
            sqlite3 mnt/dataset/aggregate/db.sqlite \
              "
                SELECT 'SELECT context_analysisKey, context_repositorySourceOwner, json_each.value AS cssVariableName FROM tailwind_changes, json_each('||name||') WHERE '||name||' IS NOT NULL'
                FROM pragma_table_info('tailwind_changes')
                WHERE NAME LIKE '%_cssVariableNames'
              " \
              | sed 's/$/ UNION /'
          )
          SELECT NULL, NULL, NULL WHERE false
        )
      )
      SELECT
        cssVariableName,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      WHERE cssVariableName IS NOT NULL
      GROUP BY cssVariableName
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY sourceOwners DESC, cssVariableName ASC
EOF
  )" \
  | jq -r '
    map("| **`\(.cssVariableName)`** | \(.sourceOwners) | \(.sources) |")[]
  '
