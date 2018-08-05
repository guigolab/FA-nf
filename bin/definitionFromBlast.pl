#!/usr/bin/perl

#This script takes input blast file in ncbi or xml formats and return definition for queries, analogous of blast description annotator from blast2go
#I am excluding words 'putative, predicted and so on', and then range phrases based on frequency 
#
# Author : Anna Vlasova
# Copyright 2017 Anna Vlasova (anna.vlasova @ crg.eu), Lab Roderic Guigo Bioinformatics and Genomics Group @ Centre for Genomic Regulation Parc de Recerca Biomedica: Dr. Aiguader, 88, 08003 Barcelona


use strict;
use Data::Dumper;
use Getopt::Long;
use Bio::SearchIO; 
use Lingua::EN::Ngram;
use List::Util qw(max);

#Usual blast output
#blast file name
my $blastFileName ='';
#blast output file name
my $outputFile = 'definition.tsv';
my $fileFormat = 'ncbi';

GetOptions(
     'in|blast=s'=>\$blastFileName,
     'output|out=s'=>\$outputFile,
     'f|format=s'=>\$fileFormat,
    ) or &usage; 

&usage if !$blastFileName;


################################## Subs #####################################################
# 
# sub getHitDef
# {
#  my ($fileName, $fileFormat) =shift;
#  my %retData=();
#  
#  my $format='blast';
#  if($fileName =~/\.xml/ || $fileFormat eq 'xml')
#   {$format='blastxml';}
# 
# my ($id, $id2, $def);
#  my $in = new Bio::SearchIO(-format => $format, 
#                            -file   => $fileName);
# 
# while( my $result = $in->next_result ) {
#   ## $result is a Bio::Search::Result::ResultI compliant object
#   $id=$result->query_name();
#   $id2 = $result->query_accession();
#   while( my $hit = $result->next_hit ) {
#     ## $hit is a Bio::Search::Hit::HitI compliant object
#     $def = $hit->description() ;
# 
#     push(@{$retData{$id}}, $def);
#  }
#  }
#  return %retData;
# }


sub getBestDef{

 my $dataIn=shift;

 my @data=@{$dataIn};

my $probableFlag=0;
my %numberWords=();
my %freq=();

my($number, $key);
#make preprocessing - remove wrong words and name of species
for(my $i=0; $i<scalar (@data); $i++)
{
  $key=$data[$i];
  $key=~s/\[[^\[\]]+\]$//i;
  $key=~s/\[([^\[\]]+)$//i;
  
  if($key=~/Putative|Predicted|probable|uncharacterized|hypothetical/i)
  {
   $probableFlag=1;
   $key=~s/Putative|Predicted|probable|uncharacterized|hypothetical//i;
  }
   $key=~s/protein//;

   $key=~s/^[:;,.]+//i;
   $key=~s/^\s+//i;
   $key=~s/\s+$//i;
   $data[$i]=$key;
  # $number=scalar(split(/\s+/, $key));
  #  $numberWords{$number}++;
  #split each sentences into words using spaces, commas and other punctuation characters as separators
   $key=~s/[,.!?:;]+/ /gi;

   #print "$key\n";
   if($key !~/^uncharacterized/){
   my @tmp=split(/\s/,$key);
   #sequence of words is very important, so I dont need to shaffle them, just take combinations 'one-by-one'
   for(my $j=0; $j<scalar @tmp; $j++)
   {
    if($tmp[$j]=~/^(.+)\-like$/){$tmp[$j]=$1;}

    my $sub = join(' ', @tmp[0..$j]);
    $freq{'counts'}{$sub}++;
    $freq{$sub}=$j;
   }
 }
}

#print "#" x20 ."\n"; 
#print Dumper(%freq);

 my $maxScoreValue = max values %{$freq{'counts'}}; 
 #print "maxScore = $maxScoreValue\n";
 my $finalString="";

 my $finalLength=0;

  foreach my $key ( sort { $freq{'counts'}{ $b } <=> $freq{'counts'}{ $a } } keys %{$freq{'counts'}} ) {
  
  if($freq{'counts'}{$key} >= ($maxScoreValue-1))
   {
    if(length($key)> $finalLength) 
     {$finalString =$key." ";}
     $finalLength=length($key);
    }
}

if($finalString eq '')
{$finalString='uncharacterized protein';}

if($probableFlag==1)
{ $finalString = "PREDICTED: ".$finalString;}
 

# my $i=0;
# my $numberNgrams;
 #get typical number of words in definitions -one with the biggest number
#foreach my $key (sort{$numberWords{$a} <=> $numberWords{$b} } keys %numberWords)
#{
# if($i==0){$numberNgrams=$key; last;}
#}
 
#  my $string= join(" ", @data);
#  
#  #this package use '-' symbol to separate words, but quite frequency there is 'smth-like' definition.. and it should stay as one word, not three words.
# 
#  #my $ngram = Lingua::EN::Ngram->new( text => $string );
#  my $score=();
#  $score = $ngram->ngram($numberNgrams);
# 

 return $finalString;

}
############################################ Main part #########################################################

#get common blast output variables, that are common to each file.
#my %hitDefinitions =&getHitDef($blastFileName);


#my $fileName=shift;
# my %retData=();
 
my $count=0;
my @str=();
 
 my $format='blast';
 if($blastFileName =~/\.xml/ || $fileFormat eq 'xml'|| $blastFileName=~/Xml/)
  {$format='blastxml';}

open(OUT, ">$outputFile")|| die "Can't open $outputFile for reading!\n";

my ($id, $id2, $def);
 my $in = new Bio::SearchIO(-format => $format, 
                           -file   => $blastFileName);

while( my $result = $in->next_result ) {
  ## $result is a Bio::Search::Result::ResultI compliant object
  #$count++;
  #if($count==10){last;}
   $id=$result->query_description();
  $id2 = $result->query_accession();
  print "$id $id2\n";
  @str=();
  while( my $hit = $result->next_hit ) {
    ## $hit is a Bio::Search::Hit::HitI compliant object
    $def = $hit->description() ;
    #push(@{$retData{$id}}, $def);
    push(@str, $def);
 }
 
 my $bestDefinition = 'NA';
 #print Dumper(@str);
 if(defined $str[0])
 {
  #print $id."\n";
  $bestDefinition=&getBestDef(\@str);
 }
 print OUT $id."\t".$bestDefinition."\n";
  
 }
close(OUT); 

#my @str=("vanin-like protein 1","vanin-like protein 2", "vanin-like protein 1 isoform X1", "vanin-like protein 1 isoform X2 [Dinoponera quadriceps]","vanin-like protein 1 isoform X2 [Linepithema humile]");
#my $bestDefinition=&getBestDef(@str);
#print $bestDefinition."\n";

#get minimum length for N-grams 



#my $bestDefinition;
#open(OUT, ">$outputFile")|| die "Can't open $outputFile for reading!\n";
#foreach my $key (sort {$a cmp $b} keys %hitDefinitions)
#{
# $bestDefinition=&getBestDef(join("\,",@{$hitDefinitions{$key}}));
# print OUT "$key\t$bestDefinition\n";
#}

#close(OUT);


sub usage {

die(qq/
 Usage:   definitionFromBlast [options]
 Options 
        in|blast    - input BLAST file in NCBI or XML format
        output|out - Output file name. By default it is 'definition.tsv'
        f|format    - input file format 'ncbi'[default] or 'xml'
\n/);
}
