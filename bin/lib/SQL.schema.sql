CREATE TABLE IF NOT EXISTS `gene` (
  `gene_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `gene_name` TEXT NOT NULL ,
  `sequence` TEXT ,
  `start` INTEGER NOT NULL DEFAULT '0' ,
  `end` INTEGER NOT NULL DEFAULT '0' ,
  `stable_id` TEXT ,
  `strand` TEXT,
  KEY `start_idx` ( `start` ),
  KEY `end_idx` ( `end` )
);

CREATE TABLE IF NOT EXISTS `protein` (
  `protein_id` INTEGER PRIMARY KEY AUTO_INCREMENT  ,
  `protein_name` TEXT NOT NULL DEFAULT '' ,
  `sequence` TEXT,
  `stable_id` TEXT NOT NULL DEFAULT '' ,
  `comment` TEXT,
  `cds_start` INTEGER NOT NULL DEFAULT '0' ,
  `cds_end` INTEGER NOT NULL DEFAULT '0' ,
  `seq_id` TEXT NOT NULL DEFAULT '' ,
  `cds_strand` TEXT ,
  `domain_checked` INTEGER NOT NULL DEFAULT '0' ,
  `gene_id` INTEGER NOT NULL ,
  `sha1` TEXT,
  `status` INTEGER,
  KEY `cds_start_idx` ( `cds_start` ),
  KEY `cds_end_idx` ( `cds_end` ),
  KEY `domain_checked_idx` ( `domain_checked` ),
  KEY `gene_id_idx` ( `gene_id` ),
  KEY `status_idx` ( `status` )
);

CREATE TABLE IF NOT EXISTS `definition` (
  `definition_id` INTEGER PRIMARY KEY AUTO_INCREMENT  ,
  `protein_id` INTEGER  NOT NULL ,
  `definition` TEXT,
  `source` TEXT,
  KEY `protein_id_idx` (`protein_id`)
);


CREATE TABLE IF NOT EXISTS `domain` (
  `domain_id` INTEGER PRIMARY KEY AUTO_INCREMENT  ,
  `domain_name` TEXT NOT NULL DEFAULT '' ,
  `sequence` TEXT ,
  `description` TEXT NOT NULL DEFAULT '' ,
  `rel_start` INTEGER ,
  `rel_end` INTEGER ,
  `db_xref` TEXT NOT NULL DEFAULT '' ,
  `score` REAL DEFAULT NULL ,
  `evalue` REAL DEFAULT NULL ,
  `ip_id` TEXT ,
  `ip_desc` TEXT,
  `go` TEXT,
  `protein_id` INTEGER  NOT NULL,
  KEY `rel_start_idx` ( `rel_start` ),
  KEY `rel_end_idx` ( `rel_end` ),
  KEY `score_idx` (`score`),
  KEY `evalue_idx` (`evalue`),
  KEY `protein_id_idx` (`protein_id`)
);

CREATE TABLE IF NOT EXISTS `kegg_group` (
  `kegg_group_id` INTEGER  PRIMARY KEY AUTO_INCREMENT  ,
  `name` TEXT ,
  `definition` TEXT,
  `pathway` TEXT,
  `module` TEXT ,
  `class` TEXT ,
  `db_links` TEXT ,
  `db_id` TEXT  ,
  `genes` LONGTEXT ,
  `kegg_release` FLOAT,
  KEY `kegg_release_idx` (`kegg_release`)
);

CREATE TABLE IF NOT EXISTS `organism` (
  `organism_id` INTEGER  PRIMARY KEY AUTO_INCREMENT  ,
  `species` TEXT,
  `reign` TEXT NOT NULL DEFAULT '' ,
  `taxonomy_id` INTEGER ,
  `name` TEXT ,
  `synonyms` TEXT,
  `kegg_code` TEXT,
  KEY `taxonomy_id_idx` (`taxonomy_id`)
);

CREATE TABLE IF NOT EXISTS `ortholog` (
  `ortholog_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `name` VARCHAR(255) NOT NULL DEFAULT '' ,
  `db_id` VARCHAR(25),
  `db_name` VARCHAR(25),
  `organism_id` INTEGER NOT NULL,
  UNIQUE( `name`, `db_id`, `db_name`, `organism_id`  ),
  KEY `name_idx` (`name`),
  KEY `db_id_idx` (`db_id`),
  KEY `db_name_idx` (`db_name`),
  KEY `organism_id_idx` (`organism_id`)
);

