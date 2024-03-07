/* Project: Infant Cascade      				*/
/* Author:  Ben Buzzee / Rachel Epstein 		*/ 
/* Created: 12/16/2022 							*/
/* Updated: 10/5/2023 by SM            			*/
/*==============================================*/

/*	Project Goal:
	Characterize the HCV care cascade of infants born to mothers seropositive for HCV 
	
	DATASETS: 
	PHDHEPC.HCV 	   		- ID, EVENT_DATE_HCV, DISEASE_STATUS_HCV
	PHDBIRTH.BIRTH_MOM 		- ID, BIRTH_LINK_ID, YEAR_BIRTH, MONTH_BIRTH, INFANT_DOB
	PHDBIRTH.BIRTH_INFANT	- ID. BIRTH_LINK_ID, YEAR_BIRTH, MONTH_BIRTH, DOB

    Part 1: Collect Cohort of Infants
    Part 2: Perform HCV Care Cascade

	Cleaning notes: Multiple INFANT_IDS matched to more than one BIRTH_LINK_ID and
					multiple BIRTH_LINK_IDs matched to more than one mom. I removed observations
					associated with these. One infant should match to exactly one mom and one birth_link_id.

	Detailed documentation of all datasets and variables:
	https://www.mass.gov/info-details/public-health-data-warehouse-phd-technical-documentation

	Useful code for checking ID counts at each step:
	Run PROC CONTENTS to determine number of rows and all variable names.
	Then create a table that is just a count of the total number of unique variable values (often IDs),
	and use proc freq to display it. Often we'll want the number of rows to match the number of IDs.

			/* PROC CONTENTS data=DATASET_NAME;
			   run; */

			/* PROC SQL; */
			/* create table counts */
			/* as select count(distinct VARIABLE_NAME) as n_var */
			/* from DATASET_NAME */
			/* GROUP BY VARIABLE_NAME2; */
			/* quit; */

			/* proc freq data = counts; */
			/* table n_var; */
			/* run; */


/* CLEAR WORKING DIRECTORY/TEMP FILES  */
proc datasets library=WORK kill; run; quit;

*Suppression code;
ods path(prepend) DPH.template(READ) SASUSER.TEMPLAT (READ);
proc format;                                                                                               
   value supp010_ 1-10=' * ';                                                                           
run ;

proc template;
%include "/sas/data/DPH/OPH/PHD/template.sas";
run;

/*============================ */
/*     Global Variables        */
/*============================ */
		
/* ======= HCV TESTING CPT CODES ========  */
%LET AB_CPT = ('G0472', '86803',
			   '86804', '80074',
			   'G0472');
			   
%LET RNA_CPT = ('87520', '87521',
			    '87522');
			    
%LET GENO_CPT = ('87902', '3266F');

/* === HCV TESTING DIAGNOSIS CODES ====== */
%LET HCV_ICD = ('7051', '7054', '707',
				'7041', '7044', '7071',
				'B1710','B182', 'B1920',
				'B1711','B1921');
				
/* HCV Direct Action Antiviral Codes */
%LET DAA_CODES = ('00003021301',
				  '00003021501',
				  '61958220101',
				  '61958180101',
				  '61958180301',
				  '61958180401',
				  '61958180501',
				  '61958150101',
				  '61958150401',
				  '61958150501',
				  '72626260101',
				  '00074262501',
				  '00074262528',
				  '00074262556',
				  '00074262580',
				  '00074262584',
				  '00074260028',
				  '72626270101',
				  '00074308228',
				  '00074006301',
				  '00074006328',
				  '00074309301',
				  '00074309328',
				  '61958240101',
				  '61958220101',
				  '61958220301',
				  '61958220401',
				  '61958220501',
				  '00006307402',
				  '51167010001',
				  '51167010003',
				  '59676022507',
				  '59676022528',
				  '00085031402');

/*============================ */
/*  Cohort Identification      */
/*============================ */

/*  Collect All HCV Seropositive Patients */
/*  Output: HCV dataset, one row per mom with HCV
	Notes:  EVENT_DATE_HCV is the date of diagnosis/first symptom
		    DISEASE_STATUS_HCV = 1 for confirmed, 2 if probable 
		    MIN function is used to remove possible duplicates within one ID */

PROC SQL;
CREATE TABLE HCV
AS SELECT ID as MOM_ID,
		  MIN(EVENT_DATE_HCV) as MOM_EVENT_DATE_HCV,
		  MIN(DISEASE_STATUS_HCV) as MOM_DISEASE_STATUS_HCV
FROM PHDHEPC.HCV
GROUP BY MOM_ID;
run;


/*  Collect All Moms */
/*  Output: MOMS dataset, one row per BIRTH_LINK_ID - so multiple rows per MOM_ID
	Variables: MOM_ID - BIRTH_LINK_ID - DOB_MOM_TBL - BIRTH_INDICATOR */
	
PROC SQL;
CREATE TABLE MOMS
AS SELECT ID as MOM_ID,
		  BIRTH_LINK_ID,
		  MIN(INFANT_DOB) as DOB_MOM_TBL,
		  1 as BIRTH_INDICATOR,
		  COUNT(DISTINCT MOM_ID) as num_moms
FROM PHDBIRTH.BIRTH_MOM
GROUP BY BIRTH_LINK_ID;
quit;

/* COUNT(DISTINCT MOM_ID) grouped by BIRTH_LINK_ID counts how many moms one birth had.
   If the birth_link has multiple mom_ids, we remove it*/

DATA MOMS; SET MOMS (WHERE = (num_moms = 1));
run;

/*  Collect All Infants */
/*  Output Dataset: INFANTS, one row per BIRTH_LINK_ID (birth) - could be multiple INFANT_IDs per BIRTH_LINK_ID
    Variables: INFANT_ID, BIRTH_LINK_ID, DOB_INFANT_TBL, INFANT_YEAR_BIRTH */

PROC SQL;
CREATE TABLE INFANTS
AS SELECT ID as INFANT_ID,
		  BIRTH_LINK_ID,
		  min(DOB) as DOB_INFANT_TBL,
		  min(YEAR_BIRTH) as INFANT_YEAR_BIRTH,
		  MONTH_BIRTH,
		  COUNT(DISTINCT BIRTH_LINK_ID) as num_births
