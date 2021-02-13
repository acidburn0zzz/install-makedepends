#!/bin/sh -e
topdir="$(realpath "$(dirname "$0")/..")"
cd "$topdir"

# shellcheck disable=SC2046
shellcheck $(find . -name '*.sh')

echo "shellcheck passed"
