#!/usr/bin/env perl6

use lib 'lib';
use BibTeX;
use Isbn;
use Fix;
use Scrape; # Must be last (See comment in Scrape.rakumod)

sub MAIN(
# =head1 SYNOPSIS
#
# bib-scrape.pl [options] <url> ...
#


# =head2 INPUTS
#
  Str $url is copy,
# =item <url>
#
# The url of the publisher's page for the paper to be scraped.
# Standard URL formats such as 'http://...' can be used.
# The non-standard URL format 'doi:...' can also be used.
# May be prefixed with '{key}' in order to specify an explicit key.
#
#  Str :@input,
# =item --input=<file>
#
# Take BibTeX data from <file> to rescrape or fix.
# If <file> is '-', then read from STDIN.
#
# WARNING: "junk" and malformed entities will be omitted from the output
# (This is an upstream problem with the libraries we use.)
#
#  Str :@names = (),
# =item --names=<file>
#
# Add <file> to the list of name files used to canonicalize author names.
# If <file> is the empty string, clears the list.
#
# See the L</NAME FILE> section for details on the format of name files.
#
#  Str :@nouns = (),
# =item --nouns=<file>
#
# Add <file> to the list of noun files used to canonicalize fields.
# If <file> is the empty string, clears the list.
#
# See the L</NOUN FILE> section for details on the format of noun files.
#


# =head2 OPERATING MODES
#
  Bool :$debug = False,
# =item --debug, --no-debug [default=no]
#
# Print debug data
#
  Bool :$scrape = True,
# =item --scrape, --no-scrape [default=yes]
#
# Scrape BibTeX entry from the publisher's page
#
  Bool :$fix = True,
# =item --fix, --no-fix [default=yes]
#
# Fix common mistakes in the BibTeX
#


# =head2 GENERAL OPTIONS
#
  Bool :$final-comma = True,
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
  Fix::MediaType :$isbn-media = Fix::Both,
# =item --isbn=<kind> [default=both]
#
# When both a print and an online ISBN are available, use only the print
# ISBN if <kind> is 'print', only the online ISBN if <kind> is 'online',
# or both if <kind> is 'both'.
#
  Isbn::IsbnType :$isbn-type = Isbn::Preserve,
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
# For example, a space is common.
# Use an empty string to specify no separator.
#
  Fix::MediaType :$issn-media = Fix::Both,
# =item --issn=<kind> [default=both]
#
# When both a print and an online ISSN are available, use only the print
# ISSN if <kind> is 'print', only the online ISSN if <kind> is 'online',
# or both if <kind> is 'both'.
#


# =head2 Per FIELD OPTIONS
#
#  Str :%field = (),
# =item --field=<field>
#
# Add a field to the list of known BibTeX fields.
#
#  Str :%no-encode = <doi url eprint bib_scrape_url>,
# =item --no-encode=<field>
#
# Add a field to the list of fields that should not be LaTeX encoded.
# By default this includes doi, url, eprint, and bib_scrape_url, but if
# this flag is specified on the command line, then only those explicitly
# listed on the command line are included.
#
#  Str :%no-collapse = (),
# =item --no-collapse=<field>
#
# Add a filed to the list of fields that should not have their
# white space collapsed.
#
#  Str :%omit = (),
# =item --omit=<field>
#
# Omit a particular field from the output.
#
#  Str :%omit-empty = (),
# =item --omit-empty=<field>
#
# Omit a particular field from the output if it is empty.
#


# =head2 NAMES
#
# We warn the user about author and editor names that publishers often get
# wrong.  For example, some publisher assume the last name of Simon Peyton Jones
# is "Jones" when it should be "Peyton Jones", and some publishers put author
# names in all upper case (e.g., "CONNOR MCBRIDE").
#
# We call these names "suspect", not because they are wrong but because the user
# should double check them.
#
# The only names we do not consider suspect are the followin formats, which the
# publishers are unlikely to get wrong, or ones explicitly listed in the </NAME
# FILES>.
#
# First names:
#
#   - Xxxx
#   - Xxxx-Xxxx
#   - Xxxx-xxxx
#   - XxxxXxxx
#
# A single middle initial may follow the first name:
#
#   - X.
#
# Last names:
#
#   - Xxxx
#   - Xxxx
#   - O'Xxxx
#   - McXxxx
#   - MacXxxx
#
# This collection of name formats was chosen based the list of all authors in
# DBLP and tries to strike a ballance between prompting the user about too many
# names and missing names that should be reported.


# =head2 NAME FILES
#
# A name file specifies the correct form for author names.
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


# =head2 NOUN FILES
#
# An noun file specifies words that should be protected from lower-casing
# by inserting curly braces.
#
# A noun file is plain text in Unicode format.
# Each line starting with # is a comment.
# Blank lines are ignored.
# Each line lists the way that a particular word
# should be curly braced.  (Curly braces tell BibTeX to not change the captalization of a particular part of a text.)
# Any word that matches but with the curly braces removed is converted to the form listed in the file.
# The first line to match in the file wins.
#
# =cut
) {
  ## INPUTS
  my Str $names = $*PROGRAM.dirname ~ </config/names.cfg>;
  my Str $nouns = $*PROGRAM.dirname ~ </config/nouns.cfg>;

  ## FIELD OPTIONS
  my @fields = <
    author editor affiliation title
    howpublished booktitle journal volume number series jstor_issuetitle
    type jstor_articletype school institution location conference_date
    chapter pages articleno numpages
    edition day month year issue_date jstor_formatteddate
    organization publisher address
    language isbn issn doi eid acmid url eprint bib_scrape_url
    note annote keywords abstract copyright>;
  my Str @no-encode = <doi url eprint bib_scrape_url>;
  my Str @no-collapse = < >;
  my Str @omit = < >;
  my Str @omit-empty = <abstract issn doi keywords>;

  my $fixer = Fix::Fix.new(
    name-file => $names,
    noun-file => $nouns,
    debug => $debug,
    scrape => $scrape,
    fix => $fix,
    final-comma => $final-comma,
    escape-acronyms => $escape-acronyms,
    isbn-media => $isbn-media,
    isbn-type => $isbn-type,
    isbn-sep => $isbn-sep,
    issn-media => $issn-media,
    fields => @fields,
    no-encode => @no-encode,
    no-collapse => @no-collapse,
    omit => @omit,
    omit-empty => @omit-empty,
  );

  sub go(Str $key is copy, Str $url) {
    my $driver-url = $url;

    # Support `{key}` before the url to specify the key
    $driver-url ~~ s/^ '{' (<-[}]>*) '}' \s* //;
    $key //= ($0 // '').Str;

    my $bibtex = scrape($driver-url);
    $bibtex.fields<bib_scrape_url> = BibTeX::Value.new($url);

    $bibtex = $fixer.fix($bibtex);

    $bibtex.key = $key if $key;

    print $bibtex.Str ~ "\n";
  }

  for ($url) -> $url {
    if $url !~~ /^ 'file:' / {
      go(Str, $url);
    } else {
      my $bibtex = bibtex-parse($/.postmatch.IO.slurp);
      for $bibtex.items -> $item {
        if $item !~~ BibTeX::Entry {
          print $item.Str;
        } else {
          if $item.fields<bib_scrape_url> {
            go($item.key, $item.fields<bib_scrape_url>.simple-str);
          } elsif $item.fields<doi> {
            my $doi = $item.fields<doi>;
            $doi = "doi:$doi" unless $doi ~~ m:i/^ 'doi:' /;
            go($item.key, $doi);
          } else {
            print $item.Str
          }
        }
      }
    }
  }
}
