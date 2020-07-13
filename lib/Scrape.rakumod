unit module Scrape;

use HTML::Entity;

use BibTeX;
use BibTeX::Html;

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
  #profile.set_preference('browser.helperApps.neverAsk.openFile','text/plain,text/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.helperApps.neverAsk.saveToDisk', 'text/plain,text/x-bibtex,application/x-research-info-systems')
  profile.set_preference('browser.download.folderList', 2)
  profile.set_preference('browser.download.dir', os.getcwd() + '/downloads')
  return webdriver.Firefox(firefox_profile=profile)

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

########

my $downloads = 'downloads'.IO;

sub scrape(Str $url --> BibTeX::Entry) is export {
  $downloads.dir».unlink;

  open();
  $web-driver.get($url);

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
    when m[ « 'wiley.com'           $] { scrape-wiley(); }
    default { say "error: unknown domain: $domain"; }
  }
  $bibtex.fields.push((bib-scrape-url => BibTeX::Value.new($url)));
  close();
  $bibtex;
}

########

sub scrape-acm(--> BibTeX::Entry) {
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

  my $abstract = $web-driver
    .find_elements_by_css_selector(".abstractSection.abstractInFull")
    .reverse.head
    .get_property('innerHTML');
  if $abstract.defined and $abstract ne '<p>No abstract available.</p>' {
    # Fix the double HTML encoding of the abstract (Bug in ACM?)
    $abstract = decode-entities($abstract);
    $bibtex.fields<abstract> = BibTeX::Value.new($abstract);
  }

  # Get the Unicode version that we can properly convert to TeX
  my $authors = $web-driver.find_elements_by_css_selector( '.citation .author-name' )».get_attribute( 'title' ).join( ' and ' );
  $bibtex.fields<author> = BibTeX::Value.new($authors);

  # Get the Unicode version that we can properly convert to TeX
  my $title = $web-driver.find_element_by_css_selector( '.citation__title' ).get_property( 'innerHTML' );
  $bibtex.fields<title> = BibTeX::Value.new($title);

  my $date =
    do if $bibtex.fields<issue_date>:exists {
      $bibtex.fields<issue_date>.simple-str
    } else {
      $web-driver.find_element_by_css_selector( '.epub-section__date' ).get_property( 'innerHTML' )
    }
  my $month = $date.split(rx/\s+/).head;
  $bibtex.fields<month> = BibTeX::Value.new($month);

  my @keywords = $web-driver.find_elements_by_css_selector( '.tags-widget__content a' );
  @keywords = @keywords».get_property( 'innerHTML' );
  # ACM is inconsistent about the order in which these are returned.
  # We sort them so that we are deterministic.
  @keywords = @keywords.sort;
  $bibtex.fields<keywords> = BibTeX::Value.new(@keywords.join( '; ' )) if @keywords.elems > 0;

  if $bibtex.type eq 'article' {
    my @journal = $web-driver.find_elements_by_css_selector( 'meta[name="citation_journal_title"]' );
    if @journal.elems > 0 { $bibtex.fields<journal> = BibTeX::Value.new(@journal.head.get_property( 'content' )); }
  }
#    html-meta-parse($web-driver);
#    my $html = Text::MetaBib::parse($mech->content());
#    $html->bibtex($entry, 'booktitle');
#
#    # ACM gets the capitalization wrong for 'booktitle' everywhere except in the BibTeX,
#    # but gets symbols right only in the non-BibTeX.  Attept to take the best of both worlds.
#    $entry->set('booktitle', merge($entry->get('booktitle'), qr[\b],
#                                   $html->get('citation_conference')->[0], qr[\b],
#                                   sub { (lc $_[0] eq lc $_[1]) ? $_[0] : $_[1] },
#                                   { keyGen => sub { lc shift }})) if $entry->exists('booktitle');

  $bibtex;
}

sub scrape-cambridge(--> BibTeX::Entry) {
  $web-driver.find_element_by_class_name('export-citation-product').click;
  sleep 5;

  $web-driver.find_element_by_css_selector('[data-export-type="bibtex"]').click;

  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

  #   my ($abst) = $mech->content() =~ m[<div class="abstract" data-abstract-type="normal">(.*?)</div>]s;
  #   $abst =~ s[^<title>Abstract</title>][] if $abst;
  #   $abst =~ s/\n+/\n/g if $abst;
  #   $entry->set('abstract', $abst) if $abst;

  #   my $html = Text::MetaBib::parse($mech->content());

  #   $entry->set('title', @{$html->get('citation_title')});

  #   my ($month) = (join(' ',@{$html->get('citation_publication_date')}) =~ m[^\d\d\d\d/(\d\d)]);
  #   $entry->set('month', $month);

  #   my ($doi) = join(' ', @{$html->get('citation_pdf_url')}) =~ m[/(S\d{16})a\.pdf];
  #   $entry->set('doi', "10.1017/$doi");

  #   print_or_online($entry, 'issn', [$html->get('citation_issn')->[0]], [$html->get('citation_issn')->[1]]);

  $bibtex;
}

