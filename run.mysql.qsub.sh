#!/bin/bash

# qsub run.mysql.qsub.sh

#$ -j y
#$ -l virtual_free=2G,h_rt=172800
#$ -e /users/bi/thermoso/mysqllog/
#$ -o /users/bi/thermoso/mysqllog/
#$ -N MYSQL_container
#$ -m be
#$ -M toni.hermoso@crg.eu
#$ -q long-sl7
#$ -cwd
#$ -V 

MYSQLIMG=/software/bi/biocore_tools/git/singularity/mariadb-10.3.simg
MYSQLDIR=/users/bi/thermoso/mysql
MYSQLCNF=/users/bi/thermoso/mariadb-custom.cnf
IPFILE=/users/bi/thermoso/mysqllog/IP
PROCESSFILE=/users/bi/thermoso/mysqllog/PROCESS
MYSQLUSR=testuser
MYSQLPWD=test12345
MYSQLPORT=12345

bash run.mysql.sh $MYSQLIMG $MYSQLDIR $MYSQLCNF $IPFILE $PROCESSFILE $MYSQLUSR $MYSQLPWD $MYSQLPORT

