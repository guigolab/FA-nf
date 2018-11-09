=head1 getResults.pm

=head2 Authors

=head3 Created by

              Anna Vlasova
              anna.vlasova@crg.es
              

=head2 Description
        
             This module is selecting data from different tables from the functional annotation database and creates different output files.
             
=head2 Example
  
            
=cut

package FunctionalAnnotation::getResults;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(printSummaryInfo printGoTerms makeAnnotatedVsNotAnnotatedPlot printDefinitionInfo);

use Data::Dumper;
#######################################################################
############## subroutines ############################################
#######################################################################

##################### SELECT INFO FROM DB ############################

sub getGOInformation
{
 my($protIdList, $dbh ) =@_;

 my %retData=();
 my $numberKeys =scalar @{$protIdList};
 my $condStat= ''; 
 if($numberKeys>0)
 {
  foreach my $item(@{$protIdList})
  {$item = "'$item'";}
  my $idString = join(',', @{$protIdList});
  $condStat = "where protein_id in (select distinct protein_id from protein where stable_id in ($idString))";
 }
  my $sqlSelect =  "SELECT protein_id, source FROM protein_go  where protein_id in (select distinct protein_id from protein where comment not like 'discarded%')  $condStat";
  print $sqlSelect."\n";
  my $results =$dbh->select_from_table($sqlSelect);
  #print Dumper($results);
  my ($protein_id, $key, $source);
  foreach my $result (@{$results}) 
  {
   $protein_id = $result->{'protein_id'};
   #print "$protein_id\n";
   $source = $result->{'source'};
   my @sourceType = split(/\s+/,$source);
   foreach my $item(@sourceType)
    { $retData{$protein_id}{'source_'.$item} = 1;}
  }

  return %retData;
}


sub printSummaryInfo
{
 my($protIdList, $dbh,$fileName ) = @_;

 
 my $numberKeys =scalar @{$protIdList};
 my $condStat= ''; 
 my $condStat2='';
 my($sqlSelect,$result,$resultNumber );
 if($numberKeys>0)
 {
  foreach my $item(@{$protIdList})
  {$item = "'$item'";}
  my $idString = join(',', @{$protIdList});
  #get protein_id for selected proteins = this will simplify selects from domain and other tables, sinci I will not use join.
  $sqlSelect= "SELECT protein_id from protein where stable_id in ($idString)";
  $results =$dbh->select_from_table($sqlSelect);
  my @tmpArray=();
  foreach my $result (@{$results})
  {
   push(@tmpArray, $result->{'protein_id'});
  }
  $idString = join(',', @tmpArray);
  $condStat = "where protein_id in ($idString)";
  $condStat2 = "and protein_id in ($idString)";
 }

 open(OUTPUT, ">$fileName")||die("Can't open $fileName for writing: $!\n");

 #get number of all proteins
  $sqlSelect = "select count(*) from protein $condStat";
 my $results =$dbh->select_from_table($sqlSelect);
 my $numberProteins = $results->[0]->{'count(*)'};
 if(defined $numberProteins && $numberProteins >0)
 {print OUTPUT "Number of proteins: $numberProteins\n";}

#get number for all genes
 $sqlSelect = "select count(distinct gene_id) from protein $condStat";
 $results =$dbh->select_from_table($sqlSelect);
 my $numberGenes = $results->[0]->{'count(distinct gene_id)'};
 if(defined $numberGenes && $numberGenes >0)
 {print OUTPUT "Number of genes: $numberGenes\n";}

#annotated vs not annotated
 my $propAnnot;
 $sqlSelect = "select count(*) from protein where status==1 $condStat2";
 $results =$dbh->select_from_table($sqlSelect);
 my $numberAnnotProteins = $results->[0]->{'count(*)'};
 if(defined $numberAnnotProteins && $numberAnnotProteins >0)
 {
  $propAnnot =sprintf("%.2f",$numberAnnotProteins*100/$numberProteins);
  print OUTPUT "Number of annotated proteins: $numberAnnotProteins ($propAnnot %)\n";
 }

#annotated vs not annotated in genes
 $sqlSelect = "select count(distinct gene_id) from protein where status==1 $condStat2";
 $results =$dbh->select_from_table($sqlSelect);
 my $numberAnnotGenes = $results->[0]->{'count(distinct gene_id)'};
 if(defined $numberAnnotGenes && $numberAnnotGenes >0)
 {
  $propAnnot =sprintf("%.2f",$numberAnnotGenes*100/$numberGenes);
  print OUTPUT "Number of annotated genes: $numberAnnotGenes ($propAnnot %)\n";
 }

 print OUTPUT '#' x40 ."\n". "Annotated features, proteins\n". '#' x40 ."\n";
 
#Proteins with definition
 $sqlSelect = "select count(distinct protein_id) from protein where (definition is not null or definition not like '') $condStat2";
 $results =$dbh->select_from_table($sqlSelect);
  $resultNumber = $results->[0]->{'count(distinct protein_id)'};
 if(defined $resultNumber && $resultNumber >0)
 {
  $propAnnot =sprintf("%.2f",$resultNumber*100/$numberProteins);
  print OUTPUT "Proteins with definition(name): $resultNumber ($propAnnot %)\n";
 }
 
 # TODO: To review all these tables
 #get proteins with domains and other features
 #$sqlSelect = "select protein_id from protein where protein_id in (select distinct protein_id from domain) $condStat2";
 my %dbHash=('domain'=>'InterPro domains',
             'blast_hit'=>'Blast hits',
             'protein_go'=>'GO terms',
             'protein_ortholog'=>'Ortholog signatures',
             'signalP'=>'SignalP signatures',
             'cd_search_hit'=>'Conserved domains(NCBI CDs)',
             'cd_search_features'=>'Conserved features(NCBI CDs)');


 foreach my $key(keys %dbHash)
 {
  $sqlSelect = "select count(distinct protein_id) from $key $condStat";
  $results =$dbh->select_from_table($sqlSelect);
  $resultNumber = $results->[0]->{'count(distinct protein_id)'};
  if(defined $resultNumber && $resultNumber >0)
  {
   $propAnnot =sprintf("%.2f",$resultNumber*100/$numberProteins);
   print OUTPUT "$dbHash{$key}: $resultNumber ($propAnnot %)\n";
  }
 }

 close(OUTPUT);
}

