https://dl.acm.org/doi/10.1145/3133906

PACMPL uses conference names as issue numbers
@article{Adams:2017:restricting:10.1145/3133906,
  author = {Adams, Michael D. and Might, Matthew},
  title = {Restricting grammars with tree automata},
  journal = {Proceedings of the ACM on Programming Languages},
  volume = {1},
  number = {OOPSLA},
  pages = {82:1--82:25},
  articleno = {82},
  numpages = {25},
  month = oct,
  year = {2017},
  issue_date = {October 2017},
  publisher = {Association for Computing Machinery},
  address = {New York, NY, USA},
  doi = {10.1145/3133906},
  bib_scrape_url = {https://dl.acm.org/doi/10.1145/3133906},
  keywords = {Ambiguous grammars; Keywords: Tree automata},
  abstract = {Precedence and associativity declarations in systems like yacc resolve ambiguities in context-free grammars (CFGs) by specifying restrictions on allowed parses. However, they are special purpose and do not handle the grammatical restrictions that language designers need in order to resolve ambiguities like dangling else, the interactions between binary operators and functional if expressions in ML, and the interactions between object allocation and function calls in JavaScript. Often, language designers resort to restructuring their grammars in order to encode these restrictions, but this obfuscates the designer's intent and can make grammars more difficult to read, write, and maintain.
{\par}
In this paper, we show how tree automata can modularly and concisely encode such restrictions. We do this by reinterpreting CFGs as tree automata and then intersecting them with tree automata encoding the desired restrictions. The results are then reinterpreted back into CFGs that encode the specified restrictions. This process can be used as a preprocessing step before other CFG manipulations and is well behaved. It performs well in practice and never introduces ambiguities or LR(\textit{k}) conflicts.},
}
