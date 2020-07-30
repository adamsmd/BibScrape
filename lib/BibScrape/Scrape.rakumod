unit module BibScrape::Scrape;

use HTML::Entity;
use Temp::Path;

use BibScrape::BibTeX;
use BibScrape::HtmlMeta;
use BibScrape::Month;
use BibScrape::Ris;
use BibScrape::WebDriver;

########

sub scrape(Str:D $url is copy --> BibScrape::BibTeX::Entry:D) is export {
  # Support 'doi:' as a url type
  $url ~~ s:i/^ 'doi:' /https:\/\/doi.org\//;

  web-driver-open();
  $web-driver.get($url);

  # Get the domain after following any redirects
  my Str:D $domain = ($web-driver%<current_url> ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"]).Str;
  my BibScrape::BibTeX::Entry:D $entry = do given $domain {
    when m[ « 'acm.org'             $] { scrape-acm(); }
    when m[ « 'cambridge.org'       $] { scrape-cambridge(); }
    when m[ « 'computer.org'        $] { scrape-ieee-computer(); }
    when m[ « 'ieeexplore.ieee.org' $] { scrape-ieee-explore(); }
    when m[ « 'iospress.com'        $] { scrape-ios-press(); }
    when m[ « 'jstor.org'           $] { scrape-jstor(); }
    when m[ « 'oup.com'             $] { scrape-oxford(); }
    when m[ « 'sciencedirect.com'   $]
      || m[ « 'elsevier.com'        $] { scrape-science-direct(); }
    when m[ « 'springer.com'        $] { scrape-springer(); }
    default { say "error: unknown domain: $domain"; }
  };

  web-driver-close();

  $entry;
}

########

sub scrape-acm(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  $web-driver.find_element_by_css_selector('a[data-title="Export Citation"]').click;
  my Str:D @citation-text =
    await({
      $web-driver.find_elements_by_css_selector("#exportCitation .csl-right-inline") })
        .map({ $_ % <text> });

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my Array:D[BibScrape::BibTeX::Entry:D] %entry = @citation-text
    .flatmap({ bibtex-parse($_).items })
    .grep({ $_ ~~ BibScrape::BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my BibScrape::BibTeX::Entry:D $entry = (%entry<False> // %entry<True>).head;

  # TODO: check SIGPLAN Notices
  ## HTML Meta
  #my $meta = html-meta-parse($web-driver);
  #html-meta-bibtex($entry, $meta);

  ## Abstract
  my Str:D $abstract = $web-driver
    .find_elements_by_css_selector(".abstractSection.abstractInFull")
    .reverse.head
    .get_property( 'innerHTML' );
  if $abstract ne '<p>No abstract available.</p>' {
    $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);
  }

  ## Author
  my Str:D $author = $web-driver.find_elements_by_css_selector( '.citation .author-name' )».get_attribute( 'title' ).join( ' and ' );
  $entry.fields<author> = BibScrape::BibTeX::Value.new($author);

  ## Title
  my Str:D $title = $web-driver.find_element_by_css_selector( '.citation__title' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Month
  #
  # ACM publication months are often inconsistent within the same page.
  # This is a best effort at picking the right month among these inconsistent results.
  if $entry.fields<issue_date>:exists {
    my Str:D $month = $entry.fields<issue_date>.simple-str.split(rx/\s+/).head;
    if str2month($month) {
      $entry.fields<month> = BibScrape::BibTeX::Value.new($month);
    }
  } elsif not $entry.fields<month>:exists {
    my Str:D $month =
      $web-driver.find_element_by_css_selector( '.book-meta + .cover-date' ).get_property( 'innerHTML' ).split(rx/\s+/).head;
    $entry.fields<month> = BibScrape::BibTeX::Value.new($month);
  }

  ## Keywords
  my Str:D @keywords =
    ($web-driver
      .find_elements_by_css_selector( '.tags-widget__content a' )
    )».get_property( 'innerHTML' )
    # ACM is inconsistent about the order in which these are returned.
    # We sort them so that we are deterministic.
    .sort;
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new(@keywords.join( '; ' ))
    if @keywords;

  ## Journal
  if $entry.type eq 'article' {
    my Str:D @journal = metas( 'citation_journal_title' );
    if @journal { $entry.fields<journal> = BibScrape::BibTeX::Value.new(@journal.head); }
  }

  ## Pages
  if $entry.fields<articleno>:exists
      and $entry.fields<numpages>:exists
      and not $entry.fields<pages>:exists {
    my Str:D $articleno = $entry.fields<articleno>.simple-str;
    my Str:D $numpages = $entry.fields<numpages>.simple-str;
    $entry.fields<pages> = BibScrape::BibTeX::Value.new("$articleno:1--$articleno:$numpages");
  }

  $entry;
}

sub scrape-cambridge(--> BibScrape::BibTeX::Entry:D) {
  # This must be before BibTeX otherwise Cambridge sometimes hangs due to an alert box
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'export-citation-product' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '[data-export-type="bibtex"]' ) }).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  html-meta-bibtex($entry, $meta, title => True, abstract => False);

  ## Abstract
  my Any:D @abstract = $web-driver.find_elements_by_class_name( 'abstract' );
  if @abstract {
    my Str:D $abstract = @abstract.head.get_property( 'innerHTML' );
    #my $abstract = meta( 'citation_abstract' );
    $abstract ~~ s:g/ "\n      \n      " //;
    $abstract ~~ s/^ '<div ' <-[>]>* '>'//;
    $abstract ~~ s/ '</div>' $//;
    $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract)
      unless $abstract ~~ /^ '//static.cambridge.org/content/id/urn' /;
  }

  ## ISSN
  my Str:D $issn = $web-driver.find_element_by_name( 'productIssn' ).get_attribute( 'value' );
  my Str:D $eissn = $web-driver.find_element_by_name( 'productEissn' ).get_attribute( 'value' );
  $entry.fields<issn> = BibScrape::BibTeX::Value.new("$issn (Print) $eissn (Online)");

  $entry;
}

