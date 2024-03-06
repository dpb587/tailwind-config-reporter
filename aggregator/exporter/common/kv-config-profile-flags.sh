#!/bin/bash

set -euo pipefail

echo '| Kind | Detail | Source Owners | Sources |'
echo '| :--- | :----- | ------------: | ------: |'

profileFields="$(
  sqlite3 mnt/dataset/aggregate/db.sqlite \
    "
      SELECT name
      FROM pragma_table_info('tailwind_changes')
      WHERE name LIKE '${1}_valueProfile\_%' ESCAPE '\'
    "
)"

if [[ -z "${profileFields}" ]]
then
  exit
fi

sqlite3 --json mnt/dataset/aggregate/db.sqlite \
  "$( cat <<EOF
    WITH q AS (
      WITH q AS (
        SELECT DISTINCT
          context_analysisKey AS source,
          context_repositorySourceOwner AS sourceOwner,
          flagKind,
          flagDetail
        FROM (
          $(
            if grep -iq "${1}_valueProfile_cssFunctionCalc$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'CSS Function' AS flagKind,
                  'calc(*)' AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_cssFunctionCalc = 1
                UNION
              "
            fi
          )
          $(
            if grep -iq "${1}_valueProfile_cssFunctionVar$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'CSS Function' AS flagKind,
                  'var(*)' AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_cssFunctionVar = 1
                UNION
              "
            fi
          )
          $(
            if grep -iq "${1}_valueProfile_unit$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'Unit' AS flagKind,
                  ${1}_valueProfile_unit AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_unit IS NOT NULL
                UNION
              "
            fi
          )
          $(
            if grep -iq "${1}_valueProfile_keyword$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'Keyword' AS flagKind,
                  ${1}_valueProfile_keyword AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_keyword IS NOT NULL
                UNION
              "
            fi
          )
          $(
            if grep -iq "${1}_valueProfile_twcrMatcher$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'Analysis Matcher' AS flagKind,
                  ${1}_valueProfile_twcrMatcher AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_twcrMatcher IS NOT NULL
                UNION
              "
            fi
          )
          $(
            if grep -iq "${1}_valueProfile_entriesCount$" <<<"${profileFields}"
            then
              echo "
                SELECT
                  context_analysisKey,
                  context_repositorySourceOwner,
                  'Subvalue Count' AS flagKind,
                  ${1}_valueProfile_entriesCount AS flagDetail
                FROM tailwind_changes
                WHERE ${1}_valueProfile_entriesCount IS NOT NULL
                UNION
              "
            fi
          )
          SELECT NULL AS context_analysisKey, NULL AS context_repositorySourceOwner, NULL AS flagKind, NULL AS flagDetail
        )
      )
      SELECT
        flagKind,
        flagDetail,
        COUNT(DISTINCT source) AS sources,
        COUNT(DISTINCT sourceOwner) AS sourceOwners
      FROM q
      GROUP BY flagKind, flagDetail
    )
    SELECT * FROM q
    WHERE sourceOwners > 1
    ORDER BY sourceOwners DESC, flagKind ASC, flagDetail ASC
EOF
  )" \
  | jq -r '
    map("| \(.flagKind) | " + ( if .flagDetail == null then "*n/a*" else "**`\(.flagDetail)`**" end ) + " | \(.sourceOwners) | \(.sources) |")[]
  '