sub printDefinitionInfo
{
 my ($listIds, $dbh, $file)=@_;

 my $numberKeys =scalar @{$listIds};
 my $condStat='';
 if($numberKeys>0)
 {
  foreach my $item(@{$protIdList})
  {$item = "'$item'";}
  my $idString = join(',', @{$protIdList});
  $condStat = "and stable_id in ($idString)";
 }
 open(OUTPUT, ">$file")||die("Can't open $file for writing $!\n");
 print OUTPUT "#PROTEIN_NAME\tDEFINITION_SOURCE\tDEFINITION\n";
 my @defArray=();
 my $stbId;

 my $sqlSelect = "select protein_id, stable_id, definition from protein where definition is not null and definition not like '' $condStat";
 my $results =$dbh->select_from_table($sqlSelect);
 foreach my $result (@{$results})
  {
   @defArray=split(";",$result->{'definition'});
   $stbId=$result->{'stable_id'};
   foreach my $item (@defArray)
   {
    if($item=~/^blast2go\:(.+)$/)
     { print OUTPUT "$stbId\tBLAST2GO\t$1\n";}
    elsif($item=~/^KEGG\:(.+)$/)
     { print OUTPUT "$stbId\tKEGG\t$1\n";}
   }

  } 
 
 close(OUTPUT);
 return 1;
}


##################### PRINT GFF3 FILES ###############################

sub printDomains
{
 my($fileName, $domainsHash, $proteinHash)=@_;

 open(OUTFILE, ">$fileName")||die("Can't open $fileName for writing!\n$!");
 print OUTFILE "##gff-version 3\n";
 my ($proteinName,$dbName,$domainStart, $domainEnd,$evalue,$ipName,$description,$domainName);
 foreach my $pItem(sort { $a<=>$b} keys %{$domainsHash})
  {
   $proteinName = $proteinHash->{$pItem}{'protein_name'};
   print OUTFILE "##sequence-region $proteinName $proteinHash->{$pItem}{'start'} $proteinHash->{$pItem}{'end'}\n";
   print OUTFILE "$proteinName\t.\tpolypeptide\t$proteinHash->{$pItem}{'start'}\t$proteinHash->{$pItem}{'end'}\t.\t$proteinHash->{$pItem}{'strand'}\t.\tID=$proteinName\n";
   foreach my $kItem(sort dbxref_start_sort keys %{$domainsHash->{$pItem}})
   {
    $dbName = $domainsHash->{$pItem}{$kItem}{'db_xref'};
    $domainStart =$domainsHash->{$pItem}{$kItem}{'rel_start'};
    $domainEnd = $domainsHash->{$pItem}{$kItem}{'rel_end'};
    $evalue = sprintf("%.1e",$domainsHash->{$pItem}{$kItem}{'evalue'});
    $ipName =$domainsHash->{$pItem}{$kItem}{'ip_id'};
    $domainName =$domainsHash->{$pItem}{$kItem}{'domain_name'};
    $description =$domainsHash->{$pItem}{$kItem}{'descr'};
    print OUTFILE "$proteinName\t$dbName\tprotein_match\t$domainStart\t$domainEnd\t$evalue\t$proteinHash->{$pItem}{'strand'}\t.\tName=$domainName;Target=$proteinName;Note=$description;\n";
   }
  
  }
 close(OUTFILE);
}

###################### PRINT TAB-DELIMITED FILES #####################

