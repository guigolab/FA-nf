#!/usr/bin/env perl

use warnings;

=head1 NAME

 get_gff3.pl

=head1 SYNOPSIS

 perl get_gff3.pl [-conf configuration file] [-h help] [-l list with selected ids]

=head1 DESCRIPTION

Utility to get information about annotated and not annotated proteins in the gff3 format

Typical usage is as follows:

  % perl get_gff3.pl -conf main_configuration.ini

=head2 Options

Script to create gff3 formatted file with all annotation features assigned to the concrete protein

 Usage:   perl get_gff3.pl <options>
 Options  -conf      : Configuration file. [Mandatory]
          -list      : File with selected protein IDs - script will process only those seqences
          -help      : This documentation

Note: Don't forget to specify mandatory options in the main configuration file :
             Database name and path;
             Result folder name;


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
use FunctionalAnnotation::sqlDB;
use FunctionalAnnotation::uploadData;
use FunctionalAnnotation::getResults;
use Text::Trim;
use Data::Dumper;
use Config::Simple;

my ( $show_help, $confFile, $listFile);

&GetOptions(
      'conf=s'  => \$confFile,
      'list=s'  => \$listFile,
			'help|h'  => \$show_help
	   )
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

if (!defined $confFile) {
  die("Please specify configuration file!\nLaunch 'perl get_gff3.pl -h' to see parameters description\n ");
}

#read configuration file
my $cfg = new Config::Simple($confFile);
#put config parameters into %config
my %config = $cfg->vars();

#my %conf =  %::conf;
my $debug = $config{'debug'};
my $update=0;

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

if ( ( $config{'loglevel'} eq 'debug' ) || ( $config{'loglevel'} eq 'info' ) ) {
 print '#' x35 ."\n";
 print '#' x5 . 'Generate results in gff format, '.$date.' '.'#' x5 ."\n";
 print '#' x35 ."\n";

}


#connect to mysqlDB
if ( !defined $config{'dbEngine'} ){ $config{'dbEngine'} = 'mysql'; }
my $dbh;
#connect to the DB

if ( lc( $config{'dbEngine'} ) eq 'mysql' ) {
  $dbh= FunctionalAnnotation::DB->new('mysql',$config{'dbname'},$config{'dbhost'},$config{'dbuser'},$config{'dbpass'},$config{'dbport'});
} else {
  my $dbName = $config{'resultPath'}.$config{'dbname'}.'.db';
  my $dsn = "DBI:SQLite:dbname=$dbName";
  $dbh= FunctionalAnnotation::DB->new('sqlite',$dbName);
}

my $outputFolder=$config{'resultPath'};
system("mkdir $outputFolder") if (!-d $outputFolder);
my $outputFile = $outputFolder.'/'.$config{'speciesName'}.'.gff';

my @listIds=();
#create a list with protein ids, if ones is setted up
if ( defined $listFile ) {
  @listIds = &getSelectedIds($listFile);
}

&createGFF3File( $dbh, \@listIds, $outputFile, lc( $config{'dbEngine'} ) );

