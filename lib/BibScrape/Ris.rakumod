unit module BibScrape::Ris;

use ArrayHash;

use BibScrape::BibTeX;
use BibScrape::Month;

class Ris {
  has Array:D[Str:D] %.fields;
}

sub ris-parse(Str:D $text --> Ris:D) is export {
#   $text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

  my Array:D[Str:D] %fields;
  my Str:D $last_key = "";
  for $text.split(rx/ ["\n" | "\r"]+ /) -> Str:D $line is copy {
    $line ~~ s:g/ "\r" | "\n" //;
    if $line ~~ /^ (<[A..Z0..9]>+) ' '* '-' ' '* (.*?) ' '* $/ {
      my Str:D ($key, $val) = ($0.Str, $1.Str);
      push %fields{$key}, $val;
      $last_key = $key;
    } elsif !$line {
      # Do nothing
    } else {
      # TODO: Test this code
      my Str:D $list = %fields{$last_key};
      $list[$list.end] ~= "\n" ~ $line;
    }
  }
  Ris.new(fields => %fields);
}

my Str:D %ris-types = <
    BOOK book
    CONF proceedings
    CHAP inbook
    CHAPTER inbook
    INCOL incollection
    JFULL journal
    JOUR article
    MGZN article
    PAMP booklet
    RPRT techreport
    REP techreport
    UNPB unpublished>;

sub ris-author(Array:D[Str:D] $names --> Str:D) {
  $names
    .map({ # Translate "last, first, suffix" to "von Last, Jr, First"
      s/ (.*) ',' (.*) ',' (.*) /$1,$3,$2/;
      / <-[, ]> / ?? $_ !! () })
    .join( ' and ' );
}

