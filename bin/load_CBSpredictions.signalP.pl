#!/usr/bin/env perl

use warnings;

=head1 NAME

load_CBSpredictions.signalP.pl

=head1 SYNOPSIS

 perl load_CBSpredictions.signalP.pl [-i prediction file] [-conf configuration file] [-h help]

Script to import data from signalP, targetP and cloroP predictions into corresponding tables in the DB

head1 DESCRIPTION

Use this script to import signalP predictions into database

Typical usage is as follows:

  % perl load_CBSpredictions.signalP.pl -i signalP.out -conf main_configuration.ini

=head2 Options

The following options are accepted:

 --i=<string>        		Specify the file containing signalP predictions [Mandatory]

 --conf=<string>		Configuration file with details for DB connections, pathways and so on. [Mandatory]

 --type      			Result type - either signalP, targetP or chloroP predictions [s/t/c] [Mandatory, 's' by default]

 --help                   	This documentation.

=head1 AUTHOR

Anna Vlasova<vlasova.av@gmail.com>

=cut

use strict;
use warnings;
use FindBin qw($RealBin);
FindBin::again();
use lib "$RealBin/lib/";
use Getopt::Long;
use Pod::Usage;
use FunctionalAnnotation::DB;
use FunctionalAnnotation::uploadData;
use DBI;
use Data::Dumper;
use Config::Simple;
use Scalar::Util qw(looks_like_number);
my $confFile = 'main_configuration.ini';

my $USAGE = "perl load_phylome_data.pl [-idf idfile] [-type s]  [-conf configuration_file] [-h help] \n";
my ($idfile, $show_help,$ortfile,$type);

$type='s';

&GetOptions(
					'i|idf=s'  				=> \$idfile,
					'conf=s'=>\$confFile,
 					'type=s'=>\$type,
 					'help|h'        				=> \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

my $cfg = new Config::Simple($confFile);
#put config parameters into %config
my %config = $cfg->vars();
#my %conf =  %::conf;
my $debug = $config{'debug'};

if(!defined $config{'dbEngine'}){$config{'dbEngine'} = 'mysql';}
my $dbh;
#connect to the DB
if(lc( $config{'dbEngine'} ) eq 'mysql')
{
$dbh = DBI->connect( "DBI:mysql:database=".$config{'dbname'}.";host=".$config{'dbhost'}.";port=".$config{'dbport'}, $config{'dbuser'}, $config{'dbpass'});

}
else
{
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= DBI->connect("DBI:SQLite:dbname=$dbName","", "", {
     RaiseError => 1,
     ShowErrorStatement               => 1,
     sqlite_use_immediate_transaction => 1,
     AutoCommit => 0});
}

#my %conf =  %::conf;

die "You must specify a file with the predictions\n Use -h for help"
	if !$idfile;

my %dataHash = &parseCBSpredictionsData($idfile,$type);
&uploadCBSpredictionsFast($dbh, \%dataHash,$config{'dbEngine'}, $type);

# Commit needed for SQLite
if(lc( $config{'dbEngine'} ) eq 'sqlite')
{
		$dbh->commit;
}

$dbh->disconnect();


sub uploadCBSpredictionsFast
{
 my ($dbh, $dataHash,$engine, $type)=@_;

 my($select, $result,$table,$tableId ,$selectString, $insertString, $updateString);
 my @keys=();

	if($type eq 's') {
		$table = 'signalP';
		$tableId = 'signalP_id';
		@keys=('start', 'end', 'score');
		if ( $engine eq 'mysql' ) {
			$insertString = "INSERT INTO $table (protein_id,".join(",",@keys).") VALUES(?,?,?,?)";
		} else {
			$insertString = "INSERT INTO $table ($tableId, protein_id,".join(",",@keys).") VALUES(NULL,?,?,?,?)";
		}
	}
  elsif($type eq 'c') {
		$table = 'chloroP';
	  $tableId = 'chloroP_id';
	  @keys=('start', 'end', 'score');
		if ( $engine eq 'mysql' ) {
			$insertString = "INSERT INTO $table (protein_id,".join(",",@keys)." ) VALUES(?,?,?,?)";
		} else {
			$insertString = "INSERT INTO $table ($tableId, protein_id,".join(",",@keys)." ) VALUES(NULL,?,?,?,?)";
		}
  }
  elsif($type eq 't') {
		$table = 'targetP';
    $tableId = 'targetP_id';
    @keys=('location','RC');
		if ( $engine eq 'mysql' ) {
			$insertString = "INSERT INTO $table (protein_id,".join(",",@keys)." ) VALUES(?,?,?)";
		} else {
			$insertString = "INSERT INTO $table ($tableId, protein_id,".join(",",@keys)." ) VALUES(NULL,?,?,?)";
		}
  }

 my $sth = $dbh->prepare($insertString);

 foreach my $protItem (keys %{$dataHash})
 {
  $select = "select protein_id from protein where stable_id like '%$protItem%'";
  my $sth2 = $dbh->prepare($select);
  $sth2->execute();
  my $proteinId = $sth2->fetchrow()||'';
  $sth2->finish();

		if ( $proteinId eq '' ) {
        next;
								# No protein ID, let's skip
  }

  my $setString='';
  my @setData=();
  push(@setData,$proteinId);
# for SQLite engine only

   foreach my $keyItem(@keys)
      {
        push(@setData, processType( $dataHash->{$protItem}{$keyItem} ) );
      }
   my $setValuesString = join(',', @setData);
#   print STDERR "$setValuesString\n";
   $sth->execute(@setData);
  # $sth->commit;
#   $sth->finish();
}

 $sth->finish();
}

sub processType {

	my $value = shift;

	if ( looks_like_number( $value ) ) {

		return $value;
	} else {
		return "\"".$value."\"";
	}

}


sub parseCBSpredictionsData {
 my ($fileName, $pType) = @_;

 my %retData=();
 my @data=();

 my($protName);
 open(IN, $fileName) || die "Can't open $fileName for reading $!\n";
 while(my $line=<IN>) {
    chomp($line);
    if($line=~/^\#/) {next;}
    @data=split(/\s+/,$line);
    if(scalar(@data) < 6) {next;}
    #for signalP
    if($type eq 's') {
      if($data[9] eq 'Y'){
       $protName=$data[0];
       $retData{$protName}{'start'} = 1;
       $retData{$protName}{'end'} = $data[2];
       $retData{$protName}{'score'} = $data[8];
     }
    }
    #for chloroP
    elsif($type eq 'c') {
      if($data[3] eq 'Y'){
       $protName=$data[0];
       $retData{$protName}{'start'} = 1;
       $retData{$protName}{'end'} = $data[5];
       $retData{$protName}{'score'} = $data[2];
     	}
    }
    #for targetP
    elsif($type eq 't') {
     if($data[6] ne '_'){
       $protName=$data[0];
       $retData{$protName}{'location'} = $data[6];
       $retData{$protName}{'RC'} = $data[7];
      }
   }
   else
	  {die "Error: Unknown type of the input data, can not proceed!\n";}
 }
 close(IN);

 return %retData;
}
