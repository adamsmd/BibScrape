 - All fields except 'doi' and 'url' are escaped.  The 'doi' and 'url' fields
   are not escaped on the assumption that you are using the Latex url package.

 - Fields are stripped to bare values. For example, leading 'ABSTRACT', 'p.' or 'doi:'
   are stripped from the 'abstract', 'pages' and 'doi' fields respectively.

 - The 'url' field is omitted if it just points back to the publisher's page.

 - The 'note' field is omitted if it just contains the 'doi'.

 - Unicode and some form formatting (e.g. superscripts) use the correct Latex codes.

 - Ranges (e.g. pages) use "--" instead of "-".  (Note, this be
   incorrect for the 'number' field of a @techreport.)

 - Full journal names are used when available instead of
   abbreviations.

 - Fields are put in a standard order.

 - Entry keys are generated as "last-name-of-first-author:year:doi"
   or when there is no doi as "last-name-of-first-author:year".
   (This needs improvement.)

 - The 'issue' and 'keyword' fields are renamed to 'number' and
   'keywords' respectively.

 - For ACM, the conference proceedings are preferred over SIGPLAN Notices.

 - And much more ...

- Data from the publishers is often wrong.  In particular, formatting of author
  names is the biggest problem.  The data from the publishers is often
  incomplete or incorrect.  For example, I've found 'Blume' misspelled as 'Blu',
  'Bruno C.d.S Oliviera' listed as 'Bruno Oliviera' and 'Simon Peyton Jones'
  listed as 'Jones, Simon Peyton'.  See the `config/names.cfg` file for how to
  fix these.

