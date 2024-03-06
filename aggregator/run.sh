#!/bin/bash

set -euo pipefail

twcrdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/.."
cd "${twcrdir}"

rm -fr mnt/dataset/aggregate
mkdir -p mnt/dataset/aggregate

bundles=(
  "installed-packages"
  "metadata"
  "package-constraints"
  "tailwind-changes"
)

for f in "${bundles[@]}"
do
  find mnt/dataset/data -name "transform-${f}.jsonl" -exec cat {} \; \
    | gzip -9 \
    > "mnt/dataset/aggregate/${f}.jsonl.gz"
done

rm -fr mnt/dataset/aggregate/db.sqlite

(
  echo 'PRAGMA locking_mode = EXCLUSIVE;'
  echo ".load ./mnt/sqlite/sqlean/crypto"

  for bundle in "${bundles[@]}"
  do
    gunzip -c "mnt/dataset/aggregate/${bundle}.jsonl.gz" \
      | jq -c '
        [
          paths as $path
          | [ $path, getpath($path) ]
          | select(
            (.[0] | map(select(type == "number")) | length == 0)
            and (.[1] | type != "object")
          )
          | ( .[1] | type ) as $type
          | [
              ( .[0] | join("_") ),
              $type,
              if $type == "boolean" then
                if .[1] then 1
                else 0
                end
              elif $type == "array" then
                .[1] | tojson
              else
                .[1]
              end
            ]
        ]
      ' \
      | gzip -9c \
      > "mnt/dataset/aggregate/kv-${bundle}.jsonl.gz"

    bundle_table="$( tr - _ <<<"${bundle%.jsonl}" )"

    echo "CREATE TABLE ${bundle_table} ("
    gunzip -c "mnt/dataset/aggregate/kv-${bundle}.jsonl.gz" \
      | jq -r '
        map([
          .[0],
          " ",
          if .[1] == "boolean" then
            "INTEGER"
          elif .[1] == "number" then
            "REAL"
          else
            "TEXT"
          end
        ] | join(""))[]
      ' \
      | sort -u \
      | sed 's/$/,/'
    echo "rowid PRIMARY KEY"
    echo ");"

    gunzip -c "mnt/dataset/aggregate/kv-${bundle}.jsonl.gz" \
      | jq -r \
        --arg bundle_table "${bundle_table}" \
        "$( cat <<'EOF'
          map([
            .[0],
            if .[1] == "boolean" or .[1] == "number" then
              .[2] | tostring
            else
              .[2] | tostring | ( "cast(decode('" + @base64 "\(.)" + "', 'base64') as text)" )
            end
          ])
          | (
            "INSERT INTO "
            + $bundle_table
            + " ("
            + ( map(.[0]) | join(", ") )
            + ") VALUES ("
            + ( map(.[1]) | join(", ") )
            + ");"
          )
EOF
        )"
  done
) \
  | ./mnt/sqlite/sqlite3 mnt/dataset/aggregate/db.sqlite
