# BibScrape: Scrape and Fix BibTeX Entries from Publisher Websites

BibScrape is a BibTeX scraper for collecting BibTeX entries from the websites of
computer-science academic publishers.  I use it personally to make preparing my
BibTeX files easier, but more importantly it makes sure all entries are
consistent.  For example, it prevents having "ACM" as the publisher in one entry
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

In addition, BibScrape fixes common problems with the BibTeX entries that these
publishers produce.  For example, it fixes:

- the handling of Unicode and other formatting (e.g., subscripts) in titles,
- the incorrect use of the `issue` field instead of the `number` field,
- the format of the `doi` and `pages` fields,
- the use of macros for the `month` field and
- *numerous* miscellaneous problems with specific publishers.

For a complete list of features and fixes see [`FEATURES.md`](FEATURES.md).

## Usage

The basic usage is:

    bibscrape <arg> ...

Each `<arg>` is either a publisher's pages to be scraped or a BibTeX file to be
read and re-scraped or fixed.

- If an `<arg>` starts with 'http:' or 'https:', it is interpreted as a URL.
- If an `<arg>` starts with 'doi:', it is interpreted as a DOI.
- If an `<arg>` is '-', BibTeX entries are read from standard input.
- Otherwise, an `<arg>` is a filename from which BibTeX entries are read.

