unit module BibScrape::Scrape;

use variables :D;

use XML;

use BibScrape::BibTeX;
use BibScrape::HtmlMeta;
use BibScrape::Month;
use BibScrape::Ris;
use BibScrape::WebDriver;

########

my BibScrape::WebDriver::WebDriver:_ $web-driver;

END { if $web-driver.defined { $web-driver.close(); } }

sub scrape(Str:D $url is copy, Bool:D :$window, Num:D :$timeout --> BibScrape::BibTeX::Entry:D) is export {
  $web-driver =
    BibScrape::WebDriver::WebDriver.new(:$window, :$timeout);
  LEAVE { $web-driver.close(); }
  $web-driver.set_page_load_timeout($timeout);

  my BibScrape::BibTeX::Entry:D $entry = dispatch($url);

  $entry.fields<bib_scrape_url> = BibScrape::BibTeX::Value.new($url);

  # Remove undefined fields
  $entry.set-fields($entry.fields.grep({ $_ }));

  $entry;
}

sub dispatch(Str:D $url is copy --> BibScrape::BibTeX::Entry:D) {
  # Support 'doi:' as a url type
  $url ~~ s:i/^ 'doi:' [ 'http' 's'? '://' 'dx.'? 'doi.org/' ]? /https:\/\/doi.org\//;
  $web-driver.get($url);

  # Get the domain after following any redirects
  my Str:D $domain = ($web-driver%<current_url> ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"]).Str;
  return do given $domain {
    when m[ « 'acm.org'             $] { scrape-acm(); }
    when m[ « 'arxiv.org'           $] { scrape-arxiv(); }
    when m[ « 'cambridge.org'       $] { scrape-cambridge(); }
    when m[ « 'computer.org'        $] { scrape-ieee-computer(); }
    when m[ « 'ieeexplore.ieee.org' $] { scrape-ieee-explore(); }
    when m[ « 'iospress.com'        $] { scrape-ios-press(); }
    when m[ « 'jstor.org'           $] { scrape-jstor(); }
    when m[ « 'oup.com'             $] { scrape-oxford(); }
    when m[ « 'sciencedirect.com'   $]
      || m[ « 'elsevier.com'        $] { scrape-science-direct(); }
    when m[ « 'link.springer.com'   $] { scrape-springer(); }
    default { die "Unsupported domain: $domain"; }
  };
}

########

sub scrape-acm(--> BibScrape::BibTeX::Entry:D) {
  if 'Association for Computing Machinery' ne
      $web-driver.find_element_by_class_name( 'publisher__name' ).get_property( 'innerHTML' ) {
    my Str:D @url = $web-driver.find_elements_by_class_name( 'issue-item__doi' )».get_attribute( 'href' );
    if @url { return dispatch(@url.head); }
    else { say "WARNING: Non-ACM paper at ACM link, and could not find link to actual publisher"; }
  }

  ## BibTeX
  $web-driver.find_element_by_css_selector( 'a[data-title="Export Citation"]').click;
  my Str:D @citation-text =
    await({
      $web-driver.find_elements_by_css_selector( '#exportCitation .csl-right-inline' ) })
        .map({ $_ % <text> });

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my Array:D[BibScrape::BibTeX::Entry:D] %entry = @citation-text
    .flatmap({ bibtex-parse($_).items })
    .grep({ $_ ~~ BibScrape::BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my BibScrape::BibTeX::Entry:D $entry = (%entry<False> // %entry<True>).head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, :!journal #`(avoid SIGPLAN Notices));

  ## Abstract
  my Str:_ $abstract = $web-driver
    .find_elements_by_css_selector( '.abstractSection.abstractInFull' )
    .reverse.head
    .get_property( 'innerHTML' );
  if $abstract.defined and $abstract ne '<p>No abstract available.</p>' {
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
  my Str:D @keywords = $web-driver.find_elements_by_css_selector( '.tags-widget__content a' )».get_property( 'innerHTML' );
  # ACM is inconsistent about the order in which these are returned.
  # We sort them so that we are deterministic.
  @keywords .= sort;
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new(@keywords.join( '; ' ))
    if @keywords;

  ## Journal
  if $entry.type eq 'article' {
    my Str:D @journal = $web-driver.metas( 'citation_journal_title' );
    $entry.fields<journal> = BibScrape::BibTeX::Value.new(@journal.head)
      if @journal;
  }

  my Str:D %issn =
    $web-driver
      .find_elements_by_class_name( 'cover-image__details' )
      .classify({ .find_elements_by_class_name( 'journal-meta' ).so })
      .map({ $_.key => $_.value.head.get_property( 'innerHTML' ) });
  if %issn {
    my Str:D $issn = %issn<False> // %issn<True>;
    my Str:_ $pissn =
      $issn ~~ / '<span class="bold">ISSN:</span><span class="space">' (.*?) '</span>' /
        ?? $0.Str !! Str;
    my Str:_ $eissn =
      $issn ~~ / '<span class="bold">EISSN:</span><span class="space">' (.*?) '</span>' /
        ?? $0.Str !! Str;
    if $pissn and $eissn {
      $entry.fields<issn> = BibScrape::BibTeX::Value.new("$pissn (Print) $eissn (Online)");
    }
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

# format_bibtex_arxiv in https://github.com/mattbierbaum/arxiv-bib-overlay/blob/master/src/ui/CiteModal.tsx
sub scrape-arxiv(--> BibScrape::BibTeX::Entry:D) {
  # Ensure we are at the "abstract" page
  $web-driver%<current_url> ~~ / '://arxiv.org/' (<-[/]>+) '/' (.*) $/;
  if $0 ne 'abs' {
    $web-driver.get("https://arxiv.org/abs/$1");
  }

  # Id
  $web-driver%<current_url> ~~ / '://arxiv.org/' (<-[/]>+) '/' (.*) $/;
  my Str:D $id = $1.Str;

  # Use the arXiv API to download meta-data
  #$web-driver.get("https://export.arxiv.org/api/query?id_list=$id"); # Causes a timeout
  #$web-driver.execute_script( 'window.location.href = arguments[0]', "https://export.arxiv.org/api/query?id_list=$id");
  $web-driver.execute_script( 'window.open(arguments[0], "_self")', "https://export.arxiv.org/api/query?id_list=$id");
  my Str:D $xml-string = $web-driver.read-downloads();
  my XML::Document:D $xml = from-xml($xml-string);

  my XML::Element:D @doi = $xml.getElementsByTagName('arxiv:doi');
  if @doi and Backtrace.new.map({$_.subname}).grep({$_ eq 'scrape-arxiv'}) <= 1 {
    # Use publisher page if it exists
    dispatch('doi:' ~ @doi.head.contents».text.join(''));
  } else {
    my XML::Element:D $xml-entry = $xml.getElementsByTagName('entry').head;

    sub text(XML::Element:D $element, Str:D $str --> Str:D) {
      my XML::Element:D @elements = $element.getElementsByTagName($str);
      if @elements {
        @elements.head.contents».text.join('');
      } else {
        '';
      }
    }

    # BibTeX object
    my BibScrape::BibTeX::Entry:D $entry = BibScrape::BibTeX::Entry.new(:type('misc'), :key("arxiv.$id"));

    # Title
    my Str:D $title = text($xml-entry, 'title');
    $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

    # Author
    my XML::Element:D @authors = $xml-entry.getElementsByTagName('author');
    my Str:D $author = @authors.map({text($_, 'name')}).join( ' and ' );
      # author=<author><name> 	One for each author. Has child element <name> containing the author name.
    $entry.fields<author> = BibScrape::BibTeX::Value.new($author);

    # Affiliation
    my Str:D $affiliation = @authors.map({text($_, 'arxiv:affiliation')}).grep({$_ ne ''}).join( ' and ' );
      # affiliation=<author><arxiv:affiliation> 	The author's affiliation included as a subelement of <author> if present.
    $entry.fields<affiliation> = BibScrape::BibTeX::Value.new($affiliation)
      if $affiliation ne '';

    # How published
    $entry.fields<howpublished> = BibScrape::BibTeX::Value.new('arXiv.org');

    # Year, month and day
    my Str:D $published = text($xml-entry, 'published');
    $published ~~ /^ (\d ** 4) '-' (\d ** 2) '-' (\d ** 2) 'T'/;
    my (Str:D $year, Str:D $month, Str:D $day) = ($0.Str, $1.Str, $2.Str);
      # year, month, day = <published> 	The date that version 1 of the article was submitted.
      # <updated> 	The date that the retrieved version of the article was submitted. Same as <published> if the retrieved version is version 1.
    $entry.fields<year> = BibScrape::BibTeX::Value.new($year);
    $entry.fields<month> = BibScrape::BibTeX::Value.new($month);
    $entry.fields<day> = BibScrape::BibTeX::Value.new($day);

    my Str:D $doi = $xml-entry.elements(:TAG<link>, :title<doi>).map({$_.attribs<href>}).join(';');
    $entry.fields<doi> = BibScrape::BibTeX::Value.new($doi)
      if $doi ne '';

    # Eprint
    my Str:D $eprint = $id;
    $entry.fields<eprint> = BibScrape::BibTeX::Value.new($eprint);

    # Archive prefix
    $entry.fields<archiveprefix> = BibScrape::BibTeX::Value.new('arXiv');

    # Primary class
    my Str:D $primaryClass = $xml-entry.getElementsByTagName('arxiv:primary_category').head.attribs<term>;
    $entry.fields<primaryclass> = BibScrape::BibTeX::Value.new($primaryClass);

    # Abstract
    my Str:D $abstract = text($xml-entry, 'summary');
    $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);

    # The following XML elements are ignored
    # <link> 	Can be up to 3 given url's associated with this article.
    # <category> 	The arXiv or ACM or MSC category for an article if present.
    # <arxiv:comment> 	The authors comment if present.
    # <arxiv:journal_ref> 	A journal reference if present.
    # <arxiv:doi> 	A url for the resolved DOI to an external resource if present.

    $entry
  }
}

sub scrape-cambridge(--> BibScrape::BibTeX::Entry:D) {
  if $web-driver%<current_url> ~~
      /^ 'http' 's'? '://www.cambridge.org/core/services/aop-cambridge-core/content/view/' ( 'S' \d+) $/ {
    $web-driver.get("https://doi.org/10.1017/$0");
  }

  # This must be before BibTeX otherwise Cambridge sometimes hangs due to an alert box
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'export-citation-product' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '[data-export-type="bibtex"]' ) }).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($web-driver.read-downloads()).items.head;

  ## HTML Meta
  html-meta-bibtex($entry, $meta, :!abstract);

  ## Title
  my Str:D $title =
    await({ $web-driver.find_element_by_class_name( 'article-title' ) }).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Abstract
  my #`(Inline::Python::PythonObject:D) @abstract = $web-driver.find_elements_by_class_name( 'abstract' );
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
  my Str:D $pissn = $web-driver.find_element_by_name( 'productIssn' ).get_attribute( 'value' );
  my Str:D $eissn = $web-driver.find_element_by_name( 'productEissn' ).get_attribute( 'value' );
  $entry.fields<issn> = BibScrape::BibTeX::Value.new("$pissn (Print) $eissn (Online)");

  $entry;
}

sub scrape-ieee-computer(--> BibScrape::BibTeX::Entry:D) {
  ## BibTeX
  await({ $web-driver.find_element_by_css_selector( '.article-action-toolbar button' ) }).click;
  my #`(Inline::Python::PythonObject:D) $bibtex-link = await({ $web-driver.find_element_by_link_text( 'BibTex' ) });
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
    ($web-driver.find_elements_by_css_selector( 'a[href^="https://www.computer.org/csdl/search/default?type=author&"]' )
    )».get_property( 'innerHTML' );
  $entry.fields<author> = BibScrape::BibTeX::Value.new(@authors.join( ' and ' ));

  ## Affiliation
  my Str:D @affiliations =
    ($web-driver.find_elements_by_class_name( 'article-author-affiliations' ))».get_property( 'innerHTML' );
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
  if $body ~~ /
      '"issn":[{"format":"Print ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)
      '"},{"format":"Electronic ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}]' / {
    $entry.fields<issn> = BibScrape::BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## ISBN
  if $body ~~ /
      '"isbn":[{"format":"Print ISBN","value":"' (<[-0..9Xx]>+)
      '","isbnType":""},{"format":"CD","value":"' (<[-0..9Xx]>+) '","isbnType":""}]' / {
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
  my BibScrape::Ris::Ris:D $ris = ris-parse($web-driver.read-downloads());
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
    my Str:D $pissn = $web-driver.meta( 'citation_issn' ).head;
    $entry.fields<issn> = BibScrape::BibTeX::Value.new("$pissn (Print) $eissn (Online)");
  }

  $entry;
}

sub scrape-jstor(--> BibScrape::BibTeX::Entry:D) {
  ## Remove overlay
  my #`(Inline::Python::PythonObject:D) @overlays = $web-driver.find_elements_by_class_name( 'reveal-overlay' );
  @overlays.map({ $web-driver.execute_script( 'arguments[0].removeAttribute("style")', $_) });

  ## BibTeX
  # Note that on-campus is different than off-campus
  await({ $web-driver.find_elements_by_css_selector( '[data-qa="cite-this-item"]' )
          || $web-driver.find_elements_by_class_name( 'cite-this-item' ) }).head.click;
  await({ $web-driver.find_element_by_css_selector( '[data-sc="text link: citation text"]' ) }).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($web-driver.read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Title
  # Note that on-campus is different than off-campus
  my Str:D $title =
    ($web-driver.find_elements_by_class_name( 'item-title' )
      || $web-driver.find_elements_by_class_name( 'title-font' )).head.get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## DOI
  my Str:D $doi = $web-driver.find_element_by_css_selector( '[data-doi]' ).get_attribute( 'data-doi' );
  $entry.fields<doi> = BibScrape::BibTeX::Value.new($doi);

  ## ISSN
  update($entry, 'issn', { s/^ (<[0..9Xx]>+) ', ' (<[0..9Xx]>+) $/$0 (Print) $1 (Online)/ });

  ## Month
  my Str:D $month =
    ($web-driver.find_elements_by_css_selector( '.turn-away-content__article-summary-journal a' )
      || $web-driver.find_elements_by_class_name( 'src' )).head.get_property( 'innerHTML' );
  if $month ~~ / '(' (<alpha>+) / {
    $entry.fields<month> = BibScrape::BibTeX::Value.new($0.Str);
  }

  ## Publisher
  # Note that on-campus is different than off-campus
  my Str:D $publisher =
    do if $web-driver.find_elements_by_class_name( 'turn-away-content__article-summary-journal' ) {
      my Str:D $text =
        $web-driver.find_element_by_class_name( 'turn-away-content__article-summary-journal' ).get_property( 'innerHTML' );
      $text ~~ / 'Published By: ' (<-[<]>*) /;
      $0.Str
    } else {
      $web-driver.find_element_by_class_name( 'publisher-link' ).get_property( 'innerHTML' )
    };
  $entry.fields<publisher> = BibScrape::BibTeX::Value.new($publisher);

  $entry;
}

sub scrape-oxford(--> BibScrape::BibTeX::Entry:D) {
  say "WARNING: Oxford imposes rate limiting.  BibScrape might hang if you try multiple papers in a row.";

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'js-cite-button' ) }).click;
  my #`(Inline::Python::PythonObject:D) $select-element = await({ $web-driver.find_element_by_id( 'selectFormat' ) });
  my #`(Inline::Python::PythonObject:D) $select = $web-driver.select($select-element);
  await({
    $select.select_by_visible_text( '.bibtex (BibTex)' );
    my #`(Inline::Python::PythonObject:D) $button = $web-driver.find_element_by_class_name( 'citation-download-link' );
    # Make sure the drop-down was populated
    $button.get_attribute( 'class' ) !~~ / « 'disabled' » /
      and $button }
  ).click;
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($web-driver.read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, :month, :year);

  ## Title
  my Str:D $title = $web-driver.find_element_by_class_name( 'article-title-main' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Abstract
  my Str:D $abstract = $web-driver.find_element_by_class_name( 'abstract' ).get_property( 'innerHTML' );
  $entry.fields<abstract> = BibScrape::BibTeX::Value.new($abstract);

  ## ISSN
  my Str:D $issn = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );
  my Str:D $pissn = ($issn ~~ / 'Print ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/)[0].Str;
  my Str:D $eissn = ($issn ~~ / 'Online ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/)[0].Str;
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
  my BibScrape::BibTeX::Entry:D $entry = bibtex-parse($web-driver.read-downloads()).items.head;

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, :number);

  ## Title
  my Str:D $title = $web-driver.find_element_by_class_name( 'title-text' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibScrape::BibTeX::Value.new($title);

  ## Keywords
  my Str:D @keywords =
    ($web-driver.find_elements_by_css_selector( '.keywords-section > .keyword > span' ))».get_property( 'innerHTML' );
  $entry.fields<keywords> = BibScrape::BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my Str:D @abstract =
    ($web-driver.find_elements_by_css_selector( '.abstract > div' ))».get_property( 'innerHTML' );
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
      try { $web-driver.find_element_by_id( 'onetrust-accept-btn-handler' ).click; }
      # Scroll to the link.  (Otherwise WebDriver reports an error.)
      try { $web-driver.find_element_by_id( 'button-Dropdown-citations-dropdown' ).click; }
      # Click the actual link for BibTeX
      $web-driver.find_element_by_css_selector( '#Dropdown-citations-dropdown a[data-track-label="BIB"]' ).click;
      True });
    $entry = bibtex-parse($web-driver.read-downloads).items.head;
  }

  ## HTML Meta
  my BibScrape::HtmlMeta::HtmlMeta:D $meta = html-meta-parse($web-driver);
  $entry.type = html-meta-type($meta);
  html-meta-bibtex($entry, $meta, :publisher);

  if $entry.fields<editor>:exists {
    my Str:D $names = $entry.fields<editor>.simple-str;
    $names ~~ s:g/ ' '* "\n" / /;
    $entry.fields<editor> = BibScrape::BibTeX::Value.new($names);
  }

  ## Author
  my Any:D @authors =
    $web-driver.find_elements_by_css_selector(
      '.c-article-authors-search__title,
        .c-article-author-institutional-author__name,
        .authors-affiliations__name')
    .map({
      $_.get_attribute( 'class' ) ~~ / « 'c-article-author-institutional-author__name' » /
        ?? '{' ~ $_.get_property( 'innerHTML' ) ~ '}'
        !! $_.get_property( 'innerHTML' ) });
  @authors.map({ s:g/ '&nbsp;' / /; });
  $entry.fields<author> = BibScrape::BibTeX::Value.new(@authors.join( ' and ' ));

  ## ISBN
  my Str:D @pisbn = $web-driver.find_elements_by_id( 'print-isbn' )».get_property( 'innerHTML' );
  my Str:D @eisbn = $web-driver.find_elements_by_id( 'electronic-isbn' )».get_property( 'innerHTML' );
  $entry.fields<isbn> = BibScrape::BibTeX::Value.new("{@pisbn.head} (Print) {@eisbn.head} (Online)")
    if @pisbn and @eisbn;

  ## ISSN
  if $web-driver.find_element_by_tag_name( 'head' ).get_property( 'innerHTML' )
      ~~ / '{"eissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '","pissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}' / {
    $entry.fields<issn> = BibScrape::BibTeX::Value.new("$1 (Print) $0 (Online)");
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
  my #`(Inline::Python::PythonObject:D) @abstract =
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
