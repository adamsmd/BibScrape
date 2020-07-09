unit module Scrape;

use BibTeX;
use BibTeX::Html;

use Inline::Python; # Must be the last import (otherwise we get: Cannot find method 'EXISTS-KEY' on 'BOOTHash': no method cache and no .^find_method)

# TODO: ignore non-domain files (timeout on file load?)

########

my $web-driver;
my $proc;

# ['CONTEXT_CHROME',
#  'CONTEXT_CONTENT',
#  'NATIVE_EVENTS_ALLOWED',
#  '__class__',
#  '__delattr__',
#  '__dict__',
#  '__doc__',
#  '__enter__',
#  '__exit__',
#  '__format__',
#  '__getattribute__',
#  '__hash__',
#  '__init__',
#  '__module__',
#  '__new__',
#  '__reduce__',
#  '__reduce_ex__',
#  '__repr__',
#  '__setattr__',
#  '__sizeof__',
#  '__str__',
#  '__subclasshook__',
#  '__weakref__',
#  '_file_detector',
#  '_is_remote',
#  '_mobile',
#  '_switch_to',
#  '_unwrap_value',
#  '_web_element_cls',
#  '_wrap_value',
#  'add_cookie',
#  'application_cache',
#  'back',
#  'binary',
#  'capabilities',
#  'close',
#  'command_executor',
#  'context',
#  'create_web_element',
#  'current_url',
#  'current_window_handle',
#  'delete_all_cookies',
#  'delete_cookie',
#  'desired_capabilities',
#  'error_handler',
#  'execute',
#  'execute_async_script',
#  'execute_script',
#  'file_detector',
#  'file_detector_context',
#  'find_element',
#  'find_element_by_class_name',
#  'find_element_by_css_selector',
#  'find_element_by_id',
#  'find_element_by_link_text',
#  'find_element_by_name',
#  'find_element_by_partial_link_text',
#  'find_element_by_tag_name',
#  'find_element_by_xpath',
#  'find_elements',
#  'find_elements_by_class_name',
#  'find_elements_by_css_selector',
#  'find_elements_by_id',
#  'find_elements_by_link_text',
#  'find_elements_by_name',
#  'find_elements_by_partial_link_text',
#  'find_elements_by_tag_name',
#  'find_elements_by_xpath',
#  'firefox_profile',
#  'forward',
#  'fullscreen_window',
#  'get',
#  'get_cookie',
#  'get_cookies',
#  'get_log',
#  'get_screenshot_as_base64',
#  'get_screenshot_as_file',
#  'get_screenshot_as_png',
#  'get_window_position',
#  'get_window_rect',
#  'get_window_size',
#  'implicitly_wait',
#  'install_addon',
#  'log_types',
#  'maximize_window',
#  'minimize_window',
#  'mobile',
#  'name',
#  'orientation',
#  'page_source',
#  'profile',
#  'quit',
#  'refresh',
#  'save_screenshot',
#  'service',
#  'session_id',
#  'set_context',
#  'set_page_load_timeout',
#  'set_script_timeout',
#  'set_window_position',
#  'set_window_rect',
#  'set_window_size',
#  'start_client',
#  'start_session',
#  'stop_client',
#  'switch_to',
#  'switch_to_active_element',
#  'switch_to_alert',
#  'switch_to_default_content',
#  'switch_to_frame',
#  'switch_to_window',
#  'title',
#  'uninstall_addon',
#  'w3c',
#  'window_handles']


