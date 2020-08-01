unit module BibScrape::Main;

use BibScrape::BibTeX;
use BibScrape::Isbn;
use BibScrape::Fix;
use BibScrape::Scrape; # Must be last (See comment in Scrape.rakumod)

my IO::Path:D $config-dir =
  ($*DISTRO.is-win
    ?? %*ENV<APPDATA> // %*ENV<USERPROFILE> ~ </AppData/Roaming/>
    !! %*ENV<XDG_CONFIG_HOME> // %*ENV<HOME> ~ </.config>).IO
    .add(<BibScrape>);
my IO::Path:D $default-names = $config-dir.add('names.cfg');
my IO::Path:D $default-nouns = $config-dir.add('nouns.cfg');

class ParamInfo {
  has Bool:D $.named is required;
  has Str:D $.name is required;
  has Any:U $.type is required;
  has Any:_ $.default is required;
  has Pod::Block::Declarator:_ $.doc is required;
}

sub param-info(Parameter:D $param --> ParamInfo:D) {
  my Str:D $name = ($param.name ~~ /^ "{$param.sigil}{$param.twigil}" (.*) $/).[0].Str;
  my Any:_ $default = $param.default && ($param.default)();
  ParamInfo.new(
    named => $param.named, name => $name, type => $param.type,
    default => $default, doc => $param.WHY);
}

my @param-info;
my %param-info;
my Str @positional;
my $no-parse = False;
# TODO: BEGIN
for &MAIN.signature.params -> Parameter:D $param {
  my ParamInfo:D $param-info = param-info($param);
  if $param.named {
    %param-info{$param-info.name} = $param-info;
  } else {
    push @param-info = $param-info;
  }
}

sub type-name(Any:U $type --> Str:D) {
  given $type {
    when Positional { type-name($type.of); }
    when IO::Path { 'File'; }
    default { $type.^name; }
  }
}

sub GENERATE-USAGE(Sub:D $main, |capture --> Str:D) is export {
  my Int:D constant $end-col = 80;
  my $out = '';
  sub col(Int:D $col --> Any:U) {
    my Int:D $old-col = $out.split("\n")[*-1].chars;
    if $old-col > $col { $out ~= "\n"; $old-col = 0; }
    $out ~= ' ' x ($col - $old-col);
    return;
  }
  sub wrap(Int:D $start, Str:D $str is copy --> Any:U) {
    for $str.split( / ' ' * ';' ' '* / ) -> $paragraph is copy {
      $paragraph ~~ s:g/ ' '+ $//;
      if $paragraph eq '' {
        $out ~= "\n";
      } else {
        for $paragraph ~~ m:g/ (. ** {0..($end-col - $start)}) [ ' '+ | $ ] / -> $line {
          col($start);
          $out ~= $line;
        }
      }
    }
    return;
  }
  $out ~= "Usage:\n";
  $out ~= "  $*PROGRAM-NAME [options]";

  # TODO: %param-info
  for @param-info -> ParamInfo:D $param-info {
    $out ~= " " ~ $param-info.name ~ ($param-info.type ~~ Positional ?? ' ...' !! '');
  }

  wrap(0, $main.WHY.leading);

  for $main.signature.params -> Parameter:D $param {
    my $param-info = param-info($param);
    with $param-info.doc and $param-info.doc.leading {
      wrap(0, $_);
    }
    if $param-info.named {
      $out ~= " --{$param-info.name}";
      given $param-info.type {
        when Bool { }
        when Positional { $out ~= "=<{type-name($param-info.type)}> ..."; }
        default { $out ~= "=<{type-name($param-info.type)}>"; }
      }
    } else {
      given $param-info.type {
        when Positional {
          $out ~= " {$param-info.name} ...";
        }
        default {
          $out ~= " {$param-info.name}";
        }
      }
    }
    # TODO: comma in list keyword flags
    if $param-info.default.defined {
      wrap(28, "Default: {$param-info.default}");
    } else {
      $out ~= "\n";
    }
    $out ~= "\n";
    # if $param-info.type ~~ Enumeration {
    #   wrap(4, "<{type-name($param-info.type)}> = {$param-info.type.enums.keys.join(' | ')};");
    # }
    with $param-info.doc and $param-info.doc.trailing {
      wrap(4, $_);
    }
    $out ~= "\n";
  }
  wrap(0, $main.WHY.trailing);
  $out.chomp;
}

sub ARGS-TO-CAPTURE(Sub:D $main, @args is copy where { $_.all ~~ Str:D }--> Capture:D) is export {

  my Int:D $positionals = 0;
  my Any:_ @param-value; # = @param-info».default;
  my Any:_ %param-value = %param-info.map({ $_.key => $_.value.default });
  while @args {
    my Str:D $arg = shift @args;
    given $arg {
      # Positionals
      when $no-parse | !/^ '--' / {
        my $param = @param-info[$positionals];
        given $param.type {
          when Positional {
            @param-value[$positionals] = Array[$param.type.of].new()
              unless @param-value[$positionals];
            push @param-value[$positionals], ($param.type.of)($arg);
            # NOTE: no `$positionals++`
          }
          default {
            @param-value[$positionals] = ($param.type)($arg);
            $positionals++;
          }
        }
      }
      # --
      when /^ '--' $/ { $no-parse = True; }
      # Keyword
      when /^ '--help' | '-h' | '-?' $/ { %param-value<help> = True; }
      when /^ '--' ('/'?) (<-[=]>+) (['=' (.*)]?) $/ {
        my $polarity = ($0.chars == 0);
        say "==", $polarity;
        my $name = $1.Str;
        # TODO: when $name eq ''
        my $param = %param-info{$name}; # TODO: Missing param name
        my $info = %param-info{$name};
        given $info.type {
          when Positional {
            my Str:D $value-str = $2.[0].Str;
            if $value-str eq '' {
              if $polarity {
                %param-value{$info.name} = Array[$info.type.of].new();
              } else {
                %param-value{$info.name} = $info.default;
              }
            } else {
              # TODO: comma in field options
              my Any:D $value = ($info.type.of)($value-str);
              if $polarity {
                push %param-value{$info.name}, $value;
              } else {
                %param-value{$info.name} =
                  Array[$info.type.of](%param-value{$info.name}.grep({ not ($_ eqv $value) }));
              }
            }
          }
          default {
            my $value =
              $2.chars > 0 ?? $2.[0] !!
                $param.type ~~ Bool ?? $polarity.Str !! # TODO: yes, no
                @args.shift; # TODO: missing arg
            my $value2 = ($info.type)($value);
            %param-value{$info.name} = $value2;
          }
        }
      }
      default {
        die "impossible";
      }
    }
  }
  my $capture = Capture.new(list => @param-value, hash => %param-value);
  $capture;
}

#|{;;
Collect BibTeX entries from the websites of academic publishers.
;;
See the README.md at https://github.com/adamsmd/BibScrape for more details.
;}

