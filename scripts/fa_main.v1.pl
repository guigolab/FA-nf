#!/usr/bin/env perl

use warnings;

=head1 NAME

annotation_main.pl

=head1 SYNOPSIS

  perl annotation_main  <command>

This is main script for functional annotation pipeline, that runs different annotation steps by specified command. Each function has its own parameteres

=head1 DESCRIPTION

Usage:  annotation_main.pl <command> [options]
Commands:
          init
          upload_kegg
          program
          get_results

Dependency:
 DBI;
 Getopt::Long;
 Data::Dumper;
 Bio::SeqIO;
 Bio::SearchIO;
 Config::Simple;

=head2 Options


=head1 AUTHOR

 Anna Vlasova <anna.vlasova@crg.es>

=cut

use strict;
use DBI;

use FindBin qw($RealBin);
use lib "$RealBin/lib/";
use Getopt::Long;
use Data::Dumper;
use Config::Simple;
use FunctionalAnnotation::DB;
use FunctionalAnnotation::sqlDB;
use FunctionalAnnotation::uploadData;
use FunctionalAnnotation::getResults;
use IO::Handle;
use File::Basename;
use Cwd;

&usage if (@ARGV < 1);

my $command = shift(@ARGV);
my %func = (init=>\&loadDataToDB, upload_kegg_KAAS=>\&uploadKEGG, program=>\&launchProgram, get_results=>\&getResults);

if (!defined($func{$command}))
{
 print("Unknown command \"$command\".\n") ;
 &usage();
}

&{$func{$command}};
exit(0);

#
# usage
#
sub usage
{
 print <<EOF;
Usage    : fnan_main.pl <command_name>
Commands : init               : This is the first step of the pipeline - it creates DB and fulfill it with initial information about sequences.

           program            : Run on of the specified program: Blast, Blast2Go, SignalP, InterProScan. This module can be used also to upload pre-calculated results into DB

           upload_kegg_KAAS   : Upload information from KEGG databases using previously obtained KO annotation through KAAS server

           get_results        : This step will extract all annotation information from the DB and create summary file.

Note    : All pipeline scripts uses its own parameters and configuration file.
          Pipeline uses external software: SQLite [ Mandatory ]
                                           R      [ Mandatory for creating resulting plots]
          Pipeline may use also local installations of:
                                           BLAST
                                           Blast2Go
                                           InterProScan
                                           SignalP

EOF
 exit(0);
}

#################################################################
################ Main subroutines ###############################
#################################################################
#
# Name : loadDataToDB == init
# Description: This subroutine upload initital data into DB - sequences and their annotation
# Requirements : DBI
# Variables :
#     fastaFile  -  sequence file
#     gffFile -  annotation file
#
# Last edited: 18/11/2015 -- added description of 'u' option and -new version from the file ~/Projects/annotation/functional_annotation/fnan_main.v1.pl
# because there were two conflicting versions developed at the same time.
#11/08/2014
#
# Author : Vlasova AV

