#!/usr/bin/perl

#This script takes input blast file in usual ncbi output format and change it into xml format. 
#This concrete version of the script take huge file, from more then 10.000 queries to more then 20 subjects. Thats the reason not to use BioPerl, since operation in memory could dramatically affect speed of the process.
#Addutional option available -number of the sequences in the output files - in case when xml files will be afterwards uploaded into some software, such as blast2go, then its better to split intial file into few chunks.
#
#    hugeBlast2MXL.pl is free software, under the terms of the GNU General Public License 
#
#    hugeBlast2MXL.pl is distributed WITHOUT ANY WARRANTY
#
# Author : Anna Vlasova
# Copyright 2012-2016 Anna Vlasova (anna.vlasova @ crg.eu), Lab Roderic Guigo Bioinformatics and Genomics Group @ Centre for Genomic Regulation Parc de Recerca Biomedica: Dr. Aiguader, 88, 08003 Barcelona


use strict;
use Data::Dumper;
#use Bio::SearchIO;
use Getopt::Long;


#Usual blast output
#blast file name
my $blastFileName ='';
#number of queries per file
my $numberSeqs =1000000;
#blast output file name
my $outputFilePrefix = 'convertedBlast';
#my $outputFilePrefix = ;


GetOptions(
     'blastFile|blast=s'=>\$blastFileName,
     'numberSeqs|n=i'=>\$numberSeqs,
     'outputPrefix|out=s'=>\$outputFilePrefix,
    ) or &usage; 

&usage if !$blastFileName;


################################## Variables definition #####################################################

#some variables used later on.
my($queryName, $queryLength, $hitStart, $hitEnd, $hitSequence, $evalue, $identitiesLength,$strand);
my($blastName,$outputFileName,$iterationQueryId,$hitId, $hitDef,$hitAcc,$hitLength,$middleSeq);
my($queryFlag, $hitFlag)=('f','f');

#filehandle for output file - I'll pass it to subroutines
my $OUTFILE;

my $iterationStatistic="<Iteration_stat>\n<Statistics>\n<Statistics_db-num>22470027</Statistics_db-num>\n".
"<Statistics_db-len>7722991751</Statistics_db-len>\n<Statistics_hsp-len>0</Statistics_hsp-len>\n".
"<Statistics_eff-space>0</Statistics_eff-space>\n<Statistics_kappa>0.041</Statistics_kappa>\n".
"<Statistics_lambda>0.267</Statistics_lambda>\n<Statistics_entropy>0.14</Statistics_entropy>\n</Statistics>\n</Iteration_stat>\n";

#this footer is closing every singel output file
my $footer = "</BlastOutput_iterations>\n</BlastOutput>";

#this will count number of queries and compare it with numberSeqs that user desire to put into one file. Every time count extend this number, new file will be created.
my $count=0;
#this is used for output file name adds on
my $fileCount=0;
#this is countign hits inside one particular query
my $hitCount=0;
#this is countign hsps within hit
my $hspCount=0;

#in the blast file Lambda results could be printed more then one time, I am interesting only in firat one
my $lambdaCount=0;

#this bloack is collecting iteration information and is printed to the file when all iteration parsings are ready.
my $iterationBlock = '';

#message 'no hits found' is stored here
my $iterationMessage ='';

#hash for storing hsp data
my %hspData =();

#hash for storing hit data
my %hitData=();

my $prevQueryName = '';
my $prevHitId ='';
############################################ Main part #########################################################

#get common blast output variables, that are common to each file.
my %blastCommonParam =&getBlastOutputParams($blastFileName);
#print Dumper(%blastCommonParam); 
#start to process queries and hits, and rint converted results into files.

