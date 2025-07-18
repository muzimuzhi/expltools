#!/bin/bash
# Update regression tests after a failed GitHub Actions run.

set -e -o xtrace

if (( $# != 1 ))
then
  printf 'Usage: %s GITHUB_ACTIONS_RUN_ID\n' "$0" 1>&2
  exit 1
fi

cd "$(dirname "$(readlink -f "$0")")"
rm -rf TL*-issues/
gh run download "$1"
