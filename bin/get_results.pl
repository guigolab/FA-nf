#!/usr/bin/perl -w
=head1 NAME

 get_results.pl

=head1 SYNOPSIS

 perl get_results.pl [-conf configuration file] [-h help] [-l list with selected ids]

=head1 DESCRIPTION

Utility to get summary information about annotated and not annotated proteins, as well as some summary plots (via R)

Typical usage is as follows:

  % perl get_results.pl -conf main_configuration.ini 

=head2 Options

Script to extract basic information about annotated and not annotated proteins

 Usage:   perl get_results.pl <options>
 Options  -conf      : Configuration file. [Mandatory]
          -list      : File with selected protein IDs - script will process only those seqences          
          -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file : 
             Database name and path;
             Result folder name;
             

=head1 AUTHORS

Vlasova Anna: vlasova dot av A gmail dot com

=cut


use strict;
use warnings;
use FindBin qw($RealBin);
FindBin::again();
use lib "$RealBin/lib/";
use Getopt::Long;
use Pod::Usage;
use FunctionalAnnotation::DB;
use FunctionalAnnotation::sqlLiteDB;
use FunctionalAnnotation::uploadData;
use FunctionalAnnotation::getResults;
use Data::Dumper;
use Config::Simple;

my ( $show_help,$confFile, $listFile);

&GetOptions(    	
                        'conf=s'=>\$confFile, 
                        'list=s'=>\$listFile, 
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if(!defined $confFile)
{ die("Please specify configuration file!\nLaunch 'perl get_results.pl -h' to see parameters description\n ");}

#read configuration file
my $cfg = new Config::Simple($confFile);
#put config parameters into %config                                             
my %config = $cfg->vars();

#my %conf =  %::conf;
my $debug = $config{'debug'};
my $update=0;

#connect to mysqlDB
if(!defined $config{'dbEngine'}){$config{'dbEngine'} = 'mysql';}
my $dbh;
#connect to the DB
if($config{'dbEngine'} eq 'mysql')
{ $dbh= FunctionalAnnotation::DB->new('mysql',$config{'dbname'},$config{'dbhost'},$config{'dbuser'},$config{'dbpass'},$config{'dbport'});}
else
{
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= FunctionalAnnotation::DB->new('sqlite',$dbName);
}

#$dbh->do('SET SESSION group_concat_max_len = 320000');
#my $sth = $dbh->do('SET @@group_concat_max_len = 320000');

if(! defined $config{'results_dir'} )
{$config{'results_dir'} = 'results';}

my $outputFolder=$config{'resultPath'}.$config{'results_dir'};
system("mkdir $outputFolder") if (!-d $outputFolder);

my @listIds=();
#create a list with protein ids, if ones is setted up
if(defined $listFile) 
 {  @listIds=&getSelectedIds($listFile);   }

#First - need to fulfill go term information if there are go terms without name and term_type fields fulfilled. To fulfill GO term information
#I will use file gene_ontology_ext.obo in bin/ folder. This file is taken from Gene Ontology consortium http://www.geneontology.org/ontology/gene_ontology.obo
 my $ontologyFile=$RealBin.'/dataset/gene_ontology_ext.obo';

&uploadGOInfo($dbh, $ontologyFile);

#Then need to update annotation status to 'annotated' for those proteins with hits in any source of evidence (including blast). 
&updateAnnotationStatus($dbh);

#get summary information
my $summaryFile = $outputFolder.'/'.'total_stats.txt';
&printSummaryInfo(\@listIds, $dbh, $summaryFile);

#print protein definition
my $definitionFile = $outputFolder.'/'.'protein_definition.txt';
&printDefinitionInfo(\@listIds, $dbh, $definitionFile);


#get GO terms info
my $goFile=$outputFolder .'/'.'go_terms.txt';
&printGoTerms(\@listIds, $goFile, $dbh, 'protein');
my $goFile2=$outputFolder .'/'.'go_terms_byGene.txt';
&printGoTerms(\@listIds, $goFile, $dbh, 'gene');


#make annotated vs not annotated plot
my $plotFile = $outputFolder .'/'.'annotatedVsnot.png';
my $tmpFolder = $config{'resultPath'};
system("mkdir $tmpFolder") if (!-d $tmpFolder);
&makeAnnotatedVsNotAnnotatedPlot(\@listIds, $plotFile, $dbh,$tmpFolder,$RealBin,$config{'specie_name'});
