unit module Isbn;

# http://www.isbn-international.org/page/ranges
# https://www.isbn-international.org/range_file_generation
# http://pcn.loc.gov/isbncnvt.html

# NOTE: Must strip CRLF from first part of file

use XML;

enum IsbnType <Isbn13 Isbn10 Preserve>;

class Rule {
  has Str $.start;
  has Str $.end;
  has Int $.prefix;
  has Int $.group;
  has Int $.publisher;
}

sub rules {
  my $xml = from-xml-file('dep/RangeMessage.xml');
  my @groups = $xml.elements(:RECURSE(Inf), :TAG<Group>);
  do for @groups -> $group {
    my Str $prefix = $group.elements(:TAG<Prefix>, :SINGLE)[0].string;
    ($prefix ~~ /^ (\d+) "-" (\d+) $/) or die "Prefix: <$prefix>";
    my ($ean, $grp) = ($0, $1);
    $prefix ~~ s:g/"-"//;

    my $rules = $group.elements(:TAG<Rules>, :SINGLE);
    my @rules = $rules.elements(:TAG<Rule>);
    do for @rules -> $rule {
      my Str $range = $rule.elements(:TAG<Range>, :SINGLE)[0].string;
      my Int $length = $rule.elements(:TAG<Length>, :SINGLE)[0].string.Int;

      ($range ~~ /^ (\d+) "-" (\d+) $/) or die "Range: <$range>";
      my ($start, $end) = ($0, $1);

      Rule.new(
        start => $prefix ~ $start.substr(0, $length),
        end => $prefix ~ $end.substr(0, $length),
        prefix => $ean.chars,
        group => $grp.chars,
        publisher => $length);
    }
  }.flat
}

my @rules;

CHECK {
  @rules = rules();
}

sub hyphenate(Str $isbn --> Str) {
  die "Bad ISBN: $isbn" unless $isbn ~~ /^ <[0..9]> ** 12 <[0..9Xx]> $/;

  for @rules -> $rule {
    if ($rule.start le $isbn le $rule.end ) {
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
  die 'Cannot find ISBN: $isbn';
}

sub check-digit(Int $mod, @consts, Str $digits) { # TODO: Int @consts
  my Int @digits = (S:g/"-"// with $digits).split("", :skip-empty)».Int;
  my Int $sum = 0;
  for @consts.kv -> $i, $const {
    $sum += @digits[$i] * $const;
  }
  my Int $digit = ($mod - $sum % $mod) % $mod;
  return $digit == 10 ?? 'X' !! $digit;
}

sub check-digit10(Str $digits) { check-digit(11, (10,9,8,7,6,5,4,3,2), $digits); }
sub check-digit13(Str $digits) { check-digit(10, (1,3,1,3,1,3,1,3,1,3,1,3), $digits); }
sub check-digit-issn(Str $digits) { check-digit(11, (8,7,6,5,4,3,2), $digits); }

sub canonical-issn(Str $issn, IsbnType $type, Str $sep) is export {
  my $i = $issn;
  $i ~~ s:g/<[- ]>//;
  $i ~~ m/^ (\d\d\d\d) (\d\d\d(\d|"X")) $/ or die "Invalid ISSN due to wrong number of digits: $issn";
  $i = "$0-$1";
  my $check = check-digit-issn($issn);
  $i ~~ /$check$/ or die "Bad check digit in ISSN. Expecting $check in $issn";
  return $i;
}

# $isbn13: >0 (force to isbn 13), <0 (use isbn10 if possible), 0 (use whatever came in)
sub canonical-isbn(Str $isbn, IsbnType $type, Str $sep) is export {
  my Str $i = $isbn;
  $i ~~ s:g/<[- ]>//;
  my Bool $was-isbn13;

  if $i ~~ m/^ <[0..9]> ** 9 <[0..9Xx]> $/ {
      my $check = check-digit10($i);
      die "Bad check digit in ISBN10. Expecting $check in $i" unless $i ~~ /$check$/;
      $i = '978' ~ $i;
      $was-isbn13 = False;
  } elsif $i ~~ m/^ <[0..9]> ** 12 <[0..9Xx]> $/ {
      my $check = check-digit13($i);
      die "Bad check digit in ISBN13. Expecting $check in $i" unless $i ~~ /$check$/;
      $was-isbn13 = True;
  } else {
      die "Invalid digits or wrong number of digits in ISBN: $i";
  }

  # By this point we know it is a valid ISBN13 w/o dashes but with a possibly wrong check digit
  $i = hyphenate($i);

  if ($type == Isbn13 or $type == Preserve and $was-isbn13 or $i !~~ s/^ "978-" //) {
      my $check = check-digit13($i);
      $i ~~ s/.$/$check/;
  } else {
      my $check = check-digit10($i);
      $i ~~ s/.$/$check/;
  }

  $i ~~ s:g/"-"/$sep/;

  return $i;
}

#print canonical-isbn('0-201-53082-1', 0, ''), "\n";
#print canonical-isbn('0-201-53082-1', 0, '-'), "\n";
#print canonical-isbn('0-201-53082-1', 1, ''), "\n";
#print canonical-isbn('0-201-53082-1', 1, '-'), "\n";
#
#print canonical-isbn('978-1-56619-909-4', 0, ''), "\n";
#print canonical-isbn('978-1-56619-909-4', 0, '-'), "\n";
#print canonical-isbn('978-1-56619-909-4', 1, ''), "\n";
#print canonical-isbn('978-1-56619-909-4', 1, '-'), "\n";
#
#print canonical-isbn('979-10-00-12222-9', 0, ''), "\n";
#print canonical-isbn('979-10-00-12222-9', 0, '-'), "\n";
#print canonical-isbn('979-10-00-12222-9', 0, ' '), "\n";
#print canonical-isbn('979-10-00-12222-9', 1, ''), "\n";
#print canonical-isbn('979-10-00-12222-9', 1, '-'), "\n";
#print canonical-isbn('979-10-00-12222-9', 1, ' '), "\n";
