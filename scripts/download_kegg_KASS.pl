#!/usr/bin/env perl

=head1 NAME

download_kegg_data.pl

=head1 SYNOPSIS

 perl download_kegg_KAAS.pl [--input] [-h help]

=head1 DESCRIPTION

Utility to download KEGG annotation

Typical usage is as follows:

  % perl download_kegg_KAAs.pl

=head2 Options

Required arguments:

 --input=<string>              File produced by KAAS with associations bewteen Prot IDs & KEGG orthologs [Mandatory]

The following options are accepted:

 --help                       	This documentation

Important: Please specify in configuration file list of 3-letters code for KEGG species used for annotation via KAAS server
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
use Data::Dumper;
use LWP::Simple;
use Config::Simple;
use String::Util 'trim';
my $confFile = 'main_configuration.ini';

my $USAGE = "perl download_kegg_KAAS.pl [-i input] [-h help]\n";
my ($show_help, $input);

&GetOptions(
      'input|i=s'     => \$input,
      'conf=s'        =>\$confFile,
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if (!$input) {
	die("Please specify input file with results of KAAS server or KEGG DB release used to annotated data!\n Launch 'perl download_kegg_KAAS.pl -h' to see parameters description\n")
}

#read configuration file

my $cfg = new Config::Simple($confFile);
#put config parameters into %config
my %config = $cfg->vars();

#my %conf =  %::conf;
#my $debug = $config{'debug'};

my $loglevel = $config{'loglevel'};
if(! defined $loglevel){$loglevel='info';}

my %keggs=();
# parse $input to know the number of associations of a KEGG group to different proteins
open (FH, "$input");
while (my $line = <FH>) {
     chomp ($line);
     my ($protein_stable_id, $kegg_id) = split (/\t/, $line);
     if ($kegg_id) {
			 push(@{$keggs{$kegg_id}},$protein_stable_id);
     }
}
close FH;


if(($loglevel eq 'debug' )||($loglevel eq 'info' )) {print STDOUT "Number of unique KEGG groups:",scalar(keys %keggs),"\n";}

my $down_kegg_dir = "down_kegg";
if ( ! -d $down_kegg_dir ) {
  system( "mkdir -p $down_kegg_dir" )
}

my $webChunk = 10;
my @queue = [];
my $iter = 0;

foreach my $kegg_id (keys %{%keggs} ) {

  if ( $#queue > $webChunk - 1 ) {

    &processByAPI( \@queue, $down_kegg_dir, $iter );

    @queue = [];
    $iter++;

  }

  push( @queue, "ko:".$kegg_id );


}

sub processByAPI {

  my $arr = shift;
  my $down_kegg_dir = shift;
  my $iter = shift;

  my $url = "http://rest.kegg.jp/get/".join("+", @{$arr});
  my $response = get $url;

  open FILEOUT, ">", $down_kegg_dir."/".$iter.".txt";
  print FILEOUT $response;
  close FILEOUT;

}
