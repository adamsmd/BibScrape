unit module BibScrape::Fix;

use variables :D;

use HTML::Entity;
use Locale::Language;
use XML;

use BibScrape::BibTeX;
use BibScrape::Isbn;
use BibScrape::Month;
use BibScrape::Names;
use BibScrape::Unicode;

enum MediaType <Print Online Both>;

sub check(BibScrape::BibTeX::Entry:D $entry, Str:D $field, Str:D $msg, &check --> Any:U) {
  if ($entry.fields{$field}:exists) {
    my Str:D $value = $entry.fields{$field}.simple-str;
    unless (&check($value)) {
      say "WARNING: $msg: $value";
    }
  }
  return;
}

class Fix {
  ## INPUTS
  has Array:D[Str:D] @.names is required;
  has Array:D[Str:D] @.nouns is required;

  ## OPERATING MODES
  has Bool:D $.scrape is required;
  has Bool:D $.fix is required;

  ## GENERAL OPTIONS
  has Bool:D $.escape-acronyms is required;
  has MediaType:D $.issn-media is required;
  has MediaType:D $.isbn-media is required;
  has BibScrape::Isbn::IsbnType:D $.isbn-type is required;
  has Str:D $.isbn-sep is required;
  # has Bool:D $.verbose is required;

  ## FIELD OPTIONS
  has Str:D @.field is required;
  has Str:D @.no-encode is required;
  has Str:D @.no-collapse is required;
  has Str:D @.omit is required;
  has Str:D @.omit-empty is required;

  method new(#`(Any:D) *%args --> Fix:D) {
    sub string-blocks(Array:D[Str:D] @blocks, Str:D $blocks --> Any:U) {
      push @blocks, Array[Str:D].new; # Ensure we are starting a new block
      for $blocks.split(rx/ "\r" | "\n" | "\r\n" /) -> Str:D $line is copy {
        $line ~~ s/"#".*//; # Remove comments (which start with `#`)
        $line ~~ s/\s+ $//; # Remove trailing whitespace
        if $line ~~ /^\s*$/ { push @blocks, Array[Str:D].new; } # Start a new block
        else { push @blocks[@blocks.end], $line; } # Add to existing block
      }
      return;
    }
    sub blocks(Str:D $file-field, Str:D $string-field --> Array:D[Array:D[Str:D]]) {
      my Array:D[Str:D] @blocks;
      for %args{$string-field} -> Str:D $string is copy {
        $string ~~ s:g/ ';' /\n/;
        string-blocks(@blocks, $string);
      }
      for %args{$file-field} -> IO::Path:D $file {
        string-blocks(@blocks, $file.slurp);
      }
      @blocks = @blocks.grep({ .elems > 0 }); # Remove empty blocks
      @blocks.Array;
    }
    my Array:D[Str:D] @names = blocks(<names-files>, <names-strings>);
    my Array:D[Str:D] @nouns = blocks(<nouns-files>, <nouns-strings>);

    self.bless(names => @names, nouns => @nouns, |%args);
  }

