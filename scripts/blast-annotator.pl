#!/usr/bin/env perl


=head1 NAME
  blast-annotator.pl
=head1 SYNOPSIS
  perl blast-annotator.pl [-i blastfile] [-o output] [-f blastformat ] [-t type] [-u url] [-s hits] [-c configfile] [-d delayseconds] [-v] [-h]
=head1 DESCRIPTION
Typical usage is as follows:
  % perl blast-annotator.pl -i blast.out -o blast.annot -f text -t all -v 
=head2 Options

=head1 AUTHORS
Toni Hermoso Pulido <toni.hermoso@crg.cat>
=cut

use warnings;
use strict;
use Getopt::Long;
use Data::Dumper;
use Pod::Usage;
use LWP::Simple;
use JSON;
use Config::JSON;
use Bio::SearchIO;
use DBI;

my $format = "blast"; # Alternative blastxml
my $type = "common";
my $numhits = 30;
my $delay = 0.25;

my $dbh = 0;
my $config_json = 0;

my ($input, $output, $url, $verbose, $accession, $query_desc, $show_help);

                                &GetOptions(
                                'input|i=s'						=> \$input,
                                'output|o=s'					=> \$output,
                                'format|f=s'					=> \$format,
                                'hits|s=s'						=> \$numhits,
                                'type|t=s'						=> \$type,
                                'url|u=s'						=> \$url,
								'delay|d=s'						=> \$delay,
								'config|c=s'					=> \$config_json, #Config file
                                'verbose|v'						=> \$verbose,
								'accession|a'					=> \$accession, #use accession instead of name for hits
								'query|q'						=> \$query_desc, #use query description instead of name
                                'help|h'  => \$show_help
)
  or pod2usage(-verbose=>2);
pod2usage(-verbose=>2) if $show_help;

###########################################
# Check analysis options and steps to run #
###########################################

die "You must specify an input BLAST file \n Use -h for help" if !$input;
die "You must specify a resulting output annotation file \n Use -h for help" if !$output;


if ( $config_json ) {

	my $config = Config::JSON->new( $config_json );

	if ( $config->get("mysql") ) {
		
		my $user = $config->get("mysql/user");
		my $password = $config->get("mysql/password");
		my $db = $config->get("mysql/db");
		my $host = $config->get("mysql/host");

		
		my $dsn = "DBI:mysql:database=$db;host=$host";
		$dbh = DBI->connect($dsn, $user, $password);
		
	}
	
}

# Out file
open my $fout, ">", $output || die "Cannot write in $output";

# Open BLAST

my $report_obj = new Bio::SearchIO(-format => $format,
                                -file   => $input);

while( my $result = $report_obj->next_result ) {
	
	my $debughash = {};

	my $query;
	
	if ( $query_desc ) {
		$query = $result->query_description();
	} else {
		$query = $result->query_name();
	}
	
	my @hitlist;
	
	my $desc = "";
	
    while( my $hit = $result->next_hit ) {
		
		if ( $desc eq "" ) {
			$desc = $hit->description();
		}
		
		if ( $accession ) {
			push( @hitlist, $hit->accession() );
		} else {
			push( @hitlist, processHitName( $hit->name() ) );
		}
    }
	
	#print $query, ": ", $#hitlist, "\n";
	
	my @slice;
	if ( $#hitlist <= $numhits - 1 ) {
		@slice = @hitlist;
	} else {
		@slice = @hitlist[ 0 .. $numhits -1 ];
	}
	
	
	$debughash->{"query"} = $query;
	@{$debughash->{"taken_hits"}} = @slice;
            
	processGOGO( \@slice, $query, $desc, $fout, $debughash, $dbh );
	sleep( $delay );
	# exit;
}

close( $fout );

# Process Hit name

sub processHitName {
	
	
	my $name = shift;
	
	if ( $name=~/\|/ ) {
		
		my (@parts) = split(/\|/, $name );
		
		if ( $#parts >= 0 ) {
			$name = $parts[1];
		}
		
	}
	
	return $name;
	
}

# Query by GO all hits, using type defined


