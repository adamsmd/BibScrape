#!/usr/bin/env perl6

use v6;

use Test;

plan 3;

# These three import all the other modules
use-ok 'BibScrape::CommandLine';
use-ok 'BibScrape::Main';
use-ok 'BibScrape::MainNounGen';

done-testing;