sub printGoTerms
{
 my($protIdList,$fileName, $dbh,$param)=@_;

 my $numberKeys =scalar @{$protIdList};
 my $condStat= ''; 
 my $condStat2='';
 if($numberKeys>0)
 {
  foreach my $item(@{$protIdList})
  {$item = "'$item'";}
  my $idString = join(',', @{$protIdList});
  if($param eq 'protein')
   {$condStat = "stable_id in ($idString) and ";}
  else
   {$condStat = "protein.stable_id in ($idString) and ";}
  }

 if($param eq 'protein')
 {
  open(OUTPUT, ">$fileName")||die("Can't open $fileName for writing! $!\n");
  print OUTPUT "#PROTEIN_NAME\tGO_ACC\tGO_NAME\tGO_TYPE\n";
  my $sqlSelect = "select protein.protein_id,stable_id, go_acc, go_name, term_type from protein,protein_go,go_term where $condStat  protein.protein_id=protein_go.protein_id  and protein_go.go_term_id=go_term.go_term_id order by protein.stable_id";  
 
  $results =$dbh->select_from_table($sqlSelect);
  foreach my $result (@{$results}) 
  {
   print OUTPUT "$result->{'stable_id'}\t$result->{'go_acc'}\t$result->{'go_name'}\t$result->{'term_type'}\n";
  }
 close(OUTPUT);
} elsif($param eq 'gene'){

 open(OUTPUT, ">$fileName")||die("Can't opne $fileName for writing! $!\n");
 print OUTPUT "#GENE_NAME\tGO_ACC\n";

  my $sqlSelect = "select gene_name, GROUP_CONCAT(go_acc) as GO_acc from gene,protein,protein_go,go_term where $condStat  protein.protein_id=protein_go.protein_id  and protein_go.go_term_id=go_term.go_term_id and protein.gene_id=gene.gene_id group by gene_name order by gene_name";  
 
  $results =$dbh->select_from_table($sqlSelect);

  foreach my $result (@{$results}) 
  {   print OUTPUT "$result->{'gene_name'}\t$result->{'GO_acc'}\n";  }

 close(OUTPUT);

}

}


sub printBlastHit
{
 my($protIdList,$fileName, $dbh)=@_;

 my $numberKeys =scalar @{$protIdList};
 my $condStat= ''; 
 my $condStat2='';
 if($numberKeys>0)
 {
  foreach my $item(@{$protIdList})
  {$item = "'$item'";}
  my $idString = join(',', @{$protIdList});
  $condStat = "stable_id in ($idString) and ";
   }

 open(OUTPUT, ">$fileName")||die("Can't open $fileName for writing! $!\n");
 print OUTPUT "PROTEIN_NAME\thit_id\tscore\te-value\tpercent identity\tProtein length\tHit length\tHSP length\thit description\n";
 my $sqlSelect = "select protein.protein_id,stable_id, hit_id,score,evalue, percent_identity, length(sequence), length, hsp_length,description from protein,blast_hit where $condStat  protein.protein_id=blast_hit.protein_id  order by protein.protein_id,score DESC";  
 my  $results =$dbh->select_from_table($sqlSelect);
  foreach my $result (@{$results}) 
  {
   print OUTPUT "$result->{'stable_id'}\t$result->{'hit_id'}\t$result->{'score'}\t$result->{'evalue'}\t$result->{'percent_identity'}\t$result->{'length(sequence)'}\t$result->{'length'}\t$result->{'hsp_length'}\t$result->{'description'}\n";
  }
 close(OUTPUT);
}


##################### PRINT CHARTS AND DIAGRAMMS #####################
sub makeAnnotatedVsNotAnnotatedPlot
{
 my ($listIds, $plotFile, $dbh, $tmpFolder,$realBin,$specie)=@_;

 my $lengthFile1 = $tmpFolder."allProteins.withLength.txt";
 my $lengthFile2 = $tmpFolder."annotatedProteins.withLength.txt";
  my $lengthFile3 = $tmpFolder."notannotatedProteins.withLength.txt";

 my($sqlSelect, $results);
 my $sqlSelect1 = "select protein_id, stable_id, length(sequence) from protein";   
 my $sqlSelect2 = "select protein_id, stable_id, length(sequence) from protein where status=1";  
 my $sqlSelect3 = "select protein_id, stable_id, length(sequence) from protein where status=0";  

 my %fileHash=($lengthFile1=>$sqlSelect1,
             $lengthFile2=>$sqlSelect2,
             $lengthFile3=>$sqlSelect3);

 foreach my $item(keys %fileHash)
 {
  open(OUT, ">$item")||die("Can't open $item for writing $!\n");
  $sqlSelect = $fileHash{$item};
  $results =$dbh->select_from_table($sqlSelect);
  foreach my $result (@{$results}) 
  {
   print OUT "$result->{protein_id}\t$result->{'stable_id'}\t$result->{'length(sequence)'}\n"; 
  }
 close(OUT);
}

my $rScript=$realBin."/plotProtLengthDistribution.R";
my $commandString = "Rscript $rScript $lengthFile1 $lengthFile2 $lengthFile3 $plotFile '$specie'";
system($commandString)==0 or die("Error running system command: <$commandString>\n$!\n");

 unlink($lengthFile1);
 unlink($lengthFile2);
 unlink($lengthFile3);
}

############################ OTHER ###################################

sub dbxref_start_sort
{
 my ($a_first,$a_val) =$a=~/(\S+)\_(\d+)/;
 my ($b_first,$b_val) = $b=~/(\S+)\_(\d+)/;
#print $a_val;
return $b_first cmp $a_first || $a_val <=> $b_val;
}
1;