CREATE TABLE IF NOT EXISTS `protein_ortholog` (
  `protein_ortholog_id` INTEGER  PRIMARY KEY AUTO_INCREMENT ,
  `type` VARCHAR(25),
  `kegg_group_id` INTEGER NOT NULL ,
  `protein_id` INTEGER  NOT NULL ,
  `ortholog_id` INTEGER NOT NULL,
  UNIQUE( `type`, `kegg_group_id`, `protein_id`, `ortholog_id`  ),
  KEY `type_idx` (`type`),
  KEY `kegg_group_id_idx` (`kegg_group_id`),
  KEY `protein_id_idx` (`protein_id`),
  KEY `ortholog_id_idx` (`ortholog_id`)
);

CREATE TABLE IF NOT EXISTS `ipscn_version` (
  `idipscn_version_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `ipscn_version` TEXT NOT NULL ,
  `domain_id` INTEGER  NOT NULL,
  KEY `domain_id_idx` (`domain_id`)
);

CREATE TABLE IF NOT EXISTS `go_term` (
  `go_term_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `go_acc` VARCHAR(30) NOT NULL,
  `go_name` TEXT ,
  `term_type` TEXT,
  KEY `go_acc_idx` (`go_acc`)
);

CREATE TABLE IF NOT EXISTS `protein_go` (
  `protein_go_id` INTEGER PRIMARY KEY AUTO_INCREMENT,
  `go_term_id` INTEGER  NOT NULL ,
  `protein_id` INTEGER  NOT NULL ,
  `source` TEXT,
  KEY `go_term_id_idx` (`go_term_id`),
  KEY `protein_id_idx` (`protein_id`)
);

CREATE TABLE IF NOT EXISTS `blast_hit` (
  `blast_hit_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `protein_id` INTEGER NOT NULL ,
   hit_id TEXT NOT NULL,
   score FLOAT NOT NULL,
   description TEXT,
   start INTEGER,
   end INTEGER,
   length INTEGER,
   evalue REAL NOT NULL,
   hsp_length INTEGER,
   percent_identity REAL,
   KEY `protein_id_idx` (`protein_id`),
   KEY `score_idx` (`score`),
   KEY `start_idx` ( `start` ),
   KEY `end_idx` ( `end` ),
   KEY `length_idx` ( `length` ),
   KEY `evalue_idx` ( `evalue` ),
   KEY `hsp_length_idx` ( `hsp_length` ),
   KEY `percent_identity_idx` ( `percent_identity` )
 );

CREATE TABLE IF NOT EXISTS `signalP` (
  `signalP_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `protein_id` INTEGER  NOT NULL ,
  start INTEGER NOT NULL,
  end INTEGER NOT NULL,
  score REAL NOT NULL,
  description TEXT,
  KEY `protein_id_idx` (`protein_id`),
  KEY `start_idx` ( `start` ),
  KEY `end_idx` ( `end` ),
  KEY `score_idx` (`score`)
);

CREATE TABLE IF NOT EXISTS `chloroP` (
  `chloroP_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `protein_id` INTEGER  NOT NULL ,
  start INTEGER NOT NULL,
  end INTEGER NOT NULL,
  score REAL NOT NULL,
  description TEXT,
  KEY `protein_id_idx` (`protein_id`),
  KEY `start_idx` ( `start` ),
  KEY `end_idx` ( `end` ),
  KEY `score_idx` (`score`)
);

CREATE TABLE IF NOT EXISTS `targetP` (
  `targetP_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `protein_id` INTEGER  NOT NULL ,
  location TEXT NOT NULL,
  RC INTEGER NOT NULL,
  KEY `protein_id_idx` (`protein_id`),
  KEY `RC_idx` (`RC`)
);


CREATE TABLE IF NOT EXISTS `cd_search_features` (
  `cd_search_features_id` INTEGER PRIMARY KEY AUTO_INCREMENT  ,
  `protein_id` INTEGER  NOT NULL ,
  `title` TEXT NOT NULL DEFAULT '' ,
  `Type` TEXT ,
  `coordinates` TEXT,
  `complete_size` INTEGER,
  `mapped_size` INTEGER ,
  `source_domain` TEXT,
  KEY `protein_id_idx` (`protein_id`),
  KEY `complete_size_idx` (`complete_size`),
  KEY `mapped_size_idx` (`mapped_size`)
);