sub scrape-ieee-computer {
  $web-driver.find_element_by_css_selector( '.article-action-toolbar button' ).click;
  sleep 1;
  my $link = $web-driver.find_element_by_link_text( 'BibTex' );
  $web-driver.execute_script( 'arguments[0].removeAttribute("target")', $link);
  $web-driver.find_element_by_link_text( 'BibTex' ).click;
  sleep 1;
  my $text = $web-driver.find_element_by_tag_name( 'pre' ).get_property( 'innerHTML' );
  $text ~~ s/ "\{," /\{key,/;
  my $bibtex = bibtex-parse($text).items.head;

#     my $html = Text::MetaBib::parse(decode('utf8', $mech->content()));
#     my $entry = parse_bibtex("\@" . ($html->type() || 'misc') . "{unknown_key,}");

#     if ($entry->type() eq 'inproceedings') { # IEEE gets this all wrong
#         $entry->set('series', $f->get('journal')) if $f->exists('journal');
#         $entry->delete('journal');
#     }
#     $entry->set('address', $f->get('address')) if $f->exists('address');
#     $entry->set('volume', $f->get('volume')) if $f->exists('volume');
#     update($entry, 'volume', sub { $_ = undef if $_ eq "00" });

#     $html->bibtex($entry);

#     # Don't use the MetaBib for this as IEEE doesn't escape quotes property
#     $entry->set('abstract', $mech->content() =~ m[<div class="abstractText abstractTextMB">(.*?)</div>]);

  $bibtex;
}

sub scrape-ieee-explore {
  $web-driver.find_element_by_tag_name( 'xpl-cite-this-modal' ).click;
  sleep 1;
  $web-driver.find_element_by_link_text( 'BibTeX' ).click;
  sleep 1;
  $web-driver.find_element_by_css_selector( '.enable-abstract input' ).click;
  sleep 1;
  my $text = $web-driver.find_element_by_class_name( 'ris-text' ).get_property( 'innerHTML' );
  my $bibtex = bibtex-parse($text).items.head;

#     # Extract data from embedded JSON
#     my @affiliations = $mech->content() =~ m[\{.*?"affiliation":"([^"]+)".*?\}]sg;
#     $entry->set('affiliation', join(" and ", @affiliations)) if @affiliations;

#     $entry->set('publisher', $mech->content() =~ m["publisher":"([^"]+)"]s);

#     $entry->set('location', $1) if $mech->content() =~ m["confLoc":"([^"]+)"]s;

#     $entry->set('conference_date', $1) if $mech->content() =~ m["conferenceDate":"([^"]+)"]s;

#     my ($isbns) = $mech->content() =~ m["isbn":\[(.+?)\]]sg;
#     if ($isbns) {
#       # TODO: refactor with print_or_online()
#       $isbns =~ s["CD-ROM ISBN"]["Online ISBN"]sg; # TODO: update Fix.pm to support CD-ROM ISBN
#       my @isbns = pairs($isbns =~ m[\{"format":"([^"]+) ISBN","value":"([^"]+)"\}]sg);
#       $entry->set('isbn', @isbns <= 1 ? $isbns[0]->[1] : join(" ", map { "$_->[1] ($_->[0])" } @isbns));
#     }

#     my ($issns) = $mech->content() =~ m["issn":\[(.+?)\]]sg;
#     if ($issns) {
#       # TODO: refactor with print_or_online()
#       $issns =~ s["Electronic ISSN"]["Online ISSN"]sg; # TODO: update Fix.pm to support Electronic ISSN
#       my @issns = pairs($issns =~ m[\{"format":"([^"]+) ISSN","value":"([^"]+)"\}]sg);
#       $entry->set('issn', @issns <= 1 ? $issns[0]->[1] : join(" ", map { "$_->[1] ($_->[0])" } @issns));
#     }

#     update($entry, 'keywords', sub { s[; *][; ]sg; });
#     update($entry, 'abstract', sub { s[&lt;&lt;ETX&gt;&gt;$][]; });

  $bibtex;
}

sub scrape-ios-press {
  die "unimplemented";

#     my $html = Text::MetaBib::parse($mech->content());
#     my $entry = parse_bibtex("\@" . ($html->type() || 'misc') . "{unknown_key,}");
#     $html->bibtex($entry);

#     $entry->set('title', decode_entities($mech->content() =~ m[data-p13n-title="([^"]*)"]));
#     $entry->set('abstract', decode_entities($mech->content() =~ m[data-abstract="([^"]*)"]));

#     # Remove extra newlines
#     update($entry, 'title', sub { s[\n][]g });

#     # Insert missing paragraphs.  This is a heuristic solution.
#     update($entry, 'abstract', sub { s[([.!?])  ][$1\n\n]g });

}

sub scrape-jstor {
  # Remove Covid-19 overlay
  my @overlays = $web-driver.find_elements_by_class_name( 'reveal-overlay' );
  @overlays.map({ $web-driver.execute_script( 'arguments[0].removeAttribute("style")', $_) });
  sleep 1;
  $web-driver.find_element_by_class_name( 'cite-this-item' ).click;
  sleep 1;
  $web-driver.find_element_by_css_selector( '[data-sc="text link: citation text"]' ).click;
  sleep 1;
  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;
#     print STDERR "WARNING: JSTOR imposes strict rate limiting.  You might have `Error GETing` errors if you try to get the BibTeX for multiple papers in a row.\n";

#     my $html = Text::MetaBib::parse($mech->content());

#     $mech->follow_link(text_regex => qr[Cite this Item]);
#     $mech->follow_link(text => 'Export a Text file');

#     my $cont = $mech->content();
#     my $entry = parse_bibtex($cont);
#     $mech->back();

#     $mech->find_link(text => 'Export a RIS file');
#     $mech->follow_link(text => 'Export a RIS file');
#     my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
#     $entry->set('month', $f->get('month'));
#     $mech->back();

#     $mech->back();

#     $html->bibtex($entry);

#     my ($abs) = $mech->content() =~ m[<div class="abstract1"[^>]*>(.*?)</div>]s;
#     $entry->set('abstract', $abs) if defined $abs;

  $bibtex;
}

sub scrape-oxford {
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
#     my $html = Text::MetaBib::parse($mech->content());
#     my $entry = parse_bibtex("\@" . ($html->type() || 'misc') . "{unknown_key,}");
#     $html->bibtex($entry);

#     $entry->set('title', $mech->content() =~ m[<h1 class="wi-article-title article-title-main">(.*?)</h1>]s);
#     $entry->set('abstract', $mech->content() =~ m[<section class="abstract">\s*(.*?)\s*</section>]si);

#     print_or_online($entry, 'issn',
#          [$mech->content() =~ m[Print ISSN (\d\d\d\d-\d\d\d[0-9X])]],
#          [$mech->content() =~ m[Online ISSN (\d\d\d\d-\d\d\d[0-9X])]]);

  $bibtex;
}

sub scrape-science-direct(--> BibTeX::Entry) {
  $web-driver.find_element_by_id( 'export-citation' ).click;
  $web-driver.find_element_by_css_selector( 'button[aria-label="bibtex"]' ).click;
  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files.head.slurp).items.head;

#     my $html = Text::MetaBib::parse($mech->content());

#     # Evil Science Direct uses JavaScript to create links
#     my ($pii) = $mech->content() =~ m[<meta name="citation_pii" content="(.*?)" />];

#     $mech->get("https://www.sciencedirect.com/sdfe/arp/cite?pii=$pii&format=text/x-bibtex&withabstract=true");
#     my $entry = parse_bibtex($mech->content());
#     $mech->back();

#     my ($keywords) = $mech->content() =~ m[>Keywords</h2>(<div\b[^>]*>.*?</div>)</div>]s;
#     if (defined $keywords) {
#         $keywords =~ s[<div\b[^>]*?>(.*?)</div>][$1; ]sg;
#         $keywords =~ s[; $][];
#         $entry->set('keywords', $keywords);
#     }

#     my ($abst) = $mech->content() =~ m[<div class="abstract author"[^>]*>(.*?</div>)</div>];
#     $abst = "" unless defined $abst;
#     $abst =~ s[<h2\b[^>]*>Abstract</h2>][]g;
#     $abst =~ s[<div\b[^>]*>(.*)</div>][$1]s;
#     $entry->set('abstract', $abst);

#     if ($entry->exists('note') and $entry->get('note') ne '') {
#         $entry->set('series', $entry->get('note'));
#         $entry->delete('note');
#     }

#     my ($iss_first) = $mech->content() =~ m["iss-first":"(\d+)"];
#     my ($iss_last) = $mech->content() =~ m["iss-last":"(\d+)"];
#     $entry->set('number', defined $iss_last ? "$iss_first--$iss_last" : "$iss_first");

#     $mech->get("http://www.sciencedirect.com/sdfe/arp/cite?pii=$pii&format=application%2Fx-research-info-systems&withabstract=false");
#     my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
#     $entry->set('month', $f->get('month'));
#     $mech->back();

# TODO: editor

#     $html->bibtex($entry);

#     my ($title) = $mech->content =~ m[<h1 class="Head"><span class="title-text">(.*?)</span>(<a [^>]+>.</a>)?</h1>]s;
#     $entry->set('title', $title);

  $bibtex;
}

