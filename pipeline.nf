#!/usr/bin/env nextflow

/*
 * Copyright (c) 2017-2019, Centre for Genomic Regulation (CRG)
 *
 * Copyright (c) 2017, Anna Vlasova
 *
 * Copyright (c) 2017, Emilio Palumbo
 *
 * Copyright (c) 2018-2019, Toni Hermoso Pulido
 * 
 * Functional Annotation Pipeline for protein annotation from non-model organisms
 * from Genome Annotation Team in Catalonia (GATC) implemented in Nextflow
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


// there can be three log levels: off (no messages), info (some main messages), debug (all messages + sql queries)


// default parameters
params.help = false
params.debug="false"

//print usage
if (params.help) {
  log.info ''
  log.info 'Functional annotation pipeline'
  log.info '----------------------------------------------------'
  log.info 'Run functional annotation for a given specie.'
  log.info ''
  log.info 'Usage: '
  log.info "  ./nextflow run  pipeline.nf --config main_configuration.config [options]"
  log.info ''
  log.info 'Options:'
  log.info '-resume		resume pipeline from the previous step, i.e. in case of error'
  log.info '-help		this message'
  exit 1
}


/*
* Parse the input parameters
*/

// specie-specific parameters
protein = file(params.proteinFile)
annotation = file(params.gffFile)
config_file = file(params.config)

dbFileName = params.resultPath+params.dbname+'.db'

//println(dbFileName)
dbFile = file(dbFileName)
boolean exists = dbFile.exists();
boolean mysql = false

if(params.dbEngine=="mysql") {
 mysql = true
}

//println(exists)

// print log info

log.info ""
log.info "Functional annotation pipeline"
log.info ""
log.info "General parameters"
log.info "------------------"
log.info "Protein sequence file        : ${params.proteinFile}"
log.info "Annotation file              : ${params.gffFile}"
log.info "BLAST results file           : ${params.blastFile}"
log.info "Specie name                  : ${params.specie_name}"
log.info "KEGG species                 : ${params.kegg_species}"
log.info "FA database 		       : $dbFileName"


// split protein fasta file into chunks and then execute annotation for each chunk
// chanels for: interpro, blast, signalP, targetP, cdsearch_hit, cdsearch_features
seqData= Channel
 .from(protein)
 .splitFasta(by: params.chunkSize)

iscan_properties = file("/usr/local/interproscan/interproscan.properties")

if(params.debug=="TRUE"||params.debug=="true")
{
 println("Debugging.. only the first 2 chunks will be processed")
 (seq_file1, seq_file2, seq_file3, seq_file4, seq_file5, seq_file6) = seqData.take(2).into(6)
}
else
{
 println("Process entire dataset")
(seq_file1, seq_file2, seq_file3, seq_file4, seq_file5, seq_file6) = seqData.into(6)
}

if(params.keggFile == "" ||  params.keggFile == null ) {

 println "Please run KEGG KO group annotation on the web server http://www.genome.jp/tools/kaas/"
 
}

keggfile=file(params.keggFile)

if(params.oboFile == "" ||  params.oboFile == null ) {

 println "Please download OBO File from http://www.geneontology.org/ontology/gene_ontology.obo"
 
}

obofile=file(params.oboFile)


if (params.blastFile == "" ||  params.blastFile == null ){

// program-specific parameters
db_name = file(params.blastDB_path).name
db_path = file(params.blastDB_path).parent

process blast{

 label 'blast'

 // publishDir "results", mode: 'copy'

 input:
 file seq from seq_file6
 file db_path

 output:
 file "blastXml${seq}" into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

 """
  blastp -db $db_path/$db_name -query $seq -num_threads 8 -evalue  0.00001 -out "blastXml${seq}" -outfmt 5
 """
}

} else {

blastInput=file(params.blastFile)

process convertBlast{

 // publishDir "results", mode: 'copy'

 input:
 file blastFile from blastInput

 output:
 file('*.xml') into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

 """
  hugeBlast2XML.pl -blast  $blastFile  -n 1000 -out blast.res
 """

}
}