sub createGFF3File {

  my($dbh, $protIdList, $outFile, $engine)=@_;

  my %geneStore;

  my $numberKeys = scalar @{$protIdList};
  my $condStat='';

  if( $numberKeys>0 ) {

    foreach my $item(@{$protIdList}) {
      $item = "'$item'";
    }

    my $idString = join(',', @{$protIdList});
    $condStat = "where stable_id in ($idString)";
  }

  my $selectString ="select distinct protein_id from protein $condStat";
  my $results =$dbh->select_from_table($selectString);
  my @protIds=();
  foreach my $result (@{$results}) {
    push(@protIds, $result->{'protein_id'});
  }

  #each gff3 record should contain unique ID field.

  my $idInterPro=0;
  my $idCDSearchHit=0;
  my $idCDSearchFeat=0;

  open( OUTFILE, ">$outFile")||die ("Can't open $outFile for writing! $!\n" );
  print OUTFILE "##gff-version 3\n";

  foreach my $idItem (@protIds) {

    my $descrField='';

  	if( $engine eq 'mysql') {
  		$selectString =  "select p.stable_id, group_concat( d.definition SEPARATOR \"@@\" ) as definition, p.cds_strand, p.cds_start, p.cds_end, length(p.sequence) as length, p.gene_id, p.seq_id from protein p left outer join definition d on p.protein_id=d.protein_id where p.protein_id = $idItem group by p.protein_id";
  	} else {
  				$selectString =  "select p.stable_id, group_concat( d.definition, \"@@\" ) as definition, p.cds_strand, p.cds_start, p.cds_end, length(p.sequence) as length, p.gene_id, p.seq_id from protein p left outer join definition d on p.protein_id=d.protein_id where p.protein_id = $idItem group by p.protein_id";
  	}

    $results =$dbh->select_from_table($selectString);
    #print STDERR Dumper($results);
    my $definition= $results->[0]->{'definition'}||'';
    my $protName =$results->[0]->{'stable_id'};
    my $strand  =  $results->[0]->{'cds_strand'}||'+';
    my $stop = $results->[0]->{'length'}||'.'; #Undefined according to spec
  	my $start =1;

  	if ( $stop eq '.' ) {
  		$start = '.';
  	}

    my $genomicStart = $results->[0]->{'cds_start'};
    my $genomicEnd = $results->[0]->{'cds_end'};
    my $genomicLocation = $results->[0]->{'seq_id'};
    my $gene_id = $results->[0]->{'gene_id'}||'0'; #default for 0, no gene

    #select gene data
    $selectString =  "select distinct gene_name from gene where gene_id=$gene_id";
    $results =$dbh->select_from_table($selectString);
    my $geneName =$results->[0]->{'gene_name'}||'';

    #blast2go
    if ( $definition ne '' ){
      my (@defparts) = split(/@@/, $definition);
    			my @descfields;
    			foreach my $def ( @defparts ) {
    				$def = escapeGFF( $def );
    				push( @descfields, $def );
    			}
    			$descrField .="Definition=".join( ",", @descfields).";";
    }

    #Xref record
    $selectString =  "select distinct dbid, dbname from xref where protein_id=$idItem";
    #print STDERR "D:".$selectString, "\n";
    $results =$dbh->select_from_table($selectString);
    my @xrefId=();

    foreach my $item( @{$results} ) {
      push(@xrefId , "$item->{'dbname'}.id=$item->{'dbid'}");
    }

    if(scalar @xrefId >0){
      my $xrefList = join(',', @xrefId);
      $descrField .= $xrefList.';';
    }

    #ontology
    my @ontologyData=();
    #The intersection of this table is too big, since protein_go is huge. Thus I decided to make a two select, and then join results.
    $selectString =  "select distinct go_term_id, source from protein_go where protein_id=$idItem";
    #print STDERR "G:".$selectString."\n";
    $results =$dbh->select_from_table($selectString);
    #one protein could have more then one go_term_id
    my @goTermId=();
	  my @goSource=();

    foreach my $item(@{$results}) {
      push(@goTermId , $item->{'go_term_id'});
		  push(@goSource , $item->{'source'});
	  }

    if ( scalar @goTermId > 0 ) {
        my $goTermIdString = join(',',@goTermId);
        $selectString =  "select go_acc from go_term where go_term_id in ($goTermIdString)";
        $results =$dbh->select_from_table($selectString);
        foreach my $item(@{$results}) {
          push(@ontologyData, $item->{'go_acc'});
        }
        my $ontologyList = join(',', @ontologyData);

        if($ontologyList ne ''){

              $descrField .= "Ontology_term=$ontologyList;";
              my @usources = do { my %seen; grep { !$seen{ trim($_ ) }++ } @goSource };
              my $usourcestr = join(',',@usources);

              if ($usourcestr ne ''){
					         # TODO: To consider better way to keep this
					         $descrField .= "Ontology_source=$usourcestr;";
				      }

			  }
      }


      #KEGG KO groups
      #The same thing here - protein_ortholog is quite big, so I will select kegg_groups first and then do select information about them.
      $selectString ="select distinct kegg_group_id from protein_ortholog where protein_id=$idItem";
      #print STDERR "G:".$selectString."\n";
      $results =$dbh->select_from_table($selectString);
      my @keggGroupId=();

      foreach my $item(@{$results}){
        push(@keggGroupId , $item->{'kegg_group_id'});
      }

      if(scalar @keggGroupId >0) {
        my $keggGroupString = join(',',@keggGroupId);
        $selectString =  "select db_id, definition, pathway from kegg_group where kegg_group_id in ($keggGroupString)";
        $results =$dbh->select_from_table($selectString);
        my $koGroup = $results->[0]->{'db_id'};
        my $koDefinition = $results->[0]->{'definition'};
        my $koPathway = $results->[0]->{'pathway'};
        if((defined $koGroup) && ($koGroup ne '')) {

         $descrField .= "ko_group=$koGroup;ko_definition=".escapeGFF($koDefinition).";";

         if ( trim( $koPathway ) ne '' ) {
           $descrField .= "ko_pathway=$koPathway;";
         }
        }
      }

      if ( $protName && $protName ne '' ) {
        print OUTFILE "##sequence-region $protName $start $stop\n";
      }

      if( $geneName ne '' ) {
        if ( ! $geneStore{$geneName} ) {
          # Avoid duplication of genes
          print OUTFILE "$genomicLocation\t.\tgene\t$genomicStart\t$genomicEnd\t.\t$strand\t.\tID=$geneName;\n";
          $geneStore{$geneName} = 1;
        }
      }

      ####### update 29/06/2017
      ### in the protein-based coordinates it should be plus strand, if other not specified.
      $strand='+';

      #updt 29/06/2017 added Parent field

      if ( $protName && $protName ne '' ) {
        print OUTFILE "$protName\t.\tpolypeptide\t$start\t$stop\t.\t$strand\t.\tID=$protName;Parent=$geneName;$descrField\n";
      }

      #blast hits TO CONSIDER
      #$selectString = "select hit_id, start, end, score, evalue, description from blast_hit where protein_id=$idItem";
      #$results =$dbh->select_from_table($selectString);
      #foreach my $result (@{$results})
      #{
      # my $blastStart = $result->{'start'};
      # my $blastEnd  = $result->{'end'};
      # my $blastScore = $result->{'score'};
      # my $blastEvalue = $result->{'evalue'};
      # my $hitId = $result->{'hit_id'};
      # my $descr = $result->{'description'};
      #my ($definition, $organism);
      #   ($definition, $organism)=$descr=~/^(.+?)\[(.+?)\]/;
      #  if(!defined $definition)
      #   {
      #     $definition = $descr;
      #     #($definition)=$descr=~/^(.+?)\>/;
      #    $organism="all";
      #   }
      # $definition =~s/[][><=:;|.]/ /g;
      # print OUTFILE "$protName\tNR\tBLAST_match\t$start\t$stop\t$blastEvalue\t$strand\t.\tName=Match;Target=$hitId $blastStart $blastEnd;score=$blastScore;Note=$definition;organism=$organism;\n";
      #}
      #domains
      $selectString =  "SELECT domain_name, rel_start, rel_end, db_xref, score, evalue,description,ip_desc, ip_id FROM domain where protein_id=$idItem order by db_xref";
      #print STDERR "D:".$selectString."\n";
      $results =$dbh->select_from_table($selectString);
      foreach my $result (@{$results}) {
       my $dbName = $result->{'db_xref'};
       my  $domainStart =$result->{'rel_start'};
       my $domainEnd = $result->{'rel_end'};
       my $evalue = $result->{'evalue'}||'.'; # Default for evalue
       if($evalue ne '.' and $evalue ne '-') {
         $evalue = sprintf("%.1e", $evalue);
       }
       my $ipID =$result->{'ip_id'};
       my $domainName =$result->{'domain_name'};
       my $descfield = $result->{'description'}||'';
       my $ipdesc = $result->{'ip_desc'}||'';

       my @descarr;
       if ( $descfield && $descfield ne '' ) {
       		push( @descarr, escapeGFF( $descfield ) );
       }
       if ( $ipdesc && $ipdesc ne '' && $ipdesc ne '-' ) {
      		push( @descarr, escapeGFF( $ipdesc ) );
       }

       my $description = join( ",", @descarr );

       #updt 29/06/2017 -added ID and Parent records

       $idInterPro++;

       if ( $protName && $protName ne '' ) {

        print OUTFILE "$protName\t$dbName\tprotein_match\t$domainStart\t$domainEnd\t$evalue\t$strand\t.\tName=$domainName;ID=InterProScan$idInterPro;";
        if( $ipID && $ipID ne '' && $ipID ne '-' ) {
      		print OUTFILE "interpro_id=$ipID;";
      	}
      	if($description && $description ne '') {
          print OUTFILE "interpro_note=$description;\n";
        } else {
          print OUTFILE "\n";
        }
       }

      }
      #NCBI conserved domains (CD) search results - hits and features
      #hits
      $selectString =  "SELECT accession, Superfamily,Hit_type, PSSM_ID, coordinateFrom, coordinateTo, E_Value, Bitscore, Short_name, Incomplete FROM cd_search_hit where protein_id=$idItem order by coordinateFrom";
      #print STDERR "C:".$selectString."\n";
      $results =$dbh->select_from_table($selectString);
      foreach my $result (@{$results}) {
         my $access = $result->{'accession'};
         my $superfamily =$result->{'Superfamily'};
         my $CDEnd = $result->{'coordinateTo'};
         my $CDStart = $result->{'coordinateFrom'};
         #my  $evalue = sprintf("%.1e", $result->{'E_Value'});
         my $evalue = $result->{'E_Value'};
         my $CDType =$result->{'Hit_type'};
         my $PSS =$result->{'PSSM_ID'};
         my $shortName =$result->{'Short_name'};
         my $Incomplete =$result->{'Incomplete'};

         #updt 29/06/17 added ID record and remove \" characters from fields
         $idCDSearchHit++;
         $CDStart=~s/\"//gi;
         $CDEnd=~s/\"//gi;
         $evalue=~s/\"//gi;

         if ( $protName && $protName ne '' ) {
           print OUTFILE "$protName\tCDsearch\tdomain_match\t$CDStart\t$CDEnd\t$evalue\t.\t.\tID=CDSearchHit$idCDSearchHit;Accession=$access;Superfamily=$superfamily;Short_name=$shortName;PSSM_ID=$PSS;Hit_type=$CDType;\n";
         }
        }
        #features
        $selectString =  "SELECT title, Type, coordinates,source_domain FROM cd_search_features where protein_id=$idItem";
        #print STDERR "F:".$selectString."\n";
        $results =$dbh->select_from_table($selectString);
        foreach my $result (@{$results}) {

          my $title = $result->{'title'};
          my $coordinates =$result->{'coordinates'};
          my $Type = $result->{'Type'};
          my $sourceDomain = $result->{'source_domain'};

          #updt 29/06/17 added ID record

          $idCDSearchFeat++;
          if ( $protName && $protName ne '' ) {
           print OUTFILE "$protName\tCDsearch\tfeature_match\t$start\t$stop\t.\t+\t.\tID=CDSeachFeat$idCDSearchFeat;Title=$title;Type=$Type;Coordinates=$coordinates;Source_domain=$sourceDomain;\n";
          }
        }

        #signalP, targetP features
        my @list=('signalP', 'targetP');
        foreach my $lItem (@list) {
          my $idKey = $lItem."_id";
          $selectString =  "SELECT distinct($idKey), start, end, class, score FROM $lItem where protein_id=$idItem";
          #print STDERR "F:".$selectString."\n";
          $results =$dbh->select_from_table($selectString);
          foreach my $result (@{$results}) {
           my $end =$result->{'end'};
           my $score = $result->{'score'};
           my $class = $result->{'class'};
           $end=~s/\"//gi;
           $start=~s/\"//gi;

           if ( $protName && $protName ne '' ) {

             my $classStr = "";

             if ( $class ne '' ) {
               $classStr = "Note=".$class.";";
             }

             # Toniher: Changed from SIGNAL to protein_match and also start despite it must be 1
             #print OUTFILE "$protName\t$lItem\tSIGNAL\t1\t$end\t$score\t.\t.\tID=".ucfirst($lItem)."_$protName;match=YES;\n";
             print OUTFILE "$protName\t$lItem\tprotein_match\t$start\t$end\t$score\t.\t.\tID=".ucfirst($lItem)."_$protName;match=YES;$classStr\n";
           }
          }
        } #signalP, targetP

  } #foreach protein item

 close(OUTFILE);

}

sub escapeGFF {
	# Ref: https://github.com/The-Sequence-Ontology/Specifications/blob/master/gff3.md

	my $string = shift;

	$string=~s/\;/%3B/g;
	$string=~s/\=/%3D/g;
	$string=~s/\&/%26/g;
	$string=~s/\,/%2C/g;

	return $string;
}
