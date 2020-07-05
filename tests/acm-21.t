https://doi.org/10.1145/1809028.1806631
Acronym and math in title, paragraph and math in abstract
@inproceedings{Might:2010:10.1145/1806596.1806631,
  author = {Might, Matthew and Smaragdakis, Yannis and Van Horn, David},
  title = {Resolving and exploiting the \textit{k}-{CFA} paradox: illuminating functional vs. object-oriented program analysis},
  booktitle = {Proceedings of the 31st ACM SIGPLAN Conference on Programming Language Design and Implementation},
  series = {PLDI~'10},
  location = {Toronto, Ontario, Canada},
  pages = {305--315},
  numpages = {11},
  month = jun,
  year = {2010},
  publisher = {ACM},
  address = {New York, NY, USA},
  isbn = {978-1-4503-0019-3},
  doi = {10.1145/1806596.1806631},
  acmid = {1806631},
  bib_scrape_url = {https://doi.org/10.1145/1809028.1806631},
  keywords = {control-flow analysis; functional; k-cfa; m-cfa; object-oriented; pointer analysis; static analysis},
  abstract = {Low-level program analysis is a fundamental problem, taking the shape of {\textquotedbl}flow analysis{\textquotedbl} in functional languages and {\textquotedbl}points-to{\textquotedbl} analysis in imperative and object-oriented languages. Despite the similarities, the vocabulary and results in the two communities remain largely distinct, with limited cross-understanding. One of the few links is Shivers's \textit{k}-CFA work, which has advanced the concept of {\textquotedbl}context-sensitive analysis{\textquotedbl} and is widely known in both communities.
{\par}
Recent results indicate that the relationship between the functional and object-oriented incarnations of \textit{k}-CFA is not as well understood as thought. Van Horn and Mairson proved \textit{k}-CFA for \textit{k} {\ensuremath{\geq}} 1 to be EXPTIME-complete; hence, no polynomial-time algorithm can exist. Yet, there are several polynomial-time formulations of context-sensitive points-to analyses in object-oriented languages. Thus, it seems that functional \textit{k}-CFA may actually be a profoundly different analysis from object-oriented \textit{k}-CFA. We resolve this paradox by showing that the exact same specification of \textit{k}-CFA is polynomial-time for object-oriented languages yet exponential-time for functional ones: objects and closures are subtly different, in a way that interacts crucially with context-sensitivity and complexity. This illumination leads to an immediate payoff: by projecting the object-oriented treatment of objects onto closures, we derive a polynomial-time hierarchy of context-sensitive CFAs for functional programs.},
}

