-- Function: i2b2_load_clinical_data(character varying, character varying, character varying, character varying, numeric)

-- DROP FUNCTION i2b2_load_clinical_data(character varying, character varying, character varying, character varying, numeric);

CREATE OR REPLACE FUNCTION i2b2_load_clinical_data(
  trial_id character varying,
  top_node character varying,
  secure_study character varying DEFAULT 'N'::character varying,
  highlight_study character varying DEFAULT 'N'::character varying,
  alwaysSetVisitName character varying DEFAULT 'N'::character varying,
  currentjobid numeric DEFAULT (-1),
  merge_mode character varying DEFAULT 'REPLACE'::character varying)
  RETURNS numeric AS
$BODY$
/*************************************************************************
* Copyright 2008-2012 Janssen Research & Development, LLC.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
******************************************************************/
Declare

	--Audit variables
	databaseName 	VARCHAR(100);
	procedureName 	VARCHAR(100);
	jobID 			numeric(18,0);
	stepCt 			numeric(18,0);
	rowCt			numeric(18,0);
	errorNumber		character varying;
	errorMessage	character varying;
	rtnCd			integer;

	topNode			varchar(2000);
	topLevel		numeric(10,0);
	root_node		varchar(2000);
	root_level		integer;
	study_name		varchar(2000);
	TrialID			varchar(100);
	secureStudy		varchar(200);
	etlDate			timestamp;
	tPath			varchar(2000);
	pCount			integer;
	pExists			integer;
	rtnCode			integer;
	tText			varchar(2000);
	recreateIndexes boolean;
	recreateIndexesSql text;
	leaf_fullname varchar(700);
	updated_patient_nums integer[];
	pathRegexp varchar(2000);
	updatedPath varchar(2000);
  cur_row RECORD;
	pathCount integer;
	trialVisitNum NUMERIC(18, 0);
	studyNum      NUMERIC(18, 0);

	addNodes CURSOR is
	select DISTINCT leaf_node, node_name
	from  wt_trial_nodes a;

		trialVisitLabels CURSOR IS
		SELECT DISTINCT
			trial_visit_label,
			visit_name
		FROM tm_dataloader.wrk_clinical_data;

	--	cursor to define the path for delete_one_node  this will delete any nodes that are hidden after i2b2_create_concept_counts

	delNodes CURSOR is
	select distinct c_fullname
	from  i2b2metadata.i2b2
	where c_fullname like topNode || '%' escape '`'
      and substr(c_visualattributes,2,1) = 'H';

	--	cursor to determine if any leaf nodes exist in i2b2 that are not used in this reload (node changes from text to numeric or numeric to text)

	delUnusedLeaf cursor is
	select l.c_fullname
	from i2b2metadata.i2b2 l
	where l.c_visualattributes like 'L%'
	  and l.c_fullname like topNode || '%' escape '`'
	  and l.c_fullname not in
		 (select t.leaf_node
		  from wt_trial_nodes t
		  union
		  select m.c_fullname
		  from deapp.de_subject_sample_mapping sm
			  ,i2b2metadata.i2b2 m
		  where sm.trial_name = TrialId
		    and sm.concept_code = m.c_basecode
			and m.c_visualattributes like 'L%');

