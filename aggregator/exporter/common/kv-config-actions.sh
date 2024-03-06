#!/bin/bash

set -euo pipefail

echo '| Configuration | Source Owners | Sources |'
echo '| :------------ | ------------: | ------: |'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          metadata.context_analysisKey AS source,
          metadata.context_repositorySourceOwner AS sourceOwner,
          config.configAction
        FROM metadata
        LEFT JOIN (
          SELECT
            context_analysisKey,
            context_repositorySourceOwner,
            theme${1}_configAction AS configAction
          FROM tailwind_changes
          WHERE theme${1}_configAction IS NOT NULL
          GROUP BY context_analysisKey, context_repositorySourceOwner, theme${1}_configAction
        ) AS config
          ON config.context_analysisKey = metadata.context_analysisKey
          AND config.context_repositorySourceOwner = metadata.context_repositorySourceOwner
        WHERE metadata.extract_completed = 1
      )
      SELECT
        configAction,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY configAction
    )
    SELECT * FROM q
    ORDER BY configAction ASC
EOF
  )" \
  | jq -r '
    { "CREATE": "Additional Names", "UPDATE": "Updated Names", "DELETE": "Deleted Names" } as $m |
    map("| " + ( if .configAction == null then "*no change*" else "**\($m[.configAction])**" end ) + " | \(.sourceOwners) | \(.sources) |")[]
  '
