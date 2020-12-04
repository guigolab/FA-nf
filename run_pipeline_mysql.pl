#!/usr/bin/env perl

use strict;

use Getopt::Long;
use Config::Simple;
use Data::Dumper;
use File::Temp qw/ :POSIX /;
use File::Path qw(make_path);
use Cwd qw(cwd);

# Wrapper for running the pipeline in MySQL mode - Use with nohup and ideally save log

my ($confFile,$show_help);
my $nextflow = "nextflow";
my $nfparams = ""; # By default no additional params

my $resume = 0;
my $mysqlonly = 0;
my $engine = "sge";

my $mysqldata = $ENV{'HOME'}."/mysqldata";
my $mysqllog = $ENV{'HOME'}."/mysqllog";

# Random
my @rchars = ("A".."Z", "a".."z");
my $random;
$random .= @rchars[rand @rchars] for 1..8;

# extra params for cluster queue
my $extra = "-j y -l virtual_free=2G,h_rt=172800 -N MYSQL_container -m be -cwd -V -q long-sl7";

GetOptions(
    "conf=s"=>\$confFile,
    "help|h" => \$show_help,
    "nextflow=s" => \$nextflow,
    "params=s" => \$nfparams,
    "extra=s" => \$extra,
    "resume|r" => \$resume,
    "mysqlonly|m" => \$mysqlonly,
    "engine=s" => \$engine
);

my $resumeStr = "";

if ( $resume ) {
    $resumeStr = "-resume";
}

if( !defined $confFile || $show_help ) {
  die(qq/
   Usage:   run_pipeline_mysql.pl [options]
   Options
         -h || help 		 : This message
         -conf    		 : Configuration file; by default 'main_configuration.ini' in the current folder
         -nextflow         : Nextflow path
         -params           : Parameters for Nextflow program
         -extra            : Extra parameters to be passed to the cluster queue
         -resume           : Resume the pipeline (it passes -resume argument to nextflow)
         -mysqlonly        : Lauch only MySQL server (as far as running in MySQL mode)
         -engine           : Engine to be used (so far 'sge' by default, otherwise local)
  \n/);
}

my $tmpconf = tmpnam();

my $pwd = cwd;

my $strFile="";
open( CONF, $confFile );

while ( <CONF> ) {

    if ( $_=~/\$\{baseDir\}/ ) {
        s/\$\{baseDir\}/$pwd/g;
    }

    if ( $_=~/\$baseDir/ ) {

        s/\$baseDir/$pwd/g;
    }

    if ($_=~/^\s*params\s*{\s*$/) {
        next;
    }

    if ($_=~/^\s*}\s*$/) {
        next;
    }

    $_=~s/\s*\=\s*/:/g;

    $strFile = $strFile. $_;
}

close( CONF );

open( TMPCONF, ">$tmpconf" );
print TMPCONF $strFile;
close( TMPCONF );

# Parsing params.config (the same place as nexflow for sake of simplicity)
my $cfg = new Config::Simple($tmpconf);
#put config parameters into %config
my %config = $cfg->vars();
print Dumper( \%config );

# If MySQL mode
if ( lc( $config{"dbEngine"} ) eq 'mysql' ) {

    # Check all MySQL params are there

    if ( $config{"dbuser"} && $config{"dbpass"} && $config{"dbport"} && $config{"mysqlimg"} ) {


        if ( $config{"mysqllog"} ) {
            $mysqllog = $config{"mysqllog"};
        }

        if ( $config{"mysqldata"} ) {
            $mysqldata = $config{"mysqldata"};
        }

        if ( ! -d $mysqldata ) { make_path( $mysqldata ); }
        if ( ! -d $mysqllog ) { make_path( $mysqllog ); }

        # Avoid show IP of previous process
        if ( -f "$mysqllog/DBHOST" ) {
            unlink "$mysqllog/DBHOST";
        }

        # Generate files
        # Mysqlconf
        my $cnfcontent = "[mysqld]\nbind-address=0.0.0.0\nport=".$config{"dbport"}."\n";
        open( CNF, ">$mysqllog/CNF" ); print CNF $cnfcontent; close( CNF );

        $extra = $extra. " -e $mysqllog/ERR -o $mysqllog/OUT ";

        if ( $engine eq 'sge' ) {
            $extra = "qsub ". $extra;
        } elsif ( $engine eq 'local' ) {
            $extra = "bash";
        } else {
            die( "Not supported engine!" );
        }

        # Run MySQL qsub process. TODO: Allow more flexibility here
        system( "$extra run.mysql.qsub.sh ".$config{"mysqlimg"}." $mysqldata $mysqllog/CNF $mysqllog/DBHOST $mysqllog/PROCESS ".$config{"dbuser"}." ".$config{"dbpass"}." ".$config{"dbport"}. " ". $random ." & " );

        # Run nextflow
        # TODO: To reconsider way of checking
        while ( ! -d "$mysqldata/db" ) {
            sleep( 5 );
        }

        if ( ! $mysqlonly ) {

            while ( ! -f "$mysqllog/PROCESS" ) {
                sleep( 5 );
            }

            my $myip=`cat "$mysqllog/DBHOST"`;
            print "DBHOST: ".$myip."\n";
           	print( "Run NEXTFLOW\n") ;
            system( "$nextflow run $nfparams -bg pipeline.nf $resumeStr --config $confFile" );
        } else {

            while ( ! -f "$mysqllog/DBHOST" ) {
                sleep( 5 );
            }

            my $myip=`cat "$mysqllog/DBHOST"`;
            print "DBHOST: ".$myip."\n";

        }
    } else {

        exit 1;
    }

} else {

    # Else, SQLite mode
    # Run Nextflow pipeline
    print( "Run NEXTFLOW\n") ;
    system( "$nextflow run $nfparams -bg pipeline.nf $resumeStr --config $confFile" );

}