sub processGOGO {
	
	my $golist = shift;
	my $query = shift;
	my $desc = shift;
	my $output = shift;
	my $debughash = shift;
	my $dbh = shift;

	my @entries;
	@{$debughash->{"found_hits"}} = ();
	
	if ( $dbh ) {
		
		#my $string = "SELECT distinct t.acc, t.name from term t, goassociation a, idmapping i where a.ID = i.uniprot and t.acc = a.GO and ";
		#
		#my @goquery;
		#foreach my $goelem ( @{$golist} ) {
		#	my $query = $string." i.external = '".$goelem."' ;";
		#	
		#	my $sth = $dbh->prepare( $query );
		#	
		#	$sth->execute();
		#	
		#	if ( $sth->rows > 0 ) {
		#	
		#		while (my $ref = $sth->fetchrow_hashref()) {
		#
		#			push( @entries, $ref );
		#		}
		#	
		#	}
		#}

		my $string = "SELECT distinct( i.uniprot ) as uniprot from idmapping i where ";
		my $string2 = "SELECT distinct t.acc, t.name from term t, goassociation a where t.acc = a.GO and ";
		
		my @idquery;
		my @goquery;
		
		my @querystr;
		
		if ( $#{$golist} > -1 ) {
		
			foreach my $goelem ( @{$golist} ) {
				push( @querystr, " ( i.external = '".$goelem."' ) " );
			}
					
			my $query = $string. " ( ".join( " OR ", @querystr )." );";
			my $sth = $dbh->prepare( $query );
			
			$sth->execute();
			
			if ( $sth->rows > 0 ) {
			
				while (my $ref = $sth->fetchrow_hashref()) {
	
					push( @idquery, $ref->{"uniprot"} );
				}
			
			}
			
			$sth->finish;
			
			# my @unique = do { my %seen; grep { !$seen{$_}++ } @idquery };
			
			foreach my $idelem ( @idquery ) {
	
				my $query = $string2." a.ID = '".$idelem."' ;";
	
				my $sth = $dbh->prepare( $query );
				
				$sth->execute();
				
				if ( $sth->rows > 0 ) {
				
					while (my $ref = $sth->fetchrow_hashref()) {
		
						push( @entries, $ref );
					}
				
				}
				
				$sth->finish;
			}	
			
			@entries = rmRedundant( \@entries );
		
		}
		
	} else {
		
		die "You must specify a GOGO API URL endpoint \n Use -h for help" if !$url; # If no URL
		
		my $goparam = join("-", @{$golist} );
		
    if ( $goparam ) {
    
      my $finalurl = $url."/go/list/".$goparam;
      
      if ( $type eq 'common' ) {
      
        $finalurl.="/common";
      } 
    
      my $json = "";
    
    
      $json = get($finalurl);
    
          
      if ( defined( $json ) && $json ne '' ) {
        
        my $jsonobj = JSON->new->utf8->decode($json);
          
        #print $finalurl, "\n";
        #print Dumper($jsonobj);
        
        # Process JSON here
        if ( $jsonobj ) {
          
          my $query = $jsonobj->{"query"};
          
          #print Dumper( $query );
          
          @{$debughash->{"found_hits"}} = keys( %{$query} );
          
          my $outcome = $jsonobj->{"outcome"};
          
          if ( $outcome ) {
          
            foreach my $key ( keys %{$outcome} ) {
              
              my $goresults = $outcome->{$key};
              
              #print $key, "\n";
              
              foreach my $goitem ( @{$goresults} ) {
      
                #print Dumper( $goitem );					
                push( @entries, $goitem );
              }
            }
            
          }
          
          
        }
      
      }
    
    }
	
	}
	
	my $num = 0;

	my $outtext = "";
	$outtext = $outtext . $query . "\t"."#". "\t". $desc. "\n";
	
	
	foreach my $entry ( @entries ) {
	
		#print Dumper( $entry );	
		$outtext = $outtext . $query . "\t" . $entry->{"acc"} . "\t" . $entry->{"name"} . "\n";
		
	}
	
	print $output $outtext;
	
	if ( $verbose ) {
		
		# Process Debug in this case
		
		print "* ".$debughash->{"query"}, "\n";
		print "# HITS TAKEN: ".join(", ", @{$debughash->{"taken_hits"}} )."\n";
		print "# NUM HITS TAKEN: ".scalar( @{$debughash->{"taken_hits"}} )."\n";
		print "@ HITS FOUND: ".join(", ", @{$debughash->{"found_hits"}} )."\n";
		print "@ NUM HITS FOUND: ".scalar( @{$debughash->{"found_hits"}} )."\n";		
	}
	
	
}

sub rmRedundant {
	
	my $array = shift;
	my %hash;
	my @new;
	
	foreach my $c (@{$array} ) {
		
		my $name = $c->{"name"};
		if ( ! defined( $hash{$name} ) ) {
			$hash{$name} = 1;
			push( @new, $c );
		}
 		
	}
	
	return @new;
	
	
}

