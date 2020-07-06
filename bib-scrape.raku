#!/usr/bin/env raku

use lib '.';
use Scrape;

# TODO: version 20.07.05
# TODO: @ flags

enum MediaType <Print Online Both>;
enum IsbnType <Isbn-13, Isbn-10, Preserve>;

sub MAIN(
# =head1 SYNOPSIS
#
# bib-scrape.pl [options] <url> ...
#


# =head2 INPUTS
#
  Str $url, # TODO: @url
# =item <url>
#
# The url of the publisher's page for the paper to be scraped.
# Standard URL formats such as 'http://...' can be used.
# The non-standard URL format 'doi:...' can also be used.
# May be prefixed with '{key}' in order to specify an explicit key.
#
#  Str :@input, # TODO: is File.read or '-' >> where *.IO.f
# =item --input=<file>
#
# Take BibTeX data from <file> to rescrape or fix.
# If <file> is '-', then read from STDIN.
#
# WARNING: "junk" and malformed entities will be omitted from the output
# (This is an upstream problem with the libraries we use.)
#
#  Str :@names = (), # TODO: is File.read
# =item --names=<file>
#
# Add <file> to the list of name files used to canonicalize author names.
# If <file> is the empty string, clears the list.
#
# See the L</NAME FILE> section for details on the format of name files.
#
#  Str :@actions = (), # TODO: is File.read and Perl
# =item --actions=<file>
#
# Add <file> to the list of action files used to canonicalize fields.
# If <file> is the empty string, clears the list.
#
# See the L</ACTION FILE> section for details on the format of action files.
#


# =head2 OPERATING MODES
#
  Bool :$debug = False,
# =item --debug, --no-debug [default=no]
#
# Print debug data
#
  Bool :$fix = True,
# =item --fix, --no-fix [default=yes]
#
# Fix common mistakes in the BibTeX
#
  Bool :$scrape = True,
# =item --scrape, --no-scrape [default=yes]
#
# Scrape BibTeX entry from the publisher's page
#


# =head2 GENERAL OPTIONS
#
  MediaType :$isbn-media = Both,
# =item --isbn=<kind> [default=both]
#
# When both a print and an online ISBN are available, use only the print
# ISBN if <kind> is 'print', only the online ISBN if <kind> is 'online',
# or both if <kind> is 'both'.
#
  IsbnType :$isbn-type = Preserve,
# =item --isbn13=<mode> [default=0]
#
# If <mode> is a positive integer, then always use ISBN-13 in the output.
# If negative, then use ISBN-10 when possible.
# If zero, then preserve the original format of an ISBN.
#
  Str :$isbn-sep = '-',
# =item --isbn-sep=<sep> [default=-]
#
# Use <sep> to separate parts of an ISBN.
# Use an empty string to specify no separator.
#
  MediaType :$issn = Both,
# =item --issn=<kind> [default=both]
#
# When both a print and an online ISSN are available, use only the print
# ISSN if <kind> is 'print', only the online ISSN if <kind> is 'online',
# or both if <kind> is 'both'.
#
  Bool :$comma = True,
# =item --comma, --no-comma [default=yes]
#
# Place a comma after the final field of a BibTeX entry.
#
  Bool :$escape-acronyms = True,
# =item --escape-acronyms, --no-escape-acronyms [default=yes]
#
# In titles, enclose sequences of two or more uppercase letters (i.e.,
# an acronym) in braces to that BibTeX preserves their case.
#


# =head2 Per FIELD OPTIONS
#
#  Str :@field = (),
# =item --field=<field>
#
# Add a field to the list of known BibTeX fields.
#
#  Str :@no-encode = <doi url eprint bib_scrape_url>,
# =item --no-encode=<field>
#
# Add a field to the list of fields that should not be LaTeX encoded.
# By default this includes doi, url, eprint, and bib_scrape_url, but if
# this flag is specified on the command line, then only those explicitly
# listed on the command line are included.
#
#  Str :@no-collapse = (),
# =item --no-collapse=<field>
#
# Add a filed to the list of fields that should not have their
# white space collapsed.
#
#  Str :@omit = (),
# =item --omit=<field>
#
# Omit a particular field from the output.
#
#  Str :@omit-empty = (),
# =item --omit-empty=<field>
#
# Omit a particular field from the output if it is empty.
#


# =head2 NAME FILES
#
# A name file specifies the correct form for author names.
# Any name that is not of the form "FIRST LAST" is suspect unless
# it is in a name file.
#
# A name file is plain text in Unicode format.
# In a name file, any line starting with # is a comment.
# Blank or whitespace-only lines separate blocks, and
# blocks consist of one or more lines.
# The first line is the canonical form of a name.
# Lines other than the first one are aliases that should be converted to the
# canonical form.
#
# When searching for the canonical form of a name, case distinctions and
# the divisions of the name into parts (e.g. first vs last name) are
# ignored as publishers often get these wrong (e.g., "Van Noort" will
# match "van Noort" and "Jones, Simon Peyton" will match "Peyton Jones,
# Simon").
#
# The default name file provides several examples and recommended practices.
#


# =head2 ACTION FILES
#
# An action file specifies transformations to be applied to each field.
#
# This file is just Perl code.
# On entry, $FIELD will contain the name of the current BibTeX field,
# and $_ will contain the contents of the field.
# The value of $_ at the end of this file will be stored back in the field.
# If it is undef then the field will be deleted.
#
# TIP: Remember to check $FIELD so you transform only the correct fields.
#
# TIP: Remember to put "\b", "/g" and/or "/i" on substitutions if appropriate.
#
# =cut
) {
  #for @url -> $url {
  my $bibtex = scrape($url);
  say $bibtex.Str;
  #}
}