sub bibtex-of-ris(Ris:D $ris --> BibScrape::BibTeX::Entry:D) is export {
  my Array:D[Str:D] %ris = $ris.fields;
  my BibScrape::BibTeX::Entry:D $entry =
    BibScrape::BibTeX::Entry.new(:type<misc>, :key<ris>, :fields(array-hash.new()));

  my Regex:D $doi = rx/^ (\s* 'doi:' \s* \w+ \s+)? (.*) $/;

  sub set(Str:D $key, Str:_ $value --> Any:U) {
    $entry.fields{$key} = BibScrape::BibTeX::Value.new($value)
      if $value;
    return;
  }

  # A1|AU: author primary
  set( 'author', ris-author(%ris<A1> // %ris<AU> // []));
  # A2|ED: author secondary
  set( 'editor', ris-author(%ris<A2> // %ris<ED> // []));

  my Str:D %self;
  for %ris.kv -> Str:D $key, Array:D[Str:D] $value {
    %self{$key} = $value.join( '; ' );
  }

  # TY: ref type (INCOL|CHAPTER -> CHAP, REP -> RPRT)
  $entry.type =
    %ris-types{%self<TY> // ''}
    // ((!%self<TY>.defined or say "Unknown RIS TY: {%self<TY>}. Using misc.") and 'misc');
  # ID: reference id
  $entry.key = %self<ID>;
  # T1|TI|CT: title primary
  # BT: title primary (books and unpub), title secondary (otherwise)
  set( 'title', %self<T1> // %self<TI> // %self<CT> // ((%self<TY> // '') eq ( 'BOOK' | 'UNPB' )) && %self<BT>);
  set( 'booktitle', !((%self<TY> // '') eq ( 'BOOK' | 'UNPB' )) && %self<BT>);
  # T2: title secondary
  set( 'journal', %self<T2>);
  # T3: title series
  set( 'series', %self<T3>);

  # A3: author series
  # A[4-9]: author (undocumented)
  # Y1|PY: date primary
  my Str:_ ($year, $month, $day) = (%self<DA> // %self<PY> // %self<Y1> // '').split(rx/ "/" | "-" /);
  set( 'year', $year);
  $entry.fields<month> = BibScrape::BibTeX::Value.new(num2month($month))
    if $month;
  if (%self<C1>:exists) {
    %self<C1> ~~ / 'Full publication date: ' (\w+) '.'? ( ' ' \d+)? ', ' (\d+)/;
    ($month, $day, $year) = ($0, $1, $2);
    set( 'month', $month);
  }
  set( 'day', $day)
    if $day.defined;
  # Y2: date secondary

  # N1|AB: notes (skip leading doi)
  # N2: abstract (skip leading doi)
  (%self<N1> // %self<AB> // %self<N2> // '') ~~ $doi;
  set( 'abstract', $1.Str)
    if $1.Str.chars > 0;
  # KW: keyword. multiple
  set( 'keywords', %self<KW>)
    if %self<KW>:exists;
  # RP: reprint status (too complex for what we need)
  # JF|JO: periodical name, full
  # JA: periodical name, abbriviated
  # J1: periodical name, user abbriv 1
  # J2: periodical name, user abbriv 2
  set( 'journal', %self<JF> // %self<JO> // %self<JA> // %self<J1> // %self<J2>);
  # VL: volume number
  set( 'volume', %self<VL>);
  # IS|CP: issue
  set( 'number', %self<IS> // %self<CP>);
  # SP: start page (may contain end page)
  # EP: end page
  set( 'pages', %self<EP> ?? "{%self<SP>}--{%self<EP>}" !! %self<SP>); # Note that SP may contain end page
  # CY: city
  # PB: publisher
  set( 'publisher', %self<PB>);
  # SN: isbn or issn
  set( 'issn', %self<SN>)
    if %self<SN> and %self<SN> ~~ / « \d ** 4 '-' \d ** 4 » /;
  set( 'isbn', %self<SN>)
    if %self<SN> and %self<SN> ~~ / « ([\d | 'X'] <[- ]>*) ** 10..13 » /;
  #AD: address
  #AV: (unneeded)
  #M[1-3]: misc
  #U[1-5]: user
  # UR: multiple lines or separated by semi, may try for doi
  set( 'url', %self<UR>)
    if %self<UR>:exists;
  #L1: link to pdf, multiple lines or separated by semi
  #L2: link to text, multiple lines or separated by semi
  #L3: link to records
  #L4: link to images
  # DO|DOI: doi
  set( 'doi', %self<DO> // %self<DOI> // %self<M3> // (%self<N1> and %self<N1> ~~ $doi and $0));
  # ER: End of record

  $entry;
}

# #ABST		Abstract
# #INPR		In Press
# #JFULL		Journal (full)
# #SER		Serial (Book, Monograph)
# #THES	phdthesis/mastersthesis	Thesis/Dissertation
# IS
# CP|CY


# sub Text::RIS::bibtex {
#     my ($self) = @_;
#     $self = {%{$self->data}};

#     my $entry = new Text::BibTeX::Entry;
#     $entry->parse_s("\@misc{RIS,}", 0); # 1 for preserve values

#     $entry->set('author', ris_author(@{$self->{'A1'} || $self->{'AU'} || []}));
#     $entry->set('editor', ris_author(@{$self->{'A2'} || $self->{'ED'} || []}));
#     $entry->set('keywords', join " ; ", @{$self->{'KW'}}) if $self->{'KW'};
#     $entry->set('url', join " ; ", @{$self->{'UR'}}) if $self->{'UR'};

#     for (keys %$self) { $self->{$_} = join " ; ", @{$self->{$_}} }

#     my $doi = qr[^(\s*doi:\s*\w+\s+)?(.*)$]s;

#     $entry->set_type(exists $ris_types{$self->{'TY'}} ?
#         $ris_types{$self->{'TY'}} :
#         (print STDERR "Unknown RIS TY: $self->{'TY'}. Using misc.\n" and 'misc'));
#     #ID: ref id
#     $entry->set('title', $self->{'T1'} || $self->{'TI'} || $self->{'CT'} || (
#         ($self->{'TY'} eq 'BOOK' || $self->{'TY'} eq 'UNPB') && $self->{'BT'}));
#     $entry->set('booktitle', $self->{'T2'} || (
#         !($self->{'TY'} eq 'BOOK' || $self->{'TY'} eq 'UNPB') && $self->{'BT'}));
#     $entry->set('series', $self->{'T3'}); # check
#     #A3: author series
#     #A[4-9]: author (undocumented)
#     my ($year, $month, $day) = split m[/|-], ($self->{'DA'} || $self->{'PY'} || $self->{'Y1'});
#     $entry->set('year', $year);
#     $entry->set('month', num2month($month)->[1]) if $month;

#     if (exists $self->{'C1'}) {
#         ($month, $day, $year) = $self->{'C1'} =~ m[Full publication date: (\w+)\.?( \d+)?, (\d+)];
#         $entry->set('month', $month);
#     }

#     $entry->set('day', $day);
#     #Y2: date secondary
#     ($self->{'N1'} || $self->{'AB'} || $self->{'N2'} || "") =~ $doi;
#     $entry->set('abstract', $2) if length($2);
#     #RP: reprint status (too complex for what we need)
#     $entry->set('journal', ($self->{'JF'} || $self->{'JO'} || $self->{'JA'} ||
#                             $self->{'J1'} || $self->{'J2'}));
#     $entry->set('volume', $self->{'VL'});
#     $entry->set('number', $self->{'IS'} || $self->{'CP'});
#     $entry->set('pages', $self->{'EP'} ?
#         "$self->{'SP'}--$self->{'EP'}" :
#         $self->{'SP'}); # start page may contain end page
#     #CY: city
#     $entry->set('publisher', $self->{'PB'});
#     $entry->set('issn', $1) if
#         $self->{'SN'} && $self->{'SN'} =~ m[\b(\d{4}-\d{4})\b];
#     $entry->set('isbn', $self->{'SN'}) if
#         $self->{'SN'} && $self->{'SN'} =~ m[\b((\d|X)[- ]*){10,13}\b];
#     #AD: address
#     #AV: (unneeded)
#     #M[1-3]: misc
#     #U[1-5]: user
#     #L1: link to pdf, multiple lines or separated by semi
#     #L2: link to text, multiple lines or separated by semi
#     #L3: link to records
#     #L4: link to images
#     $entry->set('doi', $self->{'DO'} || $self->{'DOI'} || $self->{'M3'} || (
#         $self->{'N1'} && $self->{'N1'} =~ $doi && $1));
#     #ER

#     for ($entry->fieldlist) { $entry->delete($_) if not defined $entry->get($_) }

#     return $entry;
# }

