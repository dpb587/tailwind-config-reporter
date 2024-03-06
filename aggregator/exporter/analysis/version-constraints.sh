#!/bin/bash

set -euo pipefail

echo
echo '# Version Constraints'
echo
echo 'These are the version constraints used by sources in their `package.json` files.'

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT
          packageName,
          packageVersionConstraint,
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner
        FROM package_constraints
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
        packageVersionConstraint,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY packageName, packageVersionConstraint
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY packageName ASC, sourceOwners DESC, packageVersionConstraint ASC
EOF
  )" \
  | jq -r '
    (group_by(.packageName) | map([
      "",
      "### \(.[0].packageName)",
      "",
      "| Version Constraint | Source Owners | Sources |",
      "| :----------------- | ------------: | ------: |",
      map("| **`\(.packageVersionConstraint)`** | \(.sourceOwners) | \(.sources) |")[]
    ])[])[]
  '
