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
#$ -V 

MYSQLIMG=/path/mysql/image
MYSQLDIR=/path/store/mysql
MYSQLCNF=/path/cnf
IPFILE=/path/for/ip
PROCESSFILE=/path/for/process

bash run.mysql.sh $MYSQLIMG $MYSQLDIR $MYSQLCNF $IPFILE $PROCESSFILE 

