package com.thomsonreuters.lsps.transmart.etl

import com.thomsonreuters.lsps.transmart.files.CsvLikeFile
import com.thomsonreuters.lsps.transmart.files.MetaInfoHeader
import com.thomsonreuters.lsps.transmart.files.VcfFile
import com.thomsonreuters.lsps.transmart.sql.SqlMethods
import groovy.io.FileType
import groovy.sql.Sql

/**
 * Created by bondarev on 4/3/14.
 */
class VCFDataProcessor extends DataProcessor {
    VCFDataProcessor(Object conf) {
        super(conf)
    }

    private void loadMappingFile(File mappingFile, studyInfo) {
        def csv = new CsvLikeFile(mappingFile, '#')
        if (!studyInfo.id) {
            def metaInfo = (csv as MetaInfoHeader).metaInfo
            studyInfo.id = metaInfo.STUDY_ID
            studyInfo.genomeBuild = metaInfo.GENOME_BUILD
            studyInfo.platformId = metaInfo.PLATFORM_ID ?:
                    (studyInfo.genomeBuild ? "VCF_${studyInfo.genomeBuild}".toString() : 'VCF')
            studyInfo.platformName = metaInfo.PLATFORM_NAME ?: studyInfo.platformId
            studyInfo.species = metaInfo.SPECIES ?: 'Homo Sapiens'
        }
        def sampleMapping = [:]
        csv.eachEntry {
            String subjectId = it[0]
            String sampleCd = it[1]
            sampleMapping[sampleCd] = subjectId
        }
        studyInfo.sampleMapping = sampleMapping
    }

    private void cleanupVcfTrialData(Sql sql, String trialId, String sourceCd) {
        boolean autoCommitMode = sql.connection.autoCommit
        sql.connection.autoCommit = false
        def dataSetIds = sql.rows('SELECT DISTINCT dataset_id FROM deapp.de_variant_subject_summary vss, deapp.de_subject_sample_mapping sm WHERE sm.assay_id = vss.assay_id AND trial_name = ? AND source_cd = ?', trialId, sourceCd)
        dataSetIds*.dataset_id.each { dataSetId ->
            deleteDataSet(sql, dataSetId)
        }
        sql.commit()
        sql.connection.autoCommit = autoCommitMode
    }

    private void deleteDataSet(Sql sql, dataSetId) {
        sql.execute('DELETE FROM deapp.de_variant_population_data WHERE dataset_id = ?', dataSetId)
        sql.execute('DELETE FROM deapp.de_variant_population_info WHERE dataset_id = ?', dataSetId)
        sql.execute('DELETE FROM deapp.de_variant_subject_summary WHERE dataset_id = ?', dataSetId)
        sql.execute('DELETE FROM deapp.de_variant_subject_detail WHERE dataset_id = ?', dataSetId)
        sql.execute('DELETE FROM deapp.de_variant_subject_idx WHERE dataset_id = ?', dataSetId)
        sql.execute('DELETE FROM deapp.de_variant_dataset WHERE dataset_id = ?', dataSetId)
    }

    @Override
    boolean processFiles(File dir, Sql sql, studyInfo) {
        File mappingFile = new File(dir, 'Subject_Sample_Mapping_File.txt')
        if (!mappingFile.exists()) {
            logger.log(LogType.ERROR, "Mapping file not found")
            return false
        }
        loadMappingFile(mappingFile, studyInfo)

        String studyId = studyInfo.id as String
        def samplesLoader = new SamplesLoader(studyId)
        studyInfo.sources = []
        def files = []
        dir.eachFileMatch(FileType.FILES, ~/(?i).*\.vcf$/) { files << it }
        if (!files.every { processFile(it, sql, samplesLoader, studyInfo) }) {
            return false
        }
        samplesLoader.loadSamples(sql)
        return true
    }

    def createDataSet(Sql sql, trialId, sourceCd) {
        use(SqlMethods) {
            String dataSetId = "${trialId}:${sourceCd}"
            cleanupVcfTrialData(sql, trialId, sourceCd)
            deleteDataSet(sql, dataSetId)
            logger.log(LogType.DEBUG, 'Loading study information into deapp.de_variant_dataset')
            sql.insertRecord('deapp.de_variant_dataset',
                    dataset_id: dataSetId, etl_id: 'tMDataLoader', genome: 'hg19',
                    etl_date: Calendar.getInstance())
            sql.commit()
            return dataSetId
        }
    }

