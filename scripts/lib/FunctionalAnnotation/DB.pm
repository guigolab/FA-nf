=head1 Bio::FunctionalAnnotation::DB

=head2 Authors

=head3 Created by
              Guglielmo Roma
              guglielmo.roma@crg.es
	      Anna Vlasova
              vlasova.av@gmail.com

=head2 Description

             This module have method to handle with the database for the FA, both under Mysql and SQLite engines
             Based on the module Bio::Melon::DB
=head2 Example

	my $db_obj = Bio::FunctionalAnnotation::DB->new;
	$db_obj->db_connection;
	$db_obj->host;

	my $newdb_obj = Bio::FunctionalAnnotation::DB->new(-dbname =>'MympnTest');
	my $table_name = "testtable";
	my $column_name = "test_text";
	my $value = "testword";
	my $primary = $table_name."_id";

	my $data = qq{DROP TABLE IF EXISTS $table_name;
	CREATE TABLE IF NOT EXISTS $table_name (
	  $primary int(11) NOT NULL AUTO_INCREMENT,
	  $column_name varchar(40) NOT NULL,
	  PRIMARY KEY (`testtable_id`)
	); \nINSERT INTO $table_name SET $column_name  = \"$value\";};

	use Bio::Melon::File;
	my $file = Bio::Melon::File->writeDataToFile("testtable.sql",$tmpdir, $data,1);

	my $sec_value = "second insert";
	my $par = qq{INSERT INTO $table_name SET $column_name = \"$sec_value\"};
	my $newdbID = $newdb_obj->insert_set($par);

	my $condition = "$primary=$newdbID";
	my $uppar = qq{UPDATE $table_name SET $column_name = \"$sec_value\" WHERE $condition};
	my $updbID = $newdb_obj->update_set($uppar);

	my $condition = "$primary=$updbID";
	my $selpar = qq{SELECT  $column_name FROM $table_name WHERE $condition};
	my $res = $newdb_obj->select_from_table($selpar);

	my $delpar = qq{DELETE FROM $table_name WHERE $condition};
	my $deldbID = $newdb_obj->delete_from_table($delpar);

=cut


package FunctionalAnnotation::DB;

use strict;
use DBI;
use Carp;
use FindBin qw($RealBin);
use lib "$RealBin";
use Data::Dumper;
use File::Spec;
use vars qw(@ISA);
use FunctionalAnnotation::Utils::Argument qw(rearrange);
use Bio::Root::Root;
@ISA = qw(Bio::Root::Root);

my %conf =  %::conf;
my $debug = $conf{'global'}{'debug'};
my $debugSQL = $conf{'global'}{'debugSQL'};
my $mysql_path =$conf{'default'}{'mysql_path'};
my $tmpdir = $conf{'default'}{'tmp_dir'};
#my $loglevel=$conf{'loglevel'};

sub new {
  my ($caller) =shift @_;
  my $class = ref($caller) || $caller;
  my $self = $class->SUPER::new(@_);
  my (
    $engine,
    $db,
    $host,
    $user,
    $pass,
    $port,
    $sth,
    )
    = rearrange( [
    'ENGINE',
    'DBNAME',
    'HOST',
    'USER',
    'PASS',
    'PORT',
    'STH',
    ],
    @_
    );

  unless($host){$host = $conf{'dbaccess'}{'dbhost'}};
  unless($db){$db= $conf{'dbaccess'}{'dbname'}};
  unless($user){$user= $conf{'dbaccess'}{'dbuser'}};
  unless($pass){$pass= $conf{'dbaccess'}{'dbpass'}};
  unless($port){$port= $conf{'dbaccess'}{'dbport'}};

  $host && $self->host($host);
  $user && $self->user($user);
  $pass && $self->pass($pass);
  $db && $self->dbname($db);
  $port && $self->port($port);

  my $dbh;

  if($engine eq 'mysql')
  {
    $dbh = DBI->connect("DBI:mysql:database=$db;host=$host;port=$port", $user, $pass);
   unless ($dbh){warning("Can't connect $db; I'll try to create\n");$dbh = $self->create_db} ;
    unless ($dbh){die "Can't create $db: ", $DBI::errst}
   }
  elsif($engine eq 'sqlite')
  {
   #print " DBI:SQLite:database=$db\n";
   my $dsn = "DBI:SQLite:dbname=$db";
   $dbh = DBI->connect($dsn, "", "", { RaiseError => 1 })
                      or die $DBI::errstr;
  }
  $dbh && $self->db_connection($dbh);

  return $self;
}

sub db_connection {
    my ($self, $dbh) = @_;

    $self->{'db_connection'} = $dbh if $dbh;
    return $self->{'db_connection'};
}

sub host {
    my ($self, $host) = @_;

    $self->{'host'} = $host if $host;
    return $self->{'host'};
}

sub user {
    my ($self, $user) = @_;

    $self->{'user'} = $user if $user;
    return $self->{'user'};
}

sub dbname {
    my ($self, $dbname) = @_;

    $self->{'dbname'} = $dbname if $dbname;
    return $self->{'dbname'};
}

sub port {
    my ($self, $port) = @_;

    $self->{'port'} = $port if $port;
    return $self->{'port'};
}

sub pass {
    my ($self, $pass) = @_;

    $self->{'pass'} = $pass if $pass;
    return $self->{'pass'};
}

sub create_db () {
    my ($self) = @_;

    my $user  = $self->user;
    my $pass = $self->pass;
    my $host = $self->host;
    my $dbname = $self->dbname;
    my $port = $self->port;

    my $mysql = $mysql_path."mysqladmin";
    my $res = `$mysql -u $user -p$pass -h $host CREATE $dbname`;

    my $dbh = DBI->connect("DBI:mysql:database=$dbname;host=$host;port=$port", $user, $pass);
    $self->{'create_db'} = $self->db_connection($dbh);
    return $self->{'create_db'};
}

sub exec_import () {
    my ($self, $file) = @_;

    my $user  = $self->user;
    my $pass = $self->pass;
    my $host = $self->host;
    my $db = $self->dbname;

    my $res = system $mysql_path."mysql -u $user -p$pass -h $host $db < $file";
    unless ($res){$self->{'exec_import'} = 1}
    else{$self->{'exec_import'} = 0}
    return $self->{'exec_import'};
}

sub prepare_stmt {
    my ($self,$stmt) = @_;

    my $dbh = $self->db_connection;
    my $sth = $dbh->prepare($stmt);
    $self->{'prepare_stmt'} = $sth;
    return $self->{'prepare_stmt'};
}

sub truncate_table {
    my ($self,$table_name) = @_;

    my $par=qq{truncate $table_name;};
    #if(($loglevel eq 'debug')){ print STDOUT "SQL CODE: $par\n";}

    my $sth=$self->prepare_stmt($par);
    $sth->execute();
    $self->{'sth'}=$sth;
}

sub insert_set {
    my ($self,$par)=@_;

    $par = $self->_clean_sql($par);
    my $sth = $self->prepare_stmt($par);
    my $dbID;
    #print STDERR $par;
    $sth->execute();
    $self->{'sth'} = $sth;
    $dbID = $sth->{'mysql_insertid'};
    $self->{'insert_set'} = $dbID;
    return $self->{'insert_set'};
}

sub update_set {
    my ($self, $par) = @_;

    $par = $self->_clean_sql($par);
    my $sth = $self->prepare_stmt($par);
    my $dbID;

    $sth->execute();
    $self->{'sth'} = $sth;
    $dbID = $sth->rows;
    $self->{'update_set'} = $dbID;
    return $self->{'update_set'};
}

sub select_from_table {
    my ($self, $par) = @_;

    #if(($loglevel eq 'debug')){ $debugSQL && print STDOUT "SQL CODE: $par\n";}
    my $sth = $self->prepare_stmt($par);
    $sth->execute();
    $self->{'sth'} = $sth;
    my @array=();
    while (my $res = $sth->fetchrow_hashref()) {
    	    push(@array, $res);
    }
    $self->{'select_from_table'} = \@array;
    return $self->{'select_from_table'};
}

sub sth {
    my ($self, $sth) = @_;
    $self->{'sth'} = $sth if $sth;
    return $self->{'sth'};
}

sub exec_dump () {
    my ($self, $no_data) = @_;

    my $attr='';
    my $user  = $self->user;
    my $pass = $self->pass;
    my $host = $self->host;
    my $db = $self->dbname;
    if ($no_data) {
        $attr = "--no_data";
    }

    my $file = File::Spec->catfile($tmpdir,$db.".sql");
    eval{system $mysql_path."mysqldump -u $user -p$pass -h $host $attr $db > $file"};
    unless($@){$self->{'exec_dump'} = $db.".sql";}
    return $self->{'exec_dump'};
}

sub delete_from_table {
    my ($self,$par) = @_;

    my $sth = $self->prepare_stmt($par);

    #if(($loglevel eq 'debug')){ $debugSQL && print STDOUT "SQL CODE: $par\n";}
    my $dbID;
    $sth->execute();
    $dbID = $sth->rows;
    $self->{'delete_from_table'} = $dbID;
    return $self->{'delete_from_table'};
}


sub check_return {
    my ($self, $value, $table_name, $table_column) = @_;

    my $sth = $self->sth;
    my $r = $sth->rows;
    if ($r == 0) {
	print STDERR "DB:check_return => CANNOT FIND THIS $value IN THE $table_name TABLE AND $table_column COLUMN\n";
    }
    $self->{'_check_return'} = $r;
    return $self->{'_check_return'};
}

sub select_update_insert {
    my ($self, $table_column, $sqlselect, $sqlupdate, $sqlinsert, $do_update) = @_;

    $do_update=0 unless defined $do_update;
    $debugSQL && print STDOUT "SQL CODE: $sqlselect\n";
    my @res = @{$self->select_from_table($sqlselect)};
    my $res = $res[0];
    my $dbID = $res->{$table_column};

    if (defined $dbID) {
	#if(($loglevel eq 'debug')){ print STDOUT "This $table_column already exists\n$sqlupdate => id: $dbID\n";}
	if ($do_update && $sqlupdate) {
	    #$sqlupdate=~s/;$/ WHERE $table_column=\"$dbID\";/;
            #if(($loglevel eq 'debug')){ print "$sqlupdate\n";}
	    my $sth = $self->prepare_stmt($sqlupdate);
	    $debugSQL && print STDOUT "SQL CODE: $sqlupdate\n";
	    $sth->execute();
	}
    } else {
	$self->prepare_stmt($sqlinsert);
	$debugSQL && print STDOUT "SQL CODE: $sqlinsert\n";
	$dbID = $self->insert_set($sqlinsert);
	$debug && print STDOUT "inserted id $dbID\n";
    }

    return $dbID;
}

sub multiple_query {
    my ($self, $query, $values) = @_;
    my $dbh = $self->db_connection;

    my $values_string = join( ", " @{$values} );

    $query =~ s/#VALUES#/$values_string/;
    print STDERR $query;

    $dbh->{AutoCommit} = 0;
    my $sth = $self->prepare_stmt($query);
    $sth->execute();

    $dbh->commit();
    return 1;
}

sub _clean_sql () {
   my ($self, $par) = @_;

   $par =~ s/(\"\s+|\s+\")/\"/g;
   return $par;
}

#sub exec_command_sql () {
#     my ($self, $path, $user, $pass, $db, $host, $file, $sql, $debug) = @_;
#
#     $debug && print STDOUT $path."mysql -u $user -h $host -p$pass $db -e \"$sql\" > $file\n";
#     system $path."mysql -u $user -h $host -p$pass $db -e \"$sql\" > $file";
# }

#sub import_into_table () {
#     my ($self, $fields, $file) = @_;
#     my $user  = $self->user;
#     my $pass = $self->pass;
#     my $host = $self->host;
#     my $db = $self->dbname;
#     $debug && print "$mysql_path"."mysqlimport -u $user -p$pass -h $host $db -c $fields $file\n";
#     system $mysql_path."mysqlimport -u $user -p$pass -h $host $db -c $fields $file";
# }

1;
