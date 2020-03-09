#!/usr/bin/env nextflow

/*
 * Copyright (c) 2017-2019, Centre for Genomic Regulation (CRG)
 *
 * Copyright (c) 2017, Anna Vlasova
 *
 * Copyright (c) 2017, Emilio Palumbo
 *
 * Copyright (c) 2018-2020, Toni Hermoso Pulido
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

// species-specific parameters
protein = file(params.proteinFile)
annotation = file(params.gffFile)
config_file = file(params.config)

evalue = 0.00001 // Default evalue for BLAST

if(params.evalue != "" ||  params.evalue != null ) {

 evalue = params.evalue
 
}

dbFile = false
boolean exists = false
boolean mysql = false
gffclean = false
gffstats = false

if(params.dbEngine.toLowerCase()=="mysql") {
 mysql = true
}

if ( params.gffclean != null && ( params.gffclean=="TRUE" || params.gffclean=="true" ) ) {
 gffclean = true
}

if ( params.gffstats != null && ( params.gffstats=="TRUE" || params.gffstats=="true" ) ) {
 gffstats = true
}

// Handling MySQL in a cleaner way
dbhost = null

// Getting contents of file
if ( mysql ) {
 dbhost = "127.0.0.1" // Default value. Localhost
 
 if ( new File(  params.mysqllog+"/DBHOST" ).exists() ) {
  dbhost = new File(  params.mysqllog+"/DBHOST" ).text.trim()
 }
} else {
 dbFileName = params.resultPath+params.dbname+'.db'
 dbFile = file(dbFileName)
 exists = dbFile.exists()

}


// print log info

log.info ""
log.info "Functional annotation pipeline"
log.info ""
log.info "General parameters"
log.info "------------------"
log.info "Protein sequence file        : ${params.proteinFile}"
log.info "Annotation file              : ${params.gffFile}"
log.info "BLAST results file           : ${params.blastFile}"
log.info "Species name                  : ${params.specie_name}"
log.info "KEGG species                 : ${params.kegg_species}"
if ( mysql ) {
log.info "FA database 		       : ${params.dbname}"
} else {
log.info "FA database 		       : $dbFileName"
}

// split protein fasta file into chunks and then execute annotation for each chunk
// chanels for: interpro, blast, signalP, targetP, cdsearch_hit, cdsearch_features
seqData= Channel
 .from(protein)
 .splitFasta(by: params.chunkSize)

seqWebData= Channel
 .from(protein)
 .splitFasta(by: params.chunkWebSize)

iscan_properties = file("/usr/local/interproscan/interproscan.properties")

if(params.debug=="TRUE"||params.debug=="true") {
 println("Debugging.. only the first 2 chunks will be processed")
 (seq_file1, seq_file2, seq_file3, seq_file4, seq_file5, seq_file6, seq_file7) = seqData.take(2).into(7)
 (web_seq_file1, web_seq_file2) = seqWebData.take(2).into(2)

}
else {
 println("Process entire dataset")
(seq_file1, seq_file2, seq_file3, seq_file4, seq_file5, seq_file6, seq_file7) = seqData.into(7)
(web_seq_file1, web_seq_file2) = seqWebData.into(2)

}

if(params.oboFile == "" ||  params.oboFile == null ) {

 println "Please download OBO File from http://www.geneontology.org/ontology/gene_ontology.obo"
 // TODO: Download OBO file
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

 output:
 file "blastXml${seq}" into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

 """
  blastp -db ${db_path}/${db_name} -query $seq -num_threads 8 -evalue  0.00001 -out "blastXml${seq}" -outfmt 5
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

if (params.kolist != "" ||  params.kolist != null ){

process kofamscan{

 label 'kofamscan'
 
 input:
 file seq from seq_file7

 output:
 file "koala_${seq}" into koalaResults
 
 """
  exec_annotation --cpu ${task.cpus} -p ${params.koprofiles} -k ${params.kolist} -o koala_${seq} $seq
 """

}

process kofam_parse {

 input:
 file 'koala_*' from koalaResults.collect()

 output:
 file allKoala into koala_parsed

"""

mkdir -p output
processHmmscan2TSV.pl "koala_*" output
cat output/koala_* > allKoala
"""

}

// Replacing keggfile
keggfile = koala_parsed

} else {


 if(params.keggFile == "" ||  params.keggFile == null ) {
 
  println "Please run KEGG KO group annotation on the web server http://www.genome.jp/tools/kaas/"
  
 }

 keggfile=file(params.keggFile)
 
}

if(params.gogourl != ""){

process blast_annotator {

 label 'blastannotator'
 
 input:
 file blastXml from blastXmlResults2.flatMap()

 output:
 file 'blastAnnot' into blast_annotator_results

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
 file "blastDef_${blastXml}.txt" into blastDef_results

 """
  definitionFromBlast.pl  -in $blastXml -out blastDef_${blastXml}.txt -format xml -q
 """
}

// TODO: Need to simplify this step

if ( gffclean ) {

 process cleanGFF {
 
  label 'gffcheck'
  
  input:
   file config_file
  
  output:
   file 'annot.gff' into gff_file
    
   """
    # get annot file
    export escaped=\$(echo '$baseDir')
    export basedirvar=\$(echo '\\\$\\{baseDir\\}')
    agat_sp_gxf_to_gff3.pl --gff `perl -lae 'if (\$_=~/gffFile\\s*\\=\\s*[\\x27|\\"](\\S+)[\\x27|\\"]/) { \$base = \$1; \$base=~s/\$ENV{'basedirvar'}/\$ENV{'escaped'}/g; print \$base }' $config_file` -o annot.gff
   """
 
 }


} else {

 process copyGFF {

  label 'gffcheck'
  
  input:
   file config_file
  
  output:
   file 'annot.gff' into gff_file
    
   """
    # get annot file
    export escaped=\$(echo '$baseDir')
    export basedirvar=\$(echo '\\\$\\{baseDir\\}')
    cp `perl -lae 'if (\$_=~/gffFile\\s*\\=\\s*[\\x27|\\"](\\S+)[\\x27|\\"]/) { \$base = \$1; \$base=~s/\$ENV{'basedirvar'}/\$ENV{'escaped'}/g; print \$base }' $config_file` annot.gff
   """

 }
}

if ( gffstats ) {

 process statsGFF {
 
  publishDir params.resultPath, mode: 'copy'
  
  label 'gffcheck'
  
  input:
   file gff_file
  
  output:
   file '*.txt' into gff_stats
    
   """
    # Generate Stats
    agat_sp_statistics.pl --gff $gff_file > ${gff_file}.stats.txt
   """
 
 }


}

process initDB {

 input:
  file config_file
  file gff_file

 output:
  file 'config'  into config4perl

 script:
 command = "mkdir -p $params.resultPath\n"
 command += "sed 's/^\\s*params\\s*{\\s*\$//gi' $config_file | sed 's/^\\s*}\\s*\$//gi' | sed '/^\\s*\$/d' | sed 's/\\s\\=\\s/:/gi' > configt\n"
 command += "export escaped=\$(echo '$baseDir')\n"
 command += "export basedirvar=\$(echo '\\\$\\{baseDir\\}')\n"
 command += "perl -lae '\$_=~s/\$ENV{'basedirvar'}/\$ENV{'escaped'}/g; print;' configt > config\n"
 
 
 if ( mysql ) {
  // Add dbhost to config
  command += "echo \"\$(cat config)\n dbhost:${dbhost}\" > configIn ;\n"
  command += "fa_main.v1.pl init -conf configIn"
 } else {

   if (!exists) {
     command += "fa_main.v1.pl init -conf config"
   }
 }
 
 if ( gffclean ) {
  command += " -gff ${gff_file}"
 }
 
 command
}

process 'definition_upload'{

 maxForks 1

 // publishDir "results", mode: 'copy'
 input:
 file "*.txt" from blastDef_results.collect()
 file config from config4perl

 output:
 file 'def_done' into definition_passed

 script:
  
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.txt > allDef; \
   upload_go_definitions.pl -i allDef -conf \$config -mode def -param 'blast_def' > def_done \
  "
 
  command
}

process ipscn {

    label 'ipscan'

    input:
    file seq from seq_file1
    file ("interproscan.properties") from file( iscan_properties )

    output:
    file('${seq}.out_interpro') into (ipscn_result1, ipscn_result2)

    """
    sed 's/*//' $seq > tmp4ipscn
    interproscan.sh -i tmp4ipscn --goterms --iprlookup --pathways -o ${seq}.out_interpro -f TSV -T ${params.ipscantmp}
    """
}

process 'cdSearchHit' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from web_seq_file1

    output:
    file '${seq}.out_hit' into cdSearch_hit_result

    """
    submitCDsearch.pl  -o ${seq}.out_hit -in $seq
    """
}

process 'cdSearchFeat' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from web_seq_file2

    output:
    file '${seq}.out_feat' into cdSearch_feat_result

    """
    submitCDsearch.pl -t feats -o ${seq}.out_feat -in $seq
    """
}


process 'signalP' {

    label 'sigtarp'

    input:
    file seq from seq_file4

    output:
    file('${seq}.out_signalp') into (signalP_result1, signalP_result2)

    """
    signalp  $seq > ${seq}.out_signalp
    """
}

process 'targetP' {

    label 'sigtarp'

    input:
    file seq from seq_file5

    output:
    file('${seq}.out_targetp') into (targetP_result1, targetP_result2)

    """
    targetp -P -c  $seq > ${seq}.out_targetp
    """
}

/*
Upload results into DB -- in current version of the pipeline DB is implemented with SQLite, but mySQL is also supported
*/

process 'signalP_upload'{

 maxForks 1

 input:
 file '*.out_signalp' from signalP_result1.collect()
 file config from config4perl
 file def_done from definition_passed

 output:
 file('upload_signalp') into upload_signalp


 script:
 
  command = checkMySQL( mysql, params.mysqllog )
 
  command += " \
   cat *.out_signalp > allSignal ; \
   load_CBSpredictions.signalP.pl -i allSignal -conf \$config -type s > upload_signalp ; \
  "
  
  command
}


process 'targetP_upload'{

 maxForks 1

 input:
 file '*.out_targetp' from targetP_result1.collect()
 file config from config4perl
 file upload_signalp from upload_signalp

 output:
 file('upload_targetp') into upload_targetp

 script:
 
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.out_targetp > allTarget ; \
   load_CBSpredictions.signalP.pl -i allTarget -conf \$config -type t > upload_targetp ; \
  "
  
  command
}


process 'interpro_upload'{

 maxForks 1

 input:
 file '*.out_interpro' from ipscn_result1.collect()
 file config from config4perl
 file upload_targetp from upload_targetp

 output:
 file('upload_interpro') into upload_interpro
 
 
 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.out_interpro > allInterpro ; \
   run_interpro.pl -mode upload -i allInterpro -conf \$config > upload_interpro ; \
  "
  
  command
}


process 'CDsearch_hit_upload'{

 maxForks 1

 input:
 file '*.out_hit' from cdSearch_hit_result.collect()
 file config from config4perl
 file upload_interpro from upload_interpro

 output:
 file('upload_hit') into upload_hit
 
 script:
 
  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat *.out_hit > allCDsearchHit ; \
   upload_CDsearch.pl -i allCDsearchHit -type h -conf \$config > upload_hit ; \
  "
  
  command
}

process 'CDsearch_feat_upload'{

 maxForks 1

 input:
 file '*.out_feat' from cdSearch_feat_result.collect()
 file config from config4perl
 file upload_hit from upload_hit

 output:
 file('upload_feat') into upload_feat

 script:
 
  command = checkMySQL( mysql, params.mysqllog )
  
  command += " \
   cat *.out_feat > allCDsearchFeat ; \
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

// Check MySQL IP
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

// On finising
workflow.onComplete {

 println ( workflow.success ? "\nDone! Check results in --> $params.resultPath\n" : "Oops .. something went wrong" )
 
 if ( mysql ) {
  
   def procfile = new File( params.mysqllog+"/PROCESS" )
   procfile.delete()
 }

}

workflow.onError {

 println( "Something went wrong" )
 
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
