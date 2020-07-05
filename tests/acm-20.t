https://doi.org/10.1145/1178597.1178604
Bullets in abstract
@inproceedings{Adams:2006:10.1145/1178597.1178604,
  author = {Adams, Michael D. and Wise, David S.},
  title = {Seven at one stroke: results from a cache-oblivious paradigm for scalable matrix algorithms},
  booktitle = {Proceedings of the 2006 Workshop on Memory System Performance and Correctness},
  series = {MSPC~'06},
  location = {San Jose, California},
  pages = {41--50},
  numpages = {10},
  month = oct,
  year = {2006},
  publisher = {ACM},
  address = {New York, NY, USA},
  isbn = {1-59593-578-9},
  doi = {10.1145/1178597.1178604},
  acmid = {1178604},
  bib_scrape_url = {https://doi.org/10.1145/1178597.1178604},
  keywords = {Cholesky factorization; Morton-hybrid; TLB; cache misses; paging; parallel processing; quadtrees},
  abstract = {A blossoming paradigm for block-recursive matrix algorithms is presented that, at once, attains excellent performance measured by{\textbullet} time{\textbullet} TLB misses{\textbullet} L1 misses{\textbullet} L2 misses{\textbullet} paging to disk{\textbullet} scaling on distributed processors, and{\textbullet} portability to multiple platforms.It provides a philosophy and tools that allow the programmer to deal with the memory hierarchy invisibly, from L1 and L2 to TLB, paging, and interprocessor communication. Used together, they provide a cache-oblivious \textit{style} of programming.Plots are presented to support these claims on an implementation of Cholesky factorization crafted directly from the paradigm in C with a few intrinsic calls. The results in this paper focus on low-level performance, including the new Morton-hybrid representation to take advantage of hardware and compiler optimizations. In particular, this code beats Intel's Matrix Kernel Library and matches AMD's Core Math Library, losing a bit on L1 misses while winning decisively on TLB-misses.},
}