sub scrape-springer {
  die 'unimplemented';
# # TODO: handle books
#     $mech->follow_link(url_regex => qr[format=bibtex]);
#     my $entry = parse_bibtex($mech->content());
#     $mech->back();

#     my ($abstr) = join('', $mech->content() =~ m[>(?:Abstract|Summary)</h2>(.*?)</section]s);
#     $entry->set('abstract', $abstr) if defined $abstr;

#     my $html = Text::MetaBib::parse($mech->content());

#     print_or_online($entry, 'issn',
#         [$mech->content() =~ m[id="print-issn">(.*?)</span>]],
#         [$mech->content() =~ m[id="electronic-issn">(.*?)</span>]]);

#     print_or_online($entry, 'isbn',
#         [$mech->content() =~ m[id="print-isbn">(.*?)</span>]],
#         [$mech->content() =~ m[id="electronic-isbn">(.*?)</span>]]);

#     # Ugh, Springer doesn't have a reliable way to get the series, volume,
#     # or issn.  Fortunately, this only happens for LNCS, so we hard code
#     # it.
#     my ($volume) = $mech->content() =~ m[\(LNCS, volume (\d*?)\)];
#     if (defined $volume) {
#         $entry->set('series', 'Lecture Notes in Computer Science');
#         $entry->set('volume', $volume);
#         $entry->set('issn', '0302-9743 (Print) 1611-3349 (Online)');
#     }

#     $entry->set('keywords', $1) if $mech->content() =~ m[<div class="KeywordGroup" lang="en">(?:<h2 class="Heading">KeyWords</h2>)?(.*?)</div>];
#     update($entry, 'keywords', sub {
#       s[^<span class="Keyword">\s*(.*?)\s*</span>$][$1];
#       s[\s*</span><span class="Keyword">\s*][; ]g;
#           });

#     $html->bibtex($entry, 'abstract', 'month');

#     # The publisher field should not include the address
#     update($entry, 'publisher', sub { $_ = 'Springer' if $_ eq ('Springer, ' . ($entry->get('address') // '')) });

}

