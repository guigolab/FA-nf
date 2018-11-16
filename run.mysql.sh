#!/bin/bash

set -ueo pipefail

# MySQL containerized instance

MYSQLIMG=$1
MYSQLDIR=$2
MYSQLCNF=$3
IPFILE=$4
PROCESSFILE=$5

mkdir -p $MYSQLDIR
mkdir -p $MYSQLDIR/db
mkdir -p $MYSQLDIR/socket

#sudo /usr/local/bin/singularity build mariadb.simg Singularity.mysql

# Create DB
singularity exec -B $MYSQLDIR/db:/var/lib/mysql -B $MYSQLCNF:/etc/mysql/conf.d/custom.cnf $MYSQLIMG mysql_install_db

# Execute DB
/usr/bin/hostname -I | perl -ne 'if ( $_=~/^(\S+)\s/ ) { $_=~/^(\S+)\s/ ; print $1; }' > $IPFILE

# mysql.ip will be dbhost
# dbuser, dbpass and dbport from config

singularity instance.start -B $MYSQLDIR/db:/var/lib/mysql -B $MYSQLCNF:/etc/mysql/conf.d/custom.cnf -B $MYSQLDIR/socket:/run/mysqld mariadb.simg mysql

# Create $PROCESSFILE here
date > $PROCESSFILE

# Do some work here...


while true
do
	if [ -f $PROCESSFILE ];
		sleep 60
	fi
done

singularity instance.stop mysql