FROM PHDBIRTH.BIRTH_INFANT
GROUP BY INFANT_ID;
quit;

/*  Remove cases where one infant matches to multiple birth IDs */
/*  since you can't be born multiple times */

DATA INFANTS; SET INFANTS (WHERE = (num_births = 1));
run;

/* Join cohort table without demographics */

/* Information to help understand the join: */
/* HCV:    MOM_ID - EVENT_DATE_HCV - DISEASE_STATUS - one row per MOM_ID
   MOMS:   MOM_ID - BIRTH_LINK_ID - DOB_MOM_TBL  - one row per BIRTH_LINK ID
   INFANT: INFANT_ID - BIRTH_LINK_ID - DOB_INFANT_TBL  - one row per INFANT_ID */

/*  Note: BIRTH_LINK_ID is not in the HCV table, but we can still infants after
    the first data using MOMS.BIRTH_LINK_ID as the key */

PROC SQL; 
 CREATE TABLE HCV_MOMS 
 AS SELECT DISTINCT * FROM HCV 
 LEFT JOIN MOMS on HCV.MOM_ID = MOMS.MOM_ID 
 LEFT JOIN INFANTS on MOMS.BIRTH_LINK_ID = INFANTS.BIRTH_LINK_ID; 
 quit; 

/* HCV_MOMS should be one row per infant
   NOTE: At this stage HCV moms is the entire HCV table (Men and women) with mother/infant data left joined to it.
   The vast majority of infant/mom related variables will have NA values, since most
   people in the HCV dataset did not have a child. */

/* Keep all data, but count how many BIRTH_LINK_ID's each individial infant has*/
PROC SQL;
CREATE TABLE HCV_MOMS
AS SELECT DISTINCT *, COUNT(DISTINCT BIRTH_LINK_ID) as num_infant_birth_ids FROM HCV_MOMS
GROUP BY INFANT_ID;
quit;

/* Restrict our HCV_MOMS dataset to infants with exactly one birth ID
   This deletes all non-mothers. */

DATA HCV_MOMS; SET HCV_MOMS (WHERE = (num_infant_birth_ids = 1)); 
run;

/* Filter our data table to seropositive women who had a birth */
DATA HCV_MOMS; SET HCV_MOMS;
	IF  BIRTH_INDICATOR = . THEN DELETE;
	IF  DOB_MOM_TBL < MOM_EVENT_DATE_HCV THEN DELETE;
run;

/* Pull Covariates */

/* MOUD */
proc sql;
    create table HCV_MOMS as
    select HCV_MOMS.*,
           moud.DATE_START_MOUD,
           moud.DATE_END_MOUD
    from HCV_MOMS
    left join PHDSPINE.MOUD as moud 
    on moud.ID = HCV_MOMS.MOM_ID;
quit;

data HCV_MOMS;
    set HCV_MOMS;

    /* Check if DOB_INFANT_TBL is missing */
    if missing(DOB_INFANT_TBL) then do;
        MOUD_DURING_PREG = .;
        MOUD_AT_DELIVERY = .;
    end;
    else do;
        /* Calculate the difference in days for DATE_START_MOUD */
        days_difference_start = DATE_START_MOUD - DOB_INFANT_TBL ;

        /* Calculate the difference in days for DATE_END_MOUD */
        days_difference_end = DATE_END_MOUD - DOB_INFANT_TBL ;

        /* Check if medication start or end was during the 9 months of gestation 
           or if DATE_END_MOUD is after DOB_INFANT_TBL  */
        MOUD_DURING_PREG = (days_difference_start >= -9*30) or
                            (days_difference_end >= -9*30) or
                            (DATE_END_MOUD > DOB_INFANT_TBL );

        /* Check if medication start or end was within 2 months of delivery 
           or if DATE_END_MOUD is after DOB_INFANT_TBL  */
        MOUD_AT_DELIVERY = (days_difference_start >= -2*30) or
                            (days_difference_end >= -2*30) or
                            (DATE_END_MOUD > DOB_INFANT_TBL );

        /* Drop temporary variables */
        drop days_difference_start days_difference_end;
    end;
run;

/* HCV */
proc sql;
    create table HCV_MOMS as
    select HCV_MOMS.*,
           hcv.EVENT_DATE_HCV
    from HCV_MOMS
    left join PHDHEPC.HCV as hcv 
    on hcv.ID = HCV_MOMS.MOM_ID;
quit;

data HCV_MOMS;
    set HCV_MOMS;

    /* Calculate the difference in days */
    hcv_duration_count = EVENT_DATE_HCV - DOB_INFANT_TBL ;

run;

/* HIV */
proc sql;
    create table HCV_MOMS as
    select HCV_MOMS.*,
           hiv.DIAGNOSIS_DATE_HIV
    from HCV_MOMS
    left join PHDHIV.HIV_INC as hiv 
    on hiv.ID = HCV_MOMS.MOM_ID;
quit;

data HCV_MOMS;
    set HCV_MOMS;

    /* Check if start was before birth */
    if DIAGNOSIS_DATE_HIV < DOB_INFANT_TBL  then
        HIV_DIAGNOSIS = 1;
    else
        HIV_DIAGNOSIS = 0;
        
run;

/*====================*/
/* Final COHORT TABLE */
/*====================*/

PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX
	FROM PHDSPINE.DEMO;
	QUIT;

/* INFANT_COHORT will be our primary cohort of interest */
PROC SQL;
CREATE TABLE INFANT_COHORT as
SELECT DISTINCT INFANT_ID,
				INFANT_YEAR_BIRTH,
				MONTH_BIRTH,
				DOB_INFANT_TBL,
				MOM_DISEASE_STATUS_HCV,
				MOM_EVENT_DATE_HCV,
				FINAL_RE,
				FINAL_SEX,
				HIV_DIAGNOSIS,
				MOUD_DURING_PREG,
				MOUD_AT_DELIVERY
FROM HCV_MOMS
LEFT JOIN demographics ON HCV_MOMS.INFANT_ID = demographics.ID;
quit;