#to add possibility to read gzipped files
if($blastFileName =~/\.gz/) 
{open(INFILE, " gzip -dc $blastFileName |")||die "gzip Can't open BLAST file $blastFileName for reading!\n";}
else
{open(INFILE, $blastFileName)||die "normal Can't open BLAST file for reading!\n";}
 while(my $line=<INFILE>)
  {
   chomp($line);
   if($line=~/Query\=\s+(\S+)\s*.*$/)
   {
    $queryName= $1;
       #here print everything that was not printed yet - last hsp, last hit, iteration statistic and so on.
    if(($queryName ne $prevQueryName)&&($prevQueryName ne '')) 
    {
    #check that all hsp were printed
    #check that all hits were printed
    if($prevHitId ne ''&&$lambdaCount==0)
     {print $OUTFILE "</Hit>\n</Iteration_hits>\n";}
    #check that iterationstatistic were printed
    #print iteration closing tag
     print $OUTFILE "</Iteration>\n";
     $hitCount=0;
     $lambdaCount=0;
     $prevHitId='';
    }
   #if we need - close file
   if($count == $numberSeqs)
     {
      print $OUTFILE $footer;
      close($OUTFILE);
      $count=0;
     }
   #if we need - open new file  
     if($count == 0)
     {
      $fileCount++;
      $outputFileName = $outputFilePrefix.'-'.$fileCount.'.xml';
      open($OUTFILE, ">$outputFileName")||die "Can't open $outputFileName for writing $!\n";
      &printBlastOutputParams(\%blastCommonParam, $OUTFILE);
     }
     $count++;    
     $prevQueryName = $queryName;
#here start iteration block,1 query alignment==1 iteration
    $iterationQueryId =  $count.'_0';
    print $OUTFILE "<Iteration>\n<Iteration_iter-num>$count</Iteration_iter-num>\n<Iteration_query-ID>lcl|$iterationQueryId</Iteration_query-ID>\n";
    print $OUTFILE "<Iteration_query-def>$queryName</Iteration_query-def>\n";
    $line=<INFILE>;
    ($queryLength) = $line=~/\((\d+)\s+letters\)/;
    if(!defined($queryLength))
    {
    $line=<INFILE>;
     ($queryLength) = $line=~/Length\=(\d+)\s*/;
    }
    print $OUTFILE "<Iteration_query-len>$queryLength</Iteration_query-len>\n";
    $queryFlag='t';
   } #line=query
 #new hit
  elsif(($line=~/^\>\s*(\S+)\s+(.+)$/)||($line=~/^\>(\S+)\s*$/))
   {
#iteration hits opening tag should only be started when there is something found. But it should appear only 1st time
   if($queryFlag eq 't')
    {
      print $OUTFILE "  <Iteration_hits>\n";
      $queryFlag ='f';
    }

     $hitId = $1;
     $hitDef = $2||'';
#if there is another hit to the same query, then we should close hit tags.
#28/05/2013 Vlasova AV. I found a bug - this line processed wrongly when we have exactly the same hitIds for two or more hits. This I should print hsp string and close tags every time
#when I see '>' symbol at the beginning. Two and more hsp to the same hits are separated by space, not by '>'.
#old line:
    #if(($hitId ne $prevHitId)&&($prevHitId ne ''))
    if($prevHitId ne '')
    {
     if(scalar keys %hspData >10)
     { 
      &printHSP(\%hspData,  $OUTFILE,$hspCount);
      %hspData=();
      print $OUTFILE "</Hit_hsps>\n";
     }
     print $OUTFILE "</Hit>\n";
     $prevHitId='';
    }
     $hitCount++;
    my $somedata;
    #for pdb there is another pattern
    if($hitId=~/\|pdb\|/)
    {($somedata,$hitAcc) = $hitId =~/(pdb)\|(\S+)\|/;}
    else
    {($somedata,$hitAcc) = $hitId =~/(gb|ref|dbj|emb|sp|tpg|pir|tbd|tpd)\|(\S+)\./;}
    $hspCount=0;
    %hspData=();
    
    if(!defined $hitAcc)
     {$hitAcc = 'Not known'; }
    print $OUTFILE "<Hit>\n";
    print $OUTFILE "<Hit_num>$hitCount</Hit_num>\n";
    print $OUTFILE "<Hit_id>ref|$hitId</Hit_id>\n";
    $hitDef=~s/\&//;
    print $OUTFILE "<Hit_def>$hitDef</Hit_def>\n";
    print $OUTFILE "<Hit_accession>$hitAcc</Hit_accession>\n";
    #get hit length from one of the following lines
    #until($line=~/Length\s+\=\s+/)
    until($line=~/Length\s*\=\s*/)
    {$line=<INFILE>;}
    #($hitLength) = $line=~/Length\s+\=\s+(\d+)/;
    ($hitLength) = $line=~/Length\s*\=\s*(\d+)/;
    print $OUTFILE "<Hit_len>$hitLength</Hit_len>\n";
    print $OUTFILE "<Hit_hsps>\n";
    $prevHitId = $hitId;
   } #line='>' == new hit
  #new hsp
  elsif($line=~/Score\s+\=.+Expect\s+\=/)
   {
    #if there is already fully filled %hspData hash, then it means that there was one hsp before. we need to print it and start new one
    if(scalar keys %hspData >10)
    { 
      &printHSP(\%hspData,  $OUTFILE,$hspCount);
      %hspData=();
    }
    $hspCount++;
    ($hspData{'bitScore'}, $hspData{'score'}, $hspData{'eValue'}) = $line=~/Score\s+\=\s+([0-9.]+)\s+bits\s+\((\d+)\)\,\s+Expect\s\=\s([^,]+)[, ]*/;
    #identity line
    $line=<INFILE>;
    if(($line=~/Identities\s+\=\s+(\d+)\/(\d+).+Positives\s+\=\s+(\d+)\//)||($line=~/Identities\s+\=\s+(\d+)\/(\d+)\s+/))
    {
     $hspData{'identity'}=$1; $hspData{'alignLength'}=$2;
     if(defined $3){ $hspData{'positive'} = $3;} 
     else{$hspData{'positive'} =$2;}
    }
     
   } #line==Score
  #catch start and stop of the query and hit and also sequences for each parts. This block is reading thrree lines at once
  if(($line=~/^Query\:\s+(\d+)\s+(\S+)\s+(\d+)/)||($line=~/^Query\s+(\d+)\s+(\S+)\s+(\d+)/))
  {
   if(!exists $hspData{'queryStart'})
    {$hspData{'queryStart'}=$1;}
   $hspData{'queryEnd'} =$3;
   $hspData{'querySequence'} .= $2;
  #middle line
   $line=<INFILE>;
   chomp($line);
   $middleSeq = $line;
   $middleSeq =~s/^\s+//g;
   $middleSeq =~s/\s+$//g;
   $hspData{'middleLine'} .=$middleSeq;
  #Hit line 
   $line=<INFILE>;
   ($hitStart, $hitSequence, $hitEnd) = $line=~/^Sbjct\:\s+(\d+)\s+(\S+)\s+(\d+)/;
  if(! defined $hitSequence || $hitSequence eq '' )
   {($hitStart, $hitSequence, $hitEnd) = $line=~/^Sbjct\s+(\d+)\s+(\S+)\s+(\d+)/;}
   if(!exists $hspData{'hitStart'})
    {$hspData{'hitStart'} = $hitStart;}
   $hspData{'hitEnd'} = $hitEnd;
   $hspData{'hitSequence'} .= $hitSequence;
  } #line==Query
 #catch statistic
 if(($line=~/^Lambda/)&&($lambdaCount==0))
  {
   $lambdaCount++;
   #print and close hsps and hits.
    if(scalar keys %hspData >10)
    {
       &printHSP(\%hspData,  $OUTFILE,$hspCount);
      %hspData=();
      print $OUTFILE "</Hit_hsps>\n"; 
      print $OUTFILE "</Hit>\n";
      print $OUTFILE "</Iteration_hits>\n";     
    }
  $line=<INFILE>;
  my($kappa,$lambda, $entropy);
  ( $kappa,$lambda, $entropy) = $line=~/\s+(\S+)\s+(\S+)\s+(\S+)\s*/;
  print $OUTFILE "<Iteration_stat>\n"." <Statistics>\n";
  print $OUTFILE "<Statistics_db-num>$blastCommonParam{'dbSeqs'}</Statistics_db-num>\n".
          "<Statistics_db-len>$blastCommonParam{'dbLength'}</Statistics_db-len>\n".
          "<Statistics_hsp-len>0</Statistics_hsp-len>\n".
          "<Statistics_eff-space>0</Statistics_eff-space>\n".
          "<Statistics_kappa>$kappa</Statistics_kappa>\n".
          "<Statistics_lambda>$lambda</Statistics_lambda>\n".
          "<Statistics_entropy>$entropy</Statistics_entropy>\n";        
  print $OUTFILE "</Statistics>\n</Iteration_stat>\n";

  } #line == Lambda
 #catch 'No hits found'
 if($line=~/No\s+hits\s+found/)
  {print $OUTFILE "<Iteration_message>No hits found</Iteration_message>\n";}
 }#while line=<INFILE>
close(INFILE);

#print to the final file all closing tags that needed
#if($prevHitId ne '')
# {print $OUTFILE "</Hit>\n</Iteration_hits>\n";}
print $OUTFILE "</Iteration>\n";
print $OUTFILE $footer;
close($OUTFILE);

#################################################################
################ Main subroutines ###############################
#################################################################
sub getBlastOutputParams
{
 my $fileName = shift;

 my $add = 'cat ';
 if( $fileName=~/\.gz$/)
 {$add='zcat ';}

 my $header = `$add $fileName|head -30`;
 my $tail =`$add $fileName|tail -20`;

 my $fullString = $header."\n".$tail;
 my @dataArray = split("\n", $fullString);
 my %returnData =();
 foreach my $line(@dataArray)
  {
   #print $line;
   if($line=~/^([tT]*BLAST.|blast.)\s+([0-9.]+\s*.*)/)
    {
     $blastName = lc($1);
     $returnData{'blastName'} = $blastName;
     $returnData{'blastVersion'} = $2;
     }
    
   elsif($line=~/^Reference\:/)
    {
     $returnData{'reference'}='Reference: Altschul, Stephen F., Thomas L. Madden, Alejandro A. Schaffer, ~Jinghui Zhang, Zheng Zhang, Webb Miller, and David J. Lipman (1997), ~&quot;Gapped BLAST and PSI-BLAST: a new generation of protein database search~programs&quot;,  Nucleic Acids Res. 25:3389-3402.';
    }
    elsif($line =~ /^Database\:\s*(\S+)\s*/)
    {   $returnData{'blastDatabase'}= $1;   }
    elsif($line=~/^Query\=\s*(\S+)$/)
    {    $returnData{'queryName'} =$1;  }
    elsif($line=~/\((\d+)\s+letters\)/)
    { $returnData{'queryLength'} = $1; }
    elsif($line=~/Length\=(\d+)/)
    { $returnData{'queryLength'} = $1; }
   elsif($line=~/^Matrix\:\s+(\S+)$/)
    {$returnData{'matrix'}=$1;}
   elsif($line=~/^Gap.+Existence\:\s+(\d+)\,\s+Extension\:\s+(\d+)/)
    {
     $returnData{'gapOpen'}=$1;
     $returnData{'gapExt'} =$2;
   }
  elsif($line=~/Number\sof\ssequences\sbetter\sthan\s(\S+)\:/)
   {$returnData{'evalue'}=$1;}
  elsif(($line=~/Length\s+of\s+database\:\s+(\S+)/)||($line=~/Number\sof\sletters\sin\sdatabase\:\s+(\S+)\s*/))
   {
    my $dbLength = $1;
    $dbLength =~s/\,//g;
    $returnData{'dbLength'} = $dbLength;
   }
  elsif(($line=~/Number\sof\sSequences\:\s+(\S+)\s*/)||($line=~/Number\sof\ssequences\sin\sdatabase\:\s+(\S+)\s*/))
   {
    my $dbSeqs = $1;
    $dbSeqs =~s/\,//g;
    $returnData{'dbSeqs'} = $dbSeqs;
   }
  }

 if(!exists $returnData{'reference'})
  {  $returnData{'reference'}='Reference: Altschul, Stephen F., Thomas L. Madden, Alejandro A. Schaffer, ~Jinghui Zhang, Zheng Zhang, Webb Miller, and David J. Lipman (1997), ~&quot;Gapped BLAST and PSI-BLAST: a new generation of protein database search~programs&quot;,  Nucleic Acids Res. 25:3389-3402.';}

 if(! exists $returnData{'evalue'})
  {$returnData{'evalue'} =10;}
 return %returnData;
}


sub printBlastOutputParams
{
 my ($dataHash, $fh)=@_;
 
#<BlastOutput_version>$dataHash->{'blastName'} $dataHash->{'blastVersion'}</BlastOutput_version>
print $fh <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE BlastOutput PUBLIC "-//NCBI//NCBI BlastOutput/EN" "http://www.ncbi.nlm.nih.gov/dtd/NCBI_BlastOutput.dtd">
<BlastOutput>
  <BlastOutput_program>$dataHash->{'blastName'}</BlastOutput_program>
  <BlastOutput_version>blastp 2.2.26 [Sep-21-2011]</BlastOutput_version>
  <BlastOutput_reference>$dataHash->{'reference'}</BlastOutput_reference>
  <BlastOutput_db>$dataHash->{'blastDatabase'}</BlastOutput_db>
  <BlastOutput_query-ID>lcl|1_0</BlastOutput_query-ID>
  <BlastOutput_query-def>$dataHash->{'queryName'}</BlastOutput_query-def>
  <BlastOutput_query-len>$dataHash->{'queryLength'}</BlastOutput_query-len>
  <BlastOutput_param>
    <Parameters>
      <Parameters_matrix>$dataHash->{'matrix'}</Parameters_matrix>
      <Parameters_expect>$dataHash->{'evalue'}</Parameters_expect>
      <Parameters_gap-open>$dataHash->{'gapOpen'}</Parameters_gap-open>
      <Parameters_gap-extend>$dataHash->{'gapExt'}</Parameters_gap-extend>
      <Parameters_filter>F</Parameters_filter>
    </Parameters>
  </BlastOutput_param>
  <BlastOutput_iterations>
EOF
}

sub printHSP
{
 my ($dataHash,$fh,$count)= @_;
#print Dumper($dataHash);

print $fh <<EOF;
<Hsp>
  <Hsp_num>$count</Hsp_num>
  <Hsp_bit-score>$dataHash->{'bitScore'}</Hsp_bit-score>
  <Hsp_score>$dataHash->{'score'}</Hsp_score>
  <Hsp_evalue>$dataHash->{'eValue'}</Hsp_evalue>
  <Hsp_query-from>$dataHash->{'queryStart'}</Hsp_query-from>
  <Hsp_query-to>$dataHash->{'queryEnd'}</Hsp_query-to>
  <Hsp_hit-from>$dataHash->{'hitStart'}</Hsp_hit-from>
  <Hsp_hit-to>$dataHash->{'hitEnd'}</Hsp_hit-to>
  <Hsp_query-frame>1</Hsp_query-frame>
  <Hsp_hit-frame>1</Hsp_hit-frame>
  <Hsp_identity>$dataHash->{'identity'}</Hsp_identity>
  <Hsp_positive>$dataHash->{'positive'}</Hsp_positive>
  <Hsp_align-len>$dataHash->{'alignLength'}</Hsp_align-len>
  <Hsp_qseq>$dataHash->{'querySequence'}</Hsp_qseq>
  <Hsp_hseq>$dataHash->{'hitSequence'}</Hsp_hseq>
  <Hsp_midline>$dataHash->{'middleLine'}</Hsp_midline>
</Hsp>
EOF
}


sub usage {

die(qq/
 Usage:   hugeBlast2XML.pl [options]
 Options 
        blastFile|blast  - input BLAST file in NCBI format
        numberSeqs|n     - number of sequence in the output file. Sometimes input file is huge and for parallelisation purpose user wants to divide it into chunks.
			   By default it 1,000,000 seqs per file.
        outputPrefix|out - prefix for output files. Output file names will be constructed like prefix+number+.xml
                           By default it is 'convertedBlast'
\n/);
}
