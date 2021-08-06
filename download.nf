#!/usr/bin/env nextflow

/*
 * Copyright (c) 2017-2021, Centre for Genomic Regulation (CRG)
 *
 * Copyright (c) 2021, Toni Hermoso Pulido
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


// default parameters
params.help = false

// Main result and log dirs
params.dbPath = "/nfs/db"

// Version
params.iprscanVersion = "5.48-83.0"
params.koVersion = "2021-05-02"

// URLs
params.iprscanURL = "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/${params.iprscanVersion}/interproscan-${params.iprscanVersion}-64-bit.tar.gz "
params.koURLlist = "ftp://ftp.genome.jp/pub/db/kofam/archives/${params.koVersion}/ko_list.gz"
params.koURLprofiles = "ftp://ftp.genome.jp/pub/db/kofam/archives/${params.koVersion}/profiles.tar.gz"
params.goOboURL = "http://www.geneontology.org/ontology/gene_ontology.obo"

// NCBI DB list
params.blastDBList = "swissprot,pdbaa"
params.blastTimeout = 600

// Specific DB Paths
Date date = new Date()
String datePart = date.format("yyyyMM")
params.blastDbFolder = "${params.dbPath}/ncbi/${datePart}/blastdb/db"
params.dbipscanPath = "${params.dbPath}/iprscan/${params.iprscanVersion}"
params.dbKOPath = "${params.dbPath}/kegg/${params.koVersion}"
params.oboFolder = "${params.dbPath}/geneontology/${datePart}"

// Mail for sending reports
params.email = ""

//print usage
if ( params.help ) {
  log.info ''
  log.info 'Functional Annotation - Download datasets pipeline'
  log.info '----------------------------------------------------'
  log.info ''
  log.info 'Usage: '
  log.info "  ./nextflow run download.nf --config params.config [options]"
  log.info ''
  log.info 'Options:'
  log.info '-resume		resume pipeline from the previous step, i.e. in case of error'
  log.info '-help		this message'
  exit 1
}

if ( params.dbPath == null || params.dbPath == "" ) {
  log.info "No target directory specified"
  exit 1
}

if ( params.blastDBList == null || params.blastDBList == "" ) {
  log.info "No BLAST DBs provided"
  exit 1
}

blastDBChannel = Channel.fromList( params.blastDBList?.tokenize(',') )


process oboFile {

  publishDir params.oboFolder, mode: 'copy'
  label 'download'

  output:
  file "gene_ontology.obo" into oboFile

  """
  curl --retry 3 -o gene_ontology.obo ${params.goOboURL};
  """

}


process downloadNCBI {

  publishDir params.blastDbFolder, mode: 'copy'

  label 'blast'

  input:
  val db from blastDBChannel

  output:
  set val(db), file ("*") into blastdb

  """
  update_blastdb.pl ${db} --timeout ${params.blastTimeout} --decompress
  blastdbcmd -dbtype prot -db ${db} -entry all -out ${db}.fa
  """

}

process formatDIAMOND {

  publishDir params.blastDbFolder, mode: 'copy'

  label 'diamond'

  input:
  set db, file(fasta) from blastdb

  output:
  file "*" into formatted_blastdb

  """
  diamond makedb --in ${db}.fa --db ${db}
  """

}

process downloadInterPro {

  publishDir params.dbipscanPath, mode: 'copy'
  label 'ipscan'

  output:
  file "*" into interpro_data

  """
  curl --retry 3 -o iprscan.tar.gz ${params.iprscanURL};
  tar zxf iprscan.tar.gz
  rm iprscan.tar.gz
  cd interproscan-${params.iprscanVersion}
  python3 initial_setup.py
  cd ..
  mv interproscan-${params.iprscanVersion}/data .
  rm -rf interproscan-${params.iprscanVersion}
  mv data/* .
  """

}

process downloadKO {

  publishDir params.dbKOPath, mode: 'copy'

  label 'download'

  output:
  file "ko_list" into ko_list
  file "profiles" into ko_profiles
  file "ko_store" into ko_store

  """
  curl --retry 3 -o ko_list.gz ${params.koURLlist};
  gunzip ko_list.gz;
  curl --retry 3 -o profiles.tar.gz ${params.koURLprofiles};
  tar zxf profiles.tar.gz; rm profiles.tar.gz;
  mkdir ko_store
  bulkDownloadKEGG.pl ko_list ko_store
  """

}


// On finising
workflow.onComplete {

 println ( workflow.success ? "\nDone! Check downloaded datasets in --> $params.dbPath\n" : "Oops .. something went wrong" )

}

workflow.onError {

 println( "Something went wrong" )

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

        sendMail(to: params.email, subject: "[FA-nf] Download finished", body: msg)
    }
}
