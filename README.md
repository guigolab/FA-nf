# FA-nf

A pipeline for **functional annotation** of proteins from non-model organisms implemented in Nextflow engine.

The pipeline uses a set of well characterised software to assign functional information to the proteins of interests, i.e. domains, GO terms annotation, putative name and some other features.

The software used in this pipeline is free software for academic users. For the software from the Center for Biological Sequence (CBS), i.e. signalP, a suitable license agreement should be obtained.

## Requirements

### Nextflow installation
The pipeline is build on Nextflow as a woking engine, so it need to be installed first

```
 wget -qO- get.nextflow.io | bash 
```
The detailed procedure is described in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html)

### KEGG orthology groups
Predictions of the KEGG orthology groups (KO) should be obtained outside of the pipeline, i.e. via [KAAS server](http://www.genome.jp/tools/kaas/). 

Note: for the downstream processing of the KO file it is very important to store information about species used for predictions. Species are encoded in three lellters abbreviations, and the list can be copied from the 'Selected organisms' field in the kaas_main form.

### Configuration file
The pipeline require as an input the configuration file with specified parameters, such as path to the input files, specie name, KEGG specie abbreviations used to obtain KO groups, and some more.

The example of configuration file is included into this repository with name main_configuration.config

## Running the pipeline

The annotation itself, when various software is excuted and the results are stored in a internal database.

Result files, including main annotation file in gff format and annotation report in pdf format, are generated at the end of the pipeline.

The annotation step can be launched by using the following command:

```
./nextflow run -bg pipeline.nf --config configuration_file.config &> logfile 
```

![Pipeline flow chart](./flowchart.png "Pipeline flow chart")

## Pipeline parameters

#### `-resume`
This Nextflow build-in parameter allow to re-execute processes that has changed or crashed during the pipeline run. Only processes that not finished will be executed.
More information can be found in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html#modify-and-resume)

## Pipeline steps

* **blast**: it perfoms BLAST search against defined database from input files
* **ipscn**: it performs InterProScan analyses from input files
* **signalP**: it performs signalP analyses from input files
* **targetP**: it performs targetP analyses from input files
* **blast_annotator**: it retrieves GO terms from BLAST hits
* **blastDef**: it suggest a definition to input entries based on BLAST hits
* **cdSearchHit**: it performs a NCBI CDSearch Hit query
* **cdSearchFeat**: it performs a NCBI CDSearch Feature query
* **initDB**: it initialitzes the Database used for gathering data from different analyses and later generating the reports
* **definition_upload**: it uploads definitions derived from BLAST into the DB
* **signalP_upload**: it uploads signalP analyses into the DB
* **targetP_upload**: it uploads targetP analyses into the DB
* **CDSearch_hit_upload**: : it uploads NCBI CDSearch Hit analyses into the DB
* **CDSearch_feat_upload**: it uploads NCBI CDSearch Feature analyses into the DB
* **blast_annotator_upload**: it uploads GO terms from BLAST hits into the DB
* **kegg_upload**: it retrieves and uploads KEGG data into the DB 
* **generateResultFiles**: it generates report files
* **generateGFF3File**: if GFF provided as input, it provides a modified GFF with additional information

### About blast_annotator

Retrieval of GO terms from BLAST results can be performed either from [BLAST2GO](https://www.blast2go.com/) results or from other methods as far as a BLAST2GO-compatible output format is provided.

As a example, in our case we are using a [web API](https://github.com/toniher/gogoAPI) providing this information from [UniProt GOA](https://www.ebi.ac.uk/GOA) database imported into a MySQL and [Neo4j](https://github.com/toniher/neo4j-biorelation).

## Associated containers

We recommend installing either [Docker](https://www.docker.com/) of [Singularity](https://sylabs.io/singularity/) (the latter preferred).

The software used all along this pipeline is encapsulated in, at least, 4 containers:

Whenever possible, we try to provide necessary images in a public repository (e.g. Docker hub). However, for some software that includes privative components, we suggest to build the container image by yourself.

* [NCBI Blast](https://hub.docker.com/r/ncbi/blast)
* [SignalP and TargetP](https://github.com/biocorecrg/sigtarp_docker) (user needs to build this)
* [Interproscan and 3rd party tools](https://github.com/biocorecrg/interproscan_docker) (user needs to build this)
* [Environment for annotation scripts](https://hub.docker.com/r/toniher/fa-nf)

## How to build a container

    docker build -t fa-nf .

    sudo singularity build fa-nf.sif docker-daemon://fa-nf:latest

## Running in MySQL mode

We offer a convenience wrapper script for running the pipeline in MySQL mode either in SGE-compatible clusters or in local. 

    nohup perl run_pipeline_mysql.pl -conf ./main_configuration.config  &> log.mysql &


## Running only MySQL

This is convenient for checking results database once analyses are finished. NO further analyses are run.

	nohup perl run_pipeline_mysql.pl -mysqlonly -conf ./main_configuration.config &> log.mysql.only &


for further options or details, run:

    perl run_pipeline_mysql.pl -h


