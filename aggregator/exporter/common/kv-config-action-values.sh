#!/bin/bash

set -euo pipefail

echo '| Name | Effective Value | Source Owners | Sources |'
echo '| :--- | :-------------- | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner,
          theme${1}_name AS name,
          theme${1}_configValue AS configValue
        FROM tailwind_changes
        WHERE theme${1}_configAction = '${2}'
      )
      SELECT
        name,
        configValue,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY name, configValue
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY sourceOwners DESC, name ASC, configValue ASC
EOF
  )" \
  | jq -r '
    map("| **`\(.name)`** | `\(.configValue)` | \(.sourceOwners) | \(.sources) |")[]
  '
