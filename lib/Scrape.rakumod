unit module Scrape;

use HTML::Entity;

use BibTeX;
use HtmlMeta;
use Month;
use Ris;

sub infix:<%>($obj, Str $attr) { $obj.__getattribute__($attr); }

########

my $web-driver;
my $python;

sub init() {
  use Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)
  unless $web-driver.defined {
    $python = Inline::Python.new;
    $python.run("
import sys
import os

from selenium import webdriver
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
from selenium.webdriver.firefox import firefox_profile
from selenium.webdriver.firefox import options
from selenium.webdriver.support import ui

def web_driver():
  profile = firefox_profile.FirefoxProfile()
  #profile.set_preference('browser.download.panel.shown', False)
  #profile.set_preference('browser.helperApps.neverAsk.openFile',
  #  'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.helperApps.neverAsk.saveToDisk',
    'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.download.folderList', 2)
  profile.set_preference('browser.download.dir', os.getcwd() + '/downloads')

  opt = options.Options()
  # Run without showing a browser window
  opt.headless = True

  return webdriver.Firefox(
    firefox_profile = profile,
    options = opt,
    service_log_path = '/dev/null')

def select(element):
  return ui.Select(element)
");
  }
}

sub open() {
  init();
  close();
  $web-driver = $python.call('__main__', 'web_driver');
}

sub close() {
  if $web-driver.defined {
    $web-driver.quit();
    $web-driver = Any;
  }
}

END {
  close();
}

sub meta(Str $name --> Str) {
  $web-driver.find_element_by_css_selector( "meta[name=\"$name\"]" ).get_attribute( 'content' );
}

sub metas(Str $name --> Seq) {
  $web-driver.find_elements_by_css_selector( "meta[name=\"$name\"]" ).map({ .get_attribute( 'content' ) });
}

sub update(BibTeX::Entry $entry, Str $field, &fun) is export {
  if $entry.fields{$field}:exists {
    # Have to put this in a variable so s/// can modify it
    my $value = $entry.fields{$field}.simple-str;
    &fun($value); # $value will be $_ in the block
    if $value.defined { $entry.fields{$field} = BibTeX::Value.new($value); }
    else { $entry.fields{$field}:delete; }
  }
}

########

my IO $downloads = 'downloads'.IO;

sub read-downloads {
  for 0..10 {
    my @files = $downloads.dir;
    if @files { return @files.head.slurp }
    sleep 0.1;
  }
  die "Could not find downloaded file";
}

sub await(&block) {
  my constant $timeout = 30.0;
  my constant $sleep = 0.5;
  my $result;
  my $start = now.Num;
  while True {
    $result = &block();
    if $result { return $result }
    if now - $start > $timeout {
      die "Timeout while waiting for the browser"
    }
    sleep $sleep;
    CATCH { default { sleep $sleep; } }
  }
}

########