/* Sort the dataset by INFANT_ID HIV_DIAGNOSIS MOUD_DURING_PREG */
proc sort data=infant_cohort;
  by INFANT_ID descending HIV_DIAGNOSIS descending MOUD_DURING_PREG;
run;

/* Create a new dataset to store the reduced output */
data INFANT_COHORT;
  /* Set the first row as the initial values */
  set infant_cohort;
  by INFANT_ID;

  /* Retain the first row for each INFANT_ID */
  if first.INFANT_ID then output;

run;

/*====================================*/
/* COHORT 2: Any Child <=15 in MAVEN */ 
/*====================================*/

/* Cohort of secondary interest */

PROC SQL;
CREATE TABLE COHORT15 as
SELECT DISTINCT ID, AGE_HCV, DISEASE_STATUS_HCV, EVENT_YEAR_HCV
FROM PHDHEPC.HCV
WHERE AGE_HCV <=15 AND AGE_HCV NE .;
quit;

/*============================ */
/*        HCV CASCADE          */
/*============================ */

/* ========================================================== */
/*                       HCV TESTING                          */
/* ========================================================== */

/* =========== */
/* AB TESTING */
/* ========== */
DATA ab;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR MED_AGE
					 
					 WHERE = (MED_PROC_CODE IN  &AB_CPT));
run;

/* Deduplicate */
proc sql;
create table AB1 as
select distinct ID, MED_FROM_DATE, *
from AB;
quit;

/* Sort the data by ID in ascending order */
PROC SORT data=ab1;
  by ID MED_FROM_DATE;
RUN;

/* Transpose for long table */
PROC TRANSPOSE data=ab1 out=ab_wide (KEEP = ID AB_TEST_DATE:) PREFIX=AB_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

PROC SQL;
    create table AB_YEARS as
    SELECT DISTINCT ID, MED_FROM_DATE_YEAR as AB_TEST_YEAR, MED_AGE
    FROM AB1
    ORDER BY ID, MED_FROM_DATE_YEAR;
QUIT;

data AB_YEARS_FIRST;
    set AB_YEARS;
    by ID;
    if first.ID;
run;

proc freq data=AB_YEARS_FIRST; 
    tables AB_TEST_YEAR; 
    where MED_AGE < 4; 
run;

/* =========== */
/* RNA TESTING */
/* =========== */

DATA rna;
SET PHDAPCD.MOUD_MEDICAL(KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR MED_AGE
					 
					 WHERE = (MED_PROC_CODE IN  &RNA_CPT));
run;

/* Deduplicate */
proc sql;
create table rna1 as
select distinct ID, MED_FROM_DATE, *
from rna;
quit;

/* Sort the data by ID in ascending order */
PROC SORT data=rna;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=rna out=rna_wide (KEEP = ID RNA_TEST_DATE:) PREFIX=RNA_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

PROC SQL;
    create table RNA_YEARS as
    SELECT DISTINCT ID, MED_FROM_DATE_YEAR as RNA_TEST_YEAR, MED_AGE
    FROM rna1
    ORDER BY ID, MED_FROM_DATE_YEAR;
QUIT;

data RNA_YEARS_FIRST;
    set RNA_YEARS;
    by ID;
    if first.ID;
run;

proc freq data=RNA_YEARS_FIRST; 
    tables RNA_TEST_YEAR; 
    where MED_AGE < 4; 
run;

/* ================ */
/* GENOTYPE TESTING */
/* ================ */

DATA geno;
SET PHDAPCD.MOUD_MEDICAL(KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
					 WHERE = (MED_PROC_CODE IN  &GENO_CPT));
run;

/* Sort the data by ID in ascending order */
PROC SORT data=geno;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=geno out=geno_wide (KEEP = ID GENO_TEST_DATE:) PREFIX=GENO_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

/*  Join all labs to INFANT_COHORT */
PROC SQL;
    CREATE TABLE INFANT_TESTING AS
    SELECT * FROM INFANT_COHORT 
    LEFT JOIN ab_wide ON ab_wide.ID = INFANT_COHORT.INFANT_ID
    LEFT JOIN rna_wide ON rna_wide.ID = INFANT_COHORT.INFANT_ID
    LEFT JOIN geno_wide ON geno_wide.ID = INFANT_COHORT.INFANT_ID;
QUIT;

DATA INFANT_TESTING;
	SET INFANT_TESTING;
	AB_TEST_INDICATOR = 0;
	RNA_TEST_INDICATOR = 0;
    GENO_TEST_INDICATOR = 0;
	IF AB_TEST_DATE_1 = . THEN AB_TEST_INDICATOR = 0; ELSE AB_TEST_INDICATOR = 1;
	IF RNA_TEST_DATE_1 = .  THEN RNA_TEST_INDICATOR = 0; ELSE RNA_TEST_INDICATOR = 1;
	IF GENO_TEST_DATE_1 = . THEN GENO_TEST_INDICATOR = 0; ELSE GENO_TEST_INDICATOR = 1;
    ANY_HCV_TESTING_INDICATOR = 0;
	IF AB_TEST_INDICATOR = 1 OR RNA_TEST_INDICATOR = 1 THEN ANY_HCV_TESTING_INDICATOR = 1;
 run;  

* Rachel testing adding in requirement for RNA test to occur at >= 2mo of age & Ab to be at 18mo=547 days to be 'appropriate'*/
/* I initially tried to add it to the above datastep, but I find it more accurate to do so with an array so I created a new 
   datastep for appropriate testing determination -- otherwise you need to do a super long 'OR' statement b/c even if first RNA
   or Ab test were done too early, a second, third or forth etc coudl have been appropriately timed */;

Proc sort data=INFANT_TESTING; by INFANT_ID; run; *actually, not sure the sort, by statement or retains are needed bc there's only one row per infant, right?;

