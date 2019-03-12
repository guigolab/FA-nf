=head1 uploadData

=head2 Authors

=head3 Created by

              Anna Vlasova
              vlasova dot av A gmail dot com
              Based on the scripts written by Guglielmo Roma

=head2 Description

             This module have method to upload sequence and annotation data into database

=head2 Example


=cut

package FunctionalAnnotation::uploadData;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(readListFile uploadFastaData checkGFFData uploadGFFData uploadGoAnnotation uploadBlastResults parseBlastResults parseAnnotation updateProteinDefinition parseInterProTSV uploadInterProResults uploadGOInfo updateAnnotationStatus parseCDsearchData uploadCDsearchData);

use FindBin qw($RealBin);
use lib "$RealBin/lib";
use Data::Dumper;
use FunctionalAnnotation::DB;
use Scalar::Util qw( looks_like_number );
use Text::Trim;
use Digest::SHA qw(sha1_hex);
#use Bio::SeqIO;
#use Bio::SearchIO;


#######################################################################
############## subroutines ############################################
#######################################################################

sub readListFile
{
 my $inFile = shift;
 my %returnData;

 open(INFILE, $inFile)||die "Can't open $inFile for reading! $!\n";
 while(my $line =<INFILE>)
 {
  chomp($line);
  $returnData{$line}=1;
 }
 close(INFILE);
return %returnData;
}

