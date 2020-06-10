# Based on https://github.com/aclements/biblib

#  raku -I . -M BibTeX
# > g.parse('a@ foo { bar,}')

# TODO: case insensitive
grammar g {
    token TOP { <bib_db> }
    regex bib_db { <ignored> (<command_or_entry> <ignored>)* }

    token ignored { <-[@]>* }
    token ws { <[\ \t\n]>* } # TODO: space

    regex command_or_entry { '@' <ws> (<comment> || <preamble> || <string> || <entry> ) }

    regex comment { 'comment' }

    regex preamble { 'preamble' <ws> ( '{' <ws> <preamble_body> <ws> '}'
                         || '(' <ws> <preamble_body> <ws> ')' ) }

    regex preamble_body { <value> }

    regex string { 'string' <ws> ( '{' <ws> <string_body> <ws> '}'
                     || '(' <ws> <string_body> <ws> ')' ) }

    regex string_body { <ident> <ws> '=' <ws> <value> }

    regex entry { <ident> <ws> ( '{' <ws> <key> <ws> <entry_body>? <ws> '}'
                 || '(' <ws> <key_paren> <ws> <entry_body>? <ws> ')' )}

    token key { <-[,\ \t}\n]>* } # TODO: space

    token key_paren { <-[,\ \t\n]>* } # TODO: space

    regex entry_body { (',' <ws> <ident> <ws> '=' <ws> <value> <ws>)* ','? }

    regex value { <piece> (<ws> '#' <ws> <piecepiece>)* }

    regex piece
    { <[0..9]>+
    || '{' <balanced>* '}'
    || '"' (<-["]> <balanced>)* '"'
    || <ident> }

    regex balanced
    { '{' <balanced>* '}'
    || <-[{}]> }

    token ident { <-[0..9]> (<-[\ \t"#%'(),={}]> <[\x20..\x7f]>)+ }
}
