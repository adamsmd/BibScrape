unit module Scrape;

use HTML::Entity;

use BibTeX;
use HtmlMeta;
use Month;
use Ris;

use Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)
sub infix:<%>($obj, Str $attr) { $obj.__getattribute__($attr); }

########

my $web-driver;
my $python;

sub init() {
  unless $web-driver.defined {
    $python = Inline::Python.new;
    $python.run("
import sys
import os
sys.path.append('dep/py')

from selenium import webdriver
from selenium.webdriver.firefox import firefox_profile
from selenium.webdriver.support import ui

from biblib import algo

def parse_names(string):
  return algo.parse_names(string)

def web_driver():
  profile = firefox_profile.FirefoxProfile()
  #profile.set_preference('browser.download.panel.shown', False)
  #profile.set_preference('browser.helperApps.neverAsk.openFile',
  #  'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.helperApps.neverAsk.saveToDisk',
    'text/plain,text/x-bibtex,application/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.download.folderList', 2)
  profile.set_preference('browser.download.dir', os.getcwd() + '/downloads')

  return webdriver.Firefox(firefox_profile=profile, service_log_path='/dev/null')

def select(element):
  return ui.Select(element)
");
  }
}

sub to-str($buf) {
  if $buf.elems == 0 { Nil }
  else {
    given $buf {
      when Str { $buf }
      when Buf { $buf.decode }
    }
  }
}

