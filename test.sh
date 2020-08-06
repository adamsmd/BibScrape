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

# Determine where `bibscrape` is based on the location of this script
if [ -z "$BIBSCRAPE" ]; then
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  BIBSCRAPE="$DIR"/bin/bibscrape
fi

GLOBAL_FLAGS=()

while test $# -gt 0; do
  case "$1" in
    --) break;;
    -*) GLOBAL_FLAGS+=(\"$1\"); shift;;
    * ) break;;
  esac
done

if test $# -eq 0; then
  echo "ERROR: No test files specified"
  exit 1
fi

ERR_COUNT=0

for i in "$@"; do
  echo "** [$(date +%r)] Testing $i using a URL **"
  URL=\"$(head -n 1 "$i")\"
  FLAGS=$(head -n 2 "$i" | tail -1)
  if !(head -n 3 "$i"; eval timeout 60s "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" "$URL" 2>&1) | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi

  echo "** [$(date +%r)] Testing $i using a filename **"
  if ! eval timeout 60s "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: ' "$i") 2>&1 | diff -u "$i" - | wdiff -dt; then
    true $((ERR_COUNT++))
  fi
done

exit "$ERR_COUNT"
