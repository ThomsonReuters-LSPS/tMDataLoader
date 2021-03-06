-- ---------------------------------------------------------
-- CREATE_TMP_CLINICAL_DATA_TABLES.sql
-- ---------------------------------------------------------
set serveroutput on size unlimited
set linesize 180
set head off

SELECT 'CREATE_TMP_CLINICAL_DATA_TABLES' FROM DUAL;

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = 'I2B2_LOAD_PATH';
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.I2B2_LOAD_PATH';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating TM_DATALOADER.I2B2_LOAD_PATH' FROM DUAL;

CREATE TABLE TM_DATALOADER.I2B2_LOAD_PATH
(
  PATH VARCHAR2(700) PRIMARY KEY,
  PATH50 VARCHAR2(50),
  PATH100 VARCHAR2(100),
  PATH150 VARCHAR2(150),
  PATH200 VARCHAR2(200),
  PATH_LEN integer,
  RECORD_ID rowid
) NOLOGGING;

CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH_LEN ON TM_DATALOADER.I2B2_LOAD_PATH (PATH_LEN, PATH, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH_LEN50 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH_LEN, PATH50, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH_LEN100 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH_LEN, PATH100, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH_LEN150 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH_LEN, PATH150, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH_LEN200 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH_LEN, PATH200, RECORD_ID);

CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH ON TM_DATALOADER.I2B2_LOAD_PATH (PATH, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH50 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH50, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH100 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH100, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH150 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH150, RECORD_ID);
CREATE INDEX tm_dataloader.TM_WZ_IDX_PATH200 ON TM_DATALOADER.I2B2_LOAD_PATH (PATH200, RECORD_ID);

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = 'I2B2_LOAD_TREE_FULL';
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.I2B2_LOAD_TREE_FULL';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating TM_DATALOADER.I2B2_LOAD_TREE_FULL' from dual;

CREATE TABLE TM_DATALOADER.I2B2_LOAD_TREE_FULL
(
  IDROOT          rowid,
  IDCHILD         rowid
) NOLOGGING;

CREATE INDEX tm_dataloader.TM_WZ_IDX_ROOT ON TM_DATALOADER.I2B2_LOAD_TREE_FULL (IDROOT, IDCHILD);
CREATE INDEX tm_dataloader.TM_WZ_IDX_CHILD ON TM_DATALOADER.I2B2_LOAD_TREE_FULL (IDCHILD, IDROOT);

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = 'I2B2_LOAD_PATH_WITH_COUNT';
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.I2B2_LOAD_PATH_WITH_COUNT';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating table TM_DATALOADER.I2B2_LOAD_PATH_WITH_COUNT' from dual;

CREATE TABLE TM_DATALOADER.I2B2_LOAD_PATH_WITH_COUNT
(
  C_FULLNAME          VARCHAR2(2000) PRIMARY KEY,
  NBR_CHILDREN        INTEGER
) NOLOGGING;

-- CREATE INDEX TM_WZ_IDX_PATH_COUNT ON TM_DATALOADER.I2B2_LOAD_PATH_WITH_COUNT (C_FULLNAME);

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('wt_trial_nodes');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.wt_trial_nodes';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

-- Type: TABLE; Owner: TM_DATALOADER; Name: WT_TRIAL_NODES
--
 CREATE TABLE "TM_DATALOADER"."WT_TRIAL_NODES"
  (     "LEAF_NODE" VARCHAR2(4000 BYTE),
"CATEGORY_CD" VARCHAR2(250 BYTE),
"VISIT_NAME" VARCHAR2(250 BYTE),
"SAMPLE_TYPE" VARCHAR2(250 BYTE),
"DATA_LABEL" VARCHAR2(500 BYTE),
"NODE_NAME" VARCHAR2(500 BYTE),
"DATA_VALUE" VARCHAR2(500 BYTE),
"DATA_TYPE" VARCHAR2(20 BYTE),
"DATA_LABEL_CTRL_VOCAB_CODE" VARCHAR2(500 BYTE),
"DATA_VALUE_CTRL_VOCAB_CODE" VARCHAR2(500 BYTE),
"DATA_LABEL_COMPONENTS" VARCHAR2(1000 BYTE),
"LINK_TYPE" VARCHAR2(50 BYTE),
"OBS_STRING" VARCHAR2(100 BYTE),
"VALUETYPE_CD" VARCHAR2(50 BYTE),
"REC_NUM" NUMBER(18,0)
  ) SEGMENT CREATION IMMEDIATE
 TABLESPACE "TRANSMART" ;

CREATE INDEX tm_dataloader.IDX_WTN_LOAD_CLINICAL ON TM_DATALOADER.WT_TRIAL_NODES(LEAF_NODE,CATEGORY_CD,DATA_LABEL);
CREATE INDEX tm_dataloader.IDX_WT_TRIALNODES ON TM_DATALOADER.WT_TRIAL_NODES(LEAF_NODE,NODE_NAME);

SELECT 'Creating table TM_DATALOADER.wt_del_nodes' FROM DUAL;
@@wt_del_nodes.sql

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('wt_num_data_types');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.wt_num_data_types';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating table TM_DATALOADER.wt_num_data_types' FROM DUAL;

