https://portal.acm.org/citation.cfm?id=1159807
Subtitle
@inproceedings{Might:2006:10.1145/1159803.1159807,
  author = {Might, Matthew and Shivers, Olin},
  title = {Improving flow analyses via {\textgreek{G}}{CFA}: abstract garbage collection and counting},
  booktitle = {Proceedings of the Eleventh ACM SIGPLAN International Conference on Functional Programming},
  series = {ICFP~'06},
  location = {Portland, Oregon, USA},
  pages = {13--25},
  numpages = {13},
  month = sep,
  year = {2006},
  publisher = {ACM},
  address = {New York, NY, USA},
  isbn = {1-59593-309-3},
  doi = {10.1145/1159803.1159807},
  acmid = {1159807},
  bib_scrape_url = {https://portal.acm.org/citation.cfm?id=1159807},
  keywords = {CPS; abstract counting; abstract garbage collection; continuations; environment analysis; flow analysis; functional languages; gamma-CFA; inlining; lambda calculus; program analysis; superbeta},
  abstract = {We present two independent and complementary improvements for flow-based analysis of higher-order languages: (1) \textit{abstract garbage collection} and (2) \textit{abstract counting}, collectively titled {\textgreek{G}}CFA.Abstract garbage collection is an analog to its concrete counterpart: we determine when an abstract resource has become unreachable, and then reallocate it as fresh. This prevents flow sets from merging in the abstract, which has two immediate effects: (1) the precision of the analysis is increased, and (2) the running time of the analysis is frequently reduced. In some nontrivial cases, we achieve an order of magnitude improvement in precision and time \textit{simultaneously}.In abstract counting, we track how many times an abstract resource has been allocated. A count of one implies that the abstract resource momentarily represents only one concrete resource. This, in turn, allows us to perform environment analysis and to expand the kinds (rather than just the degree) of optimizations available to the compiler.},
}

