unit module BibTeX::Months;

use BibTeX;

my @long-names = <january february march april may june july august september october november december>;

my @macro-names = <jan feb mar apr may jun jul aug sep oct nov dec>;

my %months;
%months{@macro-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{@long-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{'sept'} = 'sep';

sub macro(Str $macro) { $macro.defined ?? BibTeX::Piece.new($macro, BibTeX::Bare) !! Nil }

sub num2month(Str $num) is export {
  $num ~~ m/^ \d+ $/ ?? macro(@macro-names[$num-1]) !! die "Invalid month number: $num"
}
sub str2month(Str $str) is export { %months{$str.lc} && macro(%months{$str.lc}) }
