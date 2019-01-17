* In reports, put select distincts again tables
* Think about ID InterproScan
* Allow dynamic configuration for MySQL launch (where different IPs may be involved after resuming)
	* Ensure process is stopped when connection to MySQL is lost. -> dies in scripts
* Put in Ontology_term= in GFF a source (e. g. KEGG)
* Allow different GFF parsing (e. g., from transcriptome projects)
* Missing IPSCN in protein_go table. Recovering importing of GO from InterPro 
* Adapt to new version of KEGG - multiline (sub parse_kegg_record function) http://rest.kegg.jp/get/ko:K13137
	* Check why orthologous are not there...
