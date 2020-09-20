#!/bin/bash

# This script is a test driver for bibscrape.
# To run it do:
#
#     $ ./test.sh <flag> ... <filename> ...
#
# where <flag> is a flag to pass to bibscrape and <filename> is the name of a
# test file. The flags end at the first argument to not start with `-` or after
# a `--` argument.
#
# For example, to run all ACM tests while showing the browser window, do:
#
#     $ ./test.sh --window tests/acm-*.t

# Determine where `bibscrape` is located based on the location of this script
if [ -z "$BIBSCRAPE" ]; then
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    # if $SOURCE was a relative symlink, we need to resolve it relative to the
    # path where the symlink file was located
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  BIBSCRAPE="$DIR"/bin/bibscrape
fi

GLOBAL_FLAGS=()

while test $# -gt 0; do
  case "$1" in
    --) break;;
    -*) GLOBAL_FLAGS+=(\"$1\");;
    * ) break;;
  esac
  shift
done

if test $# -eq 0; then
  echo "ERROR: No test files specified"
  exit 1
fi

setup() {
  fail() {
    echo "EXITED ABNORMALLY: $i using a $type"
    exit 1
  }
  trap fail EXIT
  # These variables are for use by the calling function
  type="$1"
  i="$2"
  FLAGS=$(head -n 2 "$i" | tail -1)
}

teardown() {
  err="$?"
  trap - EXIT
  return $err
}

test-url() {
  setup 'URL' "$@"
  eval "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" "\"$(head -n 1 "$i")\""
  teardown
}

COUNT=0
for file in "$@"; do
  echo "================================================"
  echo "Running $file"
  echo "================================================"
  test-url "$file"
  n="$?"
  if test 0 -ne "$n"; then
    COUNT=$((COUNT+1))
  fi
done
echo "================================================"

exit "$COUNT"
