#!/usr/bin/env raku

use lib '.';
use Scrape;

sub MAIN(Str $input, Bool $debug = False) {
  scrape($input);
}
