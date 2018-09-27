dbname=$1

echo "select count(*) from protein"
echo 'select count(*) from protein;'|sqlite3 $dbname
echo "select count(*) from gene"
echo 'select count(*) from gene;'|sqlite3 $dbname

echo "select count(*) from ortholog"
echo 'select count(*) from ortholog;'|sqlite3 $dbname
echo "select count(distinct protein_id) from protein_ortholog"
echo 'select count(distinct protein_id) from protein_ortholog;'|sqlite3 $dbname

echo "select count(*) from kegg_group"
echo 'select count(*) from kegg_group;'|sqlite3 $dbname
echo "select count(*) from organism"
echo 'select count(*) from organism;'|sqlite3 $dbname

echo "select count(*) from domain"
echo 'select count(*) from domain;'|sqlite3 $dbname
echo "select count(distinct protein_id) from domain"
echo 'select count(distinct protein_id) from domain;'|sqlite3 $dbname


echo "select count(*) from protein_go"
echo 'select count(*) from protein_go;'|sqlite3 $dbname
echo "select distinct source, count(*) from protein_go group by source;"
echo "select distinct source, count(*) from protein_go group by source;"|sqlite3 $dbname
#echo "select  source, count(*) from protein_go group by source;"
#echo "select  source, count(*) from protein_go group by source;"|sqlite3 $dbname

#echo "select source, count(distinct protein_id) from protein_go where source is 'blast2go';"|sqlite3 $dbName
#echo "select source, count(distinct protein_id) from protein_go where source is 'IPSCN';"|sqlite3 $dbName
#echo "select source, count(distinct protein_id) from protein_go where source is 'KEGG';"|sqlite3 $dbName


echo "select  count(*) from go_term"
echo 'select  count(*) from go_term;'|sqlite3 $dbname

#echo "select term_type, count(distinct protein_id) from protein_go, go_term  where protein_go.go_term_id=go_term.go_term_id group by term_type;"
#echo "select term_type, count(distinct protein_id) from protein_go, go_term  where protein_go.go_term_id=go_term.go_term_id group by term_type;"|sqlite3 $dbName


echo "select status, count(*)  from protein group by status"
echo 'select status, count(*)  from protein group by status;'|sqlite3 $dbname

echo "select count(*) from protein where definition not like '' and definition is not null"
echo "select count(*) from protein where definition not like '' and definition is not null ;" |sqlite3 $dbname

echo "select  count(*) from blast_hit"
echo 'select  count(*) from blast_hit;'|sqlite3 $dbname

echo "select  count(distinct protein_id) from blast_hit"
echo 'select  count(distinct protein_id) from blast_hit;'|sqlite3 $dbname

#cd hits
echo "select  count(*) from cd_search_hit"
echo 'select  count(*) from cd_search_hit;'|sqlite3 $dbname

echo "select  count(distinct protein_id) from cd_search_hit"
echo 'select  count(distinct protein_id) from cd_search_hit;'|sqlite3 $dbname

echo "select  count(*) from cd_search_features"
echo 'select  count(*) from cd_search_features;'|sqlite3 $dbname

echo "select  count(distinct protein_id) from cd_search_features"
echo 'select  count(distinct protein_id) from cd_search_features;'|sqlite3 $dbname

#signalP
echo "select  count(*) from signalP"
echo 'select  count(*) from signalP;'|sqlite3 $dbname

echo "select  count(distinct protein_id) from signalP"
echo 'select  count(distinct protein_id) from signalP;'|sqlite3 $dbname

#targetP
echo "select  count(*) from tardetP"
echo 'select  count(*) from targetP;'|sqlite3 $dbname

echo "select  count(distinct protein_id) from targetP"
echo 'select  count(distinct protein_id) from targetP;'|sqlite3 $dbname

#some additional checks
echo "select  count(distinct protein_id) from domain where db_xref in ('PANTHER', 'Pfam', 'TIGRFAM', 'HAMAP', 'SUPERFAMILY'); "
echo "select  count(distinct protein_id) from domain where db_xref in ('PANTHER', 'Pfam', 'TIGRFAM', 'HAMAP', 'SUPERFAMILY'); "|sqlite3 $dbname


