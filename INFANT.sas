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

DATA HCV_MOMS; SET HCV_MOMS (WHERE = (num_infant_birth_ids = 1)); run;


/* Filter our data table to seropositive women who had a birth */
DATA HCV_MOMS; SET HCV_MOMS;
IF  BIRTH_INDICATOR = . THEN DELETE;
IF  DOB_MOM_TBL < MOM_EVENT_DATE_HCV THEN DELETE;
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
				FINAL_SEX
FROM HCV_MOMS
LEFT JOIN demographics ON HCV_MOMS.INFANT_ID = demographics.ID;
quit;

/* We now have a datatable of 6073 INFANT IDs from mothers who were seropositive 
	now it's 6126 with the 2021 data added in */

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
/*Dataset name updated by EErdman from MOUD_MEDICALto  RE_MEDICAL_FILTERED to 1/12/24 */
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
PROC TRANSPOSE data=ab1 out=ab_wide (KEEP = ID AB_TEST_DATE_1-AB_TEST_DATE_54);
BY ID;
VAR MED_FROM_DATE;
RUN;

/* ======================================= */
/* PREP DATASET FOR AB_TESTING BY YEAR - to see how Ab testing trends changed over time  */
/* RE edited this code and added med_age to the ab and rna tables to make possible to restrict to testing ocurring in <4yos on 8/3/23 */
/* ==================================== */

/* Count one test per person per year */
PROC SQL;
create table AB_YEARS as
SELECT DISTINCT ID, min(MED_FROM_DATE_YEAR) as AB_TEST_YEAR, MED_AGE
FROM AB1;
quit;


/* =========== */
/* RNA TESTING */
/* =========== */

DATA rna;
SET PHDAPCD.MOUD_MEDICAL(KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR MED_AGE
					 
					 WHERE = (MED_PROC_CODE IN  &RNA_CPT));
run;

/* Sort the data by ID in ascending order */
PROC SORT data=rna;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=rna out=rna_wide (KEEP = ID RNA_TEST_DATE_1-RNA_TEST_DATE_57);
BY ID;
VAR MED_FROM_DATE;
RUN;

/* Deduplicate */
proc sql;
create table rna1 as
select distinct ID, MED_FROM_DATE, *
from rna;
quit;

/* Count one test per person per year - now for RNA*/
PROC SQL;
create table RNA_YEARS as
SELECT DISTINCT ID, min(MED_FROM_DATE_YEAR) as RNA_TEST_YEAR, MED_AGE
FROM rna1;
quit;


proc freq data=AB_YEARS; tables AB_TEST_YEAR; where MED_AGE < 4; run;
proc freq data=RNA_YEARS; tables RNA_TEST_YEAR; where MED_AGE < 4; run;

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