DATA INFANT_TESTING;
    SET INFANT_TESTING;
    by INFANT_ID;

    /* Determine the number of variables dynamically */
    array RNA_TESTS (*) RNA_TEST_DATE_:;
    array AB_TESTS (*) AB_TEST_DATE_:;
    num_rna_tests = dim(RNA_TESTS);
    num_ab_tests = dim(AB_TESTS);

    /* Retain statement */
    retain APPROPRIATE_AB_Testing APPROPRIATE_RNA_Testing APPROPRIATE_Testing 
           AGE_AT_FIRST_TEST AGE_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST;

    /* Initialize variables at the start of each group */
    IF first.INFANT_ID THEN DO;
        APPROPRIATE_AB_Testing = 0; APPROPRIATE_RNA_Testing = 0;
        APPROPRIATE_Testing = 0; AGE_AT_FIRST_TEST = .; AGE_AT_FIRST_AB_TEST = .; AGE_AT_FIRST_RNA_TEST = .;
    END;

    /* Loop through the determined number of variables for RNA tests */
    DO i=1 TO num_rna_tests;
        IF AGE_AT_FIRST_RNA_TEST = . AND RNA_TESTS(i) NE . THEN
            AGE_AT_FIRST_RNA_TEST = FLOOR((RNA_TESTS(i) - DOB_INFANT_TBL)/30.4);
        IF (RNA_TESTS(i) - DOB_INFANT_TBL) > 60 THEN
            APPROPRIATE_RNA_Testing = 1; /* Had an RNA test at >=2mo of age; */
    END;

    /* Loop through the determined number of variables for AB tests */
    DO i=1 TO num_ab_tests;
        IF AGE_AT_FIRST_AB_TEST = . AND AB_TESTS(i) NE . THEN
            AGE_AT_FIRST_AB_TEST = FLOOR((AB_TESTS(i) - DOB_INFANT_TBL)/30.4);
        IF (AB_TESTS(i) - DOB_INFANT_TBL) > 547 THEN
            APPROPRIATE_AB_Testing = 1; /* Had an Ab test at >=18mo of age; */
    END;

    /* Determine if any appropriate testing occurred */
    IF APPROPRIATE_AB_Testing = 1 OR APPROPRIATE_RNA_Testing = 1 THEN
        APPROPRIATE_Testing = 1;

    /* Determine the minimum age at first test */
    IF AGE_AT_FIRST_AB_TEST NE . AND AGE_AT_FIRST_RNA_TEST NE . THEN
        AGE_AT_FIRST_TEST = MIN(AGE_AT_FIRST_AB_TEST, AGE_AT_FIRST_RNA_TEST);
    ELSE IF AGE_AT_FIRST_AB_TEST NE . THEN
        AGE_AT_FIRST_TEST = AGE_AT_FIRST_AB_TEST;
    ELSE IF AGE_AT_FIRST_RNA_TEST NE . THEN
        AGE_AT_FIRST_TEST = AGE_AT_FIRST_RNA_TEST;

    /* Format the ages at first tests to reduce suppression */
    IF AGE_AT_FIRST_AB_TEST > 30 THEN AGE_YRS_AT_FIRST_AB_TEST = FLOOR(AGE_AT_FIRST_AB_TEST/12);
    IF AGE_AT_FIRST_RNA_TEST > 18 THEN AGE_YRS_AT_FIRST_RNA_TEST = FLOOR(AGE_AT_FIRST_RNA_TEST/12);
    IF AGE_AT_FIRST_TEST > 30 THEN AGE_YRS_AT_FIRST_TEST = FLOOR(AGE_AT_FIRST_TEST/12);

RUN;

/* ========================================================== */
/*                   HCV STATUS FROM MAVEN                    */
/* ========================================================== */

/* This step is confusing and should probably be re-written
   In PHD, DISEASE_STATUS_HCV = 1 for confirmed, 2 for probable
   We recoded it here just to make it a yes/no indicator for confirmed status  */

PROC SQL;
	CREATE TABLE HCV_STATUS AS
	SELECT distinct ID,
	min(EVENT_YEAR_HCV) as EVENT_YEAR_HCV,
	min(EVENT_DATE_HCV) as EVENT_DATE_HCV,
	MIN(EVER_IDU_HCV) as EVER_IDU_HCV,
    MIN(AGE_HCV) as AGE_AT_DX, /*RACHEL just added 7/21/23*/
	1 as HCV_SEROPOSITIVE_INDICATOR,
	CASE WHEN min(DISEASE_STATUS_HCV) = 1 THEN 1 ELSE 0 END as CONFIRMED_HCV_INDICATOR FROM PHDHEPC.HCV
	GROUP BY ID;
QUIT;

/*  JOIN TO LARGER TABLE */

PROC SQL;
    CREATE TABLE INFANT_HCV_STATUS AS
    SELECT * FROM INFANT_TESTING 
    LEFT JOIN HCV_STATUS ON HCV_STATUS.ID = INFANT_TESTING.INFANT_ID;
QUIT;

/* ========================================================== */
/*                      LINKAGE TO CARE                       */
/* ========================================================== */

/* FILTER WHOLE DATASET */
DATA HCV_LINKED_SAS;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_ADM_TYPE MED_ICD1
					 
					 WHERE = (MED_ICD1 IN &HCV_ICD));
RUN;

/* FINAL LINKAGE TO CARE DATASET */
/* Should be one row per person. */

PROC SQL;
CREATE TABLE HCV_LINKED AS 
SELECT ID,
 	   1 as HCV_PRIMARY_DIAG,
       min(MED_FROM_DATE) as FIRST_HCV_PRIMARY_DIAG_DATE
from HCV_LINKED_SAS
GROUP BY ID;
QUIT;

/*  JOIN LINKAGE TO MAIN DATASET */

PROC SQL;
    CREATE TABLE INFANT_LINKED AS
    SELECT * FROM INFANT_HCV_STATUS
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = INFANT_HCV_STATUS.INFANT_ID;
QUIT;
  
/* Add 0's to those without linkage indicator */
DATA INFANT_LINKED; SET INFANT_LINKED;
IF HCV_PRIMARY_DIAG = . THEN HCV_PRIMARY_DIAG = 0;
IF HCV_SEROPOSITIVE_INDICATOR = . THEN HCV_SEROPOSITIVE_INDICATOR = 0;
run;

/* ========================================================== */
/*                       DAA STARTS                           */
/* ========================================================== */

