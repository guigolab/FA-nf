#!/usr/bin/env nextflow

/*
 * Copyright (c) 2017, Centre for Genomic Regulation (CRG)
 *
 * Copyright (c) 2017, Anna Vlasova
 *
 * Copyright (c) 2017, Emilio Palumbo
 *
 * Copyright (c) 2018, Toni Hermoso Pulido
 * 
 * Functional Annotation Pipeline for protein annotation from non-model organisms
 * from Genome Annotation Team in Catalyña (GATC) implemented in Nextflow
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
params.results = ""
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
  log.info '-results	generate result files, the final step of the pipeline'
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
 input:
 file blastXml  from blastXmlResults2.flatMap()

 output:
 file blastAnnot into blast_annotator_results

"""
 blast-annotator.pl -in $blastXml -out blastAnnot --url  $params.gogourl --format blastxml
"""
}

}

process blastDef {

 // publishDir "results", mode: 'copy'
 tag "${blastXml}"
 
 input:
 file blastXml from blastXmlResults3.flatMap()

 output:
 file "blastDef${blastXml}" into blastDef_results

 """
  definitionFromBlast.pl  -in $blastXml -out "blastDef${blastXml}" -format xml
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
 if (!exists) {
     command += "fa_main.v1.pl init -conf config"
 }
 command
}

process 'definition_upload'{

 maxForks 1

 // publishDir "results", mode: 'copy'
 input:
 file defFile from blastDef_results
 file config from config4perl

 output:
 file 'def_done' into ( definition_passed1, definition_passed2, definition_passed3, definition_passed4, definition_passed5, definition_passed6, definition_passed7 )


 """
  upload_go_definitions.pl -i $defFile -conf $config -mode def -param 'blast_def' > def_done
 """

}

process ipscn {

    label 'ipscan'

    maxRetries 3

    errorStrategy 'retry'

    input:
    file seq from seq_file1
    file ("interproscan.properties") from file( iscan_properties )

    output:
    file('out') into (ipscn_result1, ipscn_result2)

    """
    sed 's/*//' $seq > tmp4ipscn
    interproscan.sh -i tmp4ipscn --goterms --iprlookup --pathways -o out -f TSV -T ${params.ipscantmp}
    """
}

process 'cdSearchHit' {

    maxForks 1

    input:
    file seq from seq_file2

    output:
    file 'out' into cdSearch_hit_result

    """
    submitCDsearch.pl  -o out -in $seq
    """
}

process 'cdSearchFeat' {

    maxForks 1

    input:
    file seq from seq_file3

    output:
    file 'out' into cdSearch_feat_result

    """
    submitCDsearch.pl -t feats -o out -in $seq
    """
}


process 'signalP' {

    label 'sigtarp'

    input:
    file seq from seq_file4

    output:
    file('out') into (signalP_result1, signalP_result2)

    """
    signalp  $seq > out
    """
}

process 'targetP' {

    label 'sigtarp'

    input:
    file seq from seq_file5

    output:
    file('out') into (targetP_result1, targetP_result2)

    """
    targetp -P -c  $seq > out
    """
}

/*
Upload results into DB -- in current version of the pipeline DB is implemented with SQLite, but mySQL is also supported
*/

process 'signalP_upload'{

 maxForks 1

 input:
 file signalP_res from signalP_result1
 file config from config4perl
 file def_done from definition_passed1

 """
  load_CBSpredictions.signalP.pl -i $signalP_res -conf $config -type s
 """
}


process 'targetP_upload'{

 maxForks 1

 input:
 file targetP_res from targetP_result1
 file config from config4perl
 file def_done from definition_passed2

 """
  load_CBSpredictions.signalP.pl -i $targetP_res -conf $config -type t
 """
}


process 'interpro_upload'{

 maxForks 1

 input:
 file ipscn_res from ipscn_result1
 file config from config4perl
 file def_done from definition_passed3

 """
  run_interpro.pl -mode upload -i $ipscn_res -conf $config

 """
}


process 'CDsearch_hit_upload'{

 maxForks 1

 input:
 file cdsearch_hit_res from cdSearch_hit_result
 file config from config4perl
 file def_done from definition_passed4

 """
 upload_CDsearch.pl -i $cdsearch_hit_res -type h -conf $config
 """
}

process 'CDsearch_feat_upload'{

 maxForks 1

 input:
 file cdsearch_feat_res from cdSearch_feat_result
 file config from config4perl
 file def_done from definition_passed5

 """
 upload_CDsearch.pl -i $cdsearch_feat_res -type f -conf $config
 """
}

if(params.keggFile == "" ||  params.keggFile == null ) {

 println "Please run KEGG KO group annotation on the web server http://www.genome.jp/tools/kaas/"
 
}else{

 keggfile=file(params.keggFile)

process 'kegg_upload'{

 maxForks 1

 input:
 file keggfile from keggfile
 file config from config4perl
 file def_done from definition_passed6

 """
 load_kegg_KAAS.pl -input $keggfile -rel $params.kegg_release -conf $config
 """
}

process 'blast_annotator_upload'{

 maxForks 1

 input:
  file blastAnnot from blast_annotator_results
  file config from config4perl
  file def_done from definition_passed7

 """
  awk '\$2!=\"#\"{print \$1\"\t\"\$2}' $blastAnnot > two_column_file
  upload_go_definitions.pl -i two_column_file -conf $config -mode go -param 'blast_annotator'
 """

}


}
//the end of the exists loop for uploading

/*
Generate result files and report
*/

workflow.onComplete {

 process 'generateResultFiles'{
  input:
   file config from config4perl
 
   """
   get_results.pl -conf $config
  """
 }
 
 process 'generateGFF3File'{
  input:
   file config from config4perl
 
  """
  get_gff3.pl -conf $config
  """
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
