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

MYSQLIMG=$1
MYSQLDIR=$2
MYSQLCNF=$3
IPFILE=$4
PROCESSFILE=$5
MYSQLUSR=$6
MYSQLPWD=$7
MYSQLPORT=$8

bash run.mysql.sh $MYSQLIMG $MYSQLDIR $MYSQLCNF $IPFILE $PROCESSFILE $MYSQLUSR $MYSQLPWD $MYSQLPORT