/* Extract all relevant data
DATA DAA; SET PHDAPCD.MOUD_PHARM(KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
								
								WHERE = (PHARM_NDC IN &DAA_CODES));
RUN;

/* Reduce to one row per person */
PROC SQL;
CREATE TABLE DAA_STARTS as
SELECT distinct ID,
	   min(PHARM_FILL_DATE_YEAR) as FIRST_DAA_START_YEAR,
	   min(PHARM_FILL_DATE) as FIRST_DAA_DATE,
       min(PHARM_AGE) as AGE_DAA_START,
		
	   1 as DAA_START_INDICATOR from DAA
GROUP BY ID;
QUIT; *RE added 8/3 to keep PHARM_AGE and PHARM_NDC here & then 8/8 added min to PHARM_AGE and deleted PHARM_NDC bc i think there were duplicates bc of extra variables it was trying to merge;

/* Join to main dataset */
PROC SQL;
    CREATE TABLE INFANT_DAA AS
    SELECT * FROM INFANT_LINKED 
    LEFT JOIN DAA_STARTS ON DAA_STARTS.ID = INFANT_LINKED.ID;
QUIT;

DATA INFANT_DAA; SET INFANT_DAA;
IF DAA_START_INDICATOR = "." THEN DAA_START_INDICATOR = 0;
run;

PROC CONTENTS data=INFANT_DAA;
title "Contents of Final Dataset";
run;

/* Note: MED_FROM_DATE (what rna/ab test dates are derived from) and
         first_DAA_DATE are date proxies that are counts of days.
         So we can subtract them to find the number of days between events.
		 If they were in DATE format, the below code would not work. 
		 
		 EOT = end of treatment RNA -- ie was an RNA done between when treatment ended (which we call 12 wks after treatment start = so 84 days),
		 SVR12 = test of cure = RNA done at least 12 wks after treatment ENDS = 8wks of tx + 12wks after = 20wks or 140 days
		 */

DATA TESTING;
    SET INFANT_DAA;
    EOT_RNA_TEST = 0;
    SVR12_RNA_TEST = 0;
    *IF RNA_TEST_DATE_1 = "." THEN DELETE;
    *IF FIRST_DAA_DATE = "." THEN DELETE;

    /* Determine the number of variables dynamically */
    array test_date_array (*) RNA_TEST_DATE_:;
    num_tests = dim(test_date_array);

    /* Loop through the determined number of variables */
    do i = 1 to num_tests;
        if test_date_array{i} > 0 and FIRST_DAA_DATE > 0 then do;
            time_since = test_date_array{i} - FIRST_DAA_DATE;

            if time_since > 84 then EOT_RNA_TEST = 1;
            if time_since >= 140 then SVR12_RNA_TEST = 1;
        end;
    end;

    DROP i time_since;
RUN;

/* ========================================================== */
/*                       CASCADE TABLES                           */
/* ========================================================== */

PROC FORMAT;
   VALUE racefmt_all
		1 = "White"
		2 = "Black"
		3 = "Asian/PI"
		4 = "Hispanic"
		5 = "AmerInd/OtherNonHisp."
		9 = "Unknown"
		99 = "Not MA Res.";
RUN;

proc format;
	value pharmagegroupf 0="<3yo" 1="3-5yo" 2="6-11yo" 3="12-17yo" 4="adult";
	run;

PROC FORMAT;
   VALUE racefmt_comb
		1 = "White"
		2 = "Black"
		3 = "Asian/PI/AmerInd/Other/Unkn"
		4 = "Hispanic"
		5 = "Asian/PI/AmerInd/Other/Unkn"
		9 = "Asian/PI/AmerInd/Other/Unkn"
		99 = "Not MA Res.";
RUN;

proc format;
    value AGE_Testf
       ; 
run;

/* ========================================================== */
/*  HCV-EXPOSED INFANT TESTING CARE CASCADE TABLES */
/* ========================================================== */

/* For measuring testing for HCV, we want infants born 2014 (first year APCD in dataset) through 2019 
because we want Infants who were at least 18mo old by study end, because the testing recommendations,
at least through summer 2023, have been largely to wait until 18mo to test for HCV Ab - once maternal
Ab is lost. Therefore cohort for testing = born 2014-2019 */

/* Newly in July 2023, excluding those diagnosed at age >=3 or only probable status because they are 
not technically perinatal cases */

%macro Table1_Freq(title_text);
    proc freq data=TESTING;
        WHERE INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019; 
        title "&title_text";
        tables ANY_HCV_TESTING_INDICATOR AB_TEST_INDICATOR*RNA_TEST_INDICATOR APPROPRIATE_Testing APPROPRIATE_AB_Testing*APPROPRIATE_RNA_Testing CONFIRMED_HCV_INDICATOR DAA_START_INDICATOR CONFIRMED_HCV_INDICATOR*RNA_TEST_INDICATOR
               / out=Table1 norow nopercent nocol;
        format _NUMERIC_  15.;
    run;
    
    proc print data=Table1; 
    run;
%mend Table1_Freq;

%Table1_Freq("Infants born to moms with HCV, Testing and Diagnosis, Overall, born 2014-2019");

%macro Table2_Freq(title_text);
    proc freq data=TESTING;
        Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3;
        title "&title_text";
        tables ANY_HCV_TESTING_INDICATOR GENO_TEST_INDICATOR HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
               / out=Table2 norow nopercent nocol; 
    run;
    
    proc print data=Table2; 
    run;
%mend Table2_Freq;

%Table2_Freq("Infants with confirmed perinatal HCV only, unstratified, born 2014-2019 - ie age at dx <3");

%macro Table3_Freq(title_text);
    proc freq data=TESTING;
        Where (INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <=2017 OR (INFANT_YEAR_BIRTH=2018 AND MONTH_BIRTH<=6))
        AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
        title "&title_text";
        tables ANY_HCV_TESTING_INDICATOR HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
               / out=Table3 norow nopercent nocol; 
    run;
    
    proc print data=Table3; 
    run;
%mend Table3_Freq;

%Table3_Freq("Infants with confirmed perinatal HCV only, unstratified, born 1/2014-6/2018, Confirmed HCV");

