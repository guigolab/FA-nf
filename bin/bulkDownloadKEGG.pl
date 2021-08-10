#!/usr/bin/env perl

# make life easier
use warnings;
use strict;

# imports needed
use Cwd;
use File::Spec;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
use File::stat;
use LWP::Simple;
use POSIX qw/strftime/;

my $kolist = shift // '/nfs/db/kegg/ko_list';
my $downdir = shift // '/nfs/db/kegg/ko_store';
my $webChunk = shift // 50;

if ( ! -d $downdir ) {
  system( "mkdir -p $downdir" )
}

my ( @kolist );

open (KOLIST, $kolist) || die "Cannot open $kolist";

while (<KOLIST>) {

  if ( $_=~/^(K\d+)/ ) {
    push( @kolist, $1 );
  }

}

close (KOLIST);

my @queue = ();

foreach my $ko ( @kolist ) {

  if ( $#queue > $webChunk - 1 ) {

    my $response = &processByAPI( \@queue );
    &processToFile( $response, $downdir );

    @queue = ();

  }

  push( @queue, $ko );


}

if ( $#queue >= 0 ) {
  my $response = &processByAPI( \@queue );
  &processToFile( $response, $downdir );
}

sub processByAPI {

  my $arr = shift;

  my $url = "http://rest.kegg.jp/get/".join("+", @{$arr});
  my $response = get $url;

  sleep( 2 );

  return $response;

}

sub processToFile {

  my $response = shift;
  my $downdir = shift;

  my @split = splitKegg( $response );

  foreach my $split ( @split )  {

    my ($KO) = $split =~ /ENTRY\s+(K\d+)/;

    if ( $KO ) {

      open FILEOUT, ">", $downdir."/".$KO.".txt";
      print FILEOUT $split;
      close FILEOUT;
    }
  }

  return 1;

}

sub splitKegg {

	my $text = shift;
	my @strings = ();

  my ( @lines ) = split(/\n/, $text);

	my $part = "";

  foreach my $line ( @lines ) {

		if ( $line=~/\/\/\// ) {
			if ( $part!~/^\s*$/ ) {
				$part.=$line."\n";
				push( @strings, $part );
			}
			$part = "";
		} else {
			$part.=$line."\n";
		}

	}

	return @strings;

}
