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

NO_URL=0
NO_FILENAME=0
NO_WITHOUT_SCRAPING=0
RETRIES=1
TIMEOUT=60
GLOBAL_FLAGS=()

while test $# -gt 0; do
  case "$1" in
    --) break;;
    --no-url) NO_URL=1;;
    --no-filename) NO_FILENAME=1;;
    --no-without-scraping) NO_WITHOUT_SCRAPING=1;;
    --retries) shift; RETRIES="$1";;
    --timeout) shift; TIMEOUT="$1";;
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
  (head -n 3 "$i"; eval "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" "\"$(head -n 1 "$i")\"" 2>&1) \
    | diff --unified --label "$i using a $type" "$i" - | wdiff -dt
  teardown
}

test-filename() {
  setup 'filename' "$@"
  eval "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: ' "$i") 2>&1 \
    | diff --unified --label "$i using a $type" "$i" - | wdiff -dt
  teardown
}

test-without-scraping() {
  setup 'filename without scraping' "$@"
  eval "$BIBSCRAPE" --/scrape $FLAGS "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: ' "$i") 2>&1 \
    | diff --unified --label "$i using a $type" \
        <(grep -v 'WARNING: Oxford imposes rate limiting.' "$i" \
          | grep -v 'WARNING: Non-ACM paper at ACM link') - \
    | wdiff -dt
  teardown
}

source "$(which env_parallel.bash)"

run() {
  FUNCTION="$1"; shift
  TYPE="$1"; shift
  echo "================================================"
  echo "Testing $TYPE"
  echo "================================================"
  echo
  # Other `parallel` flags we might use:
  #  --progress --eta
  #  --dry-run
  #  --max-procs 8
  #  --keep-order
  #  --nice n
  #  --quote
  #  --no-run-if-empty
  #  --shellquote
  #  --joblog >(cat)
  #  --delay 0.1
  #  --jobs n
  #  --line-buffer
  env_parallel --bar --retries "$RETRIES" --timeout "$TIMEOUT" "$FUNCTION" ::: "$@"
  n="$?"
  echo
  echo "================================================"
  if test 0 -eq "$n"; then
    echo "All tests passed for $TYPE"
  else
    echo "$n tests failed for $TYPE"
  fi
  echo "================================================"
  echo
}

COUNT=0
if test 0 -eq "$NO_URL"; then
  run test-url 'URLs' "$@"
  COUNT=$((COUNT+n))
fi
if test 0 -eq "$NO_FILENAME"; then
  run test-filename 'filenames' "$@"
  COUNT=$((COUNT+n))
fi
if test 0 -eq "$NO_WITHOUT_SCRAPING"; then
  run test-without-scraping 'filenames without scraping' "$@"
  COUNT=$((COUNT+n))
fi

exit "$COUNT"