    def checkAllSamplesMapped(VcfFile vcfFile, Map sampleMapping) {
        List<String> notMappedSamples = vcfFile.samples.findAll { !sampleMapping.containsKey(it) }
        if (notMappedSamples) {
            logger.log(LogType.ERROR, "Not all samples mapped to subjects! Please, check mapping file. Not mapped samples: ${notMappedSamples}")
            return false
        }
        return true
    }

    def processFile(File inputFile, Sql sql, SamplesLoader samplesLoader, studyInfo) {
        def vcfFile = new VcfFile(inputFile)
        vcfFile.validate()
        def sampleMapping = studyInfo.sampleMapping
        if (!checkAllSamplesMapped(vcfFile, sampleMapping as Map)) {
            return false
        }
        String vcfName = inputFile.name.replaceFirst(/\.\w+$/, '').replaceAll(/\./, '_')
        String sourceCd = vcfName.toUpperCase()
        studyInfo.sources << sourceCd
        String dataSetId = createDataSet(sql, studyInfo.id, sourceCd)
        logger.log(LogType.MESSAGE, "Processing file ${inputFile.getName()}")
        use(SqlMethods) {
            DataLoader.start(database, 'deapp.de_variant_subject_idx', ['DATASET_ID', 'SUBJECT_ID', 'POSITION']) { st ->
                logger.log(LogType.DEBUG, "Loading samples: ${vcfFile.samples.size()}")
                vcfFile.samples.eachWithIndex { sample, idx ->
                    st.addBatch([dataSetId, sample, idx + 1])
                    samplesLoader.addSample("VCF+${vcfName}", sampleMapping[sample], sample, studyInfo.platformId,
                            sourceCd: sourceCd)
                }
            }

            logger.log(LogType.DEBUG, 'Loading population info')
            DataLoader.start(database, 'deapp.de_variant_population_info',
                    ['DATASET_ID', 'INFO_NAME', 'DESCRIPTION', 'TYPE', 'NUMBER']) { populationInfo ->
                vcfFile.infoFields.values().each {
                    populationInfo.addBatch([dataSetId, it.id, it.description, it.type, it.number])
                }
            }

            logger.log(LogType.DEBUG, 'Loading subject summary, subject detail & population data')
            int lineNumber = 0
            DataLoader.start(database, 'deapp.de_variant_subject_detail',
                    ['DATASET_ID', 'RS_ID', 'CHR', 'POS', 'REF', 'ALT', 'QUAL',
                     'FILTER', 'INFO', 'FORMAT', 'VARIANT_VALUE']) { subjectDetail ->
                DataLoader.start(database, 'deapp.de_variant_subject_summary',
                        ['DATASET_ID', 'SUBJECT_ID', 'RS_ID', 'CHR', 'POS', 'VARIANT', 'VARIANT_FORMAT', 'VARIANT_TYPE',
                         'REFERENCE', 'ALLELE1', 'ALLELE2']) { subjectSummary ->
                    DataLoader.start(database, 'deapp.de_variant_population_data',
                            ['DATASET_ID', 'CHR', 'POS', 'INFO_NAME', 'INFO_INDEX',
                             'INTEGER_VALUE', 'FLOAT_VALUE', 'TEXT_VALUE']) { populationData ->
                        vcfFile.eachEntry { VcfFile.Entry entry ->
                            lineNumber++
                            logger.log(LogType.PROGRESS, "[${lineNumber}]")
                            writeVariantSubjectDetailRecord(dataSetId, subjectDetail, entry)
                            writeVariantSubjectSummaryRecords(dataSetId, subjectSummary, entry)
                            writeVariantPopulationDataRecord(dataSetId, populationData, entry)
                        }
                    }
                }
            }
            logger.log(LogType.PROGRESS, '')
        }
        return true
    }