PROC TRANSPOSE data=geno out=geno_wide (KEEP = ID GENO_TEST_DATE_1-GENO_TEST_DATE_23);
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
    array RNA_TEST_DATE_ (57) RNA_TEST_DATE_1-RNA_TEST_DATE_57;
    array AB_TEST_DATE_ (57) AB_TEST_DATE_1-AB_TEST_DATE_57;
    retain APPROPRIATE_AB_Testing APPROPRIATE_RNA_Testing APPROPRIATE_Testing 
           AGE_AT_FIRST_TEST AGE_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST;
	
    /* APPRORIATE TESTING */

    IF first.INFANT_ID then do; 
            APPROPRIATE_AB_Testing = 0 ; APPROPRIATE_RNA_Testing = 0;
            APPROPRIATE_Testing = 0 ; AGE_AT_FIRST_TEST = . ; AGE_AT_FIRST_AB_TEST = . ; AGE_AT_FIRST_RNA_TEST = .;
            AGE_YRS_AT_FIRST_AB_TEST = .; AGE_YRS_AT_FIRST_RNA_TEST= . ; 
            end;

    Do i=1 to 57;
        if AGE_AT_FIRST_RNA_TEST = . and RNA_TEST_DATE_(i) ne . then AGE_AT_FIRST_RNA_TEST = floor((RNA_TEST_DATE_(i) - DOB_INFANT_TBL)/30.4);   
        if AGE_AT_FIRST_AB_TEST = . and AB_TEST_DATE_(i) ne . then AGE_AT_FIRST_AB_TEST = floor((AB_TEST_DATE_(i) - DOB_INFANT_TBL)/30.4);
		IF (RNA_TEST_DATE_(i) - DOB_INFANT_TBL) > 60 then do; 
            APPROPRIATE_RNA_Testing = 1; * Had an RNA test at >=2mo of age;   
        end;
        IF (AB_TEST_DATE_(i) - DOB_INFANT_TBL) > 547 then do; 
            APPROPRIATE_AB_Testing = 1;  * Had an Ab test at >=18mo of age;
        end;
    end;

    IF APPROPRIATE_AB_Testing = 1 or APPROPRIATE_RNA_Testing = 1 then APPROPRIATE_Testing = 1; 
    
    IF AGE_AT_FIRST_AB_TEST ne . and AGE_AT_FIRST_RNA_TEST ne . then
             AGE_AT_FIRST_TEST = min(AGE_AT_FIRST_AB_TEST, AGE_AT_FIRST_RNA_TEST); *only if niether are missing;
    ELSE if AGE_AT_FIRST_AB_TEST ne . then AGE_AT_FIRST_TEST = AGE_AT_FIRST_AB_TEST;
    ELSE if AGE_AT_FIRST_RNA_TEST ne . then AGE_AT_FIRST_TEST = AGE_AT_FIRST_RNA_TEST;

  *format the ages at first tests to reduce suppression but keep precision -- ie convert to age in yrs if >2.5-3yrs bc that's where suppression starts;

    if AGE_AT_FIRST_AB_TEST > 30 then AGE_YRS_AT_FIRST_AB_TEST = floor(AGE_AT_FIRST_AB_TEST/12);
    if AGE_AT_FIRST_RNA_TEST > 18 then AGE_YRS_AT_FIRST_RNA_TEST = floor(AGE_AT_FIRST_RNA_TEST/12);
	If AGE_AT_FIRST_TEST > 30 then AGE_YRS_AT_FIRST_TEST = floor(AGE_AT_FIRST_TEST/12);
  
run; 

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
Updated by EErdman 011224 from MOUD_PHARM to RE_PHARM_FILTERED*/
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


DATA TESTING; SET INFANT_DAA;
	EOT_RNA_TEST = 0;
	SVR12_RNA_TEST = 0;
	*IF RNA_TEST_DATE_1 = . THEN DELETE;
	*IF FIRST_DAA_DATE = . THEN DELETE;
	ARRAY test_date_array {57} RNA_TEST_DATE_1-RNA_TEST_DATE_57;
	ARRAY time_since_array {57} time_since_last_daa1 - time_since_last_daa57; 
		do i = 1 to 57;
		if TEST_DATE_ARRAY{i}>0 and FIRST_DAA_DATE>0 then
		time_since_array{i} = test_date_array{i} - FIRST_DAA_DATE;
		else Time_since_array{i}=.;
	    IF time_since_array{i} > 84   THEN EOT_RNA_TEST = 1;
        IF time_since_array{i} >= 140 THEN SVR12_RNA_TEST = 1;
		end;
	DROP i;
run;

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

/* Table 1 */
proc freq data=TESTING;
    WHERE INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019; 
    title "Infants born to moms with HCV, Testing and Diagnosis, Overall, born 2014-2019";
    tables ANY_HCV_TESTING_INDICATOR
           AB_TEST_INDICATOR*RNA_TEST_INDICATOR
           APPROPRIATE_Testing
           APPROPRIATE_AB_Testing*APPROPRIATE_RNA_Testing
           CONFIRMED_HCV_INDICATOR
           DAA_START_INDICATOR
           CONFIRMED_HCV_INDICATOR*RNA_TEST_INDICATOR / out=Table1 norow nopercent nocol;
    format _NUMERIC_  15.;
run;

proc print data=Table1; run;

/* Table 2 */
proc freq data=TESTING;
Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3;
title "Infants with confirmed perinatal HCV only, unstratified, born 2014-2019 - ie age at dx <3";
tables ANY_HCV_TESTING_INDICATOR
       GENO_TEST_INDICATOR
       HCV_PRIMARY_DIAG 
       DAA_START_INDICATOR
       EOT_RNA_TEST
       SVR12_RNA_TEST / out=Table2 norow nopercent nocol; 
run;

proc print data=Table2; run;

