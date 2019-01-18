#!/usr/bin/env perl

=head1 NAME

load_kegg_data.pl

=head1 SYNOPSIS

 perl load_kegg_KAAS.pl [--input] [-u update] [-h help]

=head1 DESCRIPTION

Utility to parse Kegg annotation and populate tables

Typical usage is as follows:

  % perl load_kegg_KAAs.pl

=head2 Options

Required arguments:

 --input=<string>              File produced by KAAS with associations bewteen Prot IDs & KEGG orthologs [Mandatory]
 --rel                         KEGG release [Mandatory]

The following options are accepted:

 --update=<do update>     	If specified, update existing records (0=no is default)
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
use FunctionalAnnotation::DB;
use FunctionalAnnotation::uploadData;
use Bio::SeqIO;
use Data::Dumper;
use LWP::Simple;
use Config::Simple;
use String::Util 'trim';
my $confFile = 'main_configuration.ini';


my $USAGE = "perl load_kegg_KAAS.pl [-i input]  [-rel Kegg release] [-h help] [-conf configuration file] \n";
my ($do_update, $show_help, $input,$kegg_release);

&GetOptions(
			'update|u=s'	=> \$do_update,
                        'input|i=s'     => \$input,
                        'rel|r=s'       => \$kegg_release,
                        'conf=s'=>\$confFile,
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

$do_update = 0 if (!defined $do_update);

if (!$input || !$kegg_release)
{die("Please specify input file with results of KAAS server or KEGG DB release used to annotated data!\n Launch 'perl load_kegg_KAAS.pl -h' to see parameters description\n")}

#read configuration file

my $cfg = new Config::Simple($confFile);
#put config parameters into %config
my %config = $cfg->vars();

#my %conf =  %::conf;
#my $debug = $config{'debug'};

my $loglevel = $config{'loglevel'};
if(! defined $loglevel){$loglevel='info';}

#kegg codes for orthologs to include in the DB
my @kegg_codes = map { trim($_) } split /,/, $config{'kegg_species'};

#print "Dumper @kegg_codes\n"; die;


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

#make hash record out of list with kegg species, specified in ini file.
my %codes=();
my %organisms=();
foreach my $item(@kegg_codes)
 {
    $item=~s/\s+//;
    $codes{$item}=1;
 }

#get list of organisms from the KEGG server and select only ones that needed
%organisms = &organism_table(\@kegg_codes,$config{'dbEngine'} ,$dbh);

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
#upload KEGG group information into DB - this will speed-up uploading process.. There are usually fewer groups then proteins assigned to them

#print Dumper( \%keggs );
#print Dumper( \%organisms );


&uploadKeggInformation($dbh, \%keggs,\%organisms,$config{'dbEngine'});


sub uploadKeggInformation
{
 my($dbh, $keggData,$codesOrg,$dbEngine)=@_;

 my($sqlSelect, $sqlInsert,$sqlUpdate);
 my %protDefinitionData=();

 foreach my $kegg_id(keys %{$keggData})
 {
  #get KO information from server
  my $hash=parse_kegg_record($kegg_id);
#  print Dumper($hash)."\n"; die;
 
 my @proteinList = @{$keggData->{$kegg_id}};
  my $numberProteinsInGroup=scalar @proteinList;
  #upload information about KO group into DB if its absent in DB
  my @absentList=qw(PATHWAY CLASS MODULE DEFINITION DBLINKS);
  foreach my $absItem(@absentList)
  { if(!defined $hash->{$absItem})
    {$hash->{$absItem}="";}
   }
  #populate kegg_group table
  #check if kegg_group already exists (yes && do_update => update record; no => insert new kegg_group)
  my $kegg_group_sql_select = qq{ SELECT kegg_group_id FROM kegg_group WHERE db_id=\"$kegg_id\" };
  my $kegg_group_sql_update = qq{ UPDATE kegg_group SET name=\"$hash->{'NAME'}\",definition=\"$hash->{'DEFINITION'}\",pathway=\"$hash->{'PATHWAY'}\",module=\"$hash->{'MODULE'}\",class=\"$hash->{'CLASS'}\", db_links=\"$hash->{'DBLINKS'}\", db_id=\"$kegg_id\", kegg_release=\"$kegg_release\";};
  my $kegg_group_sql_insert = "";
  if($dbEngine eq 'SQLite')
   { $kegg_group_sql_insert = qq{ INSERT INTO kegg_group(kegg_group_id, name,definition,pathway,module,class,db_links,db_id,kegg_release) VALUES (NULL,\"$hash->{'NAME'}\",\"$hash->{'DEFINITION'}\",\"$hash->{'PATHWAY'}\",\"$hash->{'MODULE'}\",\"$hash->{'CLASS'}\", \"$hash->{'DBLINKS'}\",\"$kegg_id\",\"$kegg_release\")}; }
  else
   { $kegg_group_sql_insert = qq{ INSERT INTO kegg_group SET name=\"$hash->{'NAME'}\",definition=\"$hash->{'DEFINITION'}\",pathway=\"$hash->{'PATHWAY'}\",module=\"$hash->{'MODULE'}\",class=\"$hash->{'CLASS'}\", db_links=\"$hash->{'DBLINKS'}\", db_id=\"$kegg_id\", kegg_release=\"$kegg_release\";};}
  if(($loglevel eq 'debug' )||($loglevel eq 'info' )){ print "SQL: $kegg_group_sql_insert\n";}
  my $kegg_group_id = $dbh->select_update_insert("kegg_group_id", $kegg_group_sql_select, $kegg_group_sql_update, $kegg_group_sql_insert, $do_update);
  #small patch for SQLite - the current insert function could not return id of the last inserted record...
  if(!defined $kegg_group_id)
    {
      my $select = &selectLastId( $dbEngine );
      my $results = $dbh->select_from_table($select);
      $kegg_group_id=$results->[0]->{'id'};
    }
 if(!defined $kegg_group_id)
  {die("Unexpectable problem! Can not find kegg_group_id for $kegg_id group!$!\n");}

  foreach my $proteinItem(@proteinList)
  {
    #select protein_id infor (because items are stable_ids in protein table)
     my $protein_sql_select= qq{ SELECT protein_id,definition FROM protein WHERE stable_id=\"$proteinItem\"};
     my $res = $dbh->select_from_table($protein_sql_select);
					
					# If no content, next. Cases of partial tests.
					if ( $#{$res} < 0 ){
						next;
					}
					
     my $protein_id=$res->[0]->{'protein_id'};
     my $protein_definition=$res->[0]->{'definition'};

    #add orthologus information from the list of species for proteins associated to this KO group
     my $gene_string=$hash->{'GENES'};
					#print STDERR $proteinItem, "\t", $gene_string, "\n";
     #print "gene string: $gene_string\n";
     my @lines=split/\,/,$gene_string;
     my $is_cluster;
     foreach my $l (@lines) {
       # insert each ortholog
       my ($code,$gene_id)=split/\:/,$l;
       $gene_id=~s/^ //;
       # determine if $gene_id containt a cluster of genes
        my @cluster=split/ /,$gene_id;
        $is_cluster=1 if scalar(@cluster)>1;
        $is_cluster=0 if scalar(@cluster)==1;
        my $lcode=lc($code);
        # next if ortholog is not in the list of species to analyze
         next if !$codesOrg->{$lcode};
         #get organism_id from DB
         #my $organism_id= organism_table($lcode,$dbEngine,$dbh);
         my $organism_id= $codesOrg->{$lcode};

         #populate ortholog table
         #check if ortholog already exists (yes && do_update => update record; no => insert new ortholog)
         my $ortholog_sql_select = qq{ SELECT ortholog_id FROM ortholog WHERE name=\"$gene_id\" };
         my $ortholog_sql_update = qq{ UPDATE ortholog SET name=\"$gene_id\",organism_id=\"$organism_id\",db_id=\"$kegg_id\",db_name=\"KEGG\";};
         my $ortholog_sql_insert = "";
         if($dbEngine eq 'SQLite')
          {
											$ortholog_sql_insert = qq{ INSERT INTO ortholog(ortholog_id,name,organism_id, db_id,db_name ) VALUES(NULL,\"$gene_id\",\"$organism_id\",\"$kegg_id\",\"KEGG\")};
										}
         else
          {
											$ortholog_sql_insert = qq{ INSERT INTO ortholog SET name=\"$gene_id\",organism_id=\"$organism_id\",db_id=\"$kegg_id\",db_name=\"KEGG\";};
										}
        my $ortholog_id = $dbh->select_update_insert("ortholog_id", $ortholog_sql_select, $ortholog_sql_update, $ortholog_sql_insert, $do_update);
        #small patch for SQLite - the current insert function could not return id of the last inserted record...
        if(!defined $ortholog_id)
          {  my $select = &selectLastId( $dbEngine );
             my $results = $dbh->select_from_table($select);
             $ortholog_id=$results->[0]->{'id'};
          }
							if(($loglevel eq 'debug' )||($loglevel eq 'info' )){ print "SQL: $ortholog_sql_insert --- $ortholog_id\n";}
       #populate protein_ortholog
       #check if protein_ortholog already exists in the table (yes && do_update => update record; no => insert new protein_ortholog)
       my $type;
       if ($numberProteinsInGroup>1 && $is_cluster==0) {
         $type="many2one";
        } elsif ($numberProteinsInGroup>1 && $is_cluster==1) {
         $type="many2many";
        } elsif ($numberProteinsInGroup==1 && $is_cluster==1) {
        $type="one2many";
        } else {
        $type="one2one";
      }
        my $prot_ortholog_sql_select = qq{ SELECT protein_ortholog_id FROM protein_ortholog WHERE protein_id=\"$protein_id\" AND ortholog_id=\"$ortholog_id\" };
        my $prot_ortholog_sql_update = qq{ UPDATE protein_ortholog SET protein_id=\"$protein_id\",ortholog_id=\"$ortholog_id\",type=\"$type\",kegg_group_id=\"$kegg_group_id\";};
        my $prot_ortholog_sql_insert ="";
        if($config{'dbEngine'} eq 'SQLite')
          { $prot_ortholog_sql_insert = qq{ INSERT INTO protein_ortholog (protein_ortholog_id, protein_id,ortholog_id,type,kegg_group_id) VALUES(NULL,\"$protein_id\",\"$ortholog_id\",\"$type\",\"$kegg_group_id\");};}
        else
         { $prot_ortholog_sql_insert = qq{ INSERT INTO protein_ortholog SET protein_id=\"$protein_id\",ortholog_id=\"$ortholog_id\",type=\"$type\",kegg_group_id=\"$kegg_group_id\";};}
         my $protein_ortholog_id = $dbh->select_update_insert("protein_ortholog_id", $prot_ortholog_sql_select, $prot_ortholog_sql_update, $prot_ortholog_sql_insert, $do_update);
       }#for each group of genes in multiply organisms

    #update definition field for proteins associated to this KO group
     if($hash->{'DEFINITION'} ne '')
     { push(@{$protDefinitionData{$protein_id}{'definition'}},$hash->{'DEFINITION'});}
#      $protein_definition .='KEGG:'.$hash->{'DEFINITION'}.';';
#      $sqlUpdate = "UPDATE protein set definition='$protein_definition' where protein_id=$protein_id";
#      print "SQL_CODE:$sqlUpdate\n" ;
#      $dbh->update_set($sqlUpdate);

    #add GO terms info into go_term and protein_go table
    if(defined $hash->{'DBLINKS'})
     {
       my $goId =parseKEGGDBLInks($hash->{'DBLINKS'});
       if($goId ne '')
        {
           #insert go term, associated with this protein into go_term table, and then into protein_go
           my $sqlSelect = "SELECT go_term_id from go_term where go_acc like '$goId'";
           my $sqlUpdate ="";
           my $sqlInsert = "";
           if($dbEngine eq 'SQLite')
            { $sqlInsert = "INSERT INTO go_term (go_term_id,go_acc) VALUES (NULL,\"$goId\")";}
           else
            { $sqlInsert = "INSERT INTO go_term SET go_acc =\"$goId\"";}
           my $goTermId = $dbh->select_update_insert("go_term_id", $sqlSelect, $sqlUpdate, $sqlInsert, 0);
           #small patch for SQLite - the current insert function could not return id of the last inserted record...
           if(!defined $goTermId)
            {
              my $select = &selectLastId( $dbEngine );
              my $results = $dbh->select_from_table($select);
              $goTermId=$results->[0]->{'id'};
            }
           #select protein_go_id if there is one, and add 'KEGG' to the source field
           $sqlSelect = "SELECT protein_go_id, source FROM protein_go where protein_id = $protein_id and go_term_id=$goTermId";
           my $result =$dbh->select_from_table($sqlSelect);
           my($proteinGoId, $source);
           if(defined $result->[0]->{'protein_go_id'})
            {
             $proteinGoId = $result->[0]->{'protein_go_id'};
             $source = $result->[0]->{'source'};
             if($source !~/KEGG/)
             {$source .= " KEGG";}
             $sqlUpdate = "UPDATE protein_go SET source = \"$source\" where protein_go_id=$proteinGoId";
             $dbh->update_set($sqlUpdate);
            }
           else
            {
            if($config{'dbEngine'} eq 'SQLite')
            { $sqlInsert = "INSERT INTO protein_go (protein_go_id,source, protein_id, go_term_id) VALUES (NULL,'KEGG',$protein_id,$goTermId)";}
           else
            {  $sqlInsert = "INSERT INTO protein_go SET source='KEGG ', protein_id=$protein_id, go_term_id = $goTermId";}
             $dbh->insert_set($sqlInsert);
            }
          }#if there was a GO records
         }#if defined dbLinks
  }#foreach protein Item

 }#foreach kegg KO item

 #update protein definition for KEGG source
  #print STDERR Dumper( \%protDefinitionData );
  &updateProteinDefinition(\%protDefinitionData,$dbh,1,'KEGG',$dbEngine,'protein_id');

}#sub


sub parseKEGGDBLInks
{
 my $dbLinks = shift;

 my $retGO='';

 $dbLinks=~s/\n//g;
 if($dbLinks =~/(GO\:\s*\d+)\s*/)
  {
   $retGO = $1;
   $retGO=~s/\s+//g;
  }

 return $retGO;
}


# subroutine to parse KEGG record and put its elements into a hash
sub parse_kegg_record {
    my $kegg_id=shift;
    my %returnData;
    my $url = "http://rest.kegg.jp/get/ko:$kegg_id";
    my $response = get $url;
#    print $response;
    my @lines = split(/\n/,$response);
    my($name, $value);
    foreach my $item (@lines)
    {
     chomp($item);
     if($item=~/\/\/\//){last;}
     if($item=~/^(\w+)\s+(.+)$/)
      {
       $name =$1;$value=$2;
       $value =~s/\"//g;
       $returnData{$name}=$value;
      }
     else
     {
       $item=~s/^\s+//;
       $item=~s/\s+$//;
       $item =~s/\"//g;
       $returnData{$name} .= ','.$item;
     }

    }

   return \%returnData;
}

# subroutine to get organism_id for a specific 3-letter code
sub organism_table {
    my ($codeList, $engine,$dbh)=@_;

    #check whether this organism is already present in the DB (without additional connction to NCBI taxonomy and KEGG rest server)
    my $url = "http://rest.kegg.jp/list/genome";
    my $response = get $url;

    my %returnData=();

   #print Dumper($codeList)."\n";

    foreach my $code(@{$codeList})
    {
    # print "Code:$code\n";

     my $selectString = "SELECT organism_id from organism where kegg_code like '$code'";
     my $results = $dbh->select_from_table($selectString);
     my $organism_id=$results->[0]->{'organism_id'}||'';
     if($organism_id eq '')
    {
    #get information from KEGG server (it does contains NCBI taxonomy record, we do not need to connect to NCBI)
    #print "Getting organism info from KEGG server...\n";
     my @lines = split(/\n/,$response);
    my($codeItem,$abbr, $taxonId, $scName);
    foreach my $item(@lines)
    {
   #example of the record:
   #genome:T00006	mpn, MYCPN, 272634; Mycoplasma pneumoniae M129
   #genome:T00007	eco, ECOLI, 511145; Escherichia coli K-12 MG1655
     ($codeItem,  $taxonId, $scName)=$item=~/[^,]+(...)\,[^,]+\,.(\d+)\;.(.+)$/;

    if(! defined $scName){
     ($codeItem,  $taxonId, $scName)=$item=~/[^,]+(...)\,.(\d+)\;.(.+)$/;
     }
  
     if(!defined $codeItem){next;}
     if($codeItem eq $code)
     {last;}
    }
    if(!defined $taxonId)
    {print "Warning: there is no information about this specie: $code! skipped\n";next;}

     #remove brackets from scName
     $scName=~s/[()]+//gi;

         # check if organism already exists (yes && do_update => update record; no => insert new organism)
    my $organism_sql_select = qq{ SELECT organism_id FROM organism WHERE taxonomy_id=\"$taxonId\" };
    my $organism_sql_update = qq{ UPDATE organism SET species=\"$scName\",name=\"$scName\",reign=\"\",taxonomy_id=\"$taxonId\",kegg_code=\"$code\";};
    my $organism_sql_insert ="";
    if($engine eq 'SQLite')
    {$organism_sql_insert = qq{ INSERT INTO organism (organism_id,species,name, reign,taxonomy_id,kegg_code) VALUES(NULL,\"$scName\",\"$scName\",\"\",\"$taxonId\",\"$code\");};}
    else
    { $organism_sql_insert = qq{ INSERT INTO organism SET species=\"$scName\",name=\"$scName\",reign=\"\",taxonomy_id=\"$taxonId\",kegg_code=\"$code\";};}
#    $do_update=0;
    #print "$organism_sql_insert\n";
    #print "$organism_sql_select\n";
   #print "$organism_sql_update\n $do_update\n";

    my $organism_id = $dbh->select_update_insert("organism_id", $organism_sql_select, $organism_sql_update, $organism_sql_insert, $do_update);

    #small patch for SQLite - the current insert function could not return id of the last inserted record...
     if(!defined $organism_id)
       {
        my $select = &selectLastId( $engine );
        my $results = $dbh->select_from_table($select);
        #print Dumper($results);
        $organism_id=$results->[0]->{'id'};
       }

    }#if ! defined organism id
    $returnData{$code}=$organism_id;
   }

    return %returnData;
}

sub selectLastId {

        my $engine = shift;

        if ( $engine eq 'mysql' ) {

                return "SELECT last_insert_id() as id ";

        } else {

                return "SELECT last_insert_rowid() as id ";

        }

}



