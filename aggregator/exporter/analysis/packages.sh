#!/bin/bash

set -euo pipefail

echo
echo '# Packages'

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
        FROM package_constraints
      )
      SELECT
        packageName,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY packageName
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY packageName ASC, sourceOwners DESC
EOF
  )" \
  | jq -r '
    map("| **`\(.packageName)`** | \(.sourceOwners) | \(.sources) |")[]
  '
