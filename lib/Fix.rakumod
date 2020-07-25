unit module Fix;

use ArrayHash;
use HTML::Entity;
use Locale::Language;
use XML;

use BibTeX;
use Month;
use Isbn;
use Unicode;
use Names;

use Scrape;

enum MediaType <Print Online Both>;

class Fix {
  ## INPUTS
  has Array[Str] @.names;
  has Str %.nouns; # Maps strings to their replacements

  ## OPERATING MODES
  has Bool $.debug;
  has Bool $.scrape;
  has Bool $.fix;

  ## GENERAL OPTIONS
  has Bool $.final-comma;
  has Bool $.escape-acronyms;
  has MediaType $.isbn-media;
  has Isbn::IsbnType $.isbn-type;
  has Str $.isbn-sep;
  has MediaType $.issn-media;

  ## FIELD OPTIONS
  has Str @.fields;
  has Str @.no-encode;
  has Str @.no-collapse;
  has Str @.omit;
  has Str @.omit-empty;

  method new(*%args --> Fix:D) {
    my Array[Str] @names;
    @names[0] = Array[Str].new;
    for %args<name-file>.IO.slurp.split(rx/ "\r" | "\n" | "\r\n" /) -> $l {
      my Str $line = $l;
      $line.chomp;
      $line ~~ s/"#".*//; # Remove comments (which start with `#`)
      if $line ~~ /^\s*$/ { push @names, Array[Str].new; } # Start a new block
      else { push @names[@names.end], $line; } # Add to existing block
    }
    @names = @names.grep({ .elems > 0 });

    my Str %nouns;
    for %args<noun-file>.IO.slurp.split(rx/ "\r" | "\n" | "\r\n" /) -> $l {
      my Str $line = $l;
      $line.chomp;
      $line ~~ s/"#".*//; # Remove comments (which start with `#`)
      if $line !~~ /^\s*$/ {
        my Str $key = do given $line { S:g/<[{}]>// };
        %nouns{$key} = $line;
      }
    }

    self.bless(names => @names, nouns => %nouns, |%args);
  }

  method fix(BibTeX::Entry:D $entry is copy --> BibTeX::Entry:D) {
    $entry = $entry.clone;

    # Remove undefined fields
    $entry.fields = multi-hash($entry.fields.map({ $_ // () }));

    # Doi field: remove "http://hostname/" or "DOI: "
    $entry.fields<doi> = $entry.fields<url> if (
        not $entry.fields<doi>:exists and
        ($entry.fields<url> // "") ~~ /^ "http" "s"? "://" "dx."? "doi.org/"/ );
    update($entry, 'doi', { s:i:g/"http" "s"? "://" <-[/]>+ "/"//; s:i:g/"DOI:"\s*//; });

    # Page numbers: no "pp." or "p."
    update($entry, 'pages', { s:i:g/"p" "p"? "." \s*//; });

    # rename fields
    for ('issue' => 'number', 'keyword' => 'keywords') -> Pair $i {
      # Fix broken field names (SpringerLink and ACM violate this)
      if ($entry.fields{$i.key}:exists and
          (not $entry.fields{$i.value}:exists or
            $entry.fields{$i.key} eq $entry.fields{$i.value})) {
        $entry.fields{$i.value} = $entry.fields{$i.key};
        $entry.fields{$i.key}:delete;
      }
    }

    # Ranges: convert "-" to "--"
    for ('chapter', 'month', 'number', 'pages', 'volume', 'year') -> Str $key {
      update($entry, $key, { s:i:g/\s* ["-" | \c[EN DASH] | \c[EM DASH]]+ \s*/--/; });
      update($entry, $key, { s:i:g/"n/a--n/a"//; $_ = Nil if !$_ });
      update($entry, $key, { s:i:g/«(\w+) "--" $0»/$0/; });
      update($entry, $key, { s:i:g/(^|" ") (\w+) "--" (\w+) "--" (\w+) "--" (\w+) ($|",")/$0$1-$2--$3-$4$5/ });
      update($entry, $key, { s:i:g/\s+ "," \s+/", "/; });
    }

    check($entry, 'pages', 'suspect page number', {
      my Regex $page = rx[
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

    check($entry, 'volume', 'suspect volume', {
      /^ \d+ $/ || /^ \d+ "-" \d+ $/ || /^ <[A..Z]> "-" \d+ $/ || /^ \d+ "-" <[A..Z]> $/ });

    check($entry, 'number', 'suspect number', {
      /^ \d+ $/ || /^ \d+ "--" \d+ $/ || /^ [\d+]+ % "/" $/ || /^ \d+ "es" $/ ||
      /^ "Special Issue " \d+ ["--" \d+]? $/ || /^ "S" \d+ $/ ||
      # PACMPL uses conference abbreviations (e.g., ICFP)
      /^ <[A..Z]>+ $/ });

    self.isbn($entry, 'isbn', $.isbn-media, &canonical-isbn);

    self.isbn($entry, 'issn', $.issn-media, &canonical-issn);

    # Change language codes (e.g., "en") to proper terms (e.g., "English")
    update($entry, 'language', { $_ = code2language($_) if code2language($_).defined });

    if ($entry.fields<author>:exists) { $entry.fields<author> = $.canonical-names($entry.fields<author>) }
    if ($entry.fields<editor>:exists) { $entry.fields<editor> = $.canonical-names($entry.fields<editor>) }

    # Don't include pointless URLs to publisher's page
    update($entry, 'url', {
      $_ = Nil if m/^
        [ 'http' 's'? '://doi.acm.org/'
        | 'http' 's'? '://doi.ieeecomputersociety.org/'
        | 'http' 's'? '://doi.org/'
        | 'http' 's'? '://dx.doi.org/'
        | 'http' 's'? '://portal.acm.org/citation.cfm'
        | 'http' 's'? '://www.jstor.org/stable/'
        | 'http' 's'? '://www.sciencedirect.com/science/article/' ]/; });
    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', { $_ = Nil if $_ eq ($entry.fields<doi> // '') });
    # Eliminate Unicode but not for no_encode fields (e.g. doi, url, etc.)
    for $entry.fields.keys -> Str $field {
      $entry.fields{$field} = BibTeX::Value.new(latex-encode($entry.fields{$field}.simple-str))
        unless $field ∈ @.no-encode;
    }

    # Canonicalize series: PEPM'97 -> PEPM~'97 (must be after Unicode escaping)
    update($entry, 'series', { s:g/(<upper>+) " "* [ "'" | '{\\textquoteright}' ] (\d+)/$0~'$1/; });

    # Collapse spaces and newlines
    $_.key ∈ $.no-collapse or update($entry, $_.key, {
      s/\s* $//; # remove trailing whitespace
      s/^ \s *//; # remove leading whitespace
      s:g/(\n " "*) ** 2..*/\{\\par}/; # BibTeX eats whitespace so convert "\n\n" to paragraph break
      s:g/\s* \n \s*/ /; # Remove extra line breaks
      s:g/"\{\\par\}"/\n\{\\par\}\n/; # Nicely format paragraph breaks
      s:g/\s ** 2..* / /; # Remove duplicate whitespace
    }) for $entry.fields.pairs;

    # Keep acronyms capitalized
    update($entry, 'title', { s:g/ (\d* [<upper> \d*] ** 2..*) /\{$0\}/; }) if $.escape-acronyms;

    # Keep proper nouns capitalized
    update($entry, 'title', {
      for %.nouns.kv -> Str $k, Str $v {
        s:g/«$k»/$v/;
      }
    });

    # Use bibtex month macros
    # Must be after field encoding because we use macros
    update($entry, 'month', {
      s/ "." ($|"-")/$0/; # Remove dots due to abbriviations
      my BibTeX::Piece @x =
        .split(rx/<wb>/)
        .grep(rx/./)
        .map({
          $_ eq ( '/' | '-' | '--' ) and BibTeX::Piece.newx($_) or
          str2month($_) or
          /^ \d+ $/ and num2month($_) or
          print "WARNING: Suspect month: $_\n" and BibTeX::Piece.newx($_)});
      $_ = BibTeX::Value.new(@x)});

    # Omit fields we don't want
    $entry.fields{$_}:exists and $entry.fields{$_}:delete for @.omit;
    for @.omit-empty {
      if $entry.fields{$_}:exists {
        my $str = $entry.fields{$_}.Str;
        if $str eq ( '{}' | '""' | '' ) {
          $entry.fields{$_}:delete;
        }
      }
    }

    # Year
    check($entry, 'year', 'suspect year', { /^ \d\d\d\d $/ });

    # Generate an entry key
    my BibTeX::Value $name-value = $entry.fields<author> // $entry.fields<editor> // BibTeX::Value;
    my Str $name = $name-value.defined ?? last-name(split-names($name-value.simple-str).head) !! 'anon';
    $name ~~ s:g/ '\\' <-[{}\\]>+ '{' /\{/; # Remove codes that add accents
    $name ~~ s:g/ <-[A..Za..z0..9]> //; # Remove non-alphanum
    my Str $year = $entry.fields<year>:exists ?? ":" ~ $entry.fields<year>.simple-str !! "";
    my Str $doi = $entry.fields<doi>:exists ?? ":" ~ $entry.fields<doi>.simple-str !! "";
    $entry.key = $name ~ $year ~ $doi;

    # Put fields in a standard order (also cleans out any fields we deleted)
    my Int %fields = @.fields.map(* => 0);
    for $entry.fields.keys -> Str $field {
      unless %fields{$field}:exists { die "Unknown field '$field'" }
      unless %fields{$field}.elems == 1 { die "Duplicate field '$field'" }
      %fields{$field} = 1;
    }
    $entry.fields =
      multi-hash(
        @.fields.flatmap(
          { $entry.fields{$_}:exists ?? ($_ => $entry.fields{$_}) !! () }));

    $entry;
  }

  method isbn(BibTeX::Entry $entry, Str $field, MediaType $print_or_online, &canonical) {
    update($entry, $field, {
      if m:i/^ (<[0..9x-]>+) " (Print) " (<[0..9x-]>+) " (Online)" $/ {
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
      } elsif m:i/^ <[0..9x-]>+ $/ {
        $_ = &canonical($_, $.isbn-type, $.isbn-sep);
      } elsif m/^$/ {
        $_ = Nil
      } else {
        print "WARNING: Suspect $field: $_\n"
      }
    });
  }

  method canonical-names(BibTeX::Value:D $value --> BibTeX::Value:D) {
    my Str @names = split-names($value.simple-str);

    my Str @new-names;
    NAME:
    for @names -> $name {
      my Str $flattened-name = flatten-name($name);
      for @.names -> Str @name-group {
        for @name-group -> Str $n {
          if $flattened-name.fc eq flatten-name($n).fc {
            push @new-names, @name-group.head.Str;
            next NAME;
          }
        }
      }

      my Regex $first = rx/
          <upper><lower>+                     # Simple name
        | <upper><lower>+ '-' <upper><lower>+ # Hyphenated name with upper
        | <upper><lower>+ '-' <lower><lower>+ # Hyphenated name with lower
        | <upper><lower>+     <upper><lower>+ # "Asian" name (e.g. XiaoLin)
        # We could allow the following but publishers often abriviate
        # names when the actual paper doesn't
        # | <upper> '.'                       # Initial
        # | <upper> '.-' <upper> '.'          # Double initial
        /;
      my Regex $middle = rx/<upper>\./; # Allow for a middle initial
      my Regex $last = rx/
          <upper><lower>+                     # Simple name
        | <upper><lower>+ '-' <upper><lower>+ # Hyphenated name with upper
        | ["O'"|"Mc"|"Mac"] <upper><lower>+   # Name with prefix
        /;
      unless $flattened-name ~~ /^ \s* $first \s+ [$middle \s+]? $last \s* $/ {
        print "WARNING: Suspect name: {order-name($name)}\n"
      }

      push @new-names, order-name($name);
    }

    # Warn about duplicate names
    my Int %seen;
    %seen{$_}++ and say "WARNING: Duplicate name: $_" for @new-names;

    BibTeX::Value.new(@new-names.join( ' and ' ));
  }

}

sub check(BibTeX::Entry $entry, Str $field, Str $msg, &check) {
  if ($entry.fields{$field}:exists) {
    my Str $value = $entry.fields{$field}.simple-str;
    unless (&check($value)) {
      say "WARNING: $msg: ", $value;
    }
  }
}

sub greek(Str $str is copy --> Str:D) {
  # Based on table 131 in Comprehensive Latex
  my Str @mapping = <
_ A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi O
\Pi P _ \Sigma T \Upsilon \Phi X \Psi \Omega _ _ _ _ _ _
_ \alpha \beta \gamma \delta \varepsilon \zeta \eta \theta \iota \kappa \mu \nu \xi o
\pi \rho \varsigma \sigma \tau \upsilon \varphi \xi \psi \omega _ _ _ _ _ _>;
  $str ~~ s:g/ (<[\x[0390]..\x[03cf]]>)
             /{ @mapping[ord($0)-0x0390] ne '_' ?? @mapping[ord($0)-0x0390] !! $0}/;
  return $str;
}

sub math(@nodes --> Str:D) {
  @nodes.map({math-node($_)}).join
}

sub math-node(XML::Node $node --> Str:D) {
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
          if ($node.attribs<mathvariant> // '') eq 'normal' {
            '\mathrm{' ~ math($node.nodes) ~ '}'
          } else {
            math($node.nodes)
          }
        }
        when 'mo' { math($node.nodes) }
        when 'mn' { math($node.nodes) }
        when 'msqrt' { '\sqrt{' ~ math($node.nodes) ~ '}' }
        when 'mrow' { '{' ~ math($node.nodes) ~ '}' }
        when 'mspace' { '\hspace{' ~ $node.attribs<width> ~ '}' }
        when 'msubsup' { '{' ~ math-node($node.nodes[0]) ~ '}_{' ~ math-node($node.nodes[1]) ~ '}^{' ~ math-node($node.nodes[2]) ~ '}' }
        when 'msub' { '{' ~ math-node($node.nodes[0]) ~ '}_{' ~ math-node($node.nodes[1]) ~ '}' }
        when 'msup' { '{' ~ math-node($node.nodes[0]) ~ '}^{' ~ math-node($node.nodes[1]) ~ '}' }
        default { say "WARNING: unknown HTML tag: {$node.name}"; "[{$node.name}]" ~ rec($node.nodes) ~ "[/{$node.name}]" }
      }
    }

    default { die }
  }
}

sub rec(@nodes --> Str:D) {
  @nodes.map({rec-node($_)}).join
}
sub rec-node(XML::Node $node --> Str:D) {
  # # HTML -> LaTeX Codes
  # $str = decode-entities($str);
  # $str ~~ s:i:g/"<a " <-[>]>* "onclick=\"toggleTabs(" .*? ")>" .*? "</a>"//; # Fix for Science Direct

  # # HTML formatting
  # $str ~~ s:i:g/"<" (<-[>]>*) <wb> "class=\"a-plus-plus\"" (<-[>]>*) ">"/<$0$1>/; # Remove class annotation
  # $str ~~ s:i:g/"<" (\w+) \s* ">"/<$0>/; # Removed extra space around simple tags

  # $str ~~ s:i:g/"<i" (" " <-[>]>*?)? ">" "</i>"//; # Remove empty <i>

  # $str ~~ s:i:g/"<img src=\"/content/" <[A..Z0..9]>+ "/xxlarge" (\d+) ".gif\"" .*? ">"/{chr($0)}/; # Fix for Springer Link
  # $str ~~ s:i:g/"<email>" (.*?) "</email>"/$0/; # Fix for Cambridge

  given $node {
    when XML::CDATA { $node.data }
    when XML::Comment { '' } # Remove HTML Comments
    when XML::Document { rec($node.root) }
    when XML::PI { '' }
    when XML::Text { decode-entities($node.text) }

    when XML::Element {
      sub wrap(Str:D $tag --> Str:D) {
        if $node.nodes {
          "\\$tag\{" ~ rec($node.nodes) ~ "\}"
        } else {
          ''
        }
      }
      given $node.name {
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
        #when 'email' { '\{' ~ rec($node.nodes) ~ '}' }
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
        default { say "WARNING: unknown HTML tag: {$node.name}"; "[{$node.name}]" ~ rec($node.nodes) ~ "[/{$node.name}]" }
      }
    }

    default { die }
  }
}

sub latex-encode(Str:D $str is copy --> Str:D) {
  my XML::Node $xml = from-xml("<root>{$str}</root>");
  $str = rec(@($xml.root.nodes));

  # Trim spaces before NBSP (otherwise they have no effect in LaTeX)
  $str ~~ s:g/" "* \xA0/\xA0/;

  # TODO: Remove
  # Encode unicode but skip any \, {, or } that we already encoded.
  my Str:D @parts = $str.split(rx/ "\$" .*? "\$" | <[\\{}_^]> /, :v)».Str;

  return @parts.map({ /<[_^{}\\\$]>/ ?? $_ !! unicode2tex($_) }).join('');
}
