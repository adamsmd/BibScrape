https://journals.cambridge.org/action/displayAbstract?fromPage=online&aid=8440159
Chinese name, unusual subtitle placement
@article{Kameyama:2011:10.1017/S0956796811000256,
  author = {Kameyama, Yukiyoshi and Kiselyov, Oleg and Shan, Chung-chieh},
  title = {Shifting the stage: Staging with delimited control},
  journal = {Journal of Functional Programming},
  volume = {21},
  number = {6},
  pages = {617--662},
  month = nov,
  year = {2011},
  publisher = {Cambridge University Press},
  issn = {1469-7653 (Print) 0956-7968 (Online)},
  doi = {10.1017/S0956796811000256},
  bib_scrape_url = {https://journals.cambridge.org/action/displayAbstract?fromPage=online&aid=8440159},
  abstract = {It is often hard to write programs that are efficient yet reusable. For example, an efficient implementation of Gaussian elimination should be specialized to the structure and known static properties of the input matrix. The most profitable optimizations, such as choosing the best pivoting or memoization, cannot be expected of even an advanced compiler because they are specific to the domain, but expressing these optimizations directly makes for ungainly source code. Instead, a promising and popular way to reconcile efficiency with reusability is for a domain expert to write code generators.
{\par}
Two pillars of this approach are types and effects. Typed multilevel languages such as MetaOCaml ensure \emph{safety} and early error reporting: a well-typed code generator neither goes wrong nor generates code that goes wrong. Side effects such as state and control ease \emph{correctness} and \emph{expressivity}: An effectful generator can resemble the textbook presentation of an algorithm, as is familiar to domain experts, yet insert \emph{let} for memoization and \emph{if} for bounds checking, as is necessary for efficiency. Together, types and effects enable structuring code generators as compositions of modules with well-defined interfaces, and hence scaling to large programs. However, blindly adding effects renders multilevel types unsound.
{\par}
We introduce the first multilevel calculus with control effects and a sound type system. We give small-step operational semantics as well as a one-pass continuation-passing-style translation. For soundness, our calculus restricts the code generator's effects to the scope of generated binders. Even with this restriction, we can finally write efficient code generators for dynamic programming and numerical methods in direct style, like in algorithm textbooks, rather than in continuation-passing or monadic style.},
}