doi and url should *not* be escaped if using the url package
All fields should be bare values (except perhaps 'note'):
  e.g. doi should not have 'doi:' or 'http://dx.doi.org/' at the front
       (one publisher even has 'doi: DOI:' at the front!
  e.g. abstract should not have the word "ABSTRACT" at the front
  e.g. pages should not have "p." or "pp." in it.
use url field for urls not the howpublished field
doi, isbn, issn should be present if available
names (e.g. author, editor) should be formatted "von last, first, jr"
  This is the only unambiguous format for latex
  Note RIS uses "last, jr, first"
url and note should be present only if it adds information
  Most publishers break this rule by linking to
  the publishers publication page.  It is
  understandable that they link there, but the
  URL doesn't actually add anything to the citation.
capitals:
  - Use proper capitalization (e.g. titlecase for titles).
    Even if your current bibliography style downcases titles,
    other styles may not.
  - Use {} to protect only characters that should
    not be upcased or downcased.  Thus "{H}askell"
    not "{Haskell}" since the latter would brake
    styles that upcase the text.
    - Unfortunately this means you can't grep for "Haskell"
      in your bibliography but even with "{Haskell}" you wouldn't
      be able to grep "Template Haskell".
      - As a workaround use "tr -d {}" to eliminate braces
        from the text before running grep.  (Feedback on better
        workarounds is welcome.)
no blank or zero fields
ranges are x--x
  - BibTeX accepts "x-x" but only for backwards compatibility purposes.
  - Page ranges are comma separated.
  - Single element "x" and multi-element "x+" ranges are allowed.
special chars are {\"o} not \"{o} (See the BibTeX FAQ)
journal is unabriviated
edition is "1st"???
quotes are proper form
Use a comma after the last field.  It is legal and makes copy-paste easier.
Continuously paginated journals
Non-sentensial periods

Does bibtex replace "K. Dybvig" with "K.~Dybvig"?

\usepackage{url} to get doi and url right in BibTeX
\usepackage{comment}
\usepackage{alstpage} \thepage of \pageref{LastPage}\us
epackage{fancyhdr}
\usepackage{flushend} instead of \usepackage{balance}


%include lhs2TeX.fmt

%subst keyword a = "{\itshape " a "}"
%subst conid a   = a
\def\subalign{\rule{1pt}{0pt}}
%
format . = "."
%format <- = "{\char24}"
%format -> = "{\char25}"
%format _c = "{c}"
%format _ctxt = "{ctxt}"
%format _s = "{s}"
%format _f = "{f}"
%format _t1 = "{t$_{\text{1}}$\subalign}"
%format _t2 = "{t$_{\text{2}}$\subalign}"
%format _t3 = "{t$_{\text{3}}$\subalign}"
%format move1 = "{move$_{\text{1}}$\subalign}"
%format move2 = "{move$_{\text{2}}$\subalign}"

%options ghci
%if False
...
%endif

\begin{comment}
\eval{let itype arg = return ("let it = (" ++arg++")\n:type it")}
\end{comment}
\begin{comment}
\eval{:def itype itype}
\end{comment}

lhs2TeX --tt $DOC.lhs >$DOC.tex && \
cp $DOC.tex $DOC.pre-tex && \
latex $DOC && \
bibtex $DOC && \
latex $DOC && \
latex $DOC && \
dvips $DOC && \
ps2pdf14 -dPDFSETTINGS=/prepress $DOC.ps

ghc -E $DOC.lhs -o $DOC.hspp && \
sed -e ':s ;/^$/N;s/^\n$//;ts' $DOC.hspp | tail -n +4 > $DOC.hs

(install PGF)
mathpartir for proof trees

overfull-line bars
itemize: \parskip, $-$





------------------------

author, editor, title

author,           title, journal,                              year.
author or editor, title,                            publisher, year.
                  title. 
author or editor, title,            chapter, pages, publisher, year. 
author,           title, booktitle,                 publisher, year. 
author,           title, booktitle,                            year. 
                  title.
author,           title, school,                               year. 
author,           title, school,                               year.
                  title,                                       year.
author,           title, institution,                          year.
author,           title,                                             note. 

volume, number,                          pages,                   month,                                note.
volume or number, series,                       address, edition, month,                                note.
howpublished,                                   address,          month, year,                          note.
volume or number, series, type,                 address, edition, month,                                note.
volume or number, series, type, chapter, pages, address, edition, month,                                note.
volume or number, series,                pages, address,          month,       organization, publisher, note.
organization,                                   address, edition, month, year,                          note.
                          type,                 address,          month,                                note.
howpublished,                                                     month, year,                          note.
                          type,                 address,          month,                                note.
volume or number, series,                       address,          month,       organization, publisher, note.
type, number,                                   address,          month,                                note.
                                                                  month,                                year.

author or editor, title, booktitle, journal, chapter, pages,                          publisher/year. 
             volume,   number, series, type, chapter, pages, address, edition, month, year, organization, publisher, note.
howpublished < address


author or editor, title, journal, booktitle, chapter, pages,                          publisher/year. 
             volume,   number, series, type, chapter, pages, address, edition, month, year, organization, publisher, note.
howpublished < address

  { "  author = {" author * "}," * write.line } author if.nonnull
  { "  editor = {" editor * "}," * write.line } editor if.nonnull
affiliation 
  { "  title = {" title * "}," * write.line } title if.nonnull

  { "  howpublished = {" howpublished * "}," * write.line } howpublished if.nonnull
  { "  booktitle = {" booktitle * "}," * write.line } booktitle if.nonnull
C { "  journal = {" journal * "}," * write.line } journal if.nonnull
C { "  volume = {" volume * "}," * write.line } volume if.nonnull
C { "  number = {" number * "}," * write.line } number if.nonnull
  { "  series = {" series * "}," * write.line } series if.nonnull
jstor_issuetitle 

  { "  type = {" type * "}," * write.line } type if.nonnull
jstor_articletype 
  { "  school = {" school * "}," * write.line } school if.nonnull
  { "  institution = {" institution * "}," * write.line } institution if.nonnull
location 

  { "  chapter = {" chapter * "}," * write.line } chapter if.nonnull
  { "  pages = {" pages * "}," * write.line } pages if.nonnull
articleno 
numpages 

  { "  edition = {" edition * "}," * write.line } edition if.nonnull
  { "  month = {" month * "}," * write.line } month if.nonnull
  { "  year = {" year * "}," * write.line } year if.nonnull
issue_date 
jstor_formatteddate 

  { "  organization = {" organization * "}," * write.line } organization if.nonnull
  { "  publisher = {" publisher * "}," * write.line } publisher if.nonnull
  { "  address = {" address * "}," * write.line } address if.nonnull

language

  { "  isbn = {" isbn * "}," * write.line } isbn if.nonnull
  { "  issn = {" issn * "}," * write.line } issn if.nonnull
  { "  doi = {" doi * "}," * write.line } doi if.nonnull
acmid 
  { "  eid = {" eid * "}," * write.line } eid if.nonnull
  { "  url = {" url * "}," * write.line } url if.nonnull
eprint 

  { "  note = {" note * "}," * write.line } note if.nonnull
anote
keywords 
abstract
copyright 
