package com.thomsonreuters.lsps.transmart.etl

import groovy.sql.Sql

import java.nio.file.Path

class RNASeqSerialHDDDataProcessor extends RNASeqDataProcessor {

    SerialHDDDataLoader serialHDDDataLoader

    RNASeqSerialHDDDataProcessor(conf) {
        super(conf)
        serialHDDDataLoader = new SerialHDDDataLoader(database, conf)
    }

    @Override
    boolean processFiles(Path dir, Sql sql, studyInfo) {
        super.processFiles(dir, sql, studyInfo)
        serialHDDDataLoader.loadSerialHDDData('lt_src_mrna_xml_data', dir, sql, studyInfo)
        true
    }

    @Override
    boolean runStoredProcedures(Object jobId, Sql sql, Object studyInfo) {
        def studyId = studyInfo['id']

        if (super.runStoredProcedures(jobId, sql, studyInfo)) {
            if (studyInfo['runSerialHDDLoad'])
                sql.call("{call " + config.controlSchema + ".I2B2_PROCESS_GENERIC_HDDDATA(?, ?, ?, ?, ?)}", [studyId, 'RNASEQCOG', 'lt_src_rna_subj_samp_map', jobId, Sql.NUMERIC])

            return true
        } else {
            return false
        }
    }
}
