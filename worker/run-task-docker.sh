#!/bin/bash

set -euo pipefail

twcrdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/.."

repo="${1}"
reporef="${2:-HEAD}"
repopath="${3:-}"

outputdir="mnt/dataset/data/${repo}/$( base64 <<<"${reporef}" | tr -d = | tr '/+' '_-' )/$( base64 <<<"${repopath}" | tr -d = | tr '/+' '_-' )"

# lazy idempotency
[ ! -d "${outputdir}" ] || [ "${4:-}" == "force" ]

proxytag="tid_$( ( date -u +%Y%m%d%H%M%S ; head -c 32 /dev/urandom ) | sha256sum | awk '{ print $1 }' | cut -c1-12 )"
logstart="$( date -u +%Y-%m-%dT%H:%M:%SZ ; sleep 1 )"

rm -fr "${twcrdir}/${outputdir}"
mkdir -p "${twcrdir}/${outputdir}"

# -e TMPDIR=/twcr/mnt/cache \ # too slow across mounts

proxyip=$(
  docker inspect tailwind-config-reporter-worker-proxy \
    | jq -r '.[0].NetworkSettings.Networks["tailwind-config-reporter-worker"].IPAddress'
)

# not practical here unless a repository added their own key
# typically misconfigured repo; should be using public https-based clones, not ssh
cat <<EOF > "${TMPDIR}/twcr-ssh-config"
Host *
  ProxyCommand socat - PROXY:${proxyip}:%h:%p,proxyport=3128,proxyauth=${proxytag}:ok
EOF

echo "==== RUN-DOCKER" > "${twcrdir}/${outputdir}/extract.log"

set -x
set +e
docker run --rm \
  -v "${PWD}/${outputdir}:/twcr/mnt/results" \
  -v "${PWD}/worker:/twcr/worker:ro" \
  -v "${TMPDIR}/twcr-ssh-config:/home/node/.ssh/config" \
  --network tailwind-config-reporter-worker \
  -e http_proxy=http://${proxytag}:ok@${proxyip}:3128 \
  -e HTTP_PROXY=http://${proxytag}:ok@${proxyip}:3128 \
  -e https_proxy=http://${proxytag}:ok@${proxyip}:3128 \
  -e HTTPS_PROXY=http://${proxytag}:ok@${proxyip}:3128 \
  -e IS_RUNNING_IN_DOCKER=true \
  -e TWCR_RUN_OUTPUT_DIR="/twcr/mnt/results" \
  -e PUPPETEER_SKIP_DOWNLOAD=true ${IFS# optimized skip; common dependency, but should not be necessary } \
  -e PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 ${IFS# optimized skip; common dependency, but should not be necessary } \
  --workdir /twcr \
  tailwind-config-reporter-worker \
  ./worker/run-task.sh "${repo}" "${reporef}" "${repopath}" \
  2>&1 \
    | tee -a "${twcrdir}/${outputdir}/extract.log"
exitcode="$?"
set -e

docker logs tailwind-config-reporter-worker-proxy 2>&1 \
  | grep " ${proxytag} " \
  | grep -v NONE_NONE/ \
  | sed "s/ ${proxytag} / /" \
  > "${twcrdir}/${outputdir}/extract-proxy.log"

if [[ "${exitcode}" != "0" ]]
then
  grep _DENIED/403 "${twcrdir}/${outputdir}/extract-proxy.log" \
    | sed 's/^/[PROXY] /' \
    || true

  exit "${exitcode}"
fi

# awk '{ sum += $5 } END { print sum }' "${twcrdir}/${outputdir}/extract-proxy.log"

node transformer/analyze-tailwind-changes.mjs "${twcrdir}/${outputdir}"
