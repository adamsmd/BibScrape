use BibTeX;

enum IsbnMedia <Print Online Both>;
enum IsbnType <Always13, Try10, Preserve>;

class Fix {
    ## INPUTS
    has List @.names; # List of List of BibTeX Names
    has File @.actions;

    ## OPERATING MODES
    has Bool $.debug;
    has Bool $.scrape;
    has Bool $.fix;

    ## GENERAL OPTIONS
    has MediaType $.isbn-media;
    has IsbnType $.isbn-type;
    has Str $.isbn-sep;
    has MediaType $.issn;
    has Bool $.final-comma;
    has Bool $.escape-acronyms;

    ## FIELD OPTIONS
    has Str @.fields = <
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location conference_date
      chapter pages articleno numpages
      edition day month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright>;
    has Str @.no-encode = <doi url eprint bib_scrape_url>;
    has Str @.no-collapse = <>;
    has Str @.omit = <>;
    has Str @.omit-empty = <abstract issn doi keywords>;
}

  #valid_names => [map {read_valid_names($_)} @NAME_FILE],
  #field_actions => join('\n', slurp_file(@FIELD_ACTION_FILE)),


sub update(Entry $entry, Str $field, $fun) {
  if $entry.fields{$field}:exists {
    $_ = $entry.fields{$field};
    $fun();
    if $_.defined { $entry.fields{$field} = $_; }
    else { delete $entry.fields{$field}; }
  }
}