sub scrape(Str $url is copy --> BibTeX::Entry:D) is export {
  # Support 'doi:' as a url type
  $url ~~ s:i/^ 'doi:' /https:\/\/doi.org\//;

  $downloads.dir».unlink;
  open();
  $web-driver.get($url);

  # Get the domain after following any redirects
  my Str $domain = ($web-driver%<current_url> ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"]).Str;
  my BibTeX::Entry $entry = do given $domain {
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

  close();

  $entry;
}

########

sub scrape-acm(--> BibTeX::Entry) {
  ## BibTeX
  $web-driver.find_element_by_css_selector('a[data-title="Export Citation"]').click;
  my Str @citation-text = await({ $web-driver.find_elements_by_css_selector("#exportCitation .csl-right-inline") }).map({ $_ % <text> });

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my Array %entry = @citation-text
    .flatmap({ bibtex-parse($_).items })
    .grep({ $_ ~~ BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my BibTeX::Entry $entry = (%entry<False> // %entry<True>).head;

  # TODO: check SIGPLAN Notices
  ## HTML Meta
  #my $meta = html-meta-parse($web-driver);
  #html-meta-bibtex($entry, $meta);

  ## Abstract
  my Str $abstract = $web-driver
    .find_elements_by_css_selector(".abstractSection.abstractInFull")
    .reverse.head
    .get_property('innerHTML');
  if $abstract.defined and $abstract ne '<p>No abstract available.</p>' {
    # Fix the double HTML encoding of the abstract (Bug in ACM?)
    $entry.fields<abstract> = BibTeX::Value.new($abstract);
  }

  ## Author
  my Str $author = $web-driver.find_elements_by_css_selector( '.citation .author-name' )».get_attribute( 'title' ).join( ' and ' );
  $entry.fields<author> = BibTeX::Value.new($author);

  ## Title
  my Str $title = $web-driver.find_element_by_css_selector( '.citation__title' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibTeX::Value.new($title);

  ## Month
  #
  # ACM publication months are often inconsistent within the same page.
  # This is a best effort at picking the right month among these inconsistent results.
  if $entry.fields<issue_date>:exists {
    my Str $month = $entry.fields<issue_date>.simple-str.split(rx/\s+/).head;
    if str2month($month) {
      $entry.fields<month> = BibTeX::Value.new($month);
    }
  } elsif not $entry.fields<month>:exists {
    my Str $month = $web-driver.find_element_by_css_selector( '.book-meta + .cover-date' ).get_property( 'innerHTML' ).split(rx/\s+/).head;
    $entry.fields<month> = BibTeX::Value.new($month);
  }

  ## Keywords
  my @keywords = $web-driver.find_elements_by_css_selector( '.tags-widget__content a' );
  @keywords = @keywords».get_property( 'innerHTML' );
  # ACM is inconsistent about the order in which these are returned.
  # We sort them so that we are deterministic.
  @keywords = @keywords.sort;
  $entry.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' )) if @keywords;

  ## Journal
  if $entry.type eq 'article' {
    my @journal = metas( 'citation_journal_title' );
    if @journal { $entry.fields<journal> = BibTeX::Value.new(@journal.head); }
  }

  ## Pages
  if $entry.fields<articleno>:exists and $entry.fields<numpages>:exists
      and not $entry.fields<pages>:exists {
    my Str $articleno = $entry.fields<articleno>.simple-str;
    my Str $numpages = $entry.fields<numpages>.simple-str;
    $entry.fields<pages> = BibTeX::Value.new("$articleno:1--$articleno:$numpages");
  }

  $entry;
}

sub scrape-cambridge(--> BibTeX::Entry) {
  # This must be before BibTeX otherwise Cambridge sometimes hangs due to an alert box
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'export-citation-product' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '[data-export-type="bibtex"]' ) }).click;
  my BibTeX::Entry $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  html-meta-bibtex($entry, $meta, title => True, abstract => False);

  ## Abstract
  my @abstract = $web-driver.find_elements_by_class_name( 'abstract' );
  if @abstract {
    my Str $abstract = @abstract.head.get_property( 'innerHTML' );
    #my $abstract = meta( 'citation_abstract' );
    $abstract ~~ s:g/ "\n      \n      " //;
    $abstract ~~ s/^ '<div ' <-[>]>* '>'//;
    $abstract ~~ s/ '</div>' $//;
    $entry.fields<abstract> = BibTeX::Value.new($abstract)
      unless $abstract ~~ /^ '//static.cambridge.org/content/id/urn' /;
  }

  ## ISSN
  my Str $issn = $web-driver.find_element_by_name( 'productIssn' ).get_attribute( 'value' );
  my Str $eissn = $web-driver.find_element_by_name( 'productEissn' ).get_attribute( 'value' );
  $entry.fields<issn> = BibTeX::Value.new("$issn (Print) $eissn (Online)");

  $entry;
}

sub scrape-ieee-computer {
  ## BibTeX
  await({ $web-driver.find_element_by_css_selector( '.article-action-toolbar button' ) }).click;
  my $bibtex-link = await({ $web-driver.find_element_by_link_text( 'BibTex' ) });
  $web-driver.execute_script( 'arguments[0].removeAttribute("target")', $bibtex-link);
  $web-driver.find_element_by_link_text( 'BibTex' ).click;
  my Str $bibtex-text = await({ $web-driver.find_element_by_tag_name( 'pre' ) }).get_property( 'innerHTML' );
  $bibtex-text ~~ s/ "\{," /\{key,/;
  $bibtex-text = Blob.new($bibtex-text.ords).decode; # Fix UTF-8 encoding
  my BibTeX::Entry $entry = bibtex-parse($bibtex-text).items.head;
  $web-driver.back();

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Authors
  my Str @authors = $web-driver.find_elements_by_css_selector( 'a[href^="https://www.computer.org/csdl/search/default?type=author&"]' ).map({ .get_property( 'innerHTML' ) });
  $entry.fields<author> = BibTeX::Value.new(@authors.join( ' and ' ));

  ## Affiliation
  my Str @affiliations = $web-driver.find_elements_by_class_name( 'article-author-affiliations' ).map({ .get_property( 'innerHTML' ) });
  $entry.fields<affiliation> = BibTeX::Value.new(@affiliations.join( ' and ' )) if @affiliations;

  ## Keywords
  update($entry, 'keywords', { s:g/ ';' \s* /; / });

  $entry;
}

sub scrape-ieee-explore {
  ## BibTeX
  await({ $web-driver.find_element_by_tag_name( 'xpl-cite-this-modal' ) }).click;
  await({ $web-driver.find_element_by_link_text( 'BibTeX' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '.enable-abstract input' ) }).click;
  my Str $text = await({ $web-driver.find_element_by_class_name( 'ris-text' ) }).get_property( 'innerHTML' );
  my BibTeX::Entry $entry = bibtex-parse($text).items.head;

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## HTML body text
  my Str $body = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );

  ## Keywords
  my Str $keywords = $entry.fields<keywords>.simple-str;
  $keywords ~~ s:g/ ';' ' '* /; /;
  $entry.fields<keywords> = BibTeX::Value.new($keywords);

  ## Author
  my Str $author = $entry.fields<author>.simple-str;
  $author ~~ s:g/ '{' (<-[}]>+) '}' /$0/;
  $entry.fields<author> = BibTeX::Value.new($author);

  ## ISSN
  if $body ~~ / '"issn":[{"format":"Print ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"},{"format":"Electronic ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}]' / {
    $entry.fields<issn> = BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## ISBN
  if $body ~~ / '"isbn":[{"format":"Print ISBN","value":"' (<[-0..9Xx]>+) '","isbnType":""},{"format":"CD","value":"' (<[-0..9Xx]>+) '","isbnType":""}]' / {
    $entry.fields<isbn> = BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## Publisher
  my Str $publisher = $web-driver.find_element_by_class_name( 'publisher-info-label' ).get_property( 'innerHTML' );
  $publisher ~~ s/^ \s* 'Publisher: ' //;
  $entry.fields<publisher> = BibTeX::Value.new($publisher);

  ## Affiliation
  my Str $affiliation =
    ($body ~~ m:g/ '"affiliation":"' (<-["]>+) '"' /)
    .map(sub ($k, $v) { $v[0].Str }).join( ' and ' );
  $entry.fields<affiliation> = BibTeX::Value.new($affiliation) if $affiliation;

  ## Location
  my Str $location = (($body ~~ / '"confLoc":"' (<-["]>+) '"' /)[0] // '').Str;
  if $location {
    $location ~~ s/ ',' \s+ $//;
    $location ~~ s/ ', USA, USA' $/, USA/;
    $entry.fields<location> = BibTeX::Value.new($location.Str);
  }

  ## Conference date
  $body ~~ / '"conferenceDate":"' (<-["]>+) '"' /;
  $entry.fields<conference_date> = BibTeX::Value.new($0.Str) if $0;

  ## Abstract
  update($entry, 'abstract', { s/ '&lt;&gt;' $// });

  $entry;
}

sub scrape-ios-press(--> BibTeX::Entry) {
  ## RIS
  await({ $web-driver.find_element_by_class_name( 'p13n-cite' ) }).click;
  await({ $web-driver.find_element_by_class_name( 'btn-clear' ) }).click;
  my Ris::Ris $ris = ris-parse(read-downloads());
  my BibTeX::Entry $entry = bibtex-of-ris($ris);

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Title
  my Str $title = $web-driver.find_element_by_css_selector( '[data-p13n-title]' ).get_attribute( 'data-p13n-title' );
  $title ~~ s:g/ "\n" //; # Remove extra newlines
  $entry.fields<title> = BibTeX::Value.new($title);

  ## Abstract
  my Str $abstract = $web-driver.find_element_by_css_selector( '[data-abstract]' ).get_attribute( 'data-abstract' );
  $abstract ~~ s:g/ (<[.!?]>) '  ' /$0\n\n/; # Insert missing paragraphs.  This is a heuristic solution.
  $entry.fields<abstract> = BibTeX::Value.new($abstract);

  ## ISSN
  if $ris.fields<SN>:exists {
    my Str $eissn = $ris.fields<SN>.head;
    my Str $pissn = meta( 'citation_issn' ).head;
    $entry.fields<issn> = BibTeX::Value.new("$pissn (Print) $eissn (Online)");
  }

  $entry;
}

sub scrape-jstor {
  ## Remove overlay
  my @overlays = $web-driver.find_elements_by_class_name( 'reveal-overlay' );
  @overlays.map({ $web-driver.execute_script( 'arguments[0].removeAttribute("style")', $_) });

  ## BibTeX
  await({ $web-driver.find_element_by_class_name( 'cite-this-item' ) }).click;
  await({ $web-driver.find_element_by_css_selector( '[data-sc="text link: citation text"]' ) }).click;
  my BibTeX::Entry $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta);

  ## Title
  my Str $title = $web-driver.find_element_by_class_name( 'title' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibTeX::Value.new($title);

  ## DOI
  my Str $doi = $web-driver.find_element_by_css_selector( '[data-doi]' ).get_attribute( 'data-doi' );
  $entry.fields<doi> = BibTeX::Value.new($doi);

  ## ISSN
  update($entry, 'issn', { s/^ (<[0..9Xx]>+) ', ' (<[0..9Xx]>+) $/$0 (Print) $1 (Online)/ });

  ## Month
  my Str $month = $web-driver.find_element_by_class_name( 'src' ).get_property( 'innerHTML' );
  if $month ~~ / '(' (<alpha>+) / {
    $entry.fields<month> = BibTeX::Value.new($0.Str);
  }

  ## Publisher
  my Str $publisher = $web-driver.find_element_by_class_name( 'publisher-link' ).get_property( 'innerHTML' );
  $entry.fields<publisher> = BibTeX::Value.new($publisher);

  $entry;
}

sub scrape-oxford(--> BibTeX::Entry) {
  # BibTeX
  await({ $web-driver.find_element_by_class_name( 'js-cite-button' ) }).click;
  my $select-element = await({ $web-driver.find_element_by_id( 'selectFormat' ) });
  my $select = $python.call( '__main__', 'select', $select-element);
  await({
    $select.select_by_visible_text( '.bibtex (BibTex)' );
    my $button = $web-driver.find_element_by_class_name( 'citation-download-link' );
    # Make sure the drop-down was populated
    $button.get_attribute( 'class' ) !~~ / « 'disabled' » /
      and $button }).click;
  my BibTeX::Entry $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, month => True, year => True);

  ## Title
  my Str $title = $web-driver.find_element_by_class_name( 'article-title-main' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibTeX::Value.new($title);

  ## Abstract
  my Str $abstract = $web-driver.find_element_by_class_name( 'abstract' ).get_property( 'innerHTML' );
  $entry.fields<abstract> = BibTeX::Value.new($abstract);

  ## ISSN
  my Str $issn = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );
  $issn ~~ / 'Print ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my Str $pissn = $0.Str;
  $issn ~~ / 'Online ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my Str $eissn = $0.Str;
  $entry.fields<issn> = BibTeX::Value.new("$pissn (Print) $eissn (Online)");

  ## Publisher
  update($entry, 'publisher', { s/^ 'Oxford Academic' $/Oxford University Press/ });

  $entry;
}

sub scrape-science-direct(--> BibTeX::Entry) {
  ## BibTeX
  await({
    $web-driver.find_element_by_id( 'export-citation' ).click;
    $web-driver.find_element_by_css_selector( 'button[aria-label="bibtex"]' ).click;
    True
  });
  my BibTeX::Entry $entry = bibtex-parse(read-downloads()).items.head;

  ## HTML Meta
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  html-meta-bibtex($entry, $meta, number => True);

  ## Title
  my Str $title = $web-driver.find_element_by_class_name( 'title-text' ).get_property( 'innerHTML' );
  $entry.fields<title> = BibTeX::Value.new($title);

  ## Keywords
  my Str @keywords = $web-driver
    .find_elements_by_css_selector( '.keywords-section > .keyword > span' )
    .map({ .get_property( 'innerHTML' )});
  $entry.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my Str @abstract = $web-driver.find_elements_by_css_selector( '.abstract > div' ).map({.get_property( 'innerHTML' )});
  if @abstract {
    $entry.fields<abstract> = BibTeX::Value.new(@abstract.head);
  }

  ## Series
  if $entry.fields<note> {
    $entry.fields<series> = $entry.fields<note>;
    $entry.fields<note>:delete;
  }

  $entry;
}

sub scrape-springer {
  ## BibTeX
  my BibTeX::Entry $entry = BibTeX::Entry.new();
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
  my HtmlMeta::HtmlMeta $meta = html-meta-parse($web-driver);
  $entry.type = html-meta-type($meta);
  html-meta-bibtex($entry, $meta, author => True, publisher => True);

  for 'author', 'editor' -> Str $key {
    if $entry.fields{$key}:exists {
      my Str $names = $entry.fields{$key}.simple-str;
      $names ~~ s:g/ ' '* "\n" / /;
      $entry.fields{$key} = BibTeX::Value.new($names);
    }
  }

  ## ISBN
  my Str @pisbn = $web-driver.find_elements_by_id( 'print-isbn' ).map({.get_property( 'innerHTML' )});
  my Str @eisbn = $web-driver.find_elements_by_id( 'electronic-isbn' ).map({.get_property( 'innerHTML' )});
  if @pisbn and @eisbn {
    $entry.fields<isbn> = BibTeX::Value.new("{@pisbn.head} (Print) {@eisbn.head} (Online)");
  }

  ## ISSN
  if $web-driver.find_element_by_tag_name( 'head' ).get_property( 'innerHTML' )
      ~~ / '{"eissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '","pissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}' / {
    my Str $issn = "$1 (Print) $0 (Online)";
    $entry.fields<issn> = BibTeX::Value.new($issn);
  }

  ## Series, Volume and ISSN
  #
  # Ugh, Springer doesn't have a reliable way to get the series, volume,
  # or ISSN.  Fortunately, this only happens for LNCS, so we hard code
  # it.
  if $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' ) ~~ / '(LNCS, volume ' (\d*) ')' / {
    $entry.fields<volume> = BibTeX::Value.new($0.Str);
    $entry.fields<series> = BibTeX::Value.new( 'Lecture Notes in Computer Science' );
  }

  ## Keywords
  my Str @keywords = $web-driver.find_elements_by_class_name( 'c-article-subject-list__subject' ).map({ .get_property( 'innerHTML' ) });
  $entry.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my @abstract =
    ($web-driver.find_elements_by_class_name( 'Abstract' ),
    $web-driver.find_elements_by_id( 'Abs1-content' )).flat;
  if @abstract {
    my Str $abstract = @abstract.head.get_property( 'innerHTML' );
    $abstract ~~ s/^ '<h' <[23]> .*? '>Abstract</h' <[23]> '>' //;
    $entry.fields<abstract> = BibTeX::Value.new($abstract);
  }

  ## Publisher
  # The publisher field should not include the address
  update($entry, 'publisher', { $_ = 'Springer' if $_ eq 'Springer, ' ~ ($entry.fields<address> // BibTeX::Value.new()).simple-str });

  $entry;
}
