unit module BibScrape::BibTeX;

# Based on the grammar at https://github.com/aclements/biblib,
# but with some modifications to better meet our needs

use variables :D;

use ArrayHash;

enum Quotation <bare braces quotes>;
class Piece {
  has Str:D $.piece is required;
  has Quotation:D $.quotation is required;
  multi method new(Str:D $piece, Quotation:D $quotation = braces --> Piece:D) {
    self.bless(:$piece, :$quotation);
  }
  multi method new(Piece:D $piece --> Piece:D) {
    $piece;
  }
  multi method new(Int:D $piece --> Piece:D) {
    self.bless(:$piece.Str, :quotation(bare));
  }
  method Str(--> Str:D) {
    given $.quotation {
      when bare { $.piece }
      when braces { "\{$.piece\}" }
      when quotes { "\"$.piece\"" }
    }
  }
}
class Value {
  has Piece:D @.pieces is required;
  multi method new(Piece:D @pieces --> Value:D) {
    self.bless(:pieces(@pieces.map({ Piece.new($_) })));
  }
  multi method new($value where Value:D --> Value:D) { $value; }
  multi method new($piece where Piece:D | Int:D | Str:D --> Value:D) {
    Value.new(Array[Piece].new(Piece.new($piece)));
  }
  method Str(--> Str:D) {
    @.pieces».Str.join(" # ")
  }
  method simple-str(--> Str:D) {
    @.pieces.elems <= 1 ?? @.pieces».piece.join !! .Str
  }
};

class Item {}
class Ignored is Item is Str {}
class Comment is Item {
  method Str(--> Str:D) { '@comment' }
}
class Preamble is Item {
  has Value:D $.value is required;
  method Str(--> Str:D) {
    "\@preamble\{$.value\}"
  }
};
class String is Item {
  has Str:D $.key is required;
  has Value:D $.value is required;
  method Str(--> Str:D) {
    "\@string\{$.key = $.value\}"
  }
};
class Entry is Item {
  has Str:_ $.type is rw;
  has Str:_ $.key is rw;
  has ArrayHash:D #`(of Value) $.fields is rw = array-hash();
  method Str(--> Str:D) {
    "\@$.type\{$.key,\n" ~
    (map { "  {$_.key} = {$_.value},\n" }, $.fields.values(:array)).join ~
    "}"
  }
  method set-fields(@fields where { $_.all.value ~~ Value:D } --> Any:U) {
    $.fields = array-hash(@fields);
    return;
  }
}
class Database {
  has Item:D @.items is required;
  method Str(--> Str:D) { @.items».Str.join("\n\n"); }
}

grammar Grammar {
  token TOP { <bib-db> }
  regex bib-db { <clause>* }
  regex clause {
    <ignored> ||
    '@' <ws> [ <comment> || <preamble> || <string> || <entry> ]
  }

  token ws { <[\ \t\n]>* }

  token ignored { <-[@]>+ }

  regex comment { :i 'comment' }

  regex preamble {
    :i 'preamble' <ws>
    [  '{' <ws> <value> <ws> '}'
    || '(' <ws> <value> <ws> ')' ]
  }

  regex string {
    :i 'string' <ws>
    [  '{' <ws> <string-body> <ws> '}'
    || '(' <ws> <string-body> <ws> ')' ]
  }

  regex string-body { <ident> <ws> '=' <ws> <value> }

  regex entry {
    <ident> <ws>
    [  '{' <ws> <key> <ws> <entry-body> <ws> '}'
    || '(' <ws> $<key>=<key-paren> <ws> <entry-body> <ws> ')' ]
  }

  # Technically spaces shouldn't be allowed, but some publishers have them anyway
  token key { <-[,\t}\n]>* }

  token key-paren { <-[,\ \t\n]>* }

  regex entry-body { [',' <key-value>]* ','? }

  regex key-value { <ws> <ident> <ws> '=' <ws> <value> <ws> }

  ########

  regex value { <piece>* % [<ws> '#' <ws> ] }

  regex piece { <bare> || <braces> || <quotes> }

  regex bare { <[0..9]>+ || <ident> }

  regex braces { '{' (<balanced>*) '}' }

  regex quotes {
    '"' ([<!["]> # Fix syntax highlighting: "]
    <balanced>]*) '"'
  }

  regex balanced { '{' <balanced>* '}' || <-[{}]> }

  token ident {
    <![0..9]> [<![\ \t"#%'(),={}]>  # Fix syntax highlighting: "]
    <[\x20..\x7f]>]+
  }
}

class Actions {
  # Use these to head-off issues with different sources using different capitalizations
  has &.string-key-filter = { .fc };
  has &.entry-type-filter = { .fc };
  has &.entry-field-key-filter = { .fc };

  method TOP($/) { make Database.new(:items($<bib-db><clause>».made)); }
  method clause($/) { make ($<ignored> // $<comment> // $<preamble> // $<string> // $<entry>).made }
  method ignored($/) { make Ignored.new(:value($/)); }
  method comment($/) { make Comment.new(); }
  method preamble($/) { make Preamble.new(:value($<value>.made)); }
  method string($/) { make String.new(:key((&.string-key-filter)($/<string-body><ident>.Str)), :value($/<string-body><value>.made)); }
  method entry($/) { make Entry.new(:type((&.entry-type-filter)($/<ident>.Str)), :key($/<key>.Str), :fields(array-hash($/<entry-body>.made))); }
  method entry-body($/) { make $/<key-value>».made; }
  method key-value($/) { make ((&.entry-field-key-filter)($/<ident>.Str) => $/<value>.made); }

  method value($/) { make Value.new(Array[Piece].new($<piece>».made)); }
  method piece($/) { make ($<bare> // $<braces> // $<quotes>).made; }
  method bare($/) { make Piece.new(:piece($/.Str), :quotation(bare)); }
  method braces($/) { make Piece.new(:piece($/[0].Str), :quotation(braces)); }
  method quotes($/) { make Piece.new(:piece($/[0].Str), :quotation(quotes)); }
}

sub bibtex-parse(Str:D $str --> Database:D) is export {
  Grammar.parse($str, :actions(Actions.new)).made;
}

sub update(BibScrape::BibTeX::Entry:D $entry, Str:D $field, &fun --> Any:U) is export {
  if $entry.fields{$field}:exists {
    # Have to put this in a variable so s/// can modify it
    my Any:_ $value where Value:_ | Str:_ | Int:_ = $entry.fields{$field}.simple-str;
    &fun($value); # $value will be $_ in the block
    if $value.defined { $entry.fields{$field} = BibScrape::BibTeX::Value.new($value); }
    else { $entry.fields{$field}:delete; }
  }
  return;
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
  has Str:_ $.first;
  has Str:_ $.von;
  has Str:D $.last is required;
  has Str:_ $.jr;

  method Str(--> Str:D) {
    ($.von.defined ?? "$.von " !! "") ~
    ($.last) ~
    ($.jr.defined ?? ", $.jr" !! "") ~
    ($.first.defined ?? ", $.first" !! "")
  }
}
