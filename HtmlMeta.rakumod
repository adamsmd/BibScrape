use lib:from<Perl5> 'dep/WebDriver-Tiny-0.102/lib/';
use WebDriver::Tiny:from<Perl5>;

use BibTeX;

sub parse-html-meta($web-driver --> Hash:D[Str]) is export {
  my @meta = $web-driver.find("meta");
  my Str %entries;
  for @meta -> $meta {
    my $name = $meta.attr("name");
    my $content = $meta.attr("content");
    if $name.defined and $content.defined {
      %entries{$name} = $content;
    }
  }
  return %entries;
}

#pbContext -> ;
#page:string:Article/Chapter View;
#subPage:string:Abstract;
#wgroup:string:ACM Publication Websites;
#
#issue:issue:doi\:10.1145/800125;
#
#groupTopic:topic:acm-pubtype>proceeding;
#topic:topic:conference-collections>stoc;
#csubtype:string:Conference Proceedings;
#
#article:article:doi\:10.1145/800125.804056;
#
#website:website:dl-site;
#ctype:string:Book Content;
#journal:journal:acmconferences;
#pageGroup:string:Publication Pages
#
#dc.Format -> text/HTML
#dc.Language -> EN
#dc.Coverage -> world
#robots -> noarchive
#viewport -> width=device-width,initial-scale=1
#msapplication-TileColor -> #00a300
#theme-color -> #ffffff


# Highwire Press tags (e.g., citation_title)
# Eprints tags (e.g., eprints.title)
# BE Press tags (e.g., bepress_citation_title)
# PRISM tags (e.g., prism.title)
#  Dublin Core tags (e.g., DC.title)

# use strict;
# use warnings;

# use HTML::HeadParser;
# use Text::BibTeX::Months;

# use Class::Struct 'Text::MetaBib' => { data => '%' };

# sub Text::MetaBib::get    { my ($self, $key) = @_;       $self->data->{$key} }
# sub Text::MetaBib::set    { my ($self, $key, $val) = @_; $self->data->{$key} = $val }
# sub Text::MetaBib::exists { my ($self, $key) = @_;       exists $self->data->{$key} }
# sub Text::MetaBib::delete { my ($self, $key) = @_;       delete $self->data->{$key} }

# sub Text::MetaBib::parse {
#     my ($text) = @_;
#     my $data = {};

#     # Avoid SIGPLAN notices if possible
#     $text =~ s/(?=<meta name="citation_journal_title")/\n/g;
#     $text =~ s/(?=<meta name="citation_conference")/\n/g;
#     $text =~ s/<meta name="citation_journal_title" content="ACM SIGPLAN Notices">[^\n]*//
#         if $text =~ m/<meta name="citation_conference"/;

#     my $p = new HTML::Parser;
#     $p->report_tags('meta');
#     $p->handler(start => sub {
#         my %a = %{$_[0]};
#         push @{$data->{lc $a{'name'}}}, $a{'content'} if $a{'name'}; }, 'attr');
#     $p->parse($text);

#     return Text::MetaBib->new(data => $data);
# }

# sub Text::MetaBib::type {
#     my ($self) = @_;
#     my %data = %{$self->data};

#     if (exists $data{'citation_journal_title'}) { return 'article'; }
#     if (exists $data{'citation_conference'}) { return 'inproceedings'; }
#     if (exists $data{'citation_conference_title'}) { return 'inproceedings'; }
#     if (exists $data{'citation_dissertation_institution'}) { return undef; } # phd vs masters
#     if (exists $data{'citation_technical_report_institution'}) { return 'techreport'; }
#     if (exists $data{'citation_technical_report_number'}) { return 'techreport'; }
#     if (exists $data{'citation_patent_number'}) { return 'patent'; }
#     return undef;
# }

# sub uniq {
#     my @result;
#     ITEM: for (@_) {
#         for my $r (@result) {
#             next ITEM if $r eq $_;
#         }
#         push @result, $_;
#     }
#     return @result;
# }

