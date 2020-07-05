https://journals.cambridge.org/action/displayAbstract?fromPage=online&aid=192403
"Mc" name
@article{McBride:2004:10.1017/S0956796803004829,
  author = {McBride, Conor and McKinna, James},
  title = {The view from the left},
  journal = {Journal of Functional Programming},
  volume = {14},
  number = {1},
  pages = {69--111},
  month = jan,
  year = {2004},
  publisher = {Cambridge University Press},
  issn = {1469-7653 (Print) 0956-7968 (Online)},
  doi = {10.1017/S0956796803004829},
  bib_scrape_url = {https://journals.cambridge.org/action/displayAbstract?fromPage=online&aid=192403},
  abstract = {Pattern matching has proved an extremely powerful and durable notion in functional programming. This paper contributes a new programming notation for type theory which elaborates the notion in various ways. First, as is by now quite well-known in the type theory community, definition by pattern matching becomes a more discriminating tool in the presence of dependent types, since it refines the explanation of types as well as values. This becomes all the more true in the presence of the rich class of datatypes known as inductive families (Dybjer, 1991). Secondly, as proposed by Peyton Jones (1997) for Haskell, and independently rediscovered by us, subsidiary case analyses on the results of intermediate computations, which commonly take place on the right-hand side of definitions by pattern matching, should rather be handled on the left. In simply-typed languages, this subsumes the trivial case of Boolean guards; in our setting it becomes yet more powerful. Thirdly, elementary pattern matching decompositions have a well-defined interface given by a dependent type; they correspond to the statement of an induction principle for the datatype. More general, user-definable decompositions may be defined which also have types of the same general form. Elementary pattern matching may therefore be recast in abstract form, with a semantics given by translation. Such abstract decompositions of data generalize Wadler's (1987) notion of {\textquoteleft}view{\textquoteright}. The programmer wishing to introduce a new view of a type $\mathit{T}$, and exploit it directly in pattern matching, may do so via a standard programming idiom. The type theorist, looking through the Curry{--}Howard lens, may see this as \emph{proving a theorem}, one which establishes the validity of a new induction principle for $\mathit{T}$. We develop enough syntax and semantics to account for this high-level style of programming in dependent type theory. We close with the development of a typechecker for the simply-typed lambda calculus, which furnishes a view of raw terms as either being well-typed, or containing an error. The implementation of this view is \emph{ipso facto} a proof that typechecking is decidable.},
}

