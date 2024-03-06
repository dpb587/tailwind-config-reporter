#!/bin/bash

set -euo pipefail

docker build -t tailwind-config-reporter-worker-proxy worker-proxy
docker build -t tailwind-config-reporter-worker worker

if ! docker network inspect tailwind-config-reporter-worker >/dev/null 2>&1
then
  docker network create --internal tailwind-config-reporter-worker
fi

if docker container inspect tailwind-config-reporter-worker-proxy >/dev/null 2>&1
then
  docker rm tailwind-config-reporter-worker-proxy
fi

if ! docker volume inspect tailwind-config-reporter-worker-proxy-mnt-squid >/dev/null 2>&1
then
  docker volume create tailwind-config-reporter-worker-proxy-mnt-squid
fi

docker create \
  --name tailwind-config-reporter-worker-proxy \
  --mount source=tailwind-config-reporter-worker-proxy-mnt-squid,target=/mnt/squid \
  tailwind-config-reporter-worker-proxy

docker network connect tailwind-config-reporter-worker tailwind-config-reporter-worker-proxy

docker start --attach tailwind-config-reporter-worker-proxy
