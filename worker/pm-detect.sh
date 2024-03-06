#!/bin/bash

set -euo pipefail

dir="${1}"

if grep -q '"packageManager":[^"]+"pnpm@"' "${dir}/package.json" \
  || [ -f "${dir}/pnpm-lock.yaml" ] \
  || [ -f "${dir}/pnpm-workspace.yaml" ] \
  || ( cat "${dir}"/README* 2>/dev/null | grep -q 'pnpm install' )
then
  echo pnpm
elif grep -q '"packageManager":[^"]+"yarn@"' "${dir}/package.json" \
  || [ -f "${dir}/yarn.lock" ] \
  || [ -f "${dir}/.yarn" ] \
  || grep -q '":[^"]+"workspace:' "${dir}/package.json" \
  || ( jq -c .scripts < "${dir}/package.json" | grep -q '":"yarn ' ) \
  || ( cat "${dir}"/README* 2>/dev/null | grep -q 'yarn install' )
then
  echo yarn
fi
