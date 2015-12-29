------------------------------------------------------------------------------
-- Run this script as user TM_CZ (or whatever user you used to define
-- TM_CZ_SCHEMA) after you ran run_as_dba.sql .
------------------------------------------------------------------------------
@STRING_TABLE_T.sql
@I2B2_ADD_LV_PARTITION.sql
@I2B2_DELETE_LV_PARTITION.sql
@I2B2_REBUILD_GLOBAL_INDEXES.sql
@I2B2_UNUSABLE_GLOBAL_INDEXES.sql
@I2B2_ADD_NODE.sql
@I2B2_ADD_NODES.sql
@I2B2_ADD_PLATFORM.sql
@I2B2_ADD_ROOT_NODE.sql
@I2B2_BACKOUT_TRIAL.sql
@I2B2_CREATE_FULL_TREE.sql
@I2B2_CREATE_CONCEPT_COUNTS.sql
@I2B2_DELETE_ALL_NODES.sql
@I2B2_DELETE_ALL_DATA.sql
@I2B2_FILL_IN_TREE.sql
@I2B2_LOAD_CLINICAL_DATA.sql
@I2B2_LOAD_PROTEOMICS_ANNOT.sql
@I2B2_LOAD_SECURITY_DATA.sql
@I2B2_LOAD_STUDY_METADATA.sql
@I2B2_MOVE_STUDY_BY_PATH.sql
@I2B2_PROCESS_MRNA_DATA.sql
@I2B2_PROCESS_SERIAL_HDD_DATA.sql
@I2B2_PROCESS_SNP_DATA.sql
@I2B2_PROCESS_VCF_DATA.sql
@I2B2_PROCESS_RNA_SEQ_DATA.sql
@I2B2_RBM_ZSCORE_CALC.sql
@I2B2_RNA_SEQ_ANNOTATION.sql
@I2B2_PROCESS_PROTEOMICS_DATA.sql
@I2B2_PROCESS_ACGH_DATA.sql
@I2B2_LOAD_CHROM_REGION.sql
@I2B2_PROCESS_QPCR_MIRNA_DATA.sql
@I2B2_MIRNA_ZSCORE_CALC.sql
