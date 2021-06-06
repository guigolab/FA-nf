* Log directory check
* Singularity file for run_mysql wrapper process
* Check kegg_upload slow process
  * In pre-upload insert many KEGG entries at once.
* Add option to detect if possible contamination from BLAST (inspiration from MEGAN)
* Include some testing and CI
* Visualization of results
    * Venn Diagrams
---
* Allow conversion from GenBank https://metacpan.org/pod/bp_genbank2gff3.pl
* Allow reports from KEGG orthologs (number of potential orthologs from KEGG species)
* blast_hit reconsider
* Allow more flexibility for input parameters batch
* Generalize and consider other programs for BLAST process or similar annotation processes: e.g. [GHOSTZ](http://www.bi.cs.titech.ac.jp/ghostz/) and [Argot2.5](http://www.medcomp.medicina.unipd.it/Argot2-5/)
* Migrate to DSL2
* Add PhylomeDB in analysis
* Add PANNZER in analysis