if(params.gogourl != ""){

process blast_annotator {

 label 'blastannotator'
 
 input:
 file blastXml  from blastXmlResults2.flatMap()

 output:
 file blastAnnot into blast_annotator_results

"""
 blast-annotator.pl -in $blastXml -out blastAnnot --url  $params.gogourl -q --format blastxml
"""
}

}

process blastDef {

 // publishDir "results", mode: 'copy'
 tag "${blastXml}"
 
 input:
 file blastXml from blastXmlResults3.flatMap()

 output:
 file "blastDef.txt" into blastDef_results

 """
  definitionFromBlast.pl  -in $blastXml -out blastDef.txt -format xml -q
 """
}

process initDB {

 input:
  file config_file

 output:
  file 'config'  into config4perl

 script:
 command = "mkdir -p $params.resultPath\n"
 command += "grep -vP '[{}]' $config_file | sed 's/\\s\\=\\s/:/gi' > config\n"
 
 if ( mysql ) {
  // Add dbhost to config
  command += "DBHOST=\"dbhost:'`cat $params.mysqllog/DBHOST`'\"; echo \"\$(cat config)\n \$DBHOST\" > configIn ;\n"
  command += "fa_main.v1.pl init -conf configIn"
 } else {

   if (!exists) {
     command += "fa_main.v1.pl init -conf config"
   }
 }
 
 command
}

process 'definition_upload'{

 maxForks 1

 // publishDir "results", mode: 'copy'
 input:
 file "*.def" from blastDef_results.collect()
 file config from config4perl

 output:
 file 'def_done' into definition_passed

 script:
  
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.def > allDef; \
   upload_go_definitions.pl -i allDef -conf \$config -mode def -param 'blast_def' > def_done \
  "
 
  command
}

process ipscn {

    label 'ipscan'

    maxRetries 3

    errorStrategy 'retry'

    input:
    file seq from seq_file1
    file ("interproscan.properties") from file( iscan_properties )

    output:
    file('out_interpro') into (ipscn_result1, ipscn_result2)

    """
    sed 's/*//' $seq > tmp4ipscn
    interproscan.sh -i tmp4ipscn --goterms --iprlookup --pathways -o out_interpro -f TSV -T ${params.ipscantmp}
    """
}

process 'cdSearchHit' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from seq_file2

    output:
    file 'out_hit' into cdSearch_hit_result

    """
    submitCDsearch.pl  -o out_hit -in $seq
    """
}

process 'cdSearchFeat' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from seq_file3

    output:
    file 'out_feat' into cdSearch_feat_result

    """
    submitCDsearch.pl -t feats -o out_feat -in $seq
    """
}


process 'signalP' {

    label 'sigtarp'

    input:
    file seq from seq_file4

    output:
    file('out_signalp') into (signalP_result1, signalP_result2)

    """
    signalp  $seq > out_signalp
    """
}

process 'targetP' {

    label 'sigtarp'

    input:
    file seq from seq_file5

    output:
    file('out_targetp') into (targetP_result1, targetP_result2)

    """
    targetp -P -c  $seq > out_targetp
    """
}

/*
Upload results into DB -- in current version of the pipeline DB is implemented with SQLite, but mySQL is also supported
*/

process 'signalP_upload'{

 maxForks 1

 input:
 file '*.out_signal' from signalP_result1.collect()
 file config from config4perl
 file def_done from definition_passed

 output:
 file('upload_signalp') into upload_signalp


 script:
 
  command = checkMySQL( mysql, params.mysqllog )
 
  command += " \
   cat *.out_signal > allSignal ; \
   load_CBSpredictions.signalP.pl -i allSignal -conf \$config -type s > upload_signalp ; \
  "
  
  command
}


process 'targetP_upload'{

 maxForks 1

 input:
 file '*.out_target' from targetP_result1.collect()
 file config from config4perl
 file upload_signalp from upload_signalp

 output:
 file('upload_targetp') into upload_targetp

 script:
 
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.out_target > allTarget ; \
   load_CBSpredictions.signalP.pl -i allTarget -conf \$config -type t > upload_targetp ; \
  "
  
  command
}


