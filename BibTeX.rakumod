unit module BibTeX;

# Based on https://github.com/aclements/biblib

#  raku -I . -M BibTeX
# > g.parse('a@ foo { bar,}')

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
    multi method new(Str $piece, Quotation $quotation = Braces) {
        self.bless(piece => $piece, quotation => $quotation);
    }
    method Str {
        given $.quotation {
            when Bare { $.piece }
            when Braces { "\{$.piece\}" }
            when Quotes { "\"$.piece\"" }
        }
    }
}
class Value {
    has Piece @.pieces;
    method new(*@pieces) {
        self.bless(pieces => map { Piece.new($_) }, @pieces);
    }
    method Str {
        @.pieces».Str.join(" # ")
    }
};
use MONKEY-TYPING;
augment class Str {
    method Value { Value.new(Piece.new(self)); }
}

class Item {}
class Ignored is Item is Str {}
class Comment is Item {
    method Str { '@comment' }
}
class Preamble is Item {
    has Value $.value;
    method Str {
        "\@preamble\{$.value\}"
    }
};
class String is Item {
    has Str $.key;
    has Value $.value;
    method Str {
        "\@string\{$.key = $.value\}"
    }
};
class Entry is Item {
    has Str $.type;
    has Str $.key;
    has Value %.fields;
    has Str @.field-order;
    method Str {
        # TODO: check that all keys are in field order
        "\@$.type\{$.key,\n" ~
        (map { "  $_ = %.fields{$_},\n"}, @.field-order).join ~
        "}"
    }
}
class Database {
    has Item @.items;
    method Str { @.items».Str.join("\n\n"); }
}

# TODO: case insensitive
grammar Grammar {
    token TOP { <bib_db> }
    regex bib_db { <clause>* }
    regex clause {
        <ignored> ||
        [ '@' <ws> [ <comment> || <preamble> || <string> || <entry> ]] }

    token ws { <[\ \t\n]>* }

    token ignored { <-[@]>+ }

    regex comment { 'comment' }

    regex preamble { 'preamble' <ws> [ '{' <ws> <value> <ws> '}'
                            || '(' <ws> <value> <ws> ')' ] }

    regex string { 'string' <ws> [ '{' <ws> <string_body> <ws> '}'
                        || '(' <ws> <string_body> <ws> ')' ] }

    regex string_body { <ident> <ws> '=' <ws> <value> }

    regex entry { <ident> <ws> [ '{' <ws> <key> <ws> <entry_body> <ws> '}'
                    || '(' <ws> $<key>=<key_paren> <ws> <entry_body> <ws> ')' ]}

    token key { <-[,\ \t}\n]>* }

    token key_paren { <-[,\ \t\n]>* }

    regex entry_body { [',' <key_value>]* ','? }

    regex key_value { <ws> <ident> <ws> '=' <ws> <value> <ws> }

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

    regex balanced
    { '{' <balanced>* '}'
    || <-[{}]> }

    token ident
    { <![0..9]> [<![\ \t"#%'(),={}]>  # Fix syntax highlighting: "]
        <[\x20..\x7f]>]+ } #"])}
}

class Actions {
    method TOP($/) { make Database.new(items => $<bib_db><clause>».made); }
    method clause($/) { make ($<ignored> // $<comment> // $<preamble> // $<string> // $<entry>).made }
    method ignored($/) { make Ignored.new(value => $/); }
    method comment($/) { make Comment.new(); }
    method preamble($/) { make Preamble.new(value => $<value>.made); }
    method string($/) { make String.new(key => $/<string_body><ident>.Str, value => $/<string_body><value>.made); }
    method entry($/) {
        my @fields = $/<entry_body>.made;
        make Entry.new(type => $/<ident>.Str, key => $/<key>.Str, fields => %@fields, field-order => @fields».key); }
    method entry_body($/) { make $/<key_value>».made; }
    method key_value($/) { make ($/<ident>.Str => $/<value>.made); }

    method value($/) { make Value.new(@($<piece>».made)); }
    method piece($/) { make ($<bare> // $<braces> // $<quotes>).made; }
    method bare($/) { make Piece.new(piece => $/.Str, quotation => Bare); }
    method braces($/) { make Piece.new(piece => $/[0].Str, quotation => Braces); }
    method quotes($/) { make Piece.new(piece => $/[0].Str, quotation => Quotes); }
}

sub parse_bibtex(Str $str) is export {
    Grammar.parse($str, actions => Actions).made;
}

#split
#names
