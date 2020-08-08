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

NO_URL=0
NO_FILENAME=0
NO_WITHOUT_SCRAPING=0

while test $# -gt 0; do
  case "$1" in
    --) break;;
    --no-url) NO_URL=1;;
    --no-filename) NO_FILENAME=1;;
    --no-without-scraping) NO_WITHOUT_SCRAPING=1;;
    -*) GLOBAL_FLAGS+=(\"$1\");;
    * ) break;;
  esac
  shift
done

if test $# -eq 0; then
  echo "ERROR: No test files specified"
  exit 1
fi

ERR_COUNT=0

for i in "$@"; do
  FLAGS=$(head -n 2 "$i" | tail -1)

  if test 0 -eq $NO_URL; then
    echo "** [$(date +%r)] Testing $i using a URL **"
    URL=\"$(head -n 1 "$i")\"
    if !(head -n 3 "$i"; eval timeout --foreground 60s "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" "$URL" 2>&1) \
        | diff -u "$i" - | wdiff -dt; then
      true $((ERR_COUNT++))
    fi
  fi

  if test 0 -eq $NO_FILENAME; then
    echo "** [$(date +%r)] Testing $i using a filename **"
    if ! eval timeout --foreground 60s "$BIBSCRAPE" $FLAGS "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: ' "$i") 2>&1 \
        | diff -u "$i" - | wdiff -dt; then
      true $((ERR_COUNT++))
    fi
  fi

  if test 0 -eq $NO_WITHOUT_SCRAPING; then
    echo "** [$(date +%r)] Testing $i using a filename without scraping **"
    if ! eval timeout --foreground 60s "$BIBSCRAPE" --/scrape $FLAGS "${GLOBAL_FLAGS[@]}" <(grep -v '^WARNING: ' "$i") 2>&1 \
        | diff -u <(grep -v 'WARNING: Oxford imposes rate limiting.' "$i" | grep -v 'WARNING: Non-ACM paper at ACM link') - | wdiff -dt; then
      true $((ERR_COUNT++))
    fi
  fi
done

exit "$ERR_COUNT"
