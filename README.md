# BibScrape: Automatically collect BibTeX entries from publisher websites

This is a BibTeX scraper for collecting BibTeX entries from the websites of
computer-science academic publishers.  I use it personally to make preparing my
BibTeX files easier, but more importantly it makes all entries are consistent.
For example, it prevents having "ACM" as the publisher in one place but
"Association for Computing Machinery" in another.

Currently it supports the following publishers:

- ACM `<acm.org>`
- Cambridge Journals `<cambridge.org>`
- IEEE Computer Society `<computer.org>`
- IEEE Explore `<ieeexplore.ieee.org>`
- IOS Press `<iospress.com>`
- JSTOR `<jstor.org>`
- Oxford Journals `<oup.org>`
- Science Direct `<sciencedirect.com>` / Elsevier `<elsevier.com>`
- Springer `<link.springer.com>`

In addition, this scraper fixes common problems with the BibTeX that
these services provide.  For example, it fixes:

- the handling of Unicode and other formatting (e.g. subscripts) in titles;
- the incorrect use of the 'issue' field instead of the 'number' field;
- the format of the 'doi' and 'pages' fields;
- the use of macros for the 'month' field; and
- *numerous* miscellaneous problems with specific publishers.

For a complete list of fixes see `FIXES.md`.

## Usage

The basic usage is:

    bibscrape <url> ...

Each URL is the publishers page of an article to scrape.  Alternatively, if a
URL starts with `doi:`, it is interpreted as the DOI of an article to scrape.

For example:

    $ ./bib-scrape.raku 'https://portal.acm.org/citation.cfm?id=1411204.1411243'

    @inproceedings{VanHorn:2008:10.1145/1411204.1411243,
      author = {Van Horn, David and Mairson, Harry G.},
      title = {Deciding \textit{k}{CFA} is complete for {EXPTIME}},
      booktitle = {Proceedings of the 13th ACM SIGPLAN International Conference on Functional Programming},
      series = {ICFP~'08},
      location = {Victoria, BC, Canada},
      pages = {275--282},
      numpages = {8},
      month = sep,
      year = {2008},
      publisher = {Association for Computing Machinery},
      address = {New York, NY, USA},
      isbn = {978-1-59593-919-7},
      doi = {10.1145/1411204.1411243},
      bib_scrape_url = {https://portal.acm.org/citation.cfm?id=1411204.1411243},
      keywords = {complexity; flow analysis},
      abstract = {We give an exact characterization of the computational complexity of the \textit{k}CFA hierarchy. For any \textit{k} {\textgreater} 0, we prove that the control flow decision problem is complete for deterministic exponential time. This theorem validates empirical observations that such control flow analysis is intractable. It also provides more general insight into the complexity of abstract interpretation.},
    }

Other examples you can try are:

    bibscrape 'https://portal.acm.org/citation.cfm?id=1614435'
    bibscrape 'https://www.springerlink.com/content/nhw5736n75028853/'
    bibscrape 'doi:10.1007/BF01975011'

See the files in `t/` for examples of what outputs look like. (The output starts
on the fourth line of those files.  The first three lines are test metadata.)

For more details on usage and command-line flags run:

    bibscrape --help

## Dependencies

### Install `perl6`/`raku` and `zef`

If on Ubuntu the following will install both perl6 and zef

    $ sudo apt install perl6

Alternatively, install `rakubrew` (including `rakubrew init`) then run the following:

    $ rakubrew build
    $ rakubrew build-zef

### Development Tools for Python 3

    $ sudo apt install python3-dev

Cannot locate native library '(null)': libpython2.7.so.1.0: cannot open shared object file: No such file or directory

python3 and pip3 (comes with python3)

pip3 install selenium

### Install Raku Modules

Install `zef`

    $ zef install ArrayHash HTML::Entity Inline::Python Locale::Codes XML

### Install `geckodriver`

    $ sudo apt install firefox-geckodriver

### Deps folder

## Building

## Tips

sometimes pages hang
--show-window
sometimes pages error

## FAQ

What about ZotBib?

Online service?

Option to show firefox window

## How to file issues

    perl6 -M Inline::Python -e 'Inline::Python.new'


URL

How you invoked bib-scrape (e.g., any flags)

Expected BibTeX

Actual BibTeX








# Disclaimer

Please use this software responsibly.  You are responsible for how you use it.
It does not contain any bandwidth limiting code as most publisher pages respond
slowly enough that it is usually not necessary.  However, I've only tested it
for preparing small bibliographies with fewer than 100 entries.  If you try to
scrape too many at a time, I make no guarantees that you won't accidentally DoS
the publisher.

Feedback
================
If you have any problems or suggestions, feel free to contact me.  I
am particularly interested in any articles on which that bib-scrape breaks
or formats incorrectly, and any BibTeX fixes that you think should be
included.

Until I build up my test suite, I am also interested in collecting
pages that test things like articles that have Unicode in their titles
and so forth.

However, since I am the only maintainer and there are hundreds of
publishers, I have to limit what publishers to support.  If you find a
computer-science publisher that I forgot, let me know and I'll add it.
I'm more hesitant to add publishers from other fields.  Also, as a
matter of policy, I prefer to scrape from publisher pages instead of
from aggregators (e.g. BibSonomy, DBLP, etc.) as aggregators are much
less predictable in the sorts of errors they introduce.

You can find my contact information at https://michaeldadams.org/

Features
================
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

## Limitations

- Basically don't trust the "title", "author" and "abstract" fields. Other
  fields will generally be right, but these fields often have Latex code that
  don't get preserved by the publishers. Though bib-scrape will do it's best,
  the results are often spotty. Example $O$$($n$)$.

- Data from the publishers is often wrong.  In particular, formatting of author
  names is the biggest problem.  The data from the publishers is often
  incomplete or incorrect.  For example, I've found 'Blume' misspelled as 'Blu',
  'Bruno C.d.S Oliviera' listed as 'Bruno Oliviera' and 'Simon Peyton Jones'
  listed as 'Jones, Simon Peyton'.  See the `config/names.cfg` file for how to
  fix these.

- Many heuristics are involved in scraping and fixing the data.  This in an
  inherently fuzzy area.

- Often 2-3 pages have to be loaded and publisher pages can be slow. In total it
  takes around 15 seconds per citation.

- There are many BibTeX problems that this program can't fix:

  - The 'howpublished' field shouldn't be used for URLs.  Use the url field for
    that.
  - Names should be 'von last, first, jr' as it is the only unambiguous format
    in BibTeX.
  - Proper names in titles should be capitalized with braces (e.g. "{H}askell").

- Complex math in titles or abstracts is likely to break.  A couple superscripts
  and Greek characters are fine, but more than that is trouble.

 - Complex math in titles or abstracts is likely to break.  A couple superscripts and
   Greek characters are fine, but more than that is trouble.

## License

Copyright (C) 2011-2020  Michael D. Adams `<https://michaeldadams.org/>`

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