BEGIN

	TrialID := upper(trial_id);
	secureStudy := upper(secure_study);

	databaseName := current_schema();
	procedureName := 'I2B2_LOAD_CLINICAL_DATA';

	--Audit JOB Initialization
	--If Job ID does not exist, then this is a single procedure run and we need to create it
	select case when coalesce(currentjobid, -1) < 1 then cz_start_audit(procedureName, databaseName) else currentjobid end into jobId;

	stepCt := 0;
	stepCt := stepCt + 1;
	topNode := REGEXP_REPLACE('\' || top_node || '\','(\\){2,}', '\', 'g');
	
	tText := 'Start i2b2_load_clinical_data for ' || TrialId || ' topNode = ' || topNode;
	select cz_write_audit(jobId,databaseName,procedureName,tText,0,stepCt,'Done') into rtnCd;

	if (secureStudy not in ('Y','N') ) then
		secureStudy := 'Y';
	end if;

	--	figure out how many nodes (folders) are at study name and above
	--	\Public Studies\Clinical Studies\Pancreatic_Cancer_Smith_GSE22780\: topLevel = 4, so there are 3 nodes
	--	\Public Studies\GSE12345\: topLevel = 3, so there are 2 nodes

	select length(topNode)-length(replace(topNode,'\','')) into topLevel;

	if topLevel < 3 then
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Path specified in top_node must contain at least 2 nodes',0,stepCt,'Done') into rtnCd;
		select cz_error_handler (jobID, procedureName, '-1', 'Application raised error') into rtnCd;
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end if;
	--	truncate wrk_clinical_data and load data from external file

	execute ('truncate table wrk_clinical_data');

	--	insert data from lt_src_clinical_data to wrk_clinical_data

	BEGIN
		INSERT INTO wrk_clinical_data
		(study_id
			, site_id
			, subject_id
			, visit_name
			, data_label
			, modifier_cd
			, data_value
			, units_cd
			, date_timestamp
			, category_cd
			, ctrl_vocab_code
			, sample_cd
			, valuetype_cd
			, baseline_value
			, end_date
			, start_date
			, instance_num
			, trial_visit_label
		)
			SELECT
				study_id,
				site_id,
				subject_id,
				visit_name,
				data_label,
				modifier_cd,
				data_value,
				units_cd,
				date_timestamp,
				category_cd,
				ctrl_vocab_code,
				sample_cd,
				valuetype_cd,
				baseline_value,
				end_date,
				start_date,
				instance_num,
				trial_visit_label
			FROM lt_src_clinical_data;
		EXCEPTION
		WHEN OTHERS
			THEN
				errorNumber := SQLSTATE;
				errorMessage := SQLERRM;
				--Handle errors.
				SELECT cz_error_handler(jobID, procedureName, errorNumber, errorMessage)
				INTO rtnCd;
				--End Proc
				SELECT cz_end_audit(jobID, 'FAIL')
				INTO rtnCd;
				RETURN -16;
	END;
	GET DIAGNOSTICS rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	SELECT
		cz_write_audit(jobId, databaseName, procedureName, 'Load lt_src_clinical_data to work table', rowCt, stepCt, 'Done')
	INTO rtnCd;

	-- Update trial_visit_label field
	UPDATE wrk_clinical_data SET
		trial_visit_label = 'Default'
	WHERE trial_visit_label is null;

	-- Get root_node from topNode

	select parse_nth_value(topNode, 2, '\') into root_node;

	select count(*) into pExists
	from i2b2metadata.table_access
	where c_name = root_node;

	select count(*) into pCount
	from i2b2metadata.i2b2
	where c_name = root_node;

	if pExists = 0 or pCount = 0 then
		select i2b2_add_root_node(root_node, jobId) into rtnCd;
	end if;

	select c_hlevel into root_level
	from i2b2metadata.table_access
	where c_name = root_node;

	-- Get study name from topNode

	select parse_nth_value(topNode, topLevel, '\') into study_name;

	--	Add any upper level nodes as needed

	tPath := REGEXP_REPLACE(replace(topNode,study_name,''),'(\\){2,}', '\', 'g');
	select length(tPath) - length(replace(tPath,'\','')) into pCount;

	if pCount > 2 then
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Adding upper-level nodes for "' || tPath || '"',0,stepCt,'Done') into rtnCd;
		select i2b2_fill_in_tree(null, tPath, jobId) into rtnCd;
		IF rtnCd <> 1 THEN
			RETURN rtnCd;
		END IF;
	end if;

	select count(*) into pExists
	from i2b2metadata.i2b2
	where c_fullname = topNode;

	--	add top node for study

	if pExists = 0 then
		select i2b2_add_node(TrialId, topNode, study_name, jobId) into rtnCd;
	end if;

	--	Set data_type, category_path, and usubjid

	update wrk_clinical_data
	set data_type = 'T'
		-- All tag values prefixed with $$, so we should remove prefixes in category_path
		,category_path = regexp_replace(regexp_replace(replace(replace(category_cd,'_',' '),'+','\'), '\$\$\d*[A-Z]\{([^}]+)\}', '\1', 'g'), '\$\$\d*[A-Z]', '', 'g')
	  ,usubjid = REGEXP_REPLACE(TrialID || ':' || coalesce(site_id,'') || ':' || subject_id,
                   '(::){1,}', ':', 'g');
	 get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set columns in wrk_clinical_data',rowCt,stepCt,'Done') into rtnCd;

	--	Delete rows where data_value is null

	begin
	delete from wrk_clinical_data
	where coalesce(data_value, '') = '';
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Delete null data_values in wrk_clinical_data',rowCt,stepCt,'Done') into rtnCd;

	--Remove Invalid pipes in the data values.
	--RULE: If Pipe is last or first, delete it
	--If it is in the middle replace with a dash

	begin
	update wrk_clinical_data
	set data_value = replace(trim('|' from data_value), '|', '-')
	where data_value like '%|%';
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Remove pipes in data_value',rowCt,stepCt,'Done') into rtnCd;

	--Remove invalid Parens in the data
	--They have appeared as empty pairs or only single ones.

	begin
	update wrk_clinical_data
	set data_value = replace(data_value,'(', '')
	where data_value like '%()%'
	   or data_value like '%( )%'
	   or (data_value like '%(%' and data_value NOT like '%)%');
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Remove empty parentheses 1',rowCt,stepCt,'Done') into rtnCd;

	begin
	update wrk_clinical_data
	set data_value = replace(data_value,')', '')
	where data_value like '%()%'
	   or data_value like '%( )%'
	   or (data_value like '%)%' and data_value NOT like '%(%');
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Remove empty parentheses 2',rowCt,stepCt,'Done') into rtnCd;

	--Replace the Pipes with Commas in the data_label column
	begin
	update wrk_clinical_data
    set data_label = replace (data_label, '|', ',')
    where data_label like '%|%';
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Replace pipes with comma in data_label',rowCt,stepCt,'Done') into rtnCd;

	--	set visit_name to null when there's only a single visit_name for the category

  analyze wrk_clinical_data;
  if alwaysSetVisitName = 'N' then
   begin
    begin
    update wrk_clinical_data tpm
    set visit_name=null
    where (regexp_replace(tpm.category_cd,'\$\$(\d*[A-Z])(\{[^}]+\}|[^+]+)','\$\$\1','g')) in
        (select regexp_replace(x.category_cd,'\$\$(\d*[A-Z])(\{[^}]+\}|[^+]+)','\$\$\1','g')
         from wrk_clinical_data x
         group by regexp_replace(x.category_cd,'\$\$(\d*[A-Z])(\{[^}]+\}|[^+]+)','\$\$\1','g')
         having count(distinct upper(x.visit_name)) = 1);
    get diagnostics rowCt := ROW_COUNT;
    exception
    when others then
      errorNumber := SQLSTATE;
      errorMessage := SQLERRM;
      --Handle errors.
      select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
      --End Proc
      select cz_end_audit (jobID, 'FAIL') into rtnCd;
      return -16;
    end;
    stepCt := stepCt + 1;
    select cz_write_audit(jobId,databaseName,procedureName,'Set single visit_name to null',rowCt,stepCt,'Done') into rtnCd;
   end;
   else
    stepCt := stepCt + 1;
    select cz_write_audit(jobId,databaseName,procedureName,'Use single visit_name in path',0,stepCt,'Done') into rtnCd;
   end if;
	--	set data_label to null when it duplicates the last part of the category_path
	--	Remove data_label from last part of category_path when they are the same

	UPDATE wrk_clinical_data tmp
	SET category_cd = regexp_replace(regexp_replace(tmp.category_cd, '\$\$\d*[A-Z]\{([^}]+)\}', '\1', 'g'), '\$\$\d*[A-Z]', '', 'g')
	WHERE tmp.category_cd LIKE '%$$%';

	stepCt := stepCt + 1;
	get diagnostics rowCt := ROW_COUNT;
	perform cz_write_audit(jobId,databaseName,procedureName,'Remove tag markers',rowCt,stepCt,'Done');

	begin
	update wrk_clinical_data tpm
	--set data_label = null
	set category_path=substr(tpm.category_path,1,instr(tpm.category_path,'\',-2,1)-1)
	   ,category_cd=substr(tpm.category_cd,1,instr(tpm.category_cd,'+',-2,1)-1)
	where (tpm.category_cd, tpm.data_label) in
		  (select distinct t.category_cd
				 ,t.data_label
		   from wrk_clinical_data t
		   where upper(substr(t.category_path,instr(t.category_path,'\',-1,1)+1,length(t.category_path)-instr(t.category_path,'\',-1,1)))
			     = upper(t.data_label)
		     and t.data_label is not null)
	  and tpm.data_label is not null AND instr(tpm.category_path,'\',-2, 1) > 0 AND instr(tpm.category_cd,'+',-2, 1) > 0;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set data_label to null when found in category_path',rowCt,stepCt,'Done') into rtnCd;

	--	set visit_name to null if same as data_label



	--	set visit_name to null if only DATALABEL in category_cd

	-- TR: disabled!!!!
	/*
	begin
	update wrk_clinical_data t
	set visit_name=null
	where t.category_cd like '%DATALABEL%'
	  and t.category_cd not like '%VISITNAME%';
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set visit_name to null when only DATALABE in category_cd',rowCt,stepCt,'Done') into rtnCd; */

	--	change any % to Pct and & and + to ' and ' and _ to space in data_label only

	begin
		update wrk_clinical_data
		set data_label=replace(replace(replace(replace(replace(data_label,'%',' Pct'),'&',' and '),'+',' and '),'_',' '),'(plus)','+')
	   		,data_value=replace(replace(replace(replace(data_value,'%',' Pct'),'&',' and '),'+',' and '),'(plus)','+')
	   		,category_cd=replace(replace(category_cd,'%',' Pct'),'&',' and ')
	   		,category_path=replace(replace(replace(category_path,'%',' Pct'),'&',' and '),'(plus)','+');

	   exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;

	--Trim trailing and leadling spaces as well as remove any double spaces, remove space from before comma, remove trailing comma
	begin
		update wrk_clinical_data
		set data_label  = trim(trailing ',' from trim(replace(replace(data_label,'  ', ' '),' ,',','))),
			data_value  = trim(trailing ',' from trim(replace(replace(data_value,'  ', ' '),' ,',','))),
			--		sample_type = trim(trailing ',' from trim(replace(replace(sample_type,'  ', ' '),' ,',','))),
			visit_name  = trim(trailing ',' from trim(replace(replace(visit_name,'  ', ' '),' ,',',')));
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Remove leading, trailing, double spaces',rowCt,stepCt,'Done') into rtnCd;

	-- set visit_name and data_label to NULL if not found in category_path. Avoids duplicates for wt_trial_nodes
	-- we should clear visit_name and data_label before filling wt_num_data_types
	UPDATE wrk_clinical_data t
	SET visit_name = NULL
	WHERE (category_path LIKE '%\$' AND category_path NOT LIKE '%VISITNAME%')
				OR (start_date IS NOT NULL OR instance_num IS NOT NULL);

	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	perform cz_write_audit(jobId,databaseName,procedureName,'Set visit_name to null if VISITNAME not in category_path',rowCt,stepCt,'Done');

	update wrk_clinical_data t
	set data_label=null
	where category_path like '%\$' and category_path not like '%DATALABEL%';

	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	perform cz_write_audit(jobId,databaseName,procedureName,'Set data_label to null if DATALABEL not in category_path',rowCt,stepCt,'Done');


 begin
	update wrk_clinical_data t
	set visit_name=null
	where (t.category_cd, t.visit_name, t.data_label) in
	      (select distinct tpm.category_cd
				 ,tpm.visit_name
				 ,tpm.data_label
		  from wrk_clinical_data tpm
		  where tpm.visit_name = tpm.data_label);
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set visit_name to null when found in data_label',rowCt,stepCt,'Done') into rtnCd;

  --	set visit_name to null if same as data_value

	begin
  	update wrk_clinical_data t
		set visit_name=null
		where (t.category_cd, t.visit_name, t.data_value) in
					(select distinct tpm.category_cd
					 ,tpm.visit_name
					 ,tpm.data_value
				from wrk_clinical_data tpm
				where tpm.visit_name = tpm.data_value);
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set visit_name to null when found in data_value',rowCt,stepCt,'Done') into rtnCd;

	--1. DETERMINE THE DATA_TYPES OF THE FIELDS
	--	replaced cursor with update, used temp table to store category_cd/data_label because correlated subquery ran too long

	execute ('truncate table wt_num_data_types');

	begin
		insert into wt_num_data_types
		(category_cd
			,data_label
			,visit_name
		)
			select category_cd,
				data_label,
				visit_name
			from wrk_clinical_data
			where data_value is not null
			group by category_cd
				,data_label
				,visit_name
			having sum(is_numeric(data_value)) = 0;
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Insert numeric data into WZ wt_num_data_types',rowCt,stepCt,'Done') into rtnCd;

	begin
		update wrk_clinical_data t
		set data_type='N'
		where exists
		(select 1 from wt_num_data_types x
				where coalesce(t.category_cd,'@') = coalesce(x.category_cd,'@')
							and coalesce(t.data_label,'**NULL**') = coalesce(x.data_label,'**NULL**')
							and coalesce(t.visit_name,'**NULL**') = coalesce(x.visit_name,'**NULL**')
		);
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Updated data_type flag for numeric data_types',rowCt,stepCt,'Done') into rtnCd;

	update wrk_clinical_data
	set category_path =
	case
		-- Path with terminator, don't change, just remove terminator
		when category_path like '%\$'
		then substr(category_path, 1, length(category_path) - 2)
		-- Add missing fields to concept_path
		else
			case
				when category_path like '%\VISITNFST' then replace(category_path, '\VISITNFST', '')
				else category_path
			end ||
			case
				when category_path not like '%DATALABEL%' then '\DATALABEL'
				else ''
			end ||
			case
				when category_path like '%\VISITNFST' then '\VISITNAME'
				else ''
			end ||
			case
				when data_type = 'T' and category_path not like '%DATAVALUE%' then '\DATAVALUE'
				else ''
			end ||
			case
				when category_path not like '%\VISITNFST' and category_path not like '%VISITNAME%' then '\VISITNAME'
				else ''
			end
		end;

	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Add if missing DATALABEL, VISITNAME and DATAVALUE to category_path',rowCt,stepCt,'Done') into rtnCd;

	WITH duplicates AS (
		DELETE FROM wrk_clinical_data
		WHERE (subject_id, coalesce(visit_name, '**NULL**'), coalesce(data_label, '**NULL**'), category_cd, data_value, coalesce(start_date,'**NULL**'), coalesce(instance_num,'**NULL**')) in (
			SELECT subject_id, coalesce(visit_name, '**NULL**'), coalesce(data_label, '**NULL**'), category_cd, data_value, coalesce(start_date,'**NULL**'), coalesce(instance_num,'**NULL**')
			FROM wrk_clinical_data
			GROUP BY subject_id, visit_name, data_label, category_cd, data_value, start_date, instance_num
			HAVING count(*) > 1)
		RETURNING *
	)
	INSERT INTO wrk_clinical_data
	SELECT DISTINCT ON (subject_id, coalesce(visit_name, '**NULL**'), data_label, category_cd, data_value) *
	FROM duplicates;
	get diagnostics rowCt := ROW_COUNT;

	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Remove duplicates from wrk_clinical_data',rowCt,stepCt,'Done') into rtnCd;

	--	Check if any duplicate records of key columns (site_id, subject_id, visit_name, data_label, category_cd) for numeric data
	--	exist.  Raise error if yes

	execute ('truncate table wt_clinical_data_dups');

	BEGIN
		INSERT INTO wt_clinical_data_dups
		(site_id
			, subject_id
			, visit_name
			, data_label
			, category_cd)
			SELECT
				w.site_id,
				CASE WHEN
					w.instance_num IS NULL AND w.start_date IS NULL AND w.end_date IS NULL
					THEN
						w.subject_id
				ELSE
					w.subject_id || '|' || coalesce(w.instance_num, '') || '|' || coalesce(w.start_date, '') || '|' ||
					coalesce(w.end_date, '')
				END,
				w.visit_name,
				w.data_label,
				w.category_cd
			FROM tm_dataloader.wrk_clinical_data w
			WHERE exists
			(SELECT 1
			 FROM tm_dataloader.wt_num_data_types t
			 WHERE coalesce(w.category_cd, '@') = coalesce(t.category_cd, '@')
						 AND coalesce(w.data_label, '@') = coalesce(t.data_label, '@')
						 AND coalesce(w.visit_name, '@') = coalesce(t.visit_name, '@')
			)
			GROUP BY w.site_id, w.subject_id, w.visit_name, w.data_label, w.category_cd, w.instance_num, w.start_date,
				w.end_date
			HAVING count(*) > 1;
		GET DIAGNOSTICS rowCt := ROW_COUNT;
		EXCEPTION
		WHEN OTHERS
			THEN
				errorNumber := SQLSTATE;
				errorMessage := SQLERRM;
				--Handle errors.
				SELECT cz_error_handler(jobID, procedureName, errorNumber, errorMessage)
				INTO rtnCd;
				--End Proc
				SELECT cz_end_audit(jobID, 'FAIL')
				INTO rtnCd;
				RETURN -16;
	END;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Check for duplicate key columns',rowCt,stepCt,'Done') into rtnCd;

	if rowCt > 0 then
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Duplicate values found in key columns',0,stepCt,'Done') into rtnCd;
		select cz_error_handler (jobID, procedureName, '-1', 'Application raised error') into rtnCd;
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end if;

	--	check for multiple visit_names for subject_id, category_cd, data_label, data_value

     select max(case when x.null_ct > 0 and x.non_null_ct > 0
					 then 1 else 0 end) into pCount
      from (select category_cd, data_label, data_value
				  ,sum(case when visit_name is null then 1 else 0 end) as null_ct
				  ,sum(case when visit_name is null then 0 else 1 end) as non_null_ct
			from lt_src_clinical_data
			where (category_cd like '%VISITNAME%' or
				   category_cd not like '%DATALABEL%')
			group by category_cd, data_label, data_value) x;
	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Check for missing visit_names for subject_id/category/label/value ',rowCt,stepCt,'Done') into rtnCd;

	if pCount > 0 then
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Not for all subject_id/category/label/value visit names specified. Visit names should be all empty or specified for all records.',0,stepCt,'Done') into rtnCd;
		select cz_error_handler (jobID, procedureName, '-1', 'Application raised error') into rtnCd;
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end if;

	-- Build all needed leaf nodes in one pass for both numeric and text nodes
	execute ('truncate table wt_trial_nodes');

	begin
	insert into wt_trial_nodes
	(leaf_node
	,category_cd
	,visit_name
	,data_label
	,data_value
	,data_type
	,valuetype_cd
	,baseline_value
	)
  select DISTINCT
    Case
    	--	Text data_type (default node)
    	When a.data_type = 'T'
      then regexp_replace(topNode || replace(replace(replace(coalesce(a.category_path, ''),'DATALABEL',coalesce(a.data_label, '')),'VISITNAME',coalesce(a.visit_name, '')), 'DATAVALUE',coalesce(a.data_value, ''))  || '\','(\\){2,}', '\', 'g')
    	--	else is numeric data_type and default_node
      else regexp_replace(topNode || replace(replace(coalesce(a.category_path, ''),'DATALABEL',coalesce(a.data_label, '')),'VISITNAME',coalesce(a.visit_name, '')) || '\','(\\){2,}', '\', 'g')
    end as leaf_node
    ,a.category_cd
    ,a.visit_name
    ,a.data_label
    ,case when a.data_type = 'T' then a.data_value else null end as data_value
    ,a.data_type
		,a.valuetype_cd
		,baseline_value
	from  wrk_clinical_data a;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Create leaf nodes for trial',rowCt,stepCt,'Done') into rtnCd;

	--	set node_name
	begin
		update wt_trial_nodes
		set
			leaf_node = replace_last_path_component(leaf_node, timestamp_to_timepoint(get_last_path_component(leaf_node), baseline_value)),
			valuetype_cd = 'TIMEPOINT'
		where baseline_value is not null;
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Updated last path component for timestamps',rowCt,stepCt,'Done') into rtnCd;

	begin
	update wt_trial_nodes
	set node_name=parse_nth_value(leaf_node,length(leaf_node)-length(replace(leaf_node,'\','')),'\');
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Updated node name for leaf nodes',rowCt,stepCt,'Done') into rtnCd;

	--	insert subjects into patient_dimension if needed

	execute ('truncate table wt_subject_info');

	begin
	insert into wt_subject_info
	(usubjid,
     age_in_years_num,
     sex_cd,
     race_cd
    )
	select a.usubjid,
	      coalesce(max(case when upper(a.data_label) = 'AGE'
					   then case when is_numeric(a.data_value) = 1 then 0 else floor(a.data_value::numeric) end
		               when upper(a.data_label) like '%(AGE)'
					   then case when is_numeric(a.data_value) = 1 then 0 else floor(a.data_value::numeric) end
					   else null end),0) as age,
		  coalesce(max(case when upper(a.data_label) = 'SEX' then a.data_value
		           when upper(a.data_label) like '%(SEX)' then a.data_value
				   when upper(a.data_label) = 'GENDER' then a.data_value
				   else null end),'Unknown') as sex,
		  max(case when upper(a.data_label) = 'RACE' then a.data_value
		           when upper(a.data_label) like '%(RACE)' then a.data_value
				   else null end) as race
	from wrk_clinical_data a
	group by a.usubjid;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Insert subject information into temp table',rowCt,stepCt,'Done') into rtnCd;

  updated_patient_nums := array(
      select pat.patient_num
      from wt_subject_info si, patient_dimension pat
      where si.usubjid = pat.sourcesystem_cd
  );

	--	Delete dropped subjects from patient_dimension if they do not exist in de_subject_sample_mapping
	if (merge_mode = 'REPLACE') then
		begin
			DELETE FROM i2b2demodata.visit_dimension
			WHERE patient_num IN (
				SELECT patient_num
				FROM i2b2demodata.patient_dimension
				WHERE sourcesystem_cd LIKE TrialId || ':%'
							 );
			get diagnostics rowCt := ROW_COUNT;
			exception
			when others then
				errorNumber := SQLSTATE;
				errorMessage := SQLERRM;
				--Handle errors.
				select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
				--End Proc
				select cz_end_audit (jobID, 'FAIL') into rtnCd;
				return -16;
		end;
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Delete dropped subjects from visit_dimension',rowCt,stepCt,'Done') into rtnCd;
		BEGIN
			DELETE FROM i2b2demodata.patient_dimension
			WHERE sourcesystem_cd IN
						(SELECT DISTINCT pd.sourcesystem_cd
						 FROM i2b2demodata.patient_dimension pd
						 WHERE pd.sourcesystem_cd LIKE TrialId || ':%'
						 EXCEPT
						 SELECT DISTINCT cd.usubjid
						 FROM wrk_clinical_data cd)
						AND patient_num NOT IN
								(SELECT DISTINCT sm.patient_id
								 FROM deapp.de_subject_sample_mapping sm);
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
		end;
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Delete dropped subjects from patient_dimension',rowCt,stepCt,'Done') into rtnCd;
	end if;

	--	update patients with changed information
	begin
	with nsi as (select t.usubjid, t.sex_cd, t.age_in_years_num, t.race_cd from wt_subject_info t)
	update i2b2demodata.patient_dimension
	set sex_cd=nsi.sex_cd
	   ,age_in_years_num=nsi.age_in_years_num
	   ,race_cd=nsi.race_cd
	   from nsi
	where sourcesystem_cd = nsi.usubjid;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Update subjects with changed demographics in patient_dimension',rowCt,stepCt,'Done') into rtnCd;

	--	insert new subjects into patient_dimension

	begin
	insert into i2b2demodata.patient_dimension
    (patient_num,
     sex_cd,
     age_in_years_num,
     race_cd,
     update_date,
     download_date,
     import_date,
     sourcesystem_cd
    )
    select nextval('i2b2demodata.seq_patient_num'),
		   t.sex_cd,
		   t.age_in_years_num,
		   t.race_cd,
		   current_timestamp,
		   current_timestamp,
		   current_timestamp,
		   t.usubjid
    from wt_subject_info t
	where t.usubjid in
		 (select distinct cd.usubjid from wt_subject_info cd
		  except
		  select distinct pd.sourcesystem_cd from i2b2demodata.patient_dimension pd
		  where pd.sourcesystem_cd like TrialId || ':%');
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Insert new subjects into patient_dimension',rowCt,stepCt,'Done') into rtnCd;


	create temporary table concept_specific_trials
	(
		trial_visit_num numeric(38,0),
		c_fullname character varying(700)
	);

	FOR trialVisitLabel IN trialVisitLabels LOOP
		SELECT insert_additional_data(TrialID, trialVisitLabel.trial_visit_label, secureStudy, jobID)
		INTO trialVisitNum;
	END LOOP;

	select study_num into studyNum
	from i2b2demodata.study
	where study_id = TrialId;

	BEGIN
		INSERT INTO i2b2demodata.visit_dimension
			(
				encounter_num,
			 	patient_num,
			 	start_date,
				sourcesystem_cd
			)
			SELECT
				nextval('tm_dataloader.visit_dimension_seq'),
				pd.patient_num,
				current_timestamp,
				TrialID
			FROM i2b2demodata.patient_dimension pd
			WHERE pd.sourcesystem_cd LIKE TrialId || ':%'
						AND pd.patient_num NOT IN (SELECT patient_num
																			 FROM i2b2demodata.visit_dimension vd);
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
	END;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Insert new visit into visit_dimension',rowCt,stepCt,'Done') into rtnCd;


	--	delete leaf nodes that will not be reused, if any
	if (merge_mode = 'REPLACE') then
		for r_delUnusedLeaf in delUnusedLeaf loop

    --	deletes unused leaf nodes for a trial one at a time

			select i2b2_delete_1_node(r_delUnusedLeaf.c_fullname) into rtnCd;
			stepCt := stepCt + 1;
			select cz_write_audit(jobId,databaseName,procedureName,'Deleted unused leaf node: ' || r_delUnusedLeaf.c_fullname,1,stepCt,'Done') into rtnCd;

		end loop;
	end if;

	begin
	insert into i2b2demodata.concept_dimension
    (concept_cd
	,concept_path
	,name_char
	,update_date
	,download_date
	,import_date
	,sourcesystem_cd
	,table_name
	)
    select nextval('i2b2demodata.concept_id')
	     ,x.leaf_node
		 ,x.node_name
		 ,current_timestamp
		 ,current_timestamp
		 ,current_timestamp
		 ,TrialId
		 ,'CONCEPT_DIMENSION'
	from (select distinct c.leaf_node
				,c.node_name::text as node_name
		  from wt_trial_nodes c
		  where not exists
			(select 1 from i2b2demodata.concept_dimension x
			where c.leaf_node = x.concept_path)
		 ) x;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Inserted new leaf nodes into I2B2DEMODATA concept_dimension',rowCt,stepCt,'Done') into rtnCd;

	--	update i2b2 with name, data_type and xml for leaf nodes
	begin
	update i2b2metadata.i2b2
	set c_name=ncd.node_name
	   ,c_columndatatype='T'
	   ,c_metadataxml=i2b2_build_metadata_xml(ncd.node_name, ncd.data_type, ncd.valuetype_cd, TrialID, ncd.leaf_node)
	from wt_trial_nodes ncd
	where c_fullname = ncd.leaf_node;
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Updated name and data type in i2b2 if changed',rowCt,stepCt,'Done') into rtnCd;

	begin
	insert into i2b2metadata.i2b2
    (c_hlevel
	,c_fullname
	,c_name
	,c_visualattributes
	,c_synonym_cd
	,c_facttablecolumn
	,c_tablename
	,c_columnname
	,c_dimcode
	,c_tooltip
	,update_date
	,download_date
	,import_date
	,sourcesystem_cd
	,c_basecode
	,c_operator
	,c_columndatatype
	,c_comment
	,m_applied_path
	,c_metadataxml
	)
    select distinct (length(c.concept_path) - coalesce(length(replace(c.concept_path, '\','')),0)) / length('\') - 2 + root_level
		  ,c.concept_path
		  ,c.name_char
		  ,'LA'
		  ,'N'
		  ,'CONCEPT_CD'
		  ,'CONCEPT_DIMENSION'
		  ,'CONCEPT_PATH'
		  ,c.concept_path
		  ,c.concept_path
		  ,current_timestamp
		  ,current_timestamp
		  ,current_timestamp
		  ,c.sourcesystem_cd
		  ,c.concept_cd
		  ,'LIKE'	--'T'
		  , 'T' --t.data_type
		  ,'trial:' || TrialID
		  ,'@'
		  ,i2b2_build_metadata_xml(c.name_char, t.data_type, t.valuetype_cd, c.sourcesystem_cd, c.concept_path)
    from i2b2demodata.concept_dimension c
		,wt_trial_nodes t
    where c.concept_path = t.leaf_node
	  and not exists
		 (select 1 from i2b2metadata.i2b2 x
		  where c.concept_path = x.c_fullname);
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Inserted leaf nodes into I2B2METADATA i2b2',rowCt,stepCt,'Done') into rtnCd;

	--New place form fill_in_tree
	select i2b2_fill_in_tree(TrialId, topNode, jobID) into rtnCd;
	IF rtnCd <> 1 THEN
		RETURN rtnCd;
	END IF;

	--	delete from observation_fact all concept_cds for trial that are clinical data, exclude concept_cds from biomarker data
	if (merge_mode = 'REPLACE') then
		begin
		delete from i2b2demodata.observation_fact f
		where
			trial_visit_num in (
				select trial_visit_num from trial_visit_dimension where study_num = studyNum
			)
			and
					f.concept_cd not in
			 (select distinct concept_code as concept_cd from deapp.de_subject_sample_mapping
				where trial_name = TrialId
					and concept_code is not null
				union
				select distinct platform_cd as concept_cd from deapp.de_subject_sample_mapping
				where trial_name = TrialId
					and platform_cd is not null
				union
				select distinct sample_type_cd as concept_cd from deapp.de_subject_sample_mapping
				where trial_name = TrialId
					and sample_type_cd is not null
				union
				select distinct tissue_type_cd as concept_cd from deapp.de_subject_sample_mapping
				where trial_name = TrialId
					and tissue_type_cd is not null
				union
				select distinct timepoint_cd as concept_cd from deapp.de_subject_sample_mapping
				where trial_name = TrialId
					and timepoint_cd is not null
				union
				select distinct concept_cd as concept_cd from deapp.de_subject_snp_dataset
				where trial_name = TrialId
					and concept_cd is not null);
		get diagnostics rowCt := ROW_COUNT;
		exception
		when others then
			errorNumber := SQLSTATE;
			errorMessage := SQLERRM;
			--Handle errors.
			select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
			--End Proc
			select cz_end_audit (jobID, 'FAIL') into rtnCd;
			return -16;
		end;
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Delete clinical data for study from observation_fact',rowCt,stepCt,'Done') into rtnCd;
	end if;

  -- delete old fact records for updated data
	if (merge_mode = 'UPDATE') then
    begin
    delete from observation_fact f
		  where
				trial_visit_num in (
					select trial_visit_num from trial_visit_dimension where study_num in (
						select study_num from i2b2demodata.study where study_id = TrialID
					)
				)
				and
				f.patient_num = any(updated_patient_nums)
						and f.concept_cd not in
								(select distinct concept_code as concept_cd from deapp.de_subject_sample_mapping
								where trial_name = TrialId
											and concept_code is not null
								 union
								 select distinct platform_cd as concept_cd from deapp.de_subject_sample_mapping
								 where trial_name = TrialId
											 and platform_cd is not null
								 union
								 select distinct sample_type_cd as concept_cd from deapp.de_subject_sample_mapping
								 where trial_name = TrialId
											 and sample_type_cd is not null
								 union
								 select distinct tissue_type_cd as concept_cd from deapp.de_subject_sample_mapping
								 where trial_name = TrialId
											 and tissue_type_cd is not null
								 union
								 select distinct timepoint_cd as concept_cd from deapp.de_subject_sample_mapping
								 where trial_name = TrialId
											 and timepoint_cd is not null
								 union
								 select distinct concept_cd as concept_cd from deapp.de_subject_snp_dataset
								 where trial_name = TrialId
											 and concept_cd is not null);
    exception
    when others then
    	errorNumber := SQLSTATE;
      errorMessage := SQLERRM;
      --Handle errors.
      select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
      --End Proc
      select cz_end_audit (jobID, 'FAIL') into rtnCd;
      return -16;
    end;
    stepCt := stepCt + 1;
    select cz_write_audit(jobId,databaseName,procedureName,'Delete old fact records for updated data',rowCt,stepCt,'Done') into rtnCd;

	end if;

  if (merge_mode = 'UPDATE_VARIABLES') then
    begin
    for cur_row in (select wcd.category_path, wcd.data_value, wcd.data_label, wcd.visit_name,pat.patient_num, wcd.data_type
                      from wrk_clinical_data wcd, patient_dimension pat
                     where pat.sourcesystem_cd = wcd.usubjid) loop
			if (cur_row.data_type = 'T') then
      	pathRegexp := regexp_replace(topNode || replace(replace(coalesce(cur_row.category_path, ''), 'DATALABEL',coalesce(cur_row.data_label, '')), 'VISITNAME',coalesce(cur_row.visit_name, ''))  || '\','(\\){2,}', '\', 'g');
				pathRegexp := regexp_replace(pathRegexp, '([\[\]\(\)\\])', '\\\1', 'g');
				pathRegexp :=  '^' || replace(pathRegexp,'DATAVALUE','[^\\]+') || '$';
        select cz_write_audit(jobId,databaseName,procedureName,'RegExp for search : ' || pathRegexp,rowCt,stepCt,'Done') into rtnCd;
        select count(cd.concept_path)
        into pathCount
        from concept_dimension cd, observation_fact fact
        where cd.concept_path ~ pathRegexp
              and fact.concept_cd = cd.concept_cd
              and fact.patient_num = cur_row.patient_num;

        if (pathCount = 1) then
          select cd.concept_path
          into updatedPath
          from concept_dimension cd, observation_fact fact
          where cd.concept_path ~ pathRegexp
                and fact.concept_cd = cd.concept_cd
                and fact.patient_num = cur_row.patient_num;

          delete from observation_fact f
          where
						trial_visit_num in (
						select trial_visit_num from trial_visit_dimension where study_num in (
							select study_num from i2b2demodata.study where study_id = TrialID
						)
					)
								and
						f.patient_num = cur_row.patient_num
                and f.concept_cd in (select cd.concept_cd
                                     from concept_dimension cd
                                     where cd.concept_path like updatedPath || '%' escape '`')
                and f.concept_cd not in
                    (select distinct concept_code as concept_cd from deapp.de_subject_sample_mapping
                    where trial_name = TrialId
                          and concept_code is not null
                     union
                     select distinct platform_cd as concept_cd from deapp.de_subject_sample_mapping
                     where trial_name = TrialId
                           and platform_cd is not null
                     union
                     select distinct sample_type_cd as concept_cd from deapp.de_subject_sample_mapping
                     where trial_name = TrialId
                           and sample_type_cd is not null
                     union
                     select distinct tissue_type_cd as concept_cd from deapp.de_subject_sample_mapping
                     where trial_name = TrialId
                           and tissue_type_cd is not null
                     union
                     select distinct timepoint_cd as concept_cd from deapp.de_subject_sample_mapping
                     where trial_name = TrialId
                           and timepoint_cd is not null
                     union
                     select distinct concept_cd as concept_cd from deapp.de_subject_snp_dataset
                     where trial_name = TrialId
                           and concept_cd is not null);

          stepCt := stepCt + 1;
          select cz_write_audit(jobId,databaseName,procedureName,'Delete old fact records for updated data. Path: ' || updatedPath || '. Patient:' || cur_row.patient_num,rowCt,stepCt,'Done') into rtnCd;
        else
					if (pathCount > 1) then
						stepCt := stepCt + 1;
						select cz_write_audit(jobId,databaseName,procedureName,'Find several categorical value on the same path',0,stepCt,'Done') into rtnCd;
						select cz_error_handler (jobID, procedureName, '-1', 'Application raised error') into rtnCd;
						select cz_end_audit (jobID, 'FAIL') into rtnCd;
						return -16;
					end if;
				end if;
      else
				updatedPath := regexp_replace(topNode || replace(replace(coalesce(cur_row.category_path, ''),'DATALABEL',coalesce(cur_row.data_label, '')),'VISITNAME',coalesce(cur_row.visit_name, '')) || '\','(\\){2,}', '\', 'g');
        delete from observation_fact f
        where
					trial_visit_num in (
						select trial_visit_num from trial_visit_dimension where study_num in (
							select study_num from i2b2demodata.study where study_id = TrialID
						)
					)
					and
					f.patient_num = cur_row.patient_num
              and f.concept_cd in (select cd.concept_cd
                                   from concept_dimension cd
                                   where cd.concept_path = updatedPath)
              and f.concept_cd not in
                  (select distinct concept_code as concept_cd from de_subject_sample_mapping
                  where trial_name = TrialId
                        and concept_code is not null
                   union
                   select distinct platform_cd as concept_cd from de_subject_sample_mapping
                   where trial_name = TrialId
                         and platform_cd is not null
                   union
                   select distinct sample_type_cd as concept_cd from de_subject_sample_mapping
                   where trial_name = TrialId
                         and sample_type_cd is not null
                   union
                   select distinct tissue_type_cd as concept_cd from de_subject_sample_mapping
                   where trial_name = TrialId
                         and tissue_type_cd is not null
                   union
                   select distinct timepoint_cd as concept_cd from de_subject_sample_mapping
                   where trial_name = TrialId
                         and timepoint_cd is not null
                   union
                   select distinct concept_cd as concept_cd from de_subject_snp_dataset
                   where trial_name = TrialId
                         and concept_cd is not null);

        stepCt := stepCt + 1;
        select cz_write_audit(jobId,databaseName,procedureName,'Delete old fact records for updated data. Path: ' || updatedPath || '. Patient: ' || cur_row.patient_num,rowCt,stepCt,'Done') into rtnCd;
      end if;
    end loop;
    exception
    when others then
        errorNumber := SQLSTATE;
        errorMessage := SQLERRM;
        --Handle errors.
        select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
        --End Proc
        select cz_end_audit (jobID, 'FAIL') into rtnCd;
        return -16;
    end;
  end if;

	if (merge_mode = 'APPEND') then
    begin
		delete from observation_fact f
		 where
			 trial_visit_num in (
				 select trial_visit_num from trial_visit_dimension where study_num in (
					 select study_num from i2b2demodata.study where study_id = TrialID
				 )
			 )
			 and
		f.valtype_cd = 'N'
		   and f.patient_num = any(updated_patient_nums)
		   and f.concept_cd in (select cd.concept_cd
								  from observation_fact fact, concept_dimension cd, wt_trial_nodes node
								 where fact.patient_num = any(updated_patient_nums)
								   and fact.concept_cd = cd.concept_cd
								   and cd.concept_path = node.leaf_node
								   and node.data_type = 'N');
    exception
    when others then
    	errorNumber := SQLSTATE;
      errorMessage := SQLERRM;
      --Handle errors.
      select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
      --End Proc
      select cz_end_audit (jobID, 'FAIL') into rtnCd;
      return -16;
    end;
    stepCt := stepCt + 1;
    select cz_write_audit(jobId,databaseName,procedureName,'Delete old numerical fact records for append data',rowCt,stepCt,'Done') into rtnCd;
  end if;

	analyze wrk_clinical_data;
	analyze wt_trial_nodes;
	begin

	set enable_mergejoin=f;
	create temporary table tmp_observation_facts without oids as
	select distinct
			vd.encounter_num as encounter_num,
		  c.patient_num,
		  i.c_basecode as concept_cd,
			case when a.start_date is null then 'infinity'
				else to_timestamp(a.start_date,'YYYY-MM-DD HH24:MI:SS.MS') end
				as start_date,
			'@' as modifier_cd, 			--a.study_id as modifier_cd,
		  a.data_type as valtype_cd,
		  case when a.data_type = 'T' then a.data_value
				else 'E'  --Stands for Equals for numeric types
				end as tval_char,
		  case when a.data_type = 'N' then a.data_value::numeric
				else null --Null for text types
				end as nval_num,
			a.units_cd,
		  a.study_id as sourcesystem_cd,
		  current_timestamp as import_date,
		  '@' as valueflag_cd,
		  '@' as provider_id,
		  '@' as location_cd,
			to_number(coalesce(a.instance_num, '1'),'9999') as instance_num,
			tvd.trial_visit_num,
			case when a.end_date is null then NULL
				else to_timestamp(a.end_date,'YYYY-MM-DD HH24:MI:SS.MS') end
				as end_date
	from wrk_clinical_data a
		,i2b2demodata.patient_dimension c
		,wt_trial_nodes t
		,i2b2metadata.i2b2 i
		,i2b2demodata.visit_dimension vd
		,i2b2demodata.trial_visit_dimension tvd
	where a.usubjid = c.sourcesystem_cd
	  and coalesce(a.category_cd,'@') = coalesce(t.category_cd,'@')
	  and coalesce(a.data_label,'**NULL**') = coalesce(t.data_label,'**NULL**')
	  and coalesce(a.visit_name,'**NULL**') = coalesce(t.visit_name,'**NULL**')
	  and coalesce(a.baseline_value,'**NULL**') = coalesce(t.baseline_value,'**NULL**')
	  and case when a.data_type = 'T' then a.data_value else '**NULL**' end = coalesce(t.data_value,'**NULL**')
	  and t.leaf_node = i.c_fullname
		and c.patient_num = vd.patient_num
		and tvd.study_num = studyNum
		and tvd.rel_time_label = a.trial_visit_label
--	  and not exists		-- don't insert if lower level node exists
--		 (select 1 from wt_trial_nodes x
--		  where x.leaf_node like t.leaf_node || '%_' escape '`')
--	  and a.data_value is not null;
	  and not exists		-- don't insert if lower level node exists
		(
			select 1 from wt_trial_nodes x
			where regexp_replace(x.leaf_node, '[^\\]+\\$', '') = t.leaf_node
		)
	  and a.data_value is not null
		and not (a.data_type = 'N' and a.data_value = '');
	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	set enable_mergejoin to default;
	select cz_write_audit(jobId,databaseName,procedureName,'Collect observation facts',rowCt,stepCt,'Done') into rtnCd;

	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		set enable_mergejoin to default;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;

	recreateIndexes := TRUE;
	if rowCt < 200 then
		recreateIndexes := FALSE;
	end if;

	if recreateIndexes = TRUE then
		SELECT DROP_ALL_INDEXES('i2b2demodata', 'observation_fact') INTO recreateIndexesSql;
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Drop observation facts indexes',0,stepCt,'Done') into rtnCd;
	end if;

	--Insert into observation_fact
	begin
	insert into i2b2demodata.observation_fact
	(encounter_num,
     patient_num,
     concept_cd,
     start_date,
     modifier_cd,
     valtype_cd,
     tval_char,
     nval_num,
	   units_cd,
     sourcesystem_cd,
     import_date,
     valueflag_cd,
     provider_id,
     location_cd,
     instance_num,
	 	 trial_visit_num,
	 	 end_date
	)
	select * from tmp_observation_facts;

	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Insert trial into I2B2DEMODATA observation_fact',rowCt,stepCt,'Done') into rtnCd;

	UPDATE I2B2DEMODATA.OBSERVATION_FACT
	SET TRIAL_VISIT_NUM = cst.trial_visit_num
		FROM concept_specific_trials cst
	WHERE concept_cd IN (SELECT cd.concept_cd
											 FROM I2B2DEMODATA.CONCEPT_DIMENSION cd
											 WHERE cd.CONCEPT_PATH = cst.c_fullname
														 AND sourcesystem_cd = TrialID)
				AND sourcesystem_cd = TrialID;
	get diagnostics rowCt := ROW_COUNT;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'UPDATE trial_visit_num in observation_fact',rowCt,stepCt,'Done') into rtnCd;


--July 2013. Performance fix by TR. Prepare precompute tree
	SELECT I2B2_CREATE_FULL_TREE(topNode, jobId) INTO rtnCd;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Create i2b2 full tree', 0, stepCt,'Done') into rtnCd;

	if recreateIndexes = TRUE then
		execute(recreateIndexesSql);
		stepCt := stepCt + 1;
		select cz_write_audit(jobId,databaseName,procedureName,'Create observation facts index', 0, stepCt,'Done') into rtnCd;
	end if;


  DELETE FROM i2b2_load_path_with_count;

  insert into i2b2_load_path_with_count
  select p.c_fullname, count(*)
	from i2b2metadata.i2b2 p
		--,i2b2metadata.i2b2 c
		,I2B2_LOAD_TREE_FULL tree
	where p.c_fullname like topNode || '%' escape '`'
		--and c.c_fullname like p.c_fullname || '%'
		and p.RECORD_ID = tree.IDROOT
		--and c.rowid = tree.IDCHILD
		group by P.C_FULLNAME;

	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Create i2b2 full tree counts', 0, stepCt,'Done') into rtnCd;

	--	update c_visualattributes for all nodes in study, done to pick up node that changed c_columndatatype
	begin
	/*with upd as (select p.c_fullname, count(*) as nbr_children
				 from i2b2metadata.i2b2 p
					 ,i2b2metadata.i2b2 c
				 where p.c_fullname like topNode || '%' escape '`'
				   and c.c_fullname like p.c_fullname || '%' escape '`'
				 group by p.c_fullname)*/
	update i2b2metadata.i2b2 b
	set c_visualattributes=case when u.nbr_children = 1
								then 'L' || substr(b.c_visualattributes,2,2)
								else 'F' || substr(b.c_visualattributes,2,1) ||
                     case when u.c_fullname = topNode then case when highlight_study = 'Y' then 'J' else
                       'S' end else substr(b.c_visualattributes,3,1) end
								end
		,c_columndatatype=case when u.nbr_children > 1 then 'T' else b.c_columndatatype end
	from i2b2_load_path_with_count u
	where b.c_fullname = u.c_fullname
	  and b.c_fullname in
		 (select x.c_fullname from i2b2metadata.i2b2 x
		  where x.c_fullname like topNode || '%' escape '`');
  	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set c_visualattributes in i2b2',rowCt,stepCt,'Done') into rtnCd;

	-- final procs
    --moved earlier
	--select i2b2_fill_in_tree(TrialId, topNode, jobID) into rtnCd;

	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Finish fill in tree',0, stepCt,'Done') into rtnCd;

	--	set sourcesystem_cd, c_comment to null if any added upper-level nodes

	begin
	update i2b2metadata.i2b2 b
	set sourcesystem_cd=null,c_comment=null
	where b.sourcesystem_cd = TrialId
	  and length(b.c_fullname) < length(topNode);
	get diagnostics rowCt := ROW_COUNT;
	exception
	when others then
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
	end;
	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'Set sourcesystem_cd to null for added upper-level nodes',rowCt,stepCt,'Done') into rtnCd;

	select i2b2_create_concept_counts(topNode, jobID, 'N') into rtnCd;

	--	delete each node that is hidden after create concept counts

	 FOR r_delNodes in delNodes Loop

    --	deletes hidden nodes for a trial one at a time

		select i2b2_delete_1_node(r_delNodes.c_fullname) into rtnCd;
		stepCt := stepCt + 1;
		tText := 'Deleted node: ' || r_delNodes.c_fullname;
		select cz_write_audit(jobId,databaseName,procedureName,tText,rowCt,stepCt,'Done') into rtnCd;

	END LOOP;

	select i2b2_create_security_for_trial(TrialId, secureStudy, jobID) into rtnCd;
	select i2b2_load_security_data(TrialId, jobID) into rtnCd;

	stepCt := stepCt + 1;
	select cz_write_audit(jobId,databaseName,procedureName,'End i2b2_load_clinical_data',0,stepCt,'Done') into rtnCd;

	---Cleanup OVERALL JOB if this proc is being run standalone
	perform cz_end_audit (jobID, 'SUCCESS') where coalesce(currentJobId, -1) <> jobId;

	return 1;
/*
	EXCEPTION
	WHEN OTHERS THEN
		errorNumber := SQLSTATE;
		errorMessage := SQLERRM;
		--Handle errors.
		select cz_error_handler (jobID, procedureName, errorNumber, errorMessage) into rtnCd;
		--End Proc
		select cz_end_audit (jobID, 'FAIL') into rtnCd;
		return -16;
*/
END;

$BODY$
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  SET search_path FROM CURRENT
  COST 100;

