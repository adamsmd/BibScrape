use lib:from<Perl5> 'dep/WebDriver-Tiny-0.102/lib/';
use WebDriver::Tiny:from<Perl5>;

use BibTeX;
use HtmlMeta;

# TODO: ignore non-domain files (timeout on file load?)

########

my $web-driver;
my $proc;

sub init() {
  unless $web-driver.defined {
    $proc = Proc::Async.new('geckodriver', '--log=warn');
    $proc.start;
    await $proc.ready;
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

sub scrape(Str $url) is export {
  open();
  $web-driver.get($url);

  # Get the domain after following any redirects
  my $domain = $web-driver.url() ~~ m[ ^ <-[/]>* "//" <( <-[/]>* )> "/"];
  given $domain {
    when m[ << "acm.org" $] { parse-acm(); }
    default { say "error: unknown domain: $domain"; }
  }
  # TODO: exit?
  close();
}

########

sub parse-acm {
  $web-driver.find('a[data-title="Export Citation"]').click;
  my @text = map { .text() }, $web-driver.find("#exportCitation .csl-right-inline");

  say @text;

  # Avoid SIGPLAN Notices, SIGSOFT Software Eng Note, etc. by prefering
  # non-journal over journal
  my %bibtex = @text
    .flatmap({ parse_bibtex($_).items })
    .grep({ $_ ~~ BibTeX::Entry })
    .classify({ .fields<journal>:exists });
  my $bibtex = (flat %bibtex<False>, %bibtex<True>)[0];

  say $bibtex.Str;

  my @abstract = map { .prop("innerHTML"); }, $web-driver.find(".abstractSection.abstractInFull");
  say @abstract;

  parse-html-meta($web-driver);
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
