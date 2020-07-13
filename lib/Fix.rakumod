unit module Fix;

use ArrayHash;
use HTML::Entity;
use Locale::Language;

use BibTeX;
use BibTeX::Months;
use Isbn;
use Unicode;

use Scrape;

enum MediaType <Print Online Both>;

class Fix {
  ## INPUTS
  has Array @.names;
  has Str @.nouns;

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

    my Str @nouns;
    for %args<noun-file>.IO.slurp.split(rx/ "\r" | "\n" | "\r\n" /) -> $l {
      my $line = $l;
      $line.chomp;
      $line ~~ s/"#".*//; # Remove comments (which start with `#`)
      if $line !~~ /^\s*$/ {
        push @nouns, $line;
      }
    }

    self.bless(names => @names, nouns => @nouns, |%args);
  }

  method fix(BibTeX::Entry $bibtex --> BibTeX::Entry) {
    my $entry = $bibtex.clone;

    # TODO: $bib_text ~~ s/^\x{FEFF}//; # Remove Byte Order Mark
    # Fix any unicode that is in the field values
    # $entry->set_key(decode('utf8', $entry->key));
    # $entry->set($_, decode('utf8', $entry->get($_)))
    #     for ($entry->fieldlist());

    $entry.key = $entry.key.lc;
    $entry.fields = multi-hash($entry.fields.map({ $_.key.lc => $_.value }));

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
        \d+ (<[.:/]>) \d+ "--" \d+ \0 \d+ |

        # "Front" page
        "f" \d+ |
        "f" \d+ "--" f\d+
        ];
      /^ $page+ % "," $/;
    });

    check($entry, 'volume', 'suspect volume', {
      /^ \d+ $/ || /^ \d+ "-" \d+ $/ || /^ <[A..Z]> "-" \d+ $/ || /^ \d+ "-" <[A..Z]> $/ });

    check($entry, 'number', 'suspect number', {
      /^ \d+ $/ || /^ \d+ "--" \d+ $/ || /^ [\d+]+ % "/" $/ || /^ \d+ "es" $/ ||
      /^ "Special Issue " \d+ ["--" \d+]? $/ || /^ "S" \d+ $/});

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
        | 'http' 's'? '://onlinelibrary.wiley.com/doi/abs/'
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
    $_ ∈ $.no-collapse or update($entry, $_.key, {
      s/\s* $//; # remove trailing whitespace
      s/^ \s *//; # remove leading whitespace
      s:s:g/(\n " "*) ** 2..*/"\{\\par}"/; # BibTeX eats whitespace so convert "\n\n" to paragraph break
      s:s:g/\s* \n \s*/ /; # Remove extra line breaks
      s:s:g/"\{\\par\}"/\n\{\\par\}\n/; # Nicely format paragraph breaks
      s:s:g/\s ** 2..* / /; # Remove duplicate whitespace
    }) for $entry.fields.pairs;

    update($entry, 'title', { s:g/ (\d* [<upper> \d*] ** 2..*) /\{$0\}/; }) if $.escape-acronyms;

    # TODO: nouns

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
    $entry.fields{$_}:exists and $entry.fields{$_} eq '' and $entry.fields{$_}:delete for @.omit-empty;

    # Year
    check($entry, 'year', 'suspect year', { /^ \d\d\d\d $/ });

    # Generate an entry key
    my $name = $entry.fields<author> // $entry.fields<editor>;
    $name = $name.defined ??
      purify-string(do given parse-names($name.simple-str).head.last { S:g/ ' ' // }) !!
      'anon';
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
      if m:i/^ (<[0..9x-]>+) "(Print)" (<[0..9x-]>+) "(Online)" $/ {
        given $print_or_online {
          when Print {
            $_ = &canonical($0, $.isbn-type, $.isbn-sep);
          }
          when Online {
            $_ = &canonical($1, $.isbn-type, $.isbn-sep);
          }
          when Both {
            $_ = &canonical($0, $.isbn-type, $.isbn-sep)
              ~ ' (Print) '
              ~ &canonical($1, $.isbn-type, $.isbn-sep)
              ~ ' (Online)';
          }
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
          if flatten-name($name).lc eq flatten-name($n).lc {
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

sub update(BibTeX::Entry $entry, Str $field, &fun) {
  if $entry.fields{$field}:exists {
    # Have to put this in a variable so s/// can modify it
    my $value = $entry.fields{$field}.simple-str;
    &fun($value); # $value will be $_ in the block
    if $value.defined { $entry.fields{$field} = BibTeX::Value.new($value); }
    else { $entry.fields{$field}:delete; }
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

sub purify-string (Str $str) { $str }

# Based on TeX::Encode and modified to use braces appropriate for BibTeX.
sub latex-encode(Str $s) {
  my $str = $s;

  # HTML -> LaTeX Codes
  $str = decode-entities($str);
  $str ~~ s:s:g/"<!--" .*? "-->"//; # Remove HTML comments
  $str ~~ s:i:s:g/"<a " <-[>]>* "onclick=\"toggleTabs(" .*? ")>" .*? "</a>"//; # Fix for Science Direct

  # HTML formatting
  $str ~~ s:i:s:g/"<" (<-[>]>*) <wb> "class=\"a-plus-plus\"" (<-[>]>*) ">"/<$0$1>/; # Remove class annotation
  $str ~~ s:i:s:g/"<" (\w+) \s* ">"/<$0>/; # Removed extra space around simple tags
  $str ~~ s:i:s:g/"<a" (" ".*?)? ">" (.*?)"</a>"/$1/; # Remove <a> links
  $str ~~ s:i:s:g/"<p" (""|" " <-[>]>*) ">" (.*?) "</p>"/$1\n\n/; # Replace <p> with "\n\n"
  $str ~~ s:i:s:g/"<par" (""|" " <-[>]>*) ">" (.*?) "</par>"/$1\n\n/; # Replace <par> with "\n\n"
  $str ~~ s:i:s:g/"<span style=" <["']> "font-family:monospace" \s* <["']> ">" (.*?) "</span>"/\\texttt\{$0\}/; # Replace monospace spans with \texttt
  $str ~~ s:i:s:g/"<span class=" <["']> "monospace" \s* <["']> <-[>]>* ">" (.*?) "</span>"/\\texttt\{$0\}/; # Replace monospace spans with \texttt
  $str ~~ s:i:s:g/"<span class=" <["']> "small" "-"? "caps" \s* <["']> <-[>]>* ">" (.*?) "</span>"/\\textsc\{$0\}/; # Replace small caps spans with \textsc
  $str ~~ s:i:s:g/"<span class=" <["']> <-["']>* "type-small-caps" <-["']>* <["']> ">" (.*?) "</span>"/\\textsc\{$0\}/; # Replace small caps spans with \textsc
  $str ~~ s:i:s:g/"<span class=" <["']> "italic" <["']> ">" (.*?) "</span>"/\\textit\{$0\}/;
  $str ~~ s:i:s:g/"<span class=" <["']> "bold" <["']> ">" (.*?) "</span>"/\\textbf\{$0\}/;
  $str ~~ s:i:s:g/"<span class=" <["']> "sup" <["']> ">" (.*?) "</span>"/\\textsuperscript\{$0\}/;
  $str ~~ s:i:s:g/"<span class=" <["']> "sub" <["']> ">" (.*?) "</span>"/\\textsubscript\{$0\}/;
  $str ~~ s:i:s:g/"<span class=" <["']> "sc" <["']> ">" (.*?) "</span>"/\\textsc\{$0\}/;
  $str ~~ s:i:s:g/"<span class=" <["']> "EmphasisTypeSmallCaps " <["']> ">" (.*?) "</span>"/\\textsc\{$0\}/;
  $str ~~ s:i:s:g/"<span" (" " .*?)? ">" (.*?) "</span>"/$1/; # Remove <span>
  $str ~~ s:i:s:g/"<span" (" " .*?)? ">" (.*?) "</span>"/$1/; # Remove <span>
  $str ~~ s:i:s:g/"<i" (" " <-[>]>*?)? ">" "</i>"//; # Remove empty <i>
  $str ~~ s:i:s:g/"<i>" (.*?) "</i>"/\\textit\{$0\}/; # Replace <i> with \textit
  $str ~~ s:i:s:g/"<italic>" (.*?) "</italic>"/\\textit\{$0\}/; # Replace <italic> with \textit
  $str ~~ s:i:s:g/"<em" <wb> <-[>]>*? ">" (.*?) "</em>"/\\emph\{$0\}/; # Replace <em> with \emph
  $str ~~ s:i:s:g/"<strong>" (.*?) "</strong>"/\\textbf\{$0\}/; # Replace <strong> with \textbf
  $str ~~ s:i:s:g/"<b>" (.*?) "</b>"/\\textbf\{$0\}/; # Replace <b> with \textbf
  $str ~~ s:i:s:g/"<tt>" (.*?) "</tt>"/\\texttt\{$0\}/; # Replace <tt> with \texttt
  $str ~~ s:i:s:g/"<code>" (.*?) "</code>"/\\texttt\{$0\}/; # Replace <code> with \texttt
  $str ~~ s:i:s:g/"<sup>" "</sup>"//; # Remove emtpy <sup>
  $str ~~ s:i:s:g/"<sup>" (.*?) "</sup>"/\\textsuperscript\{$0\}/; # Super scripts
  $str ~~ s:i:s:g/"<supscrpt>" (.*?) "</supscrpt>"/\\textsuperscript\{$0\}/; # Super scripts
  $str ~~ s:i:s:g/"<sub>" (.*?) "</sub>"/\\textsubscript\{$0\}/; # Sub scripts

  $str ~~ s:i:s:g/"<img src=\"/content/" <[A..Z0..9]>+ "/xxlarge" (\d+) ".gif\"" .*? ">"/{chr($0)}/; # Fix for Springer Link
  $str ~~ s:i:s:g/"<email>" (.*?) "</email>"/$0/; # Fix for Cambridge

  # MathML formatting
#  my $xml = XML::Parser->new(Style => 'Tree');
#  $str ~~ s:g:s/("<" <?"mml:">? "math" <wb> <-[>]>* ">" .*? "</" <?"mml:">? "math>")
#            /\\ensuremath\{{rec(@($xml->parse($0)))}\}/; # TODO: ensuremath (but avoid latex encoding)

  # Trim spaces before NBSP (otherwise they have not effect in LaTeX)
  $str ~~ s:g/" "* \xA0/\xA0/;

  # Encode unicode but skip any \, {, or } that we already encoded.
  my @parts = $str.split(rx/ "\$" .*? "\$" | <[\\{}_^]> /, :v);

  return @parts.map({ /<[_^{}\\\$]>/ ?? $_ !! unicode2tex($_) }).join('');
}

#sub rec {
#    my ($tag, $body) = @_;
#
#    if ($tag eq '0') { return greek($body); }
#    my %attr = %{shift @$body};
#
#    if ($tag ~~ m[(mml:)?math]) { return xml(@$body); }
#    if ($tag ~~ m[(mml:)?mtext]) { return xml(@$body); }
#    if ($tag ~~ m[(mml:)?mi] and exists $attr{'mathvariant'} and $attr{'mathvariant'} eq 'normal') {
#        return '\mathrm{' . xml(@$body) . '}' }
#    if ($tag ~~ m[(mml:)?mi]) { return xml(@$body) }
#    if ($tag ~~ m[(mml:)?mo]) { return xml(@$body) }
#    if ($tag ~~ m[(mml:)?mn]) { return xml(@$body) }
#    if ($tag ~~ m[(mml:)?msqrt]) { return '\sqrt{' . xml(@$body) . '}' }
#    if ($tag ~~ m[(mml:)?mrow]) { return '{' . xml(@$body) . '}' }
#    if ($tag ~~ m[(mml:)?mspace]) { return '\hspace{' . $attr{'width'} . '}' }
#    if ($tag ~~ m[(mml:)?msubsup]) { return '{' . xml(@$body[0..1]) .
#                                     '}_{' . xml(@$body[2..3]) .
#                                     '}^{' . xml(@$body[4..5]) . '}' }
#    if ($tag ~~ m[(mml:)?msub]) { return '{' . xml(@$body[0..1]) . '}_{' . xml(@$body[2..3]) . '}' }
#    if ($tag ~~ m[(mml:)?msup]) { return '{' . xml(@$body[0..1]) . '}^{' . xml(@$body[2..3]) . '}' }
#}

#sub xml {
#    if ($#_ == -1) { return ''; }
#    elsif ($#_ == 0) { die; }
#    else { rec(@_[0..1]) . xml(@_[2..$#_]); }
#}

#sub greek {
#    my ($str) = @_;
##    370; 390
## Based on table 131 in Comprehensive Latex
#    my @mapping = qw(
#_ A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi O
#\Pi P _ \Sigma T \Upsilon \Phi X \Psi \Omega _ _ _ _ _ _
#_ \alpha \beta \gamma \delta \varepsilon \zeta \eta \theta \iota \kappa \mu \nu \xi o
#\pi \rho \varsigma \sigma \tau \upsilon \varphi \xi \psi \omega _ _ _ _ _ _);
#    $str ~~ s[([\N{U+0390}-\N{U+03cf}])]
#             [@{[$mapping[ord($0)-0x0390] ne '_' ? $mapping[ord($0)-0x0390] : $0]}]g;
#    return $str;
#
##    0x03b1 => '\\textgreek{a}',
##\varphi
##    0x03b2 => '\\textgreek{b}',
##    0x03b3 => '\\textgreek{g}',
##    0x03b4 => '\\textgreek{d}',
##    0x03b5 => '\\textgreek{e}',
##    0x03b6 => '\\textgreek{z}',
##    0x03b7 => '\\textgreek{h}',
##    0x03b8 => '\\textgreek{j}',
##    0x03b9 => '\\textgreek{i}',
##    0x03ba => '\\textgreek{k}',
##    0x03bb => '\\textgreek{l}',
##    0x03bc => '\\textgreek{m}',
##    0x03bd => '\\textgreek{n}',
##    0x03be => '\\textgreek{x}',
##    0x03bf => '\\textgreek{o}',
##    0x03c0 => '\\textgreek{p}',
##    0x03c1 => '\\textgreek{r}',
##    0x03c2 => '\\textgreek{c}',
##    0x03c3 => '\\textgreek{s}',
##    0x03c4 => '\\textgreek{t}',
##    0x03c5 => '\\textgreek{u}',
##    0x03c6 => '\\textgreek{f}',
##    0x03c7 => '\\textgreek{q}',
##    0x03c8 => '\\textgreek{y}',
##    0x03c9 => '\\textgreek{w}',
##
##    0x03d1 => '\\ensuremath{\\vartheta}',
##    0x03d4 => '\\textgreek{"\\ensuremath{\\Upsilon}}',
##    0x03d5 => '\\ensuremath{\\phi}',
##    0x03d6 => '\\ensuremath{\\varpi}',
##    0x03d8 => '\\textgreek{\\Koppa}',
##    0x03d9 => '\\textgreek{\\coppa}',
##    0x03da => '\\textgreek{\\Stigma}',
##    0x03db => '\\textgreek{\\stigma}',
##    0x03dc => '\\textgreek{\\Digamma}',
##    0x03dd => '\\textgreek{\\digamma}',
##    0x03df => '\\textgreek{\\koppa}',
##    0x03e0 => '\\textgreek{\\Sampi}',
##    0x03e1 => '\\textgreek{\\sampi}',
##    0x03f0 => '\\ensuremath{\\varkappa}',
##    0x03f1 => '\\ensuremath{\\varrho}',
##    0x03f4 => '\\ensuremath{\\Theta}',
##    0x03f5 => '\\ensuremath{\\epsilon}',
##    0x03f6 => '\\ensuremath{\\backepsilon}',
#
##ff
#
#}

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
