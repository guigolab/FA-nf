#!/usr/bin/env nextflow

/*
 * Copyright (c) 2017-2021, Centre for Genomic Regulation (CRG)
 *
 * Copyright (c) 2017, Anna Vlasova
 *
 * Copyright (c) 2017, Emilio Palumbo
 *
 * Copyright (c) 2018-2021, Toni Hermoso Pulido
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
params.debug = false
params.dbEngine = "mysql" // SQLite otherwise

// Main input files
params.proteinFile = null;
params.gffFile = null;

// Main result and log dirs
params.resultPath = "${baseDir}/results/"
params.stdoutLog = "${baseDir}/logs/out.log"
params.stderrLog = "${baseDir}/logs/err.log"

// Sizes for different programs
params.chunkIPSSize = null
params.chunkBlastSize = null
params.chunkKoalaSize = null
params.chunkWebSize = null
params.debugSize = 2

// Blast related params
params.blastFile = null
params.evalue = 0.00001
params.diamond = null

// GO retrieval params
params.gogourl = ""
params.gogohits = 30
params.blastAnnotMode = "common" // common, most, all available so far

// KEGG
params.kolist = ""
params.koprofiles = ""
params.koentries = ""
params.kegg_release = null

// Params for InterProScan
//  Temporary location for InterproScan intermediary files. This can be huge
params.ipscantmp = "${baseDir}/tmp/"
//  Location of InterproScan properties. Do not modify unless it matches your container
params.ipscanproperties = "/usr/local/interproscan/interproscan.properties"

// Params for dealing with GFF
params.gffclean = true
params.gffstats = true
// Remove version from protein entries (e.g. X5543AP.2)
params.rmversion = false

// File with GO information, otherwise is downloaded
params.oboFile = null

// Skip params
params.skip_cdSearch = false

// Mail for sending reports
params.email = ""

//print usage
if ( params.help ) {
  log.info ''
  log.info 'Functional annotation pipeline'
  log.info '----------------------------------------------------'
  log.info 'Run functional annotation for a given species.'
  log.info ''
  log.info 'Usage: '
  log.info "  ./nextflow run main.nf --config params.config [options]"
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
protein = null
annotation = null
config_file = file(params.config)

dbFile = false
boolean exists = false
boolean mysql = false
gffavail = false
gffclean = false
gffstats = false
// Skip cdSearch
skip_cdSearch = false

if( params.dbEngine.toLowerCase()=="mysql" ) {
 mysql = true
}

if ( params.gffclean ) {
 gffclean = true
}

if ( params.gffstats ) {
 gffstats = true
}

if ( params.skip_cdSearch ) {
 skip_cdSearch = true
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
 if ( dbFile.exists() && dbFile.size() > 0 ) {
  exists = true
 }
}


// print log info

log.info ""
log.info "Functional annotation pipeline"
log.info ""
log.info "General parameters"
log.info "------------------"

if ( params.proteinFile == null || params.proteinFile == "" ) {
  log.info "No protein sequence file specified!"
  exit 1
} else {
  if ( file( params.proteinFile ).exists() && file( params.proteinFile ).size() > 0 ) {
    log.info "Protein sequence file            : ${params.proteinFile}"
    protein = file(params.proteinFile)
  } else {
    log.info "Protein sequence file does not exist or it is empty!"
    exit 1
  }
}

if ( params.gffFile == null || params.gffFile == "" ) {
  log.info "No GFF Structural Annotation file specified!"
  log.info "We proceed anyway..."
} else {
  if ( file( params.gffFile ).exists() && file( params.gffFile ).size() > 0 ) {
    log.info "GFF Structural Annotation file              : ${params.gffFile}"
    gffavail = true
    annotation = file(params.gffFile)
  } else {
    log.info "GFF Structural Annotation file is missing or empty."
    log.info "We stop the pipeline so you can check it and define as \"\" otherwise if no GFF file is provided."
    exit 1
  }
}

if ( params.blastFile ) {
  log.info "BLAST results file           : ${params.blastFile}"
}

log.info "Species name                  : ${params.speciesName}"
log.info "KEGG species                 : ${params.kegg_species}"

if ( mysql ) {
  log.info "MySQL FA database 		       : ${params.dbname}"
} else {
  log.info "SQLite FA database 		       : $dbFileName"
}

if ( skip_cdSearch ) {
  log.info "CD-Search queries will be skipped."
}


// split protein fasta file into chunks and then execute annotation for each chunk
// chanels for: interpro, blast, signalP, targetP, cdsearch_hit, cdsearch_features

chunkSize = params.chunkSize
chunkBlastSize = chunkSize
chunkIPSSize = chunkSize
chunkKoalaSize = chunkSize
chunkWebSize = chunkSize

if ( params.chunkBlastSize ) {
  chunkBlastSize = params.chunkBlastSize
}

if ( params.chunkIPSSize ) {
  chunkIPSSize = params.chunkIPSSize
}

if ( params.chunkKoalaSize ) {
  chunkKoalaSize = params.chunkKoalaSize
}

if ( params.chunkWebSize ) {
  chunkWebSize = params.chunkWebSize
}

seqData = Channel
 .from(protein)
 .splitFasta( by: chunkSize )

 seqBlastData = Channel
  .from(protein)
  .splitFasta( by: chunkBlastSize )

seqKoalaData = Channel
 .from(protein)
 .splitFasta( by: chunkKoalaSize )

 seqIPSData = Channel
  .from(protein)
  .splitFasta( by: chunkIPSSize )

seqWebData = Channel
 .from(protein)
 .splitFasta( by: chunkWebSize )

ipscan_properties = file(params.ipscanproperties)

if ( params.debug == "true" || params.debug == true ) {
 println("Debugging... only the first $params.debugSize chunks will be processed")
 // Diferent parts for different processes.
 // TODO: With DSL2 this is far simpler
 (seq_file1, seq_file2) = seqData.take(params.debugSize).into(2)
 (seq_file_blast) = seqBlastData.take(params.debugSize).into(1)
 (seq_file_koala) = seqKoalaData.take(params.debugSize).into(1)
 (seq_file_ipscan) = seqIPSData.take(params.debugSize).into(1)
 (web_seq_file1, web_seq_file2) = seqWebData.take(params.debugSize).into(2)

 testNum = ( params.chunkSize.toInteger() * params.debugSize )
 seqTestData = Channel
  .from(protein)
  .splitFasta(by: testNum)

  (seq_test) = seqTestData.take(1).into(1)

} else {
 println("Process entire dataset")
 (seq_file1, seq_file2) = seqData.into(2)
 (seq_file_blast) = seqBlastData.into(1)
 (seq_file_koala) = seqKoalaData.into(1)
 (seq_file_ipscan) = seqIPSData.into(1)
 (web_seq_file1, web_seq_file2) = seqWebData.into(2)

 seqTestData = Channel
  .from(protein)

 // Anything for keeping. This is only kept for coherence
 (seq_test) = seqTestData.into(1)

}

if ( params.oboFile == "" || params.oboFile == null ) {
  oboFile = downloadURL( "http://www.geneontology.org/ontology/gene_ontology.obo", "gene_ontology.obo" )
} else {
  oboFile = params.oboFile
}


// Preprocessing GFF File
if ( gffavail ) {

  if ( gffclean ) {

   process cleanGFF {

    publishDir params.resultPath, mode: 'copy'

    label 'gffcheck'

    input:
     file config_file

    output:
     file "annot.gff" into gff_file
     file "annot.gff.clean.txt" into gff_file_log

     """
      # get annot file
      export escaped=\$(echo '$baseDir')
      export basedirvar=\$(echo '\\\$\\{baseDir\\}')
      agat_sp_gxf_to_gff3.pl --gff `perl -lae 'if (\$_=~/gffFile\\s*\\=\\s*[\\x27|\\"](\\S+)[\\x27|\\"]/) { \$base = \$1; \$base=~s/\$ENV{'basedirvar'}/\$ENV{'escaped'}/g; print \$base }' $config_file` -o annot.gff > annot.gff.clean.txt
     """

   }


  } else {

   process copyGFF {

    label 'gffcheck'

    input:
     file config_file

    output:
     file "annot.gff" into gff_file

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
     file "*.txt" into gff_stats

     """
      # Generate Stats
      agat_sp_statistics.pl --gff $gff_file > ${gff_file}.stats.txt
     """

   }


  }

} else {

  // Dummy empty GFF
  process dummyGFF {

   label 'gffcheck'

   input:
    file config_file

   output:
    file "annot.gff" into gff_file

    """
     # empty annot file
     touch annot.gff
    """

  }
}

// Database setup below
process initDB {

 input:
  file config_file
  file gff_file
  file seq from seq_test

 output:
  file 'config' into (config4perl1, config4perl2, config4perl3, config4perl4, config4perl5, config4perl6, config4perl7, config4perl8, config4perl9, config4perl10, config4perl11)

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

   if ( gffavail && gffclean ) {
    command += " -gff ${gff_file}"
   }
 } else {

   if (!exists) {
     command += "fa_main.v1.pl init -conf config"

    if ( gffavail && gffclean ) {
     command += " -gff ${gff_file}"
    }
   } else {
     log.info "SQLite database ${dbFileName} exists. We proceed anyway..."
   }
 }

 if ( params.debug=="TRUE"||params.debug=="true" ) {
   // If in debug mode, we restrict de seq entries we process
   command += " -fasta ${seq}"
 }

 if ( params.rmversion=="TRUE"||params.rmversion=="true" ) {
   // If remove versioning in protein sequences (for cases like ENSEMBL)
   command += " -rmversion"
 }

 command
}

// Blast like processes
// TODO: To change for different aligners
diamond = false

if( params.diamond == "true" || params.diamond == true ) {
 diamond = true
}

// BlastAnnotMode
blastAnnotMode = "common"
if( params.blastAnnotMode != "" && params.blastAnnotMode != null ) {
  blastAnnotMode = params.blastAnnotMode
}

if ( params.blastFile == "" ||  params.blastFile == null ){

 // program-specific parameters
 db_name = file(params.blastDbPath).name
 db_path = file(params.blastDbPath).parent

 // Handling Database formatting
 formatdbDetect = "false"

 if ( diamond ) {

  formatDbFileName = params.blastDbPath + ".dmnd"
  formatDbFile = file(formatDbFileName)
  if ( formatDbFile.exists() && formatDbFile.size() > 0 ) {
   formatdbDetect = "true"
  }

  if ( formatdbDetect == "false" ) {

   process diamondFormat{

    label 'diamond'

    output:
    file "${db_name}_formatdb.dmnd" into formatdb

    """
     diamond makedb --in ${db_path}/${db_name} --db "${db_name}_formatdb"
    """
   }

  } else {
   formatdb = params.blastDbPath
  }

 } else {

  formatDbDir = file( db_path )
  filter =  ~/${db_name}.*.phr/
  def fcount = 0
  formatDbDir.eachFileMatch( filter ) { it ->
   fcount = fcount + 1
  }
  if ( fcount > 0 ) {
    formatdbDetect = "true"
  }

  println( formatdbDetect )
  if ( formatdbDetect == "false" ) {

   // println( "TUR" )

   process blastFormat{

    label 'blast'

    output:
    file "${db_name}.p*" into formatdb

    """
     makeblastdb -dbtype prot -in ${db_path}/${db_name} -parse_seqids -out ${db_name}
    """
   }

  } else {
   formatdb = params.blastDbPath
  }
 }

 if ( diamond == true ) {

  process diamond{

   label 'diamond'

   input:
   file seq from seq_file_blast
   file formatdb_file from formatdb

   output:
   file "blastXml${seq}" into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

   script:
   if ( formatdbDetect == "false" ) {
    command = "diamond blastp --db ${formatdb_file} --query $seq --outfmt 5 --threads ${task.cpus} --evalue ${params.evalue} --out blastXml${seq}"
   } else {
    command = "diamond blastp --db ${db_path}/${db_name} --query $seq --outfmt 5 --threads ${task.cpus} --evalue ${params.evalue} --out blastXml${seq}"
   }

   command

  }

 } else {

  process blast{

   label 'blast'

   // publishDir "results", mode: 'copy'

   input:
   file seq from seq_file_blast
   file formatdb_file from formatdb

   output:
   file "blastXml${seq}" into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

   script:
   if ( formatdbDetect == "false" ) {
    command = "blastp -db ${formatdb_file} -query $seq -num_threads ${task.cpus} -evalue ${params.evalue} -out blastXml${seq} -outfmt 5"
   } else {
    command = "blastp -db ${db_path}/${db_name} -query $seq -num_threads ${task.cpus} -evalue ${params.evalue} -out blastXml${seq} -outfmt 5"
   }

   command
  }

 }

} else {

 blastInput=file(params.blastFile)

 process convertBlast {

  // publishDir "results", mode: 'copy'

  input:
  file blastFile from blastInput

  output:
  file("*.xml") into (blastXmlResults1, blastXmlResults2, blastXmlResults3)

  """
   hugeBlast2XML.pl -blast $blastFile -n 1000 -out blast.res
  """

 }
}

if ( params.kolist != "" ||  params.kolist != null ){

  process kofamscan{

   label 'kofamscan'

   input:
   file seq from seq_file_koala

   output:
   file "koala_${seq}" into koalaResults

   """
    exec_annotation --cpu ${task.cpus} -p ${params.koprofiles} -k ${params.kolist} -o koala_${seq} $seq
   """

  }

  process kofam_parse {

   input:
   file "koala_*" from koalaResults.collect()

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


 if (params.keggFile == "" ||  params.keggFile == null ) {

  println "Please run KEGG KO group annotation on the web server http://www.genome.jp/tools/kaas/"

 }

 keggfile = file(params.keggFile)

}

// GO retrieval from BLAST results
if (params.gogourl != "") {

  process blast_annotator {

   label 'blastannotator'

   input:
   file blastXml from blastXmlResults2.flatMap()

   output:
   file "blastAnnot" into blast_annotator_results

  """
   blast-annotator.pl -in $blastXml -out blastAnnot --hits $params.gogohits --url $params.gogourl -t $blastAnnotMode -q --format blastxml
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

process 'definition_upload'{

 maxForks 1

 // publishDir "results", mode: 'copy'
 input:
 file "def*" from blastDef_results.collect()
 file config from config4perl1

 output:
 file 'def_done' into definition_passed

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat def* > allDef; \
   upload_go_definitions.pl -i allDef -conf \$config -mode def -param 'blast_def' > def_done \
  "

  command
}

process ipscn {

    label 'ipscan'

    input:
    file seq from seq_file_ipscan
    file ("interproscan.properties") from file( ipscan_properties )

    output:
    file("out_interpro_${seq}") into (ipscn_result1, ipscn_result2)

    """
    sed 's/*//g' $seq > tmp4ipscn
    interproscan.sh -i tmp4ipscn --goterms --iprlookup --pathways -o out_interpro_${seq} -f TSV -T ${params.ipscantmp}
    """
}

process 'cdSearchHit' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from web_seq_file1

    output:
    file("out_hit_${seq}") into cdSearch_hit_result

    script:
    if ( skip_cdSearch ) {
      // Dummy content
      command = "touch out_hit_${seq}"
    } else {
      command = "submitCDsearch.pl -o out_hit_${seq} -in $seq"
    }

    command
}

process 'cdSearchFeat' {

    label 'cdSearch'

    maxForks 1

    input:
    file seq from web_seq_file2

    output:
    file("out_feat_${seq}") into cdSearch_feat_result

    script:
    if ( skip_cdSearch ) {
      // Dummy content
      command = "touch out_feat_${seq}"
    } else {
      command = "submitCDsearch.pl -t feats -o out_feat_${seq} -in $seq"
    }

    command
}


process 'signalP' {

    label 'sigtarp'

    input:
    file seq from seq_file1

    output:
    file("out_signalp_${seq}") into (signalP_result1, signalP_result2)

    """
    signalp  $seq > out_signalp_${seq}
    """
}

process 'targetP' {

    label 'sigtarp'

    input:
    file seq from seq_file2

    output:
    file("out_targetp_${seq}") into (targetP_result1, targetP_result2)

    """
    targetp -P -c  $seq > out_targetp_${seq}
    """
}

process 'signalP_upload'{

 maxForks 1

 input:
 file "out_signalp*" from signalP_result1.collect()
 file config from config4perl2
 file def_done from definition_passed

 output:
 file("upload_signalp") into upload_signalp


 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat out_signalp* > allSignal ; \
   load_CBSpredictions.signalP.pl -i allSignal -conf \$config -type s > upload_signalp ; \
  "

  command
}


process 'targetP_upload'{

 maxForks 1

 input:
 file "out_targetp*" from targetP_result1.collect()
 file config from config4perl3
 file upload_signalp from upload_signalp

 output:
 file("upload_targetp") into upload_targetp

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat out_targetp* > allTarget ; \
   load_CBSpredictions.signalP.pl -i allTarget -conf \$config -type t > upload_targetp ; \
  "

  command
}

process 'interpro_upload'{

 maxForks 1

 input:
 file "out_interpro*" from ipscn_result1.collect()
 file config from config4perl4
 file upload_targetp from upload_targetp

 output:
 file("upload_interpro") into upload_interpro


 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat out_interpro* > allInterpro ; \
   run_interpro.pl -mode upload -i allInterpro -conf \$config > upload_interpro ; \
  "

  command
}


process 'CDsearch_hit_upload'{

 maxForks 1

 input:
 file "out_hit*" from cdSearch_hit_result.collect()
 file config from config4perl5
 file upload_interpro from upload_interpro

 output:
 file("upload_hit") into upload_hit

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat out_hit* > allCDsearchHit ; \
   upload_CDsearch.pl -i allCDsearchHit -type h -conf \$config > upload_hit ; \
  "

  command
}

process 'CDsearch_feat_upload'{

 maxForks 1

 input:
 file "out_feat*" from cdSearch_feat_result.collect()
 file config from config4perl6
 file upload_hit from upload_hit

 output:
 file("upload_feat") into upload_feat

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat out_feat* > allCDsearchFeat ; \
   upload_CDsearch.pl -i allCDsearchFeat -type f -conf \$config > upload_feat ; \
  "

  command
}

process 'blast_annotator_upload' {

 maxForks 1

 input:
  file "blastAnnot*" from blast_annotator_results.collect()
  file config from config4perl7
  file upload_feat from upload_feat

  output:
  file("upload_blast") into upload_blast

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   cat blastAnnot* > allBlast ; \
   awk '\$2!=\"#\"{print \$1\"\t\"\$2}' allBlast > two_column_file ; \
   upload_go_definitions.pl -i two_column_file -conf \$config -mode go -param 'blast_annotator' > upload_blast ; \
  "

  command
}

if ( params.koentries == "" ) {

  process 'kegg_download'{

   maxForks 1

   input:
   file keggfile from keggfile
   file config from config4perl8

   output:
   file("down_kegg") into (down_kegg)


   script:

    command = "download_kegg_KAAS.pl -input $keggfile -conf $config > done 2>err"

    command
  }

} else {

  process 'kegg_download_dummy' {

   maxForks 1

   input:
   file keggfile from keggfile
   file config from config4perl8

   output:
   file("down_kegg") into (down_kegg)


   script:

    command = "touch down_kegg"

    command

  }
}

process 'kegg_upload' {

 label 'kegg_upload'

 maxForks 1

 input:
 file keggfile from keggfile
 file config from config4perl9
 file("down_kegg") from down_kegg
 // We do after blast Upload
 file("upload_blast") from upload_blast

 output:
 file('done') into (last_step1, last_step2)


 script:

  command = checkMySQL( mysql, params.mysqllog )


  if ( params.koentries == "" ) {
    command += " \
     load_kegg_KAAS.pl -input $keggfile -dir down_kegg -rel $params.kegg_release -conf \$config > done 2>err; \
    "
  } else {
    command += " \
     load_kegg_KAAS.pl -input $keggfile -entries $params.koentries -rel $params.kegg_release -conf \$config > done 2>err; \
    "
  }

  command
}

process 'generateResultFiles'{
 input:
  file config from config4perl10
  file all_done from last_step1

 script:

  command = checkMySQL( mysql, params.mysqllog )

  command += " \
   get_results.pl -conf \$config -obo ${oboFile} ; \
  "

  command
}

if ( annotation != null && annotation != "" ){

process 'generateGFF3File'{
 input:
  file config from config4perl11
  file all_done from last_step2


 script:

  command = checkMySQL( mysql, params.mysqllog )

  // TODO: add case for debug using -list
  command += " \
   get_gff3.pl -conf \$config ; \
  "

  command
}

}

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

def downloadURL( address, filename ) {
  downFile = new File( filename ) << new URL (address).getText()
  return downFile.absolutePath
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


if (params.email == "yourmail@yourdomain" || params.email == "") {
    log.info 'Skipping email\n'
} else {
    log.info "Sending email to ${params.email}\n"

    workflow.onComplete {

    def msg = """\
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        workDir     : ${workflow.workDir}
        exit status : ${workflow.exitStatus}
        Error report: ${workflow.errorReport ?: '-'}
        """
        .stripIndent()

        sendMail(to: params.email, subject: "[FA-nf] Execution finished", body: msg)
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
