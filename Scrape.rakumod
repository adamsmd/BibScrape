use lib:from<Perl5> 'dep/WebDriver-Tiny-0.102/lib/';
use WebDriver::Tiny:from<Perl5>;

use BibTeX;
use BibTeX::Html;

# TODO: ignore non-domain files (timeout on file load?)

########

my $web-driver;
my $proc;

sub init() {
  unless $web-driver.defined {
    $proc = Proc::Async.new('geckodriver', '--log=warn');
    $proc.bind-stdout($*ERR);
    $proc.start;
    await $proc.ready;
    # TODO: check if already running (use explicit port?)
  }
}

sub open() {
  init();
  close();
  $web-driver = WebDriver::Tiny.new(port => 4444);
}

sub close() {
  if $web-driver.defined {
    $web-driver._req( DELETE => '' );
    $web-driver = Any;
  }
}

END {
  close();
  if $proc.defined {
    $proc.kill;
  }
}

########

sub scrape(Str $url --> BibTeX::Entry) is export {
  open();
  $web-driver.get($url);

  # Get the domain after following any redirects
  my $domain = $web-driver.url() ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"];
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
  $web-driver.find('a[data-title="Export Citation"]').click;
  my @citation-text = $web-driver.find("#exportCitation .csl-right-inline")».text;

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my %bibtex = @citation-text
    .flatmap({ bibtex-parse($_).items })
    .grep({ $_ ~~ BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my $bibtex = (flat (@(%bibtex<False>), @(%bibtex<True>)))[0];

  my @elements =
    (try $web-driver.find(".abstractSection.abstractInFull .abstractSection.abstractInFull"))
    // $web-driver.find(".abstractSection.abstractInFull");
  my @abstract = map { .prop("innerHTML"); }, @elements;
  $bibtex.fields<abstract> = BibTeX::Value.new(@abstract.join);

  html-meta-parse($web-driver);
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
  $web-driver.find('.export-citation-product').click;
  $web-driver.find('a[data-export-type="bibtex"]').click;
  sleep 15;

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