sub init() {
  unless $web-driver.defined {
    #$proc = Proc::Async.new('geckodriver', '--log=warn');
    #$proc.bind-stdout($*ERR);
    #$proc.start;
    #await $proc.ready;
    # TODO: check if already running (use explicit port?)
    $proc = Inline::Python.new;
    $proc.run("
import sys
sys.path += ['dep/py']
from selenium import webdriver
from selenium.webdriver.firefox import firefox_profile
import os

def web_driver():
  profile = firefox_profile.FirefoxProfile()
  #profile.set_preference('browser.download.panel.shown', False)
  #profile.set_preference('browser.helperApps.neverAsk.openFile','text/x-bibtex')
  profile.set_preference('browser.helperApps.neverAsk.saveToDisk', 'text/x-bibtex')
  profile.set_preference('browser.download.folderList', 2)
  profile.set_preference('browser.download.dir', os.getcwd() + '/downloads')
  return webdriver.Firefox(firefox_profile=profile)
");
  }
}

sub open() {
  init();
  close();
  #$web-driver = WebDriver::Tiny.new(port => 4444);
  $web-driver = $proc.call('__main__', 'web_driver');
  #$web-driver.set_page_load_timeout(5);
}

sub close() {
  if $web-driver.defined {
    $web-driver.quit();
    #$web-driver._req( DELETE => '' );
    $web-driver = Any;
  }
}

END {
  close();
  if $proc.defined {
    #$proc.kill;
    # TODO: kill all sub-processes
  }
}

sub infix:<%>($obj, Str $attr) { $obj.__getattribute__($attr); }

########

sub scrape(Str $url --> BibTeX::Entry) is export {
  open();
  $web-driver.get($url);

  # Get the domain after following any redirects
  sleep 5;
  my $domain = $web-driver%<current_url> ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"];
  my $bibtex = do given $domain {
    when m[ « "acm.org" $] { scrape-acm(); }
    when m[ « "sciencedirect.com" $] { scrape-science-direct(); }
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
  my $bibtex = (flat (@(%bibtex<False>), @(%bibtex<True>)))[0];

  my $abstract = $web-driver
    .find_elements_by_css_selector(".abstractSection.abstractInFull")
    .reverse.head
    .get_property('innerHTML');
  $bibtex.fields<abstract> = BibTeX::Value.new($abstract);

  #html-meta-parse($web-driver);
  # TODO: month

  $bibtex;
}

#sub parse_acm {
#    # Abstract
#    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
#    $mech->get($abstr_url);
#    # Fix the double HTML encoding of the abstract (Bug in ACM?)
#    $entry->set('abstract', decode_entities($1)) if $mech->content() =~
#        m[<div style="display:inline">((?:<par>|<p>)?.+?(?:</par>|</p>)?)</div>];
#    $mech->back();
#
#    my $html = Text::MetaBib::parse($mech->content());
#    $html->bibtex($entry, 'booktitle');
#
#    # ACM gets the capitalization wrong for 'booktitle' everywhere except in the BibTeX,
#    # but gets symbols right only in the non-BibTeX.  Attept to take the best of both worlds.
#    $entry->set('booktitle', merge($entry->get('booktitle'), qr[\b],
#                                   $html->get('citation_conference')->[0], qr[\b],
#                                   sub { (lc $_[0] eq lc $_[1]) ? $_[0] : $_[1] },
#                                   { keyGen => sub { lc shift }})) if $entry->exists('booktitle');
#
#    $entry->set('title', $mech->content() =~ m[<h1 class="mediumb-text" style="margin-top:0px; margin-bottom:0px;">(.*?)</h1>]);
#
#    return $entry;
#}

sub scrape-science-direct(--> BibTeX::Entry) {
  my $downloads = 'downloads'.IO;
  $downloads.dir».unlink;
  $web-driver.find_element_by_id('export-citation').click;
  # say "++1";
  $web-driver.find_element_by_css_selector('button[aria-label="bibtex"]').click;
  # say "++2";
  my @files = 'downloads'.IO.dir;
  my $bibtex = bibtex-parse(@files[0].slurp).items[0];
  # say $bibtex.Str;
  $bibtex;
  #bibtex-parse('@foo{bar,}').items[0];

  # export-citation-product
  #   $mech->content() =~ m[data-prod-id="([0-9A-F]+)">Export citation</a>];
  #   my $product_id = $1;
  #   $mech->get("https://www.cambridge.org/core/services/aop-easybib/export/?exportType=bibtex&productIds=$product_id&citationStyle=bibtex");
  #   my $entry = parse_bibtex($mech->content());
  #   $mech->back();

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

  #   return $entry;
}
