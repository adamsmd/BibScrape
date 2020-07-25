unit module BibTeX;

# Based on the grammar at https://github.com/aclements/biblib,
# but with some modifications to better meet our needs

use ArrayHash;

enum Quotation <Bare Braces Quotes>;
class Piece {
  has Str $.piece;
  has Quotation $.quotation;
  multi method new(Int $piece --> Piece:D) {
    self.bless(piece => $piece.Str, quotation => Bare);
  }
  multi method new(Piece $piece --> Piece:D) {
    $piece;
  }
  multi method new(Str $piece, Quotation $quotation = Braces --> Piece:D) {
    self.bless(piece => $piece, quotation => $quotation);
  }
  method Str(--> Str:D) {
    given $.quotation {
      when Bare { $.piece }
      when Braces { "\{$.piece\}" }
      when Quotes { "\"$.piece\"" }
    }
  }
}
class Value {
  has Piece @.pieces;
  multi method new(*@pieces --> Value:D) {
    self.bless(pieces => map { Piece.new($_) }, @pieces);
  }
  multi method new(Value $value --> Value) { $value; }
  method Str(--> Str:D) {
    @.pieces».Str.join(" # ")
  }
  method simple-str(--> Str:D) {
    if (@.pieces.elems <= 1) {
      @.pieces».piece.join
    } else {
      .Str;
    }
  }
};

class Item {}
class Ignored is Item is Str {}
class Comment is Item {
  method Str(--> Str:D) { '@comment' }
}
class Preamble is Item {
  has Value $.value;
  method Str(--> Str:D) {
    "\@preamble\{$.value\}"
  }
};
class String is Item {
  has Str $.key;
  has Value $.value;
  method Str(--> Str:D) {
    "\@string\{$.key = $.value\}"
  }
};
class Entry is Item {
  has Str $.type is rw;
  has Str $.key is rw;
  has ArrayHash $.fields is rw = array-hash(); # Maps Str to Value
  method Str(--> Str:D) {
    "\@$.type\{$.key,\n" ~
    (map { "  {$_.key} = {$_.value},\n" }, $.fields.values(:array)).join ~
    "}"
  }
}
class Database {
  has Item @.items;
  method Str(--> Str:D) { @.items».Str.join("\n\n"); }
}

grammar Grammar {
  token TOP { <bib-db> }
  regex bib-db { <clause>* }
  regex clause {
    <ignored> ||
    [ '@' <ws> [ <comment> || <preamble> || <string> || <entry> ]] }

  token ws { <[\ \t\n]>* }

  token ignored { <-[@]>+ }

  regex comment { :i 'comment' }

  regex preamble { :i 'preamble' <ws> [ '{' <ws> <value> <ws> '}'
                                     || '(' <ws> <value> <ws> ')' ] }

  regex string { :i 'string' <ws> [ '{' <ws> <string-body> <ws> '}'
                                 || '(' <ws> <string-body> <ws> ')' ] }

  regex string-body { <ident> <ws> '=' <ws> <value> }

  regex entry { <ident> <ws> [ '{' <ws> <key> <ws> <entry-body> <ws> '}'
                            || '(' <ws> $<key>=<key-paren> <ws> <entry-body> <ws> ')' ] }

  # Technically spaces shouldn't be allowed, but some publishers have them anyway
  token key { <-[,\t}\n]>* }

  token key-paren { <-[,\ \t\n]>* }

  regex entry-body { [',' <key-value>]* ','? }

  regex key-value { <ws> <ident> <ws> '=' <ws> <value> <ws> }

  ########

  regex value { <piece>* % [<ws> '#' <ws> ] }

  regex piece
  { <bare>
  || <braces>
  || <quotes> }

  regex bare { <[0..9]>+ || <ident> }

  regex braces { '{' (<balanced>*) '}' }

  regex quotes {
    '"' ([<!["]> # Fix syntax highlighting: "]
    <balanced>]*) '"' }

  regex balanced { '{' <balanced>* '}' || <-[{}]> }

  token ident {
    <![0..9]> [<![\ \t"#%'(),={}]>  # Fix syntax highlighting: "]
    <[\x20..\x7f]>]+ }
}

class Actions {
  # Use these to head-off issues with different sources using different capitalizations
  has &.string-key-filter = { .fc };
  has &.entry-type-filter = { .fc };
  has &.entry-field-key-filter = { .fc };

  method TOP($/) { make Database.new(items => $<bib-db><clause>».made); }
  method clause($/) { make ($<ignored> // $<comment> // $<preamble> // $<string> // $<entry>).made }
  method ignored($/) { make Ignored.new(value => $/); }
  method comment($/) { make Comment.new(); }
  method preamble($/) { make Preamble.new(value => $<value>.made); }
  method string($/) { make String.new(key => (&.string-key-filter)($/<string-body><ident>.Str), value => $/<string-body><value>.made); }
  method entry($/) { make Entry.new(type => (&.entry-type-filter)($/<ident>.Str), key => $/<key>.Str, fields => array-hash($/<entry-body>.made)); }
  method entry-body($/) { make $/<key-value>».made; }
  method key-value($/) { make ((&.entry-field-key-filter)($/<ident>.Str) => $/<value>.made); }

  method value($/) { make Value.new(@($<piece>».made)); }
  method piece($/) { make ($<bare> // $<braces> // $<quotes>).made; }
  method bare($/) { make Piece.new(piece => $/.Str, quotation => Bare); }
  method braces($/) { make Piece.new(piece => $/[0].Str, quotation => Braces); }
  method quotes($/) { make Piece.new(piece => $/[0].Str, quotation => Quotes); }
}

sub bibtex-parse(Str $str --> BibTeX::Database:D) is export {
  Grammar.parse($str, actions => Actions.new).made;
}

grammar Names {
  regex w { <[\ \t~-]> }

  regex balanced  { '{' <balanced>* '}' || <-[{}]> }
  regex balanced2 { '{' <balanced>* '}' || <-[{}\ ~,-]> }

  regex names { :i [<.w>* $<name>=[<.balanced>+?] [<.w> | ","]*]* % [ \s+ 'and' <?before \s+> ] }
  regex name { [ \s* <part> \s* ]+ % ',' }
  regex part { [ <tok> ]+ % [ <w> <.w>* ] }
  regex tok { <.balanced2>* }
}

class Name {
  has Str $.first;
  has Str $.von;
  has Str $.last;
  has Str $.jr;

  method Str(--> Str:D) {
    ($.von.defined ?? "$.von " !! "") ~
    ($.last) ~
    ($.jr.defined ?? ", $.jr" !! "") ~
    ($.first.defined ?? ", $.first" !! "")
  }
}
