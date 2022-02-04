# FA-nf

[![DOI](https://zenodo.org/badge/209515370.svg)](https://zenodo.org/badge/latestdoi/209515370)

A pipeline for **functional annotation** of proteins from non-model organisms implemented in Nextflow engine.

The pipeline uses a set of well characterised software to assign functional information to the proteins of interests, i.e. domains, GO terms annotation, putative name and some other features.

The software used in this pipeline is mostly free software for academic users. For some software, such as signalP, a suitable license agreement should be obtained. More details about how to use this software in the *Associated containers* section.

## Installation

If you want to use the ```latest``` version you can clone the last commit of the repository:

```
git clone --recursive https://github.com/guigolab/FA-nf
```

This will download FA-nf repository and also some repository submodules (in containers directory) that are needed if we want to generate custom container images.

This will generate a FA-nf directory with the pipeline. You can go there inside:

```
cd FA-nf
```

Alternately, and actually recommended, you can clone the whole repository and choose the tag you want with ```git checkout``` command, or download a specific release from: https://github.com/guigolab/FA-nf/releases

Since the pipeline is built on Nextflow as a woking engine, it needs to be installed as well:

```
 export NXF_VER=20.10.0; curl -s https://get.nextflow.io | bash
```
The detailed procedure is described in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html)

You can place the Nextflow binary somewhere in your ```PATH``` or in the same location where the pipeline is going to be run.

### Associated containers

We recommend installing either [Docker](https://www.docker.com/) or [Singularity](https://singularity.hpcng.org/) (the later is preferred).

The software used all along this pipeline is encapsulated in several containers:

As written down in ```nextflow.config``` file, whenever possible, we try to provide necessary images in a public repository (e.g. [Docker hub](https://hub.docker.com/) or quay.io from [Biocontainers](https://biocontainers.pro/)). However, for some software that includes privative components, we suggest to build the container image by yourself.

Custom containers are available as Git submodules in ```containers``` directory. **They need to be generated first if privative software is used.**

* [SignalP and TargetP](https://github.com/biocorecrg/sigtarp_docker) (Please check **sigtarp** process in ```nextflow.config```)
* [Interproscan and 3rd party tools](https://github.com/biocorecrg/interproscan_docker) (Please check **ipscan** process in ```nextflow.config```. Two recipes are available: one with privative software and one without. The later is already available in Docker Hub)

#### How to build base container

The base container is already [available in Docker Hub](https://hub.docker.com/r/guigolab/fa-nf) and Nextflow takes care automatically to retrieve it form there, but you can always decide to generate it yourself.

```
    # Generate Docker image from latest version
    docker build -t fa-nf .

    # Generate Singularity image if preferred
    sudo singularity build fa-nf.sif docker-daemon://fa-nf:latest
```

### Dataset resources

For downloading and formatting diferent datasets used by the programs part of this pipeline, [some scripts are provided here](https://github.com/toniher/biomirror/) for convenience.

Alternately, a separate Nextflow pipeline is also provided for downloading all the minimally necessary datasets from Internet sources.

```
./nextflow run -bg download.nf --config params.download.config &> download.logfile
```

Below you can see the minimal amount of parameters in ```params.download.config``` file needed to run the script. These can be reused for running the actual pipeline.

```
  // Root path for Database
  params.dbPath = "/nfs/db"
  // Interproscan version used
  params.iprscanVersion = "5.52-86.0"
  // Kofam version used
  params.koVersion = "2021-05-02"
  // NCBI DB list - Comma separated
  params.blastDBList = "swissprot,pdbaa"
```

For convenience and test purposes, some sample pre-downloaded minimal datasets [can be found here](https://biocore.crg.eu/papers/FA-nf-2021/datasets/). You can simply extract their contents in your final ```dbPath```  location.

## Preparation of the pipeline

Before running the pipeline users need to adapt configuration files ```nextflow.config``` and ```params.config``` to fit their system and the location of the necessary datasets. File ```nextflow.config``` contains execution instructions for Nextflow engine, such as executor (slurm/local/other), number of cpus for parallel execution, and paths to container images. Detailed description of the parameters can be found in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html). User need to prepare this file once when setting up the pipeline. The second configuration file, ```params.config```, contains parameters for concrete annotation run, such as path to protein sequences in fasta format, size for chunks to split files, and location of additional datasets. Therefore this configuration file need to be adapted every time user runs a new dataset. We recommend to create a new cofiguration file per each annotation and keep it together with the result files.

Users also may need to download and index when necessary BLAST, Interproscan and KEGG datasets, as described in the **Dataset resources** section, and point where they are located in ```params.config``` file.  Parameters for concrete datasets are explained in the sections below.


## Running the pipeline

The annotation process consists of different programs which, once they are executed and finished, store their results in an internal database.

Result files, including a main annotation file in GFF format and diferent annotation reports, are generated at the last steps of the pipeline.

First of all, users need to adapt configuration files as specified in the previous section.

Once the datasets and containers/software are prepared, the whole annotation process can be launched by using the following command:

```
./nextflow run -bg main.nf --config params.config &> logfile
```

This executes this Nextflow pipeline in the background and its progress can be followed by inspecting ```logfile```. It can be done in real time with ```tail -f logfile``` command.

## Pipeline parameters

### `-resume`
This Nextflow build-in parameter allow to re-execute processes that has changed or crashed during the pipeline run. Only processes that not finished will be executed.
More information can be found in the [Nextflow documentation](https://www.nextflow.io/docs/latest/getstarted.html#modify-and-resume)

### `-config`
The pipeline require as an input the configuration file with specified parameters, such as path to the input files, species name, KEGG species abbreviations used to obtain KO groups, and some more.

The example of configuration file is included into this repository with name ```params.config```

Most parameters are self-explanatory. We highlight some below and in upcoming sections:

```
  // Protein fasta input
  proteinFile = "${baseDir}/dataset/P.vulgaris.proteins.fa"
  // GFF input
  gffFile = "${baseDir}/dataset/P.vulgaris.gff3"
```
These two files can be gzipped and the pipeline will take care to uncompress them in advance.


When approaching a new dataset, we suggest to run first the pipeline in **debug** mode (provided as such in example params config). This will analyze a limited number of protein entries. This way you may save time and troubleshoot some potential problems in your input files.

```
  // Whether to run pipeline in debug mode or not
  debug = "true"
```

One of the strenghts of Nextflow is allowing the parallelization and merging of several processes. In our case, input protein FASTA file is split and its sequences are delievered to the different used applications in chunks. For a quick processing, the optimal size of these chunks is not the same for each target application, and it can also depend on the setup of your HPC environment or network health. This can be tuned using the parameters below:

```
  // Number of protein sequences per chunk (used as fallback)
  chunkSize = 25
  // Number of protein sequences per chunk when using BLAST (or DIAMOND)
  chunkBlastSize = 50
  // Number of protein sequences per chunk when using InterProScan
  chunkIPSSize = 25
  // Number of protein sequences per chunk when using KofamKOALA
  chunkKoalaSize = 50
  // Number of protein sequences per chunk when submitting to web processes (CD-Search for now)
  chunkWebSize = 100
  // Number of chunks to be used when running in debug mode (e.g., for facllback processes this would be 5*25=125 protein sequences)
  debugSize = 5
```

## Pipeline steps

![Pipeline flow chart](./flowchart.png "Pipeline flow chart")

* **cleanGFF**: it cleans input GFF if enabled
* **statsGFF**: it provides some general statistics on the GFF input
* **blast**: it perfoms BLAST search against defined database from input files
* **diamond**: the same as above but using DIAMOND ( ```diamond = "true"``` in config file )
* **ipscn**: it performs InterProScan analyses from input files
* **signalP**: it performs signalP analyses from input files
* **targetP**: it performs targetP analyses from input files
* **blast_annotator**: it retrieves GO terms from BLAST hits
* **blastDef**: it attaches a definition to input entries based on BLAST hits
* **cdSearchHit**: it performs a NCBI CDSearch Hit query
* **cdSearchFeat**: it performs a NCBI CDSearch Feature query
* **initDB**: it initialitzes the database used for gathering data from different analyses and later generating the reports. Starting inputs are FASTA and GFF files
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

### GFF preparation

Despite [some existing recommendations](https://github.com/The-Sequence-Ontology/Specifications/blob/master/gff3.md), there is a huge diversity of GFF formats in the wild. For safety reasons, we introduce an initial step, thanks to [AGAT toolkit](https://github.com/NBISweden/AGAT), (which can be disabled with ```gffclean = "false" ```) for ensuring that GFF input files will be properly processed.

We suggest to check **annot.gff**, **annot.gff.clean.txt** and **annot.gff.stats.txt** files in results directory and generated during the first steps of the pipeline, for checking that used GFF files are OK.

### BLAST databases

The parameter ```blastDbPath``` hosts the path of the BLAST/DIAMOND database to be used. If not set or commented, a path compatible with the defaults from ```download.nf``` pipeline and the set ```dbPath``` parameter.

* For NCBI BLAST+: ```blastDbPath = "/path/to/db"``` and ```diamond = "false"```. It looks for formatted database files (normally named ``db.p*`` for protein type based ones), otherwise it will try to format FASTA file with that name
* For DIAMOND: ```blastDbPath = "/path/to/db"``` and ```diamond = "true"```. It looks for a single formatted database file (normally named ``db.dmnd``), otherwise it will try to format the FASTA file with that name (gzip compressed files accepted)

### Retrieval of GO terms from BLAST results

Retrieval of GO terms from BLAST results can be performed either from [BLAST2GO](https://www.blast2go.com/) results or from other methods as far as a BLAST2GO-compatible output format is provided.

In any case, we are also providing a web API for retrieving protein-GO mapping from [UniProt GOA](https://www.ebi.ac.uk/GOA) and other resources. More details for [for setting an own instance here](https://github.com/toniher/gogoAPI).

When using the second option, you can tune it with the parameters below:

```
  // Instance from where to retrieve GO mappings
  gogourl = "http://myinstance.example.com/api"
  // Maximum number of hits to consider (up to 30 by default))
  gogohits = 30
  // Modes of retrieval from BLAST matches
  //  * Common: Only GO entries appearing in all matches
  //  * Most: Only GO entries appearing in more than half of matches
  //  * All: All GO entries appearing in all matches
  blastAnnotMode = "common"
```

**IMPORTANT: This step requires so far network connection to the defined instance.**

### Interproscan

[Interproscan](https://www.ebi.ac.uk/interpro/search/sequence/) step launches several computing-intensive application within the same process, so care must be taken to assign enough resources in ```nextflow.config``` **ipscan** section.

It is **very important** to ensure that used Interproscan data directory matches the version of the used software. More details can be found at ```containers/interproscan``` directory.

Below the Interproscan parameters that can be tuned:
```
// Interproscan Version
iprscanVersion = "5.52-86.0"
// Defined Interproscan Data directory. It will override version parameter above.
// ipscandata = "/nfs/db/iprscan/5.52-86.0"
// Directory where to store intermediary Interproscan files (ensure there is enough space)
ipscantmp = "${baseDir}/tmp/"
```

### KEGG orthology groups
Predictions of the KEGG orthology groups (KO) can be obtained outside of the pipeline, i.e. via [KAAS server](http://www.genome.jp/tools/kaas/) or using a previously set-up version of [KofamKOALA](https://www.genome.jp/tools/kofamkoala/).

For KofamKOLA, adjust the parameters below to match the location in your system (ftp://ftp.genome.jp/pub/db/kofam/)

```
  koVersion = "2021-05-02"
  kolist = "/nfs/db/kegg/2021-05-02/ko_list"
  koprofiles = "/nfs/db/kegg/2021-05-02/profiles"
  koentries = "/nfs/db/kegg/2021-05-02/ko_store"
```

If ```kolist```, ```koprofiles``` are either not set or commented, ```koVersion``` will be used for completing their paths if ```dbPath``` (used in ```download.nf``` pipeline) is set.

In the parameters above, ```koentries``` refers to a directory containing KO entries text files that can be downloaded in advance (check ***Dataset resources*** section above). Otherwise a process will take care of retrieving them.

**Note**: when using KAAS, for the downstream processing of the KO file it is very important to store information about species used for predictions. Species are encoded in three letters abbreviations, and the list can be copied from the 'Selected organisms' field in the kaas_main form.

### Skipping some analyses

Future versions of this pipeline might allow to control in more detail which applications to run. For now, it is possible to skip some of them: *cdSearch* (hit and features retrieval), *signalP* and *targetP*. For the first case, since it is a web process, it can be time-consuming in some HPC setups. For the last two cases, since [preparing a container with privative software]((https://github.com/biocorecrg/sigtarp_docker)) can be troublesome or problematic, it can also be skipped. It is worth noting that some CD-Search data is actually available in InterPro.


For skipping these applications, the following lines can be added in the configuration file:

```
  skip_cdSearch = true
  skip_sigtarp  = true
```

In the provided example ```params.config``` file we keep these two lines uncommented.


## Result files

Below you can check all the possibly available files in results directory (defined with ```resultPath``` parameter) at the end of the pipeline execution. Some files may not be there if certain options are switched (e.g., if GFF cleaning is skipped with ```gffclean = "false"```).

* **«myorg».gff**: final outcome GFF that adds retrieved annotation information to the provided GFF. Filename matches the ```dbname``` parameter
* **annot.gff**: input GFF file after being cleaned at the beginning of the pipeline and used in downstream processes
* **annot.gff.clean.txt**: GFF cleaning log information
* **annot.gff.stats.txt**: GFF input file statistics
* **annotatedVsnot.png**: summary chart with protein length distribution and annotation coverage
* **go_terms_byGene.tsv**: TSV file containing a list of genes, and all the GO codes assigned to the proteins associated to that gene and the different methods (e.g., KEGG)
* **go_terms.tsv**: TSV file containing a list of proteins with their assigned GO codes with the used methods
* **interProScan.res.tsv**: TSV file with all protein domain and signature matches using InterproScan
* **protein_definition.tsv**: TSV file with assigned protein definition and the method uses (e.g., using BLAST matches)
* **signalP.res.tsv**: TSV file with all SignalP predictions
* **targetP.res.tsv**: TSV file with all TargetP predictions
* **total_stats.txt**: Annotation coverage provided at the end of the pipeline execution


## Running in MySQL mode

Running in MySQL mode improves the speed of the pipeline, but some care must be taken for including connection details in the configuration.

The relevant paremetres below:

```  
    // Database engine. Specify MySQL (otherwise 'SQLite' will be used)
    dbEngine = "MySQL"
    // Database name. If it does not exist, if the user has enough permissions it will be created
    dbname = "Pvulgaris"
    // Database user name
    dbuser = "test"
    // Database user password
    dbpass = "test"
    // Port of the MySQL engine (3306 default)
    dbport = 12345
    // The host where the MySQL engine is located. Skip it if using the wrapper below
    dbhost = 0.0.0.0
    // If using the wrapper below, where MySQL data will be stored
    mysqldata = "${baseDir}/mysql/"
    // If using the wrapper below, where MySQL instance logs will be stored
    mysqllog = "${baseDir}/tmp/"
    // If using the wrapper below, which Singularity/Docker image will be used
    mysqlimg = "https://biocore.crg.eu/singularity/mariadb-10.3.sif"
```

**Note**: when running a different analysis, take care to use a different ```dbname``` for avoiding unexpected problems.  

### Execution without an ad-hoc database

We offer a convenience wrapper script for running the pipeline in MySQL mode either in SGE-compatible clusters or in local without having to set up any MySQL server and database before thanks to Singularity.

    nohup perl run_pipeline_mysql.pl -conf ./params.config  &> log.mysql &

It is also possible to pass additional Nextflow parameters

    nohup perl run_pipeline_mysql.pl -params "-with-dag -with-report -with-timeline" -conf ./params.config  &> log.mysql &

The Singularity recipe for the database container image is the ```Singularity.mysql``` file in the root of the repository and can be generated as shown below:

```
  sudo singularity build mariadb-10.3.sif Singularity.mysql
```

#### Inspection of MySQL database

If run without an ad-hoc database, this is convenient for checking results database once analyses are finished. NO further analyses are run.

	nohup perl run_pipeline_mysql.pl -mysqlonly -conf ./params.config &> log.mysql.only &


for further options or details, run:

    perl run_pipeline_mysql.pl -h


## Citation

Vlasova, A.; Hermoso Pulido, T.; Camara, F.; Ponomarenko, J.; Guigó, R. FA-nf: A Functional Annotation Pipeline for Proteins from Non-Model Organisms Implemented in Nextflow. *Genes* **2021**, 12, 1645. https://doi.org/10.3390/genes12101645

```
@Article{genes12101645,
AUTHOR = {Vlasova, Anna and Hermoso Pulido, Toni and Camara, Francisco and Ponomarenko, Julia and Guigó, Roderic},
TITLE = {FA-nf: A Functional Annotation Pipeline for Proteins from Non-Model Organisms Implemented in Nextflow},
JOURNAL = {Genes},
VOLUME = {12},
YEAR = {2021},
NUMBER = {10},
ARTICLE-NUMBER = {1645},
URL = {https://www.mdpi.com/2073-4425/12/10/1645},
ISSN = {2073-4425},
ABSTRACT = {Functional annotation allows adding biologically relevant information to predicted features in genomic sequences, and it is, therefore, an important procedure of any de novo genome sequencing project. It is also useful for proofreading and improving gene structural annotation. Here, we introduce FA-nf, a pipeline implemented in Nextflow, a versatile computational workflow management engine. The pipeline integrates different annotation approaches, such as NCBI BLAST+, DIAMOND, InterProScan, and KEGG. It starts from a protein sequence FASTA file and, optionally, a structural annotation file in GFF format, and produces several files, such as GO assignments, output summaries of the abovementioned programs and final annotation reports. The pipeline can be broken easily into smaller processes for the purpose of parallelization and easily deployed in a Linux computational environment, thanks to software containerization, thus helping to ensure full reproducibility.},
DOI = {10.3390/genes12101645}
}
```

## Troubleshooting

**At the beginning of the pipeline execution, I get an error message such as ```FATAL:   While making image from oci registry: while building SIF from layers: conveyor failed to get: no descriptor found for reference``` or any other mentioning OCI, SIF or Singularity.**

*Ensure you have an up-to-date version of Singularity. Otherwise you may need to clean some Singularity directories, the singularity one (where pipeline images are stored) in FA-nf base directory and ```.singularity``` in your ```$HOME``` directory.*


**Just after starting the pipeline, it stops and I get a message such as ```Something went wrong. No supported configuration file syntax found at /your/path/lib/site_perl/5.26.2/Config/Simple.pm line 184, <FH> line 23.```**

*Check line **23** (or the number you have) of your params.config if you have any syntax error (e.g., new line, additional quote character, etc.)*


**Despite it ran successfully, the pipeline did not process the whole dataset but just a small part of it**

*You may have run it in debug mode. Check your params file and change it to ```debug = 'false'```*

**After several retries, a process stops and the pipeline finishes unsucessfully**

*You may need to assign more time, CPU or memory to the involved process from ```nextflow.config``` file. If it keeps failing you may need to check input files (e.g., there may be sequences of anomalous length). Otherwise, submit an issue in this Github repo detailing your problem.*

**When using MySQL database mode with Singularity wrapper, it does not start and it complains it is locked**

*Ensure no Singularity process is running on the contents of the selected MySQL directory. If it is not the case and it is still failing, copy the contents in another directory and run it from there instead*

**My HPC infrastructure cannot access the Internet. Can I use the pipeline?**

*Yes, as far as you skip CD-Search analyses (```skip_cdSearch = true```), you can use it by pre-downloading container images first (assuming Singularity) and replacing container values in ```nextflow.config``` for their path in your filesystem. You can download singularity images for later placing them in your filesystem with a command like this: ```singularity pull kofamscan-1.2.0.sif docker://quay.io/biocontainers/kofamscan:1.2.0--0```.*
