unit module Fix;

use ArrayHash;
use HTML::Entity;
use Locale::Language;
use XML;

use BibTeX;
use Month;
use Isbn;
use Unicode;

use Scrape;

enum MediaType <Print Online Both>;

class Fix {
  ## INPUTS
  has Array @.names;
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

  method new(*%args) {
    my @names;
    @names[0] = ();
    for %args<name-file>.IO.slurp.split(rx/ "\r" | "\n" | "\r\n" /) -> $l {
      my $line = $l;
      $line.chomp;
      $line ~~ s/"#".*//; # Remove comments (which start with `#`)
      if $line ~~ /^\s*$/ { push @names, []; } # Start a new block
      else {
        my @new-names = parse-names($line);
        die if @new-names.elems != 1;
        push @names[@names.end], @new-names.head;
      }
    }
    @names = @names.grep({ .elems > 0});

    my Str %nouns;
    for %args<noun-file>.IO.slurp.split(rx/ "\r" | "\n" | "\r\n" /) -> $l {
      my $line = $l;
      $line.chomp;
      $line ~~ s/"#".*//; # Remove comments (which start with `#`)
      if $line !~~ /^\s*$/ {
        my $key = do given $line { S:g/<[{}]>// };
        %nouns{$key} = $line;
      }
    }

    self.bless(names => @names, nouns => %nouns, |%args);
  }

  # TODO: is copy
  method fix(BibTeX::Entry $bibtex --> BibTeX::Entry) {
    my $entry = $bibtex.clone;

    # TODO: $bib_text ~~ s/^\x{FEFF}//; # Remove Byte Order Mark
    # Fix any unicode that is in the field values
    # $entry->set_key(decode('utf8', $entry->key));
    # $entry->set($_, decode('utf8', $entry->get($_)))
    #     for ($entry->fieldlist());

    $entry.type = $entry.type.lc;
    $entry.fields = multi-hash($entry.fields.map({ $_.defined ?? ($_.key.lc => $_.value) !! () }));

    # Doi field: remove "http://hostname/" or "DOI: "
    $entry.fields<doi> = $entry.fields<url> if (
        not $entry.fields<doi>:exists and
        ($entry.fields<url> // "") ~~ /^ "http" "s"? "://" "dx."? "doi.org/"/ );
    update($entry, 'doi', { s:i:g/"http" "s"? "://" <-[/]>+ "/"//; s:i:g/"DOI:"\s*//; });

    # Page numbers: no "pp." or "p."
    update($entry, 'pages', { s:i:g/"p" "p"? "." \s*//; });

    # rename fields
    for ('issue' => 'number', 'keyword' => 'keywords') -> $i {
      # Fix broken field names (SpringerLink and ACM violate this)
      if ($entry.fields{$i.key}:exists and
          (not $entry.fields{$i.value}:exists or
            $entry.fields{$i.key} eq $entry.fields{$i.value})) {
        $entry.fields{$i.value} = $entry.fields{$i.key};
        $entry.fields{$i.key}:delete;
      }
    }

    # Ranges: convert "-" to "--"
    for ('chapter', 'month', 'number', 'pages', 'volume', 'year') -> $key {
      update($entry, $key, { s:i:g/\s* ["-" | \c[EN DASH] | \c[EM DASH]]+ \s*/--/; });
      update($entry, $key, { s:i:g/"n/a--n/a"//; $_ = Nil if $_ eq "" });
      update($entry, $key, { s:i:g/«(\w+) "--" $0»/$0/; });
      update($entry, $key, { s:i:g/(^|" ") (\w+) "--" (\w+) "--" (\w+) "--" (\w+) ($|",")/$0$1-$2--$3-$4$5/ });
      update($entry, $key, { s:i:g/\s+ "," \s+/", "/; });
    }

    check($entry, 'pages', 'suspect page number', {
      my $page = rx[
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
    update($entry, 'language', { $_ = code2language($_) if defined code2language($_) });

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
    for $entry.fields.keys -> $field {
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
      for %.nouns.kv -> $k, $v {
        s:g/«$k»/$v/;
      }
    });

    # Use bibtex month macros
    # Must be after field encoding because we use macros
    update($entry, 'month', {
      s/ "." ($|"-")/$0/; # Remove dots due to abbriviations
      my @x =
        .split(rx/<wb>/)
        .grep(rx/./)
        .map({
          ($_ eq '/' || $_ eq '-' || $_ eq '--') and BibTeX::Piece.newx($_) or
          str2month($_) or
          /^ \d+ $/ and num2month($_) or
          print "WARNING: Suspect month: $_\n" and BibTeX::Piece.newx($_)});
      $_ = BibTeX::Value.new(@x)});

    # Omit fields we don't want
    $entry.fields{$_}:exists and $entry.fields{$_}:delete for @.omit;
    for @.omit-empty {
      if $entry.fields{$_}:exists {
        my $str = $entry.fields{$_}.Str;
        if $str eq '{}' or $str eq '""' or $str eq '' {
          $entry.fields{$_}:delete;
        }
      }
    }

    # Year
    check($entry, 'year', 'suspect year', { /^ \d\d\d\d $/ });

    # Generate an entry key
    my $name = $entry.fields<author> // $entry.fields<editor>;
    $name = $name.defined ?? parse-names($name.simple-str).head.last !! 'anon';
    $name ~~ s:g/ '\\' <-[{}\\]>+ '{' /\{/; # Remove codes that add accents
    $name ~~ s:g/ <-[A..Za..z0..9]> //; # Remove non-alphanum
    my $year = $entry.fields<year>:exists ?? ":" ~ $entry.fields<year>.simple-str !! "";
    my $doi = $entry.fields<doi>:exists ?? ":" ~ $entry.fields<doi>.simple-str !! "";
    $entry.key = $name ~ $year ~ $doi;

    # Put fields in a standard order (also cleans out any fields we deleted)
    my %fields = @.fields.map(* => 0);
    for $entry.fields.keys -> $field {
      unless %fields{$field}:exists { die "Unknown field '$field'" }
      unless %fields{$field} == 0 { die "Duplicate field '$field'" }
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
        if $print_or_online == Print {
          $_ = &canonical($0.Str, $.isbn-type, $.isbn-sep);
        }
        if $print_or_online == Online {
          $_ = &canonical($1.Str, $.isbn-type, $.isbn-sep);
        }
        if $print_or_online == Both {
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

  method canonical-names(BibTeX::Value $value --> BibTeX::Value) {
    my $names = $value.simple-str;
    my BibTeX::Name @names = parse-names($names);

    my Str @new-names;
    NAME:
    for @names -> $name {
      for @.names -> @name-group {
        for @name-group -> $n {
          if flatten-name($name).fc eq flatten-name($n).fc {
            push @new-names, @name-group.head.Str;
            next NAME;
          }
        }
      }
      print "WARNING: Suspect name: {$name.Str}\n" unless
        (not $name.von.defined and
          not $name.jr.defined and
          check-first-name($name.first) and
          check-last-name($name.last));

      push @new-names, $name.Str;
    }

    # Warn about duplicate names
    my %seen;
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

sub greek(Str $str is copy) {
  # Based on table 131 in Comprehensive Latex
  my @mapping = <
_ A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi O
\Pi P _ \Sigma T \Upsilon \Phi X \Psi \Omega _ _ _ _ _ _
_ \alpha \beta \gamma \delta \varepsilon \zeta \eta \theta \iota \kappa \mu \nu \xi o
\pi \rho \varsigma \sigma \tau \upsilon \varphi \xi \psi \omega _ _ _ _ _ _>;
  $str ~~ s:g/ (<[\x[0390]..\x[03cf]]>)
             /{ @mapping[ord($0)-0x0390] ne '_' ?? @mapping[ord($0)-0x0390] !! $0}/;
  return $str;
}

multi sub math(@nodes) {
  @nodes.map({math($_)}).join
}

multi sub math(XML::Node $node) {
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
        when 'msubsup' { '{' ~ math($node.nodes[0]) ~ '}_{' ~ math($node.nodes[1]) ~ '}^{' ~ math($node.nodes[2]) ~ '}' }
        when 'msub' { '{' ~ math($node.nodes[0]) ~ '}_{' ~ math($node.nodes[1]) ~ '}' }
        when 'msup' { '{' ~ math($node.nodes[0]) ~ '}^{' ~ math($node.nodes[1]) ~ '}' }
        default { say "WARNING: unknown HTML tag: {$node.name}"; "[{$node.name}]" ~ rec($node.nodes) ~ "[/{$node.name}]" }
      }
    }

    default { die }
  }
}

multi sub rec(@nodes) {
  @nodes.map({rec($_)}).join
}
multi sub rec(XML::Node $node) {
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
      sub wrap($tag) {
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

sub latex-encode(Str $str is copy) {
  my $xml = from-xml("<root>{$str}</root>");
  $str = rec($xml.root.nodes);

  # Trim spaces before NBSP (otherwise they have no effect in LaTeX)
  $str ~~ s:g/" "* \xA0/\xA0/;

  # TODO: Remove
  # Encode unicode but skip any \, {, or } that we already encoded.
  my @parts = $str.split(rx/ "\$" .*? "\$" | <[\\{}_^]> /, :v);

  return @parts.map({ /<[_^{}\\\$]>/ ?? $_ !! unicode2tex($_) }).join('');
}

sub check-first-name(Str $n) {
  my $name = $n;
  $name ~~ s/\s<upper>\.$//; # Allow for a middle initial

  $name ~~ /^<upper><lower>+$/ || # Simple name
    $name ~~ /^<upper><lower>+ '-' <upper><lower>+$/ || # Hyphenated name with upper
    $name ~~ /^<upper><lower>+ '-' <lower><lower>+$/ || # Hyphenated name with lower
    $name ~~ /^<upper><lower>+     <upper><lower>+$/ || # "Asian" name (e.g. XiaoLin)
    # We could allow the following but publishers often abriviate
    # names when the actual paper doesn't
    #$name =~ /^\p{upper}\.$/ || # Initial
    #$name =~ /^\p{upper}\.-\p{upper}\.$/ || # Double initial
    False;
}

sub check-last-name(Str $name) {
  $name ~~ /^<upper><lower>+$/ || # Simple name
    $name ~~ /^<upper><lower>+ '-' <upper><lower> +$/ || # Hyphenated name with upper
    $name ~~ /^("O'"|"Mc"|"Mac") <upper><lower>+$/; # Name with prefix
}

sub flatten-name(BibTeX::Name $name) {
  join( ' ',
    $name.first // (),
    $name.von // (),
    $name.last // (),
    $name.jr // ());
}