  method fix(BibScrape::BibTeX::Entry:D $entry is copy --> BibScrape::BibTeX::Entry:D) {
    $entry = $entry.clone;

    ################################
    # Pre-omit fixes               #
    ################################

    # Doi field: remove "http://hostname/" or "DOI: "
    if not $entry.fields<doi>:exists
        and ($entry.fields<url> // "") ~~ /^ "http" "s"? "://" "dx."? "doi.org/"/ {
      $entry.fields<doi> = $entry.fields<url>;
      $entry.fields<url>:delete;
    }

    # Fix wrong field names (SpringerLink and ACM violate this)
    for ('issue', 'number', 'keyword', 'keywords') -> Str:D $key, Str:D $value {
      if $entry.fields{$key}:exists and
          (not $entry.fields{$value}:exists or
            $entry.fields{$key} eq $entry.fields{$value}) {
        $entry.fields{$value} = $entry.fields{$key};
        $entry.fields{$key}:delete;
      }
    }

    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', { $_ = Str if $_ eq ($entry.fields<doi> // '') });

    ################################
    # Post-omit fixes              #
    ################################

    # Omit fields we don't want.  Should be first after inter-field fixes.
    $entry.fields{$_}:exists and $entry.fields{$_}:delete for @.omit;

    update($entry, 'doi', { s:i:g/"http" "s"? "://" <-[/]>+ "/"//; s:i:g/"DOI:"\s*//; });

    # Page numbers: no "pp." or "p."
    update($entry, 'pages', { s:i:g/"p" "p"? "." \s*//; });

    # Ranges: convert "-" to "--"
    for ('chapter', 'month', 'number', 'pages', 'volume', 'year') -> Str:D $key {
      my Str:D $dash = # Don't use en-dash in techreport numbers
        $entry.type eq 'techreport' && $_ eq 'number'
        ?? '-' !! '--';
      update($entry, $key, { s:i:g/ \s* [ '-' | \c[EN DASH] | \c[EM DASH] ]+ \s* /$dash/; });
      update($entry, $key, { s:i:g/ 'n/a--n/a' //; $_ = Str if !$_ });
      update($entry, $key, { s:i:g/ «(\w+) '--' $0» /$0/; });
      update($entry, $key, { s:i:g/ (^ | ' ') (\w+) '--' (\w+) '--' (\w+) '--' (\w+) ($ | ',')/$0$1-$2--$3-$4$5/ });
      update($entry, $key, { s:i:g/ \s+ ',' \s+/, /; });
    }

    check($entry, 'pages', 'Possibly incorrect page number', {
      my Regex:D $page = rx[
        # Simple digits
        \d+ |
        \d+ "--" \d+ |

        # Roman digits
        <[XVIxvi]>+ |
        <[XVIxvi]>+ "--" <[XVIxvi]>+ |
        # Roman digits dash digits
        <[XVIxvi]>+ "-" \d+ |
        <[XVIxvi]>+ "-" \d+ "--" <[XVIxvi]>+ "-" \d+ |

        # Digits plus letter
        \d+ <[a..z]> |
        \d+ <[a..z]> "--" \d+ <[a..z]> |
        # Digits sep Digits
        \d+ <[.:/]> \d+ |
        \d+ (<[.:/]>) \d+ "--" \d+ $0 \d+ |

        # "Front" page
        "f" \d+ |
        "f" \d+ "--" f\d+ |

        # "es" as ending number
        \d+ "--" "es" ];
      /^ $page+ % "," $/;
    });

    check($entry, 'volume', 'Possibly incorrect volume', {
      /^ \d+ $/ || /^ \d+ "-" \d+ $/ || /^ <[A..Z]> "-" \d+ $/ || /^ \d+ "-" <[A..Z]> $/ });

    check($entry, 'number', 'Possibly incorrect number', {
      /^ \d+ $/ || /^ \d+ "--" \d+ $/ || /^ [\d+]+ % "/" $/ || /^ \d+ "es" $/ ||
      /^ "Special Issue " \d+ ["--" \d+]? $/ || /^ "S" \d+ $/ ||
      # PACMPL uses conference abbreviations (e.g., ICFP)
      /^ <[A..Z]>+ $/ });

    self.isbn($entry, 'issn', $.issn-media, &canonical-issn);

    self.isbn($entry, 'isbn', $.isbn-media, &canonical-isbn);

    # Change language codes (e.g., "en") to proper terms (e.g., "English")
    update($entry, 'language', { $_ = code2language($_) if code2language($_).defined });

    if ($entry.fields<author>:exists) { $entry.fields<author> = $.canonical-names($entry.fields<author>) }
    if ($entry.fields<editor>:exists) { $entry.fields<editor> = $.canonical-names($entry.fields<editor>) }

    # Don't include pointless URLs to publisher's page
    update($entry, 'url', {
      $_ = Str if m/^
        [ 'http' 's'? '://doi.acm.org/'
        | 'http' 's'? '://doi.ieeecomputersociety.org/'
        | 'http' 's'? '://doi.org/'
        | 'http' 's'? '://dx.doi.org/'
        | 'http' 's'? '://portal.acm.org/citation.cfm'
        | 'http' 's'? '://www.jstor.org/stable/'
        | 'http' 's'? '://www.sciencedirect.com/science/article/' ]/; });

    # Keep proper nouns capitalized
    update($entry, 'title', {
      for @.nouns -> Str:D @noun-group {
        for @noun-group -> Str:D $noun {
          my Str:D $noun2 = $noun.subst(rx/ <[{}]> /, '', :g);
          s:g/ « [$noun | $noun2] » /{@noun-group.head}/;
        }
      }

      for @.nouns -> Str:D @noun-group {
        for @noun-group -> Str:D $noun {
          my Str:D $noun2 = $noun.subst(rx/ <[{}]> /, '', :g);
          for m:i:g/ « [$noun | $noun2] » / {
            if $/ ne @noun-group.head {
              say "WARNING: Possibly incorrectly capitalized noun '$/' in title";
            }
          }
        }
      }
    });

    # Keep acronyms capitalized.
    # We intentionally do not use <upper> as Unicode encoding will catch those.
    update($entry, 'title', { s:g/ (\d* [<[A..Z]> \d*] ** 2..*) /\{$0\}/; })
      if $.escape-acronyms;

    # Year
    check($entry, 'year', 'Possibly incorrect year', { /^ \d\d\d\d $/ });

    # Eliminate Unicode but not for no-encode fields (e.g. doi, url, etc.)
    for $entry.fields.keys -> Str:D $field {
      unless $field ∈ @.no-encode {
        update($entry, $field, {
          $_ = rec(from-xml("<root>{$_}</root>").root.nodes);
          s:g/" "* \xA0/\xA0/; # Trim spaces before NBSP (otherwise they have no effect in LaTeX)
          $_ = unicode2tex($_, ignore => rx/<[_^{}\\\$]>/); # NOTE: Ignores LaTeX introduced by translation from XML
        });
      }
    }

    ################################
    # Post-Unicode fixes           #
    ################################

    # Canonicalize series: PEPM'97 -> PEPM~'97.  After Unicode encoding so "'" doesn't get encoded.
    update($entry, 'series', { s:g/(<upper>+) " "* [ "'" | '{\\textquoteright}' ] (\d+)/$0~'$1/; });

    # Collapse spaces and newlines.  After Unicode encoding so stuff from XML is caught.
    for $entry.fields.pairs -> Pair:D $pair {
      unless $pair.key ∈ $.no-collapse {
        update($entry, $pair.key, {
          s/ \s* $//; # remove trailing whitespace
          s/^ \s* //; # remove leading whitespace
          s:g/ (\n ' '*) ** 2..* /\{\\par}/; # BibTeX eats whitespace so convert "\n\n" to paragraph break
          s:g/ \s* \n \s* / /; # Remove extra line breaks
          s:g/ [\s | '{~}']* \s [\s | '{~}']* / /; # Remove duplicate whitespace
          s:g/ \s* "\{\\par\}" \s* /\n\{\\par\}\n/; # Nicely format paragraph breaks
          #s:g/ [\s | '{~}']+ \s [\s | '{~}']* / /; # Remove duplicate whitespace
        });
      }
    }

    # Use bibtex month macros.  After Unicode encoding because it uses macros.
    update($entry, 'month', {
      s/ "." ($|"-") /$0/; # Remove dots due to abbriviations
      my BibScrape::BibTeX::Piece:D @x =
        .split(rx/<wb>/)
        .grep(rx/./)
        .map({
          $_ eq ( '/' | '-' | '--' ) and BibScrape::BibTeX::Piece.new($_) or
          str2month($_) or
          /^ \d+ $/ and num2month($_) or
          say "WARNING: Possibly incorrect month: $_" and BibScrape::BibTeX::Piece.new($_)});
      $_ = BibScrape::BibTeX::Value.new(@x)});

    ################################
    # Final fixes                  #
    ################################

    # Omit empty fields we don't want
    for @.omit-empty {
      if $entry.fields{$_}:exists {
        my Str:D $str = $entry.fields{$_}.Str;
        if $str eq ( '{}' | '""' | '' ) {
          $entry.fields{$_}:delete;
        }
      }
    }

    # Generate an entry key
    my BibScrape::BibTeX::Value:_ $name-value =
      $entry.fields<author> // $entry.fields<editor> // BibScrape::BibTeX::Value;
    my Str:D $name = $name-value.defined ?? last-name(split-names($name-value.simple-str).head) !! 'anon';
    $name ~~ s:g/ '\\' <-[{}\\]>+ '{' /\{/; # Remove codes that add accents
    $name ~~ s:g/ <-[A..Za..z0..9]> //; # Remove non-alphanum
    my Str:D $year = $entry.fields<year>:exists ?? ":" ~ $entry.fields<year>.simple-str !! "";
    my Str:D $doi = $entry.fields<doi>:exists ?? ":" ~ $entry.fields<doi>.simple-str !! "";
    $entry.key = $name ~ $year ~ $doi;

    # Put fields in a standard order (also cleans out any fields we deleted)
    my Int:D %fields = @.field.map(* => 0);
    for $entry.fields.keys -> Str:D $field {
      unless %fields{$field}:exists { die "Unknown field '$field'" }
      unless %fields{$field}.elems == 1 { die "Duplicate field '$field'" }
      %fields{$field} = 1;
    }
    $entry.set-fields(@.field.flatmap({ $entry.fields{$_}:exists ?? ($_ => $entry.fields{$_}) !! () }));

    $entry;
  }

  method isbn(BibScrape::BibTeX::Entry:D $entry, Str:D $field, MediaType:D $print_or_online, &canonical --> Any:U) {
    update($entry, $field, {
      if m/^$/ {
        $_ = Str
      } elsif m:i/^ (<[0..9x\-\ ]>+) " (Print) " (<[0..9x\-\ ]>+) " (Online)" $/ {
        if $print_or_online eqv Print {
          $_ = &canonical($0.Str, $.isbn-type, $.isbn-sep);
        }
        if $print_or_online eqv Online {
          $_ = &canonical($1.Str, $.isbn-type, $.isbn-sep);
        }
        if $print_or_online eqv Both {
          $_ = &canonical($0.Str, $.isbn-type, $.isbn-sep)
            ~ ' (Print) '
            ~ &canonical($1.Str, $.isbn-type, $.isbn-sep)
            ~ ' (Online)';
        }
      } else {
        $_ = &canonical($_, $.isbn-type, $.isbn-sep);
      }
    });
  }

  method canonical-names(BibScrape::BibTeX::Value:D $value --> BibScrape::BibTeX::Value:D) {
    my Str:D @names = split-names($value.simple-str);

    my Str:D @new-names;
    NAME:
    for @names -> Str:D $name {
      my Str:D $flattened-name = flatten-name($name);
      for @.names -> Str:D @name-group {
        for @name-group -> Str:D $n {
          if $flattened-name.fc eq flatten-name($n).fc {
            push @new-names, @name-group.head.Str;
            next NAME;
          }
        }
      }

      my Regex:D $first = rx/
          <upper><lower>+                     # Simple name
        | <upper><lower>+ '-' <upper><lower>+ # Hyphenated name with upper
        | <upper><lower>+ '-' <lower><lower>+ # Hyphenated name with lower
        | <upper><lower>+     <upper><lower>+ # "Asian" name (e.g. XiaoLin)
        # We could allow the following but publishers often abriviate
        # names when the actual paper doesn't
        # | <upper> '.'                       # Initial
        # | <upper> '.-' <upper> '.'          # Double initial
        /;
      my Regex:D $middle = rx/<upper>\./; # Allow for a middle initial
      my Regex:D $last = rx/
          <upper><lower>+                     # Simple name
        | <upper><lower>+ '-' <upper><lower>+ # Hyphenated name with upper
        | ["d'"|"D'"|"de"|"De"|"Di"|"Du"|"La"|"Le"|"Mac"|"Mc"|"O'"|"Van"]
          <upper><lower>+                     # Name with prefix
        /;
      unless $flattened-name ~~ /^ \s* $first \s+ [$middle \s+]? $last \s* $/ {
        say "WARNING: Possibly incorrect name: {order-name($name)}"
      }

      push @new-names, order-name($name);
    }

    # Warn about duplicate names
    my Int:D %seen;
    %seen{$_}++ and say "WARNING: Duplicate name: $_" for @new-names;

    BibScrape::BibTeX::Value.new(@new-names.join( ' and ' ));
  }

}

sub greek(Str:D $str is copy --> Str:D) {
  # Based on table 131 in the Comprehensive Latex Symbol List
  my Str:D @mapping = <
_ A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi O
\Pi P _ \Sigma T \Upsilon \Phi X \Psi \Omega _ _ _ _ _ _
_ \alpha \beta \gamma \delta \varepsilon \zeta \eta \theta \iota \kappa \mu \nu \xi o
\pi \rho \varsigma \sigma \tau \upsilon \varphi \xi \psi \omega _ _ _ _ _ _>;
  $str ~~ s:g/ (<[\x[0390]..\x[03cf]]>) /{ @mapping[ord($0)-0x0390] ne '_' ?? @mapping[ord($0)-0x0390] !! $0}/;
  return $str;
}

sub math(@nodes where { $_.all ~~ XML::Node:D } --> Str:D) { @nodes.map({math-node($_)}).join }

sub math-node(XML::Node:D $node --> Str:D) {
  given $node {
    when XML::CDATA { $node.data }
    when XML::Comment { '' } # Remove HTML Comments
    when XML::Document { math($node.root) }
    when XML::PI { '' }
    when XML::Text { greek(decode-entities($node.text)) }
    when XML::Element {
      given $node.name {
        when 'mtext' { math($node.nodes) }
        when 'mi' {
          ($node.attribs<mathvariant> // '') eq 'normal'
            ?? '\mathrm{' ~ math($node.nodes) ~ '}'
            !! math($node.nodes)
        }
        when 'mo' { math($node.nodes) }
        when 'mn' { math($node.nodes) }
        when 'msqrt' { '\sqrt{' ~ math($node.nodes) ~ '}' }
        when 'mrow' { '{' ~ math($node.nodes) ~ '}' }
        when 'mspace' { '\hspace{' ~ $node.attribs<width> ~ '}' }
        when 'msubsup' { '{' ~ math-node($node.nodes[0]) ~ '}_{' ~ math-node($node.nodes[1]) ~ '}^{' ~ math-node($node.nodes[2]) ~ '}' }
        when 'msub' { '{' ~ math-node($node.nodes[0]) ~ '}_{' ~ math-node($node.nodes[1]) ~ '}' }
        when 'msup' { '{' ~ math-node($node.nodes[0]) ~ '}^{' ~ math-node($node.nodes[1]) ~ '}' }
        default { say "WARNING: Unknown HTML tag: {$node.name}"; "[{$node.name}]" ~ rec($node.nodes) ~ "[/{$node.name}]" }
      }
    }

    default { die "Unknown XML node type '{$node.^name}': $node" }
  }
}

sub rec(@nodes where { $_.all ~~ XML::Node:D } --> Str:D) { @nodes.map({rec-node($_)}).join }

sub rec-node(XML::Node:D $node --> Str:D) {
  given $node {
    when XML::CDATA { $node.data }
    when XML::Comment { '' } # Remove HTML Comments
    when XML::Document { rec($node.root) }
    when XML::PI { '' }
    when XML::Text { decode-entities($node.text) }

    when XML::Element {
      sub wrap(Str:D $tag --> Str:D) {
        my Str:D $str = rec($node.nodes);
        $str eq '' ?? '' !! "\\$tag\{" ~ $str ~ "\}"
      }
      given $node.name {
        when 'a' and $node.attribs<class>:exists and $node.attribs<class> ~~ / « 'xref-fn' » / { '' } # Omit footnotes added by Oxford when on-campus
        when 'a' { rec($node.nodes) } # Remove <a> links
        when 'p' | 'par' { rec($node.nodes) ~ "\n\n" } # Replace <p> with \n\n
        when 'i' | 'italic' { wrap( 'textit' ) } # Replace <i> and <italic> with \textit
        when 'em' { wrap( 'emph' ) } # Replace <em> with \emph
        when 'b' | 'strong' { wrap( 'textbf' ) } # Replace <b> and <strong> with \textbf
        when 'tt' | 'code' { wrap( 'texttt' ) } # Replace <tt> and <code> with \texttt
        when 'sup' | 'supscrpt' { wrap( 'textsuperscript' ) } # Superscripts
        when 'sub' { wrap( 'textsubscript' ) } # Subscripts
        when 'svg' { '' }
        when 'script' { '' }
        when 'math' { $node.nodes ?? '\ensuremath{' ~ math($node.nodes) ~ '}' !! '' }
        #when 'img' { '\{' ~ rec($node.nodes) ~ '}' }
          # $str ~~ s:i:g/"<img src=\"/content/" <[A..Z0..9]>+ "/xxlarge" (\d+) ".gif\"" .*? ">"/{chr($0)}/; # Fix for Springer Link
        #when 'email' { '\{' ~ rec($node.nodes) ~ '}' }
          # $str ~~ s:i:g/"<email>" (.*?) "</email>"/$0/; # Fix for Cambridge
        when 'span' {
          if ($node.attribs<style> // '') ~~ / 'font-family:monospace' / {
            wrap( 'texttt' )
          } elsif $node.attribs<aria-hidden>:exists {
            ''
          } elsif $node.attribs<class>:exists {
            given $node.attribs<class> {
              when / 'monospace' / { wrap( 'texttt' ) }
              when / 'italic' / { wrap( 'textit' ) }
              when / 'bold' / { wrap( 'textbf' ) }
              when / 'sup' / { wrap( 'textsuperscript' ) }
              when / 'sub' / { wrap( 'textsubscript' ) }
              when / 'sc' | [ 'type' ? 'small' '-'? 'caps' ] | 'EmphasisTypeSmallCaps' / {
                wrap( 'textsc' )
              }
              default { rec($node.nodes) }
            }
          } else {
            rec($node.nodes)
          }
        }
        default { say "WARNING: Unknown HTML tag: {$node.name}"; "[{$node.name}]" ~ rec($node.nodes) ~ "[/{$node.name}]" }
      }
    }

    default { die "Unknown XML node type '{$node.^name}': $node" }
  }
}
