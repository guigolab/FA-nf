#!/usr/bin/env perl

use warnings;

# Script to POST and retrieve CD search via HTTP protocol, taken from 
#https://www.ncbi.nlm.nih.gov/Structure/cdd/cdd_help.shtml

use strict;
use LWP::UserAgent;
#use Getopt::Std;
use Getopt::Long;


###############################################################################
# URL to the Batch CD-Search server
###############################################################################

my $bwrpsb = "https://www.ncbi.nlm.nih.gov/Structure/bwrpsb/bwrpsb.cgi";


###############################################################################
# set default values
###############################################################################
my $cdsid = "";
my $cddefl = "false";
my $qdefl = "false";
my $smode = "auto";
my $useid1 = "true";
my $maxhit = 250;
my $filter = "true";
my $db = "cdd";
my $evalue = 0.01;
my $dmode = "rep";
my $clonly = "false";
my $tdata = "hits";
my $output="hits.res.tsv";

###############################################################################
# deal with command line parameters, change default settings if necessary
###############################################################################

my ($opt_d, $opt_e, $opt_F, $opt_b, $opt_t, $opt_s, $opt_a, $opt_q,$opt_o, $show_help,$opt_in);

GetOptions(
           "d=s"	=>\$opt_d,
           "e=s"=>\$opt_e,
           "F=s" =>\$opt_F,
           "b=s"=>\$opt_b,
           "t=s"=>\$opt_t,
           "s=s"=>\$opt_s,
           "a=s"=>\$opt_a,
           "q=s"=>\$opt_q,
           "o=s"=>\$opt_o,
           "i|in=s"=>\$opt_in,
           "help|h" => \$show_help
           );

if($show_help) 
{
die(qq/
  Usage:   perl  submitCDsearch.pl [options]  < test.fa        
 complete set of options see here https\:\/\/www.ncbi.nlm.nih.gov\/Structure\/cdd\/cdd_help.shtml#BatchRPSBWebAPI_parameters

 Options 
       -h || help 		 : This message
       -t    		 : data type. Specify the data type (target data) desired in the output. Allowable values are: "hits" (domain hits), "aligns" (alignment details), or "feats" (features). 
       -o    		 : output file name
\n/)};

#getopts('d:e:F:b:t:s:a:q:o');

if ($opt_d) {
  $db = $opt_d;
  print "Databast option set to: $db\n";
}
if ($opt_e) {
  $evalue = $opt_e;
  print "Evalue option set to: $evalue\n";
}
if ($opt_F) {
  if ($opt_F eq "F") {
    $filter = "false"
  } else {
    $filter = "true";
  }
  print "Filter option set to: $filter\n";
}
if ($opt_b) {
  $maxhit = $opt_b;
  print "Maxhit option set to: $maxhit\n";
}
if ($opt_t) {
  $tdata = $opt_t;
  print "Target data option set to: $tdata\n";
}
if ($opt_s) {
  $clonly = "true";
  print "Superfamilies only will be reported\n";
}
if ($opt_a) {
  $dmode = "all";
  print "All hits will be reported\n";
}
if ($opt_q) {
  $qdefl = "true";
  print "Query deflines will be reported\n";
}


if ($opt_o) {
  $output = $opt_o;
  print "Result data will be written to $output file\n";
}


###############################################################################
# read list of queries and parameters supplied; queries specified in list piped
# from stdin
###############################################################################

#my @queries = <STDIN>;

my @queries=();
open(IN, $opt_in)||die "Cant open file $opt_in for reading!\n";
while(my $line=<IN>)
 {chomp($line);
 push(@queries, $line);
}
close(IN);

my $havequery = 0;

###############################################################################
# do some sort of validation and exit if only invalid lines found
###############################################################################

foreach my $line (@queries) {
  if ($line =~ /[a-zA-Z0-9_]+/) {
    $havequery = 1;
  }
}
if ($havequery == 0) {
  die "No valid queries!\n";
}


###############################################################################
# submitting the search
###############################################################################
my $rid;
{
  my $browser = LWP::UserAgent->new;
  my $response = $browser->post(
    $bwrpsb,
    [
      'useid1' => $useid1,
      'maxhit' => $maxhit,
      'filter' => $filter,
      'db'     => $db,
      'evalue' => $evalue,
      'cddefl' => $cddefl,
      'qdefl'  => $qdefl,
      'dmode'  => $dmode,
      'clonly' => $clonly,
      'tdata'  => $tdata,
      ( map {; queries => $_ } @queries )
    ],
  );
  die "Error: ", $response->status_line
    unless $response->is_success;

  if($response->content =~ /^#cdsid\s+([a-zA-Z0-9-]+)/m) {
    $rid =$1;
    print "Search with Request-ID $rid started.\n";
  } else {
    die "Submitting the search failed,\n can't make sense of response: $response->content\n";
  }
}
###############################################################################
# checking for completion, wait 5 seconds between checks
###############################################################################

$|++;
my $done = 0;
my $status = -1;
while ($done == 0) {
  sleep(5);
  my $browser = LWP::UserAgent->new;
  my $response = $browser->post(
    $bwrpsb,
    [
      'tdata' => $tdata,
      'cdsid' => $rid
    ],
  );
  die "Error: ", $response->status_line
    unless $response->is_success;

  if ($response->content =~ /^#status\s+([\d])/m) {
    $status = $1;
    if ($status == 0) {
      $done = 1;
      print "Search has been completed, retrieving results ..\n";
    } elsif ($status == 3) {
      print ".";
    } elsif ($status == 1) {
      die "Invalid request ID\n";
    } elsif ($status == 2) {
      die "Invalid input - missing query information or search ID\n";
    } elsif ($status == 4) {
      die "Queue Manager Service error\n";
    } elsif ($status == 5) {
      die "Data corrupted or no longer available\n";
    }
  } else {
    die "Checking search status failed,\ncan't make sense of response: $response->content\n";
  }

}
print "===============================================================================\n\n";

###############################################################################
# retrieve and display results
###############################################################################
{
  my $browser = LWP::UserAgent->new;
  my $response = $browser->post(
    $bwrpsb,
    [
        'tdata'  => $tdata,
        'cddefl' => $cddefl,
        'qdefl'  => $qdefl,
        'dmode'  => $dmode,
        'clonly' => $clonly,
        'cdsid'  => $rid
    ],
  );
  die "Error: ", $response->status_line
    unless $response->is_success;

 open(OUT, ">$output");
 print OUT $response->content,"\n";
 close(OUT);

 
}
