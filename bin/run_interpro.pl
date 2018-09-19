#!/usr/bin/env perl

use warnings;

=head1 NAME

 run_interpro.pl

=head1 SYNOPSIS

 perl run_interpro.pl [-mode run/upload] [-conf configuration file] [-h help]

=head1 DESCRIPTION

Utility to launch local installation of InterPro search and populate tables

Typical usage is as follows:

  % perl run_interpro.pl -conf main_configuration.ini -mode run

=head2 Options

Run interpro analysis; this program can be used to upload pre-calculated results into DB

 Usage:   fa_main.pl program -p interpro  [options]
 Options  -mode      : Running mode [run\/upload] [Mandatory]
          -input     : input folder with resulting files. For uploading mode only
          -list      : File with selected protein IDs - script will process only those seqences
          -conf      : Configuration file. [Mandatory]
          -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file : 
             Database name and path;
             Interproscan software path and parameters;
             Chunk size;    

In running mode this is very time consuming step!

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
use Bio::SeqIO;
use Data::Dumper;
use Config::Simple;

my ( $show_help, $input,$confFile, $mode, $listFile);

&GetOptions(    	
			'input|i=s'     => \$input,
                        'conf=s'=>\$confFile, 
                        'mode=s'=>\$mode, 
                        'list=s'=>\$listFile, 
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if(!defined $confFile)
{ die("Please specify configuration file!\nLaunch 'perl run_interpro.pl -h' to see parameters description\n ");}

if(!defined $mode)
{ die("Please specify running mode: run/upload only!\nLaunch 'perl run_interpro.pl -h' to see parameters description\n ");}


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


my %blastData=();

if($mode eq 'run')
{
 my @selectedIds=();
 if(defined $listFile)
  {@selectedIds=&getSelectedIds($listFile);}

 my @fileList = &prepareInputFiles($dbh, \%config, \@selectedIds);
 
 my $interProPath = $config{'iprscan_path'};
 my $interProParam = $config{'iprscan_params'};
 my $commandString = '';
 foreach my $fileItem (@fileList)
  {
     $commandString = "$interProPath $interProParam -i $fileItem -o $fileItem.iprout";
     print "$commandString\n";
     #die();
#     system($commandString)==0 or die("Error running system command: <$commandString>\n");
     my %ipscanHash = &parseInterProTSV("$fileItem.iprout");
     my $goData = &uploadInterProResults($dbh, \%ipscanHash,$config{'dbEngine'});
     &uploadGoAnnotation($goData, $dbh,$update,'IPSCN',$config{'dbEngine'});
  }
}
elsif($mode eq 'upload')
{
 if(!defined $input)
 {die("Please specify input file with interpro results in tsv format!\nLaunch 'perl run_interpro.pl -h' to see parameters description\n ");}
  my %ipscanHash = &parseInterProTSV($input);
   #print Dumper(%ipscanHash);
  my $goData = &uploadInterProResults($dbh, \%ipscanHash,$config{'dbEngine'});
  #print Dumper($goData);

  &uploadGoAnnotation($goData, $dbh,$update,'IPSCN',$config{'dbEngine'});

}
else
{die("Please specify correct running mode: run/upload only!\nLaunch 'perl run_interpro.pl -h' to see parameters description\n ");}