process 'interpro_upload'{

 maxForks 1

 input:
 file '*.ipscan' from ipscn_result1.collect()
 file config from config4perl
 file upload_targetp from upload_targetp

 output:
 file('upload_interpro') into upload_interpro
 
 
 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.ipscan > allInterpro ; \
   run_interpro.pl -mode upload -i allInterpro -conf \$config > upload_interpro ; \
  "
  
  command
}


process 'CDsearch_hit_upload'{

 maxForks 1

 input:
 file '*.cdsearch_hit' from cdSearch_hit_result.collect()
 file config from config4perl
 file upload_interpro from upload_interpro

 output:
 file('upload_hit') into upload_hit
 
 script:
 
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.cdsearch_hit > allCDsearchHit ; \
   upload_CDsearch.pl -i allCDsearchHit -type h -conf \$config > upload_hit ; \
  "
  
  command
}

process 'CDsearch_feat_upload'{

 maxForks 1

 input:
 file '*.cdsearch_feat' from cdSearch_feat_result.collect()
 file config from config4perl
 file upload_hit from upload_hit

 output:
 file('upload_feat') into upload_feat

 script:
 
  command = checkMySQL( mysql, params.mysqllog )
  
  command += " \
   cat *.cdsearch_feat > allCDsearchFeat ; \
   upload_CDsearch.pl -i allCDsearchFeat -type f -conf \$config > upload_feat ; \
  "
  
  command
}

process 'blast_annotator_upload'{

 maxForks 1

 input:
  file "*.blast" from blast_annotator_results.collect()
  file config from config4perl
  file upload_feat from upload_feat

  output:
  file('upload_blast') into upload_blast

 script:
 
  command = checkMySQL( mysql, params.mysqllog )
 
  command += " \
   cat *.blast > allBlast ; \
   awk '\$2!=\"#\"{print \$1\"\t\"\$2}' allBlast > two_column_file ; \
   upload_go_definitions.pl -i two_column_file -conf \$config -mode go -param 'blast_annotator' > upload_blast ; \
  "
  
  command
}

/** Last step **/

process 'kegg_upload'{

 maxForks 1

 input:
 file keggfile from keggfile
 file config from config4perl
 file('upload_blast') from upload_blast

 output:
 file('done') into last_step


 script:
 
  command = checkMySQL( mysql, params.mysqllog )
  
  command += " \
   load_kegg_KAAS.pl -input $keggfile -rel $params.kegg_release -conf \$config > done 2>err; \
  "
  
  command
}

process 'generateResultFiles'{
 input:
  file config from config4perl
  file all_done from last_step
  file obofile from obofile

 script:
 
  command = checkMySQL( mysql, params.mysqllog )
  
  command += " \
   get_results.pl -conf \$config -obo $obofile ; \
  "
  
  command
}

if ( annotation != null && annotation != "" ){

process 'generateGFF3File'{
 input:
  file config from config4perl
  file all_done from last_step


 script:
 
  command = checkMySQL( mysql, params.mysqllog )
  
  command += " \
   get_gff3.pl -conf \$config ; \
  "
  
  command
}

}

/*
process 'generateReport'{
 input:

 output:

 """
  pdflatex bin\/report_template
"""

}
*/


def checkMySQL( mysql, mysqllog )  {

 command = ""

 if ( mysql ) {
   // Add dbhost to config
   command += "DBHOST=\"dbhost:'`cat ${mysqllog}/DBHOST`'\"; echo \"\$(cat config)\n \$DBHOST\" > configIn ;\n"
   command += "config=configIn ;"
 } else {
   command += "config=config ;"
 }

 return command

}

workflow.onComplete {

 println ( workflow.success ? "\nDone! Check results in --> $params.resultPath\n" : "Oops .. something went wrong" )
 
 if ( mysql ) {
  
   def procfile = new File( params.mysqllog+"/PROCESS" )
   procfile.delete()
 }

}


signalP_result2
 .collectFile(name: file(params.resultPath + "signalP.res.tsv"))
  .println { "Result saved to file: $it" }

targetP_result2
 .collectFile(name: file(params.resultPath + "targetP.res.tsv"))
  .println { "Result saved to file: $it" }

ipscn_result2
  .collectFile(name: file(params.resultPath + "interProScan.res.tsv"))
  .println { "Result saved to file: $it" }
