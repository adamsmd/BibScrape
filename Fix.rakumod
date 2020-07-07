use ArrayHash;

use BibTeX;
use BibTeX::Months;
use Isbn;

enum MediaType <Print Online Both>;

class Fix {
  #valid_names => [map {read_valid_names($_)} @NAME_FILE],
  #field_actions => join('\n', slurp_file(@FIELD_ACTION_FILE)),

  ## INPUTS
  has List @.names; # List of List of BibTeX Names
  has IO::Path @.actions; # TODO: Executable

  ## OPERATING MODES
  has Bool $.debug;
  has Bool $.scrape;
  has Bool $.fix;

  ## GENERAL OPTIONS
  has Bool $.final-comma;
  has Bool $.escape-acronyms;
  has MediaType $.isbn-media;
  has IsbnType $.isbn-type;
  has Str $.isbn-sep;
  has MediaType $.issn-media;

  ## FIELD OPTIONS
  has Str @.fields;
  has Str @.no-encode;
  has Str @.no-collapse;
  has Str @.omit;
  has Str @.omit-empty;

  method fix(BibTeX::Entry $bibtex) {
    my $entry = $bibtex.clone;

#     # TODO: $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark
#     # Fix any unicode that is in the field values
# #    $entry->set_key(decode('utf8', $entry->key));
# #    $entry->set($_, decode('utf8', $entry->get($_)))
# #        for ($entry->fieldlist());

    # Doi field: remove "http://hostname/" or "DOI: "
    $entry.fields<doi> = $entry.fields<url> if (
        not $entry.fields<doi>:exists and
        ($entry.fields<url> // "") ~~ /^ "http" "s"? "://" "dx."? "doi.org/"/ );
    update($entry, 'doi', { s:i:g/"http" "s"? "://" <-[/]>+ "/"//; s:i:g/"DOI:"\s*//; });

    # Page numbers: no "pp." or "p."
    # TODO: page fields
    # [][pages][pp?\.\s*][]ig;
    update($entry, 'pages', { s:i:g/"p" "p"? "." \s*//; });

    # [][number]rename[issue][.+][$1]delete;
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
    # TODO: option for numeric range
    # TODO: might misfire if "-" doesn't represent a range, Common for tech report numbers
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

    check($entry, 'number', 'suspect number', sub {
      /^ \d+ $/ || /^ \d+ "--" \d+ $/ || /^ [\d+]+ % "/" $/ || /^ \d+ "es" $/ ||
      /^ "Special Issue " \d+ ["--" \d+]? $/ || /^ "S" \d+ $/});

#     # TODO: Keywords: ';' vs ','

    self.isbn($entry, 'isbn', $.isbn-media, &canonical-isbn);

    self.isbn($entry, 'issn', $.issn-media, &canonical-issn);

#     # TODO: Author, Editor, Affiliation: List of renames
# # Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:

#     # Change language codes (e.g., "en") to proper terms (e.g., "English")
#     update($entry, 'language', sub { $_ = code2language($_) if defined code2language($_) });
# #  List of renames (regex?)

#     if ($entry->exists('author')) { canonical_names($self, $entry, 'author') }
#     if ($entry->exists('editor')) { canonical_names($self, $entry, 'editor') }

# #D<onald|.=[onald]> <E.|> Knuth
# #
# #D(onald|.) (E.) Knuth
# #D E Knuth
# #
# #D[onald] Knuth
# #D Knuth
# #
# #D[onald] [E.] Knuth
# #D Knuth
# #
# #Donald Knuth
# #D[onald] Knuth
# #D. Knuth
# #Knuth, D.

    # Don't include pointless URLs to publisher's page
    # [][url][http://dx.doi.org/][];
    # TODO: via Omit if matches
    # TODO: omit if ...
    update($entry, 'url', {
      $_ = Nil if m/^
        [ "http" "s"? "://doi.org/"
        | "http" "s"? "://dx.doi.org/"
        | "http" "s"? "://doi.acm.org/"
        | "http" "s"? "://portal.acm.org/citation.cfm"
        | "http" "s"? "://www.jstor.org/stable/"
        | "http" "s"? "://www.sciencedirect.com/science/article/"
        | "http" "s"? "://onlinelibrary.wiley.com/doi/abs/" ]/; });
    # TODO: via omit if empty
    update($entry, 'note', { $_ = Nil if $_ eq "" });
    # TODO: add $doi to omit if matches
    # [][note][$doi][]
    # regex delete if looks like doi
    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', { $_ = Nil if $_ eq ($entry.fields<doi> // "") });

#     # Eliminate Unicode but not for no_encode fields (e.g. doi, url, etc.)
#     for my $field ($entry->fieldlist()) {
#         warn "Undefined $field" unless defined $entry->get($field);
#         $entry->set($field, latex_encode($entry->get($field)))
#             unless exists $self->no_encode->{$field};
#     }

    # Canonicalize series: PEPM'97 -> PEPM~'97 (must be after Unicode escaping)
    update($entry, 'series', { s:g/(<upper>+) " "* "'" (\d+)/$1~'$2/; });

    # Collapse spaces and newlines
    $_ ∈ $.no-collapse or update($entry, $_.key, {
      s/\s* $//; # remove trailing whitespace
      s/^ \s *//; # remove leading whitespace
      s:s:g/(\n " "*) ** 2..*/"\{\\par}"/; # BibTeX eats whitespace so convert "\n\n" to paragraph break
      s:s:g/\s* \n \s*/ /; # Remove extra line breaks
      s:s:g/"\{\\par\}"/\n\{\\par\}\n/; # Nicely format paragraph breaks
      s:s:g/\s ** 2..* / /; # Remove duplicate whitespace
    }) for $entry.fields.pairs;

    # TODO: Title Capticalization: Initialisms, After colon, list of proper names
    update($entry, 'title', { s:g/ (\d* [<upper> \d*] ** 2..*) / "\{" $1 "\}" /; }) if $.escape-acronyms;

#     for $FIELD ($entry->fieldlist()) {
#         my $compartment = new Safe;
#         $compartment->deny_only();
#         $compartment->share_from('Text::BibTeX::Fix', ['$FIELD']);
#         $compartment->share('$_');
#         update($entry, $FIELD, sub { $compartment->reval($self->field_actions); });
#     }

    # Use bibtex month macros
    # Must be after field encoding because we use macros
    update($entry, 'month', {
      s/ "." ($|"-")/$1/; # Remove dots due to abbriviations
      my @x =
        .split(rx/<wb>/)
        .map({
          ($_ eq '/' || $_ eq '-' || $_ eq '--') and BibTeX::Value($_) or
          str2month($_) or
          /^ \d+ $/ and num2month($_) or
          print "WARNING: Suspect month: $_\n" and BibTeX::Value($_)});
      $_ = BibTeX::Value.new(@x)});

    # Omit fields we don't want
    # TODO: controled per type or with other fields or regex matching
    $entry.fields{$_}:exists and $entry.fields{$_}:delete for @.omit;
    $entry.fields{$_}:exists and $entry.fields{$_} eq '' and $entry.fields{$_}:delete for @.omit-empty;

    # Year
    check($entry, 'year', 'suspect year', { /^ \d\d\d\d $/ });

#     # Generate an entry key
#     # TODO: Formats: author/editor1.last year title/journal.abbriv
#     # TODO: Remove doi?
#     if (not defined $entry->key()) {
#         my ($name) = ($entry->names('author'), $entry->names('editor'));
#         $name = defined $name ?
#             purify_string(join("", $name->part('last'))) :
#             "anon";
#         my $year = $entry->exists('year') ? ":" . $entry->get('year') : "";
#         my $doi = $entry->exists('doi') ? ":" . $entry->get('doi') : "";
#         #$organization, or key
#         $entry->set_key($name . $year . $doi);
#     }

    # Put fields in a standard order
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

#     # Force comma or no comma after last field
#     my $str = $entry->print_s();
#     $str =~ s[(})(\s*}\s*)$][$1,$2] if $self->final_comma;
#     $str =~ s[(}\s*),(\s*}\s*)$][$1$2] if !$self->final_comma;

#     return $str;
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
