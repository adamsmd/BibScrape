use BibTeX;

      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location conference_date
      chapter pages articleno numpages
      edition day month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright;

enum IsbnMedia <Print Online Both>;
enum IsbnType <Always13, Try10, Preserve

class Fix {
  has Str @.valid_names; ????;

  has Bool $.debug = False;
  has IsbnMode $.isbn = Both;
  has IsbnType $.isbn13 = Preserve;
  has Str $.isbn_sep = "-";
  has IsbnMode $.issn = Both;
  has Bool $.final_comma = True;
  has Bool $.escape_acronyms = True;

  has Str @.known_fields;
  has Unit %.no_encode = <doi url eprint bib_scrape_url>;
  has Unit %.no_collapse = <>;
  has Unit %.omit = <>;
  has Unit %.omit_empty = <>;
  has Str $.field_actions;

}

    valid_names => [map {read_valid_names($_)} @NAME_FILE],
    field_actions => join('\n', slurp_file(@FIELD_ACTION_FILE)),


sub update(Entry $entry, Str $field, $fun) {
  if $entry.fields{$field}:exists {
    $_ = $entry.fields{$field};
    $fun();
    if $_.defined { $entry.fields{$field} = $_; }
    else { delete $entry.fields{$field}; }
  }
}

#sub update {
#    my ($entry, $field, $fun) = @_;
#    if ($entry->exists($field)) {
#        $_ = $entry->get($field);
#        &$fun();
#        if (defined $_) { $entry->set($field, $_); }
#        else { $entry->delete($field); }
#    }
#}