%macro Table4_Freq(title_text);
    proc freq data=TESTING;
        Where INFANT_YEAR_BIRTH >= 2011 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
        title "&title_text";
        tables HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
               / out=Table4 norow nopercent nocol; 
    run;
    
    proc print data=Table4; 
    run;
%mend Table4_Freq;

%Table4_Freq("Infants with confirmed perinatal HCV only, unstratified, born 2011-2021");

%macro Table5_Freq(title_text);
    proc freq data=INFANT_DAA;
    WHERE INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2021;
    title "&title_text";
    table final_re / out=Table5 norow nopercent nocol;
    FORMAT final_re racefmt_all.;
    run;
    
    proc print data=Table5; 
    run;
%mend Table5_Freq;

%Table5_Freq("Total Number of EXPOSED Infants in Cohort, By Race, born 2014-2021");

%macro Table6_Freq(title_text);
    proc freq data=INFANT_DAA;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019;
    title "&title_text";
    tables ANY_HCV_TESTING_INDICATOR*final_re APPROPRIATE_Testing*final_re CONFIRMED_HCV_INDICATOR*final_re
        / out=Table6 norow nopercent nocol;
    FORMAT _NUMERIC_ 8.;
    FORMAT final_re racefmt_all.;
    run;
    
    proc print data=Table6; 
    run;
%mend Table6_Freq;

%Table6_Freq("Infants born to moms with HCV, TESTing/DIAGNOSIS Care Cascade, By Race, 2014-2019");

%macro Table7_Freq(title_text);
    proc freq data=INFANT_DAA;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
    title "&title_text";
    tables CONFIRMED_HCV_INDICATOR*final_re HCV_PRIMARY_DIAG*final_re GENO_TEST_INDICATOR*final_re
       / out=Table7 norow nopercent nocol;
    FORMAT _NUMERIC_  15.;
    FORMAT final_re racefmt_comb.;
    run;
    
    proc print data=Table7; 
    run;
%mend Table7_Freq;

%Table7_Freq("Infants born to moms with HCV, Care Cascade, By Race/Hispance Ethnicity, born 2014-2019, Confirmed Perinatal HCV");

%macro Table8_Freq(title_text);
    proc freq data=INFANT_DAA;
    Where INFANT_YEAR_BIRTH >= 2014; /*to exclude those born 2011-13 whose first test occurred pre-APCD start;*/
    TITLE "&title_text";
    TABLES INFANT_YEAR_BIRTH AGE_AT_FIRST_AB_TEST AGE_YRS_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST AGE_YRS_AT_FIRST_RNA_TEST AGE_AT_FIRST_TEST AGE_YRS_AT_FIRST_TEST
        / out=Table8 nocol nopercent norow;
    run;
    
    proc print data=Table8; 
    run;
%mend Table8_Freq;

%Table8_Freq("Number of Exposed Infants Born by YEAR & Age at first appropriate Ab, RNA testing, 2014-2021");

%macro Table9_Freq(title_text);
    proc freq data=PHDBIRTH.BIRTH_INFANT;
    TITLE "&title_text";
    TABLE YEAR_BIRTH / out=Table9 nocol nopercent norow;
    run;
    
    proc print data=Table9; 
    run;
%mend Table9_Freq;

%Table9_Freq("Total Number of Infants Born by YEAR, 2014-2021");

%macro Table10_Freq(title_text);
    proc freq data=INFANT_DAA;
    where APPROPRIATE_Testing = 1;
    Title "&title_text";
    TABLES INFANT_YEAR_BIRTH / out=Table10 nocol nopercent norow;
    run;
    
    proc print data=Table10; 
    run;
%mend Table10_Freq;

%Table10_Freq("Number of appropriately tested infants by infant year of birth ie in each year how many infants born that year were ultimately appropriately tested bt 2014-2021");

/*===============================================================================*/
/*  Apply HCV cascade to the 372 kids <15 in MAVEN HEPC
/*===============================================================================*/

/* Join all relevant tables */

/*  Testing */
PROC SQL;
    CREATE TABLE TESTING15 AS
    SELECT * FROM COHORT15 
    LEFT JOIN ab_wide ON ab_wide.ID = COHORT15.ID
    LEFT JOIN rna_wide ON rna_wide.ID = COHORT15.ID
    LEFT JOIN geno_wide ON geno_wide.ID = COHORT15.ID;
QUIT;

DATA TESTING15;
	SET TESTING15;
	AB_TEST_INDICATOR = 0;
	RNA_TEST_INDICATOR = 0;
    GENO_TEST_INDICATOR = 0;
	IF AB_TEST_DATE_1 = . THEN AB_TEST_INDICATOR = 0; ELSE AB_TEST_INDICATOR = 1;
	IF RNA_TEST_DATE_1 = . THEN RNA_TEST_INDICATOR = 0; ELSE RNA_TEST_INDICATOR = 1;
	IF GENO_TEST_DATE_1 = . THEN GENO_TEST_INDICATOR = 0; ELSE GENO_TEST_INDICATOR = 1;
	run;
	
DATA TESTING15;
	SET TESTING15;
		ANY_HCV_TESTING_INDICATOR = 0;
		IF AB_TEST_INDICATOR = 1 OR RNA_TEST_INDICATOR = 1 THEN ANY_HCV_TESTING_INDICATOR = 1;
run;

/* Linkage to Care  */

PROC SQL;
    CREATE TABLE HCV_STATUS15 AS
    SELECT * FROM TESTING15 
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = TESTING15.ID;
QUIT;

/* DAA STARTS */
PROC SQL;
    CREATE TABLE DAA15 AS
    SELECT * FROM HCV_STATUS15 
    LEFT JOIN DAA_STARTS ON DAA_STARTS.ID = HCV_STATUS15.ID;
QUIT;

