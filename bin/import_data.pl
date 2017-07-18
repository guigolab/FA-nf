#!/usr/bin/perl -w

=head1 NAME

import_data.pl

=head1 SYNOPSIS
	
  perl import_data.pl [-conf configuration file] [-l list_with_ids] [-u update] [-h help]

Import data from fasta and gff files into main DB. This script could upload all data or by given list.
In case when user wants to upload just some of the proteins he could specify their ids in separate file, one per line.
Parameter update could have value 1 if user wants to update data or 0 if not. 

=head1 DESCRIPTION

Use this script to import data main DB database.

Typical usage is as follows:

  % perl import_data.pl -conf main_configuration.ini 

=head2 Options

The following options are accepted:

 -conf  Configuration file [mandatory]
 -help	This documentation.

=head1 AUTHOR

Anna Vlasova <anna.vlasova@crg.es>

=cut

use strict;
use FindBin qw($RealBin);
FindBin::again();
use lib "$RealBin/lib/";
use DBI;
use Getopt::Long;
use Data::Dumper;
use FunctionalAnnotation::DB;
use FunctionalAnnotation::sqlLiteDB;
use FunctionalAnnotation::uploadData;
use Config::Simple;

my $confFile = 'main_configuration.ini';


my $usage = "perl import_data.pl [-l listfile] [-u update] [-h help] [-conf configuration_file] [-comm comment_string]\n";
my ($annt_file, $show_help,$fasta_file, $list_file, $do_update,$comment);

&GetOptions(
    'l=s'	=>\$list_file,
    'update|u=s'	=> \$do_update,
    'help|h'        => \$show_help,
    'comm=s'=>\$comment,
    'conf=s'=>\$confFile,
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

die($usage) if (!$confFile);

print "Starting to upload data..Configuration file is $confFile\n";
#read configuration file
my $cfg = new Config::Simple($confFile);
#put config parameters into %config                                             
my %config = $cfg->vars();
#my %conf =  %::conf;
my $debug = $config{'debug'};
my $debugSQL = $config{'debugSQL'};

#check whether protein fa and annotation gff3 files exists
 $annt_file = $config{'gffFile'};
 $fasta_file = $config{'proteinFile'};

if(!-e $fasta_file)
 {die "The protein fasta file does not exists! There is nothing to work with!\n";}

if(!-e $annt_file)
 {print "The annotation gff3 file does not exists! Information in DB will be incomplete!\n";}

print "DBname $config{'dbname'}\n"; 

# Connect to the DB,depending on the engine 
if(! exists $config{'dbEngine'})
 {$config{'dbEngine'} = 'mysql';}
my $dbh;

if($config{'dbEngine'} eq 'mysql')
{ $dbh= FunctionalAnnotation::DB->new('mysql',$config{'dbname'},$config{'dbhost'},$config{'dbuser'},$config{'dbpass'},$config{'dbport'});}
else
{
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= FunctionalAnnotation::DB->new('sqlite',$dbName);
}

$do_update = 0 if (!defined $do_update);

#read list file, if ones is present
my %IdsList=();
if(defined $list_file )
 { %IdsList = &readListFile($list_file);}



#upload annotation data from gff file
if(! defined $annt_file || $annt_file eq ''){print STDOUT "The annotation file was not specified, skipped.\n";}
else
 { 
   print STDOUT "Upload annotation data from $annt_file\n";
   #my $checkResult = &checkGFFData($annt_file);
   my $checkResult = 1;
   if ($checkResult==1)
   {&uploadGFFData($annt_file, $dbh,\%IdsList, $do_update,'SQLite');}
  else
  { print STDOUT "Due to errors in GFF file, data will not be uploaded. Correct file first!\n"; 
    die;}
 }

print STDOUT "Upload sequences from $fasta_file\n";
#upload sequences from fasta file

if(! defined $fasta_file){print STDOUT "The fasta file was not specified, skipped.\n";}
else
 {&uploadFastaData($fasta_file, $dbh,\%IdsList,1,$comment,'SQLite');}


print "done.";
