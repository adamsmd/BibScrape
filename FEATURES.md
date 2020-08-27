# BibScrape Features

## Command line interface

For details on any of the following options see `bibscrape --help` or
`HELP.txt`.

- Takes multiple URLs or filenames as input.

  - URLs can be `http://`, `https://`, or `doi:`.

  - Files are read for BibTeX entries to update.

  - When the filename is `-`, reads BibTeX entries from standard input.

- Explicit keys to use in the output can be specified with the `--key` flag.

- Custom names and nouns files can be specified with the `--names` and `--nouns`
  flags.

- Custom names and nouns can be specified with the `--name` and `--noun` flags,
  without needing to put them in a file.

- Can run just scraping or just fixing by disabling either scraping with
  `--/scrape` or fixing with `--/fix`.

- Uses a real browser with a hidden window to collect publication information.
  Show this window with `--window`.

- Includes a controllable timeout for individual page loads with `--timeout`.

- For ISSN and ISBN, can prefer either print, online or both when both are
  available.  See `--issn-media` and `--isbn-media`.

- For ISBN, can convert to either ISBN-10 or ISBN-13 when possible.  See
  `--isbn-type`.

- Has a configurable ISBN separator.  See `--isbn-sep`.

- The order of fields can be controlled.  See `--field`.

- Fields can be excluded from LaTeX encoding.  See `--no-encode`.

- Fields can be explicitly omitted.  See `--omit`.

- Fields can be omitted if they are empty.  See `--omit-empty` flag.

## BibTeX Fixes

- Removes `http://doi.org`, `doi:` and similar from the front of the `doi`
  field.

- Removes `p.` and `pp.` from the front of the `pages` field.

- Renames the `issue` and `keyword` fields (which are used by Springer and ACM)
  to `number` and `keywords` respectively.

- Makes ranges (e.g., `pages` or `volumes`) use `--` instead of `-`.

- Checks that the `pages` field is sane.

- Checks that the `volume` field is sane.

- Checks that the `number` field is sane.

- Converts the `isbn` field to ISBN-13 or ISBN-10 depending on the
  `--isbn-type` flag.

- Checks that the `isbn` field has a correct checksum.

- Selects the print or online `isbn` depending on the `--isbn-media` flag.

- Checks that the `issn` field has a correct checksum.

- Selects the print or online `issn` depending on the `--issn-media` flag.

- Expands language codes (e.g., `en`) in the `language` field into their full
  name (e.g., `English`).

- TODO: author

- TODO: editor

- Removes the `url` field if it is just a link to the publisher's page.

- Removes the `notes` field if it just stores the DOI.  (Springer does this.)

- Translates Unicode, HTML and MathML to LaTeX for all fields except the ones
  listed in `--no-encode`.

- Puts the `series` field in a canonical form (e.g., `PEPM~'97`).

- Collapses multiple spaces or newlines into a single space for all fields
  except the ones listed in `--no-collapse`.

- In the `title` field, wraps acronyms (e.g., two or more uppercase characters
  in a row) with braces so BibTeX doesn't lowercase them.  Can be disabled with
  `--/escape-acronyms`.

- TODO: nouns

- TODO: names

- Makes the `month` field use the BibTeX month macros (e.g., `feb` without
  braces or quotes around it).

- Removes any fields listed in `--omit`.

- Removes any fields that are just a blank string if they are listed in
  `--omit-empty`.

- Automatically generates keys for entries.  Keys are of the form
  "last-name-of-first-author:year:doi", where `:year` or `:doi` may be omitted
  if they are not available.

- Puts the fields in an entry into a standard order.

- Warns about unknown field types.

- Warns about duplicated fields.

## BibTeX Scraping

- Collects information from the HTML of a page in addition to the BibTeX export
  offered by a page.  For example, getting a title with correct formatting.

- On ACM pages, additionally does the following.

  - Detects when ACM is listing a non-ACM publication and tries to redirect to the
    publisher's page.

  - Prefers conference references over SIGPLAN Notices, SIGSOFT Software
    Engineering Notes.

  - Sorts keywords since ACM is inconsistent in how they are ordered.

  - Calculates the `pages` field if it is missing based on the `numpages` field.

  - Full journal names are used when available instead of
    abbreviations.

TODO:

Names (e.g. author, editor) should be formatted "von last, first, jr".
  This is the only unambiguous format for latex.
  Note RIS uses "last, jr, first".

Data from the publishers is often wrong.  In particular, formatting of author
names is the biggest problem.  The data from the publishers is often
incomplete or incorrect.  For example, I've found 'Blume' misspelled as 'Blu',
'Bruno C.d.S Oliviera' listed as 'Bruno Oliviera' and 'Simon Peyton Jones'
listed as 'Jones, Simon Peyton'.  See the `config/names.cfg` file for how to
fix these.
