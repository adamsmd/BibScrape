# BibScrape: Automatically collect BibTeX entries from publisher websites

**This version depends on the `python3` branch of `Inline::Python`.  Until that
is released upstream, you may have trouble setting up BibScrape.**

This is a BibTeX scraper for collecting BibTeX entries from the websites of
computer-science academic publishers.  I use it personally to make preparing my
BibTeX files easier, but more importantly it makes sure all entries are
consistent. For example, it prevents having "ACM" as the publisher in one place
but "Association for Computing Machinery" in another.

Currently, BibScrape supports the following publishers:

- ACM (`acm.org`)
- Cambridge Journals (`cambridge.org`)
- IEEE Computer Society (`computer.org`)
- IEEE Explore (`ieeexplore.ieee.org`)
- IOS Press (`iospress.com`)
- JSTOR (`jstor.org`)
- Oxford Journals (`oup.org`)
- Science Direct / Elsevier (`sciencedirect.com` and `elsevier.com`)
- Springer (`link.springer.com`)

In addition, this scraper fixes common problems with the BibTeX entries that
these publishers produce.  For example, it fixes:

- the handling of Unicode and other formatting (e.g., subscripts) in titles;
- the incorrect use of the 'issue' field instead of the 'number' field;
- the format of the 'doi' and 'pages' fields;
- the use of macros for the 'month' field; and
- *numerous* miscellaneous problems with specific publishers.

For a complete list of features and fixes see [`FEATURES.md`](FEATURES.md).

## Usage

The basic usage is:

    bibscrape <url> ...

Each `<url>` is the URL of the publishers page of an article to scrape.
Alternatively, if a `<url>` starts with `doi:`, it is interpreted as the DOI of
an article to scrape.

For example:

    $ bibscrape 'https://portal.acm.org/citation.cfm?id=1411204.1411243'
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

See the files in [`tests/`](tests) for more examples and what their outputs look
like.  (The output starts on the fourth line of those files.  The first three
lines are metadata.)

For more details on usage and command-line flags run:

    bibscrape --help

## Disclaimer

Please use this software responsibly.  You are responsible for how you use it.
It does not contain any bandwidth limiting code as most publisher pages respond
slowly enough that it is usually not necessary.  However, I've only tested it
for preparing small bibliographies with fewer than 100 entries.  If you try to
scrape too many at a time, I make no guarantees that you won't accidentally DoS
the publisher.

## Limitations

- Many heuristics are involved in scraping and fixing the data.  This in an
  inherently fuzzy task.

- To collect information from publisher pages, often 2-3 pages have to be
  loaded, and publisher pages can be slow.  On average, it takes around 10-30
  seconds per citation.

- Always double check the "title", "author" and "abstract" fields in the output
  BibTeX.  Other fields will generally be right, but publishers sometimes do
  strange things with LaTeX, Unicode or unusually formatted names.  Though
  BibScrape has heuristics that try to resolve these, sometimes something goes
  wrong.

## Tips

- BibScrape's version number indicate the approximate date on which the software
  was last updated.  For example, version 20.08.01 corresponds to August 1,
  2020.  As publishers change their web pages, old versions of BibScrape will no
  longer work correctly.

- Sometimes publisher pages don't load properly and an error results.  Often
  re-running BibScrape fixes the problem.

- Sometimes publisher pages stall and don't finish loading.  If BibScrape takes
  longer than 60 seconds for one BibTeX entry, the publisher page has probably
  stalled.  Often, re-running BibScrape fixes the problem.

- If a publisher page consistently hangs or errors, use `--show-window` to show
  the browser window and see what is going on.

- If an author name is formatted wrong is wrong, add an entry to your names file.

## Setup

### Dependencies

#### Perl 6/Raku and Zef

If on Ubuntu, the following will install both Perl 6 and Zef.

    $ sudo apt install perl6

Alternatively, install [`rakubrew`](https://rakubrew.org/) (including running
`rakubrew init` if needed) and then run the following:

    $ rakubrew build
    $ rakubrew build-zef

#### Python 3 and the Development Tools for Python 3

    $ sudo apt install python3 python3-dev

#### Firefox and `geckodriver`

    $ sudo apt install firefox firefox-geckodriver

#### Perl 6/Raku Modules

    $ zef install ArrayHash HTML::Entity Locale::Codes Temp::Path XML

Install `Inline::Python`
    git clone
    cd
    git checkout python3
    zef install . --exclude=python3

#### Python Modules

    $ pip3 install selenium

### Installation

    $ zef install

### Per User Initialization

    $ bibscrape --init

This creates default names and nouns files in `~/.config/BibScrape/`.

## Feedback

If you have any problems or suggestions, feel free to contact me.  I am
particularly interested in any articles for which BibScrape breaks or formats
incorrectly and any BibTeX fixes that you think should be included.

I am also interested in collecting pages that test things like articles that
have Unicode in their titles and so forth.

However, since I am the only maintainer and there are hundreds of publishers, I
have to limit what publishers to support.  If you find a computer-science
publisher that I forgot, let me know and I'll add it.  I'm more hesitant to add
publishers from other fields.  Also, as a matter of policy, I prefer to scrape
from publisher pages instead of from aggregators (e.g., BibSonomy, DBLP, etc.)
as aggregators are much less predictable in the sorts of errors they introduce.

### How to file issues

Software versions

    bibscrape --version
    uname -a
    perl6 --version
    zef --version
    python3 --version
    firefox --version
    geckodriver --version
    zef info ArrayHash HTML::Entity Inline::Python Locale::Codes Temp::Path XML
    pip3 info selenium

Command line you used to invoke BibScrape including any flags

The BibTeX you expected to get from BibScrape

The BibTeX you actually got from BibScrape

## License

Copyright (C) 2011-2020  Michael D. Adams [`<https://michaeldadams.org/>`](https://michaeldadams.org/)

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
