#!/bin/bash

set -euo pipefail

datadir="${1}"

twcrdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/.."
cd "${twcrdir}"

rm -fr "${datadir}"/transform-*

record_context="$(
  jq -cs \
    '
      from_entries
      | {
        analysisKey: .analysis_key,
        repositorySource: .input_repo_name,
        repositorySourceOwner: (.input_repo_name | split("/")[1] ),
        repositoryRef: .input_repo_ref,
        repositoryPath: .input_repo_path,
      }
    ' \
    < "${datadir}/extract-metadata.jsonl"
)"

jq -sc \
  --argjson context "${record_context}" \
  --argjson completed "$( ! [ -f "${datadir}/extract-completed" ] && echo false || echo true )" \
  --argjson failed "$( ! [ -f "${datadir}/extract-failed" ] && echo false || echo true )" \
  --arg datadir "${datadir}" \
  '
    {
      context: $context,
      extract_datadir: $datadir,
      extract_completed: $completed,
      extract_failed: $failed
    }
    + ( . | from_entries )
  ' \
  < <(
    cat "${datadir}/extract-metadata.jsonl"

    if [ -f "${datadir}/extract-raw-package.json" ]
    then
      sha256sum "${datadir}/extract-raw-package.json" | awk '{ print $1 }' | jq -cR '{ key: "file_package_sha256", value: . }'
    fi

    if [ -f "${datadir}/extract-raw-tailwind-config.js" ]
    then
      sha256sum "${datadir}/extract-raw-tailwind-config.js" | awk '{ print $1 }' | jq -cR '{ key: "file_tailwind_config_sha256", value: . }'
    fi
  ) \
  > "${datadir}/transform-metadata.jsonl"

if ! [ -f "${datadir}/extract-completed" ]
then
  exit
fi

node transformer/tailwind-changes-analyzer/run.mjs "${datadir}" \
  | jq -c \
    --argjson context "${record_context}" \
    '
      {
        context: $context,
      } + .
    ' \
    > "${datadir}/transform-tailwind-changes.jsonl"

jq -c \
  --argjson context "${record_context}" \
  '
    {
      context: $context,
      packageName: .name,
      packageVersion: .version,
    }
  ' \
  < "${datadir}/extract-installed-packages.jsonl" \
  > "${datadir}/transform-installed-packages.jsonl"

jq -c \
  --argjson context "${record_context}" \
  '
    [
      ( .dependencies | [ "dependencies", . ] ),
      ( .devDependencies | [ "devDependencies", . ] ),
      ( .optionalDependencies | [ "optionalDependencies", . ] ),
      ( .peerDependencies | [ "peerDependencies", . ] )
    ] | map(
      .[0] as $set |
      .[1] // [] | to_entries | map({
        context: $context,
        dependencySet: $set,
        packageName: .key,
        packageVersionConstraint: .value,
      })[]
    )[]
  ' \
  < "${datadir}/extract-raw-package.json" \
  > "${datadir}/transform-package-constraints.jsonl"