sub MAIN(
#={
;----------------
;BOOLEAN FLAGS
;----------------
;
;Use --/flag to set a boolean flag to False.
;;
;----------------
;LIST FLAGS
;----------------
;
;Use --/flag=<value> to remove an element.
;Use --flag= to reset to an empty list.
;Use --/flag= to reset to the default list.
;;
;----------------
;NAMES
;----------------
;;
We warn the user about author and editor names that publishers often get
wrong.  For example, some publisher assume the last name of Simon Peyton Jones
is "Jones" when it should be "Peyton Jones", and some publishers put author
names in all upper case (e.g., "CONNOR MCBRIDE").
;;
We call these names "suspect", not because they are wrong but because the user
should double check them.
;;
The only names we do not consider suspect are the followin formats, which the
publishers are unlikely to get wrong, or ones explicitly listed in the </NAME
FILES>.
;;
First names:
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
Last names:
;
; - Xxxx
; - Xxxx
; - O'Xxxx
; - McXxxx
; - MacXxxx
;;
This collection of name formats was chosen based the list of all authors in
DBLP and tries to strike a ballance between prompting the user about too many
names and missing names that should be reported.
;;
;----------------
;NAME FILES
;----------------
;;
A name file specifies the correct form for author names.
;;
A name file is plain text in Unicode format.
In a name file, any line starting with # is a comment.
Blank or whitespace-only lines separate blocks, and
blocks consist of one or more lines.
The first line is the canonical form of a name.
Lines other than the first one are aliases that should be converted to the
canonical form.
;;
When searching for the canonical form of a name, case distinctions and
the divisions of the name into parts (e.g. first vs last name) are
ignored as publishers often get these wrong (e.g., "Van Noort" will
match "van Noort" and "Jones, Simon Peyton" will match "Peyton Jones,
Simon").
;;
The default name file provides several examples and recommended practices.
;;
;----------------
;NOUN FILES
;----------------
;;
An noun file specifies words that should be protected from lower-casing
by inserting curly braces.
;;
A noun file is plain text in Unicode format.
Each line starting with # is a comment.
Blank lines are ignored.
Each line lists the way that a particular word
should be curly braced.  (Curly braces tell BibTeX to not change the captalization of a particular part of a text.)
Any word that matches but with the curly braces removed is converted to the form listed in the file.
The first line to match in the file wins.}

#|{
;----------------
;INPUTS
;----------------
;}

  Str:D @url,# = Array[Str:D](< >),
