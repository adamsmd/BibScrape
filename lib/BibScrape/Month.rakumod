unit module BibScrape::Month;

use variables :D;

use BibScrape::BibTeX;

my Str:D @long-names = <january february march april may june july august september october november december>;

my Str:D @macro-names = <jan feb mar apr may jun jul aug sep oct nov dec>;

my Str:D %months;
%months{@macro-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{@long-names[$_]} = @macro-names[$_] for @long-names.keys;
%months{'sept'} = 'sep';

sub wrap(Str:D $macro --> BibScrape::BibTeX::Piece:_) {
  $macro.defined
    ?? BibScrape::BibTeX::Piece.new($macro, BibScrape::BibTeX::bare)
    !! BibScrape::BibTeX::Piece
}

sub num2month(Str:D $num --> BibScrape::BibTeX::Piece:D) is export {
  $num ~~ m/^ \d+ $/
    ?? wrap(@macro-names[$num-1])
    !! die "Invalid month number: $num"
}

sub str2month(Str:D $str --> BibScrape::BibTeX::Piece:_) is export {
  %months{$str.fc}
    ?? wrap(%months{$str.fc})
    !! BibScrape::BibTeX::Piece
}