sub parse-names(Str $string) is export {
  init();
  my @names = $python.call( '__main__', 'parse_names', $string);
  @names.map({
    BibTeX::Name.new(
      first => to-str($_%<first>),
      von => to-str($_%<von>),
      last => to-str($_%<last>),
      jr => to-str($_%<jr>)) })
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

my $downloads = 'downloads'.IO;

sub scrape(Str $url --> BibTeX::Entry) is export {
  $downloads.dir».unlink;

  open();

  # Support 'doi:' as a url type
  my $driver-url = $url;
  $driver-url ~~ s:i/^ 'doi:' /https:\/\/doi.org\//;

  $web-driver.get($driver-url);

  # Get the domain after following any redirects
  sleep 5;
  my $domain = $web-driver%<current_url> ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"];
  my $bibtex = do given $domain {
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
  }
  $bibtex.fields.push((bib_scrape_url => BibTeX::Value.new($url)));
  close();
  $bibtex;
}

########

sub scrape-acm(--> BibTeX::Entry) {
  ## BibTeX
  $web-driver.find_element_by_css_selector('a[data-title="Export Citation"]').click;
  sleep 1;
  my @citation-text = $web-driver.find_elements_by_css_selector("#exportCitation .csl-right-inline").map({ $_ % <text> });

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my %bibtex = @citation-text
    .flatmap({ bibtex-parse($_).items })
    .grep({ $_ ~~ BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my $bibtex = (%bibtex<False> // %bibtex<True>).head;

  # TODO: check SIGPLAN Notices
  ## HTML Meta
  #my $meta = html-meta-parse($web-driver);
  #html-meta-bibtex($bibtex, $meta);

  ## Abstract
  my $abstract = $web-driver
    .find_elements_by_css_selector(".abstractSection.abstractInFull")
    .reverse.head
    .get_property('innerHTML');
  if $abstract.defined and $abstract ne '<p>No abstract available.</p>' {
    # Fix the double HTML encoding of the abstract (Bug in ACM?)
    $bibtex.fields<abstract> = BibTeX::Value.new($abstract);
  }

  ## Author
  my $author = $web-driver.find_elements_by_css_selector( '.citation .author-name' )».get_attribute( 'title' ).join( ' and ' );
  $bibtex.fields<author> = BibTeX::Value.new($author);

  ## Title
  my $title = $web-driver.find_element_by_css_selector( '.citation__title' ).get_property( 'innerHTML' );
  $bibtex.fields<title> = BibTeX::Value.new($title);

  ## Month
  #
  # ACM publication months are often inconsistent within the same page.
  # This is a best effort at picking the right month among these inconsistent results.
  if $bibtex.fields<issue_date>:exists {
    my $month = $bibtex.fields<issue_date>.simple-str.split(rx/\s+/).head;
    if str2month($month) {
      $bibtex.fields<month> = BibTeX::Value.new($month);
    }
  } elsif not $bibtex.fields<month>:exists {
    my $month = $web-driver.find_element_by_css_selector( '.book-meta + .cover-date' ).get_property( 'innerHTML' ).split(rx/\s+/).head;
    $bibtex.fields<month> = BibTeX::Value.new($month);
  }

  ## Keywords
  my @keywords = $web-driver.find_elements_by_css_selector( '.tags-widget__content a' );
  @keywords = @keywords».get_property( 'innerHTML' );
  # ACM is inconsistent about the order in which these are returned.
  # We sort them so that we are deterministic.
  @keywords = @keywords.sort;
  $bibtex.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' )) if @keywords.elems > 0;

  ## Journal
  if $bibtex.type eq 'article' {
    my @journal = metas( 'citation_journal_title' );
    if @journal.elems > 0 { $bibtex.fields<journal> = BibTeX::Value.new(@journal.head); }
  }

  ## Pages
  if $bibtex.fields<articleno>:exists and $bibtex.fields<numpages>:exists
      and not $bibtex.fields<pages>:exists {
    my Str $articleno = $bibtex.fields<articleno>.simple-str;
    my Str $numpages = $bibtex.fields<numpages>.simple-str;
    $bibtex.fields<pages> = BibTeX::Value.new("$articleno:1--$articleno:$numpages");
  }

  $bibtex;
}

sub scrape-cambridge(--> BibTeX::Entry) {
  ## BibTeX
  $web-driver.find_element_by_class_name( 'export-citation-product' ).click;
  sleep 5;

  $web-driver.find_element_by_css_selector( '[data-export-type="bibtex"]' ).click;

  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta, title => True, abstract => False);

  ## Abstract
  my $abstract = meta( 'citation_abstract' );
  $abstract ~~ s:g/ "\n      \n      " //;
  $abstract ~~ s/^ '<div ' <-[>]>* '>'//;
  $abstract ~~ s/ '</div>' $//;
  $bibtex.fields<abstract> = BibTeX::Value.new($abstract)
    unless $abstract ~~ /^ '//static.cambridge.org/content/id/urn' /;

  ## ISSN
  my $issn = $web-driver.find_element_by_name( 'productIssn' ).get_attribute( 'value' );
  my $eissn = $web-driver.find_element_by_name( 'productEissn' ).get_attribute( 'value' );
  $bibtex.fields<issn> = BibTeX::Value.new("$issn (Print) $eissn (Online)");

  $bibtex;
}

sub scrape-ieee-computer {
  ## BibTeX
  $web-driver.find_element_by_css_selector( '.article-action-toolbar button' ).click;
  sleep 1;
  my $bibtex-link = $web-driver.find_element_by_link_text( 'BibTex' );
  $web-driver.execute_script( 'arguments[0].removeAttribute("target")', $bibtex-link);
  $web-driver.find_element_by_link_text( 'BibTex' ).click;
  sleep 1;
  my $bibtex-text = $web-driver.find_element_by_tag_name( 'pre' ).get_property( 'innerHTML' );
  $bibtex-text ~~ s/ "\{," /\{key,/;
  $bibtex-text = Blob.new($bibtex-text.ords).decode; # Fix UTF-8 encoding
  my $bibtex = bibtex-parse($bibtex-text).items.head;
  $web-driver.back();

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta);

  ## Authors
  my @authors = $web-driver.find_elements_by_css_selector( 'a[href^="https://www.computer.org/csdl/search/default?type=author&"]' ).map({ .get_property( 'innerHTML' ) });
  $bibtex.fields<author> = BibTeX::Value.new(@authors.join( ' and ' ));

  ## Affiliation
  my @affiliations = $web-driver.find_elements_by_class_name( 'article-author-affiliations' ).map({ .get_property( 'innerHTML' ) });
  $bibtex.fields<affiliation> = BibTeX::Value.new(@affiliations.join( ' and ' )) if @affiliations;

  ## Keywords
  update($bibtex, 'keywords', { s:g/ ';' \s* /; / });

  $bibtex;
}

sub scrape-ieee-explore {
  ## BibTeX
  $web-driver.find_element_by_tag_name( 'xpl-cite-this-modal' ).click;
  sleep 2;
  $web-driver.find_element_by_link_text( 'BibTeX' ).click;
  sleep 2;
  $web-driver.find_element_by_css_selector( '.enable-abstract input' ).click;
  sleep 2;
  my $text = $web-driver.find_element_by_class_name( 'ris-text' ).get_property( 'innerHTML' );
  my $bibtex = bibtex-parse($text).items.head;

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta);

  ## HTML body text
  my $body = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );

  ## Keywords
  my $keywords = $bibtex.fields<keywords>.simple-str;
  $keywords ~~ s:g/ ';' ' '* /; /;
  $bibtex.fields<keywords> = BibTeX::Value.new($keywords);

  ## Author
  my $author = $bibtex.fields<author>.simple-str;
  $author ~~ s:g/ '{' (<-[}]>+) '}' /$0/;
  $bibtex.fields<author> = BibTeX::Value.new($author);

  ## ISSN
  if $body ~~ / '"issn":[{"format":"Print ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"},{"format":"Electronic ISSN","value":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}]' / {
    $bibtex.fields<issn> = BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## ISBN
  if $body ~~ / '"isbn":[{"format":"Print ISBN","value":"' (<[-0..9Xx]>+) '","isbnType":""},{"format":"CD","value":"' (<[-0..9Xx]>+) '","isbnType":""}]' / {
    $bibtex.fields<isbn> = BibTeX::Value.new("$0 (Print) $1 (Online)");
  }

  ## Publisher
  my $publisher = $web-driver.find_element_by_class_name( 'publisher-info-label' ).get_property( 'innerHTML' );
  $publisher ~~ s/^ \s* 'Publisher: ' //;
  $bibtex.fields<publisher> = BibTeX::Value.new($publisher);

  ## Affiliation
  my $affiliation =
    ($body ~~ m:g/ '"affiliation":"' (<-["]>+) '"' /)
    .map(sub ($k, $v) { $v[0].Str }).join( ' and ' );
  $bibtex.fields<affiliation> = BibTeX::Value.new($affiliation) if $affiliation ne '';

  ## Location
  my $location = ($body ~~ / '"confLoc":"' (<-["]>+) '"' /)[0];
  if $location {
    $location ~~ s/ ',' \s+ $//;
    $location ~~ s/ ', USA, USA' $/, USA/;
    $bibtex.fields<location> = BibTeX::Value.new($location.Str);
  }

  ## Conference date
  $body ~~ / '"conferenceDate":"' (<-["]>+) '"' /;
  $bibtex.fields<conference_date> = BibTeX::Value.new($0.Str) if $0;

  ## Abstract
  update($bibtex, 'abstract', { s/ '&lt;&gt;' $// });

  $bibtex;
}

sub scrape-ios-press {
  ## RIS
  $web-driver.find_element_by_class_name( 'p13n-cite' ).click;
  sleep 1;
  $web-driver.find_element_by_class_name( 'btn-clear' ).click;
  sleep 3;
  my @files = 'downloads'.IO.dir;
  my $ris = ris-parse(@files.head.slurp);
  my $bibtex = bibtex-of-ris($ris);

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta);

  ## Title
  my $title = $web-driver.find_element_by_css_selector( '[data-p13n-title]' ).get_attribute( 'data-p13n-title' );
  $title ~~ s:g/ "\n" //; # Remove extra newlines
  $bibtex.fields<title> = BibTeX::Value.new($title);

  ## Abstract
  my $abstract = $web-driver.find_element_by_css_selector( '[data-abstract]' ).get_attribute( 'data-abstract' );
  $abstract ~~ s:g/ (<[.!?]>) '  ' /$0\n\n/; # Insert missing paragraphs.  This is a heuristic solution.
  $bibtex.fields<abstract> = BibTeX::Value.new($abstract);

  ## ISSN
  if $ris.fields<SN>:exists {
    my $eissn = $ris.fields<SN>;
    my $pissn = meta( 'citation_issn' );
    $bibtex.fields<issn> = BibTeX::Value.new("$pissn (Print) $eissn (Online)");
  }

  $bibtex;
}

sub scrape-jstor {
  ## Remove overlay
  my @overlays = $web-driver.find_elements_by_class_name( 'reveal-overlay' );
  @overlays.map({ $web-driver.execute_script( 'arguments[0].removeAttribute("style")', $_) });
  sleep 1;

  ## BibTeX
  $web-driver.find_element_by_class_name( 'cite-this-item' ).click;
  sleep 1;
  $web-driver.find_element_by_css_selector( '[data-sc="text link: citation text"]' ).click;
  sleep 1;
  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta);

  ## Title
  my $title = $web-driver.find_element_by_class_name( 'title' ).get_property( 'innerHTML' );
  $bibtex.fields<title> = BibTeX::Value.new($title);

  ## DOI
  my $doi = $web-driver.find_element_by_css_selector( '[data-doi]' ).get_attribute( 'data-doi' );
  $bibtex.fields<doi> = BibTeX::Value.new($doi);

  ## ISSN
  update($bibtex, 'issn', { s/^ (<[0..9Xx]>+) ', ' (<[0..9Xx]>+) $/$0 (Print) $1 (Online)/ });

  ## Month
  my $month = $web-driver.find_element_by_class_name( 'src' ).get_property( 'innerHTML' );
  if $month ~~ / '(' (<alpha>+) / {
    $bibtex.fields<month> = BibTeX::Value.new($0.Str);
  }

  ## Publisher
  my $publisher = $web-driver.find_element_by_class_name( 'publisher-link' ).get_property( 'innerHTML' );
  $bibtex.fields<publisher> = BibTeX::Value.new($publisher);

  $bibtex;
}

sub scrape-oxford {
  # BibTeX
  $web-driver.find_element_by_class_name( 'js-cite-button' ).click;
  sleep 2;
  my $select-element = $web-driver.find_element_by_id( 'selectFormat' );
  my $select = $python.call( '__main__', 'select', $select-element);
  $select.select_by_visible_text( '.bibtex (BibTex)' );
  sleep 1;
  $web-driver.find_element_by_class_name( 'citation-download-link' ).click;
  sleep 1;

  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta, month => True, year => True);

  ## Title
  my $title = $web-driver.find_element_by_class_name( 'article-title-main' ).get_property( 'innerHTML' );
  $bibtex.fields<title> = BibTeX::Value.new($title);

  ## Abstract
  my $abstract = $web-driver.find_element_by_class_name( 'abstract' ).get_property( 'innerHTML' );
  $bibtex.fields<abstract> = BibTeX::Value.new($abstract);

  ## ISSN
  my $issn = $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' );
  $issn ~~ / 'Print ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my $pissn = $0.Str;
  $issn ~~ / 'Online ISSN ' (\d\d\d\d '-' \d\d\d<[0..9Xx]>)/;
  my $eissn = $0.Str;
  $bibtex.fields<issn> = BibTeX::Value.new("$pissn (Print) $eissn (Online)");

  ## Publisher
  update($bibtex, 'publisher', { s/^ 'Oxford Academic' $/Oxford University Press/ });

  $bibtex;
}

sub scrape-science-direct(--> BibTeX::Entry) {
  ## BibTeX
  $web-driver.find_element_by_id( 'export-citation' ).click;
  $web-driver.find_element_by_css_selector( 'button[aria-label="bibtex"]' ).click;
  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  html-meta-bibtex($bibtex, $meta, number => True);

  ## Title
  my $title = $web-driver.find_element_by_class_name( 'title-text' ).get_property( 'innerHTML' );
  $bibtex.fields<title> = BibTeX::Value.new($title);

  ## Keywords
  my @keywords = $web-driver
    .find_elements_by_css_selector( '.keywords-section > .keyword > span' )
    .map({ .get_property( 'innerHTML' )});
  $bibtex.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my @abstract = $web-driver.find_elements_by_css_selector( '.abstract > div' ).map({.get_property( 'innerHTML' )});
  if @abstract.elems > 0 {
    $bibtex.fields<abstract> = BibTeX::Value.new(@abstract.head);
  }

  ## Series
  if ($bibtex.fields<note> // '') ne '' {
    $bibtex.fields<series> = $bibtex.fields<note>;
    $bibtex.fields<note>:delete;
  }

  $bibtex;
}

sub scrape-springer {
  ## Close overlay
  my @close-banner = $web-driver.find_elements_by_class_name( 'optanon-alert-box-close' );
  if @close-banner { @close-banner.head.click; }

  ## BibTeX
  my @elements = $web-driver.find_elements_by_id( 'button-Dropdown-citations-dropdown' );

  my $bibtex;
  # Springer seems to have two different page designs
  if @elements {
    #
    # This just scrolls the final link into view, but if we do not do this WebDriver reports an error
    @elements.head.click;
    sleep 5;
    $web-driver.find_element_by_css_selector( '#Dropdown-citations-dropdown a[data-track-label="BIB"]' ).click;
    sleep 5;
    my @files = 'downloads'.IO.dir;
    $bibtex = bibtex-parse(@files.head.slurp).items.head;
  } else {
    $bibtex = BibTeX::Entry.new();
  }

  ## HTML Meta
  my $meta = html-meta-parse($web-driver);
  $bibtex.type = html-meta-type($meta);
  html-meta-bibtex($bibtex, $meta, author => True, publisher => True);

  for 'author', 'editor' -> $key {
    if $bibtex.fields{$key}:exists {
      my $names = $bibtex.fields{$key}.simple-str;
      $names ~~ s:g/ ' '* "\n" / /;
      $bibtex.fields{$key} = BibTeX::Value.new($names);
    }
  }

  ## ISBN
  my @pisbn = $web-driver.find_elements_by_id( 'print-isbn' ).map({.get_property( 'innerHTML' )});
  my @eisbn = $web-driver.find_elements_by_id( 'electronic-isbn' ).map({.get_property( 'innerHTML' )});
  if @pisbn and @eisbn {
    $bibtex.fields<isbn> = BibTeX::Value.new("{@pisbn.head} (Print) {@eisbn.head} (Online)");
  }

  ## ISSN
  if $web-driver.find_element_by_tag_name( 'head' ).get_property( 'innerHTML' )
      ~~ / '{"eissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '","pissn":"' (\d\d\d\d '-' \d\d\d<[0..9Xx]>) '"}' / {
    my $issn = "$1 (Print) $0 (Online)";
    $bibtex.fields<issn> = BibTeX::Value.new($issn);
  }

  ## Series, Volume and ISSN
  #
  # Ugh, Springer doesn't have a reliable way to get the series, volume,
  # or issn.  Fortunately, this only happens for LNCS, so we hard code
  # it.
  if $web-driver.find_element_by_tag_name( 'body' ).get_property( 'innerHTML' ) ~~ / '(LNCS, volume ' (\d*) ')' / {
    $bibtex.fields<volume> = BibTeX::Value.new($0.Str);
    $bibtex.fields<series> = BibTeX::Value.new( 'Lecture Notes in Computer Science' );
  }

  ## Keywords
  my Str @keywords = $web-driver.find_elements_by_class_name( 'c-article-subject-list__subject' ).map({ .get_property( 'innerHTML' ) });
  $bibtex.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' ));

  ## Abstract
  my @abstract =
    ($web-driver.find_elements_by_class_name( 'Abstract' ),
    $web-driver.find_elements_by_id( 'Abs1-content' )).flat;
  if @abstract {
    my $abstract = @abstract.head.get_property( 'innerHTML' );
    $abstract ~~ s/^ '<h' <[23]> .*? '>Abstract</h' <[23]> '>' //;
    $bibtex.fields<abstract> = BibTeX::Value.new($abstract);
  }

  ## Publisher
  # The publisher field should not include the address
  update($bibtex, 'publisher', { $_ = 'Springer' if $_ eq 'Springer, ' ~ ($bibtex.fields<address> // BibTeX::Value.new()).simple-str });

  $bibtex;
}
