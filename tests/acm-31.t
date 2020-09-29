https://dl.acm.org/doi/10.1145/1149982.1149987

Use of SIGPLAN Notices even though we normally avoid it
@article{Adams:2006:fast:10.1145/1149982.1149987,
  author = {Adams, Michael D. and Wise, David S.},
  title = {Fast additions on masked integers},
  journal = {ACM SIGPLAN Notices},
  volume = {41},
  number = {5},
  pages = {39--45},
  numpages = {7},
  month = may,
  year = {2006},
  issue_date = {May 2006},
  publisher = {Association for Computing Machinery},
  address = {New York, NY, USA},
  issn = {0362-1340 (Print) 1558-1160 (Online)},
  doi = {10.1145/1149982.1149987},
  bib_scrape_url = {https://dl.acm.org/doi/10.1145/1149982.1149987},
  keywords = {compilers; dilated integers; index arithmetic; morton order; quadtrees},
  abstract = {Suppose the bits of a computer word are partitioned into \textit{d} disjoint sets, each of which is used to represent one of a \textit{d}-tuple of cartesian indices into \textit{d}-dimensional space. Then, regardless of the partition, simple group operations and comparisons can be implemented for each index on a conventional processor in a sequence of two or three register operations.These indexings allow any blocked algorithm from linear algebra to use some non-standard matrix orderings that increase locality and enhance their performance. The underlying implementations were designed for alternating bit postitions to index Morton-ordered matrices, but they apply, as well, to any bit partitioning. A hybrid ordering of the elements of a matrix becomes possible, therefore, with row-/column-major ordering within cache-sized blocks and Morton ordering of those blocks, themselves. So, one can enjoy the temporal locality of nested blocks, as well as compiler optimizations on row- or column-major ordering in base blocks.},
}
