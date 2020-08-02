#!/bin/bash

# This script is a test driver for bib-scrape.
# To run it do:
#
#     $ ./test.sh <flag> ... <filename> ...
#
# where <flag> is a flag to pass to bib-scrape and <filename> is the name of a
# test file. The flags end at the first argument to not start with `-` or after
# a `--` argument.
#
# For example, to run all ACM tests while showing the browser window, do:
#
#     $ ./test.sh --show-window tests/acm-*.t

GLOBAL_FLAGS=()

while test $# -gt 0; do
  case "$1" in
    --) break;;
    -*) GLOBAL_FLAGS+=("$1"); shift;;
    * ) break;;
  esac
done

if test $# -eq 0; then
  echo "ERROR: No test files specified"
  exit 1
fi

ERR_COUNT=0

for i in "$@"; do
  echo "** Testing $i using a URL **"
  URL=$(head -n 1 "$i")
  FLAGS="$(head -n 2 "$i" | tail -1)"
  if !(head -n 3 "$i"; ./bin/bibscrape $FLAGS "${GLOBAL_FLAGS[@]}" "$URL" 2>&1) | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi

  echo "** Testing $i using a filename **"
  if ! ./bin/bibscrape "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: Suspect name: ' "$i") 2>&1 | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi
done

exit "$ERR_COUNT"