/* Final Dataset for the under 15 cohort */
DATA DAA15; SET DAA15;
IF DAA_START_INDICATOR = . THEN DAA_START_INDICATOR = 0;
if AGE_DAA_START ne . then do;
	if 0 <= AGE_DAA_START < 3 then AGE_DAA_START_group=0;
	else if 3 <= AGE_DAA_START < 6 then AGE_DAA_START_group=1;
	else if 6 <= AGE_DAA_START < 12 then AGE_DAA_START_group=2;
	else if 12 <= AGE_DAA_START < 18 then AGE_DAA_START_group=3;
	else if AGE_DAA_START >=18 then AGE_DAA_START_group=4;
end;
run;

PROC SQL;
    CREATE TABLE DAA15 AS
    SELECT * FROM DAA15 
    LEFT JOIN demographics ON demographics.ID = DAA15.ID;
QUIT;

DATA TRT_TESTING15;
    SET DAA15;
    EOT_RNA_TEST = 0;
    SVR12_RNA_TEST = 0;
    *IF RNA_TEST_DATE_1 = "." THEN DELETE;
    *IF FIRST_DAA_DATE = "." THEN DELETE;

    /* Determine the number of variables dynamically */
    array test_date_array (*) RNA_TEST_DATE_:;
    num_tests = dim(test_date_array);

    /* Loop through the determined number of variables */
    do i = 1 to num_tests;
            if test_date_array{i} > 0 and FIRST_DAA_DATE > 0 then do;
                time_since = test_date_array{i} - FIRST_DAA_DATE;

                if time_since > 84 then EOT_RNA_TEST = 1;
                if time_since >= 140 then SVR12_RNA_TEST = 1;
            end;
            else time_since = .; /* Added this else back in 8/1/23 RE */
        end;

    DROP i time_since;
RUN;

/*=================================	*/
/*        <=15 Year Old   TABLES    */
/*=================================	*/

%macro Table11_Freq(title_text);
    proc freq data=DAA15;
        title "&title_text";
        tables DISEASE_STATUS_HCV DAA_START_INDICATOR FIRST_DAA_START_YEAR
               / out=Table11 norow nopercent nocol;
    run;
    
    proc print data=Table11; 
    run;
%mend Table11_Freq;

%Table11_Freq("HCV Care Cascade for children diagnosed with HCV at age <=15 years between 2011-2021, Overall");

%macro Table12_Freq(title_text);
    proc freq data=DAA15;
        Where FIRST_DAA_START_YEAR < 2020;
        title "&title_text";
        tables DAA_START_INDICATOR
               / out=Table12 norow nopercent nocol;
    run;
    
    proc print data=Table12; 
    run;
%mend Table12_Freq;

%Table12_Freq("<=15 HCV Care Cascade, DAA starts pre 2020");

%macro Table13_Freq(title_text);
    proc freq data=DAA15;
        WHERE DISEASE_STATUS_HCV = 1;
        title "&title_text";
        tables HCV_PRIMARY_DIAG RNA_TEST_INDICATOR GENO_TEST_INDICATOR
               DAA_START_INDICATOR EVENT_YEAR_HCV AGE_HCV
               / out=Table13 norow nopercent nocol;
    run;
    
    proc print data=Table13; 
    run;
%mend Table13_Freq;

%Table13_Freq("<=15 HCV Care Cascade, Among Confirmed");

%macro Table14_Freq(title_text);
    proc freq data=DAA15;
        WHERE DISEASE_STATUS_HCV = 1 and 3 < AGE_HCV < 11;
        title "&title_text";
        tables DISEASE_STATUS_HCV
               / out=Table14 norow nopercent nocol;
    run;
    
    proc print data=Table14; 
    run;
%mend Table14_Freq;

%Table14_Freq("HCV Diagnoses made among children 4-10yo between 2011-2021");

/* Table 15 */
%macro Table15_Freq(age_condition, title_text);
    proc freq data=DAA15;
        WHERE DISEASE_STATUS_HCV = 1 and &age_condition;
        title "&title_text";
        tables DISEASE_STATUS_HCV / out=Table15 norow nopercent nocol;
    run;
    
    proc print data=Table15; 
    run;
%mend Table15_Freq;

%Table15_Freq(10 < AGE_HCV <= 15, HCV Diagnoses made among children 11-15yo between 2011-2021);


%macro Table16_Freq(title_text);
    proc freq data=TRT_TESTING15;
        WHERE DAA_START_INDICATOR = 1;
        title "&title_text";
        tables EOT_RNA_TEST SVR12_RNA_TEST AGE_DAA_START_group
               / out=Table16 norow nopercent nocol;
        format AGE_DAA_START_group pharmagegroupf.;
    run;
    
    proc print data=Table16; 
    run;
%mend Table16_Freq;

%Table16_Freq("EOT/SVR12 & age at treatment, Among those treated");

%macro Table17_Freq(title_text);
    proc freq data=TRT_TESTING15;
        WHERE DISEASE_STATUS_HCV = 1 and DAA_START_INDICATOR = 1;
        title "&title_text";
        tables EOT_RNA_TEST SVR12_RNA_TEST
               / out=Table17 norow nopercent nocol;
    run;
    
    proc print data=Table17; 
    run;
%mend Table17_Freq;

%Table17_Freq("EOT/SVR12 & age at treatment, Among those treated & w confirmed HCV - dup in case age daa start group errors out again to get eot and svr");

%macro Table18_Freq(title_text);
    proc freq data=DAA15;
        title "&title_text";
        tables DISEASE_STATUS_HCV*final_re
               / out=Table18 norow nopercent nocol;
        FORMAT final_re racefmt_all.;
    run;
    
    proc print data=Table18; 
    run;
%mend Table18_Freq;

%Table18_Freq("<=15 HCV Care Cascade, by race/ethnicity");

%macro Table19_Freq(title_text);
    proc freq data=DAA15;
        Where DISEASE_STATUS_HCV = 1;
        title "&title_text";
        tables HCV_PRIMARY_DIAG*final_re
               GENO_TEST_INDICATOR*final_re
               DAA_START_INDICATOR*final_re
               / out=Table19 norow nopercent nocol;
        FORMAT final_re racefmt_comb.;
    run;
    
    proc print data=Table19; 
    run;
%mend Table19_Freq;

%Table19_Freq("<=15 HCV Care Cascade, by race/ethnicity, Among Confirmed");

