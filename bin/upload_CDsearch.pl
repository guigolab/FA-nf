#!/usr/bin/perl -w

=head1 NAME

 upload_CDsearch.pl

=head1 SYNOPSIS

 perl upload_CDsearch.pl [-conf configuration file] [-h help]

=head1 DESCRIPTION

Utility to populate coresponding tables for CDsearch results (NCBI utility to scan for domains and features http://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi)

Typical usage is as follows:

  % perl upload_CDsearch.pl -conf main_configuration.ini

=head2 Options

Upload pre-calculated results of CDsearch scan, both features and hits, into DB

 Usage:   upload_CDsearch.pl -conf main_configuration.ini  [options]
 Required arguments:
 - type   f/h corresponnd to features or hits data obtained from the NCBI CDsearch

Note: Don't forget to specify mandatory options in the main configuration file :
             Database name and path;

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
use Bio::SeqIO;
use Data::Dumper;
use FunctionalAnnotation::DB;
use FunctionalAnnotation::uploadData;
use FunctionalAnnotation::sqlLiteDB;
use Config::Simple;
use DBI;

my ( $show_help, $input,$confFile, $mode, $listFile,$type);

&GetOptions(
			'input|i=s'     => \$input,
                        'conf=s'=>\$confFile,
                        'type=s'=>\$type,
                        'list=s'=>\$listFile,
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if(!defined $confFile)
{ die("Please specify configuration file!\nLaunch 'perl upload_CDsearch.pl -h' to see parameters description\n ");}

if(!defined $type)
{ die("Please specify results type: f/h only, corresponnd to features or hits data obtained from the NCBI CDsearch!\nLaunch 'perl upload_CDsearch.pl -h' to see parameters description\n ");}


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
{ $dbh= DBI->connect('mysql',$config{'dbname'},$config{'dbhost'},$config{'dbuser'},$config{'dbpass'},$config{'dbport'});}
else
{
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= DBI->connect("DBI:SQLite:dbname=$dbName","", "", { RaiseError => 1 });
}


my %blastData=();
 if(!defined $input)
 {die("Please specify input file with CDsearch results in tsv format!\nLaunch 'perl run_CDsearch.pl -h' to see parameters description\n ");}

my %dataHash = &parseCDsearchData($input,$type);
  #print Dumper(%dataHash); die();
#  &uploadCDsearchData($dbh, \%dataHash,$config{'dbEngine'}, $type);
&uploadCDsearchDataFast($dbh, \%dataHash,$config{'dbEngine'}, $type);

$dbh->disconnect();


sub uploadCDsearchDataFast
{
 my ($dbh, $dataHash,$engine, $type)=@_;

 my($select, $result,$table,$tableId ,$selectString, $insertString, $updateString,$uniqField,$fieldName);

 my $setValuesString="";
 my @setValues=();
 if($type eq 'h')
      {
        $table = 'cd_search_hit';
        $tableId = 'cd_search_hit_id';
        $uniqField ='accession';
        $fieldName = 'Accession';
				@setValues=qw( Hit_type coordinateFrom Bitscore Superfamily Incomplete PSSM_ID coordinateTo E_Value Short_name);
				$setValuesString=join(",", @setValues);

        $insertString = "INSERT INTO $table ($tableId, protein_id, $uniqField, $setValuesString) VALUES(NULL,?,?,?,?,?,?,?,?,?,?,? )";
      }
     elsif($type eq 'f')
      {$table = 'cd_search_features';
       $tableId = 'cd_search_features_id';
       $uniqField='title';
       $fieldName = 'Title';
			 @setValues  =qw(Type mapped_size coordinates complete_size source_domain);
			 $setValuesString=join(",", @setValues);

       $insertString = "INSERT INTO $table ($tableId, protein_id, $uniqField,$setValuesString ) VALUES(NULL,?,?,?,?,?,?,?)";
      }


# my $sth = $dbh->prepare($insertString);

 foreach my $protItem (keys %{$dataHash})
 {
  $select = "select protein_id from protein where stable_id like '%$protItem%'";
  my $sth2 = $dbh->prepare($select);
  $sth2->execute();
  my $proteinId = $sth2->fetchrow()||'';
  $sth2->finish();

  #foreach result line - do its uploading
  for(my $i=0; $i<scalar @{$dataHash->{$protItem}}; $i++)
    {
     my %tmpHash = %{$dataHash->{$protItem}[$i]};

		#26/02/2018 Vlasova.AV
    #important bug - hash data structure does not preserve order of keys, while for DB submission I always need keys in the same order.
		#and it should be exactly the order which is specified in insert string, otherwise script will insert nonsense data into DB without error

  #   my @keyList = keys %tmpHash;
     my $setString='';
     my @setData=();
    # my @setValues=();
     push(@setData,$proteinId);
     push(@setData,"\"$tmpHash{$fieldName}\"" );

     #foreach my $keyItem(@keyList)
		 foreach my $keyItem(@setValues)
      {
       next if ($keyItem eq 'Accession' && $type eq 'h');
#will skip definition so far.
       next if ($keyItem eq 'Definition' && $type eq 'h');
       next if ($keyItem eq 'Title' && $type eq 'f');
      # push(@setValues, $keyItem);
       if($engine eq 'SQLite')
        {push(@setData, "\"$tmpHash{$keyItem}\"");}
       else
        {push(@setData, "$keyItem = \"$tmpHash{$keyItem}\"");}
      }
     $setString = join(', ', @setData);
     my $setValuesString = join(',', @setValues);
     #print "$setValuesString\n";
     #$dbh->disconnect();
     #die();

          if($engine eq 'SQLite')
      {$insertString = "INSERT INTO $table ($tableId, protein_id, $uniqField, $setValuesString) VALUES(NULL,\"$proteinId\",\"$tmpHash{$fieldName}\",$setString)"; }
     else
      {$insertString = "INSERT INTO $table SET protein_id=$proteinId,$setString ";}

    # $selectString = "SELECT $tableId from $table where protein_id=$proteinId and $uniqField=\"$tmpHash{$fieldName}\"";
    # $updateString = "UPDATE $table SET $setString where protein_id=$proteinId and $uniqField=\"$tmpHash{$fieldName}\"";
    # print $insertString."\n";
    # $blastHitId = $dbh->select_update_insert("blast_hit_id", $selectString, $updateString, $insertString, $update);
     #my $setString = join(',', @setData);
     print "$setString\n";
    # my $id= $dbh->insert_set($insertString);
     my $sth = $dbh->prepare($insertString);
     $sth->execute();
  $sth->finish();
 
     #$sth->execute(@setData);
     }#foreach result line - each domain or feature, do its uploading
 }#foreach protein item
}
