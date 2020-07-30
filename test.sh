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
# For example, to run all ACM tests in headless mode, do:
#
#     $ ./test.sh --headless tests/acm-*.t

FLAGS=()

while test $# -gt 0; do
  case "$1" in
    --) break;;
    -*) FLAGS+=("$1"); shift;;
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
  if !(head -n 2 "$i"; ./bin/bibscrape "${FLAGS[@]}" "$URL") | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi

  echo "** Testing $i using a filename **"
  if ! ./bin/bibscrape "${FLAGS[@]}" <(grep -v '^WARNING: Suspect name: ' "$i") | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi
done

exit "$ERR_COUNT"
