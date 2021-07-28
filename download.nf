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
params.ipscanVersion = "5.48-83.0"
params.koVersion = "2021-05-02"

// URLs
params.ipscanURL = "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/5/${params.ipscanVersion}/interproscan-${params.ipscanVersion}-64-bit.tar.gz "
params.koURLlist = "ftp://ftp.genome.jp/pub/db/kofam/archives/${params.koVersion}/ko_list.gz"
params.koURLprofiles = "ftp://ftp.genome.jp/pub/db/kofam/archives/${params.koVersion}/profiles.tar.gz"

// File with GO information, otherwise is downloaded
params.oboFile = null

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

if ( params.oboFile == "" || params.oboFile == null ) {
  oboFile = downloadURL( "http://www.geneontology.org/ontology/gene_ontology.obo", "gene_ontology.obo" )
} else {
  oboFile = params.oboFile
}



def downloadURL( address, filename ) {
  downFile = new File( filename ) << new URL (address).getText()
  return downFile.absolutePath
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
