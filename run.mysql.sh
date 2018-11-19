#!/bin/bash

set -ueo pipefail

# MySQL containerized instance

MYSQLIMG=$1
MYSQLDIR=$2
MYSQLCNF=$3
IPFILE=$4
PROCESSFILE=$5
MYSQLUSR=$6
MYSQLPWD=$7
MYSQLPORT=$8

mkdir -p $MYSQLDIR
mkdir -p $MYSQLDIR/db
mkdir -p $MYSQLDIR/socket

#sudo /usr/local/bin/singularity build mariadb.simg Singularity.mysql

# Create DB
singularity exec -B $MYSQLDIR/db:/var/lib/mysql -B $MYSQLCNF:/etc/mysql/conf.d/custom.cnf $MYSQLIMG mysql_install_db

# Execute DB
hostname -I | perl -lne 'if ( $_=~/^(\S+)\s/ ) { $_=~/^(\S+)\s/ ; print $1; }' > $IPFILE

# mysql.ip will be dbhost
# dbuser, dbpass and dbport from config

singularity instance.start -B $MYSQLDIR/db:/var/lib/mysql -B $MYSQLCNF:/etc/mysql/conf.d/custom.cnf -B $MYSQLDIR/socket:/run/mysqld $MYSQLIMG mysql

sleep 15

singularity exec instance://mysql mysql -uroot -h127.0.0.1 -P$MYSQLPORT -e "GRANT ALL PRIVILEGES on *.* TO '$MYSQLUSR'@'%' identified by '$MYSQLPWD' ;"

# Create $PROCESSFILE here
date > $PROCESSFILE

# Do some work here...


while [ -f $PROCESSFILE ];
do
	echo $PROCESSFILE
	sleep 10;
done;

singularity instance.stop mysql
exit 0

