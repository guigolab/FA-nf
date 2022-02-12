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
use Array::Split qw( split_by split_into );
my $confFile = 'main_configuration.ini';


my $USAGE = "perl load_kegg_KAAS.pl [-i input]  [-rel Kegg release] [-h help] [-conf configuration file] \n";
my ($do_update, $show_help, $input, $directory, $entries, $kegg_release);

&GetOptions(
			'update|u=s'		=> \$do_update,
      'input|i=s'     => \$input,
			'dir|d=s'				=> \$directory,
			'entries|e=s'		=> \$entries,
      'rel|r=s'       => \$kegg_release,
      'conf=s'				=>\$confFile,
			'help|h'        => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

$do_update = 0 if (!defined $do_update);

if ( !$input || !$kegg_release ) {
	die("Please specify input file with results of KAAS server or KEGG DB release used to annotated data!\n Launch 'perl load_kegg_KAAS.pl -h' to see parameters description\n")
}

# If null, let's assign 0.0
if ( $kegg_release eq 'null' || $kegg_release eq '' ) {

	$kegg_release = &retrieve_kegg_release;

}

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
if (lc( $config{'dbEngine'} ) eq 'mysql') {
	$dbh= FunctionalAnnotation::DB->new('mysql',$config{'dbname'},$config{'dbhost'},$config{'dbuser'},$config{'dbpass'},$config{'dbport'});
} else {
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= FunctionalAnnotation::DB->new('sqlite',$dbName);
}

#make hash record out of list with kegg species, specified in ini file.
my %codes=();
my %organisms=();
foreach my $item ( @kegg_codes ) {
    $item =~s/\s+//;
    $codes{$item}=1;
 }

#get list of organisms from the KEGG server and select only ones that needed
%organisms = &organism_table(\@kegg_codes,$config{'dbEngine'} ,$dbh);

print STDERR "Start here ".getLoggingTime()."\n";

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

#print Dumper( \%keggs );
#print Dumper( \%organisms );

my $pre_upload_kegg = 0;

if ( $directory ) {
	$pre_upload_kegg = &preUploadKeggInformation( $dbh, $directory, $config{'dbEngine'} );
} else {
	if ( $entries ) {
		$pre_upload_kegg = &preUploadKeggEntries( $dbh, $entries, $config{'dbEngine'} );
	}
}

print STDERR "Preupload finished here ".getLoggingTime()."\n";

#print Dumper( \%keggs );
#print Dumper( \%organisms );
#print Dumper( $pre_upload_kegg );
#exit;

&uploadKOInformation( $dbh, \%keggs, \%organisms, $config{'dbEngine'}, $pre_upload_kegg );

print STDERR "Second gone here ".getLoggingTime()."\n";

&uploadKeggInformation( $dbh, \%keggs, \%organisms, $config{'dbEngine'} );

print STDERR "Finished here ".getLoggingTime()."\n";

sub retrieve_kegg_release {

	my $value = 0.0;

	my $url = "http://rest.kegg.jp/info/ko";
	my $response = get $url;
	# print $response;
	my @lines = split(/\n/,$response);
	foreach my $item (@lines) {
	 chomp($item);
	 if ( $item =~ /^ko\s+Release\s+(\d+)/ ) {
		 $value = $1;
	 }

	}

	return $value;
}

sub parseAndUploadKEGGEntry {
	my $filestr = shift;
	my $dbh = shift;
	my $dbEngine = shift;

	my %returnData;
	my $kegg_id;

	my @lines = split(/\n/,$filestr);
	my($name, $value);
	foreach my $item (@lines) {
	 chomp($item);
	 if ($item=~/\/\/\//) {
		 $name = ""; $value = "";
		 last;
	 } else {
		 if($item=~/^ENTRY\s+(\w+)/) {
			 $kegg_id = $1;
		 } else {
			 if($item=~/^(\w+)\s+(.+)$/) {
				 $name = $1; $value = $2;
				 $value =~s/\"//g;
				 $returnData{$name}=$value;
			 } else {
				 if ( $name ) {
				 	$item=~s/^\s+//;
				 	$item=~s/\s+$//;
				 	$item =~s/\"//g;
				 	$returnData{$name} .= ','.$item;
			 	}
			 }
	 	 }
 	 }
	}


	# TODO: Rewrite into specific table
	#if ( $returnData{"GENES"} ) {
	#	my (@parts) = split( ",", $returnData{"GENES"} );
	#	if ( $#parts > 1500 ) { # TODO: check this margin
	#		$returnData{"GENES"} = join( ",", @parts[0 .. 1000] );
			# print STDERR "** Too big GENES in $kegg_id\n";
	#	}
	#}

	if ( $kegg_id ) {

		#print STDERR "* KEGG_ID: ", $kegg_id, "\n";
		#print STDERR Dumper( \%returnData );

		my $kegg_group_id = &uploadSingleKEGGId( $kegg_id, \%returnData, $dbh, $dbEngine );

		#print STDERR $kegg_group_id, "\n";

		if(!defined $kegg_group_id) {
			die("Unexpectable problem! Can not find kegg_group_id for $kegg_id group!$!\n");
		}

	}

	return 1;

}

sub preUploadKeggInformation {

	my ($dbh, $directory, $dbEngine) = @_;

	my $pre_upload_kegg = 0;

	opendir(my $dh, $directory) || die "Can't open $directory: $!";
	my @files = grep { /\.txt/ && -f "$directory/$_" } readdir($dh);
	closedir $dh;

	foreach my $file (@files) {
		# Process Downloaded KEGG files and import into DB
		my ( @filentries ) = &splitKeggFile( $directory."/".$file );
		foreach my $filentry ( @filentries ) {
			&parseAndUploadKEGGEntry( $filentry, $dbh, $dbEngine);
			$pre_upload_kegg++;
		}
	}

	return $pre_upload_kegg;

}

sub preUploadKeggEntries {

	my ($dbh, $directory, $dbEngine) = @_;

	opendir(my $dh, $directory) || die "Can't open $directory: $!";
	my @files = grep { /\.txt/ && -f "$directory/$_" } readdir($dh);
	closedir $dh;

	foreach my $file (@files) {
		open my $fh, '<', $directory."/".$file;
		my $filentry = do { local $/; <$fh> };
		close $fh;

		&parseAndUploadKEGGEntry( $filentry, $dbh, $dbEngine);
		$pre_upload_kegg++;
	}

	return $pre_upload_kegg;

}

sub splitKeggFile {
	my $file = shift;
	my @strings = ();

	open (FH, "$file");

	my $part = "";
	while (<FH>) {

		if ( $_=~/\/\/\// ) {
			if ( $part!~/^\s*$/ ) {
				$part.=$_;
				push( @strings, $part );
			}
			$part = "";
		} else {
			$part.=$_;
		}

	}
	close FH;

	return @strings;
}

sub uploadSingleKEGGId {

	my $kegg_id = shift;
	my $hash = shift;
	my $dbh = shift;
	my $dbEngine = shift;

	my @absentList=qw(PATHWAY CLASS MODULE DEFINITION DBLINKS GENES);
	foreach my $absItem(@absentList) {
		if(!defined $hash->{$absItem}) {
			$hash->{$absItem}="";
		}
	}

	#populate kegg_group table
	#check if kegg_group already exists (yes && do_update => update record; no => insert new kegg_group)
	my $kegg_group_sql_select = qq{ SELECT kegg_group_id FROM kegg_group WHERE db_id=\"$kegg_id\" };
	my $kegg_group_sql_update = qq{ UPDATE kegg_group SET name=\"$hash->{'NAME'}\",definition=\"$hash->{'DEFINITION'}\",pathway=\"$hash->{'PATHWAY'}\",module=\"$hash->{'MODULE'}\",class=\"$hash->{'CLASS'}\", db_links=\"$hash->{'DBLINKS'}\", db_id=\"$kegg_id\", genes=\"$hash->{'GENES'}\", kegg_release=\"$kegg_release\";};
	my $kegg_group_sql_insert = "";
	#if( lc( $dbEngine ) eq 'sqlite') {
	$kegg_group_sql_insert = qq{ INSERT INTO kegg_group(name,definition,pathway,module,class,db_links,db_id,genes,kegg_release) VALUES (\"$hash->{'NAME'}\",\"$hash->{'DEFINITION'}\",\"$hash->{'PATHWAY'}\",\"$hash->{'MODULE'}\",\"$hash->{'CLASS'}\", \"$hash->{'DBLINKS'}\",\"$kegg_id\",\"$hash->{'GENES'}\",\"$kegg_release\")};
	#}
	#else {
	#	$kegg_group_sql_insert = qq{ INSERT INTO kegg_group SET name=\"$hash->{'NAME'}\",definition=\"$hash->{'DEFINITION'}\",pathway=\"$hash->{'PATHWAY'}\",module=\"$hash->{'MODULE'}\",class=\"$hash->{'CLASS'}\", db_links=\"$hash->{'DBLINKS'}\", db_id=\"$kegg_id\", genes=\"$hash->{'GENES'}\", kegg_release=\"$kegg_release\";};
	#}
	if(($loglevel eq 'debug' )||($loglevel eq 'info' )) {
		# print "SQL: $kegg_group_sql_insert\n";
	}

	my $kegg_group_id = $dbh->select_update_insert("kegg_group_id", $kegg_group_sql_select, $kegg_group_sql_update, $kegg_group_sql_insert, $do_update);

	# small patch for SQLite - the current insert function could not return id of the last inserted record...
	if (!defined $kegg_group_id) {
			my $select = &selectLastId( $dbEngine );
			my $results = $dbh->select_from_table($select);
			$kegg_group_id=$results->[0]->{'id'};
	}

	return $kegg_group_id;

}

# sub uploadKOInformation {
#
# 	my($dbh, $keggData, $codesOrg, $dbEngine, $pre_upload_kegg)=@_;
#
#   print STDERR "KO entries: ".$pre_upload_kegg."\n";
#
#   my($sqlSelect, $sqlInsert,$sqlUpdate);
#
#   my @countk = keys %{$keggData};
#   print STDERR "* COUNT: ", $#countk + 1, "\n";
#
# 	# Number limit names
# 	my $limnames = 9;
#
#   # Let's put buckets here
#   my $bucketsize = 10000;
# 	my @orthobucket = ();
#
# 	foreach my $kegg_id (sort( keys %{$keggData})) {
#    #get KO information from server
#
# 	 	my $hash;
# 	 	my $kegg_group_id;
# 	 	if ( $pre_upload_kegg > 0 ) {
#
# 	 		print STDERR "\n* Entering $kegg_id\n";
# 	 		( $hash, $kegg_group_id ) = retrieve_kegg_record( $kegg_id );
#
# 	 		#print STDERR "Prefilled\n";
# 	 		#print STDERR Dumper( $hash );
# 	 		#print STDERR Dumper( $kegg_group_id );
#
# 	 	} else {
#
# 	 		$hash = parse_kegg_record($kegg_id);
#
# 	 		#upload information about KO group into DB if its absent in DB
# 	 	  my @absentList=qw(PATHWAY CLASS MODULE DEFINITION DBLINKS GENES);
# 	 	  foreach my $absItem(@absentList) {
# 	 			if(!defined $hash->{$absItem}) {
# 	 				$hash->{$absItem}="";
# 	 			}
# 	 	  }
#
# 	 		$kegg_group_id = &uploadSingleKEGGId($kegg_id, $hash, $dbh, $dbEngine);
# 	 	}
#
# 		if(!defined $kegg_group_id) {
# 			print STDERR "Unexpectable problem! Can not find kegg_group_id for $kegg_id group!$!\n";
# 			next; # Skip to another entry
# 		}
#
# 		#add orthologus information from the list of species for proteins associated to this KO group
# 		my $gene_string = "";
# 		if ( $hash->{'GENES'} ) {
# 			$gene_string = $hash->{'GENES'};
# 		}
#
# 		# print STDERR $proteinItem, "\t", $gene_string, "\n";
# 		# print STDERR "gene string: $gene_string\n";
# 		my @lines=split/\,/,$gene_string;
#
# 		# We do batch mode for MySQL but not sqlite
# 		# https://sqlite.org/np1queryprob.html
#
# 		print "NUM LINES: $#lines\n";
#
# 		foreach my $l (@lines) {
#
# 			# insert each ortholog
# 			my ($code,$gene_id)=split/\:/,$l;
# 			$gene_id = trim($gene_id);
# 			my $lcode=lc(trim($code));
#
# 			my $name;
# 			# Gene id can be too long
# 			my (@names) = split(/ /, $gene_id);
# 			if ( $#names > $limnames ) {
# 				$name = join(" ", @names[0..$limnames]);
# 			} else {
# 				$name = join(" ", @names);
# 			}
# 			#print STDERR "* ", $lcode, "\n";
# 			#print STDERR "- ", Dumper( $codesOrg );
# 			# next if ortholog is not in the list of species to analyze
# 			next if !$codesOrg->{$lcode};
# 			#print STDERR "Passed\n";
# 			#get organism_id from DB
# 			#my $organism_id= organism_table($lcode,$dbEngine,$dbh);
# 			my $organism_id= $codesOrg->{$lcode};
#
# 			my $values = "( \"$name\", \"$organism_id\", \"$kegg_id\", \"KEGG\" )";
# 			push( @orthobucket, $values );
#
# 		}
#
# 		@orthobucket = &processBucket( $dbh, $dbEngine, \@orthobucket, $bucketsize, "ortho" );
#
#
# 	}
#
# 	@orthobucket = &processBucket( $dbh, $dbEngine, \@orthobucket, 0, "ortho" );
#
#
# }


sub uploadKOInformation {

	my($dbh, $keggData, $codesOrg, $dbEngine, $pre_upload_kegg)=@_;

  print STDERR "KO entries: ".$pre_upload_kegg."\n";

  my($sqlSelect, $sqlInsert,$sqlUpdate);

  my @countk = keys %{$keggData};
  print STDERR "* COUNT: ", $#countk + 1, "\n";

	if ( $pre_upload_kegg < 1 ) {
		print STDERR "No entries!";
	}

	# Number limit names
	my $limnames = 9;

  # Let's put buckets here
  my $bucketsize = 100;
	my $winsize = 100;
	my @orthobucket = ();

	# RETRIEVE By windows
	my ( @all_kegg ) = sort( keys %{$keggData} );
	my ( @kegg_windows ) = split_by( $winsize, @all_kegg );

	foreach my $kw ( @kegg_windows ) {

	 	my $hash = retrieve_kegg_window( $dbh, $kw );

		foreach my $kegg_id (sort( keys %{$hash} ) ) {
			#get KO information from server

			my $kegg_group_id = $hash->{$kegg_id}->{"KEGGGROUPID"};


			if(!defined $kegg_group_id) {
				print STDERR "Unexpectable problem! Can not find kegg_group_id for $kegg_id group!$!\n";
				next; # Skip to another entry
			}

			#add orthologus information from the list of species for proteins associated to this KO group
			my $gene_string = "";
			if ( $hash->{$kegg_id}->{'GENES'} ) {
				$gene_string = $hash->{$kegg_id}->{'GENES'};
			}

			# print STDERR $proteinItem, "\t", $gene_string, "\n";
			# print STDERR "gene string: $gene_string\n";
			my @lines=split/\,/,$gene_string;

			# We do batch mode for MySQL but not sqlite
			# https://sqlite.org/np1queryprob.html

			print "NUM LINES: $#lines\n";

			foreach my $l (@lines) {

				# insert each ortholog
				my ($code,$gene_id)=split/\:/,$l;
				$gene_id = trim($gene_id);
				my $lcode=lc(trim($code));

				my $name;
				# Gene id can be too long
				my (@names) = split(/ /, $gene_id);
				if ( $#names > $limnames ) {
					$name = join(" ", @names[0..$limnames]);
				} else {
					$name = join(" ", @names);
				}
				#print STDERR "* ", $lcode, "\n";
				#print STDERR "- ", Dumper( $codesOrg );
				# next if ortholog is not in the list of species to analyze
				next if !$codesOrg->{$lcode};
				#print STDERR "Passed\n";
				#get organism_id from DB
				#my $organism_id= organism_table($lcode,$dbEngine,$dbh);
				my $organism_id= $codesOrg->{$lcode};

				my $values = "( \"$name\", \"$organism_id\", \"$kegg_id\", \"KEGG\" )";
				push( @orthobucket, $values );

			}

			@orthobucket = &processBucket( $dbh, $dbEngine, \@orthobucket, $bucketsize, "ortho" );

		}

	}

	@orthobucket = &processBucket( $dbh, $dbEngine, \@orthobucket, 0, "ortho" );


}

sub uploadKeggInformation {
 my($dbh, $keggData, $codesOrg, $dbEngine)=@_;

 my($sqlSelect, $sqlInsert,$sqlUpdate);
 my %protDefinitionData=();
 my %goall;

 my @countk = keys %{$keggData};
 print STDERR "* COUNT: ", $#countk + 1, "\n";

 # Let's put buckets here
 my $bucketsize = 100;
 my $winsize = 100;
 my @porthobucket = ();
 my @gobucket = ();

 # RETRIEVE By windows
 my ( @all_kegg ) = sort( keys %{$keggData} );
 my ( @kegg_windows ) = split_by( $winsize, @all_kegg );

 foreach my $kw ( @kegg_windows ) {

	 my $hash = retrieve_kegg_window( $dbh, $kw );

	 foreach my $kegg_id (sort( keys %{$hash} ) ) {
	  #get KO information from server

		my $kegg_group_id = $hash->{$kegg_id}->{"KEGGGROUPID"};
		print STDERR "\n* Entering $kegg_id\n";
		#( $hash, $kegg_group_id ) = retrieve_kegg_record( $kegg_id );

		#  print Dumper($hash)."\n"; die;


		if(!defined $kegg_group_id) {
			print STDERR "Unexpectable problem! Can not find kegg_group_id for $kegg_id group!$!\n";
			next; # Skip to another entry
		}

	 	my @proteinList = @{$keggData->{$kegg_id}};
	  my $numberProteinsInGroup=scalar @proteinList;

		print "* NUM PROT: $#proteinList\n";

		# Number limit names
		my $limnames = 9;

		# We store mapping of proteins and GO for making it faster
		my %gomap;
		# my @porthobucket = ();

		# Here we preretrieve orthologs_id for saving time with fixed KEGG_ID
		my ($orthoidlist) = {};
		my $results_ortho = $dbh->select_from_table("SELECT ortholog_id, name, organism_id from `ortholog` where db_id = \"$kegg_id\" ;");

		foreach my $result ( @{$results_ortho} ) {
			my $org = $result->{"organism_id"};
			my $name = $result->{"name"};
			my $oid = $result->{"ortholog_id"};

			if ( ! $orthoidlist->{$org} ) {
				$orthoidlist->{$org} = {};
			}

			$orthoidlist->{$org}->{$name} = $oid;
		}

	  foreach my $proteinItem ( @proteinList ) {

				#select protein_id infor (because items are stable_ids in protein table)
				my $protein_sql_select= qq{ SELECT d.protein_id,d.definition d FROM definition d, protein p WHERE p.protein_id=d.protein_id and p.stable_id=\"$proteinItem\"};
				my $res = $dbh->select_from_table($protein_sql_select);

				# If no content, next. Cases of partial tests.
				if ( $#{$res} < 0 ){
					next;
				}

				my $protein_id = $res->[0]->{'protein_id'};
				my $protein_definition = $res->[0]->{'definition'};

				my $is_cluster;

				#add orthologus information from the list of species for proteins associated to this KO group
				my $gene_string = "";
				if ( $hash->{$kegg_id}->{'GENES'} ) {
					$gene_string = $hash->{$kegg_id}->{'GENES'};
				}

				# print STDERR $proteinItem, "\t", $gene_string, "\n";
				# print STDERR "gene string: $gene_string\n";
				my @lines=split/\,/,$gene_string;

				# We do batch mode for MySQL but not sqlite
				# https://sqlite.org/np1queryprob.html

				foreach my $l (@lines) {

					# insert each ortholog
					my ($code,$gene_id)=split/\:/,$l;
					$gene_id = trim($gene_id);
					# determine if $gene_id containt a cluster of genes
					my $name;
					# Gene id can be too long
					my (@names) = split(/ /, $gene_id);
					if ( $#names > $limnames ) {
						$name = join(" ", @names[0..$limnames]);
					} else {
						$name = join(" ", @names);
					}

					$is_cluster=1 if scalar(@names)>1;
					$is_cluster=0 if scalar(@names)==1;
					my $lcode=lc(trim($code));
					#print STDERR "* ", $lcode, "\n";
					#print STDERR "- ", Dumper( $codesOrg );
					# next if ortholog is not in the list of species to analyze
					next if !$codesOrg->{$lcode};
					#print STDERR "Passed\n";
					#get organism_id from DB
					#my $organism_id= organism_table($lcode,$dbEngine,$dbh);
					my $organism_id= $codesOrg->{$lcode};

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

					#my $query = "SELECT ortholog_id from ortholog WHERE name = \"$gene_id\" AND organism_id = \"$organism_id\" AND db_id = \"$kegg_id\"";
					#my $results_ortho = $dbh->select_from_table($query);

					#my $ortholog_id = $results_ortho->[0]->{'ortholog_id'};
					my $ortholog_id = $orthoidlist->{$organism_id}->{$name};

					print STDERR "* ORTHO_ID: $ortholog_id\n";

					if ( ! $ortholog_id ) {
						print STDERR "Major error here\n";
						exit;
					}

					my $values = "( \"$protein_id\", \"$ortholog_id\", \"$type\", \"$kegg_group_id\" )";
					push( @porthobucket, $values );

				} #for each group of genes in multiply organisms


				print STDERR "Ortholog here ".getLoggingTime()."\n";

				# add GO terms info into go_term and protein_go table.
				# TODO Consider in the future other annotations, such as COG
				if(defined $hash->{$kegg_id}->{'DBLINKS'}) {

				 my @goIds = &parseKEGGDBLinks($hash->{$kegg_id}->{'DBLINKS'});

				 # Define storage
				 $gomap{$protein_id} = ();

				 foreach my $goId ( @goIds ) {

					 	 my $goTermId;

					   if ( ! $goall{$goId} ) {

					     #insert go term, associated with this protein into go_term table, and then into protein_go
					     my $sqlSelect = "SELECT go_term_id from go_term where go_acc like '$goId'";
					     my $sqlUpdate ="";
					     my $sqlInsert = "";
					     if( lc( $dbEngine ) eq 'sqlite') {
								 $sqlInsert = "INSERT INTO go_term (go_term_id,go_acc) VALUES (NULL,\"$goId\")";
							 }
					     else {
								 $sqlInsert = "INSERT INTO go_term SET go_acc =\"$goId\"";
							 }
					     $goTermId = $dbh->select_update_insert("go_term_id", $sqlSelect, $sqlUpdate, $sqlInsert, 0);
					     #small patch for SQLite - the current insert function could not return id of the last inserted record...
					     if(!defined $goTermId) {
					        my $select = &selectLastId( $dbEngine );
					        my $results = $dbh->select_from_table($select);
					        $goTermId=$results->[0]->{'id'};
					     }

							 $goall{$goId} = $goTermId;
						 } else {
							 $goTermId = $goall{$goId};
						 }

						 push( @{$gomap{$protein_id}}, $goTermId );
				 }#if there was a GO records
			 }#if defined dbLinks
		}#foreach protein Item

		# my @gobucket = ();
		foreach my $protein_id ( keys %gomap ) {
			foreach my $goTermId ( @{$gomap{$protein_id}} ) {
				my $values = "( \"$protein_id\", \"$goTermId\", \"KEGG\" )";
				push( @gobucket, $values );
			}

		}

		print STDERR "KO finished here ".getLoggingTime()."\n";
		%gomap = ();

		@porthobucket = &processBucket( $dbh, $dbEngine, \@porthobucket, $bucketsize, "portho" );
		@gobucket = &processBucket( $dbh, $dbEngine, \@gobucket, $bucketsize, "go" );

		print STDERR "KO upload finished here ".getLoggingTime()."\n";

	 }#foreach kegg KO item

		#update protein definition for KEGG source
		#print STDERR "Definition\n";
		#print STDERR Dumper( \%protDefinitionData );
		# Toniher: We do not include protein Definition here
		# &updateProteinDefinition(\%protDefinitionData,$dbh,1,'KEGG',$dbEngine,'protein_id');
	}

	@porthobucket = &processBucket( $dbh, $dbEngine, \@porthobucket, 0, "portho" );
	@gobucket = &processBucket( $dbh, $dbEngine, \@gobucket, 0, "go" );

}#sub

sub processBucket {

	my $dbh = shift;
	my $dbEngine = shift;
	my $bucket = shift;
	my $size = shift;
	my $type = shift;

	if ( $#{$bucket} >= $size ) {

		my $query;
		if ( $type eq 'go' ) {

			# VALUES here used for replacement
			if ( lc($dbEngine) eq 'sqlite' ) {
				$query = "INSERT OR IGNORE INTO protein_go (protein_id, go_term_id, source) VALUES #VALUES# ;";
			} else {
				$query = "INSERT INTO protein_go (protein_id, go_term_id, source) VALUES #VALUES# ON DUPLICATE KEY UPDATE protein_id=values(protein_id), go_term_id=values(go_term_id), source=values(source) ;";
			}
		}
		if ( $type eq 'portho' ) {

			if ( lc($dbEngine) eq 'sqlite' ) {
				$query = "INSERT OR IGNORE INTO protein_ortholog (protein_id, ortholog_id, type, kegg_group_id) VALUES #VALUES# ;";
			} else {
				$query = "INSERT INTO protein_ortholog (protein_id, ortholog_id, type, kegg_group_id) VALUES #VALUES# ON DUPLICATE KEY UPDATE protein_id=values(protein_id), ortholog_id=values(ortholog_id), type=values(ortholog_id), kegg_group_id=values(kegg_group_id) ;";
			}
		}

		if ( $type eq 'ortho' ) {

			if ( lc($dbEngine) eq 'sqlite' ) {
				$query = "INSERT OR IGNORE INTO ortholog (name, organism_id, db_id, db_name) VALUES #VALUES# ;";
			} else {
				$query = "INSERT INTO ortholog (name, organism_id, db_id, db_name) VALUES #VALUES# ON DUPLICATE KEY UPDATE name = values(name), organism_id = values(organism_id), db_id = values(db_id) ;";
			}
		}

		$dbh->multiple_query( $query, $bucket );

		print STDERR "Done here $type ".getLoggingTime()."\n";
		# Return empty bucket
		return ();

	} else {

		# Continue with the bucket
		return @{$bucket};
	}

}

sub parseKEGGDBLinks {
	my $dbLinks = shift;

	my ( @retGO ) = ();

	my ( @dblines ) = split(/\,/, $dbLinks);

	# DBLINKS     GO: 0016279 0030544

	foreach my $dbline ( @dblines ) {

		if ( $dbline=~/\bGO\:/ ) {

			# Let's restrict GO here. Future others
			while ( $dbline=~/(\d+)/g ) {
				push( @retGO, "GO:".$1 );
			}

		}
	}

	return @retGO;
}

# subroutine to retrieve KEGG record from DB
sub retrieve_kegg_record {

	my $kegg_id = shift;
	my %hash;

	my $sqlSelect = "SELECT * from kegg_group where db_id = \"$kegg_id\" limit 1";
	my $results =$dbh->select_from_table($sqlSelect);

	my $kegg_group_id;

	if ( $#{$results} >= 0 ) {
		$kegg_group_id = $results->[0]->{"kegg_group_id"};

		foreach my $key ( keys %{$results->[0]} ) {
			my $finalkey = uc($key);
			$finalkey=~s/\_//g;
			$hash{$finalkey} = $results->[0]->{$key};
		}

	}

	return (\%hash, $kegg_group_id);
}

# subroutine to retrieve KEGG record from DB
sub retrieve_kegg_window {

	my $dbh = shift;
	my $kegg_window = shift;
	my %hash;

	if ( $#{$kegg_window} >= 0 ) {

		my @arrSel;
		foreach my $kw ( @{$kegg_window} ) {
				push( @arrSel, "\"".$kw."\"" )
		}

		my $sqlSelect = "SELECT * from kegg_group where db_id in ( ".join( ", ", @arrSel )." ) ";
		#print STDERR $sqlSelect, "\n";
		my $results =$dbh->select_from_table($sqlSelect);

		if ( $#{$results} >= 0 ) {

			foreach my $result ( @{$results} ) {
				my $db_id = $result->{"db_id"};
				$hash{$db_id} = {};

				foreach my $key ( keys %{$result} ) {
					my $finalkey = uc($key);
					$finalkey=~s/\_//g;
					$hash{$db_id}->{$finalkey} = $result->{$key};
				}

			}
		}

	}

	return (\%hash);
}

# subroutine to parse KEGG record and put its elements into a hash
sub parse_kegg_record {
    my $kegg_id=shift;
    my %returnData;
    my $url = "http://rest.kegg.jp/get/ko:$kegg_id";
    my $response = get $url;
		# print $response;
    my @lines = split(/\n/,$response);
    my($name, $value);
    foreach my $item (@lines) {
     chomp($item);
     if($item=~/\/\/\//){last;}
     if($item=~/^(\w+)\s+(.+)$/) {
       $name =$1;$value=$2;
       $value =~s/\"//g;
       $returnData{$name}=$value;
     }
     else {
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
    if( lc( $engine ) eq 'sqlite')
    {$organism_sql_insert = qq{ INSERT INTO organism (organism_id,species,name, reign,taxonomy_id,kegg_code) VALUES(NULL,\"$scName\",\"$scName\",\"\",\"$taxonId\",\"$code\");};}
    else
    { $organism_sql_insert = qq{ INSERT INTO organism SET species=\"$scName\",name=\"$scName\",reign=\"\",taxonomy_id=\"$taxonId\",kegg_code=\"$code\";};}
#    $do_update=0;
    # print "1. $organism_sql_insert\n";
    # print "2. $organism_sql_select\n";
    # print "3. $organism_sql_update\n";

    $organism_id = $dbh->select_update_insert("organism_id", $organism_sql_select, $organism_sql_update, $organism_sql_insert, $do_update);

				# print "4. ".$organism_id."\n";

    #small patch for SQLite - the current insert function could not return id of the last inserted record...
     if(!defined $organism_id && lc( $engine ) eq "sqlite") {

        my $select = &selectLastId( $engine );
        my $results = $dbh->select_from_table($select);
        #print Dumper($results);
        $organism_id=$results->[0]->{'id'};
     }

    }#if ! defined organism id

				if ( $organism_id ) {

					$returnData{$code}=$organism_id;
				}
   }

    return %returnData;
}

sub getLoggingTime {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $nice_timestamp;
}

sub selectLastId {

        my $engine = shift;

        if ( $engine eq 'mysql' ) {

                return "SELECT last_insert_id() as id ";

        } else {

                return "SELECT last_insert_rowid() as id ";

        }

}