CREATE TABLE IF NOT EXISTS `cd_search_hit` (
  `cd_search_hit_id` INTEGER PRIMARY KEY AUTO_INCREMENT  ,
  `protein_id` INTEGER  NOT NULL ,
  `accession` TEXT NOT NULL DEFAULT '' ,
  `Superfamily` TEXT,
  `Hit_type` TEXT ,
  `PSSM_ID` TEXT,
  `coordinateFrom` INTEGER ,
  `coordinateTo` INTEGER ,
  `E_Value` REAL ,
  `Bitscore` REAL ,
  `Short_name` TEXT ,
  `Incomplete` TEXT,
  KEY `protein_id_idx` (`protein_id`),
  KEY `coordinateFrom_idx` (`coordinateFrom`),
  KEY `coordinateTo_idx` (`coordinateTo`),
  KEY `E_Value_idx` (`E_Value`),
  KEY `Bitscore_idx` (`Bitscore`)
);

CREATE TABLE IF NOT EXISTS `xref` (
  `xref_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `dbname` TEXT NOT NULL DEFAULT '' ,
  `dbid` TEXT NOT NULL DEFAULT '' ,
  `protein_id` INTEGER  NOT NULL,
  KEY `protein_id_idx` (`protein_id`)
);



CREATE TABLE IF NOT EXISTS `orthologxref` (
  `orthologxref_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `dbname` TEXT NOT NULL DEFAULT '' ,
  `dbid` TEXT NOT NULL DEFAULT '' ,
  `ortholog_id` INTEGER NOT NULL,
  KEY `ortholog_id_idx` (`ortholog_id`)
);

CREATE TABLE IF NOT EXISTS `pathway` (
  `pathway_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `stable_id` TEXT NOT NULL DEFAULT '' ,
  `db_id` TEXT NOT NULL DEFAULT '' ,
  `db_name` TEXT NOT NULL DEFAULT '' ,
  `name` TEXT NULL DEFAULT NULL ,
  `go` TEXT NULL DEFAULT NULL ,
  `evidence_type` TEXT NOT NULL DEFAULT ''
);


CREATE TABLE IF NOT EXISTS `reaction` (
  `reaction_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `stable_id` TEXT NOT NULL DEFAULT '' ,
  `db_id` TEXT NOT NULL DEFAULT '' ,
  `db_name` TEXT NOT NULL DEFAULT '' ,
  `name` TEXT NULL DEFAULT NULL ,
  `evidence_type` TEXT NOT NULL DEFAULT ''
);


CREATE TABLE IF NOT EXISTS `ortholog_reaction` (
  `ortholog_reaction_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `ortholog_id` INTEGER NOT NULL ,
  `reaction_id` INTEGER UNSIGNED NOT NULL,
  KEY `ortholog_id_idx` (`ortholog_id`),
  KEY `reaction_id_idx` (`reaction_id`)
);

CREATE TABLE IF NOT EXISTS `complex` (
  `complex_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `db_id` TEXT NOT NULL DEFAULT '',
  `db_name` TEXT NOT NULL DEFAULT '',
  `name` TEXT NULL DEFAULT NULL,
  `stable_id` TEXT NOT NULL DEFAULT ''
);


CREATE TABLE IF NOT EXISTS `ortholog_complex` (
  `ortholog_complex_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `complex_id` INTEGER  NOT NULL ,
  `ortholog_id` INTEGER NOT NULL,
  KEY `complex_id_idx` (`complex_id`),
  KEY `ortholog_id_idx` (`ortholog_id`)
);

CREATE TABLE IF NOT EXISTS `reaction_pathway` (
  `reaction_pathway_id` INTEGER PRIMARY KEY AUTO_INCREMENT ,
  `reaction_id` INTEGER NOT NULL ,
  `pathway_id` INTEGER NOT NULL,
  KEY `reaction_id_idx` (`reaction_id`),
  KEY `pathway_id_idx` (`pathway_id`)
);
