unit module BibScrape::Main;

use BibScrape::BibTeX;
use BibScrape::CommandLine;
use BibScrape::Isbn;
use BibScrape::Fix;
use BibScrape::Scrape; # Must be last (See comment in Scrape.rakumod)

#|{;;
Collect BibTeX entries from the websites of academic publishers.
;;
See https://github.com/adamsmd/BibScrape/README.md for more details.
;}
sub MAIN(
#={
 ----------------
;BOOLEAN FLAGS
;----------------
;
;Use --flag to set to True.
;Use --/flag to set to False.
;
;----------------
;LIST FLAGS
;----------------
;
;Use --flag=<value> to add an element.
;Use --/flag=<value> to remove an element.
;Use --flag= to set to an empty list.
;Use --/flag= to set to the default list.
;
;----------------
;NAMES
;----------------
;;
BibScrape warns the user about author and editor names that publishers often get
wrong.  For example, some publisher assume the last name of Simon Peyton Jones
is "Jones" when it should be "Peyton Jones", and some publishers put author
names in all upper case (e.g., "CONNOR MCBRIDE").
;;
We call these names "suspect", not because they are wrong but because the user
should double check them.
;;
The only names we do not consider suspect are those in the names files (see the
NAMES FILE section) or those that consist of a first name, optional middle
initial, and last name in any of the following formats:
;;
First name:
;
; - Xxxx
; - Xxxx-Xxxx
; - Xxxx-xxxx
; - XxxxXxxx
;;
Middle initial:
;
; - X.
;;
Last name:
;
; - Xxxx
; - Xxxx
; - O'Xxxx
; - McXxxx
; - MacXxxx
;;
This collection of name formats was chosen based the list of all authors in
DBLP and tries to strike a ballance between names that publishers are unlikely
to get wrong and prompting the user about too many names.
;
;----------------
;NAMES FILES
;----------------
;;
A names file specifies the correct form for author names.
;;
A names file is plain text in Unicode format.
Anything after # (hash) is a comment.
Blank or whitespace-only lines separate blocks, and
blocks consist of one or more lines.
The first line in a block is the canonical/correct form for a name.
Lines other than the first one are aliases that should be converted to the
canonical form.
;;
When searching for a name, case distinctions and divisions of the name into
parts (e.g. first vs last name) are ignored as publishers often get these
wrong (e.g., "Van Noort" will match "van Noort" and "Jones, Simon Peyton" will
match "Peyton Jones, Simon").
;;
The default name file provides several examples with comments and recommended
practices.
;
;----------------
;NOUNS FILES
;----------------
;;
An nouns file specifies words that should be protected from lower-casing by
inserting curly braces into the output BibTeX.
;;
A noun file is plain text in Unicode format.
Anything after # (hash) is a comment.
Blank or whitespace-only lines are ignored.
Each line lists the way that a particular word should be curly braced.
(Curly braces tell BibTeX to not change the captalization of a particular part of a text.)
Any word that matches with the curly braces removed is converted to the form listed in the file.
The first line to match in the file is the one that is used.
;;
The default nouns file provides several examples with comments and recommended
practices.
}

#|{
 ----------------
;INPUTS
;----------------
;}

  Str:D @url,
#={The publisher's page to be scraped or the filename of a BibTeX
    file to be read to find BibTeX entries to rescrape or fix.
    ;
    ;- If it starts with 'http:' or 'https:', it is interpreted as a URL.
    ;- If it starts with 'doi:', it is interpreted as a DOI.
    ;- Otherwise, it is interpreted as a filename.
    ;;
    The URL and DOI forms may be prefixed with '{<key>}' in order to specify an
    explicit key.  E.g., "{my-key}http://...".}

  IO::Path:D :@names = Array[IO::Path:D](<.>.IO),
#={Add to the list of names files.
    See the NAMES FILES section for details.
    The file name "." means the default names file.}

  IO::Path:D :@nouns = Array[IO::Path:D](<.>.IO),
#={Add to the list of nouns files.
    See the NOUNS FILES section for details.
    The file name "." means the default nouns file.}

# TODO: reorder
#|{
 ----------------
;OPERATING MODES
;----------------
;}

  Bool:D :$init = False,
#={Create the default names and nouns files.}

  Bool:D :$debug = False,
#={Print debug data}

  Bool:D :$scrape = True,
#={Scrape the BibTeX entry from the publisher's page}

  Bool:D :$fix = True,
#={Fix common BibTeX mistakes}

  Bool:D :$show-window = False,
#={Show the browser window while scraping.  (Usefull for debugging.)}

#|{
 ----------------
;GENERAL OPTIONS
;----------------
;}

  Bool:D :$escape-acronyms = True,
#={In titles, enclose sequences of two or more uppercase letters (i.e.,
    an acronym) in braces so that BibTeX preserves their case.}

  BibScrape::Fix::MediaType:D :$isbn-media = BibScrape::Fix::Both,
#={When both a print and an online ISBN are available:

    ;- if <MediaType> is "Print", use only the print ISBN,
    ;- if <MediaType> is "Online", use only the online ISBN,
    ;- if <MediaType> is "Both", use both the print and the online ISBN
    ;;
    If only one ISBN is available, this option is ignored.}

  BibScrape::Isbn::IsbnType:D :$isbn-type = BibScrape::Isbn::Preserve,