# sub Text::MetaBib::bibtex {
#     my ($self, $entry, @exceptions) = @_;

#     # Save old values that we don't want to change
#     my %old_values;
#     for (@exceptions) {
#         $old_values{$_} = $entry->get($_) if $entry->exists($_);
#     }

#     # The meta-data is highly redundent and multiple fields contain
#     # similar information.  In the following we choose fields that
#     # work for all publishers, but note what other fields also contain
#     # that information.

#     # 'author', 'dc.contributor', 'dc.creator', 'rft_aufirst', 'rft_aulast', and 'rft_au'
#     # also contain authorship information
#     my @authors;
#     if ($self->exists('citation_author')) { @authors = @{$self->get('citation_author')} }
#     elsif ($self->exists('citation_authors')) { @authors = split(';', $self->get('citation_authors')->[0]) }
#     if (@authors) { $entry->set('author', join(' and ', map { s[^ +][]g; s[ +$][]g; $_ } @authors)); }

#     # 'title', 'rft_title', 'dc.title', 'twitter:title' also contain title information
#     $entry->set('title', $self->get('citation_title')->[0]) if $self->exists('citation_title');

#     # test/acm-17.t has the article number in 'citation_firstpage' but no 'citation_firstpage'
#     # test/ieee-computer-1.t has 'pages' but empty 'citation_firstpage'
#     if ($self->exists('citation_firstpage') and $self->get('citation_firstpage')->[0] ne '' and
#         $self->exists('citation_lastpage') and $self->get('citation_lastpage')->[0] ne '') {
#         $entry->set('pages', $self->get('citation_firstpage')->[0] .
#                     ($self->get('citation_firstpage')->[0] ne $self->get('citation_lastpage')->[0] ?
#                      "--" . $self->get('citation_lastpage')->[0] : ""));
#     } elsif ($self->exists('pages')) {
#         $entry->set('pages', $self->get('pages')->[0]);
#     }

#     $entry->set('volume', $self->get('citation_volume')->[0]) if $self->exists('citation_volume');
#     $entry->set('number', $self->get('citation_issue')->[0]) if $self->exists('citation_issue');

#     # 'keywords' also contains keyword information
#     $entry->set('keywords',
#         join('; ', map { s/^\s*;*//; s/;*\s*$//; $_ } uniq(@{$self->get('citation_keywords')})))
#         if $self->exists('citation_keywords');

#     # 'rft_pub' also contains publisher information
#     if ($self->exists('dc.publisher')) { $entry->set('publisher', $self->get('dc.publisher')->[0]) }
#     elsif ($self->exists('citation_publisher')) { $entry->set('publisher', $self->get('citation_publisher')->[0]) }
#     elsif ($self->exists('st.publisher')) { $entry->set('publisher', $self->get('st.publisher')->[0]) }

#     # 'dc.date', 'rft_date', 'citation_online_date' also contain date information
#     if ($self->exists('citation_publication_date')) {
#         if ($self->get('citation_publication_date')->[0] =~ m[^(\d{4})[/-](\d{2})[/-](\d{2})$]) {
#             my ($year, $month, $day) = ($1, $2, $3);
#             $entry->set('year', $year);
#             $entry->set('month', num2month($month)->[1]);
#         }
#     } elsif ($self->exists('citation_date')) {
#         if ($self->get('citation_date')->[0] =~ m[^(\d{2})[/-](\d{2})[/-](\d{4})$]) {
#             my ($month, $day, $year) = ($1, $2, $3);
#             $entry->set('year', $year);
#             $entry->set('month', num2month($month)->[1]);
#         } elsif ($self->get('citation_date')->[0] =~ m[^[ 0-9-]*?\b(\w+)\b[ .0-9-]*?\b(\d{4})\b]) {
#             my ($month, $year) = ($1, $2);
#             $entry->set('year', $year);
#             $entry->set('month', str2month($month)->[1]);
#         }
#     }