CREATE TABLE TM_DATALOADER.wt_num_data_types NOLOGGING AS SELECT * FROM tm_wz.wt_num_data_types where 1=0;

ALTER TABLE TM_DATALOADER.wt_num_data_types MODIFY category_cd VARCHAR2(250);

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('WRK_CLINICAL_DATA');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.WRK_CLINICAL_DATA';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating table TM_DATALOADER.WRK_CLINICAL_DATA' FROM DUAL;

CREATE TABLE TM_DATALOADER.WRK_CLINICAL_DATA NOLOGGING AS SELECT * FROM tm_wz.wrk_clinical_data where 1=0;

CREATE INDEX tm_dataloader.IDX_WRK_CLN_ID_VALUE ON TM_DATALOADER.WRK_CLINICAL_DATA(usubjid, data_value, data_type);

SELECT 'Creating table TM_DATALOADER.wt_clinical_data_dups' FROM DUAL;
@@wt_clinical_data_dups.sql

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('lt_src_clinical_data');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.lt_src_clinical_data';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating table TM_DATALOADER.lt_src_clinical_data' FROM DUAL;

CREATE TABLE TM_DATALOADER.lt_src_clinical_data NOLOGGING AS SELECT * FROM tm_lz.lt_src_clinical_data where 1=0;

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('lt_src_mrna_subj_samp_map');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.lt_src_mrna_subj_samp_map';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating TM_DATALOADER.lt_src_mrna_subj_samp_map' FROM DUAL;
CREATE TABLE TM_DATALOADER.lt_src_mrna_subj_samp_map NOLOGGING AS SELECT * FROM tm_lz.lt_src_mrna_subj_samp_map where 1=0;

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('lt_src_mrna_data');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.lt_src_mrna_data';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating TM_DATALOADER.lt_src_mrna_data' FROM DUAL;
CREATE TABLE TM_DATALOADER.lt_src_mrna_data NOLOGGING AS SELECT * FROM tm_lz.lt_src_mrna_data where 1=0;

DECLARE
rows int;
drop_sql VARCHAR2(500);
BEGIN
	SELECT COUNT(*)
	INTO rows
	FROM dba_tables
	WHERE owner='TM_DATALOADER'
	 and table_name = upper('lt_src_deapp_annot');
 
 	IF rows > 0 
 	THEN
	 	drop_sql := 'DROP TABLE TM_DATALOADER.lt_src_deapp_annot';
		dbms_output.put_line(drop_sql);
 	    EXECUTE IMMEDIATE drop_sql;
 	END IF;
 END;
/

SELECT 'Creating work mrna node tables.' FROM DUAL;
@@wt_mrna_node_values.sql
@@wt_mrna_nodes.sql

SELECT 'Creating TM_DATALOADER.lt_src_ tables...' FROM DUAL;

@@lt_src_deapp_annot.sql
@@lt_src_qpcr_mirna_data.sql

SELECT 'Creating wt QPCR tables...' FROM DUAL;
@@wt_qpcr_mirna_nodes.sql
@@wt_qpcr_mirna_node_values.sql

SELECT 'Creating lt_qpcr_mirna_annotation table...' FROM DUAL;
@@lt_qpcr_mirna_annotation.sql

SELECT 'Creating tmp_subject_info table.' FROM DUAL;
@@tmp_subject_info.sql

SELECT 'Creating wt_subject_acgh_region. ' FROM DUAL;
@@wt_subject_acgh_region.sql

SELECT 'Createing wt_subject_rna tables...' FROM DUAL;
@@wt_subject_rna_logs
@@wt_subject_rna_calcs
@@wt_subject_rna_med
@@wt_subject_rna_probeset.sql
SELECT 'Creating metabolomic tables...' FROM DUAL;
@@wt_metabolomic_nodes.sql
@@wt_metabolomic_node_values.sql
@@wt_subject_mbolomics_probeset.sql
@@wt_subject_metabolomics_logs.sql
@@wt_subject_metabolomics_calcs.sql
@@wt_subject_metabolomics_med.sql

SELECT 'Creating mirna tables...' FROM DUAL;
@@wt_subject_mirna_probeset.sql
@@wt_subject_mirna_calcs.sql
@@wt_subject_mirna_med.sql
@@wt_subject_mirna_logs.sql
@@lt_src_mirna_deapp_annot.sql
@@lt_src_mirna_display_mapping.sql
@@lt_src_mirna_subj_samp_map.sql

SELECT 'Creating proteomic tables...' FROM DUAL;
@@wt_subject_proteomics_calcs.sql
@@wt_subject_proteomics_logs.sql
@@wt_subject_proteomics_med.sql
@@wt_subject_proteomics_probeset.sql
@@lt_src_proteomics_data.sql
@@lt_src_proteomics_sub_sam_map.sql
ALTER TABLE tm_lz.lt_src_deapp_annot
   modify gene_symbol character varying(400 byte);
@@wt_proteomics_nodes.sql
@@wt_proteomics_node_values.sql

SELECT 'Creating RNA SEQ Node tables.' FROM DUAL;
@@wt_rna_seq_nodes.sql
@@wt_rna_seq_node_values.sql
