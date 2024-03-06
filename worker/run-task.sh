#!/bin/bash

set -euxo pipefail

twcrdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/.."

repo="${1}"
reporef="${2:-HEAD}"
repopath="./${3:-}"

[ "${IS_RUNNING_IN_DOCKER}" == "true" ] # assert container user
! grep -q "^././" <<<"${repopath}" # avoid accidental key divergence

procdir="${TMPDIR:-/tmp}/twcr-$( echo "${repo}" | sha256sum | awk '{ print $1 }' | cut -c1-12 )"
datadir="${twcrdir}/mnt/dataset/data/$( echo "${repo};${reporef};${repopath}" | sha256sum | awk '{ print $1 }' | cut -c1-12 )"

if [ ! -z "${TWCR_RUN_OUTPUT_DIR:-}" ]
then
  # caller should manage lifecycle
  datadir="${TWCR_RUN_OUTPUT_DIR}"
else
  rm -fr "${datadir}"
  mkdir -p "${datadir}"
fi

touch "${datadir}/extract-failed"

writetaskstat() {
  jq -nc \
    --arg key "${1}" \
    --arg value "${2}" \
    '{ key: $key, value: $value }' \
    >> "${datadir}/extract-metadata.jsonl"
}

writetaskstat "analysis_key" "${repo}/$( base64 <<<"${reporef}" | tr -d = | tr '/+' '_-' )/$( base64 <<<"${repopath}" | tr -d = | tr '/+' '_-' )"
writetaskstat "analysis_nonce" "$( ( date -u +%Y%m%d%H%M%S ; head -c 32 /dev/urandom ) | sha256sum | awk '{ print $1 }' | cut -c1-16 )"
writetaskstat "input_repo_name" "${repo}"
writetaskstat "input_repo_ref" "${reporef}"
writetaskstat "input_repo_path" "${repopath}"
writetaskstat "timestamp_begin" "$( date -u +%Y-%m-%dT%H:%M:%SZ )"

mkdir -p "${procdir}"
pushd "${procdir}"

# TODO maybe first fetch tree, find package.json + tailwind.config, download, attempt; only then fallback to clone

if ! [ -d ".git" ]
then
  git clone --depth=1 -b "${reporef}" "https://${repo}.git" .
else
  rm -f tailwind.config* # clean up after manual hacks
  git -c core.hooksPath= checkout "${reporef}"
  git -c core.hooksPath= checkout .
  # git clean -fdx
fi

writetaskstat "timestamp_git_clone_complete" "$( date -u +%Y-%m-%dT%H:%M:%SZ )"

writetaskstat "exec_repo_commit_sha" "$( git rev-parse HEAD )"
writetaskstat "exec_repo_commit_date" "$( date -u --date "$( git show --no-patch --format=%ci )" +%Y-%m-%dT%H:%M:%SZ )"

if ! [ -z "${repopath}" ]
then
  pushd "${repopath}"
fi

#
# capture raw files
#

tailwind_config_file_name=

if [ -f tailwind.config.js ]
then
  tailwind_config_file_name=tailwind.config.js
elif [ -f tailwind.config.cjs ]
then
  tailwind_config_file_name=tailwind.config.cjs
elif [ -f tailwind.config.mjs ]
then
  tailwind_config_file_name=tailwind.config.mjs
elif [ -f tailwind.config.ts ]
then
  tailwind_config_file_name=tailwind.config.ts
else
  echo "[worker] ERROR: expected tailwind.config.EXT, but found none" >&2
  exit 1
fi

writetaskstat "exec_tailwind_config_file" "${tailwind_config_file_name}"

cp "${tailwind_config_file_name}" "${datadir}/extract-raw-tailwind-config.js"

if [ ! -f package.json ]
then
  echo "[worker] ERROR: expected package.json, but found none" >&2
  exit 1
fi

cp package.json "${datadir}/extract-raw-package.json"

#
# detect package manager
#

package_manager_name=$( "${twcrdir}/worker/pm-detect.sh" "${PWD}" )