/* Table 3 */
proc freq data=TESTING;
Where (INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <=2017 OR (INFANT_YEAR_BIRTH=2018 AND MONTH_BIRTH<=6))
AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
title "Infants with confirmed perinatal HCV only, unstratified, born 1/2014-6/2018, Confirmed HCV";
tables ANY_HCV_TESTING_INDICATOR
       HCV_PRIMARY_DIAG 
       DAA_START_INDICATOR
       EOT_RNA_TEST
       SVR12_RNA_TEST
       / out=Table3 norow nopercent nocol; 
run;

proc print data=Table3; run;

/* Table 4 */
proc freq data=TESTING;
Where INFANT_YEAR_BIRTH >= 2011 
AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
title "Infants with confirmed perinatal HCV only, unstratified, born 2011-2021";
tables 
       HCV_PRIMARY_DIAG 
       DAA_START_INDICATOR
       EOT_RNA_TEST
       SVR12_RNA_TEST
       / out=Table4 norow nopercent nocol; 
run;

proc print data=Table4; run;

/* Table 5 */
proc freq data=INFANT_DAA;
WHERE INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2021;
title "Total Number of EXPOSED Infants in Cohort, By Race, born 2014-2021";
table final_re / out=Table5 norow nopercent nocol;
FORMAT final_re racefmt_all.;
run;

proc print data=Table5; run;

/* Table 6 */
proc freq data=INFANT_DAA;
Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019;
title "Infants born to moms with HCV, TESTing/DIAGNOSIS Care Cascade, By Race, 2014-2019";
tables ANY_HCV_TESTING_INDICATOR*final_re
       APPROPRIATE_Testing*final_re
       CONFIRMED_HCV_INDICATOR*final_re
        / out=Table6 norow nopercent nocol;
FORMAT _NUMERIC_ 8. ; 
FORMAT final_re racefmt_all. ;
run;

proc print data=Table6; run;

/* Table 7 */
proc freq data=INFANT_DAA;
Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
title "Infants born to moms with HCV, Care Cascade, By Race/Hispance Ethnicity, born 2014-2019, Confirmed Perinatal HCV";
tables 
        CONFIRMED_HCV_INDICATOR*final_re
       HCV_PRIMARY_DIAG*final_re 
       GENO_TEST_INDICATOR*final_re
       / out=Table7 norow nopercent nocol;
FORMAT _NUMERIC_  15.;
FORMAT final_re racefmt_comb. ;
run;

proc print data=Table7; run;

/* Table 8 */
proc freq data=INFANT_DAA;
Where INFANT_YEAR_BIRTH >= 2014; *to exclude those born 2011-13 whose first test occurred pre-APCD start;
    TITLE "Number of Exposed Infants Born by YEAR & Age at first appropriate Ab, RNA testing, 2014-2021";
    TABLES INFANT_YEAR_BIRTH 
            AGE_AT_FIRST_AB_TEST
            AGE_YRS_AT_FIRST_AB_TEST
            AGE_AT_FIRST_RNA_TEST
            AGE_YRS_AT_FIRST_RNA_TEST
            AGE_AT_FIRST_TEST
            AGE_YRS_AT_FIRST_TEST
        / out=Table8 nocol nopercent norow ;
run;

proc print data=Table8; run;

/* Table 9 */
proc freq data=PHDBIRTH.BIRTH_INFANT;
TITLE "Total Number of Infants Born by YEAR, , 2014-2021";
TABLE YEAR_BIRTH / out=Table9 nocol nopercent norow;
run;

proc print data=Table9; run;

/* Table 10 */
proc freq data=INFANT_DAA;
where APPROPRIATE_Testing = 1;
Title "Number of appropriately tested infants by infant year of birth ie in each year how many infants born that year were ultimately appropriately tested bt 2014-2021";
TABLES INFANT_YEAR_BIRTH / out=Table10 nocol nopercent norow;
run;

proc print data=Table10; run;

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

