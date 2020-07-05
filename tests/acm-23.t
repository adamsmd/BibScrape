https://dl.acm.org/citation.cfm?id=2516760.2516769
Ampersand in booktitle
@inproceedings{Liang:2013:10.1145/2516760.2516769,
  author = {Liang, Shuying and Keep, Andrew W. and Might, Matthew and Lyde, Steven and Gilray, Thomas and Aldous, Petey and Van Horn, David},
  title = {Sound and precise malware analysis for android via pushdown reachability and entry-point saturation},
  booktitle = {Proceedings of the Third ACM Workshop on Security and Privacy in Smartphones {\&} Mobile Devices},
  series = {SPSM~'13},
  location = {Berlin, Germany},
  pages = {21--32},
  numpages = {12},
  month = nov,
  year = {2013},
  publisher = {ACM},
  address = {New York, NY, USA},
  isbn = {978-1-4503-2491-5},
  doi = {10.1145/2516760.2516769},
  acmid = {2516769},
  bib_scrape_url = {https://dl.acm.org/citation.cfm?id=2516760.2516769},
  keywords = {abstract interpretation; malware detection; pushdown systems; static analysis; taint analysis},
  abstract = {Sound malware analysis of Android applications is challenging. First, object-oriented programs exhibit highly interprocedural, dynamically dispatched control structure. Second, the Android programming paradigm relies heavily on the asynchronous execution of multiple entry points. Existing analysis techniques focus more on the second challenge, while relying on traditional analytic techniques that suffer from inherent imprecision or unsoundness to solve the first.
{\par}
We present Anadroid, a static malware analysis framework for Android apps. Anadroid exploits two techniques to soundly raise precision: (1) it uses a pushdown system to precisely model dynamically dispatched interprocedural and exception-driven control-flow; (2) it uses Entry-Point Saturation (EPS) to soundly approximate all possible interleavings of asynchronous entry points in Android applications. (It also integrates static taint-flow analysis and least permissions analysis to expand the class of malicious behaviors which it can catch.) Anadroid provides rich user interface support for human analysts which must ultimately rule on the {\textquotedbl}maliciousness{\textquotedbl} of a behavior.
{\par}
To demonstrate the effectiveness of Anadroid's malware analysis, we had teams of analysts analyze a challenge suite of 52 Android applications released as part of the Automated Program Analysis for Cybersecurity (APAC) DARPA program. The first team analyzed the apps using a version of Anadroid that uses traditional (finite-state-machine-based) control-flow-analysis found in existing malware analysis tools; the second team analyzed the apps using a version of Anadroid that uses our enhanced pushdown-based control-flow-analysis. We measured machine analysis time, human analyst time, and their accuracy in flagging malicious applications. With pushdown analysis, we found statistically significant (p {\textless} 0.05) decreases in time: from 85 minutes per app to 35 minutes per app in human plus machine analysis time; and statistically significant (p {\textless} 0.05) increases in accuracy with the pushdown-driven analyzer: from 71{\%} correct identification to 95{\%} correct identification.},
}

