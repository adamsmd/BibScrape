unit module Month;

use BibTeX;

my Str:D @long-names = <january february march april may june july august september october november december>;

my Str:D @macro-names = <jan feb mar apr may jun jul aug sep oct nov dec>;

my Str:D %months;
%months{@macro-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{@long-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{'sept'} = 'sep';

sub macro(Str $macro --> BibTeX::Piece) { $macro.defined ?? BibTeX::Piece.new($macro, BibTeX::Bare) !! BibTeX::Piece }

sub num2month(Str $num --> BibTeX::Piece) is export {
  $num ~~ m/^ \d+ $/ ?? macro(@macro-names[$num-1]) !! die "Invalid month number: $num"
}
sub str2month(Str $str --> BibTeX::Piece) is export { %months{$str.fc} ?? macro(%months{$str.fc}) !! BibTeX::Piece }