sub scrape-wiley {
  $web-driver.find_element_by_class_name( 'article-tools__ctrl' ).click;
  sleep 1;
  $web-driver.find_elements_by_class_name( 'article-tool' )[1].click;
  sleep 5;

  $web-driver.find_element_by_css_selector( 'input[value="bibtex"] + span' ).click;
  sleep 1;
  $web-driver.find_element_by_css_selector( 'input[value="other-type"] + span' ).click;
  sleep 1;
  $web-driver.find_element_by_css_selector( 'input[value="Download"]' ).click;
  sleep 5;
  my $text = $web-driver.find_element_by_tag_name( 'pre' ).get_property( 'innerHTML' );
  my $bibtex = bibtex-parse($text).items.head;

#     my $html = Text::MetaBib::parse($mech->content());
#     $html->bibtex($entry);

#     # Extract abstract from HTML
#     my ($abs) = ($mech->content() =~ m[<section class="article-section article-section__abstract"[^>]*>(.*?)</section>]s);
#     $abs =~ s[<h[23].*?>Abstract</h[23]>][];
#     $abs =~ s[<div class="article-section__content[^"]*">(.*)</div>][$1]s;
#     $abs =~ s[(Copyright )?(.|&copy;) \d\d\d\d John Wiley (.|&amp;) Sons, (Ltd|Inc)\.\s*][];
#     $abs =~ s[(.|&copy;) \d\d\d\d Wiley Periodicals, Inc\. Random Struct\. Alg\..*, \d\d\d\d][];
#     $abs =~ s[\\begin\{align\*\}(.*?)\\end\{align\*\}][\\ensuremath\{$1\}]sg;
#     $entry->set('abstract', $abs);

#     # To handle multiple month issues we must use HTML
#     my ($month_year) = $mech->content() =~ m[<div class="extra-info-wrapper cover-image__details">(.*?)</div>]s;
#     my ($month) = $month_year =~ m[<p>([^<].*?) \d\d\d\d</p>]s;
#     $entry->set('month', $month);

#     # Choose the title either from bibtex or HTML based on whether we think the BibTeX has the proper math in it.
#     $entry->set('title', $mech->content() =~ m[<h2 class="citation__title">(.*?)</h2>]s)
#         unless $entry->get('title') =~ /\$/;

#     # Remove math rendering images. (The LaTeX code is usually beside the image.)
#     update($entry, 'title', sub { s[<img .*?>][]sg; });
#     update($entry, 'abstract', sub { s[<img .*?>][]sg; });

#     # Fix "blank" spans where they should be monospace
#     update($entry, 'title', sub { s[<span>(?=[^\$])][<span class="monospace">]sg; });
#     update($entry, 'abstract', sub { s[<span>(?=[^\$])][<span class="monospace">]sg; });

  $bibtex;
}
