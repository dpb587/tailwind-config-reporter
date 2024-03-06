#!/bin/bash

set -euxo pipefail

package_manager_name="${1}"
procdir="${2}"
datadir="${3}"

case "${package_manager_name}" in
npm)
  npm \
    $( [ -f package-lock.json ] && echo 'ci' || echo 'install' ) \
    --ignore-engines ${IFS# runtime should not significantly affect analysis }

  npm query '*' \
    | jq -cr \
      '
        map({ name: .name, version: .version })
        | map(select(.name))
        | sort_by(.name)[]
      ' \
    > "${datadir}/extract-installed-packages.jsonl"

  ;;
pnpm)
  # avoid version strictness
  [ ! -f "${procdir}/package.json" ] \
    || sed -Ei 's/("pnpm": ")(.+)(")/\1'$( pnpm -v )'\3/' "${procdir}/package.json"
  [ ! -f package.json ] \
    || sed -Ei 's/("pnpm": ")(.+)(")/\1'$( pnpm -v )'\3/' package.json

  pnpm install
    # commented out after getting tired of tweaking with mixed results
    # --filter ./... ${IFS# avoid installing an entire repository } \
    # --config.dedupe-peer-dependents=false ${IFS# attempt at further reducing side effects(?); https://github.com/pnpm/pnpm/issues/6300 } \
    # --fix-lockfile ${IFS# in case we squashed packages }

  # TODO doesn't include workspace project links (e.g. ./worker/run-task-docker.sh "github.com/sushiswap/sushiswap" "master" "apps/storybook")

  pnpm ls --json \
    | jq -cr \
      '
        .[]
        | [.dependencies, .devDependencies, .optionalDependencies]
        | map(select(.))[]
        | to_entries
        | map({ name: .key, version: .value.version })
        | sort_by(.name)[]
      ' \
    > "${datadir}/extract-installed-packages.jsonl"

  ;;
yarn)
  # env settings seem to be ignored for embedded yarn.cjs or maybe when repository .yarnrc exists
  # also, seems like parameter names maybe evolved; http[s]Proxy being the newer standard
  # also, seems like auth support was only added in 2022 for v4+?: https://github.com/yarnpkg/berry/pull/4243
  [ -z "${http_proxy}" ] \
    || (
      yarn config set httpProxy "${http_proxy}"
      # yarn config set proxy "${http_proxy}"
    )
  [ -z "${https_proxy}" ] \
    || (
      yarn config set httpsProxy "${https_proxy}"
      # yarn config set https-proxy "${https_proxy}"
    )

  yarn \
    install
    # sometimes option fails with alt embedded yarn.cjs `➤ YN0050: The --ignore-engines option is deprecated; engine checking isn't a core feature anymore`
    # --ignore-engines ${IFS# runtime should not significantly affect analysis }

  # sometimes `list` fails with alt embedded yarn.cjs
  yarn list --depth=0 --json --non-interactive --no-progress \
    | jq -cr \
      '
        [.. | .name?]
        | map(select(.))
        | map(capture("^(?<name>@?[^@]+)@(?<version>.+)$"))
        | sort_by(.name)[]' \
    > "${datadir}/extract-installed-packages.jsonl"

  ;;
*)

esac
