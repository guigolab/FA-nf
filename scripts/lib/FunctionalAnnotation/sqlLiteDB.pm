#!/Usr/bin/perl -w

=head1 NAME

createSQLliteDB.pl

=head1 SYNOPSIS
	
  perl createSQLliteDB.pl [-h help] [-conf configuration.ini]

Run this script to create SQLliteDB for the functional annotation pipeline

=head1 DESCRIPTION

Typical usage is as follows:

  % perl createSQLliteDB.pl -conf path/main_configuration.ini

=head2 Options

The following options are accepted:

          --help                   	This documentation.
           -conf         : Configuration file. By default main_configuration.ini in current folder is used
=head1 AUTHOR

Vlasova Anna: vlasova dot av A gmail dot com

=cut

package FunctionalAnnotation::sqlLiteDB;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(createSQLliteDB prepareInputFiles getSelectedIds);

use strict;
use DBI;
use FindBin qw($RealBin);
FindBin::again();
use lib "$RealBin/lib/";
use Config::Simple;
use Getopt::Long;

sub createSQLliteDB
{
 my $confFile = shift;
 my $cfg = new Config::Simple($confFile);
 #put config parameters into %config                                             
 my %config = $cfg->vars();
  
  #$config{'debug'};

#########################
#get DB name and db path from configuration file
my $dbName = $config{'dbname'};
my $dbPath = $config{'resultPath'};

my $dbFileName = $dbPath.$dbName.'.db';
my $sqlCommandFile = $RealBin.'/lib/SQLlite.scheme.sql';
if(!-e $dbFileName)
{  
if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
{  print "DB $dbName does not exists, will create it!\n";}

  my $systemCommand="sqlite3 $dbFileName < $sqlCommandFile";
  system($systemCommand)==0 or die("Error running system command: <$systemCommand>\n");
  
 }
else
{
 if(($config{'loglevel'} eq 'debug')||($config{'loglevel'} eq 'info'))
 {  print "This DB is already exists! Continue..\n";}
}

}

sub getSelectedIds
{
 my $listFile =shift;
 my @returnData=();
 
 open(INPUT, $listFile) ||die "Can't open $listFile for reading!\n$!\n";
  while(my $line=<INPUT>)
    {
     chomp($line);
     push(@returnData, $line);
    }
 close(INPUT);
 return @returnData;
}


sub prepareInputFiles
{
 my ($dbh, $configRecord, $selectedIds)=@_;

 #important variables from config file:
 my $chunkSize = $configRecord->{'chunk_size'};
 my $tmpFolder = $configRecord->{'tmp_dir'};
 my $resultFolder = $configRecord->{'resultPath'};
 my $specieName = $configRecord->{'specie_name'};
 my $loglevel =  $configRecord->{'loglevel'};
 
 $tmpFolder = $resultFolder.$tmpFolder;
 my $count=0;
 my $countFile=0;
 if(!-e $tmpFolder)
 {
  mkdir($tmpFolder);
 }

 my $outFile = $tmpFolder.$specieName.'_'.$countFile.'.fa';

#file names with the whole path
 my @returnData;
 my($protName, $protId, $protSeq);
 
if(($loglevel eq 'debug'))
 {
  print "outFile: $outFile\n";
  print "chunk: $chunkSize\n";
 }
 open(OUT, ">$outFile")|| die "Can't open $outFile for writing! $!\n";
 push(@returnData, $outFile);

 my $selectString = "SELECT protein_id, stable_id, sequence from protein ";
 if (scalar @{$selectedIds} >0 )
  {
   my @quotedIds = &quoteEveryRecord(@{$selectedIds});
   my $restrString = join(",", @quotedIds);
   $selectString .= "where stable_id in ($restrString) ";
  }
   print "$selectString\n";
   my $results = $dbh->select_from_table($selectString);
   
   foreach my $result (@{$results}) 
   {
    $protName = $result->{'stable_id'};
    $protId = $result->{'protein_id'};
    $protSeq = $result->{'sequence'};
  if(($loglevel eq 'debug'))
   {  print "Name: $protName\n";}
    $count++;
    print OUT "\>$protName\n$protSeq\n";
    if($count >= $chunkSize)
    {
     close(OUT);
     $countFile++;
     $count=0;
  if(($loglevel eq 'debug'))
  {  print "outFile: $outFile\n";}
     $outFile = $tmpFolder.$specieName.'_'.$countFile.'.fa';
     open(OUT, ">$outFile")|| die "Can't open $outFile for writing! $!\n";
     push(@returnData, $outFile);
    }
   }
 
 close(OUT);

 return @returnData;
}


sub quoteEveryRecord
{
 my @list=@_;

 for(my $i=0;$i<= scalar(@list); $i++)
 {
   $list[$i]= '"'.$list[$i].'"';
 }
 return @list;
}