For example:

    $ bibscrape 'https://portal.acm.org/citation.cfm?id=1614435'
    @article{Benedikt:2009:10.1145/1614431.1614435,
      author = {Benedikt, Michael and Segoufin, Luc},
      title = {Regular tree languages definable in {FO} and in {FO}\textsubscript{\textit{mod}}},
      journal = {ACM Transactions on Computational Logic (TOCL)},
      volume = {11},
      number = {1},
      pages = {4:1--4:32},
      articleno = {4},
      numpages = {32},
      month = oct,
      year = {2009},
      issue_date = {October 2009},
      publisher = {Association for Computing Machinery},
      address = {New York, NY, USA},
      issn = {1529-3785},
      doi = {10.1145/1614431.1614435},
      bib_scrape_url = {https://portal.acm.org/citation.cfm?id=1614435},
      keywords = {Regular tree languages; first-order logic},
      abstract = {We consider regular languages of labeled trees. We give an effective characterization of the regular languages over such trees that are definable in first-order logic in the language of labeled graphs. These languages are the analog on trees of the {\textquotedblleft}locally threshold testable{\textquotedblright} languages on strings. We show that this characterization yields a decision procedure for determining whether a regular tree language is first-order definable: The procedure is polynomial time in the minimal automaton presenting the regular language. We also provide an algorithm for deciding whether a regular language is definable in first-order logic supplemented with modular quantifiers.},
    }

You could also run the following to get the same result:

    bibscrape 'doi:10.1145/1614431.1614435'

See the files in [`tests/`](tests/) for more examples and what their outputs
look like.  (The first three lines of those files are metadata.  Outputs start
on the fourth line.)

For more details on usage and command-line flags run:

    bibscrape --help

Alternatively, read [`HELP.txt`](HELP.txt), which is a simply a copy of the
output of `bibscrape --help`.

## Disclaimer

Since BibScrape is sending network traffic to publisher web pages, please use
this software responsibly.  You are solely responsible for how you use it.
BibScrape does not contain any bandwidth limiting code as most publisher pages
respond slowly enough that it is usually not necessary.  However, I've only
tested it for preparing small bibliographies with fewer than 100 entries.  If
you try to scrape too many at a time, I make no guarantee that you won't get IP
banned or accidentally DoS the publisher.

## Limitations

- Many heuristics are involved in scraping and fixing the data.  This in an
  inherently fuzzy task.

- To collect information from publisher pages, often 2-3 pages have to be
  loaded, and publisher pages can be slow.  As a result, BibScrape takes around
  10-30 seconds per BibTeX entry.

- You should always manually check the `title`, `author` and `abstract` fields
  in the output BibTeX.  Other fields will generally be right, but publishers
  sometimes do strange things with LaTeX, Unicode or uncommon name formats.
  Though BibScrape has heuristics that try to resolve these, sometimes something
  goes wrong.

## Tips

- Make a habit of putting single quotes around URLs (as seen in the usage
  examples above) in case they contain things like `&` or `?`.

- BibScrape's version number indicates the approximate date on which the
  software was last updated.  For example, version 20.08.01 corresponds to
  August 1, 2020.  As publishers change their web pages, old versions of
  BibScrape may no longer work correctly.

- Sometimes publisher pages don't load properly and an error results.  Often
  times, re-running BibScrape fixes the problem.

- Sometimes publisher pages stall and don't finish loading, which causes
  BibScrape to hang.  If BibScrape takes longer than 60 seconds for one BibTeX
  entry, the publisher page has probably stalled.  Often times, re-running
  BibScrape fixes the problem.

- If a publisher page consistently hangs or errors, use `--window` to show the
  browser window and see what is going on.

- If an author name is formatted wrong, add an entry to your names file.  See
  the "NAMES FILES" section of `bibscrape --help`.

- If a title contains a proper noun that needs to be protected from lower
  casing, add an entry to your nouns file.  See the "NOUNS FILES" section of
  `bibscrape --help`.

- By default, the `url` and `doi` fields are not LaTeX escaped.  Using BibTeX
  entries with these field may thus require that your LaTeX document use the
  `url` package.

## Setup

The following setup instructions assume you are on Ubuntu.  Modify them as
needed for your platform.

### Dependencies

#### Perl 6/Raku and Zef

Run the following to install both Perl 6 and Zef.

    sudo apt install perl6

Alternatively, install [`rakubrew`](https://rakubrew.org/) (including running
`rakubrew init` if needed) and then run the following where `<version>` is the
Raku version installed (e.g., `moar-2020.08.2`) as reported in the last line of
the output of `rakubrew build` (e.g., `Rakudo has been built and installed.
Done, moar-2020.08.2 built`):

    rakubrew build
    rakubrew switch <version>
    rakubrew build-zef

Whichever you do, make sure the language version is at least `6.d`, as in the
following.

    $ perl6 --version
    This is Rakudo version 2020.07 built on MoarVM version 2020.07
    implementing Raku 6.d.

#### Python 3 and the Development Tools for Python 3

    sudo apt install python3 python3-dev

#### Selenium for Python 3

    pip3 install selenium

#### Firefox and `geckodriver`

    sudo apt install firefox firefox-geckodriver

### Non-Installed Mode

If you want to run BibScrape without installing it, run the following from the
directory in which the BibScrape source resides:

    zef install --deps-only --exclude=python3 .

Then you can run BibScrape with the following where `<DIR>` is the directory in
which the BibScrape source resides.

    <DIR>/bin/bibscrape <arg> ...

### Installed Mode

If you want to install BibScrape, run the following from the directory in which
the BibScrape source resides:

    zef install --exclude=python3 .

Then you can run the `bibscrape` command from anywhere.

### Per User Initialization

Every user that uses BibScrape, must run the following to create the default
names and nouns files.

    bibscrape --init

Run `bibscrape --config-dir` to find out where those files are created.

### Testing

The [`tests/`](tests/) folder contains tests for each publisher.  You can run
them using [`test.sh`](test.sh).  For example to run all the ACM tests, run the
following command:

    ./test.sh tests/acm-*.t

Note that publisher pages aren't the most reliable, so if a test fails, you
should re-run that particular test to make sure it isn't a transient issue.

## Feedback

If you have any problems or suggestions, feel free to create a GitHub issue
about it.  I am particularly interested in any publications for which BibScrape
breaks or that it formats incorrectly as well as any BibTeX fixes that you think
should be added to BibScrape.

I am also interested in collecting publisher pages that test things like
articles that have Unicode in their titles and so forth.

However, since I am the only maintainer and there are hundreds of publishers, I
have to limit what publishers to support.  If you find a computer-science
publisher that I forgot, let me know and I'll add it.  I'm more hesitant to add
publishers from other fields.  Also, as a matter of policy, I prefer to scrape
from publisher pages instead of from aggregators (e.g., BibSonomy, DBLP, etc.)
as aggregators are much less predictable in the sorts of BibTeX mistakes they
introduce.

### How to file issues

Please include the following information in any issues you file:

- Software versions as output from the following commands:

    bibscrape --version
    uname -a
    perl6 --version
    zef --version
    python3 --version
    firefox --version
    geckodriver --version
    zef info ArrayHash HTML::Entity Inline::Python Locale::Codes Temp::Path XML
    pip3 info selenium

- The command line you used to invoke BibScrape including flags and arguments

- The BibTeX you expected to get from BibScrape

- The BibTeX you actually got from BibScrape

## License

    Copyright (C) 2011-2020  Michael D. Adams <https://michaeldadams.org/>

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