    private void writeVariantPopulationDataRecord(String trialId, st, VcfFile.Entry entry) {
        entry.infoData.entrySet().each {
            VcfFile.InfoField infoField = it.key
            Object[] values = it.value
            if (infoField != null && infoField.type != null) {
                String type = infoField.type.toLowerCase()
                Integer intValue
                Float floatValue
                String textValue
                values.eachWithIndex { value, int idx ->
                    switch (type) {
                        case 'integer':
                        case 'flag':
                            intValue = value as int
                            break
                        case 'float':
                            floatValue = value as float
                            break
                        case 'character':
                        case 'string':
                            textValue = value as String
                            break
                    }
                    st.addBatch([trialId, entry.chromosome, entry.chromosomePosition, infoField.id,
                                 idx, intValue, floatValue, textValue])
                }
            } else {
                logger.log(LogType.WARNING, "Field [${it.key?.id}] with value=${it.value} won't be added to deapp.de_variant_population_data " +
                        "because it does not have description in INFO part in file header.")
            }
        }
    }

    private void writeVariantSubjectSummaryRecords(String trialId, st, VcfFile.Entry entry) {
        CharSequence variantType = entry.reference.size() == 1 &&
                entry.alternatives.size() == 1 && entry.alternatives[0].size() == 1 ? 'SNV' : 'DIV'
        entry.samplesData.entrySet().each { sampleEntry ->
            VcfFile.SampleData sampleData = sampleEntry.value
            CharSequence variant = ''
            CharSequence variantFormat = ''
            Integer allele1 = sampleData.allele1 != null && sampleData.allele1 != '.' ? sampleData.allele1 as int : null
            Integer allele2 = sampleData.allele2 != null && sampleData.allele2 != '.' ? sampleData.allele2 as int : null
            boolean reference = false

            if (sampleData.allele1 != null && sampleData.allele2 == null) {
                if (sampleData.allele1 == '0') {
                    reference = true
                    variant = entry.reference
                    variantFormat = 'R'
                } else {
                    if (!allele1.is(null)) {
                        variant = entry.alternatives[allele1 - 1]
                        variantFormat = "V"
                    }
                }
            } else {
                if (sampleData.allele1 == '0') {
                    variant += entry.reference
                    variantFormat += 'R'
                } else {
                    if (!allele1.is(null)) {
                        variant += entry.alternatives[allele1 - 1]
                        variantFormat += 'V'
                    }
                }
                variant += sampleData.alleleSeparator
                variantFormat += sampleData.alleleSeparator
                if (sampleData.allele2 == '0') {
                    variant += entry.reference
                    variantFormat += 'R'
                } else {
                    if (!allele2.is(null)) {
                        variant += entry.alternatives[allele2 - 1]
                        variantFormat += 'V'
                    }
                }
                reference = (allele1.is(null) || allele1 == 0) && (allele2.is(null) || allele2 == 0)
            }

            st.addBatch([trialId, sampleEntry.key, entry.probesetId, entry.chromosome, entry.chromosomePosition,
                         variant, variantFormat, variantType,
                         reference, allele1, allele2
            ])
        }
    }

    private def writeVariantSubjectDetailRecord(CharSequence trialId, def st, VcfFile.Entry entry) {
        st.addBatch([
                trialId, entry.probesetId, entry.chromosome, entry.chromosomePosition, entry.reference,
                entry.alternatives.join(','), entry.qual, entry.filter, entry.infoString, entry.formatString,
                entry.sampleValues.join('\t')
        ])
    }

    private void loadPlatform(jobId, Sql sql, studyInfo) {
        String markerType = 'VCF'
        boolean loaded = sql.rows('select 1 from deapp.de_gpl_info where platform = ?', studyInfo.platformId as String)
                .asBoolean()
        if (!loaded) {
            use(SqlMethods) {
                sql.callProcedure("${config.controlSchema}.i2b2_add_platform",
                        studyInfo.platformId, studyInfo.platformName, studyInfo.species, markerType,
                        studyInfo.genomeBuild, null, jobId)
            }
        }
    }

    @Override
    boolean runStoredProcedures(jobId, Sql sql, studyInfo) {
        def studyId = studyInfo['id']
        def studyNode = studyInfo['node']
        def sources = studyInfo['sources']
        if (studyId && studyNode) {
            loadPlatform(jobId, sql, studyInfo)
            use(SqlMethods) {
                sources.each { source ->
                    sql.callProcedure("${config.controlSchema}.i2b2_process_vcf_data",
                            studyId, studyNode, source, config.securitySymbol, jobId)
                }
            }
            return true
        } else {
            logger.log(LogType.ERROR, 'Study ID or Node not defined')
            return false
        }
    }

    @Override
    String getProcedureName() {
        return "${config.controlSchema}.I2B2_PROCESS_VCF_DATA"
    }
}
