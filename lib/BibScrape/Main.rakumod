unit module BibScrape::Main;

use variables :D;

use HTML::Entity;

use BibScrape::BibTeX;
use BibScrape::CommandLine;
use BibScrape::Fix;
use BibScrape::Isbn;
use BibScrape::Scrape;
use BibScrape::Unicode;

#|{;;
Collect BibTeX entries from the websites of academic publishers.
;;
See https://github.com/adamsmd/BibScrape/README.md for more details.
;}
sub MAIN(
#={
 ------------------------
;BOOLEAN FLAGS
;------------------------
;
;Use --flag, --flag=true, --flag=yes, --flag=y, --flag=on or --flag=1
;to set a boolean flag to True.
;
;Use --/flag, --flag=false, --flag=no, --flag=n, --flag=off or --flag=0
;to set a boolean flag to False.
;
;Arguments to boolean flags (e.g., 'true', 'yes', etc.) are case insensitive.
;
;------------------------
;LIST FLAGS
;------------------------
;
;Use --flag=<value> to add a value to a list flag.
;
;Use --/flag=<value> to remove a value from a list flag.
;
;Use --flag= to set a list flag to an empty list.
;
;Use --/flag= to set a list flag to its default list.
;
;------------------------
;NAMES
;------------------------
;;
BibScrape warns the user about author and editor names that publishers often get
wrong.  For example, some publisher assume the last name of Simon Peyton Jones
is "Jones" when it should be "Peyton Jones", and some publishers put author
names in all upper case (e.g., "CONNOR MCBRIDE").
;;
We call these names "possibly incorrect", not because they are wrong but because
the user should double check them.
;;
The only names we do not consider possibly incorrect are those in the names
files (see the NAMES FILE section) or those that consist of a first name,
optional middle initial and last name in any of the following formats:
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
; - Xxxx-Xxxx
; - d'Xxxx
; - D'Xxxx
; - deXxxx
; - DeXxxx
; - DiXxxx
; - DuXxxx
; - LaXxxx
; - LeXxxx
; - MacXxxx
; - McXxxx
; - O'Xxxx
; - VanXxxx
;;
This collection of name formats was chosen based the list of all authors in
DBLP and tries to strike a ballance between names that publishers are unlikely
to get wrong and prompting the user about too many names.
;
;------------------------
;NAMES FILES
;------------------------
;;
Names files specify the correct form for author names.
;;
Names files are plain text in Unicode format.
Anything after # (hash) is a comment.
Blank or whitespace-only lines separate blocks, and
blocks consist of one or more lines.
The first line in a block is the canonical/correct form for a name.
Lines other than the first one are aliases that should be converted to the
canonical form.
;;
When searching for a name, case distinctions and divisions of the name into
parts (e.g., first versus last name) are ignored as publishers often get these
wrong (e.g., "Van Noort" will match "van Noort" and "Jones, Simon Peyton" will
match "Peyton Jones, Simon").
;;
The default names file provides several examples with comments and recommended
practices.
;
;------------------------
;NOUNS FILES
;------------------------
;;
Nouns files specify words in titles that should be wrapped in curly braces so
that BibTeX does not convert them to lowercase.
;;
Nouns files are plain text in Unicode format.
Anything after # (hash) is a comment.
Blank or whitespace-only lines separate blocks, and
blocks consist of one or more lines.
The first line in a block is the canonical/correct form for a noun.
Typically, this first line includes curly braces,
which tell BibTeX to not change the capitalization the text wrapped by the curly braces.
Lines other than the first one are aliases that should be converted to the canonical form.
;;
Lines (including the first line) match both with and without the curly braces in them.
Matching is case sensitive.
;;
The default nouns file provides several examples with comments and recommended
practices.
;
;------------------------
;STOP-WORDS FILES
;------------------------
;;
TODO
}

  #|{
   ------------------------
  ;INPUTS
  ;------------------------
  ;}

  Str:D @arg,
  #={The publisher's pages to be scraped or a BibTeX files to be read and
    re-scraped or fixed.
    ;
    ;- If an <arg> starts with 'http:' or 'https:', it is interpreted as a URL.
    ;- If an <arg> starts with 'doi:', it is interpreted as a DOI.
    ;- If an <arg> is '-', BibTeX entries are read from standard input.
    ;- Otherwise, an <arg> is a filename from which BibTeX entries are read.}

  Str:D :k(:@key) = Array[Str:D](< >) but Sep[','],
  #={Keys to use in the output BibTeX.
    ;;
    Successive keys are used for successive BibTeX entries.
    ;;
    If omitted or an empty string, the key will be copied from the existing
    BibTeX entry or automatically generated if there is no existing BibTeX
    entry.}

  IO::Path:D :@names = Array[IO::Path:D](<.>.IO) but Sep[';'],
  #={The names files to use.
    See the NAMES FILES and LIST FLAGS sections for details.
    The file name "." means "names.cfg" in the user-configuration directory.}

  Str:D :@name = Array[Str:D].new(),
  #={Treat <Str> as if it were the content of a names file.
    See the NAMES FILES section for details about names files.
    Semicolons in <Str> are interpreted as newlines.}

  IO::Path:D :@nouns = Array[IO::Path:D](<.>.IO) but Sep[';'],
  #={The nouns files to use.
    See the NOUNS FILES and LIST FLAGS sections for details.
    The file name "." means "nouns.cfg" in the user-configuration directory.}

  Str:D :@noun = Array[Str:D].new(),
  #={Treat <Str> as if it were the content of a nouns file.
    See the NOUNS FILES section for details about nouns files.
    Semicolons in <Str> are interpreted as newlines.}

  IO::Path:D :@stop-words = Array[IO::Path:D](<.>.IO) but Sep[';'],
  #={The nouns files to use.
    See the STOP-WORDS FILES and LIST FLAGS sections for details.
    The file name "." means "stop-words.cfg" in the user-configuration directory.}

  Str:D :@stop-word = Array[Str:D].new(),
  #={Treat <Str> as if it were the content of a stop-words file.
    See the STOP-WORDS FILES section for details about stop-words files.
    Semicolons in <Str> are interpreted as newlines.}

  #|{
   ------------------------
  ;OPERATING MODES
  ;------------------------
  ;}

  Bool:D :$init = False,
  #={Create default names and nouns files in the user-configuration directory.}

  Bool:D :$config-dir = False,
  #={Print the location of the user-configuration directory.}

  Bool:D :S(:$scrape) = True,
  #={Scrape BibTeX entries from publisher's pages.}

  Bool:D :F(:$fix) = True,
  #={Fix mistakes found in BibTeX entries.}

  #|{
   ------------------------
  ;GENERAL OPTIONS
  ;------------------------
  ;}

  Bool:D :w(:$window) = False,
  #={Show the browser window while scraping.  This is useful for debugging or
    determining why BibScrape hangs on a particular publisher's page.}

  Num:D :t(:$timeout) = 60.Num,
  #={Browser timeout in seconds for individual page loads.}

  Bool:D :$escape-acronyms = True,
  #={In BibTeX titles, enclose detected acronyms (e.g., sequences of two or more
  uppercase letters) in braces so that BibTeX preserves their case.}

  BibScrape::Fix::MediaType:D :$issn-media = BibScrape::Fix::both,
  #={Whether to use print or online ISSNs.
    ;
    ;- If <MediaType> is "print", use only the print ISSN.
    ;- If <MediaType> is "online", use only the online ISSN.
    ;- If <MediaType> is "both", use both the print and online ISSNs.
    ;;
    If only one type of ISSN is available, this option is ignored.}

  BibScrape::Fix::MediaType:D :$isbn-media = BibScrape::Fix::both,
  #={Whether to use print or online ISBNs.
    ;
    ;- If <MediaType> is "print", use only the print ISBN.
    ;- If <MediaType> is "online", use only the online ISBN.
    ;- If <MediaType> is "both", use both the print and online ISBNs.
    ;;
    If only one type of ISBN is available, this option is ignored.}

  BibScrape::Isbn::IsbnType:D :$isbn-type = BibScrape::Isbn::preserve,
  #={Whether to convert ISBNs to ISBN-13 or ISBN-10.
    ;
    ;- If <IsbnType> is "isbn13", always convert ISBNs to ISBN-13.
    ;- If <IsbnType> is "isbn10", convert ISBNs to ISBN-10 but only if possible.
    ;- If <IsbnType> is "preserve", do not convert ISBNs.}

  Str:D :$isbn-sep = '-',
  #={The string to separate parts of an ISBN.
    Hyphen and space are the most common.
    Use an empty string to specify no separator.}

  # Haven't found any use for this yes, but leaving it here in case we ever do
  #  Bool:D :v(:$verbose) = False,
  ##={Print verbose output.}

  Bool:D :V(:$version) = False,
  #={Print version information.}

  Bool:D :h(:$help) = False,
  #={Print this usage message.}

  #|{
   ------------------------
  ;BIBTEX FIELD OPTIONS
  ;------------------------
  ;}

  Str:D :f(:@field) = Array[Str:D](<
    key author editor affiliation title
    howpublished booktitle journal volume number series
    type school institution location conference_date
    chapter pages articleno numpages
    edition day month year issue_date
    organization publisher address
    language isbn issn doi url eprint archiveprefix primaryclass
    bib_scrape_url
    note annote keywords abstract>)
    but Sep[','],
  #={The order that fields should placed in the output.}

  Str:D :@no-encode = Array[Str:D](<doi url eprint bib_scrape_url>) but Sep[','],
  #={Fields that should not be LaTeX encoded.}

  Str:D :@no-collapse = Array[Str:D](< >) but Sep[','],
  #={Fields that should not have multiple successive whitespaces collapsed into a
  single whitespace.}

  Str:D :o(:@omit) = Array[Str:D](< >) but Sep[','],
  #={Fields that should be omitted from the output.}

  Str:D :@omit-empty = Array[Str:D](<abstract issn doi keywords>) but Sep[','],
  #={Fields that should be omitted from the output if they are empty.}

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
  my Str:D constant $stop-words-filename = 'stop-words.cfg';

  if $config-dir {
    say "User-configuration directory: $config-dir-path";
  }

  if $init {
    $config-dir-path.mkdir;
    for ($names-filename, $nouns-filename, $stop-words-filename) -> Str:D $src {
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
  @stop-words = @stop-words.map(default-file('Stop-words', $stop-words-filename));

  my BibScrape::Fix::Fix:D $fixer = BibScrape::Fix::Fix.new(
    :@names,
    :@name,
    :@nouns,
    :@noun,
    :@stop-words,
    :@stop-word,
    :$scrape,
    :$fix,
    :$escape-acronyms,
    :$issn-media,
    :$isbn-media,
    :$isbn-type,
    :$isbn-sep,
    # :$verbose,
    :@field,
    :@no-encode,
    :@no-collapse,
    :@omit,
    :@omit-empty,
  );

  for @arg -> Str:D $arg {
    sub scr(Str:D $url --> BibScrape::BibTeX::Entry:D) {
      scrape($url, :$window, :$timeout);
    }
    sub fix(Str:D $key, BibScrape::BibTeX::Entry:D $entry is copy --> Any:U) {
      if $fix { $entry = $fixer.fix($entry) }
      if $key { $entry.key = $key }
      print $entry.Str;
      return;
    }

    if $arg ~~ m:i/^ 'http:' | 'https:' | 'doi:' / {
      # It's a URL
      if !$scrape { die "Scraping disabled but given URL: $arg"; }
      fix(@key.shift || '', scr($arg));
      print "\n"; # BibTeX::Entry.Str doesn't have a newline at the end so we add one
    } else {
      # Not a URL so try reading it as a file
      my Str:D $str = ($arg eq '-' ?? $*IN !! $arg.IO).slurp;
      my BibScrape::BibTeX::Database:D $bibtex = bibtex-parse($str);
      ITEM: for $bibtex.items -> BibScrape::BibTeX::Item:D $item {
        if $item !~~ BibScrape::BibTeX::Entry:D {
          print $item.Str;
        } else {
          my $key = @key.shift || $item.key;
          if !$scrape {
            # Undo any encoding that could get double encoded
            update($item, 'abstract', { s:g/ \s* "\{\\par}" \s* /\n\n/; }); # Must be before tex2unicode
            for $item.fields.keys -> Str:D $field {
              unless $field ∈ @no-encode {
                update($item, $field, { $_ = tex2unicode($_) });
                update($item, $field, { $_ = encode-entities($_); s:g/ '&#' (\d+) ';'/{$0.chr}/; });
              }
            }
            update($item, 'title', { s:g/ '{' (\d* [<upper> \d*] ** 2..*) '}' /$0/ });
            update($item, 'series', { s:g/ '~' / / });
            fix($key, $item);
          } elsif $item.fields<bib_scrape_url> {
            fix($key, scr($item.fields<bib_scrape_url>.simple-str));
          } elsif $item.fields<doi> {
            my Str:D $doi = $item.fields<doi>.simple-str;
            $doi = "doi:$doi"
              unless $doi ~~ m:i/^ 'doi:' /;
            fix($key, scr($doi));
          } else {
            for <url howpublished> -> Str:D $field {
              next unless $item.fields{$field}:exists;
              my Str:D $value = $item.fields{$field}.simple-str;
              if $value ~~ m:i/^ 'doi:' | 'http' 's'? '://' 'dx.'? 'doi.org/' / {
                fix($key, scr($value));
                next ITEM;
              }
            }

            say "WARNING: Not changing entry '{$item.key}' because could not find publisher URL";
            print $item.Str;
          }
        }
      }
    }
  }
  return;
}
