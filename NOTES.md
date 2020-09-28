# Development Notes

## How to make a release

- Run all tests
- `bin/bibscrape --help >HELP.txt`
- Commit everything
- Update `version` in `META6.json`
- Commit the edit with message "Version 20.09.21"
- `git tag v20.09.21`
- `git push origin master`
- `git push origin v20.09.21`
  - ?? `git push origin master v20.09.21`

## Words

https://en.wikipedia.org/wiki/English_grammar#Phrases
  https://en.wikipedia.org/wiki/English_articles
  https://en.wikipedia.org/wiki/Preposition_and_postposition
  https://en.wikipedia.org/wiki/Determiner
https://papyr.com/hypertextbooks/grammar/
https://en.wikipedia.org/wiki/Part-of-speech_tagging

### Function words

STOPWORDS in https://github.com/mattbierbaum/arxiv-bib-overlay/blob/master/src/ui/CiteModal.tsx

https://en.wikipedia.org/wiki/Function_word

http://flesl.net/Grammar/Grammar_Glossary/closed_open_class.php

https://github.com/Yoast/javascript/blob/develop/packages/yoastseo/src/researches/english/functionWords.js

### Nouns

Use ispell, aspell, hunspell, and enchant to find words in DBLP
that are correct capitalizaed but not in lower case

Do statistical measurements of word capitalization in DBLP

Use Wiktionary list of English (all?) proper nouns

https://duckduckgo.com/?q=wiktionary+api
https://duckduckgo.com/?q=list+of+common+nouns

https://en.wiktionary.org/wiki/Category:English_language
https://en.wiktionary.org/wiki/Category:English_appendices

https://en.wiktionary.org/wiki/Wiktionary:Lemmas
https://en.wiktionary.org/wiki/Category:English_lemmas
https://en.wiktionary.org/wiki/Category:English_non-lemma_forms


https://en.wiktionary.org/wiki/Category:English_locatives
https://en.wiktionary.org/wiki/Category:English_post-nominal_letters
https://en.wiktionary.org/wiki/Category:English_proper_nouns


https://en.wiktionary.org/wiki/Module:number_list/data/en

https://dumps.wikimedia.org/
  https://stackoverflow.com/questions/2770547/how-to-retrieve-wiktionary-word-content
  https://en.wiktionary.org/w/api.php
  https://dumps.wikimedia.org/enwiktionary/latest/
  https://en.wiktionary.org/wiki/Help:FAQ#Downloading_Wiktionary
  https://github.com/Suyash458/WiktionaryParser

#### Programming Languages

https://githut.info/
https://madnight.github.io/githut/#/pull_requests/2020/2
https://tiobe.com/tiobe-index/
https://pypl.github.io/PYPL.html
https://brainhub.eu/blog/most-popular-languages-on-github/
https://github.com/oprogramador/github-languages
https://docs.github.com/en/free-pro-team@latest/rest/reference/search

https://github.com/github/linguist/blob/master/lib/linguist/languages.yml

https://docs.github.com/en?query=languages
https://docs.github.com/en/free-pro-team@latest/github/creating-cloning-and-archiving-repositories/about-repository-languages#markup-languages

https://docs.github.com/en/free-pro-team@latest/rest/reference/repos#list-repository-languages