sub loadDataToDB
{
 my ($updateFlag, $newVersion, $listIds,$confFile,$comment,$show_help,$o_annt_file,$o_fasta_file,$rm_version);

 ($updateFlag, $newVersion) =(0,0);

 GetOptions(
           "u=s"	=>\$updateFlag,
           "l=s"=>\$listIds,
           "new_version=s" =>\$newVersion,
           "conf=s"=>\$confFile,
           "comm=s"=>\$comment,
           "gff=s"=>\$o_annt_file,
           "fasta=s"=>\$o_fasta_file,
           "help|h" => \$show_help,
           "rmversion" => \$rm_version
           );

if(!defined $confFile || $show_help)
{
die(qq/
 Usage:   fa_main.pl init  [options]
 Options
       -h || help 		 : This message
       -conf    		 : Configuration file; by default 'main_configuration.ini' in the current folder
       -comm    		 : Comment, description. This record will be stored in the protein.comment field
       -u     		    	 : update flag. if set up to 1 then data in DB is updated; Default is 0
       -new_version [0\/1]	 : new version flag; Set up to 1 means that this is a new version [did not checked this option]
				   of the existing annotation, and the old one is present in DB, this flag should go
				   with -u flag specified. Default is 0

 Note: Don't forget to specify mandatory options in the main configuration file :
             File with the protein sequences in fasta format;
             File with the corresponding annotation in gff3 or gtf formats;
             Database name and path;

       All files must be specified with the full paths!

\n/)};

 #first - check that DB exists and if not than create new DB with all required tables.

 #redirect standart output and standart error into log files
 my $cfg = new Config::Simple($confFile);
 #put config parameters into %config
 my %config = $cfg->vars();
 my $logFile = $config{'stdoutLog'};
 my $errFile = $config{'stderrLog'};

 &setLogDirs( $config{'stdoutLog'}, $config{'stderrLog'} );
 #open OUTPUT, '>>', $logFile or die $!;
 #open ERROR,  '>>', $errFile  or die $!;
 #STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
 #STDERR->fdopen( \*ERROR,  'w' ) or die $!;

 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
 $year += 1900;
 my $date = "$year/$mon/$mday $hour:$min:$sec";
if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{
 print '#' x35 ."\n";
 print '#' x5 . 'Init, '.$date.' '.'#' x5 ."\n";
 print '#' x35 ."\n";
 print "Check DB presence...\n";
}

 &createSQLDB($confFile);

if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{
  print "Data uploading..\n";
}

 my $commandString='';
 $commandString =" -u $updateFlag ";

 if(defined $confFile)
  {$commandString .="-conf $confFile ";}

 if(defined $comment)
  {$commandString .="-comm $comment ";}

 	# Override if specified explicitly
	if (defined $o_annt_file ) {
		$commandString .="-gff $o_annt_file ";
	}

	if (defined $o_fasta_file ) {
		$commandString .="-fasta $o_fasta_file ";
 }

 if (defined $rm_version ) {
   $commandString .="-rmversion ";
 }


 if($newVersion =='1')
  {
##4/12/2013 I did not check this option for the moment!!
    my $fastaFile=$config{'proteinFile'};
    my $outFile  = $fastaFile.'.stat';
    $commandString = "perl $RealBin/compareNewAnnotation.pl -o $outFile " .$commandString;
  }
 else
 {
  $commandString = "perl $RealBin/import_data.pl ".$commandString;
 }

if($config{'loglevel'} eq 'debug')
{
  my $cwd=getcwd();
  print "Folder: $cwd\n";
  print "$commandString\n";
}

 system($commandString)==0 or die("Error running system command: < $commandString >\n $!");

}

#
# Name : uploadKegg
# Description: This subroutine upload infromation from KEGG DB using BioMart modules and list of KO groups
# Requirements : DBI, BioMart (for taxonomy)
# Variables :
# Note:
#    User needs to analyse its proteins in the KAAS server first, and then use result list of KO elements as input.
#
# Last edited: 11/08/2014
# Author : Vlasova AV

sub uploadKEGG
{
 my ($do_update, $input, $kegg_release, $show_help,$configurationFile);


 GetOptions(	'update|u=s'	=> \$do_update,
                'input|i=s'     => \$input,
                'rel=s'       => \$kegg_release,
                'conf=s'=>\$configurationFile,
		'help|h'        => \$show_help
             );

 if((!defined $input) || (!defined $kegg_release) || ($show_help))
{
die(qq/
 upload_kegg_KAAS           : Upload information from KEGG databases using previously obtained KO annotation
                              through KAAS server

 Usage:   fa_main.pl upload_kegg  [options]
 Options  -input : Input file, obtained from KAAS server  [Mandatory]
                  (http:\/\/www.genome.jp\/tools\/kaas\/)
          -rel   : KEGG DB release [Mandatory]
                  (http:\/\/www.kegg.jp\/kegg\/docs\/relnote.html)
          -update: Flag that indicates to re-write existing record in the DB, or not. Default value is 0.
          -conf  : configuration file.

Note: Don't forget to specify mandatory options in the main configuration file :
             Database name and path;
             Species 3 letters codes used for annotation via KAAS;
\n/)};

 #redirect standart output and standart error into log files

 my $cfg = new Config::Simple($configurationFile);
 #put config parameters into %config
 my %config = $cfg->vars();

 my $logFile = $config{'stdoutLog'};
 my $errFile = $config{'stderrLog'};

 &setLogDirs( $config{'stdoutLog'}, $config{'stderrLog'} );


 open OUTPUT, '>>', $logFile or die $!;
 open ERROR,  '>>', $errFile  or die $!;
 STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
 STDERR->fdopen( \*ERROR,  'w' ) or die $!;

 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
 $year += 1900;
 my $date = "$year/$mon/$mday $hour:$min:$sec";

if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{
 print '#' x40 ."\n";
 print '#' x5 . 'Upload KEGG, '.$date.' '.'#' x5 ."\n";
 print '#' x40 ."\n";
}

 my $commandString = "perl $RealBin/load_kegg_KAAS.pl -input $input -rel $kegg_release -conf $configurationFile";

 if(! defined $configurationFile)
  {die("Please specify correct configuration file!\n Launch 'fa_main upload_kegg -h' to see parameters description\n ");}

if(! defined $kegg_release)
  {die("Please specify release of the KEGG DB!\n Launch 'fa_main upload_kegg -h' to see parameters description\n ");}

if(($config{'loglevel'} eq 'debug'))
{
  my $cwd=getcwd();
  print "Folder: $cwd\n";
  print "$commandString\n";
}

 system($commandString)==0 or die("Error running system command: <$commandString>\n");

}


