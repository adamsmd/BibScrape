unit module BibScrape::Main;

use BibScrape::BibTeX;
use BibScrape::CommandLine;
use BibScrape::Fix;
use BibScrape::Isbn;
use BibScrape::Scrape;

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
;Use --flag, --flag=true, --flag=yes, --flag=y, --flag=on or --flag=1
;to set a boolean flag to True.
;
;Use --/flag, --flag=false, --flag=no, --flag=n, --flag=off or --flag=0
;to set a boolean flag to False.
;
;----------------
;LIST FLAGS
;----------------
;
;Use --flag=<value> to add a value to a list flag.
;
;Use --/flag=<value> to remove a value from a list flag.
;
;Use --flag= to set a list flag to an empty list.
;
;Use --/flag= to set a list flag to its default list.
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
parts (e.g., first vs last name) are ignored as publishers often get these
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
    ;- Otherwise, it is interpreted as a filename.}

  Str:D :k(:@key),
#={Specify the keys to use in the output BibTeX.
    ;;
    Successive keys are used for succesive BibTeX entries.
    ;;
    If omitted or a single space, the key will be automatically generated or
    copied from the existing BibTeX entry.}

  IO::Path:D :@names = Array[IO::Path:D](<.>.IO),
#={Add to the list of names files.
    See the NAMES FILES section for details.
    The file name "." means "names.cfg" in the user-configuration directory.}

  IO::Path:D :@nouns = Array[IO::Path:D](<.>.IO),
#={Add to the list of nouns files.
    See the NOUNS FILES section for details.
    The file name "." means "nouns.cfg" in the user-configuration directory.}

#|{
 ----------------
;OPERATING MODES
;----------------
;}

  Bool:D :$init = False,
#={Create the default names and nouns files.}

  Bool:D :$config-dir = False,
#={Print the location of the user-configuration directory.}

  Bool:D :S(:$scrape) = True,
#={Scrape the BibTeX entry from the publisher's page}

  Bool:D :F(:$fix) = True,
#={Fix common BibTeX mistakes}

#|{
 ----------------
;GENERAL OPTIONS
;----------------
;}

  Bool:D :w(:$window) = False,
#={Show the browser window while scraping.  (This is usefull for debugging or
    if BibScrape unexpectedly hangs.)}

  Num:D :t(:$timeout) = 30.Num,
  #={Browser timeout in seconds for individual page loads}

  Bool:D :$escape-acronyms = True,
#={In titles, enclose sequences of two or more uppercase letters (i.e.,
    an acronym) in braces so that BibTeX preserves their case.}

  BibScrape::Fix::MediaType:D :$issn-media = BibScrape::Fix::Both,
#={When both a print and an online ISSN are available:
    ;
    ;- if <MediaType> is "Print", use only the print ISSN,
    ;- if <MediaType> is "Online", use only the online ISSN,
    ;- if <MediaType> is "Both", use both the print and the online ISSN
    ;;
    If only one ISSN is available, this option is ignored.}

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

# Haven't found any use for this yes, but leaving it here in case we ever do
#  Bool:D :v(:$verbose) = False,
##={Print verbose output}

  Bool:D :$version = False,
#={Print version information}

  Bool:D :h(:$help) = False,
#={Print this usage message}

