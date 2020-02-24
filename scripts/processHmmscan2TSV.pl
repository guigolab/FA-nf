#!/usr/bin/env perl

use File::Basename;

my $glob = shift;
my $outdir = shift;

my (@files) =  glob($glob);

foreach $file (@files) {
  if ( -f $file ){

    my $filename = basename($file);

    open( FILEOUT, ">", "$outdir/$filename" );

    open( FILEIN, "<", "$file" );
    while ( <FILEIN> ) {
        
        unless ($_=~/^\#/ ) {
    
            my ($id, $ko) = $_=~ /\s*(\S+)\s+(K\d{5})/;
            
            print FILEOUT "$id\t$ko\n";
        }
        
        
        
    }
    
    close( FILEIN );
    close( FILEOUT );
    
  }
}
