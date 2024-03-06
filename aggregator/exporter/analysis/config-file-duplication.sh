#!/bin/bash

set -euo pipefail

echo
echo '# Config File Duplication'

while read -r entry
do
  echo
  echo "## Example ($( jq -r .sha256 <<<"${entry}" | cut -c1-8 ))"
  echo
  jq -r '"Found across \(.sources) sources (and \(.sourceOwners) source owners)."' <<<"${entry}"
  echo
  echo '```javascript'
  cat "$( jq -r .exampleDatadir <<<"${entry}" )/extract-raw-tailwind-config.js"
  echo '```'
done < <(
  sqlite3 --json mnt/dataset/aggregate/db.sqlite \
    '
      SELECT
        file_tailwind_config_sha256 AS sha256,
        COUNT(context_analysisKey) AS sources,
        COUNT(DISTINCT context_repositorySourceOwner) AS sourceOwners,
        extract_datadir AS exampleDatadir
      FROM metadata
      GROUP BY file_tailwind_config_sha256
      HAVING COUNT(DISTINCT context_repositorySourceOwner) > 2
      ORDER BY COUNT(file_tailwind_config_sha256) DESC
      LIMIT 10;
    ' \
    | jq -c '.[]'
)