#
# Name : launchProgram
# Description: This subroutine runs local version of specified programs and upload its results into DB
#            Or, alternatively, it can be used to upload pre-calculated results into DB
# Requirements : DBI
# Variables :
# Note:
#   For majority of the programs this step is very time consuming!
#
# Last edited: 13/08/2014
# Author : Vlasova AV


sub launchProgram
{
 my ($soft, $mode,$do_update, $input, $list, $show_help,$confFile );

 my $allFlag=0;
 GetOptions(    'help|h'        => \$show_help,
                'conf=s'=>\$confFile,
                'prog|p=s'=>\$soft,
                'mode=s'=>\$mode,
                'update|u=i'=>\$do_update,
                'input|i=s'=>\$input,
                'list|l=s'=>\$list,
             );

 if($show_help)
{
die(qq/
 program   : Launch local installation of specified program and upload its results into DB, or just upload pre-calculated results into DB

 Usage:   fa_main.pl program  [options]
 Options  -prog | -p     : Program name. In current version we're support blast, blast2go, interpro, signalp, CDsearch [Mandatory]
          -mode  	 : Running mode [run\/upload] [Mandatory]
          -conf          : Configuration file. [Mandatory]
          -input | -i    : input file with pre-calculated results. For uploading mode only
          -list | -l     : File with selected protein IDs - script will process only those seqences
          -update | -u 	 : Flag [0\/1] indicating whether user wants to update records in DB, i.e. rewrite an existing record with new data. Not recommended and not really tested in current version.
                           By default it is 0
           -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file :
             Database name and path;
             Software path and parameters;
             Additional important parameteres for software, such as Blast DB paths;
             Chunk size;

Input results files are acepted in following formats:
 Blast         - in classical NCBI-like, xml and tabular separated (-m 8).
                 Important! Its require xml-formatted blast result file in order to use it as input to blast2go local installation.
 InterProScan - in tsv format
 Blast2Go     - in 3 column tabular separated format.
 SignalP      - in its default tsv format
 CDsearch     - in tabular separated  hitsFull results [ uploading only ]

In running mode this is very time consuming step!

\n/)};

if(!defined $soft)
 {die("Please specify correct program to execute!\nLaunch 'fa_main program -h' to see parameters description\n ");}

if(!defined $mode)
 {die("Please specify running mode!\nLaunch 'fa_main program -h' to see parameters description\n ");}

if(!defined $confFile)
 {die("Please specify configuration file!\nLaunch 'fa_main program -h' to see parameters description\n ");}


#redirect standart output and standart error into log files
 my $cfg = new Config::Simple($confFile);
 #put config parameters into %config
 my %config = $cfg->vars();
 my $logFile = $config{'stdoutLog'};
 my $errFile = $config{'stderrLog'};

 &setLogDirs( $config{'stdoutLog'}, $config{'stderrLog'} );
 open OUTPUT, '>>', $logFile or die $!;
 open ERROR,  '>>', $errFile  or die $!;
 STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
 STDERR->fdopen( \*ERROR,  'w' ) or die $!;

 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
 $year += 1900;
 my $date = "$year/$mon/$mday $hour:$min:$sec";

if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{
 print '#' x40 ."\n";
 print '#' x5 . "Program:$soft, ".$date.' '.'#' x5 ."\n";
 print '#' x40 ."\n";
}

 my $commandString="";

if($soft eq 'blast')
 {$commandString .="perl $RealBin/bin/run_blast.pl -mode $mode ";}
elsif($soft eq 'blast2go')
 {$commandString .="perl $RealBin/bin/run_blast2go.pl -mode $mode ";}
elsif($soft eq 'interpro')
 {$commandString .="perl $RealBin/bin/run_interpro.pl -mode $mode ";}
elsif($soft eq 'signalp')
 {$commandString .="perl $RealBin/bin/run_signalp.pl -mode $mode ";}
elsif($soft eq 'CDsearch')
 {$commandString .="perl $RealBin/bin/run_CDsearch.pl -mode $mode ";}

 $commandString .="-conf $confFile ";

if($mode eq 'upload')
{
 if(! defined $input)
  {die("Please specify input file with results!\nLaunch 'fa_main program -h' to see parameters description\n ");}
 else
 {$commandString .="-i $input ";}
}

if(defined $list)
 {$commandString = "-l $list ";}

if(defined $do_update)
 {$commandString = "-u $do_update ";}

if(($config{'loglevel'} eq 'debug'))
{
  my $cwd=getcwd();
  print "Folder: $cwd\n";
  print "$commandString\n";
}
 system($commandString)==0 or die("Error running system command: <$commandString>\n$!\n");

}