#={The url of the publisher's page for the paper to be scraped.
    Standard URL formats such as 'http://...' can be used.
    The non-standard URL format 'doi:...' can also be used.
    May be prefixed with '{key}' in order to specify an explicit key.}

  IO::Path:D :@names = Array[IO::Path:D](<.>.IO),
#={Add <file> to the list of name files used to canonicalize author names.
    If <file> is the empty string, clears the list.
    ;;
    See the L</NAME FILE> section for details on the format of name files.}

  IO::Path:D :@nouns = Array[IO::Path:D](<.>.IO),
#={Add <file> to the list of noun files used to canonicalize fields.
    If <file> is the empty string, clears the list.
    ;;
    See the L</NOUN FILE> section for details on the format of noun files.}

# TODO: reorder
#|{
;----------------
;OPERATING MODES
;----------------
;}

  Bool:D :$init = False,
#={TODO}

  Bool:D :$debug = False,
#={Print debug data}

  Bool:D :$scrape = True,
#={Scrape BibTeX entry from the publisher's page}

  Bool:D :$fix = True,
#={Fix common mistakes in the BibTeX}

  Bool:D :$show-window = False,
#={Show the browser window while scraping}

#|{
;----------------
;GENERAL OPTIONS
;----------------
;}

  Bool:D :$escape-acronyms = True,
#={In titles, enclose sequences of two or more uppercase letters (i.e.,
    an acronym) in braces to that BibTeX preserves their case.}

  BibScrape::Fix::MediaType:D :$isbn-media = BibScrape::Fix::Both,
#={When both a print and an online ISBN are available, use only the print
    ISBN if <kind> is 'print', only the online ISBN if <kind> is 'online',
    or both if <kind> is 'both'.}

  BibScrape::Isbn::IsbnType:D :$isbn-type = BibScrape::Isbn::Preserve,
#={If <mode> is a positive integer, then always use ISBN-13 in the output.
    If negative, then use ISBN-10 when possible.
    If zero, then preserve the original format of an ISBN.}

  Str:D :$isbn-sep = '-',
#={Use <sep> to separate parts of an ISBN.
    For example, a space is common.
    Use an empty string to specify no separator.}

  BibScrape::Fix::MediaType:D :$issn-media = BibScrape::Fix::Both,
#={When both a print and an online ISSN are available, use only the print
    ISSN if <kind> is 'print', only the online ISSN if <kind> is 'online',
    or both if <kind> is 'both'.}

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
#={Add a field to the list of known BibTeX fields.}

  Str:D :@no-encode = Array[Str:D](<doi url eprint bib_scrape_url>),
#={Add a field to the list of fields that should not be LaTeX encoded.
    By default this includes doi, url, eprint, and bib_scrape_url, but if
    this flag is specified on the command line, then only those explicitly
    listed on the command line are included.}

  Str:D :@no-collapse = Array[Str:D](< >),
#={Add a filed to the list of fields that should not have their white space collapsed.}

  Str:D :@omit = Array[Str:D](< >),
#={Omit a particular field from the output.}

  Str:D :@omit-empty = Array[Str:D](<abstract issn doi keywords>),
#={Omit a particular field from the output if it is empty.}

) is export {
  if $init {
    $config-dir.mkdir;
    $*RESOURCE<names.cfg>.copy($default-names);
    $*RESOURCE<nouns.cfg>.copy($default-nouns);
  }

  sub default-file(Str:D $type, IO::Path:D $file) {
    sub (IO::Path:D $x) {
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
    sub go(Str $key is copy, Str:D $url is copy) {
      $url ~~ $url-rx;
      $key = $0.Str
        if !$key.defined and $0.defined;

      my BibScrape::BibTeX::Entry:D $entry = scrape($1.Str, show-window => $show-window);
      $entry.fields<bib_scrape_url> = BibScrape::BibTeX::Value.new($url);

      $entry = $fixer.fix($entry);

      $entry.key = $key
        if $key.defined;

      print $entry.Str;
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
}
