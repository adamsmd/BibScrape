# bib-scrape

Install `perl6` and `zef`.
zef
python2
## Setup

### Install `raku`

    $ sudo apt install perl6

### Development Tools for Python 2.7
    $ sudo apt install python2-dev

Cannot locate native library '(null)': libpython2.7.so.1.0: cannot open shared object file: No such file or directory

### Install Raku Modules

Install `zef`
    $ zef install ArrayHash HTML::Entity Inline::Python Locale::Codes XML

### Install `geckodriver`

    $ sudo apt install firefox-geckodriver

### Deps folder

## Usage

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

--headless

Browser page load timeout

## Notes

We use python 2.7 because Inline::Python doesn't support python 3 yet.
Once we have python 3, we can use the urllib3 that comes with python.

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