#
#
sub uploadFastaData
{
 my($inFile, $dbh, $idList, $do_update,$comment, $engine, $loglevel) =@_;

  if(!defined $engine){$engine ='mysql'};
 my $numberElements = scalar keys %{$idList}||'';
 my $processFlag = 'part';
 if($numberElements eq '')
   {$processFlag ='all';}


  #update 25/01/2018 -- Bioperl does not work anymore in CRG cluster, so I will need to substitute it. Actually, I use it only to read fasta sequence
  my %seqData=();
  my $prevSeq='';
  my $prevHeader='';
  my $headee='';

  open(IN, $inFile)||die "Cant read fasta file $inFile !\n$!\n";
   while(my $line=<IN>)
    {
      chomp($line);
      if($line=~/^\>(\S+)/)
      {
        $header=$1;
        if($prevSeq ne ''){
          $seqData{$prevHeader} = $prevSeq;
          $prevSeq='';
        }
        $prevHeader=$header;
      }
      else{
        $prevSeq .=$line;
      }
    }
  close(IN);
  $seqData{$prevHeader} = $prevSeq;


 #my $in = Bio::SeqIO->new(-file => "$inFile", '-format' => 'Fasta');

  my $commString ='';
 if(defined $comment && $comment ne '')
 {$commString = ", comment=\"$comment\""; }


 #while (my $seqio = $in->next_seq) {
 foreach my $seqKey (keys %seqData){
	#my $stable_id = $seqio->display_id;
  my $stable_id = $seqKey;

 #Small patch to Wheat genome - Francisco added protein length into the header of fasta sequence, now its look like 'NNN_186'
 #and pipeline recognize protein name as new one  even if protein with name NN is already in DB.
       #if($stable_id =~/^(TAES1a\S+)\_\d+$/)
       #  {$stable_id=$1;}
  #patch for the Lynx genome- New Tylers annotation contains transcript name and protein name in the header.
       #if($stable_id =~/^LYPA23B\d+T\S+\|(LYPA23B\S+)$/)
       #  {$stable_id=$1;}
 #patch for Turbot genome - and probably more general patch, since this new Tylers pipeline contains double header in fasta with peptide sequences.
       #if($stable_id =~/^[^|]+\d+T\S+\|(\S+)$/)
       #  {$stable_id=$1;}
 #patch for Pc2127 isolate, p.cucumerina genome = it contains '.' symbol in the middle of sequence.

   #print "STABLE id : $stable_id, $processFlag, $do_update\n";

	#my $seq = $seqio->seq;
  my $seq = $seqData{$seqKey};

#10/02/2016 Vlasova AV
#patch for comparing  annotations - it can be that the two sequences are differ from each other just by presence or absence stop codone *. from FA point of view, this sequences will remain the same,
#but sha1 checksum will be very different.
        my $seqString4SHA=$seq;
        $seqString4SHA=~s/\*$//;
	my $sha1 =   sha1_hex($seqString4SHA);

       if(($loglevel eq 'debug'))
	{print STDOUT "Stable_id $stable_id\nSequence $seq\n\n";}

	if(($processFlag eq 'all')||(exists $idList->{$stable_id})) {
		# check if protein already exists (yes && do_update => update record; no => insert new protein)
		my $protein_sql_select = qq{ SELECT protein_id FROM protein WHERE stable_id=\"$stable_id\" };
                my ($protein_sql_update, $protein_sql_insert);
                if($engine eq 'SQLite')
                   {
                    $protein_sql_update= qq{ UPDATE protein SET stable_id=\"$stable_id\",protein_name=\"$stable_id\",sequence=\"$seq\", sha1=\"$sha1\" $commString where stable_id=\"$stable_id\";};
		    $protein_sql_insert = qq{ INSERT INTO protein (protein_id,stable_id, protein_name, sequence,sha1,gene_id) VALUES (NULL,\"$stable_id\",\"$stable_id\",\"$seq\",\"$sha1\",0);};
                  }
               else
                   {
                    $protein_sql_update= qq{ UPDATE protein SET stable_id=\"$stable_id\",protein_name=\"$stable_id\",sequence=\"$seq\", sha1=\"$sha1\" $commString where stable_id=\"$stable_id\";};
		    $protein_sql_insert = qq{ INSERT INTO protein SET stable_id=\"$stable_id\",protein_name=\"$stable_id\",sequence=\"$seq\", sha1=\"$sha1\", gene_id="0" $commString;};
                   }


	#	my $protein_sql_update = qq{ UPDATE protein SET stable_id=\"$stable_id\",protein_name=\"$stable_id\",sequence=\"$seq\",gene_id=\"$gene_id\";};
       #		my $protein_sql_insert = qq{ INSERT INTO protein SET stable_id=\"$stable_id\",protein_name=\"$stable_id\",sequence=\"$seq\",gene_id=\"$gene_id\";};
             if(($loglevel eq 'debug'))
               {print "$protein_sql_insert\n$protein_sql_select\n$protein_sql_update\n";		}

		my $protein_id = $dbh->select_update_insert("protein_id", $protein_sql_select, $protein_sql_update, $protein_sql_insert, $do_update);
	}

   }#while
}#sub

#
#
#Note: here I assume that gff file is correct and soesnot contain errors, e.g. all genes and their transcript are at the same strand and so on. All genes definition is prior to cds definition!
# For checking correctness on the gff file there is another subroutine.

sub uploadGFFData
{
 my($inFile, $dbh, $idList,$do_update, $engine, $loglevel)=@_;

 my $numberElements = scalar keys %{$idList}||'';
 my $processFlag = 'part';
 if($numberElements eq '')
   {$processFlag ='all';}

if(! defined $engine){$engine = 'mysql';}
#idxs in file
my $contig_ix=0;
my $type_ix=2;
my $start_ix=3;
my $end_ix=4;
my $strand_ix=6;
my $ids_ix=8;

my($g_id, $gene_start, $gene_end, $gene_strand, $gene_name, $c_prot_id, $c_contig, $c_start, $c_strand, $start, $end);
my @elms;
my $duplicated=0;
$c_prot_id='';
#open file for parsing
open FH,"$inFile";
 while(<FH>) {
   next if /^#/;
    chomp;
    my $line=$_;
    #@elms=split/\t/,$line;
    @elms=split/\s+/,$line;
  if($elms[$type_ix] eq 'gene')
   {
    if($c_prot_id ne '')
     {
      #if there was some protein before, insert it into DB
      &insertProtein($c_prot_id, $c_contig, $start, $end, $c_strand, $g_id, $idList,$dbh, $engine,$loglevel);
      $c_prot_id='';
     }

    $gene_name=$1 if $elms[$ids_ix]=~/ID=(\w+)/;
 #patch for pc2127 isolate, p.cucumerina project - gene name contains . symbol in the name
  #if( $elms[$ids_ix]=~/ID=(PCUC.+)$/)
  #  {$gene_name=$1;}

    # check that this gene is not present in DB
     $duplicated=0;
     # check if there is already a gene with this gene_name in the DB
     my $selectString ="SELECT gene_id FROM gene WHERE gene_name=\"$gene_name\"";
    if(($loglevel eq 'debug'))
     {print "$selectString\n";}
     my @res= @{$dbh->select_from_table($selectString,$dbh)};
     # if YES, then do not insert
     if (scalar(@res)) {
     if(($loglevel eq 'debug')||($loglevel eq 'info'))
      {	print STDOUT "WARN: $gene_name already exists in the DB. Skipping\n"; }

  	$duplicated=1;
        $g_id = $res[0]->{'gene_id'};
     if(($loglevel eq 'debug'))
      {  print "GENE_ID: $g_id\n";}

        next;
      }
      # insert new gene
     $gene_strand=$elms[$strand_ix];
     $gene_start=$elms[$start_ix];
     $gene_end=$elms[$end_ix];
     my $gene_sql_insert;
    if($engine eq 'SQLite')
     {$gene_sql_insert = qq{ INSERT INTO gene(gene_id, gene_name,start,end,strand)  VALUES (NULL,\"$gene_name\", \"$gene_start\", \"$gene_end\", \"$gene_strand\");};}
    else
     { $gene_sql_insert = qq{ INSERT INTO gene SET gene_name=\"$gene_name\", start=\"$gene_start\", end=\"$gene_end\", strand=\"$gene_strand\";};}
   if(($loglevel eq 'debug'))
     {
      print STDOUT "$gene_sql_insert";
      print STDOUT "SQL CODE: $gene_sql_insert\n" if $duplicated==0;
    }

     $g_id =  $dbh->insert_set($gene_sql_insert,$dbh) if $duplicated==0;
    if(!defined $g_id)
     {
       my $select = &selectLastId( $engine );
       my $results = $dbh->select_from_table($select);
       #print Dumper($results);
       $g_id=$results->[0]->{'id'};
     }
    if(($loglevel eq 'debug'))
     { print "GENE_ID: $g_id\n";}
   }
   #elsif ($elms[$type_ix] eq 'CDS') {
#29/01/2016 - Francisco's annotation does not contain transcript field, but CDs
#14/09/2016 - Tyler's annotation contains both - transcript field and CDs, so there is a clear confusion - protein information is uploading twice.
# I need to check with CDs, if the prot_id is already present - just skip it.
#14/09/2016 - new Francisco's annotation contains mRNA field in combination with Name attribute
  elsif (($elms[$type_ix] eq 'transcript' )||($elms[$type_ix] eq 'mRNA' )||(($elms[$type_ix] eq 'CDS') && ( !$c_prot_id || $c_prot_id eq ''))) {
   my $prot_id='';
   $prot_id=$1 if $elms[$ids_ix]=~/Target=(\w+)/;
#update 18/11/2015
#In some annotation versions, provided by Tyler he added 'product' instead of Target... Parent is also exists, but it refer to the transcripts, not proteins
if($prot_id eq '')
      {   $prot_id=$1 if $elms[$ids_ix]=~/product\=([^;]+)/;}

if($prot_id eq '')
      {   $prot_id=$1 if $elms[$ids_ix]=~/Name\=([^;]+)/;}

#In some annotation versions, provided by Tyler, Target field is absent and only present Parent transcript id.
 if($prot_id eq '')
      {   $prot_id=$1 if $elms[$ids_ix]=~/Parent\=([^;]+)/;}


     if (!$c_prot_id || $c_prot_id eq '') {
	    $c_prot_id=$prot_id;
	    $c_contig=$elms[$contig_ix];
	    $c_strand=$elms[$strand_ix];
	    $start=$elms[$start_ix];
	    $end=$elms[$end_ix];
	} elsif ($c_prot_id eq $prot_id) {
           # if($c_strand eq '+')
	   #  {$end=$elms[$end_ix];}
           # else
             {$start = $elms[$start_ix];}
	    next;
	} elsif ($c_prot_id ne $prot_id) {
	    &insertProtein($c_prot_id, $c_contig, $start, $end, $c_strand, $g_id, $idList,$dbh,$engine,$loglevel);
	    $c_prot_id=$prot_id;
	    $c_strand=$elms[$strand_ix];
	    $c_contig=$elms[$contig_ix];
	    $start=$elms[$start_ix];
	    $end=$elms[$end_ix];
	}
    }
}
close FH;

#update tailing record
 &insertProtein($c_prot_id, $c_contig, $start, $end, $c_strand, $g_id, $idList,$dbh, $engine, $loglevel);

} #end sub


#
#
sub insertProtein
{
 my($c_prot_id, $c_contig, $start, $end, $c_strand, $g_id, $idList,$dbh, $engine,$loglevel) =@_;

 if(!defined $engine){$engine = 'mysql';}

 my $numberElements = scalar keys %{$idList}||'';
 my $processFlag = 'part';
 if($numberElements eq '')
   {$processFlag ='all';}

 my $duplicated=0;
 if(($processFlag eq 'all')||(exists $idList->{$c_prot_id}))
    {
     my $selectString = "SELECT protein_id FROM protein WHERE stable_id=\"$c_prot_id\"";
      #print "$selectString\n";
      my @res= @{$dbh->select_from_table($selectString)};
     # check if there is already a protein with this stable_id in the DB
      # if YES, then do not insert
      if (scalar(@res)) {
       if(($loglevel eq 'debug')||($loglevel eq 'info'))
  	{print STDOUT "NOTICE: $c_prot_id already exists in the DB. SKipping\n";}
 	$duplicated=1;
      }
      # insert new protein
      my $protein_sql_insert;
      if($engine eq 'SQLite')
      {
         $protein_sql_insert= qq{ INSERT INTO protein(protein_id, stable_id, seq_id, cds_start, cds_end, cds_strand,gene_id) VALUES (NULL,\"$c_prot_id\",\"$c_contig\",\"$start\",\"$end\",\"$c_strand\", \"$g_id\");};
      }
      else
      {
        $protein_sql_insert= qq{ INSERT INTO protein SET stable_id=\"$c_prot_id\", seq_id=\"$c_contig\", cds_start=\"$start\", cds_end=\"$end\", cds_strand=\"$c_strand\", gene_id=\"$g_id\";};
      }
      #print  "SQL CODE: $protein_sql_insert\n";
     if(($loglevel eq 'debug'))
      {  print STDOUT "SQL CODE: $protein_sql_insert\n" if $duplicated==0;}
      $dbh->insert_set($protein_sql_insert) if $duplicated==0;
     }

}


sub updateProteinDefinition
{
 my ($annotData,$dbh,$update,$source, $engine,$keyType, $loglevel)=@_;
 my $debugSQL = 1;
 my ($selectString,$res,$proteinId);
 my @protList=();
  
 foreach my $protItem(keys %{$annotData}) {
    #select protein_id from DB
    if($keyType eq 'protein_id')
    {$selectString = "SELECT d.protein_id, d.definition from protein p, definition d where p.protein_id=d.protein_id and p.protein_id = $protItem and d.source = '$source'";}
    else
    {$selectString = "SELECT d.protein_id, p.sha1, d.definition from protein p, definition d where p.protein_id=d.protein_id and p.stable_id like '$protItem' and d.source = '$source'";}
    $res = $dbh->select_from_table($selectString);
 
    if ( $#res < 0 ) {
 
      $definition = trim( join( " ", @{$annotData->{$protItem}{'annot'}} ) ); #TODO: Check quoting here
      $definition=~s/\s{2,}/ /g;
      
      my $insertString;
      if($keyType eq 'protein_id') {
       $insertString = "INSERT INTO definition SET definition =\"$definition\", source =\"$source\" where protein_id='$protItem';";
      } else {
        $selectString = "SELECT p.protein_id from protein p where p.stable_id like '$protItem';";
        $res = $dbh->select_from_table($selectString);
        if ( $#$res >= 0 ){
         $proteinId=$res->[0]->{'protein_id'};
         $insertString = "INSERT INTO definition SET definition =\"$definition\", source =\"$source\", protein_id='$proteinId';";
        }
      }
     if(($loglevel eq 'debug'))
     { print "$insertString\n";}
      $dbh->insert_set($insertString);
      
   } else {
     
      if(($loglevel eq 'debug')||($loglevel eq 'info'))
      {  print STDERR "There is no protein_id for $protItem, skipped!\n";}
       next;
       
    }
 }

return 1;
}

#
#
sub uploadGoAnnotation
{
 my ($annotData,$dbh,$update,$source, $engine, $loglevel)=@_;

# print "INSIDE upload Go\n'$debugSQL'\n"; die;
 my $debugSQL = 1;
 my ($selectString, $insertString, $uploadString,$res,$proteinId,$goId,$proteinGoId,$sourceInDB,$b2gDefinition,$shaData);
 my @protList=();
 foreach my $protItem(keys %{$annotData})
  {
    #select protein_id from DB
    $selectString = "SELECT protein_id, sha1 from protein where stable_id like '$protItem'";
   if(($loglevel eq 'debug')){   print "SQL:$selectString\n";}
    $res = $dbh->select_from_table($selectString);
    $proteinId=$res->[0]->{'protein_id'};
    $shaData=$res->[0]->{'sha1'};

    if(!defined $proteinId)
     {
      if(($loglevel eq 'debug')||($loglevel eq 'info'))
       {print STDERR "There is no protein_id for $protItem, skipped!\n";}
       next;
     }

    my @goList = &uniqueValues(\@{$annotData->{$protItem}{'annot'}});
    foreach my $goItem(@goList)
    {
      #select go_term_id: if this go is present then select id, otherwise upload it.
      if($engine eq 'SQLite')
         {
          $insertString = qq{INSERT INTO go_term (go_term_id,go_acc) VALUES (NULL,\"$goItem\");};
         }
        else
          {
           $insertString = "INSERT INTO go_term SET go_acc=\"$goItem\"";
          }

       $selectString = "SELECT go_term_id FROM go_term where go_acc like '$goItem'";
       $updateString = '';

       $goId = $dbh->select_update_insert("go_term_id", $selectString, $updateString, $insertString, 0);
       if(!defined $goId)
       {
        my $select = &selectLastId( $engine );
        my $results = $dbh->select_from_table($select);
        #print Dumper($results);
        $goId=$results->[0]->{'id'};
      }#if

       #print "$selectString\n$insertString\n";
      #insert protein_go record
       $selectString = "SELECT protein_go_id, source FROM protein_go where go_term_id=$goId and protein_id=$proteinId and source=\"$source\"";
       #print "$selectString\n";
       $res = $dbh->select_from_table($selectString);
       if ( $#res < 0 )
       {
        if($engine eq 'SQLite')
      {$insertString =  "INSERT INTO protein_go(protein_go_id,go_term_id,protein_id,source) VALUES(NULL,\"$goId\",\"$proteinId\", \"$source\")";}
        else
        {$insertString = "INSERT INTO protein_go SET go_term_id=$goId, protein_id=$proteinId, source=\"$source\"";}
       if(($loglevel eq 'debug')){        print "$insertString\n";}
        $proteinGoId = $dbh->insert_set($insertString);
       }
   #die;
  } #foreach $goItem

 }#foreach $proteinItem
}#sub


sub uploadInterProResults
{
 my ($dbh, $ipscanHash, $engine)= @_;

 my $update =0;
 my ($protValue,$inputseq_id, $checksum, $length, $method, $dbentry, $dbdesc, $start, $end, $evalue, $status, $date, $ip_id, $ip_desc, $go) ;

 my %retGOData=();

 foreach my $protKey(keys %{$ipscanHash})
 {
 #retrive sequence and reference_gene_id once more from DB for new inputseq_id  data
  $select = "select protein_id,sequence from protein where stable_id like '$protKey'";
  $results = $dbh->select_from_table($select);
  my $sequence = $results->[0]{'sequence'};
  my $protId = $results->[0]{'protein_id'};

 #check that domains are not present for this protein in the domain table. If there are domains and update flag is 0 (do not do update) then skip this protein and pass to the next one.
  $select = "select count(*) from domain where protein_id in (select distinct protein_id from protein where stable_id like '$protKey')";
 # print "$select";
  $results = $dbh->select_from_table($select);
  my $countSeqs = $results->[0]{'count(*)'};
  
  # Toniher 2019-01-19: Recover countSeqs
  if($countSeqs>0)
  {
   next;
  }
  
  #  next if $updateFlag==0;

  #if updateFlag ==1
   #delete from ipscn_version first (?)
   #$delete = "delete from ipscn_version where domain_id in (select distinct domain_id from)";
  # }

  foreach my $countKey(keys %{$ipscanHash->{$protKey}})
    {
      $start = $ipscanHash->{$protKey}{$countKey}{'start'};
      $end = $ipscanHash->{$protKey}{$countKey}{'end'};
      $method = $ipscanHash->{$protKey}{$countKey}{'method'};
      $length = $ipscanHash->{$protKey}{$countKey}{'length'};
      $dbentry =$ipscanHash->{$protKey}{$countKey}{'dbentry'};
      $dbdesc = $ipscanHash->{$protKey}{$countKey}{'dbdesc'};
      $evalue = $ipscanHash->{$protKey}{$countKey}{'evalue'};
      $status = $ipscanHash->{$protKey}{$countKey}{'status'};
      $date = $ipscanHash->{$protKey}{$countKey}{'date'};
      $ip_id = $ipscanHash->{$protKey}{$countKey}{'ip_id'}||'';
      $ip_desc = $ipscanHash->{$protKey}{$countKey}{'ip_desc'}||'';
      $go = $ipscanHash->{$protKey}{$countKey}{'go'}||'';

 #    my $domain_sequence = substr ($sequence, $start - 1, ($end - $start + 1));
#The " symbol create a lot of problems! lets better remove it!
     #$dbdesc =~s/\"/\\\"/g;
     $dbdesc =~s/\"//g;

      my %domain;
      $domain{'protein_id'} = $protId;
      $domain{'db_xref'} = $method;
      $domain{'domain_name'} = $dbentry;
      $domain{'description'} = $dbdesc;
      $domain{'rel_start'} = $start;
      $domain{'rel_end'} = $end;
      $domain{'sequence'} = substr ($sequence, $start - 1, ($end - $start + 1));
      # TODO: Ensure this applies for more cases
      $domain{'evalue'} = &handleValue( $evalue, "evalue" );
      $domain{'ip_id'} = $ip_id;
      $domain{'ip_desc'} = $ip_desc;
      $domain{'go'} = $go;

# insert domain
    my $domain_id;
  if ($engine eq 'SQLite')
   { $domain_id = &insert_set_sqlite($dbh, 'domain',\%domain);	}
  else
   {	my $st_domain = &constructStatment(\%domain);
	$domain_id = &insert_set($dbh, $st_domain, 'domain');
   }
#insert ipscan version
#update 14/02/2018 -- I dont need interproscan version for now
  #    my %ipscn;
  #    $ipscn{'domain_id'} = $domain_id;
  #    $ipscn{'ipscn_version'} =$iprscnVersion;
  #    my $ipscn_id;
  #    if ($engine eq 'SQLite')
  #    { $ipscn_id = &insert_set_sqlite($dbh, 'ipscn_version',\%ipscn);	}
  #    else
  #    {
  #     my $st_ipscn = &constructStatment(\%ipscn);
  #     $ipscn_id = &insert_set($dbh, $st_ipscn, 'ipscn_version');
  #    }

#Vlasova A. 16-01-2013
#insert go information into go_term table and then into protein_go
  $go =~s/^\s+//;
  $go =~s/\s+$//;
  my @goList=split(/\|/, $go);
  # Toniher. 2019-01-18. Changed key from go to annot, so it can be imported back
  push(@{$retGOData{$protKey}{'annot'}}, @goList);

  }#foreach count key


 }#for each protein

return \%retGOData;
}

sub uploadBlastResults
{
 my ($dbh, $blastData, $engine, $loglevel)= @_;
 my $update =0;

 my %tmpHash=();
 my($selectString, $updateString, $insertString,$proteinId,$blastHitId,$shaData);

 foreach my $protItem(keys %{$blastData})
 {
  #select proteinId from protein table
   $selectString = "SELECT protein_id,sha1 from protein where stable_id like '$protItem'";
    $res = $dbh->select_from_table($selectString);
    $proteinId=$res->[0]->{'protein_id'};
    $shaData=$res->[0]->{'sha1'};
    if(!defined $proteinId)
     {
       if(($loglevel eq 'debug')||($loglevel eq 'info')){ print "There is no protein_id for $protItem, skipped!\n";}
       next;
     }

   for(my $i=0; $i<scalar @{$blastData->{$protItem}}; $i++)
    {
     #print Dumper($blastData->{$protItem}[$i]);
     #die;
     %tmpHash = %{$blastData->{$protItem}[$i]};
     my @keyList = keys %tmpHash;
     my $setString='';
     my @setData=();
     my @setValues=();
     foreach my $keyItem(@keyList)
      {
       next if $keyItem eq 'hit_id';
       push(@setValues, $keyItem);
       if($engine eq 'SQLite')
       {push(@setData, "\"$tmpHash{$keyItem}\"");}
       else
        {push(@setData, "$keyItem = \"$tmpHash{$keyItem}\"");}
      }
     $setString = join(', ', @setData);
     my $setValuesString = join(',', @setValues);

     if($engine eq 'SQLite')
      {$insertString = "INSERT INTO blast_hit(blast_hit_id, protein_id, hit_id, $setValuesString) VALUES(NULL,\"$proteinId\", \"$tmpHash{'hit_id'}\",$setString)"; }
     else
      {$insertString = "INSERT INTO blast_hit SET protein_id=$proteinId, hit_id=\"$tmpHash{'hit_id'}\",$setString ";}
     $selectString = "SELECT blast_hit_id from blast_hit where protein_id=$proteinId and hit_id=\"$tmpHash{'hit_id'}\"";
     $updateString = "UPDATE blast_hit SET $setString where protein_id=$proteinId and hit_id=\"$tmpHash{'hit_id'}\"";
   if(($loglevel eq 'debug')){
     print $selectStrinng."\n";
     print $insertString."\n";
     print $updateString."\n";
   }
     $blastHitId = $dbh->select_update_insert("blast_hit_id", $selectString, $updateString, $insertString, $update);
    }#foreach blast result

  } #foreach protein_id

} #sub

sub uploadGOInfo
{
 my ($dbh, $ontologyFile)=@_;

 if(!-e $ontologyFile)
  {print "Please provide ontology file in obo format!\nOtherwise information about GO terms will be incomplete!\n"; exit();}

 my %goData=&parseOboFile($ontologyFile);

 my %goTermAcc =();

 my $selectString = "SELECT distinct go_acc from go_term where go_name is NULL";
 #print "SQL_CODE:$selectString\n" if $debug==1;
 my $results = $dbh->select_from_table($selectString);
 foreach my $result (@{$results})
   {
    $goTermAcc{$result->{'go_acc'}}{'acc'}=1;
   }


 my $updateString='';
 foreach my $item(keys %goTermAcc)
 {
  if(!exists $goData{$item})
   {next;}
  $updateString = "UPDATE go_term set go_name = \"$goData{$item}{'name'}\", term_type=\"$goData{$item}{'type'}\" where go_acc like '$item'";
  #print "SQL_CODE:$updateString\n" if $debug==1;
  $dbh->update_set($updateString);
 }

return 1;
}


sub updateAnnotationStatus
{
 my $dbh=shift;
 #annotation status can be either 0 = not annotated, or 1 - annotated. Status==1 setting up when there is at least one hit from any
 # source of evidence was used for annotation.

 #lets reset to zero status any of the protein in DB
  my $updateString = "UPDATE protein set status = 0";
if(($loglevel eq 'debug')){   print "SQL_CODE:$updateString\n";}
  $dbh->update_set($updateString);

 #then lets go through all tables and update status to 1 in case if protein had a record in selected table_name
 #definition blast2go and kegg
  $updateString = "UPDATE protein set status = 1 where definition is not null and definition not like ''";
 if(($loglevel eq 'debug')){  print "SQL_CODE:$updateString\n" ;}
  $dbh->update_set($updateString);
#blast hits, interpro domains and keggs
#my @tableList = qw(blast_hit domain protein_ortholog signalP);
my @tableList = qw(domain protein_ortholog signalP);
 foreach my $dbItem(@tableList)
 {
   $updateString = "UPDATE protein set status = 1 where protein_id in (select distinct protein_id from $dbItem )";
  if(($loglevel eq 'debug')){  print "SQL_CODE:$updateString\n";}
   $dbh->update_set($updateString);
 }

 return 1;
}

sub uploadCDsearchData
{
 my ($dbh, $dataHash,$engine, $type)=@_;

 my($select, $result,$table,$tableId ,$selectString, $insertString, $updateString,$uniqField,$fieldName);

 foreach my $protItem (keys %{$dataHash})
 {
  $select = "select protein_id from protein where stable_id like '%$protItem%'";
  my $sth2 = $dbh->prepare($select);
  $sth2->execute();
  my $proteinId = $sth2->fetchrow()||'';
  $sth2->finish();
  
  #$results = $dbh->select_from_table($select);
  #my $proteinId = $results->[0]{'protein_id'};

  #foreach result line - do its uploading
  for(my $i=0; $i<scalar @{$dataHash->{$protItem}}; $i++)
    {
     %tmpHash = %{$dataHash->{$protItem}[$i]};

     my @keyList = keys %tmpHash;
     my $setString='';
     my @setData=();
     my @setValues=();
     foreach my $keyItem(@keyList)
      {
       next if ($keyItem eq 'Accession' && $type eq 'h');
       next if ($keyItem eq 'Title' && $type eq 'f');

       push(@setValues, $keyItem);
       if($engine eq 'SQLite')
        {push(@setData, "\"$tmpHash{$keyItem}\"");}
       else
        {push(@setData, "$keyItem = \"$tmpHash{$keyItem}\"");}
      }
     $setString = join(', ', @setData);
     my $setValuesString = join(',', @setValues);

     if($type eq 'h')
      {
        $table = 'cd_search_hit';
        $tableId = 'cd_search_hit_id';
        $uniqField ='accession';
        $fieldName = 'Accession';
      }
     elsif($type eq 'f')
      {$table = 'cd_search_features';
       $tableId = 'cd_search_features_id';
       $uniqField='title';
       $fieldName = 'Title';
      }

     if($engine eq 'SQLite')
      {$insertString = "INSERT INTO $table ($tableId, protein_id, $uniqField, $setValuesString) VALUES(NULL,\"$proteinId\",\"$tmpHash{$fieldName}\",$setString)"; }
     else
      {$insertString = "INSERT INTO $table SET protein_id=$proteinId,$setString ";}

     $selectString = "SELECT $tableId from $table where protein_id=$proteinId and $uniqField=\"$tmpHash{$fieldName}\"";
     $updateString = "UPDATE $table SET $setString where protein_id=$proteinId and $uniqField=\"$tmpHash{$fieldName}\"";
    if(($loglevel eq 'debug')){   print $insertString."\n".$updateString."\n";}
     $blastHitId = $dbh->select_update_insert("blast_hit_id", $selectString, $updateString, $insertString, $update);

    }#foreach result line - each domain or feature, do its uploading

 }#foreach protein item
}


################################################################
################### Parsing files ##############################
################################################################
sub parseCDsearchData
{
 my ($file, $type)=@_;

 my %returnData=();

 my @fields=();
 my @data=();
 my $mainField='';
 my $idData='';

 $mainField = 'Query';

 my %tmpHash=();

 open(INPUT, $file) || die("Can't open $file for reading !$!\n");
 while(my $line=<INPUT>)
  {
   chomp($line);
   if($line eq ''){next;}
   if($line=~/^\#/){next;}
   if($line=~/^Query/)
    {
    @fields=split(/\t+/,$line);
    #substitute spaces for '_' characters
    foreach my $item(@fields)
     {
      $item=~s/\s+/\_/gi;
      $item=~s/\-/\_/gi;
      if($item eq 'To' || $item eq 'From')
      {$item='coordinate'.$item;}
     }
    next;
    }
   @data = split(/\t+/,$line);
   %tmpHash=();

   if(scalar @data != scalar @fields)
    {
     #Loop features does not contain coordinate field in the resulting line, and have 1 column less. Unfortunately, this column is in the middle, so I would need to assign
     #field names and their values by hand. !Temporary solution!
     if($type eq 'f')
      {
       print "Warning: unusial feature, most probably does not contain coordinate column. Assigned by hands '$line'\n";
       $idData=$data[0];
       $idData =~s/.+\>(.+)$/$1/;
       $tmpHash{'Type'} = $data[1];
       $tmpHash{'Title'} = $data[2];
       $tmpHash{'coordinates'} = '';
       $tmpHash{'complete_size'} = $data[3];
       $tmpHash{'mapped_size'} = $data[4];
       $tmpHash{'source_domain'} = $data[5];
       push(@{$returnData{$idData}}, {%tmpHash});
      }
     else
     {     print "Error: Problem in parsing $file file! Number of fields in data line is not the same as in header line! '$line'\n"; }
     next;
   }

   for(my $i=0; $i<scalar @data; $i++)
    {
     if($fields[$i] eq $mainField)
      {
       $idData=$data[$i];
       #NCBI cut sequence id name from the left side (beginning) if it is longer then 8 characters and substitute deleted part by the '>' symbol. Need to delete this symbol:
       $idData=~s/.+\>(.+)$/$1/;
       #latest version of CDsearch adds additional information to the id in brackets, like >Ode2a024285P1[Ode2a024285P1]
       if($idData =~/^([^[]+)\[/)
       {$idData=$1;}
      }
     else
      {$tmpHash{$fields[$i]} =$data[$i];}
    }
   push(@{$returnData{$idData}}, {%tmpHash});
  }
 close(INPUT);
 return %returnData;
}

sub parseOboFile
{
 my $fileName =shift;
 my %data=();

 my($acc, $name, $type);
 my @altId=();
 open(INPUT, $fileName) ||die "Can't open $fileName for reading!\n$!";
 while(my $line=<INPUT>)
 {
  chomp($line);
  if($line=~/^id\:\s+(GO\:\d+)\s*$/)
   {
    $acc=$1;
    @altId=();
   }
  if($line=~/^alt\_id\:\s+(GO\:\d+)\s*$/)
   {
   # push(@altId,$1);
    $data{$1}{'name'}=$name;
    $data{$1}{'type'}=$type;
   }
  elsif($line=~/^name:\s+(.+)$/)
   {
    $name=$1;
    $data{$acc}{'name'}=$name;
   }
  elsif($line=~/^namespace\:\s+(.+)$/)
   {
    $type=$1;
    $data{$acc}{'type'}=$type;
   }

 }
 close(INPUT);
 return %data;
}

sub parseAnnotation
{
 my ($fileName) = shift;
 my %returnData=();

 my ($proteinName, $annotTerm);
 open(INFILE, $fileName)||die("Can't open $fileName for reading!$!\n");
 while(my $line=<INFILE>)
  {
   chomp($line);
   ($proteinName, $annotTerm)=$line=~/^(\S+)\s+(\S.*)\s*/;
   
   if ( $annotTerm eq '#' ) {
    
    ($proteinName, $annotTerm)=$line=~/^(\S+)\s+\#\s+(\S.*)\s*/;
    
   }

#some patch - new Lynx annotation had transcript name within protein name: LYPA23B012832T1|LYPA23B012832P1 I need only the second part, not the first one:
        # $proteinName=~s/LYPA[^|]+\|(.+)/$1/;

#some patch for stable_id in general - in new Tylers pipeline transcript names are included into fasta header. If they were not removed at the stage of uploding data to kaas server,
#then resulting file contains something like 'TranscriptName|ProteinName'
 if($proteinName =~/^[^|]+\d+T\S+\|(\S+)$/)
      {$proteinName=$1;}

#another patch - Wheat proteins from fasta file (that was used for kegg web search) have additional protein length in it., need to remove it/
#  $proteinName=~s/^(TAES1a\S+)\_\d+$/$1/;
 if($proteinName =~/([^_]+)\_\d+/)
 {$proteinName=$1;}

# Let's ensure everything uploaded should be OK
  if ( $proteinName && $annotTerm ) {

    push(@{$returnData{$proteinName}{'annot'}}, $annotTerm);

  }
   
   #if($line=~/\S+\s+\S+\s+(.+)$/)
   # {push(@{$returnData{$proteinName}{'definition'}}, $1); }

  }
 close(INFILE);
 return %returnData;
}


sub parseBlastResults
{
 my $fileName = shift;
 my %returnData=();
 my $prevProtId = '';
 my %tmpHash=();

 my $blastFormat='blast';
#get first line of the input file to get blast format
 open(IN, $fileName)||die "Can't open $fileName for reading ! $!\n";
 my $line=<IN>;
 close(IN);

# xml format -m 7 option
 if($line=~/^\<\?xml/)
  {$blastFormat = 'blastxml';}
#tabular format -m 9 option
elsif($line=/^\#\s+/)
  {$blastFormat = 'blasttable';}

#tabular format -m 8 == 12 columns
#other formats - 3 or 4 columns - hashtag(in m -9), program, version, release
 my @tmp=split(/\s+/,$line);
 if(scalar @tmp > 4)
  {$blastFormat = 'blasttable';}

 if(($loglevel eq 'debug')){  print "blastFormat: $blastFormat\n";}


my $in = new Bio::SearchIO(-format => $blastFormat,
                           -file   => $fileName);
while( my $result = $in->next_result ) {
  ## $result is a Bio::Search::Result::ResultI compliant object
  while( my $hit = $result->next_hit ) {

    %tmpHash=();
    ## $hit is a Bio::Search::Hit::HitI compliant object
     my $hsp = $hit->next_hsp ;
      #queryName == proteinId
         my $queryName = $result->query_name;
      #print "Query name: $queryName\n";
      #some patch - new Lynx annotation had transcript name within protein name: LYPA23B012832T1|LYPA23B012832P1 I need only the second part, not the first one:
       # $queryName=~s/LYPA[^|]+\|(.+)/$1/;
    #another patch - Wheat proteins from fasta file (that was used for kegg web search) have additional protein length in it., need to remove it/
      # $queryName=~s/^(TAES1a\S+)\_\d+$/$1/;
#some patch for stable_id in general - in new Tylers pipeline transcript names are included into fasta header. If they were not removed at the stage of uploding data to kaas server,
#then resulting file contains something like 'TranscriptName|ProteinName'
 #if($queryName =~/^[^|]+\d+T\S+\|(\S+)$/)
 #        {$queryName=$1;}

      #subject == hit in NR
         my $subjectName= $hit->name;
         my $subjectAcc = $hit->accession;
         my $start =  $hsp->start('hit');
         my  $stop = $hsp->end('hit');
         my  $identity =  $hsp->percent_identity;
         my $score =  $hsp->score;
         my $evalue = $hsp->evalue;
         my $description = $hit->description;
         #need to remove '"' characters from all text fields - they couse an uploading problem afterwards.
         $description=~s/\"//gi;
         $subjectAcc=~s/\"//gi;
         $tmpHash{'hit_id'} = $subjectAcc;
         $tmpHash{'evalue'} =$evalue;
         $tmpHash{'score'} = $score;
         $tmpHash{'percent_identity'} = sprintf("%.2f", $identity);
         $tmpHash{'hsp_length'} = $hsp->hsp_length;
         $tmpHash{'length'} = $hit->length;
         $tmpHash{'start'} = $start;
         $tmpHash{'end'} =$stop;
         $tmpHash{'description'} = $description;
         push(@{$returnData{$queryName}}, {%tmpHash});
    #print "$description\n";
  }
 }
 return %returnData;
}


sub parseInterProTSV
{
 my $inputFile = shift;

 my %ipscanHash =();
my $count=0;
my @inputIds =();
 my ($protValue,$inputseq_id, $checksum, $length, $method, $dbentry, $dbdesc, $start, $end, $evalue, $status, $date, $ip_id, $ip_desc, $go) ;
open (FILE, $inputFile) || die "Can't open $inputFile for reading! $!\n";
 while (defined (my $line=<FILE>)) {
  chomp($line);
 ($protValue, $checksum, $length, $method, $dbentry, $dbdesc, $start, $end, $evalue, $status, $date, $ip_id, $ip_desc, $go) = split(/\t/, $line);

@inputIds=();

#here is a problem for NCBI annotation - there ids are contains '|' character, but at the same time this symbol separate exactly the same proteins
#update 9/03/2016
 if(($protValue =~/\|/) && ($protValue !~/^gi\|/)     )
 {@inputIds = split(/\|/,$protValue);}
 else
  {push(@inputIds, $protValue);}
#some patch for Lynx new annotation - it has transcript name within protein name: LYPA23B012832T1|LYPA23B012832P1 I need only the second part, not the first one:
#Interesting - how it will work for normal sets?
#my @tmp;
#for(my $i=0; $i<scalar @inputIds; $i++)
# {
#  push(@tmp, $inputIds[$i]);
#}
#then I need only unique ids
#@inputIds = @tmp;

foreach my $inputseq_id(@inputIds)
 {
 #some genomic annotations, produced by Tyler have transcript name within protein name.But at the same time  Interpro collapsed similar proteins into one line, separate them with | tag.
#So I need to skip transcripts, but keep information about proteins.
 #if($inputseq_id=~/T\d+$/){next;}

#another patch - Wheat proteins from fasta file (that was used for kegg web search) have additional protein length in it., need to remove it/
 #$inputseq_id=~s/^(TAES1a\S+)\_\d+/$1/;

  $ipscanHash{$inputseq_id}{$count}{'checksum'} = $checksum;
  $ipscanHash{$inputseq_id}{$count}{'length'} = $length;
  $ipscanHash{$inputseq_id}{$count}{'method'} = $method;
  $ipscanHash{$inputseq_id}{$count}{'dbentry'} = $dbentry;
  $ipscanHash{$inputseq_id}{$count}{'dbdesc'} = $dbdesc;
  $ipscanHash{$inputseq_id}{$count}{'start'} = $start;
  $ipscanHash{$inputseq_id}{$count}{'end'} = $end;
  $ipscanHash{$inputseq_id}{$count}{'evalue'} = $evalue;
  $ipscanHash{$inputseq_id}{$count}{'status'} = $status;
  $ipscanHash{$inputseq_id}{$count}{'date'} = $date;
  $ipscanHash{$inputseq_id}{$count}{'ip_id'} = $ip_id;
  $ipscanHash{$inputseq_id}{$count}{'ip_desc'} = $ip_desc;
  $ipscanHash{$inputseq_id}{$count}{'go'} = $go;
  $count++;
 }
}
close(FILE);

return %ipscanHash;
}


################################################################
################### Other subs #################################
################################################################

sub checkGFFData
{
 my $inFile = shift;
 my $returnData =1;

 my($transcriptDirection, $exonDirection);
 my @tmp=();
 my $count=0;
 open(INFILE, $inFile)||die "Can't open $inFile for reading! $!\n";
 while(my $line =<INFILE>)
 {
  $count++;
  chomp($line);
  next if $line=~/^#/;
  @tmp=split(/\t/, $line);
  if($tmp[2] eq 'gene')
   {
    $transcriptDirection =$tmp[6];
    #print "$line\n $transcriptDirection\n";
    if($tmp[8]!~/ID\=/)
     {
      if(($loglevel eq 'debug')||($loglevel eq 'info')){  print STDOUT  "Line $count: gene description does not contain ID!\n$line\n";}
      $returnData=0;
     }
  }
 elsif($tmp[2] eq 'CDS' )
  {
   $exonDirection = $tmp[6];
   if($transcriptDirection ne $exonDirection)
   {
    if(($loglevel eq 'debug')||($loglevel eq 'info')){ print STDOUT "Line $count: strand of the transcript is contrary to  ones in the gene!\n $line\n";}
    $returnData = 0;
   }
   if($tmp[8] !~/Target\=/)
   {
     if(($loglevel eq 'debug')||($loglevel eq 'info')){ print STDOUT  "Line $count: CDS description doesnot contain Target!\n$line\n";}
      $returnData=0;
   }
  }
 }#while

close(INFILE);

 return $returnData;
}




# subroutine select only unique values from the input list. For now order is not important for me, thats why I do not keep it.
sub uniqueValues
{
 my $list = shift;
 my @returnData=();
 my %tmpHash=();

 foreach my $item(@{$list})
  {
   $tmpHash{$item}=1;
  }
 @returnData = keys %tmpHash;

 return @returnData;
}


sub insert_set_sqlite {
    my ($dbh, $table_name, $dataHash) = @_;
    if(!defined $loglevel){$loglevel=1;}
    #prepare insert string
    my @fields = keys %{$dataHash};
    my @values;
    foreach my $field(@fields)
     {
      push(@values, "\"$dataHash->{$field}\"");
     }
    my $fieldString = join(',', @fields);
    my $valueString = join(',', @values);
    my $insString = "INSERT INTO $table_name($fieldString) VALUES($valueString)";
    if(($loglevel eq 'debug')){ print STDERR "### doing insert  $insString ###\n";}
    my $sth = $dbh->prepare_stmt($insString);
    $sth->execute() || warn "insert failed : $DBI::errstr";
    my $select = &selectLastId( "sqlite" );
    my $results = $dbh->select_from_table($select);
    #print Dumper($results);
    my $dbi=$results->[0]->{'id'};
    return $dbi;
}

sub insert_set {
    my ($dbh, $stmt, $table_name) = @_;
    #print "here" . $stmt . "\n";
    my $s = "INSERT INTO $table_name SET  $stmt";
    if(($loglevel eq 'debug')){ print STDERR "### doing insert  $s ###\n";}
    my $sth = $dbh->prepare_stmt($s);
    $sth->execute() || warn "insert failed : $DBI::errstr";
    my $dbi = $sth->{'mysql_insertid'};
    #print STDERR "the table $table_name last inserted id is $melondbi \n";
    return $dbi;
}

sub constructStatment {
    my ($par) = shift;
    my %params = %{$par};
    #construct statment nd quote
    my $stmt;

    foreach my $f (keys %params) {
        $stmt .= " , " if $stmt;

        my $val;

        if ( ! $params{ $f } && ( $f eq 'evalue' ) ) {
                $val = "NULL";
        } else {
                $val = "\"" . $params{$f} . "\"";
        }

        $stmt .= $f . " = " . $val;
    }
    
    return $stmt;

}

sub selectLastId {

	my $engine = shift;

	if ( $engine eq 'mysql' ) {
	
		return "SELECT last_insert_id() as id ";

	} else {
		
		return "SELECT last_insert_rowid() as id ";

	}

}

sub handleValue {
 
  my $value = shift;
  my $context = shift;
  
  if ( $context eq 'evalue' ) {
   
   if ( looks_like_number( $value ) ) {
    
     return $value;
    
   } else {
    
    return undef;
   }
   
   
  } else {
    return $value;
  }
 
}

1;