sub scrape-ieee-computer(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  await({ $web-driver.find_element_by_css_selector( '.article-action-toolbar button' ) }).click;
  my Any:D $bibtex-link = await({ $web-driver.find_element_by_link_text( 'BibTex' ) });
  $web-driver.execute_script( 'arguments[0].removeAttribute("target")', $bibtex-link);
  $web-driver.find_element_by_link_text( 'BibTex' ).click;
  my Str:D $bibtex-text = await({ $web-driver.find_element_by_tag_name( 'pre' ) }).get_property( 'innerHTML' );
  $bibtex-text ~~ s/ "\{," /\{key,/;
  $bibtex-text = Blob.new($bibtex-text.ords).decode; # Fix UTF-8 encoding
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($bibtex-text).items.head;
  $web-driver.back();

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Authors
  my Str:D @authors =
    ($web-driver
      .find_elements_by_css_selector( 'a[href^="https://www.computer.org/csdl/search/default?type=author&"]' )
    )».get_property( 'innerHTML' );
  $entry.fields<author> = BibScrape::BibTeX::Value.new(@authors.join( ' and ' ));

  ## Affiliation
  my Str:D @affiliations =
    ($web-driver
      .find_elements_by_class_name( 'article-author-affiliations' )
    )».get_property( 'innerHTML' );
  $entry.fields<affiliation> = BibScrape::BibTeX::Value.new(@affiliations.join( ' and ' ))
    if @affiliations;

  ## Keywords
  update($entry, 'keywords', { s:g/ ';' \s* /; / });

  $entry;
}

sub scrape-ieee-explore(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  await({ $web-driver.find_element_by_tag_name( 'xpl-cite-this-modal' ) }).click;
  await({ $web-driver.find_element_by_link_text( 'BibTeX' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '.enable-abstract input' ) }).click;
  my Str:D $text = await({ $web-driver.find_element_by_class_name( 'ris-text' ) }).get_property( 'innerHTML' );
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($text).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## HTML body text
  my Str:D $body = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );

  ## Keywords
  my Str:D $keywords = $entry.fields<keywords>.simple-str;
  $keywords ~~ s:g/ ';' ' '* /; /;
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new($keywords);

  ## Author
  my Str:D $author = $entry.fields<author>.simple-str;
  $author ~~ s:g/ '{' (<-[}]>+) '}' /$0/;
  $entry.fields<author> = BibScrape::BibTeX::Value.new($author);

  ## ISSN
  if $body ~~ / '"issn":[{"format":"Print ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"},{"format":"Electronic ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}]' / {
    $entry.fields<issn> = BibScrape::BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## ISBN
  if $body ~~ / '"isbn":[{"format":"Print ISBN","value":"' (<[-0..9Xx]>+) '","isbnType":""},{"format":"CD","value":"' (<[-0..9Xx]>+) '","isbnType":""}]' / {
    $entry.fields<isbn> = BibScrape::BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## Publisher
  my Str:D $publisher =
    $web-driver
    .find_element_by_css_selector( '.publisher-info-container > span > span > span + span' )
    .get_property( 'innerHTML' );
  $entry.fields<publisher> = BibScrape::BibTeX::Value.new($publisher);

  ## Affiliation
  my Str:D $affiliation =
    ($body ~~ m:g/ '"affiliation":["' (<-["]>+) '"]' /)
    .map(sub (Match:D $match --> Str:D) { $match[0].Str }).join( ' and ' );
  $entry.fields<affiliation> = BibScrape::BibTeX::Value.new($affiliation)
    if $affiliation;

  ## Location
  my Str:D $location = (($body ~~ / '"confLoc":"' (<-["]>+) '"' /)[0] // '').Str;
  if $location {
    $location ~~ s/ ',' \s+ $//;
    $location ~~ s/ ', USA, USA' $/, USA/;
    $entry.fields<location> = BibScrape::BibTeX::Value.new($location.Str);
  }

  ## Conference date
  $body ~~ / '"conferenceDate":"' (<-["]>+) '"' /;
  $entry.fields<conference_date> = BibScrape::BibTeX::Value.new($0.Str) if $0;

  ## Abstract
  update($entry, 'abstract', { s/ '&lt;&gt;' $// });

  $entry;
}

sub scrape-ios-press(--> BibScrape::BibTeX::Entry:D) {
  ## RIS
  await({ $web-driver.find_element_by_class_name( 'p13n-cite' ) }).click;
  await({ $web-driver.find_element_by_class_name( 'btn-clear' ) }).click;
  my BibScrape::Ris::Ris:D $ris = ris-parse(read-downloads());
  my BibScrape::BibTeX::Entry:D $entry = bibtex-of-ris($ris);

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Title
  my Str:D $title =
    $web-driver.find_element_by_css_selector( '[data-p13n-title]' ).get_attribute( 'data-p13n-title' );
  $title ~~ s:g/ "\n" //; # Remove extra newlines
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Abstract
  my Str:D $abstract =
    $web-driver.find_element_by_css_selector( '[data-abstract]' ).get_attribute( 'data-abstract' );
  $abstract ~~ s:g/ (<[.!?]>) '  ' /$0\n\n/; # Insert missing paragraphs.  This is a heuristic solution.
  $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);

  ## ISSN
  if $ris.fields<SN>:exists {
    my Str:D $eissn = $ris.fields<SN>.head;
    my Str:D $pissn = meta( 'citation_issn' ).head;
    $entry.fields<issn> = BibScrape::BibTeX::Value.new("$pissn (Print) $eissn (Online)");
  }

  $entry;
}

sub scrape-jstor(--> BibScrape::BibTeX::Entry:D) {
  ## Remove overlay
  my Any:D @overlays = $web-driver.find_elements_by_class_name( 'reveal-overlay' );
  @overlays.map({ $web-driver.execute_script( 'arguments[0].removeAttribute("style")', $_) });

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'cite-this-item' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '[data-sc="text link: citation text"]' ) }).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Title
  my Str:D $title = $web-driver.find_element_by_class_name( 'title' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## DOI
  my Str:D $doi = $web-driver.find_element_by_css_selector( '[data-doi]' ).get_attribute( 'data-doi' );
  $entry.fields<doi> = BibScrape::BibTeX::Value.new($doi);

  ## ISSN
  update($entry, 'issn', { s/^ (<[0..9Xx]>+) ', ' (<[0..9Xx]>+) $/$0 (Print) $1 (Online)/ });

  ## Month
  my Str:D $month = $web-driver.find_element_by_class_name( 'src' ).get_property( 'innerHTML' );
  if $month ~~ / '(' (<alpha>+) / {
    $entry.fields<month> = BibScrape::BibTeX::Value.new($0.Str);
  }

  ## Publisher
  my Str:D $publisher = $web-driver.find_element_by_class_name( 'publisher-link' ).get_property( 'innerHTML' );
  $entry.fields<publisher> = BibScrape::BibTeX::Value.new($publisher);

  $entry;
}

sub scrape-oxford(--> BibScrape::BibTeX::Entry:D) {
  # BibTeX
  await({ $web-driver.find_element_by_class_name( 'js-cite-button' ) }).click;
  my Any:D $select-element = await({ $web-driver.find_element_by_id( 'selectFormat' ) });
  my Any:D $select = select($select-element);
  await({
    $select.select_by_visible_text( '.bibtex (BibTex)' );
    my Any:D $button = $web-driver.find_element_by_class_name( 'citation-download-link' );
    # Make sure the drop-down was populated
    $button.get_attribute( 'class' ) !~~ / « 'disabled' » /
      and $button }
  ).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, month => True, year => True);

  ## Title
  my Str:D $title = $web-driver.find_element_by_class_name( 'article-title-main' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Abstract
  my Str:D $abstract = $web-driver.find_element_by_class_name( 'abstract' ).get_property( 'innerHTML' );
  $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);

  ## ISSN
  my Str:D $issn = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );
  $issn ~~ / 'Print ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my Str:D $pissn = $0.Str;
  $issn ~~ / 'Online ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my Str:D $eissn = $0.Str;
  $entry.fields<issn> = BibScrape::BibTeX::Value.new("$pissn (Print) $eissn (Online)");

  ## Publisher
  update($entry, 'publisher', { s/^ 'Oxford Academic' $/Oxford University Press/ });

  $entry;
}

sub scrape-science-direct(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  await({
    $web-driver.find_element_by_id( 'export-citation' ).click;
    $web-driver.find_element_by_css_selector( 'button[aria-label="bibtex"]' ).click;
    True
  });
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, number => True);

  ## Title
  my Str:D $title = $web-driver.find_element_by_class_name( 'title-text' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Keywords
  my Str:D @keywords =
    ($web-driver
      .find_elements_by_css_selector( '.keywords-section > .keyword > span' )
    )».get_property( 'innerHTML' );
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my Str:D @abstract =
    ($web-driver
      .find_elements_by_css_selector( '.abstract > div' )
    )».get_property( 'innerHTML' );
  $entry.fields<abstract> = BibScrape::BibTeX::Value.new(@abstract.head)
    if @abstract;

  ## Series
  if $entry.fields<note> {
    $entry.fields<series> = $entry.fields<note>;
    $entry.fields<note>:delete;
  }

  $entry;
}

sub scrape-springer(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  my BibScrape::BibTeX::Entry:D $entry = BibScrape::BibTeX::Entry.new();
  # Use the BibTeX download if it is available
  if $web-driver.find_elements_by_id( 'button-Dropdown-citations-dropdown' ) {
    await({
      # Close the cookie/GDPR overlay
      try { $web-driver.find_element_by_class_name( 'optanon-alert-box-close' ).click; }
      # Scroll to the link.  (Otherwise WebDriver reports an error.)
      try { $web-driver.find_element_by_id( 'button-Dropdown-citations-dropdown' ).click; }
      # Click the actual link for BibTeX
      $web-driver.find_element_by_css_selector( '#Dropdown-citations-dropdown a[data-track-label="BIB"]' ).click;
      True });
    $entry = bibtex-parse(read-downloads).items.head;
  }

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  $entry.type = html-meta-type($meta);
  html-meta-bibtex($entry, $meta, author => True, publisher => True);

  for 'author', 'editor' -> Str:D $key {
    if $entry.fields{$key}:exists {
      my Str:D $names = $entry.fields{$key}.simple-str;
      $names ~~ s:g/ ' '* "\n" / /;
      $entry.fields{$key} = BibScrape::BibTeX::Value.new($names);
    }
  }

  ## ISBN
  my Str:D @pisbn = $web-driver.find_elements_by_id( 'print-isbn' )».get_property( 'innerHTML' );
  my Str:D @eisbn = $web-driver.find_elements_by_id( 'electronic-isbn' )».get_property( 'innerHTML' );
  $entry.fields<isbn> = BibScrape::BibTeX::Value.new("{@pisbn.head} (Print) {@eisbn.head} (Online)")
    if @pisbn and @eisbn;

  ## ISSN
  if $web-driver.find_element_by_tag_name( 'head' ).get_property( 'innerHTML' )
      ~~ / '{"eissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '","pissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}' / {
    my Str:D $issn = "$1 (Print) $0 (Online)";
    $entry.fields<issn> = BibScrape::BibTeX::Value.new($issn);
  }

  ## Series, Volume and ISSN
  #
  # Ugh, Springer doesn't have a reliable way to get the series, volume,
  # or ISSN.  Fortunately, this only happens for LNCS, so we hard code
  # it.
  if $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' ) ~~ / '(LNCS, volume ' (\d*) ')' / {
    $entry.fields<volume> = BibScrape::BibTeX::Value.new($0.Str);
    $entry.fields<series> = BibScrape::BibTeX::Value.new( 'Lecture Notes in Computer Science' );
  }

  ## Keywords
  my Str:D @keywords =
    $web-driver.find_elements_by_class_name( 'c-article-subject-list__subject' )».get_property( 'innerHTML' );
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my Any:D @abstract =
    ($web-driver.find_elements_by_class_name( 'Abstract' ),
      $web-driver.find_elements_by_id( 'Abs1-content' )).flat;
  if @abstract {
    my Str:D $abstract = @abstract.head.get_property( 'innerHTML' );
    $abstract ~~ s/^ '<h' <[23]> .*? '>Abstract</h' <[23]> '>' //;
    $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);
  }

  ## Publisher
  # The publisher field should not include the address
  update($entry, 'publisher', {
    my Str:D $address = $entry.fields<address>.defined ?? $entry.fields<address>.simple-str !! '';
    $_ = 'Springer'
      if $_ eq "Springer, $address";
  });

  $entry;
}
