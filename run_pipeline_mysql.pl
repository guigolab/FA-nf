#!/usr/bin/env perl

use strict;

use Getopt::Long;
use Config::Simple;
use Data::Dumper;
use File::Temp qw/ :POSIX /;
use File::Path qw(make_path);

# Wrapper for running the pipeline in MySQL mode - Use with nohup and ideally save log

my ($confFile,$show_help,$mysqlimg);
my $nextflow = "nextflow";

my $mysqldata = $ENV{'HOME'}."/mysqldata";
my $mysqllog = $ENV{'HOME'}."/mysqllog";

GetOptions(
    "conf=s"=>\$confFile,
    "help|h" => \$show_help,
    "nextflow=s" => \$nextflow,
    "mysqldata=s" => \$mysqldata,
    "mysqllog=s" => \$mysqllog,
    "mysqlimg=s" => \$mysqlimg
);

if(!defined $confFile || !defined $mysqlimg || $show_help) 
{
die(qq/
 Usage:   run_pipeline_mysql.pl [options]
 Options 
       -h || help 		 : This message
       -conf    		 : Configuration file; by default 'main_configuration.ini' in the current folder
       -nextflow         : Nextflow path

\n/)};

if ( ! -d $mysqldata ) { make_path( $mysqldata ); }
if ( ! -d $mysqllog ) { make_path( $mysqllog ); }

my $tmpconf = tmpnam();
# As it is used in the pipeline, consider if migrating to Perl function
system( "grep -vP '[{}]' $confFile | sed 's/\\s\\=\\s/:/gi' > $tmpconf" );

# Parsing params.config (the same place as nexflow for sake of simplicity)
my $cfg = new Config::Simple($tmpconf);
#put config parameters into %config                                             
my %config = $cfg->vars();
print Dumper( \%config );

# If MySQL mode
if ( $config{"dbEngine"} eq 'mysql' ) {
    
    # Check all MySQL params are there
    
    if ( $config{"dbuser"} && $config{"dbpass"} && $config{"dbport"} ) {
        
        # Generate files
        # Mysqlconf
        my $cnfcontent = "[mysqld]\nbind-address=0.0.0.0\nport=".$config{"dbport"}."\n";
        open( CNF, ">$mysqllog/CNF" ); print CNF $cnfcontent; close( CNF );
        
        # Run MySQL qsub process. TODO: Allow more flexibility here
        system( "qsub run.mysql.qsub.sh $mysqlimg $mysqldata $mysqllog/CNF $mysqllog/IP $mysqllog/PROCESS ".$config{"dbuser"}." ".$config{"dbpass"}." ".$config{"dbport"});
        # Run nextflow
        # TODO: To reconsider way of checking
        while ( ! -d "$mysqldata/db" ) {
		sleep( 5 );
	}
        system( "$nextflow run pipeline.nf --config $confFile" );
        
    } else {
        
        exit 1;
    }

} else {

    # Else, SQLite mode
    # Run Nextflow pipeline
    system( "$nextflow run pipeline.nf --config $confFile" );

}