if [ -z "${package_manager_name}" ] && [ "${repopath}" != "./" ]
then
  package_manager_name=$( "${twcrdir}/worker/pm-detect.sh" "${procdir}" )
fi

if [ -z "${package_manager_name}" ]
then
  package_manager_name=npm
fi

writetaskstat "exec_node_package_manager" "${package_manager_name}"

attempt_mode=squash

while true
do
  writetaskstat "timestamp_attempt_${attempt_mode}_begin" "$( date -u +%Y-%m-%dT%H:%M:%SZ )"

  if [[ "${attempt_mode}" == "squash" ]]
  then
    # first try and install without excess dependencies

    set +e
    node ${twcrdir}/worker/squash-package.mjs "${tailwind_config_file_name}"
    exitcode="$?"
    set -e

    if [[ "${exitcode}" != "0" ]]
    then
      echo "[worker] WARN: squash failed; retrying with full install" >&2

      attempt_mode=full

      continue
    fi

    cat package.json | sed 's/^/>>> /'
    rm -f package-lock.json pnpm-lock.yaml yarn.lock
    
    if [ "${repopath}" != "./" ]
    then
      rm -f "${procdir}/package.json" "${procdir}/package-lock.json" "${procdir}/pnpm-lock.yaml" "${procdir}/yarn.lock"
    fi
  else
    git clean -fdx
    git reset --hard
  fi

  set +e
  "${twcrdir}/worker/pm-install.sh" "${package_manager_name}" "${procdir}" "${datadir}"
  exitcode="$?"
  set -e

  if [[ "${exitcode}" != "0" ]]
  then
    if [[ "${attempt_mode}" == "squash" ]]
    then
      echo "[worker] WARN: package manager failed; retrying with full install" >&2

      attempt_mode=full

      continue
    fi

    exit "${exitcode}"
  fi

  tailwind_package_version=$(
    jq -sr 'map(select(.name == "tailwindcss")) | first | .version' \
      < "${datadir}/extract-installed-packages.jsonl"
  )

  #
  # capture effective config
  #

  tailwind_config_exporter=tailwind.config.exporter2.cjs
  
  if [ -f node_modules/tailwindcss/lib/lib/load-config.js ]
  then
    tailwind_config_exporter=tailwind.config.exporter3.mjs
  fi

  cp "${twcrdir}/worker/${tailwind_config_exporter}" ./

  set +e
  node "./${tailwind_config_exporter}" "${tailwind_config_file_name}" \
    > "${datadir}/extract-tailwind-config-effective.json"
  exitcode="$?"
  set -e

  if [[ "${exitcode}" != "0" ]]
  then
    if [[ "${attempt_mode}" == "squash" ]]
    then
      echo "[worker] WARN: exporter failed; retrying with full install" >&2

      attempt_mode=full

      continue
    fi

    exit "${exitcode}"
  fi

  #
  # capture baseline config
  #

  (
    echo 'module.exports={plugins:['
    # lazy; better selection/validation of testable plugins?
    jq -rs \
      '
        map(select(.name | startswith("@tailwindcss/")))
        | map("require(" + ( .name | tojson ) + "),")[]
      ' \
      < "${datadir}/extract-installed-packages.jsonl" \
      | grep -Ev '"@tailwindcss/postcss7-compat"' \
      || true
    echo ']}'
  ) > "${tailwind_config_file_name}"

  cat "${tailwind_config_file_name}" | sed 's/^/>>> /'

  node "./${tailwind_config_exporter}" "${tailwind_config_file_name}" \
    > "${datadir}/extract-tailwind-config-baseline.json"

  #
  # done
  #

  writetaskstat "timestamp_attempt_${attempt_mode}_end" "$( date -u +%Y-%m-%dT%H:%M:%SZ )"

  break
done

writetaskstat "timestamp_end" "$( date -u +%Y-%m-%dT%H:%M:%SZ )"

rm "${datadir}/extract-failed"
touch "${datadir}/extract-completed"