#     # 'dc.relation.ispartof', 'rft_jtitle', 'citation_journal_abbrev' also contain collection information
#     if ($self->exists('citation_conference')) { $entry->set('booktitle', $self->get('citation_conference')->[0]) }
#     elsif ($self->exists('citation_journal_title')) { $entry->set('journal', $self->get('citation_journal_title')->[0]) }
#     elsif ($self->exists('citation_inbook_title')) { $entry->set('booktitle', $self->get('citation_inbook_title')->[0]) }
#     elsif ($self->exists('st.title')) { $entry->set('journal', $self->get('st.title')->[0]) }

#     # 'rft_id' and 'doi' also contain doi information
#     if ($self->exists('citation_doi')) { $entry->set('doi', $self->get('citation_doi')->[0]) }
#     elsif ($self->exists('st.discriminator')) { $entry->set('doi', $self->get('st.discriminator')->[0]) }
#     elsif ($self->exists('dc.identifier') and $self->get('dc.identifier')->[0] =~ m[^doi:(.+)$]) { $entry->set('doi', $1) }

#     # If we get two ISBNs then one is online and the other is print so
#     # we don't know which one to use and we can't use either one
#     if ($self->exists('citation_isbn') and 1 == @{$self->get('citation_isbn')}) {
#         $entry->set('isbn', $self->get('citation_isbn')->[0])
#     }

#     # 'rft_issn' also contains ISSN information
#     if ($self->exists('citation_issn') and 1 == @{$self->get('citation_issn')}) {
#         $entry->set('issn', $self->get('citation_issn')->[0]);
#     } elsif ($self->exists('st.printissn') and $self->exists('st.onlineissn')) {
#         $entry->set('issn', $self->get('st.printissn')->[0] . " (Print) " . $self->get('st.onlineissn')->[0] . " (Online)");
#     }

#     if ($self->exists('citation_language')) { $entry->set('language', $self->get('citation_language')->[0]) }
#     elsif ($self->exists('dc.language')) { $entry->set('language', $self->get('dc.language')->[0]) }

#     # 'dc.description' also contains abstract information
#     if ($self->exists('description')) {
#         for my $d (@{$self->get('description')}) {
#             $entry->set('abstract', $d) if $d ne '' and $d ne '****' and $d !~ /^(IEEE Xplore|IEEE Computer Society)/;
#         }
#     }

#     $entry->set('affiliation', join(' and ', @{$self->get('citation_author_institution')}))
#         if $self->exists('citation_author_institution');

#     # Restore values that we don't want to change
#     for (@exceptions) {
#         if (exists $old_values{$_}) { $entry->set($_, $old_values{$_}); }
#         else { $entry->delete($_); }
#     }
# }

###### Other fields
##
## Some fields that we are not using but could include the following.
## (The numbers in front are how many tests could use that field.)
##
#### Article
##     12 citation_author_email (unused: author e-mail)
##
#### URL (unused)
##      4 citation_fulltext_html_url (good: url)
##      7 citation_public_url (unused: page url)
##     10 citation_springer_api_url (broken: url broken key)
##     64 citation_abstract_html_url (good: url may dup)
##     69 citation_pdf_url (good: url may dup)
##
#### Misc (unused)
##      7 citation_section
##      7 issue_cover_image
##      7 citation_id (unused: some sort of id)
##      7 citation_id_from_sass_path (unused: some sort of id)
##      7 citation_mjid (unused: some sort of id)
##      7 hw.identifier
##     25 rft_genre (always "Article")
##      8 st.datatype (always "JOURNAL")
##     25 rft_place (always "Cambridge")
##        citation_fulltext_world_readable (always "")
##      9 article_references (unused: textual version of reference)
##
###### Non-citation related
##      7 hw.ad-path
##      8 st.platformapikey (unused: API key)
##      7 dc.type (always "text")
##     14 dc.format (always "text/html")
##      7 googlebot
##      8 robots
##      8 twitter:card
##      8 twitter:image
##      8 twitter:description
##      8 twitter:site
##     17 viewport
##     25 coins
##     10 msapplication-tilecolor
##     10 msapplication-tileimage
##     25 test
##     25 verify-v1
##     35 format-detection
