https://portal.acm.org/citation.cfm?doid=800125.804056
Authors should be "Aho, Alfred V." instead of "Aho, A. V.", etc.
@inproceedings{Aho:1973:10.1145/800125.804056,
  author = {Aho, A[lfred] V. and Hopcroft, J[ohn] E. and Ullman, J[effrey] D.},
  title = {On finding lowest common ancestors in trees},
  booktitle = {Proceedings of the Fifth Annual ACM Symposium on Theory of Computing},
  series = {STOC~'73},
  location = {Austin, Texas, USA},
  pages = {253--265},
  numpages = {13},
  month = apr,
  year = {1973},
  publisher = {ACM},
  address = {New York, NY, USA},
  doi = {10.1145/800125.804056},
  acmid = {804056},
  bib_scrape_url = {https://portal.acm.org/citation.cfm?doid=800125.804056},
  abstract = {Trees in an n node forest are to be merged according to instructions in a given sequence, while other instructions in the sequence ask for the lowest common ancestor of pairs of nodes. We show that any sequence of O(n) instructions can be processed {\textquotedblleft}on line{\textquotedblright} in O(n log n) steps on a random access computer.
{\par}
If we can accept our answer {\textquotedblleft}off-line{\textquotedblright}, that is, no answers need to be produced until the entire sequence of instructions has been seen seen, then we may perform the task in O(n G(n)) steps, where G(n) is the number of times we must apply log2 to n to obtain a number less than or equal to zero.
{\par}
A third algorithm solves a problem of intermediate complexity. We require the answers on line, but we suppose that all tree merging instructions precede the information requests. This algorithm requires O(n log log n) time.
{\par}
We apply the first on line algorithm to a problem in code optimization, that of computing immediate dominators in a reducible flow graph. We show how this computation can be performed in O(n log n) steps.},
}

