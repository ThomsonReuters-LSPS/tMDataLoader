CREATE OR REPLACE PROCEDURE analyze_table (p_owner VARCHAR2, p_table VARCHAR2, p_job_id NUMBER := NULL)
AS
    l_owner VARCHAR2(32);
    l_table VARCHAR2(32);
    stats_locked exception;
    pragma exception_init(stats_locked, -20005);
    stats_locked2 exception;
    pragma exception_init(stats_locked2, -38029);

    --Audit variables
    job_was_created boolean;
    current_schema_name VARCHAR2(32);
    procedure_name VARCHAR2(32);
    l_job_id INTEGER;
    step INTEGER;
BEGIN
    --Set Audit Parameters
    step := 0;
    l_job_id := p_job_id;
    job_was_created := false;
    SELECT sys_context('USERENV', 'CURRENT_SCHEMA') INTO current_schema_name FROM dual;
    procedure_name := $$PLSQL_UNIT;

    -- Audit JOB Initialization
    -- If Job ID does not exist, then this is a single procedure run and we need to create it
    IF l_job_id IS NULL OR l_job_id < 1 THEN
        job_was_created := true;
        cz_start_audit(procedure_name, current_schema_name, l_job_id);
    END IF;

    l_owner := p_owner;
    l_table := p_table;
    BEGIN
        FOR i IN 0..99 LOOP
            IF i = 99 THEN
                raise_application_error(-20100, 'Too many synonyms for '||p_owner||'.'||p_table);
            END IF;
            SELECT table_owner, table_name INTO l_owner, l_table FROM all_synonyms WHERE owner=l_owner AND synonym_name=l_table;
        END LOOP;
    EXCEPTION
        WHEN no_data_found THEN
            NULL;
    END;
    BEGIN
        dbms_stats.gather_table_stats(l_owner, l_table, cascade => true);
        step := step + 1;
        cz_write_audit(l_job_id, current_schema_name, procedure_name, 'Analyzed table '||p_owner||'.'||p_table, 0, step, 'Done');
    EXCEPTION
        WHEN stats_locked OR stats_locked2 THEN
            step := step + 1;
            cz_write_audit(l_job_id, current_schema_name, procedure_name, 'Statistics is locked for table '||p_owner||'.'||p_table, 0, step, 'Done');
    END;

    IF job_was_created THEN
        cz_end_audit(l_job_id, 'SUCCESS');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        IF job_was_created THEN
            cz_error_handler(l_job_id, procedure_name);
            cz_end_audit(l_job_id, 'FAIL');
        END IF;
        RAISE;
END;
/