#|{
;----------------
;FIELD OPTIONS
;----------------
;}

  Str:D :f(:@field) = Array[Str:D](<
    author editor affiliation title
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

  Str:D :o(:@omit) = Array[Str:D](< >),
#={Fields that should be omitted from the output}

  Str:D :@omit-empty = Array[Str:D](<abstract issn doi keywords>),
#={Fields that should be omitted from the output if they are empty}

--> Any:U
) is export {
  if $version {
    given $?DISTRIBUTION.meta<ver> {
      when '*' {
        my $rev = run(<git rev-parse HEAD>, :out, :cwd($?DISTRIBUTION.prefix)).out.slurp(:close).chomp;
        my $status = run(<git status --short>, :out, :cwd($?DISTRIBUTION.prefix)).out.slurp(:close).chomp;
        if $status eq '' {
          say "BibScrape version git:{$rev}-clean";
        } else {
          $status ~~ s:g/ "\n" /;/;
          say "BibScrape version git:{$rev}-dirty[$status]";
        }
      }
      default {
        say "BibScrape version ", $_.Str;
      }
    }
  }

  my IO::Path:D $config-dir-path =
    ($*DISTRO.is-win
      ?? %*ENV<APPDATA> // %*ENV<USERPROFILE> ~ </AppData/Roaming/>
      !! %*ENV<XDG_CONFIG_HOME> // %*ENV<HOME> ~ </.config>).IO
      .add(<BibScrape>);
  my Str:D constant $names-filename = 'names.cfg';
  my Str:D constant $nouns-filename = 'nouns.cfg';
  my IO::Path:D $default-names = $config-dir-path.add('names.cfg');
  my IO::Path:D $default-nouns = $config-dir-path.add('nouns.cfg');

  if $config-dir {
    say "User-configuration directory: $config-dir-path";
  }

  if $init {
    $config-dir-path.mkdir;
    for ($names-filename, $nouns-filename) -> Str:D $src {
      my IO::Path:D $dst = $config-dir-path.add($src);
      if $dst.e {
        say "Not copying default $src since $dst already exists";
      } else {
        %?RESOURCES{$src}.copy($dst);
        say "Successfully copied default $src to $dst";
      }
    }
  }

  sub default-file(Str:D $type, Str:D $file --> Callable[IO::Path:D]) {
    sub (IO::Path:D $x --> IO::Path:D) {
      if $x ne '.' {
        $x
      } else {
        my IO::Path:D $io = $config-dir-path.add($file);
        if !$io.IO.e {
          die "$type file does not exist: $file.  Invoke bibscrape with --init to automatically create it.";
        }
        $io
      }
    }
  }
  @names = @names.map(default-file('Names', $names-filename));
  @nouns = @nouns.map(default-file('Nouns', $nouns-filename));

  my BibScrape::Fix::Fix:D $fixer = BibScrape::Fix::Fix.new(
    names-files => @names,
    nouns-files => @nouns,
    scrape => $scrape,
    fix => $fix,
    escape-acronyms => $escape-acronyms,
    issn-media => $issn-media,
    isbn-media => $isbn-media,
    isbn-type => $isbn-type,
    isbn-sep => $isbn-sep,
    # verbose => $verbose,
    field => @field,
    no-encode => @no-encode,
    no-collapse => @no-collapse,
    omit => @omit,
    omit-empty => @omit-empty,
  );

  for @url -> Str:D $arg {
    sub go(Str:D $key, Str:D $url --> Any:U) {
      my BibScrape::BibTeX::Entry:D $entry = scrape($url, show-window => $window, browser-timeout => $timeout);
      $entry = $fixer.fix($entry);
      $entry.key = $key
        if $key ne ' ';
      print $entry.Str;
      return;
    }

    if $arg ~~ m:i/^ 'http:' | 'https:' | 'doi:' / {
      # It's a URL
      go(@key.shift // ' ', $arg);
      print "\n"; # BibTeX::Entry.Str doesn't have a newline at the end so we add one
    } else {
      # Not a URL so try reading it as a file
      my Str:D $str = ($arg eq '-' ?? $*IN !! $arg.IO).slurp;
      my BibScrape::BibTeX::Database:D $bibtex = bibtex-parse($str);
      for $bibtex.items -> BibScrape::BibTeX::Item:D $item {
        if $item !~~ BibScrape::BibTeX::Entry:D {
          print $item.Str;
        } else {
          if $item.fields<bib_scrape_url> {
            go(@key.shift // $item.key, $item.fields<bib_scrape_url>.simple-str);
          } elsif $item.fields<doi> {
            my Str:D $doi = $item.fields<doi>.simple-str;
            $doi = "doi:$doi"
              unless $doi ~~ m:i/^ 'doi:' /;
            go(@key.shift // $item.key, $doi);
          } else {
            print $item.Str
          }
        }
      }
    }
  }
  return;
}
