#!/usr/bin/env raku

#$|++;

use lib '.';
use BibTeX;
use Isbn;
use Fix;
use Scrape; # Must be last (See comment in Scrape.rakumod)

# TODO: version 20.07.05
# TODO: @ flags

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
  ## INPUTS
  # TODO: $FindBin::RealBin/config/names.cfg
  #say $*PROGRAM;
  #say $*PROGRAM-NAME;
  my Str $names = <config/names.cfg>;
  my Str $nouns = <config/nouns.cfg>;

  ## FIELD OPTIONS
  my @fields = <
    author editor affiliation title
    howpublished booktitle journal volume number series jstor_issuetitle
    type jstor_articletype school institution location conference_date
    chapter pages articleno numpages
    edition day month year issue_date jstor_formatteddate
    organization publisher address
    language isbn issn doi eid acmid url eprint bib-scrape-url
    note annote keywords abstract copyright>;
  my Str @no-encode = <doi url eprint bib-scrape-url>;
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

  #for @url -> $url {
  my $bibtex = scrape($url);
  $bibtex = $fixer.fix($bibtex);
  say $bibtex.Str;
  #}
}


############
# Options
############
#
# Key: Keep vs generate
#
# Author, Editor: title case, initialize, last-first
# Author, Editor, Affiliation(?): List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
#  List of renames (regex?)
#
# Title
#  Captialization: Initialisms, After colon, list of proper names
#
# ISSN: Print vs Electronic
# Keywords: ';' vs ','

# TODO:
#  author as editors?
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  follow jstor links to original publisher
#  add abstract to jstor
#  get PDF
#END TODO

# TODO: omit type-regex field-regex (existing entry is in scope)

# Omit:class/type
# Include:class/type
# no issn, no isbn
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
# Warning on duplicate names

# TODO:
# ALWAYS_GEN_KEY
#$PREFER_NEW 1 = use new when both new and old have a key
#$ADD_NEW 1 = use new when only new has key
#$REMOVE_OLD 1 = not use old when only new has key

#my %RANGE = map {($_,1)} qw(chapter month number pages volume year);
#my @REQUIRE_FIELDS = (...); # per type (optional regex on value)
#my @RENAME

# TODO:
# preserve key if from bib-tex?
# warn about duplicate author names

# my (@NAME_FILE) = ("$FindBin::RealBin/config/names.cfg");
# my (@FIELD_ACTION_FILE) = ("$FindBin::RealBin/config/actions.cfg");

# # TODO: make debug be verbose and go to STDERR

# # TODO: whether to re-scrape bibtex
# for my $filename (@INPUT) {
#     my $bib = new Text::BibTeX::File $filename;
#     # TODO: print "junk" between entities

#     until ($bib->eof()) {
#         my $entry = new Text::BibTeX::Entry $bib;
#         next unless defined $entry and $entry->parse_ok;

#         if (not $entry->metatype == BTE_REGULAR) {
#             print $entry->print_s;
#         } else {
#             if (not $entry->exists('bib_scrape_url')) {
#                 # Try to find a URL to scrape
#                 if ($entry->exists('doi') and $entry->get('doi') =~ m[http(?:s)?://[^/]+/(.*)]i) {
#                     (my $url = $1) =~ s[DOI:\s*][]ig;
#                     $entry->set('bib_scrape_url', "https://doi.org/$url");
#                 } elsif ($entry->exists('url') and $entry->get('url') =~ m[^http(?:s)?://(?:dx.)?doi.org/.*$]) {
#                     $entry->set('bib_scrape_url', $entry->get('url'));
#                 }
#             }
# ###TODO(?): decode utf8
#             scrape_and_fix_entry($entry);
#         }
#     }
# }

# for (@ARGV) {
#     my $entry = new Text::BibTeX::Entry;
#     $entry->set_key($1) if $_ =~ s[^\{([^}]*)\}][];
#     $_ =~ s[^doi:][http(?:s)?://(?:dx)?.doi.org/]i;
#     $entry->set('bib_scrape_url', $_);
#     scrape_and_fix_entry($entry);
# }

# sub scrape_and_fix_entry {
#     my ($old_entry) = @_;

#     # TODO: warn if not exists bib_scrape_url
#     my $entry = (($old_entry->exists('bib_scrape_url') && $SCRAPE) ?
#         Text::BibTeX::Scrape::scrape($old_entry->get('bib_scrape_url')) :
#         $old_entry);
#     $entry->set_key($old_entry->key());
#     print $FIX ? $fixer->fix($entry) : $entry->print_s;
# }
