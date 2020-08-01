unit module BibScrape::Isbn;

# http://pcn.loc.gov/isbncnvt.html
# https://www.isbn-international.org/range_file_generation
# https://www.isbn-international.org/export_rangemessage.xml

use XML;

enum IsbnType <Isbn13 Isbn10 Preserve>;

class Rule {
  has Str:D $.start is required;
  has Str:D $.end is required;
  has Int:D $.group is required;
  has Int:D $.prefix is required;
  has Int:D $.publisher is required;
}

sub rules(--> Array:D[Rule:D]) {

  my Str:D $xml-str =
    (%?RESOURCES<export_rangemessage.xml> // $*PROGRAM.add( '../resources/export_rangemessage.xml' ))
    .slurp;
  # NOTE: due to a bug in the XML module, must strip tags containing '.'
  $xml-str ~~ s/ '<EAN.UCCPrefixes>' [.|\r]* '</EAN.UCCPrefixes>' //;
  my XML::Document:D $xml = from-xml($xml-str);
  my XML::Element:D @groups = $xml.elements(:RECURSE(Inf), :TAG<Group>);
  do for @groups -> XML::Element:D $group {
    my Str:D $prefix = $group.elements(:TAG<Prefix>, :SINGLE)[0].string;
    ($prefix ~~ /^ (\d+) '-' (\d+) $/) or die "Prefix: <$prefix>";
    my Str:D ($ean, $grp) = ($0.Str, $1.Str);
    $prefix ~~ s:g/ '-' //;

    my XML::Element:D $rules = $group.elements(:TAG<Rules>, :SINGLE);
    my XML::Element:D @rules = $rules.elements(:TAG<Rule>);
    do for @rules -> XML::Element:D $rule {
      my Str:D $range = $rule.elements(:TAG<Range>, :SINGLE)[0].string;
      my Int:D $length = $rule.elements(:TAG<Length>, :SINGLE)[0].string.Int;

      ($range ~~ /^ (\d+) '-' (\d+) $/) or die "Range: <$range>";
      my Str:D ($start, $end) = ($0.Str, $1.Str);

      Rule.new(
        start => $prefix ~ $start.substr(0, $length),
        end => $prefix ~ $end.substr(0, $length),
        prefix => $ean.chars,
        group => $grp.chars,
        publisher => $length);
    }
  }.flat.Array
}

my Rule:D @rules;

CHECK {
  @rules = rules();
}

sub hyphenate(Str:D $isbn --> Str:D) {
  die "Bad ISBN: $isbn" unless $isbn ~~ /^ <[0..9]> ** 12 <[0..9Xx]> $/;

  for @rules -> Rule:D $rule {
    if $rule.start le $isbn le $rule.end {
      return S/^
        (<[0..9]> ** {$rule.prefix})
        (<[0..9]> ** {$rule.group})
        (<[0..9]> ** {$rule.publisher})
        (<[0..9]>*) # item
        (<[0..9Xx]>) # checksum
        $
        /$0-$1-$2-$3-$4/
        with $isbn;
    }
  }
  die "Cannot find ISBN: $isbn";
}

sub check-digit(Int:D $mod, @consts where { $_.all ~~ Int:D }, Str:D $digits is copy --> Str:D) {
  $digits ~~ s:g/ '-' //;
  $digits ~~ s/ . $//;
  my Int:D @digits = $digits.split("", :skip-empty)».Int;
  my Int:D $sum = 0;
  for @consts.kv -> Int:D $i, Int:D $const {
    $sum += @digits[$i] * $const;
  }
  my Int:D $digit = ($mod - $sum % $mod) % $mod;
  return $digit == 10 ?? 'X' !! $digit.Str;
}

sub check-digit10(Str:D $digits --> Str:D) { check-digit(11, (10,9,8,7,6,5,4,3,2), $digits); }
sub check-digit13(Str:D $digits --> Str:D) { check-digit(10, (1,3,1,3,1,3,1,3,1,3,1,3), $digits); }
sub check-digit-issn(Str:D $digits --> Str:D) { check-digit(11, (8,7,6,5,4,3,2), $digits); }

sub canonical-issn(Str:D $issn, IsbnType:D $type, Str:D $sep --> Str:D) is export {
  my Str:D $i = $issn; # Copy so errors can use the original
  $i ~~ s:g/ <[- ]> //;
  $i ~~ m/^ (\d\d\d\d) (\d\d\d(\d|"X")) $/ or die "Invalid ISSN due to wrong number of digits: $issn";
  $i = "$0-$1";
  my Str:D $check = check-digit-issn($issn);
  $i ~~ / $check $/ or die "Bad check digit in ISSN. Expecting $check in $issn";
  return $i;
}

sub canonical-isbn(Str:D $isbn, IsbnType:D $type, Str:D $sep --> Str:D) is export {
  my Str:D $i = $isbn; # Copy so errors can use the original
  $i ~~ s:g/ <[- ]> //;
  my Bool:D $was-isbn13 = False;

  if $i ~~ m/^ <[0..9]> ** 9 <[0..9Xx]> $/ {
    my Str:D $check = check-digit10($i);
    die "Bad check digit in ISBN-10. Expecting $check in $isbn" unless $i ~~ / $check $/;
    $i = '978' ~ $i;
    $was-isbn13 = False;
  } elsif $i ~~ m/^ <[0..9]> ** 12 <[0..9Xx]> $/ {
    my Str:D $check = check-digit13($i);
    die "Bad check digit in ISBN-13. Expecting $check in $isbn" unless $i ~~ / $check $/;
    $was-isbn13 = True;
  } else {
    die "Invalid digits or wrong number of digits in ISBN: $isbn";
  }

  # By this point we know it is a valid ISBN-13 w/o dashes but with a possibly wrong check digit
  $i = hyphenate($i);

  if ($type eqv Isbn13
      or $type eqv Preserve and $was-isbn13
      or $i !~~ s/^ '978-' //) {
    my Str:D $check = check-digit13($i);
    $i ~~ s/ . $/$check/;
  } else {
    my Str:D $check = check-digit10($i);
    $i ~~ s/ . $/$check/;
  }

  $i ~~ s:g/ '-' /$sep/;

  return $i;
}

#print canonical-isbn('0-201-53082-1', Preserve, ''), "\n";
#print canonical-isbn('0-201-53082-1', Preserve, '-'), "\n";
#print canonical-isbn('0-201-53082-1', Isbn13, ''), "\n";
#print canonical-isbn('0-201-53082-1', Isbn13, '-'), "\n";
#
#print canonical-isbn('978-1-56619-909-4', Preserve, ''), "\n";
#print canonical-isbn('978-1-56619-909-4', Preserve, '-'), "\n";
#print canonical-isbn('978-1-56619-909-4', Isbn13, ''), "\n";
#print canonical-isbn('978-1-56619-909-4', Isbn13, '-'), "\n";
#
#print canonical-isbn('979-10-00-12222-9', Preserve, ''), "\n";
#print canonical-isbn('979-10-00-12222-9', Preserve, '-'), "\n";
#print canonical-isbn('979-10-00-12222-9', Preserve, ' '), "\n";
#print canonical-isbn('979-10-00-12222-9', Isbn13, ''), "\n";
#print canonical-isbn('979-10-00-12222-9', Isbn13, '-'), "\n";
#print canonical-isbn('979-10-00-12222-9', Isbn13, ' '), "\n";