#={- If <IsbnType> is "Isbn13", always convert ISBNs to ISBN-13
    ;- If <IsbnType> is "Isbn10", when possible convert ISBns to ISBN-10
    ;- If <IsbnType> is "Preserve", do not convert ISBNs.}

  Str:D :$isbn-sep = '-',
#={The string to separate parts of an ISBN.
    Hyphen and space are the most common.
    Use an empty string to specify no separator.}

# TODO: reorder (before all ISBN)
  BibScrape::Fix::MediaType:D :$issn-media = BibScrape::Fix::Both,
#={When both a print and an online ISSN are available:

    ;- if <MediaType> is "Print", use only the print ISSN,
    ;- if <MediaType> is "Online", use only the online ISSN,
    ;- if <MediaType> is "Both", use both the print and the online ISSN
    ;;
    If only one ISSN is available, this option is ignored.}

#|{
;----------------
;FIELD OPTIONS
;----------------
;}

  Str:D :@field = Array[Str:D](
    <author editor affiliation title
    howpublished booktitle journal volume number series jstor_issuetitle
    type jstor_articletype school institution location conference_date
    chapter pages articleno numpages
    edition day month year issue_date jstor_formatteddate
    organization publisher address
    language isbn issn doi eid acmid url eprint bib_scrape_url
    note annote keywords abstract copyright>),
#={Known BibTeX fields in the order that they should appear in the output}

  Str:D :@no-encode = Array[Str:D](<doi url eprint bib_scrape_url>),
#={Fields that should not be LaTeX encoded}

  Str:D :@no-collapse = Array[Str:D](< >),
#={Fields that should not have their whitespace collapsed}

  Str:D :@omit = Array[Str:D](< >),
#={Fields that should be omitted from the output}

  Str:D :@omit-empty = Array[Str:D](<abstract issn doi keywords>),
#={Fields that should be omitted from the output if they are empty}

--> Any:U
) is export {
  my IO::Path:D $config-dir =
    ($*DISTRO.is-win
      ?? %*ENV<APPDATA> // %*ENV<USERPROFILE> ~ </AppData/Roaming/>
      !! %*ENV<XDG_CONFIG_HOME> // %*ENV<HOME> ~ </.config>).IO
      .add(<BibScrape>);
  my IO::Path:D $default-names = $config-dir.add('names.cfg');
  my IO::Path:D $default-nouns = $config-dir.add('nouns.cfg');

  if $init {
    $config-dir.mkdir;
    %?RESOURCES<names.cfg>.copy($default-names);
    %?RESOURCES<nouns.cfg>.copy($default-nouns);
  }

  sub default-file(Str:D $type, IO::Path:D $file) { # TODO: return type
    sub (IO::Path:D $x --> IO::Path:D) {
      if $x ne '.' {
        $x
      } else {
        if !$file.IO.e { die "$type file does not exist: $file; bibscrape with --init to automatically create it"; }
        $file
      }
    }
  }
  @names = @names.map(default-file('Names', $default-names));
  @nouns = @nouns.map(default-file('Nouns', $default-nouns));

  my BibScrape::Fix::Fix:D $fixer = BibScrape::Fix::Fix.new(
    names-files => @names,
    nouns-files => @nouns,
    debug => $debug,
    scrape => $scrape,
    fix => $fix,
    escape-acronyms => $escape-acronyms,
    isbn-media => $isbn-media,
    isbn-type => $isbn-type,
    isbn-sep => $isbn-sep,
    issn-media => $issn-media,
    field => @field,
    no-encode => @no-encode,
    no-collapse => @no-collapse,
    omit => @omit,
    omit-empty => @omit-empty,
  );

  my Regex:D $url-rx = rx:i/^ [ \s* '{' (<-[}]>*) '}' \s* ]? (['http' 's'? | 'doi'] ':' .*) $/;

  for @url -> Str:D $arg {
    sub go(Str $key is copy, Str:D $url is copy --> Any:U) {
      $url ~~ $url-rx;
      $key = $0.Str
        if !$key.defined and $0.defined;

      my BibScrape::BibTeX::Entry:D $entry = scrape($1.Str, show-window => $show-window);
      $entry.fields<bib_scrape_url> = BibScrape::BibTeX::Value.new($url);

      $entry = $fixer.fix($entry);

      $entry.key = $key
        if $key.defined;

      print $entry.Str;

      return;
    }

    # Look for 'http:', 'https:' or 'doi:' with an optional `{key}` before the url
    if $arg ~~ $url-rx {
      go(Str, $arg);
      print "\n"; # BibTeX::Entry.Str doesn't have a newline at the end so we add one
    } else {
      my BibScrape::BibTeX::Database:D $bibtex = bibtex-parse($arg.IO.slurp);
      for $bibtex.items -> BibScrape::BibTeX::Item:D $item {
        if $item !~~ BibScrape::BibTeX::Entry:D {
          print $item.Str;
        } else {
          if $item.fields<bib_scrape_url> {
            go($item.key, $item.fields<bib_scrape_url>.simple-str);
          } elsif $item.fields<doi> {
            my Str:D $doi = $item.fields<doi>.simple-str;
            $doi = "doi:$doi"
              unless $doi ~~ m:i/^ 'doi:' /;
            go($item.key, $doi);
          } else {
            print $item.Str
          }
        }
      }
    }
  }
  return;
}
