# FA-nf

[![DOI](https://zenodo.org/badge/209515370.svg)](https://zenodo.org/badge/latestdoi/209515370)

A pipeline for **functional annotation** of proteins from non-model organisms implemented in Nextflow engine.

The pipeline uses a set of well characterised software to assign functional information to the proteins of interests, i.e. domains, GO terms annotation, putative name and some other features.

The software used in this pipeline is free software for academic users. For the software from the Center for Biological Sequence (CBS), i.e. signalP, a suitable license agreement should be obtained.

## Installation
The pipeline is build on Nextflow as a woking engine, so it need to be installed first

```
 wget -qO- get.nextflow.io | bash
```
The detailed procedure is described in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html)

## Running the pipeline

The annotation itself, when various software is excuted and the results are stored in an internal database.

Result files, including a main annotation file in gff format and annotation report, are generated at the end of the pipeline.

The annotation step can be launched by using the following command:

```
./nextflow run -bg main.nf --config params.config &> logfile
```

## Pipeline parameters

### `-resume`
This Nextflow build-in parameter allow to re-execute processes that has changed or crashed during the pipeline run. Only processes that not finished will be executed.
More information can be found in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html#modify-and-resume)

### `-config`
The pipeline require as an input the configuration file with specified parameters, such as path to the input files, species name, KEGG species abbreviations used to obtain KO groups, and some more.

The example of configuration file is included into this repository with name ```params.config```

## Pipeline steps

![Pipeline flow chart](./flowchart.png "Pipeline flow chart")

* **blast**: it perfoms BLAST search against defined database from input files
* **diamond**: the same as above but using DIAMOND ( ```diamond = "true"``` in config file )
* **ipscn**: it performs InterProScan analyses from input files
* **signalP**: it performs signalP analyses from input files
* **targetP**: it performs targetP analyses from input files
* **blast_annotator**: it retrieves GO terms from BLAST hits
* **blastDef**: it attaches a definition to input entries based on BLAST hits
* **cdSearchHit**: it performs a NCBI CDSearch Hit query
* **cdSearchFeat**: it performs a NCBI CDSearch Feature query
* **initDB**: it initialitzes the Database used for gathering data from different analyses and later generating the reports
* **definition_upload**: it uploads definitions derived from BLAST into the DB
* **signalP_upload**: it uploads signalP analyses into the DB
* **targetP_upload**: it uploads targetP analyses into the DB
* **CDSearch_hit_upload**: : it uploads NCBI CDSearch Hit analyses into the DB
* **CDSearch_feat_upload**: it uploads NCBI CDSearch Feature analyses into the DB
* **blast_annotator_upload**: it uploads GO terms from BLAST hits into the DB
* **kegg_download**: it downloads KO (Kegg Ortholog) from KEGG
* **kegg_upload**: it retrieves and uploads KEGG data (either from a KAAS file or KofamKOALA) into the DB
* **generateResultFiles**: it generates report files
* **generateGFF3File**: if GFF provided as input, it provides a modified GFF with additional information from the previous annotation steps

### GFF cleaning

...

### Formatted databases

* For NCBI BLAST+: ```blastDbPath = "/path/to/db"``` and ```diamond = "false"```. It looks for formatted database files (normally named db.p* for protein type based ones), otherwise it will try to format FASTA file with that name
* For DIAMOND: ```blastDbPath = "/path/to/db"``` and ```diamond = "true"```. It looks for a single formatted database file (normally named db.dmnd), otherwise it will try to format the FASTA file with that name (gzip compressed files accepted)

### Retrieval of GO terms from BLAST results

Retrieval of GO terms from BLAST results can be performed either from [BLAST2GO](https://www.blast2go.com/) results or from other methods as far as a BLAST2GO-compatible output format is provided.

As an example, in our case we are using a [web API](https://github.com/toniher/gogoAPI) providing this information from [UniProt GOA](https://www.ebi.ac.uk/GOA) database imported into a MySQL and/or [Neo4j](https://github.com/toniher/neo4j-biorelation).

### KEGG orthology groups
Predictions of the KEGG orthology groups (KO) can be obtained outside of the pipeline, i.e. via [KAAS server](http://www.genome.jp/tools/kaas/) or using a previously set-up version of [KofamKOALA](https://www.genome.jp/tools/kofamkoala/).

Note: in the first case for the downstream processing of the KO file it is very important to store information about species used for predictions. Species are encoded in three lellters abbreviations, and the list can be copied from the 'Selected organisms' field in the kaas_main form.

## Result files

* **«myorg».gff**:
* **annot.gff**:
* **annot.gff.clean.txt**:
* **annot.gff.stats.txt**:
* **annotatedVsnot.png**:
* **go_terms_byGene.txt**:
* **go_terms.txt**:
* **interProScan.res.tsv**:
* **protein_definition.txt**:
* **signalP.res.tsv**:
* **targetP.res.tsv**:
* **total_stats.txt**:


## Running in MySQL mode

Running in MySQL mode improves the speed of the pipeline, but some care must be taken for including connection details in the configuration.

The relevant paremetres below:

```  
    # Database engine. Specify MySQL (otherwise 'SQLite' will be used)
    dbEngine = "MySQL"
    # Database name. If it does not exist, if the user has enough permissions it will be created
    dbname = "Pvulgaris"
    # Database user name
    dbuser = "test"
    # Database user password
    dbpass = "test"
    # Port of the MySQL engine
    dbport = 12345
    # The host where the MySQL engine is located. Skip it if using the wrapper below
    dbhost = 0.0.0.0
    # If using the wrapper below, where MySQL data will be stored
    mysqldata = "${baseDir}/mysql/"
    # If using the wrapper below, where MySQL instance logs will be stored
    mysqllog = "${baseDir}/tmp"
    # If using the wrapper below, which Singularity image will be used
    mysqlimg = "/software/bi/biocore_tools/git/singularity/mariadb-10.3.simg"
```

### Execution without an ad-hoc database

We offer a convenience wrapper script for running the pipeline in MySQL mode either in SGE-compatible clusters or in local without having to set up any MySQL server and database before thanks to Singularity.

    nohup perl run_pipeline_mysql.pl -conf ./params.config  &> log.mysql &

It is also possible to pass additional Nextflow parameters

    nohup perl run_pipeline_mysql.pl -params "-with-dag -with-report -with-timeline" -conf ./params.config  &> log.mysql &


#### Inspection of MySQL database

If run without an ad-hoc database, this is convenient for checking results database once analyses are finished. NO further analyses are run.

	nohup perl run_pipeline_mysql.pl -mysqlonly -conf ./params.config &> log.mysql.only &


for further options or details, run:

    perl run_pipeline_mysql.pl -h


## Associated containers

We recommend installing either [Docker](https://www.docker.com/) or [Singularity](https://sylabs.io/singularity/) (the latter preferred).

The software used all along this pipeline is encapsulated in, at least, 4 containers:

As written down in ```nextflow.config``` file, whenever possible, we try to provide necessary images in a public repository (e.g. [Docker hub](https://hub.docker.com/) or quay.io from [Biocontainers](https://biocontainers.pro/)). However, for some software that includes privative components, we suggest to build the container image by yourself.

* [SignalP and TargetP](https://github.com/biocorecrg/sigtarp_docker) (user needs to build this)
* [Interproscan and 3rd party tools](https://github.com/biocorecrg/interproscan_docker) (user needs to build this)

### How to build base container

The base container is [available in Docker Hub](https://hub.docker.com/r/guigolab/fa-nf) and Nextflow takes care automatically to retrieve it form there, but you can always decide to generate it yourself.

```
    # Generate Docker image
    docker build -t fa-nf .

    # Generate Singularity image if preferred
    sudo singularity build fa-nf.sif docker-daemon://fa-nf:latest
```