/* ========================================================== */
/*                       Pull Covariates                      */
/* ========================================================== */

/* Join to add covariates */

proc sql;
    create table INFANT_DAA_with_covariates as
    select INFANT_DAA.*, 
           demographics.FINAL_RE,
           demographics.APCD_anyclaim,
           demographics.NON_MA,
           demographics.SELF_FUNDED,
           demographics.HOMELESS_HISTORY,
           birthsinfants.DISCH_WITH_MOM,
           birthsinfants.FACILITY_ID_BIRTH,
           birthsinfants.GESTATIONAL_AGE,
           birthsinfants.INF_VAC_HBIG,
           birthsinfants.NAS_BC,
           birthsinfants.NAS_BC_NEW,
           birthsinfants.RES_ZIP_BIRTH,
           birthsinfants.SEX_BIRTH,
           birthsinfants.Res_Code_Birth,
           case 
               when birthsinfants.NAS_BC = 1 or birthsinfants.NAS_BC_NEW = 1 then 1
               else .
           end as NAS_BC_TOTAL
    from INFANT_DAA
    left join PHDSPINE.DEMO as demographics
    on INFANT_DAA.ID = demographics.ID
    left join PHDBIRTH.BIRTH_INFANT as birthsinfants
    on INFANT_DAA.ID = birthsinfants.ID
    where demographics.APCD_anyclaim ne 1 
      and demographics.SELF_FUNDED ne 1 
      and demographics.NON_MA ne 1;
quit;

%let well_child = ('Z00129', 'Z00121', /* ICD-10 codes */
                    'V202', 'V700', 'V703', 'V705', 'V706', 'V708', 'V709'); /* ICD-9 codes */

proc sql;
    create table INFANT_DAA_with_covariates as
	select INFANT_DAA_with_covariates.*,
       case when apcd.MED_PROC_CODE in &well_child and age_months between 18 and 36 then 1 else 0 end as well_child
	from INFANT_DAA_with_covariates
	left join (
    select apcd.ID, apcd.MED_PROC_CODE,
           floor((intck('month', INFANT_DAA_with_covariates.INFANT_YEAR_BIRTH, apcd.MED_FROM_DATE))/12)*12 +
           intck('month', INFANT_DAA_with_covariates.INFANT_YEAR_BIRTH, apcd.MED_FROM_DATE) as age_months
    from PHDAPCD.MOUD_MEDICAL as apcd
    inner join INFANT_DAA_with_covariates
    on apcd.ID = INFANT_DAA_with_covariates.ID
	) as apcd
		on INFANT_DAA_with_covariates.ID = apcd.ID;
quit;

%let oud_data_path = OUD_HCV_DAA_with_covariates;

data INFANT_DAA_with_covariates;
    merge INFANT_DAA_with_covariates (in=a)
          OUD_HCV_DAA (in=b)
          &oud_data_path (in=b);
    by ID;

    OUD_capture = (b = 1) and oud_age < AGE_BIRTH;
    
    drop b;
    if missing(OUD_capture) then OUD_capture = 0;
run;

/* ========================================================== */
/*                       Table 1 and Regressions              */
/* ========================================================== */

%macro Table1Freqs (var);
proc freq data=INFANT_DAA_with_covariates; tables &var / missing; run;
%mend;

%Table1freqs (FINAL_SEX);
%Table1freqs (GESTATIONAL_AGE);
%Table1freqs (FINAL_RE);
%Table1freqs (FACILITY_ID_BIRTH);
%Table1freqs (Res_Code_Birth);
%Table1freqs (well_child);
%Table1freqs (NAS_BC_TOTAL);
%Table1freqs (HOMELESS_HISTORY);
%Table1freqs (DISCH_WITH_MOM);
%Table1freqs (INF_VAC_HBIG);
%Table1freqs (HIV_DIAGNOSIS);
%Table1freqs (MOUD_DURING_PREG);
%Table1freqs (MOUD_AT_DELIVERY);
%Table1freqs (OUD_CAPTURE);

%macro Table1StrataFreqs(var);
    /* Sort the dataset by APPROPRIATE_Testing */
    proc sort data=INFANT_DAA_with_covariates;
        by APPROPRIATE_Testing;
    run;

    /* Run PROC FREQ with BY statement */
    proc freq data=INFANT_DAA_with_covariates;
        by APPROPRIATE_Testing;
        tables &var / missing;
    run;
%mend;

%Table1Stratafreqs (FINAL_SEX);
%Table1Stratafreqs (GESTATIONAL_AGE);
%Table1Stratafreqs (FINAL_RE);
%Table1Stratafreqs (FACILITY_ID_BIRTH);
%Table1Stratafreqs (Res_Code_Birth);
%Table1Stratafreqs (well_child);
%Table1Stratafreqs (NAS_BC_TOTAL);
%Table1Stratafreqs (HOMELESS_HISTORY);
%Table1Stratafreqs (DISCH_WITH_MOM);
%Table1Stratafreqs (INF_VAC_HBIG);
%Table1Stratafreqs (HIV_DIAGNOSIS);
%Table1Stratafreqs (MOUD_DURING_PREG);
%Table1Stratafreqs (MOUD_AT_DELIVERY);
%Table1Stratafreqs (OUD_CAPTURE);

%macro Table2Crude (var);
proc logistic data=INFANT_DAA_with_covariates desc; 
	class &var (param=ref);
	model APPROPRIATE_Testing=&var;
	run;
%mend;

%Table2Crude (FINAL_SEX);
%Table2Crude (GESTATIONAL_AGE);
%Table2Crude (FINAL_RE);
%Table2Crude (FACILITY_ID_BIRTH);
%Table2Crude (Res_Code_Birth);
%Table2Crude (well_child);
%Table2Crude (NAS_BC_TOTAL);
%Table2Crude (HOMELESS_HISTORY);
%Table2Crude (DISCH_WITH_MOM);
%Table2Crude (INF_VAC_HBIG);
%Table2Crude (HIV_DIAGNOSIS);
%Table2Crude (MOUD_DURING_PREG);
%Table2Crude (MOUD_AT_DELIVERY);
%Table2Crude (OUD_CAPTURE);