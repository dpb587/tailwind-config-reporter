#!/bin/bash

set -euo pipefail

twcrdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/.."
cd "${twcrdir}"

set -x

find mnt/dataset/data \
  -depth 5 \
  -print0 \
  | xargs -n1 -0 -P 4 ./transformer/run-extract.sh
