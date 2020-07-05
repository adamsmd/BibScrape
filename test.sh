#!/bin/sh

# This script is a test driver for bib-scrape.
# To run it do:
#  $ ./test.sh <filename> ...
# where <filename> is the name of a test file.  For example,
# to run all ACM tests do:
#  $ ./test.sh tests/acm-*.t

if test 0 -eq $#; then
    echo "ERROR: No test files specified"
    exit 1
fi

for i in "$@"; do
    echo "$i"
    URL=$(head -n 1 "$i")
    (head -n 2 "$i"; ./bib-scrape.pl "$URL") | diff -u "$i" - | wdiff -dt
done