#
# Name : getResults
# Description: This subroutine get information from all fulfilled table for the current protein and return to the user number of gff files and charts
# Requirements : DBI, R
# Variables : configuration file
# Note:
#   Creates banch of files in resulting folder
#
# Last edited:
# Author : Vlasova AV

sub getResults
{
 my ($list, $show_help,$confFile );

 my $allFlag=0;
 GetOptions(    'help|h'        => \$show_help,
                'conf=s'=>\$confFile,
                'list|l=s'=>\$list,
             );

 if($show_help)
{
die(qq/
 get_results   : This part extract all available information from DB (from collected sources) and create banch of result files in result folder.


 Usage:   fa_main.pl get_results  [options]
 Options  -conf      : Configuration file. [Mandatory]
          -list | -l     : File with selected protein IDs - script will process only those seqences
          -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file :
             Database name and path;
             Results folder name and path

Result folder should contain following files:
  summary.txt		  Functional annotation summary - number of input proteins, number of proteins with annotaion features and so on.
  summary.gff3 	          Resulting annotation in gff3 format
  prot_definition.txt     Possible protein definition given by blast2go or kegg ortholog
  go_terms.txt 		  GO terms associated with the sequences
  ann_vs_notAnn.pdf       Plot of length distribution for annotated and not annotated proteins (requires R )

\n/)};


if(!defined $confFile)
 {die("Please specify configuration file!\nLaunch 'fa_main program -h' to see parameters description\n ");}

 #redirect standart output and standart error into log files
 my $cfg = new Config::Simple($confFile);
 #put config parameters into %config
 my %config = $cfg->vars();
 my $logFile = $config{'stdoutLog'};
 my $errFile = $config{'stderrLog'};

 &setLogDirs( $config{'stdoutLog'}, $config{'stderrLog'} );
 open OUTPUT, '>>', $logFile or die $!;
 open ERROR,  '>>', $errFile  or die $!;
 STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
 STDERR->fdopen( \*ERROR,  'w' ) or die $!;

 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
 $year += 1900;
 my $date = "$year/$mon/$mday $hour:$min:$sec";

if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{
 print '#' x40 ."\n";
 print '#' x5 . 'Get results, '.$date.' '.'#' x5 ."\n";
 print '#' x40 ."\n";
}

 my $commandString="";

#create all result files, but without gff3 -fast step
 $commandString .="perl $RealBin/get_results.pl -conf $confFile ";

if(defined $list)
 {$commandString = "-l $list ";}

 print "$commandString\n";
 system($commandString)==0 or die("Error running system command: <$commandString>\n$!\n");

#create gff3 file - this is a longest step

 $commandString .="perl $RealBin/get_gff3.pl -conf $confFile ";

if(defined $list)
 {$commandString = "-l $list ";}

if(($config{'loglevel'} eq 'debug'))
{
  my $cwd=getcwd();
  print "Folder: $cwd\n";
  print "$commandString\n";
}

 system($commandString)==0 or die("Error running system command: <$commandString>\n$!\n");

}
