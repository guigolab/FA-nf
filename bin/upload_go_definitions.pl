#!/usr/bin/env perl

use warnings;

=head1 NAME

 upload_go_definitions.pl

=head1 SYNOPSIS

 perl upload_go_definitions.pl [-input] [-conf configuration file] [-mode go/def] [-param param_string] [-h help]

=head1 DESCRIPTION

Utility to upload GO terms or protein definitions obtained from different programs into annotation DB file

Typical usage is as follows:

  % perl upload_go_definitions.pl -conf main_configuration.ini -i file.tsv -mode go -param 'BLAST2GO'

=head2 OPTIONS


 Usage:   upload_go_definitions.pl  [options]
 Options  -mode      : Type of data to upload [go\/def] [Default : go]
          -input     : input file. [Mandatory]
          -conf      : Configuration file. [Mandatory]
          -param     : param string that will be attached to definition/GO annotation source
          -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file : 
             Database name and path;
             

==head2 INPUT DATA FORMAT
Input file with GO terms annotations or protein putative names, definitions, should be two-column tabular separated file with first column as a protein names and the second column - annotation

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
use FunctionalAnnotation::uploadData ;
use Bio::SeqIO;
use Data::Dumper;
use Config::Simple;
use File::Basename;

my ( $show_help, $input,$confFile, $mode, $listFile, $param);

&GetOptions(    	
			'input|i=s'     => \$input,
                        'conf=s'=>\$confFile, 
                        'mode=s'=>\$mode, 
                        'param=s'=>\$param,
                        'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if(!defined $confFile)
{ die("Please specify configuration file!\nLaunch 'perl fa_blast2go.pl -h' to see parameters description\n ");}

if(! defined $input)
 {die("Please specify input file in tabular separated format!\n It should be two-columns formatted. First column - protein ID, second column - annotation information.\n");}

if(!defined $mode)
{ $mode= 'go';}


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

my %annotData = &parseAnnotation($input);
 
if( %annotData)
 {
 if($mode eq 'go')
 {
 #print Dumper(%annotData)."\n"; die;
   &uploadGoAnnotation(\%annotData, $dbh,$update,$param,$config{'dbEngine'});
 }
 elsif($mode eq 'def')
 {
   &updateProteinDefinition(\%annotData, $dbh,$update,$param,$config{'dbEngine'});
 }
 else
 {die("Please specify correct running mode: go/def only!\nLaunch 'upload_go_definitions.pl -h' to see parameters description\n ");}
}