DATA TRT_TESTING15; SET DAA15; *RE changed the dataset being set here from testing15 to daa15 so has the daainfo on 8/3;
	EOT_RNA_TEST = 0;
	SVR12_RNA_TEST = 0;
	*IF RNA_TEST_DATE_1 = . THEN DELETE;
	*IF FIRST_DAA_DATE = . THEN DELETE; 
	ARRAY test_date_array {57} RNA_TEST_DATE_1-RNA_TEST_DATE_57;
	ARRAY time_since_array {57} time_since_last_daa1 - time_since_last_daa57;
		do i = 1 to 57;
		if test_date_array{i}>0 and FIRST_DAA_DATE>0 then 
		    time_since_array{i} = test_date_array{i} - FIRST_DAA_DATE;
		else Time_since_array{i}=.; *added this else back in 8/1/23 RE;
	    IF time_since_array{i} > 84   THEN EOT_RNA_TEST = 1; 
        IF time_since_array{i} >= 140 THEN SVR12_RNA_TEST = 1; *removed the else =0 here bc if missing a later rna it'll get set back to zero i think;
		end;
	DROP i;
run;

/*=================================	*/
/*        <=15 Year Old   TABLES    */
/*=================================	*/

/* Table 11 */
proc freq data=DAA15;
title "HCV Care Cascade for children diagnosed with HCV at age <=15 years between 2011-2021, Overall";
tables DISEASE_STATUS_HCV
       DAA_START_INDICATOR
       FIRST_DAA_START_YEAR
        / out=Table11 norow nopercent nocol;
run;

proc print data=Table11; run;

/* Table 12 */
proc freq data=DAA15;
Where FIRST_DAA_START_YEAR < 2020;
title "<=15 HCV Care Cascade, DAA starts pre 2020";
tables DAA_START_INDICATOR
        / out=Table12 norow nopercent nocol;
run;

proc print data=Table12; run;

/* Table 13 */
proc freq data=DAA15;
WHERE DISEASE_STATUS_HCV = 1;
title "<=15 HCV Care Cascade, Among Confirmed";
tables HCV_PRIMARY_DIAG
        RNA_TEST_INDICATOR
       GENO_TEST_INDICATOR
       DAA_START_INDICATOR
       EVENT_YEAR_HCV
       AGE_HCV
        / out=Table13 norow nopercent nocol;
run;

proc print data=Table13; run;

/* Table 14 */
proc freq data=DAA15;
WHERE DISEASE_STATUS_HCV = 1 and 3 < AGE_HCV < 11;
title "HCV Diagnoses made among children 4-10yo between 2011-2021";
tables DISEASE_STATUS_HCV
        / out=Table14 norow nopercent nocol;
run;

proc print data=Table14; run;

/* Table 15 */
proc freq data=DAA15;
WHERE DISEASE_STATUS_HCV = 1 and 10 < AGE_HCV <= 15;
title "HCV Diagnoses made among children 11-15yo between 2011-2021";
tables DISEASE_STATUS_HCV
        / out=Table15 norow nopercent nocol;
run;

proc print data=Table15; run;

/* Table 16 */
proc freq data=TRT_TESTING15;
WHERE DAA_START_INDICATOR = 1;
title "EOT/SVR12 & age at treatment, Among those treated";
tables EOT_RNA_TEST
       SVR12_RNA_TEST
       AGE_DAA_START_group
        / out=Table16 norow nopercent nocol;
format AGE_DAA_START_group pharmagegroupf.;
run;

proc print data=Table16; run;

/* Table 17 */
proc freq data=TRT_TESTING15;
WHERE DISEASE_STATUS_HCV = 1 and DAA_START_INDICATOR = 1;
title "EOT/SVR12 & age at treatment, Among those treated & w confirmed HCV - dup in case age daa start group errors out again to get eot and svr";
tables EOT_RNA_TEST
       SVR12_RNA_TEST
        / out=Table17 norow nopercent nocol;
run;

proc print data=Table17; run;

/* Table 18 */
proc freq data=DAA15;
title "<=15 HCV Care Cascade, by race/ethnicity";
tables DISEASE_STATUS_HCV*final_re
        / out=Table18 norow nopercent nocol;
FORMAT final_re racefmt_all.;
run;

proc print data=Table18; run;

/* Table 19 */
proc freq data=DAA15;
Where DISEASE_STATUS_HCV = 1;
title "<=15 HCV Care Cascade, by race/ethnicity, Among Confirmed";
tables HCV_PRIMARY_DIAG*final_re
GENO_TEST_INDICATOR*final_re
DAA_START_INDICATOR*final_re      
        / out=Table19 norow nopercent nocol;
FORMAT final_re racefmt_comb.;
run;

proc print data=Table19; run;