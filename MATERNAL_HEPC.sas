/*==============================================*/
/* Project: PHD Maternal HEPC Analysis  	    */
/* Author: Ryan O'Dea and Sarah Munroe          */ 
/* Created: 4/27/2023 		                    */
/* Updated: 03/2025 by SJM  	                */
/*==============================================*/

/*	Project Goal:
	Characterize the HCV care cascade in women of reproductive age with OUD and Hepatitis C
    Describe charateristics of the cohort and related Hepatitis C outcomes: linkage to care, loss-to-follow-up, relinkage to care, and DAA treatment initiation
    Calculate rates of Hepatitis C outcomes: linkage to care, loss-to-follow-up, relinkage to care, and DAA treatment initiation

    Part 1: Construct OUD cohort
    Part 2: HCV Care Cascade
    Part 3: Tables1 and 2 - Crude Analysis 
    Part 4: Calculate Rates

	Detailed documentation of all datasets and variables:
	https://www.mass.gov/info-details/public-health-data-warehouse-phd-technical-documentation */

/*===== SUPRESSION CODE =========*/
ods path(prepend) DPH.template(READ) SASUSER.TEMPLAT (READ);
proc format;                                                                                               
   value supp010_ 1-10=' * ';                                                                           
run ;
proc template;
%include "/sas/data/DPH/OPH/PHD/template.sas";
run;
/*==============================*/

/* Overall, the logic behind the known capture is fairly simple: 
search through individual databases and flag if an ICD9, ICD10, 
CPT, NDC, or other specialized code matches our lookup table. 
If a record has one of these codes, it is 'flagged' for OUD. 
The utilized databases are then joined onto the SPINE demographics 
dataset and if the sum of flags is greater than zero, then the 
record is flagged with OUD.  
At current iteration, data being pulled through this method is 
stratified by Year (or Year and Month), Race, Sex, and Age 
(where age groups are defined in the table below). */

/*==============================*/
/*  	GLOBAL VARIABLES   	    */
/*==============================*/
%LET year = (2014:2022);
%LET MOUD_leniency = 30;
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

/*===========AGE================*/
PROC FORMAT;
	VALUE age_grps_five
		low-14 = '999'
		15-18 = '1'
		19-25 = '2'
		26-30 = '3'
		31-35 = '4'
		36-45 = '5'
		46-high = '999';

/* ======= HCV TESTING CPT CODES ========  */
%LET AB_CPT = ('G0472','86803','86804','80074');
%LET RNA_CPT = ('87520','87521','87522');
%LET GENO_CPT = ('87902','3266F');

/* === HCV DIAGNOSIS CODES ====== */
%LET HCV_ICD = ('7051',  '7054','707',
		'7041',  '7044','7071',
		'B1710','B182','B1920',
		'B1711','B1921');


/* HCV Direct Action Antiviral Codes */
%LET DAA_CODES = ('00003021301','00003021501','61958220101','61958180101','61958180301',
                  '61958180401','61958180501','61958150101','61958150401','61958150501',
                  '72626260101','00074262501','00074262528','00074262556','00074262580',
                  '00074262584','00074260028','72626270101','00074308228','00074006301',
                  '00074006328','00074309301','00074309328','61958240101','61958220101',
                  '61958220301','61958220401','61958220501','00006307402','51167010001',
                  '51167010003','59676022507','59676022528','00085031402');			

/*========ICD CODES=============*/
%LET ICD = ('30400','30401','30402','30403',
	'30470','30471','30472','30473',
    '30550','30551','30552','30553', /* ICD9 */
    'F1110','F1111','F11120','F11121', 
	'F11122','F11129','F1113','F1114', 
    'F11150','F11151','F11159','F11181', 
    'F11182','F11188','F1119','F1120', 
    'F1121','F11220','F11221','F11222', 
    'F11229','F1123','F1124','F11250',
    'F11251','F11259','F11281','F11282',
    'F11288','F1129','F1193','F1199',  /* ICD10 */
	'9701','96500','96501','96502',
 	'96509','E8500','E8501','E8502',
  	'T400X1A','T400X2A','T400X3A','T400X4A',
    'T400X1D','T400X2D','T400X3D','T400X4D',
    'T401X1A','T401X2A','T401X3A','T401X4A',
    'T401X1D','T401X2D','T401X3D','T401X4D',
    'T402X1A','T402X2A','T402X3A','T402X4A',
    'T402X1D','T402X2D','T402X3D','T402X4D', 
	'T403X1A','T403X2A','T403X3A','T403X4A', 
	'T403X1D','T403X2D','T403X3D','T403X4D', 
	'T404X1A','T404X2A','T404X3A','T404X4A', 
	'T404X1D','T404X2D','T404X3D','T404X4D',
	'T40601A','T40601D','T40602A','T40602D', 
	'T40603A','T40603D','T40604A','T40604D', 
	'T40691A','T40692A','T40693A','T40694A', 
	'T40691D','T40692D','T40693D','T40694D',
    'T40411A','T40411D','T40412A','T40412D', 
    'T40413A','T40413D','T40414A','T40414D', 
    'T40421A','T40421D','T40422A','T40422D', 
    'T40423A','T40423D','T40424A','T40424D' /* Overdose Codes */);
           
%LET PROC = ('G2067','G2068','G2069','G2070', 
	'G2071','G2072','G2073','G2074', 
	'G2075', /* MAT Opioid */
	'G2076','G2077','G2078','G2079', 
	'G2080', /*Opioid Trt */
 	'H0020','HZ81ZZZ','HZ84ZZZ','HZ91ZZZ','HZ94ZZZ',
    'J0570','J0571','J0572','J0573', 
 	'J0574','J0575','J0592', 'J2315','Q9991','Q9992''S0109'/* Naloxone*/);

/* Take NDC codes where buprenorphine has been identified,
insert them into BUP_NDC as a macro variable */

%LET bsas_drugs = (5,6,7,21,22,23,24,26);

proc sql;
create table bupndcf as
select distinct ndc
from PHDPMP.PMP
where BUP_CAT_PMP = 1;
quit;

proc sql noprint;
select quote(trim(ndc),"'") into :BUP_NDC separated by ','
from bupndcf;
quit;
            
/*============================ */
/*  Part 1: Construct OUD cohort */
/*============================ */

/*====================*/
/* 1. Demographics    */
/*====================*/
/* Using data from DEMO, take the cartesian coordinate of years
(as defined above) and months 1:12 to construct a shell table */

PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX, YOB, SELF_FUNDED
	FROM PHDSPINE.DEMO
	WHERE FINAL_SEX = 2 & SELF_FUNDED = 0;
QUIT;

/*====================*/
/* 2. APCD            */
/*====================*/
/* The APCD consists of the Medical and Pharmacy Claims datasets and, 
along with Casemix, are the datasets where we primarily search along 
our ICD code list. We construct a variable named `OUD_APCD` within our 
APCD Medical dataset using `MED_ICD1-25`, `MED_PROC1-7`, `MED_ECODE`, `MED_ADM_DIAGNOSIS`
and `MED_DIS_DIAGNOSIS`. We preform a rowwise search and add one to a 
temporary `count` variable if they appear within our ICD code list.
At the end, if the `count` variable is strictly greater than one 
then our `OUD_APCD` flag is set to 1.

The APCD medical dataset does not hold variables for searching 
for NDC Codes, so we add in the APCD pharmacy dataset with 
`PHARM_NDC` to search for applicable NDC codes. 
If `PHARM_NDC` or `PHARM_ICD` is within our OUD Codes lists above,
then our `OUD_PHARM` flag is set to 1.*/

DATA apcd (KEEP= ID oud_apcd year_apcd);
	SET PHDAPCD.MOUD_MEDICAL (KEEP= ID MED_ECODE MED_ADM_DIAGNOSIS MED_AGE
								MED_ICD_PROC1-MED_ICD_PROC7
								MED_ICD1-MED_ICD25
								MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH
								MED_DIS_DIAGNOSIS
                                MED_PROC_CODE
                        WHERE= (MED_FROM_DATE_YEAR IN &year));
    cnt_oud_apcd = 0;
    oud_apcd = 0;
    ARRAY vars1 {*} ID MED_ECODE MED_ADM_DIAGNOSIS
					MED_ICD_PROC1-MED_ICD_PROC7
					MED_ICD1-MED_ICD25
					MED_DIS_DIAGNOSIS
                    MED_PROC_CODE;
		DO i = 1 TO dim(vars1);
		IF vars1[i] in &ICD THEN cnt_oud_apcd = cnt_oud_apcd+1;
		END;
		DROP= i;
	IF cnt_oud_apcd > 0 THEN oud_apcd = 1;
	IF oud_apcd = 0 THEN DELETE;

	year_apcd = MED_FROM_DATE_YEAR;
RUN;

DATA pharm (KEEP= oud_pharm ID year_pharm);
    SET PHDAPCD.MOUD_PHARM(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH PHARM_AGE
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;
    IF oud_pharm = 0 THEN DELETE;

IF oud_pharm > 0 THEN year_pharm = PHARM_FILL_DATE_YEAR;

RUN;

/*====================*/
/* 3. CASEMIX         */
/*====================*/
/* ### Emergency Department
Casemix.ED (Emergency Department) has three smaller internally 
linked tables: ED, ED_DIAG, and ED_PROC; all linked together by 
their internal `ED_ID`, which is only found in the ED tables 
and should not be linked back to the PHD ID.
1. ED: Within the ED Dataset, we are interested in if `ED_DIAG1` 
   or `ED_PRINCIPLE_ECODE` are within our OUD Code list. 
   A temporary variable `OUD_ED_RAW` is created as a flag.
2. ED_DIAG: Within the ED_DIAG Dataset, we construct our flag, 
   `OUD_ED_DIAG` from the variable `ED_DIAG`
3. ED_PROC: Within the ED_PROC Dataset, we construct our flag, 
   `OUD_ED_PROC` from the variable `ED_PROC`
4. Datasets ED, ED_DIAG, and ED_PROC and joined along 
   their internal `ED_ID`. If the sum of created flags is 
   strictly greater than zero, then the overall `OUD_CM_ED` 
   flag is set to 1.

### Hospital Inpatient Discharge
Casemix.HD (Hospital Inpatient Discharge) follows the same pattern
as ED and has three smaller internally linked tables: HD, HD_DIAG, 
and HD_PROC; all linked together by their internal `HD_ID`, 
which is only found in the HD tables and should not be linked 
back to the PHD ID.
1. HD: Within the HD Dataset, we are intersted in if `HD_PROC1` or 
   `HD_DIAG1` are within our OUD Code list. A temporary variable 
   `OUD_HD_RAW` is created as a flag.
2. HD_DIAG: Within the HD_DIAG Dataset, we construct our flag, 
   `OUD_HD_DIAG` from the variable `HD_DIAG`
3. HD_PROC: Within the HD_PROC Dataset, we construct our flag, 
   `OUD_HD_PROC` from the variable `HD_PROC`
4. Datasets HD, HD_DIAG, and HD_PROC and joined along their 
   internal `HD_ID`. If the sum of created flags is strictly 
   greater than zero, then the overall `OUD_CM_HD` flag is set to 1.

### Outpatient Observations
Casemix.OO (Outpatient Observations) breaks from the previous 
pattern of HD and ED by only have one attributing table. 
Within this table, we construct our flag `OUD_CM_OO` by searching 
through `OO_DIAG1-16`, `OO_PROC1-4`, `OO_CPT1-10`, and 
`OO_PRINCIPALEXTERNAL_CAUSECODE`. We preform a rowwise search and 
add one to a temporary `count` variable if they appear within our 
code lists. At the end, if the `count` variable is strictly greater 
than one then our `OUD_CM_OO` flag is set to 1. */

/* ED */

DATA casemix_ed (KEEP= ID oud_cm_ed year_cm ED_ID);
	SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
				  WHERE= (ED_ADMIT_YEAR IN &year));
	IF ED_DIAG1 in &ICD OR 
        ED_PRINCIPLE_ECODE IN &ICD THEN oud_cm_ed = 1;
	ELSE oud_cm_ed = 0;

	IF oud_cm_ed > 0 THEN do;
	year_cm = ED_ADMIT_YEAR;
end;
RUN;

/* ED_DIAG */

DATA casemix_ed_diag (KEEP= oud_cm_ed_diag ED_ID);
	SET PHDCM.ED_DIAG (KEEP= ED_ID ED_DIAG);
	IF ED_DIAG in &ICD THEN oud_cm_ed_diag = 1;
	ELSE oud_cm_ed_diag = 0;
RUN;

PROC SQL;
    CREATE TABLE casemix_ed_diag AS
    SELECT a.ID, a.ED_ID, a.ED_ADMIT_YEAR, b.oud_cm_ed_diag
    FROM PHDCM.ED AS a
    RIGHT JOIN casemix_ed_diag AS b
    ON a.ED_ID = b.ED_ID
    WHERE a.ED_ADMIT_YEAR IN &year;
QUIT;

/* ED_PROC */

DATA casemix_ed_proc (KEEP= oud_cm_ed_proc ED_ID);
	SET PHDCM.ED_PROC (KEEP= ED_ID ED_PROC);
	IF ED_PROC in &PROC THEN oud_cm_ed_proc = 1;
	ELSE oud_cm_ed_proc = 0;
RUN;

/* CASEMIX ED MERGE */

PROC SQL;
    CREATE TABLE pharm AS
    SELECT DISTINCT *
    FROM pharm;
    
    CREATE TABLE casemix_ed_proc AS
	SELECT DISTINCT *
	FROM casemix_ed_proc;

	CREATE TABLE apcd AS
	SELECT DISTINCT *
	FROM apcd;

	CREATE TABLE casemix_ed AS
	SELECT DISTINCT *
	FROM casemix_ed;

	CREATE TABLE casemix_ed_diag AS
	SELECT DISTINCT *
	FROM casemix_ed_diag;

	CREATE TABLE casemix AS 
	SELECT *
	FROM casemix_ed
	LEFT JOIN casemix_ed_diag ON casemix_ed.ED_ID = casemix_ed_diag.ED_ID
	LEFT JOIN casemix_ed_proc ON casemix_ed_diag.ED_ID = casemix_ed_proc.ED_ID;
QUIT;

DATA casemix (KEEP= ID oud_ed year_cm);
	SET casemix;
	IF SUM(oud_cm_ed_proc, oud_cm_ed_diag, oud_cm_ed) > 0 THEN oud_ed = 1;
	ELSE oud_ed = 0;
	
	IF oud_ed = 0 THEN DELETE;
RUN;

/*====================*/
/* 4. HD              */
/*====================*/

DATA hd (KEEP= HD_ID ID oud_hd_raw year_hd);
	SET PHDCM.HD (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH HD_ECODE
					WHERE= (HD_ADMIT_YEAR IN &year));
	IF HD_DIAG1 in &ICD OR
     HD_PROC1 in &PROC OR
     HD_ECODE IN &ICD THEN oud_hd_raw = 1;
	ELSE oud_hd_raw = 0;

	IF oud_hd_raw > 0 THEN do;
    year_hd = HD_ADMIT_YEAR;
end;
RUN;

/* HD DIAG DATA */

DATA hd_diag (KEEP= HD_ID oud_hd_diag);
	SET PHDCM.HD_DIAG (KEEP= HD_ID HD_DIAG);
	IF HD_DIAG in &ICD THEN oud_hd_diag = 1;
	ELSE oud_hd_diag = 0;
RUN;

PROC SQL;
    CREATE TABLE hd_diag AS
    SELECT a.ID, a.HD_ID, a.HD_ADMIT_YEAR, b.oud_hd_diag
    FROM PHDCM.HD AS a
    RIGHT JOIN hd_diag AS b
    ON a.HD_ID = b.HD_ID
    WHERE a.HD_ADMIT_YEAR IN &year;
QUIT;

/* HD PROC DATA */

DATA hd_proc(KEEP= HD_ID oud_hd_proc);
	SET PHDCM.HD_PROC (KEEP = HD_ID HD_PROC);
	IF HD_PROC IN &PROC THEN oud_hd_proc = 1;
	ELSE oud_hd_proc = 0;
RUN;

/* HD MERGE */

PROC SQL;
    CREATE TABLE pharm AS
    SELECT DISTINCT * 
    FROM pharm;

	CREATE TABLE hd_diag AS
	SELECT DISTINCT *
	FROM hd_diag;

	CREATE TABLE casemix AS
	SELECT DISTINCT *
	FROM casemix;

	CREATE TABLE hd AS
	SELECT DISTINCT *
	FROM hd;

    CREATE TABLE hd_proc AS
	SELECT DISTINCT * 
    FROM hd_proc;

	CREATE TABLE hd AS 
	SELECT *
	FROM hd
	LEFT JOIN hd_diag ON hd.HD_ID = hd_diag.HD_ID
	LEFT JOIN hd_proc ON hd.HD_ID = hd_proc.HD_ID;
QUIT;

DATA hd (KEEP= ID oud_hd year_hd);
	SET hd;
	IF SUM(oud_hd_diag, oud_hd_raw, oud_hd_proc) > 0 THEN oud_hd = 1;
	ELSE oud_hd = 0;
	
	IF oud_hd = 0 THEN DELETE;
RUN;

/*====================*/
/* 5. OO              */
/*====================*/

DATA oo (KEEP= ID oud_oo year_oo);
    SET PHDCM.OO (KEEP= ID OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4
                        OO_ADMIT_YEAR OO_ADMIT_MONTH OO_AGE
                        OO_CPT1-OO_CPT10
                        OO_PRINCIPALEXTERNAL_CAUSECODE
                    WHERE= (OO_ADMIT_YEAR IN &year));
	cnt_oud_oo = 0;
    
    ARRAY vars2 {*} OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4 OO_CPT1-OO_CPT10 OO_PRINCIPALEXTERNAL_CAUSECODE;
    
    DO k = 1 TO dim(vars2);
        IF SUBSTR(VNAME(vars2[k]), 1) IN ('OO_PROC', 'OO_CPT') THEN DO;
            IF vars2[k] IN &PROC THEN 
                cnt_oud_oo = cnt_oud_oo + 1;
   END;
            ELSE IF vars2[k] IN &ICD THEN 
                cnt_oud_oo = cnt_oud_oo + 1;
    END;

    DROP k;

    IF cnt_oud_oo > 0 THEN oud_oo = 1; 
    ELSE oud_oo = 0;

    IF oud_oo = 0 THEN DELETE;

    year_oo = OO_ADMIT_YEAR;
RUN;

/*====================*/
/* 6. CM OO MERGE     */
/*====================*/

PROC SQL;
    CREATE TABLE casemix AS
    SELECT *
    FROM casemix
    FULL JOIN hd ON casemix.ID = hd.ID
    FULL JOIN oo ON hd.ID = oo.ID;
QUIT;

PROC STDIZE DATA = casemix OUT = casemix reponly missing = 9999; RUN;

DATA casemix (KEEP = ID oud_cm year_cm);
    SET casemix;

    IF oud_ed = 9999 THEN oud_ed = 0;
    IF oud_hd = 9999 THEN oud_hd = 0;
    IF oud_oo = 9999 THEN oud_oo = 0;

    IF sum(oud_ed, oud_hd, oud_oo) > 0 THEN oud_cm = 1;
    ELSE oud_cm = 0;
    IF oud_cm = 0 THEN DELETE;

   year_cm = min(year_oo, year_hd, year_cm);
RUN;

/*====================*/
/* 7. BSAS            */
/*====================*/
/* Like Matris, the BSAS dataset involves some PHD level encoding. 
We tag a record with our flag, `OUD_BSAS`, if 
`CLT_ENR_PRIMARY_DRUG`, `CLT_ENR_SECONDARY_DRUG`, 
`CLT_ENR_TERTIARY_DRUG` are in the encoded list: (5,6,7,21,22,23,24,26) 
or if `PHD_PRV_SERV_CAT = 7` (Opioid Treatment).

Descriptions of the BSAS drugs respective to 
PHD level documentation
1. 5: Heroin
2. 6: Non-Rx Methadone
3. 7: Other Opiates
4. 21: Oxycodone
5. 22: Non-Rx Suboxone
6. 23: Rx Opiates
7. 24: Non-Rx Opiates
8. 26: Fentanyl */

DATA bsas (KEEP= ID oud_bsas year_bsas);
    SET PHDBSAS.BSAS (KEEP= ID CLT_ENR_OVERDOSES_LIFE
                             CLT_ENR_PRIMARY_DRUG
                             CLT_ENR_SECONDARY_DRUG
                             CLT_ENR_TERTIARY_DRUG
                             PDM_PRV_SERV_CAT
                             ENR_YEAR_BSAS 
                             ENR_MONTH_BSAS
                             AGE_BSAS
                      WHERE= (ENR_YEAR_BSAS IN &year));
    IF (CLT_ENR_OVERDOSES_LIFE > 0 AND CLT_ENR_OVERDOSES_LIFE ^= 999)
        OR CLT_ENR_PRIMARY_DRUG in &bsas_drugs
        OR CLT_ENR_SECONDARY_DRUG in &bsas_drugs
        OR CLT_ENR_TERTIARY_DRUG in &bsas_drugs
        OR PDM_PRV_SERV_CAT = 7 THEN oud_bsas = 1;
    ELSE oud_bsas = 0;
    IF oud_bsas = 0 THEN DELETE;

    year_bsas = ENR_YEAR_BSAS;

RUN;

/*====================*/
/* 8. MATRIS          */
/*====================*/
/* The MATRIS Dataset depends on PHD level encoding of variables 
`OPIOID_ORI_MATRIS` and `OPIOID_ORISUBCAT_MATRIS` to 
construct our flag variable, `OUD_MATRIS`. */

DATA matris (KEEP= ID oud_matris year_matris);
SET PHDEMS.MATRIS (KEEP= ID OPIOID_ORI_MATRIS
                          OPIOID_ORISUBCAT_MATRIS
                          inc_year_matris
                          inc_month_matris
						  AGE_MATRIS
						  AGE_UNITS_MATRIS
                    WHERE= (inc_year_matris IN &year));
    IF OPIOID_ORI_MATRIS = 1 
        OR OPIOID_ORISUBCAT_MATRIS in (1:5) THEN oud_matris = 1;
    ELSE oud_matris = 0;
    IF oud_matris = 0 THEN DELETE;

    year_matris = inc_year_matris;

RUN;

/*====================*/
/* 9. DEATH           */
/*====================*/
/* The Death dataset holds the official cause and manner of 
death assigned by physicians and medical examiners. For our 
purposes, we are only interested in the variable `OPIOID_DEATH` 
which is based on 'ICD10 codes or literal search' from other 
PHD sources.*/

DATA death (KEEP= ID oud_death year_death);
    SET PHDDEATH.DEATH (KEEP= ID OPIOID_DEATH YEAR_DEATH AGE_DEATH
                        WHERE= (YEAR_DEATH IN &year));
    IF OPIOID_DEATH = 1 THEN oud_death = 1;
    ELSE oud_death = 0;
    IF oud_death = 0 THEN DELETE;

    year_death = YEAR_DEATH;

RUN;

/*====================*/
/* 10. PMP            */
/*====================*/
/* Within the PMP dataset, we only use the `BUPRENORPHINE_PMP` 
to define the flag `OUD_PMP` - conditioned on BUP_CAT_PMP = 1. */

DATA pmp (KEEP= ID oud_pmp year_pmp);
    SET PHDPMP.PMP (KEEP= ID BUPRENORPHINE_PMP date_filled_year AGE_PMP date_filled_month BUP_CAT_PMP
                    WHERE= (date_filled_year IN &year));
    IF BUPRENORPHINE_PMP = 1 AND 
        BUP_CAT_PMP = 1 THEN oud_pmp = 1;
    ELSE oud_pmp = 0;
    IF oud_pmp = 0 THEN DELETE;

    year_pmp = date_filled_year;

RUN;

/*===========================*/
/* 11.  MAIN MERGE           */
/*===========================*/
/* As a final series of steps:
1. APCD-Pharm, APCD-Medical, Casemix, Death, PMP, Matris, 
   BSAS are joined together on the cartesian coordinate of Months 
   (1:12), Year (2015:2022), and SPINE (Race, Sex, ID)
2. The sum of the fabricated flags is taken. If the sum is strictly
   greater than zero, then the master flag is set to 1. 
   Zeros are deleted
4. We select distinct ID, Age Bins, Race, Year, and Month and 
   output the count of those detected with OUD
5. Any count that is between 1 and 10 are suppressed and set to -1,
   any zeros are true zeros */

PROC SQL;
    CREATE TABLE oo AS
    SELECT DISTINCT *
    FROM oo;

    CREATE TABLE bsas AS
    SELECT DISTINCT *
    FROM bsas;

    CREATE TABLE matris AS
    SELECT DISTINCT *
    FROM matris;

    CREATE TABLE death AS
    SELECT DISTINCT *
    FROM death;

    CREATE TABLE pmp AS
    SELECT DISTINCT *
    FROM pmp;

PROC SQL;
    CREATE TABLE oud AS
    SELECT * FROM demographics
    LEFT JOIN apcd ON apcd.ID = demographics.ID
    LEFT JOIN casemix ON casemix.ID = demographics.ID
    LEFT JOIN death ON death.ID = demographics.ID
    LEFT JOIN bsas ON bsas.ID = demographics.ID
    LEFT JOIN matris ON matris.ID = demographics.ID
    LEFT JOIN pmp ON pmp.ID = demographics.ID
    LEFT JOIN pharm ON pharm.ID = demographics.ID;

    CREATE TABLE oud AS
    SELECT DISTINCT * 
    FROM oud;
QUIT;

PROC STDIZE DATA = oud OUT = oud reponly missing = 9999; RUN;

DATA oud;
    SET oud;

    ARRAY oud_flags {*} oud_apcd oud_cm
                        oud_death oud_matris
                        oud_pmp oud_bsas
                        oud_pharm;
                        
    DO i = 1 TO dim(oud_flags);
        IF oud_flags[i] = 9999 THEN oud_flags[i] = 0;
    END;

    oud_cnt = sum(oud_apcd, oud_cm, oud_death, oud_matris, oud_pmp, oud_bsas, oud_pharm);
    IF oud_cnt > 0 THEN oud_master = 1;
    ELSE oud_master = 0;
    IF oud_master = 0 THEN DELETE;

	oud_year = min(year_apcd, year_cm, year_matris, year_bsas, year_pmp);
    IF oud_year = 9999 THEN oud_age = 999;
    ELSE IF oud_year ne 9999 THEN oud_age = oud_year - YOB;
RUN;

PROC SORT data=oud;
    by ID oud_age;
RUN;

data oud;
    set oud;
    by ID;
    if first.ID;
run;	

data oud;
	set oud;
	age_grp_five  = put(oud_age, age_grps_five.);
    IF age_grp_five  = 999 THEN DELETE;
run;

PROC SQL;
    CREATE TABLE oud_distinct AS
    SELECT DISTINCT ID, YOB, oud_age, age_grp_five as agegrp, FINAL_RE FROM oud;
QUIT;

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM oud_distinct;
QUIT;

%put Number of unique IDs in oud_distinct table: &num_unique_ids;

/*============================ */
/* 12. ADD PREGANANCY          */
/*============================ */

DATA all_births (keep = ID BIRTH_INDICATOR YEAR_BIRTH AGE_BIRTH);
   SET PHDBIRTH.BIRTH_MOM (KEEP = ID YEAR_BIRTH AGE_BIRTH
                            WHERE= (YEAR_BIRTH IN &year));
   BIRTH_INDICATOR = 1;
RUN;

data fetal_deaths_renamed;
    set PHDFETAL.FETALDEATH;
    rename FETAL_DEATH_YEAR = YEAR_BIRTH
    	   MOTHER_AGE_FD = AGE_BIRTH;
run;

DATA fetal_deaths_renamed (keep = ID BIRTH_INDICATOR YEAR_BIRTH AGE_BIRTH);
   SET fetal_deaths_renamed (KEEP = ID YEAR_BIRTH AGE_BIRTH
                            WHERE= (YEAR_BIRTH IN &year));
   BIRTH_INDICATOR = 1;
RUN;

DATA all_births;
   SET all_births fetal_deaths_renamed;
RUN;

proc SQL;
CREATE TABLE births AS
SELECT  ID,
		SUM(BIRTH_INDICATOR) AS TOTAL_BIRTHS,
		min(YEAR_BIRTH) as FIRST_BIRTH_YEAR, 
		max(BIRTH_INDICATOR) as BIRTH_INDICATOR FROM all_births
GROUP BY ID;
run;

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM births;
QUIT;

%put Number of unique IDs in births table: &num_unique_ids;

PROC SQL;
    CREATE TABLE oud_preg AS
    SELECT * FROM oud_distinct
    LEFT JOIN births ON oud_distinct.ID = births.ID;
QUIT;

DATA oud_preg;
SET oud_preg;
	IF BIRTH_INDICATOR = . THEN BIRTH_INDICATOR = 0;
run;

proc sort data=all_births;
    by ID AGE_BIRTH;
run;

data birthsmoms_first;
    set all_births;
    by ID AGE_BIRTH;
    if first.ID;
run;

proc sql;
    create table oud_preg as
    select oud_preg.*,
           birthsmoms_first.AGE_BIRTH
    from oud_preg
    left join birthsmoms_first
    on oud_preg.ID = birthsmoms_first.ID;
quit;

/* ========================================================== */
/* 13. Extract AB/RNA/GENOTYPE Testing Data                   */
/* ========================================================== */
/* Extract antibody/rna/genotype testing records (CPT codes) from the PHDAPCD.MOUD_MEDICAL dataset.
Then, remove duplicate testing records based on unique combinations of ID and testing date and sort by ID and testing date in ascending order. 
Transpose the testing dates for each individual into wide format to create multiple columns for testing dates. 
Extract the year from the testing records for each ID and creates a new dataset that includes distinct IDs, testing years, and age at testing.
Select the earliest testing year for each ID and output the frequency of tests occurring in infants under the age of 4. */

/* AB */

DATA ab;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR
					 WHERE = (MED_PROC_CODE IN  &AB_CPT));
run;

proc sql;
create table AB1 as
select distinct ID, MED_FROM_DATE, *
from AB;
quit;

PROC SORT data=ab1;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=ab1 out=ab_wide (KEEP = ID AB_TEST_DATE:) PREFIX=AB_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

PROC SQL;
create table AB_YEARS as
SELECT DISTINCT ID, MED_FROM_DATE_YEAR as AB_TEST_YEAR
FROM AB1;
quit;

PROC SQL;
create table AB_YEARS_COHORT as
SELECT *
FROM OUD_DISTINCT
LEFT JOIN AB_YEARS on OUD_DISTINCT.ID = AB_YEARS.ID;
quit;

/* RNA */

DATA rna;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE
 					 WHERE = (MED_PROC_CODE IN  &RNA_CPT)); 
run;

PROC SORT data=rna;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=rna out=rna_wide (KEEP = ID RNA_TEST_DATE:) PREFIX=RNA_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

/* GENOTYPE */

DATA geno;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE
 					 WHERE = (MED_PROC_CODE IN  &GENO_CPT)); 
run;

PROC SORT data=geno;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=geno out=geno_wide (KEEP = ID GENO_TEST_DATE:) PREFIX=GENO_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

PROC FREQ data = AB;
title "AB CPT CODES";
table MED_PROC_CODE;
run;

PROC FREQ data = RNA;
title "RNA CPT CODES";
table MED_PROC_CODE;
run;

PROC FREQ data = geno;
title "GENOTYPE CPT CODES";
table MED_PROC_CODE;
run;
title;

/* ========================================================== */
/* 14. Join All Testing Data with OUD Cohort and Create HCV Testing Indicators */
/* ========================================================== */
/* This step joins antibody, RNA, and genotype testing data to the main OUD dataset based on the ID and
creates indicators for whether ID had antibody, RNA, and any HCV testing. */

PROC SQL;
    CREATE TABLE OUD_HCV AS
    SELECT * FROM oud_preg 
    LEFT JOIN ab_wide ON ab_wide.ID = oud_preg.ID
    LEFT JOIN rna_wide ON rna_wide.ID = oud_preg.ID
    LEFT JOIN geno_wide ON geno_wide.ID = oud_preg.ID;
QUIT;

DATA OUD_HCV;
	SET OUD_HCV;
	AB_TEST_INDICATOR = 0;
	RNA_TEST_INDICATOR = 0;
    GENO_TEST_INDICATOR = 0;
	IF AB_TEST_DATE_1 = . THEN AB_TEST_INDICATOR = 0; ELSE AB_TEST_INDICATOR = 1;
	IF RNA_TEST_DATE_1 = . THEN RNA_TEST_INDICATOR = 0; ELSE RNA_TEST_INDICATOR = 1;
	IF GENO_TEST_DATE_1 = . THEN GENO_TEST_INDICATOR = 0; ELSE GENO_TEST_INDICATOR = 1;
	run;
	
DATA OUD_HCV;
	SET OUD_HCV;
		ANY_HCV_TESTING_INDICATOR = 0;
		IF AB_TEST_INDICATOR = 1 OR RNA_TEST_INDICATOR = 1 THEN ANY_HCV_TESTING_INDICATOR = 1;
	run;

/* ========================================================== */
/* 15. Extract HCV Status from MAVEN Database                 */
/* ========================================================== */
/* This section retrieves the HCV diagnosis status for each ID from the MAVEN database,
   calculates the age at diagnosis, and creates indicators for HCV seropositivity and confirmed HCV. */

PROC SORT DATA=PHDHEPC.HCV;
    BY ID EVENT_DATE_HCV;
RUN;

DATA HCV_STATUS;
    SET PHDHEPC.HCV;
    BY ID EVENT_DATE_HCV;
	IF FIRST.ID AND EVENT_YEAR_HCV >= 2014 THEN DO;
	    HCV_SEROPOSITIVE_INDICATOR = 1;
	    CONFIRMED_HCV_INDICATOR = (DISEASE_STATUS_HCV = 1);
	    OUTPUT;
	END;
KEEP ID AGE_HCV EVENT_MONTH_HCV EVENT_YEAR_HCV EVENT_DATE_HCV HCV_SEROPOSITIVE_INDICATOR CONFIRMED_HCV_INDICATOR RES_CODE_HCV;
RUN;

PROC SQL;
    CREATE TABLE IDU_STATUS AS 
    SELECT ID,
        CASE 
            WHEN SUM(EVER_IDU_HCV = 1) > 0 THEN 1 
            WHEN SUM(EVER_IDU_HCV = 0) > 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 0 
            WHEN SUM(EVER_IDU_HCV = 9) > 0 AND SUM(EVER_IDU_HCV = 0) <= 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 9 
            ELSE 9 
        END AS EVER_IDU_HCV_MAT
    FROM PHDHEPC.HCV
    WHERE EVENT_YEAR_HCV >= 2014
    GROUP BY ID;
QUIT;

PROC SQL;
    CREATE TABLE HCV_STATUS AS 
    SELECT A.*, B.EVER_IDU_HCV_MAT
    FROM HCV_STATUS A
    LEFT JOIN IDU_STATUS B ON A.ID = B.ID;
QUIT;

PROC SQL;
    CREATE TABLE OUD_HCV_STATUS AS
    SELECT * FROM OUD_HCV 
    LEFT JOIN HCV_STATUS ON HCV_STATUS.ID = OUD_HCV.ID;
QUIT;

/* ========================================================== */
/* 16. Linkage to HCV Care                                    */
/* ========================================================== */
/* This section retrieves medical records related to HCV care from the MOUD_MEDICAL dataset,
   filters based on relevant ICD codes, and creates a dataset for infants linked to HCV care. */

DATA HCV_LINKED_SAS;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_FROM_DATE_MONTH MED_FROM_DATE_YEAR MED_ADM_TYPE MED_ICD1
 					 WHERE = (MED_ICD1 IN &HCV_ICD)); 
RUN;

PROC SORT DATA=HCV_LINKED_SAS;
    BY ID MED_FROM_DATE;
RUN;

DATA HCV_LINKED;
    SET HCV_LINKED_SAS;
    BY ID MED_FROM_DATE;
    IF FIRST.ID THEN DO;
        HCV_PRIMARY_DIAG = 1;
        OUTPUT;
    END;
KEEP ID MED_FROM_DATE_MONTH MED_FROM_DATE_YEAR HCV_PRIMARY_DIAG;
RUN;

PROC SQL;
    CREATE TABLE OUD_HCV_LINKED AS
    SELECT * FROM OUD_HCV_STATUS 
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = OUD_HCV_STATUS.ID;
QUIT;
  
DATA OUD_HCV_LINKED; SET OUD_HCV_LINKED;
IF HCV_PRIMARY_DIAG = . THEN HCV_PRIMARY_DIAG = 0;
IF HCV_SEROPOSITIVE_INDICATOR = . THEN HCV_SEROPOSITIVE_INDICATOR = 0;
run;

/* ========================================================== */
/* 17. DAA (Direct-Acting Antiviral) Treatment Starts         */
/* ========================================================== */
/* This section identifies IDs who started DAA treatment, retains the first DAA start, calculates the age at DAA start,
   and creates indicators for DAA initiation. */

DATA DAA; SET PHDAPCD.MOUD_PHARM (KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_MONTH PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
 								WHERE = (PHARM_NDC IN &DAA_CODES)); 
RUN;

PROC SORT DATA=DAA;
    BY ID PHARM_FILL_DATE;
RUN;

DATA DAA_STARTS;
    SET DAA;
    BY ID PHARM_FILL_DATE;
    IF FIRST.ID THEN DO;
        DAA_START_INDICATOR = 1;
        OUTPUT;
    END;
KEEP ID PHARM_AGE PHARM_FILL_DATE PHARM_FILL_DATE_MONTH PHARM_FILL_DATE_YEAR DAA_START_INDICATOR;
RUN;


PROC SQL;
    CREATE TABLE OUD_HCV_DAA AS
    SELECT * FROM OUD_HCV_LINKED 
    LEFT JOIN DAA_STARTS ON DAA_STARTS.ID = OUD_HCV_LINKED.ID;
QUIT;

DATA OUD_HCV_DAA; SET OUD_HCV_DAA;
IF DAA_START_INDICATOR = . THEN DAA_START_INDICATOR = 0;
run;

DATA OUD_HCV_DAA;
  SET OUD_HCV_DAA;
  IF agegrp ne ' ' THEN
    num_agegrp = INPUT(agegrp, best12.);
  DROP agegrp;
RUN;

DATA TESTING; 
SET OUD_HCV_DAA;
	EOT_RNA_TEST = 0;
	SVR12_RNA_TEST = 0;
	IF RNA_TEST_DATE_1 = .  THEN DELETE;
	IF PHARM_FILL_DATE = .  THEN DELETE;

    array test_date_array (*) RNA_TEST_DATE_:;
    num_tests = dim(test_date_array);

    do i = 1 to num_tests;
        if test_date_array{i} > 0 and PHARM_FILL_DATE > 0 then do;
            time_since = test_date_array{i} - PHARM_FILL_DATE;

            if time_since > 84 then EOT_RNA_TEST = 1;
            if time_since >= 140 then SVR12_RNA_TEST = 1;
        end;
    end;

    DROP i time_since;
RUN;

/* ======================================= */
/* 18. Identifying HCV and OUD Case Counts  */
/* ======================================= */
/* This section calculates and summarizes the total number of HCV cases for women of reproductive age,
   the number of HCV cases with co-occurring OUD, the total number of OUD cases, and the number of OUD cases
   without an HCV diagnosis. It also calculates the percentage of HCV cases not captured by the OUD definition 
   and the percentage of OUD cases without an HCV diagnosis. */

proc sql;
    create table HCV_IDS as
    select distinct ID
    from PHDHEPC.HCV
    where DISEASE_STATUS_HCV in (1, 2)
      and EVENT_YEAR_HCV >= 2014;
quit;

title "Total N HCV Case Reports for Women of Reproductive Age";
proc sql noprint;
    select count(distinct ID) as Total_HCV_Cases
    from PHDHEPC.HCV
    where DISEASE_STATUS_HCV in (1, 2)
      and AGE_HCV between 15 and 45
      and SEX_HCV = 2
      and EVENT_YEAR_HCV >= 2014;
quit;

title "Total N HCV Case Reports for Women of Reproductive Age with OUD";
proc sql noprint;
    select count(distinct a.ID) as HCV_in_OUD
    from OUD_HCV_DAA as a
    inner join HCV_IDS as b
    on a.ID = b.ID;
quit;

title "Total N OUD Cases for Women of Reproductive Age";
proc sql noprint;
    select count(distinct ID) as Total_OUD_Cases
    from OUD_HCV_DAA;
quit;

title "Total N OUD Cases Without HCV Diagnoses for Women of Reproductive Age";
proc sql noprint;
    select count(distinct a.ID) as OUD_without_HCV
    from OUD_HCV_DAA as a
    left join HCV_IDS as b
    on a.ID = b.ID
    where b.ID is null;
quit;

title "Summary of HCV Cases Not Captured by OUD Definition and OUD Without HCV"; 
proc sql;
    select Total_HCV_Cases, 
           HCV_in_OUD, 
           (Total_HCV_Cases - HCV_in_OUD) as HCV_not_in_OUD,
           ((Total_HCV_Cases - HCV_in_OUD) / Total_HCV_Cases) * 100 as Percent_Missing_HCV format=8.2,
           Total_OUD_Cases,
           HCV_in_OUD as OUD_in_HCV,
           (Total_OUD_Cases - HCV_in_OUD) as OUD_missing_HCV,
           ((Total_OUD_Cases - HCV_in_OUD) / Total_OUD_Cases) * 100 as Percent_OUD_missing_HCV format=8.2
    from (
        select count(distinct ID) as Total_HCV_Cases
        from PHDHEPC.HCV
        where DISEASE_STATUS_HCV in (1, 2)
          and AGE_HCV between 15 and 45
          and SEX_HCV = 2
          and EVENT_YEAR_HCV >= 2014
    ) as total_hcv,
    (
        select count(distinct a.ID) as HCV_in_OUD
        from OUD_HCV_DAA as a
        inner join HCV_IDS as b
        on a.ID = b.ID
    ) as hcv_in_oud,
    (
        select count(distinct ID) as Total_OUD_Cases
        from OUD_HCV_DAA
    ) as total_oud;
quit;
title;

/*=====================*/
/* 19. Final OUD cohort */
/*=====================*/

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM TESTING;
QUIT;

%put Number of unique IDs in TESTING table: &num_unique_ids;

/*============================ */
/*  Part 2: HCV Care Cascade   */
/*============================ */

PROC FORMAT;
   VALUE agefmt_all
		1 = "15-18"
		2 = "19-25"
		3 = "26-30"
		4 = "31-35"
		5 = "36-45";
RUN;

PROC FORMAT;
   VALUE agefmt_comb
		1 = "15-25"
		2 = "15-25"
		3 = "26-30"
		4 = "31-35"
		5 = "36-45";
RUN;

PROC FORMAT;
   VALUE birthfmt
		0 = "No Births"
		1 = "Had Birth";
RUN;

PROC FORMAT;
   VALUE injectfmt
		0 = "Never Injected"
		1 = "Has Injected"
		9 = "Unknown Injection Status";
RUN;

PROC FORMAT;
   VALUE hcvfmt
		0 = "No HCV"
		1 = "HCV Confirmed or Probable";
run;

PROC FORMAT;
   VALUE momhcvfmt
		1 = "Confirmed"
		2 = "Probable";
run;

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

proc sort data=OUD_HCV_DAA;
    by CONFIRMED_HCV_INDICATOR;
run;

title "HCV Care Cascade, OUD Cohort, Overall";
proc freq data=OUD_HCV_DAA;
    tables ANY_HCV_TESTING_INDICATOR
           AB_TEST_INDICATOR
           RNA_TEST_INDICATOR
           HCV_SEROPOSITIVE_INDICATOR
           CONFIRMED_HCV_INDICATOR
           HCV_PRIMARY_DIAG
           DAA_START_INDICATOR
           BIRTH_INDICATOR
           EVENT_YEAR_HCV
           PHARM_FILL_DATE_YEAR / missing norow nocol nopercent;
run;

proc freq data=OUD_HCV_DAA;
    by CONFIRMED_HCV_INDICATOR;
    tables HCV_PRIMARY_DIAG
           GENO_TEST_INDICATOR
           DAA_START_INDICATOR
           BIRTH_INDICATOR / missing norow nocol nopercent;
run;

proc sort data=OUD_HCV_DAA;
    by HCV_PRIMARY_DIAG;
run;

proc freq data=OUD_HCV_DAA;
    by HCV_PRIMARY_DIAG;
    tables HCV_SEROPOSITIVE_INDICATOR / missing norow nocol nopercent;
run;

title "AB Tests Per Year, In Cohort";
PROC FREQ data = AB_YEARS_COHORT;
table  AB_TEST_YEAR / missing norow nocol nopercent;
run;

title "AB Tests Per Year, All MA Res.";
PROC FREQ data = AB_YEARS;
table  AB_TEST_YEAR / missing norow nocol nopercent;
run;

title   "Testing Among Confirmed HCV";
proc freq data=Testing;
where   CONFIRMED_HCV_INDICATOR = 1;
tables  BIRTH_INDICATOR
        EOT_RNA_TEST
		SVR12_RNA_TEST
		PHARM_FILL_DATE_YEAR / missing norow nopercent nocol;
run;

%macro CascadeTestFreq(strata, mytitle, ageformat, raceformat);
    TITLE "&mytitle";
    PROC FREQ DATA = OUD_HCV_DAA;
        BY &strata;
        TABLES ANY_HCV_TESTING_INDICATOR
               AB_TEST_INDICATOR
               RNA_TEST_INDICATOR
               HCV_SEROPOSITIVE_INDICATOR
               CONFIRMED_HCV_INDICATOR / missing norow nocol nopercent;
        FORMAT num_agegrp &ageformat 
               final_re &raceformat
               BIRTH_INDICATOR birthfmt.;
%mend CascadeTestFreq;

%macro CascadeCareFreq(strata, mytitle, ageformat, raceformat);
    TITLE "&mytitle";
    PROC FREQ DATA=OUD_HCV_DAA;
    BY &strata;
    TABLES GENO_TEST_INDICATOR
           HCV_PRIMARY_DIAG
           DAA_START_INDICATOR / missing norow nocol nopercent;
    WHERE CONFIRMED_HCV_INDICATOR=1;
    FORMAT num_agegrp &ageformat 
           final_re &raceformat
           BIRTH_INDICATOR birthfmt.;
%mend CascadeCareFreq;

%macro EndofTrtFreq(strata, mytitle, ageformat, raceformat);
    TITLE &mytitle;
    PROC FREQ DATA = TESTING;
        BY &strata;
        TABLES DAA_START_INDICATOR
               HCV_PRIMARY_DIAG
               EOT_RNA_TEST
               SVR12_RNA_TEST / missing norow nocol nopercent;
        WHERE CONFIRMED_HCV_INDICATOR = 1;
        FORMAT num_agegrp &ageformat 
               final_re &raceformat
               BIRTH_INDICATOR birthfmt.;
%mend EndofTrtFreq;

%macro YearFreq(var, strata, confirm_status, mytitle, ageformat, raceformat);
    TITLE &mytitle;
    PROC FREQ DATA = OUD_HCV_DAA;
        BY &strata;
        TABLE &var / missing norow nocol nopercent;
        WHERE CONFIRMED_HCV_INDICATOR = &confirm_status;
        FORMAT num_agegrp &ageformat
               final_re &raceformat
               BIRTH_INDICATOR birthfmt.;
%mend YearFreq;

proc sort data=OUD_HCV_DAA;
    by num_agegrp;
run;

proc sort data=TESTING;
    by num_agegrp;
run;

%CascadeTestFreq(num_agegrp, "HCV Testing: Stratified by Age", agefmt_all., racefmt_all.);   
%CascadeCareFreq(num_agegrp, "HCV Care: Stratified by Age", agefmt_all., racefmt_all.);
%EndofTrtFreq(num_agegrp, "HCV EOT/SVR Testing Among Confirmed HCV by Age", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, num_agegrp, 1, "Counts per year among confirmed, by Age", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, num_agegrp, 0, "Counts per year among probable, by Age", agefmt_comb., racefmt_all.)
%YearFreq(PHARM_FILL_DATE_YEAR, num_agegrp, 1, "Counts per year among confirmed, by Age", agefmt_comb., racefmt_all.)

proc sort data=OUD_HCV_DAA;
    by final_re;
run;

proc sort data=TESTING;
    by final_re;
run;

%CascadeTestFreq(final_re, "HCV Testing: Stratified by Race", agefmt_all., racefmt_all.);   
%CascadeCareFreq(final_re, "HCV Care: Stratified by Race", agefmt_all., racefmt_all.);
%EndofTrtFreq(final_re, "HCV EOT/SVR Testing Among Confirmed HCV by Race - all", agefmt_all., racefmt_all.)
%EndofTrtFreq(final_re, "HCV EOT/SVR Testing Among Confirmed HCV by Race -combined", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, final_re, 1, "Counts per year among confirmed, by Race", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, final_re, 0, "Counts per year among probable, by Race", agefmt_comb., racefmt_all.)
%YearFreq(PHARM_FILL_DATE_YEAR, final_re, 1, "Counts per year among confirmed, by Race", agefmt_comb., racefmt_all.)

proc sort data=OUD_HCV_DAA;
    by birth_indicator;
run;

proc sort data=TESTING;
    by birth_indicator;
run;

%CascadeTestFreq(birth_indicator, "HCV Testing: Stratified by Birth", agefmt_all., racefmt_all.);   
%CascadeCareFreq(birth_indicator, "HCV Care: Stratified by Birth", agefmt_all., racefmt_comb.);
%EndofTrtFreq(birth_indicator, "HCV EOT/SVR Testing Among Confirmed HCV by Birth", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, birth_indicator, 1, "Counts per year among confirmed, by Birth", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, birth_indicator, 0, "Counts per year among probable, by Birth", agefmt_comb., racefmt_all.)
%YearFreq(PHARM_FILL_DATE_YEAR, birth_indicator, 1, "Counts per year among confirmed, by Birth", agefmt_comb., racefmt_all.)

%macro CascadeCareFreqWithChi(strata, mytitle, ageformat, raceformat);
    TITLE "&mytitle";
    PROC FREQ DATA=OUD_HCV_DAA;
      TABLES &strata * GENO_TEST_INDICATOR
             &strata * HCV_PRIMARY_DIAG
             &strata * DAA_START_INDICATOR / missing norow nocol nopercent chisq;
      WHERE CONFIRMED_HCV_INDICATOR=1;
      FORMAT num_agegrp &ageformat
             final_re &raceformat
             BIRTH_INDICATOR birthfmt.;
    RUN;
  %mend CascadeCareFreqWithChi;
  
  %CascadeCareFreqWithChi(birth_indicator, "Chi Square Test for HCV Care: Stratified by Birth", agefmt_all., racefmt_comb.);
  
/*=========================================*/
/* Part 3: Tables1 and 2 - Crude Analysis  */
/*=========================================*/

/*====================*/
/* 1. Add Demographic Data */
/*====================*/
/* Aggregate Covariates: HOMELESS_EVER, county, FINAL_RE, EVER_INCARCERATED, FOREIGN_BORN, LANGUAGE
EDUCATION, OCCUPATION_CODE, MENTAL_HEALTH_DIAG, IJI_DIAG, OTHER_SUBSTANCE_USE, HCV_DIAG, IDU_EVIDENCE */

proc sql;
    create table FINAL_COHORT as
    select OUD_HCV_DAA.*,
           demographics.FINAL_RE, 
           demographics.HOMELESS_EVER,
           demographics.EVER_INCARCERATED,
           demographics.FOREIGN_BORN,
           demographics.LANGUAGE,
           demographics.EDUCATION,
           demographics.OCCUPATION_CODE
    from OUD_HCV_DAA
    left join PHDSPINE.DEMO as demographics
    on OUD_HCV_DAA.ID = demographics.ID;
quit;

proc sql;
create table MENTAL_HEALTH_COHORT(where=(MENTAL_HEALTH_DIAG=1)) as
select distinct FINAL_COHORT.ID,
       case
           when prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ECODE) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ADM_DIAGNOSIS) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD1) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD2) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD3) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD4) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD5) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD6) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD7) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD8) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD9) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD10) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD11) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD12) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD13) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD14) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD15) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD16) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD17) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD18) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD19) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD20) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD21) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD22) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD23) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD24) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD25) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_DIS_DIAGNOSIS) > 0 
                or substr(apcd.MED_ECODE, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ADM_DIAGNOSIS, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD1, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD2, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD3, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD4, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD5, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD6, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD7, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD8, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD9, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD10, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD11, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD12, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD13, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD14, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD15, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD16, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD17, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD18, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD19, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD20, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD21, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD22, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD23, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD24, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_ICD25, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                or substr(apcd.MED_DIS_DIAGNOSIS, 1, 3) in ('295', '296', '297', '298', '300', '311') then 1
           else 0
       end as MENTAL_HEALTH_DIAG
from FINAL_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_COHORT.ID = apcd.ID;
quit;

proc sql;
create table FINAL_COHORT as select *,
case
when ID in (select ID from MENTAL_HEALTH_COHORT) then 1
else 0
end as MENTAL_HEALTH_DIAG
from FINAL_COHORT;
quit;

%let IJI = ('3642', '9884', '11281', '11504', '11514', '11594',
           '421', '4211', '4219', 'A382', 'B376', 'I011', 'I059',
           'I079', 'I080', 'I083', 'I089', 'I330', 'I339', 'I358', 'I378',
           'I38', 'T826', 'I39', '681', '6811', '6819', '682', '6821', '6822',
           '6823', '6824', '6825', '6826', '6827', '6828', '6829', 'L030',
           'L031', 'L032', 'L033', 'L038', 'L039', 'M000', 'M001', 'M002',
           'M008', 'M009', '711', '7114', '7115', '7116', '7118', '7119',
           'I800', 'I801', 'I802', 'I803', 'I808', 'I809', '451', '4512',
           '4518', '4519');
           
proc sql;
create table IJI_COHORT(where=(IJI_DIAG=1)) as
select distinct FINAL_COHORT.ID,
  case
       when apcd.MED_ECODE in &IJI or
                    apcd.MED_ADM_DIAGNOSIS like '4249%' or apcd.MED_ADM_DIAGNOSIS in &IJI or
                    apcd.MED_ICD1 like '4249%' or apcd.MED_ICD1 in &IJI or
                    apcd.MED_ICD2 like '4249%' or apcd.MED_ICD2 in &IJI or
                    apcd.MED_ICD3 like '4249%' or apcd.MED_ICD3 in &IJI or
                    apcd.MED_ICD4 like '4249%' or apcd.MED_ICD4 in &IJI or
                    apcd.MED_ICD5 like '4249%' or apcd.MED_ICD5 in &IJI or
                    apcd.MED_ICD6 like '4249%' or apcd.MED_ICD6 in &IJI or
                    apcd.MED_ICD7 like '4249%' or apcd.MED_ICD7 in &IJI or
                    apcd.MED_ICD8 like '4249%' or apcd.MED_ICD8 in &IJI or
                    apcd.MED_ICD9 like '4249%' or apcd.MED_ICD9 in &IJI or
                    apcd.MED_ICD10 like '4249%' or apcd.MED_ICD10 in &IJI or
                    apcd.MED_ICD11 like '4249%' or apcd.MED_ICD11 in &IJI or
                    apcd.MED_ICD12 like '4249%' or apcd.MED_ICD12 in &IJI or
                    apcd.MED_ICD13 like '4249%' or apcd.MED_ICD13 in &IJI or
                    apcd.MED_ICD14 like '4249%' or apcd.MED_ICD14 in &IJI or
                    apcd.MED_ICD15 like '4249%' or apcd.MED_ICD15 in &IJI or
                    apcd.MED_ICD16 like '4249%' or apcd.MED_ICD16 in &IJI or
                    apcd.MED_ICD17 like '4249%' or apcd.MED_ICD17 in &IJI or
                    apcd.MED_ICD18 like '4249%' or apcd.MED_ICD18 in &IJI or
                    apcd.MED_ICD19 like '4249%' or apcd.MED_ICD19 in &IJI or
                    apcd.MED_ICD20 like '4249%' or apcd.MED_ICD20 in &IJI or
                    apcd.MED_ICD21 like '4249%' or apcd.MED_ICD21 in &IJI or
                    apcd.MED_ICD22 like '4249%' or apcd.MED_ICD22 in &IJI or
                    apcd.MED_ICD23 like '4249%' or apcd.MED_ICD23 in &IJI or
                    apcd.MED_ICD24 like '4249%' or apcd.MED_ICD24 in &IJI or
                    apcd.MED_ICD25 like '4249%' or apcd.MED_ICD25 in &IJI or
                    apcd.MED_DIS_DIAGNOSIS like '4249%' or apcd.MED_DIS_DIAGNOSIS in &IJI then 1
           else 0
       end as IJI_DIAG
from FINAL_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_COHORT.ID = apcd.ID;
quit;

proc sql;
create table FINAL_COHORT as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from FINAL_COHORT;
quit;

proc sql;
    create table FINAL_COHORT as
    select 
        FINAL_COHORT.*, 
        min_hiv.DIAGNOSIS_MONTH_HIV, 
        min_hiv.DIAGNOSIS_YEAR_HIV,
        (case when min_hiv.ID is not null then 1 else 0 end) as HIV_DIAG
    from FINAL_COHORT
    left join (
        select ID, 
               min(DIAGNOSIS_MONTH_HIV) as DIAGNOSIS_MONTH_HIV,
               min(DIAGNOSIS_YEAR_HIV) as DIAGNOSIS_YEAR_HIV
        from PHDHIV.HIV_INC
        group by ID
    ) as min_hiv
    on FINAL_COHORT.ID = min_hiv.ID;
quit;

/* Create EVER_MOUD indicator from cleaned MOUD dataset */
DATA moud;
    SET PHDSPINE.MOUD3;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

data moud_demo;
    set moud;
    rename 
        DATE_START_MOUD = start_date
        DATE_END_MOUD = end_date
        DATE_START_YEAR_MOUD = start_year
        DATE_END_YEAR_MOUD = end_year
        DATE_START_MONTH_MOUD = start_month
        DATE_END_MONTH_MOUD = end_month;
run;

PROC SORT DATA=moud_demo;
    by ID TYPE_MOUD start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID TYPE_MOUD;
    RETAIN new_start_date new_end_date new_start_month new_start_year new_end_month new_end_year;

    IF FIRST.ID OR FIRST.TYPE_MOUD THEN DO;
        new_start_date = start_date;
        new_start_month = start_month;
        new_start_year = start_year;

        new_end_date = end_date;
        new_end_month = end_month;
        new_end_year = end_year;
    END;
    ELSE DO;
        diff_days = start_date - new_end_date;

        IF diff_days <= &MOUD_leniency THEN DO;
            new_end_date = end_date;
            new_end_month = end_month;
            new_end_year = end_year;
        END;
        ELSE DO;
            OUTPUT;
            new_start_date = start_date;
            new_start_month = start_month;
            new_start_year = start_year;

            new_end_date = end_date;
            new_end_month = end_month;
            new_end_year = end_year;
        END;
    END;
    IF LAST.ID OR LAST.TYPE_MOUD THEN OUTPUT;


    DROP diff_days start_date end_date start_month end_month start_year end_year;
RUN;

PROC SQL;
 CREATE TABLE moud_demo 
 AS SELECT DISTINCT * FROM moud_demo;
QUIT;

PROC SORT data=moud_demo (KEEP= new_start_date new_start_month new_start_year
					  			new_end_date new_end_month new_end_year 
					  			ID TYPE_MOUD);
    BY ID new_start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID;
	
	IF new_end_date - new_start_date < &MOUD_leniency THEN DELETE;
	
	IF FIRST.ID THEN diff = .; 
	ELSE diff = new_start_date - lag(new_end_date);
    IF new_end_date < lag(new_end_date) THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;

RUN;

PROC SORT data=moud_demo;
    BY ID new_start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    by ID;
    retain episode_num;

    lag_date = lag(new_end_date);
    IF FIRST.ID THEN lag_date = .;
    IF FIRST.ID THEN episode_num = 1;
    
    diff = new_start_date - lag_date;

    IF diff >= &MOUD_leniency THEN flag = 1; ELSE flag = 0;
    IF flag = 1 THEN episode_num = episode_num + 1;

    episode_id = catx("_", ID, episode_num);
RUN;

data moud_demo;
    set moud_demo;
    where new_start_year >= 2014;
run;

PROC SQL;
    CREATE TABLE moud_demo AS 
    SELECT * 
    FROM moud_demo
    WHERE ID IN (SELECT DISTINCT ID FROM oud_distinct);
QUIT;

PROC SQL;                    
    CREATE TABLE moud_starts AS
    SELECT ID,
           1 AS moud_start
    FROM moud_demo
    ORDER BY new_start_month, new_start_year, TYPE_MOUD, ID;
QUIT;

PROC SQL;                    
    CREATE TABLE moud_starts AS
    SELECT DISTINCT *
    FROM moud_starts;
QUIT;

proc sql;
    create table FINAL_COHORT as
    select 
        A.*, 
        (case when B.ID is not null then 1 else 0 end) as EVER_MOUD
    from FINAL_COHORT as A
    left join moud_starts as B
    on A.ID = B.ID;
quit;

%LET OTHER_SUBSTANCE_USE = ('2910', '2911', '2912', '2913', '2914', '2915', '2918', '29181', '29182', '29189', '2919',
                      '30300', '30301', '30302', '30390', '30391', '30392', '30500', '30501',
                      '30502', '76071', '9800', '3575', '4255', '53530', '53531', '5710', '5711', '5712',
                      '5713', 'F101', 'F1010', 'F1012', 'F10120', 'F10121', 'F10129', 'F1013',
                      'F10130', 'F10131', 'F10132', 'F10139', 'F1014', 'F1015', 'F10150', 'F10151', 'F10159',
                      'F1018', 'F10180', 'F10181', 'F10182', 'F10188', 'F1019', 'F102', 'F1020', 'F1022',
                      'F10220', 'F10221', 'F10229', 'F1023', 'F10230', 'F10231', 'F10232', 'F10239', 'F1024',
                      'F1025', 'F10250', 'F10251', 'F10259', 'F1026', 'F1027', 'F1028', 'F10280', 'F10281',
                      'F10282', 'F10288', 'F1029', 'F109', 'F1090', 'F1092', 'F10920', 'F10921', 'F10929',
                      'F1093', 'F10930', 'F10931', 'F10932', 'F10939', 'F1094', 'F1095', 'F10950', 'F10951',
                      'F10959', 'F1096', 'F1097', 'F1098', 'F10980', 'F10981', 'F10982', 'F10988', 'F1099', 'T405X4A', /* AUD */
                      '30421', '30422', '3056', '30561', '30562', '3044', '30441', '30442',
                      '9697', '96972', '96973', '96979', 'E8542', 'F14', 'F141', 'F1410', 'F1412',
                      'F14120', 'F14121', 'F14122', 'F14129', 'F1413', 'F1414', 'F1415', 'F14150', 'F14151',
                      'F14159', 'F1418', 'F14180', 'F14181', 'F14182', 'F14188', 'F1419', 'F142', 'F1420', 'F1421',
                      'F1422', 'F14220', 'F14221', 'F14222', 'F14229', 'F1423', 'F1424', 'F1425', 'F14250', 'F14251',
                      'F14259', 'F1428', 'F14280', 'F14281', 'F14282', 'F14288', 'F1429', 'F149', 'F1490', 'F1491',
                      'F1492', 'F14920', 'F14921', 'F14922', 'F14929', 'F1493', 'F1494', 'F1495', 'F14950', 'F14951',
                      'F14959', 'F1498', 'F14980', 'F14981', 'F14982', 'F14988', 'F1499', 'F15', 'F151', 'F1510',
                      'F1512', 'F15120', 'F15121', 'F15122', 'F15129', 'F1513', 'F1514', 'F1515', 'F15150',
                      'F15151', 'F15159', 'F1518', 'F15180', 'F15181', 'F15182', 'F15188', 'F1519', 'F152',
                      'F1520', 'F1522', 'F15220', 'F15221', 'F15222', 'F15229', 'F1523', 'F1524', 'F1525',
                      'F15250', 'F15251', 'F15259', 'F1528', 'F15280', 'F15281', 'F15282', 'F15288', 'F1529',
                      'F159', 'F1590', 'F1592', 'F15920', 'F15921', 'F15922', 'F15929', 'F1593', 'F1594',
                      'F1595', 'F15950', 'F15951', 'F15959', 'F1598', 'F15980', 'F15981', 'F15982', 'F15988',
                      'F1599', 'T405', 'T436', 'T405XIA', 'T43601A', 'T43602A', 'T43604A', 'T43611A',
                      'T43621A', 'T43624A', 'T43631A', 'T43634A', 'T43641A', 'T43644A',
                      '96970', '96972', '96973', '96979', '97081', '97089', 'E8542', 'E8543', 'E8552',
                      'T43691A', 'T43694A' /* Stimulants */);

proc sql;
create table OTHER_SUBSTANCE_USE_COHORT(where=(OTHER_SUBSTANCE_USE=1)) as
select distinct FINAL_COHORT.ID,
  case
       when apcd.MED_ECODE in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ADM_DIAGNOSIS in &OTHER_SUBSTANCE_USE or
                        apcd.MED_PROC_CODE in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC1 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC2 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC3 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC4 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC5 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC6 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD_PROC7 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD1 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD2 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD3 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD4 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD5 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD6 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD7 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD8 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD9 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD10 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD11 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD12 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD13 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD14 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD15 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD16 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD17 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD18 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD19 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD20 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD21 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD22 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD23 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD24 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ICD25 in &OTHER_SUBSTANCE_USE or
                        apcd.MED_DIS_DIAGNOSIS in &OTHER_SUBSTANCE_USE 
                   or
                  (BSAS.CLT_ENR_PRIMARY_DRUG in (1,2,3,10,11,12) or
                   BSAS.CLT_ENR_SECONDARY_DRUG in (1,2,3,10,11,12) or
                   BSAS.CLT_ENR_TERTIARY_DRUG in (1,2,3,10,11,12)) then 1
           else 0
       end as OTHER_SUBSTANCE_USE
from FINAL_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd on FINAL_COHORT.ID = apcd.ID
left join PHDBSAS.BSAS as bsas on FINAL_COHORT.ID = bsas.ID;
quit;

proc sql;
create table FINAL_COHORT as select *,
case
when ID in (select ID from OTHER_SUBSTANCE_USE_COHORT) then 1
else 0
end as OTHER_SUBSTANCE_USE
from FINAL_COHORT;
quit;

%LET HCV_ICD = ('7051', '7054', '707',
				'7041', '7044', '7071',
				'B1710','B182', 'B1920',
				'B1711','B1921');
				
proc sql;
create table HCV_DIAG_COHORT (where=(HCV_DIAG=1)) as
select distinct FINAL_COHORT.ID,
  case
       when apcd.MED_ECODE in &HCV_ICD or
                        apcd.MED_ADM_DIAGNOSIS in &HCV_ICD or
                        apcd.MED_ICD1 in &HCV_ICD or
                        apcd.MED_ICD2 in &HCV_ICD or
                        apcd.MED_ICD3 in &HCV_ICD or
                        apcd.MED_ICD4 in &HCV_ICD or
                        apcd.MED_ICD5 in &HCV_ICD or
                        apcd.MED_ICD6 in &HCV_ICD or
                        apcd.MED_ICD7 in &HCV_ICD or
                        apcd.MED_ICD8 in &HCV_ICD or
                        apcd.MED_ICD9 in &HCV_ICD or
                        apcd.MED_ICD10 in &HCV_ICD or
                        apcd.MED_ICD11 in &HCV_ICD or
                        apcd.MED_ICD12 in &HCV_ICD or
                        apcd.MED_ICD13 in &HCV_ICD or
                        apcd.MED_ICD14 in &HCV_ICD or
                        apcd.MED_ICD15 in &HCV_ICD or
                        apcd.MED_ICD16 in &HCV_ICD or
                        apcd.MED_ICD17 in &HCV_ICD or
                        apcd.MED_ICD18 in &HCV_ICD or
                        apcd.MED_ICD19 in &HCV_ICD or
                        apcd.MED_ICD20 in &HCV_ICD or
                        apcd.MED_ICD21 in &HCV_ICD or
                        apcd.MED_ICD22 in &HCV_ICD or
                        apcd.MED_ICD23 in &HCV_ICD or
                        apcd.MED_ICD24 in &HCV_ICD or
                        apcd.MED_ICD25 in &HCV_ICD or
                        apcd.MED_DIS_DIAGNOSIS in &HCV_ICD 
                   then 1
           else 0
       end as HCV_DIAG
from FINAL_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd on FINAL_COHORT.ID = apcd.ID;
quit;

proc sql;
create table FINAL_COHORT as select *,
case
when ID in (select ID from HCV_DIAG_COHORT) then 1
else 0
end as HCV_DIAG
from FINAL_COHORT;
quit;

/* =================================================================== */
/* 2. Finding Closest Medical Event Dates for HCV Cases for HCV Cohort */
/* =================================================================== */
/* This section identifies the closest APCD claim relative to each HCV diagnosis date.  
   The HCV and MOUD_MEDICAL datasets are first sorted by ID and relevant date variables to facilitate merging.  
   In the merged dataset, past and future MOUD event dates are compared to the HCV diagnosis date for each individual.  
   The closest event date before or after the diagnosis is retained, along with associated attributes such as insurance type and provider city.  
   For each ID, if a past event exists, it is preferred; otherwise, the closest future event is selected.  
   The final dataset includes ID, HCV event date, closest MOUD event date, insurance type, and provider city,  
   which are then merged with the FINAL_COHORT dataset to add context on healthcare access. */

DATA hepc;
    SET PHDHEPC.HCV;
    WHERE EVENT_YEAR_HCV >= 2014;
RUN;

proc sort data=hepc;
    by ID EVENT_DATE_HCV;
run;

DATA apcd;
    SET PHDAPCD.ME_MTH;
RUN;

proc sort data=apcd;
    by ID ME_MEM_YEAR ME_MEM_MONTH;
run;

data closest_date;
length closest_past_type closest_future_type closest_type $2;
    merge hepc (in=a)
          apcd (in=b);
    by ID;
    
    if a;

    retain closest_past_date closest_past_type min_past_diff;
    retain closest_future_date closest_future_type min_future_diff;

    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        min_past_diff = .;
        closest_future_date = .;
        closest_future_type = "";
        min_future_diff = .;
    end;

    if ME_MEM_YEAR < EVENT_YEAR_HCV or (ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH < EVENT_MONTH_HCV) then do;
        past_diff = (EVENT_YEAR_HCV - ME_MEM_YEAR) * 12 + (EVENT_MONTH_HCV - ME_MEM_MONTH);
        if min_past_diff = . or past_diff < min_past_diff then do;
            min_past_diff = past_diff;
            closest_past_date = mdy(ME_MEM_MONTH, 1, ME_MEM_YEAR);
            closest_past_type = ME_INSURANCE_PRODUCT;
        end;
    end;

    else if ME_MEM_YEAR > EVENT_YEAR_HCV or (ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH > EVENT_MONTH_HCV) then do;
        future_diff = (ME_MEM_YEAR - EVENT_YEAR_HCV) * 12 + (ME_MEM_MONTH - EVENT_MONTH_HCV);
        if min_future_diff = . or future_diff < min_future_diff then do;
            min_future_diff = future_diff;
            closest_future_date = mdy(ME_MEM_MONTH, 1, ME_MEM_YEAR);
            closest_future_type = ME_INSURANCE_PRODUCT;
        end;
    end;

    if last.ID then do;
        if min_past_diff ne . then do;
            closest_date = closest_past_date;
            closest_type = closest_past_type;
        end;
        else do;
            closest_date = closest_future_date;
            closest_type = closest_future_type;
        end;
        output;
    end;
run;

data final_output;
    set closest_date;
    keep ID EVENT_YEAR_HCV EVENT_MONTH_HCV closest_date closest_type 
run;

proc sort data=FINAL_COHORT;
    by ID;
run;

proc sort data=final_output;
    by ID;
run;

data FINAL_COHORT;
    merge FINAL_COHORT (in=a)
          final_output (keep=ID closest_type rename=(closest_type=INSURANCE));
    by ID;
    if a;
run;

/* ========================================================================= */
/* 3. Finding Closest Medical Event Dates for OUD Diagnosis (Non-HCV Cohort) */
/* ========================================================================= */
/* This section identifies the closest APCD claim relative to the OUD diagnosis year for individuals without HCV diagnoses.
   The `missing_hcv` dataset is created by selecting individuals from the FINAL_COHORT who do not have a match in the HCV dataset.  
   Using the sorted APCD_MEDICAL dataset, the closest MOUD event year before or after the OUD diagnosis year is retained for each individual.  
   The closest event's attributes (insurance type and res zip) are captured, with preference given to past events if available.  
   Finally, the enriched data with closest MOUD event details is merged back into the FINAL_COHORT dataset for a comprehensive view of healthcare access. */

proc sql;
    create table missing_hcv as
    select f.ID, f.YOB, f.OUD_AGE,
           (f.YOB + f.OUD_AGE) as OUD_DIAGNOSIS_YEAR
    from FINAL_COHORT as f
    left join (
        select *
        from PHDHEPC.HCV
        where EVENT_YEAR_HCV >= 2014
    ) as h
    on f.ID = h.ID
    where h.ID is null;
quit;

DATA apcd;
    SET PHDAPCD.ME_MTH;
RUN;

proc sort data=apcd;
    by ID ME_MEM_YEAR ME_MEM_MONTH;
run;

data closest_date;
length closest_past_type closest_future_type closest_type $2 closest_zip $10;
format closest_past_zip closest_future_zip closest_zip $5.;
    merge missing_hcv (in=a)
          apcd (in=b);
    by ID;
    
    if a;

    retain closest_past_date closest_past_type min_past_diff closest_past_zip;
    retain closest_future_date closest_future_type min_future_diff closest_future_zip;

    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        min_past_diff = .;
        closest_past_zip = "";
        closest_future_date = .;
        closest_future_type = "";
        min_future_diff = .;
        closest_future_zip = "";
    end;

    /* Compare the months and years for past and future dates */
    if ME_MEM_YEAR < EVENT_YEAR_HCV or (ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH < EVENT_MONTH_HCV) then do;
        past_diff = (EVENT_YEAR_HCV - ME_MEM_YEAR) * 12 + (EVENT_MONTH_HCV - ME_MEM_MONTH);
        if min_past_diff = . or past_diff < min_past_diff then do;
            min_past_diff = past_diff;
            closest_past_date = mdy(ME_MEM_MONTH, 1, ME_MEM_YEAR);  /* create a date from year and month */
            closest_past_type = ME_INSURANCE_PRODUCT;
            closest_past_zip = RES_ZIP_APCD_ME;
        end;
    end;

    else if ME_MEM_YEAR > EVENT_YEAR_HCV or (ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH > EVENT_MONTH_HCV) then do;
        future_diff = (ME_MEM_YEAR - EVENT_YEAR_HCV) * 12 + (ME_MEM_MONTH - EVENT_MONTH_HCV);
        if min_future_diff = . or future_diff < min_future_diff then do;
            min_future_diff = future_diff;
            closest_future_date = mdy(ME_MEM_MONTH, 1, ME_MEM_YEAR);
            closest_future_type = ME_INSURANCE_PRODUCT;
            closest_future_zip = RES_ZIP_APCD_ME;
        end;
    end;

    if last.ID then do;
        if min_past_diff ne . then do;
            closest_date = closest_past_date;
            closest_type = closest_past_type;
            closest_zip = closest_past_zip;
        end;
        else do;
            closest_date = closest_future_date;
            closest_type = closest_future_type;
            closest_zip = closest_future_zip;
        end;
        output;
    end;
run;

data final_output;
    set closest_date;
    keep ID closest_type closest_zip;
run;

proc sort data=FINAL_COHORT;
    by ID;
run;

proc sort data=final_output;
    by ID;
run;

data FINAL_COHORT;
    merge FINAL_COHORT (in=a)
          final_output (keep=ID closest_type closest_zip rename=(closest_type=INSURANCE));
    by ID;
    if a;
run;

/* ================================= */
/* 4. FORMATS                        */
/* ================================= */

proc format;
    value flagf
        0 = 'No'
        1 = 'Yes'
        9 = 'Unknown';

    value raceef
        1 = 'White Non-Hispanic'
        2 = 'Black non-Hispanic'
        3 = 'Asian/PI non-Hispanic'
        4 = 'Hispanic'
        5 = 'American Indian or Other non-Hispanic'
        9 = 'Missing'
        99 = 'Not an MA resident';

    value fbornf
        0 = 'No'
        1 = 'Yes'
        8 = 'Missing in dataset'
        9 = 'Not collected';

    value langfsecondary
        0 = 'Not Provided' 
        1 = 'English Only'
        2 = 'English and Another Language'
        3 = 'Another Language'
        9 = 'Unknown/missing';

    value edu_fmt
        1 = 'HS or less'
        2 = '13+ years'
        3 = 'Not of School Age'
        8 = 'Missing in dataset'
        9 = 'Not collected'
        10 = 'Special Education';
    
    value ld_pay_fmt
	    1 = 'Public'
	    2 = 'Private'
	    9 = 'Unknown';
    
    value kotel_fmt
        0 = 'Missing/Unknown'
        1 = 'Inadequate'
        2 = 'Intermediate'
        3 = 'Adequate'
        4 = 'Intensive';

    value prenat_site_fmt
    	1 = 'Private Physicians Office'
    	2 = 'Community Health Center'
	    3 = 'HMO'
	    4 = 'Hospital Clinic'
    	5 = 'Other'
    	9 = 'Unknown';

    VALUE age_grps
		1 = '15-18'
		2 = '19-25'
		3 = '26-30'
		4 = '31-35'
		5 = '36-45';

run;

/* ================================= */
/* 5. RECATEGORIZE                   */
/* ================================= */

data FINAL_COHORT;
   set FINAL_COHORT;
   length INSURANCE_CAT $10.;
   if INSURANCE = 1 then INSURANCE_CAT = 'Commercial';
   else if INSURANCE = 2 then INSURANCE_CAT = 'Medicaid';
   else if INSURANCE = 3 then INSURANCE_CAT = 'Medicare';
   else INSURANCE_CAT = 'Other/Missing';
run;

/* Recategorize zip into town/city code for OUD cohort (HCV cohort has direct pull from HEPC dataset) */
data FINAL_COHORT;
   set FINAL_COHORT;
     if not missing(closest_zip) then do;
	 if closest_zip = "02351" then RES_CODE_HCV = 1;
else if closest_zip = "01718" then RES_CODE_HCV = 2;
else if closest_zip = "01720" then RES_CODE_HCV = 2;
else if closest_zip = "02743" then RES_CODE_HCV = 3;
else if closest_zip = "01220" then RES_CODE_HCV = 4;
else if closest_zip = "01001" then RES_CODE_HCV = 5;
else if closest_zip = "01030" then RES_CODE_HCV = 5;
else if closest_zip = "01230" then RES_CODE_HCV = 6;
else if closest_zip = "01913" then RES_CODE_HCV = 7;
else if closest_zip = "01003" then RES_CODE_HCV = 8;
else if closest_zip = "01004" then RES_CODE_HCV = 8;
else if closest_zip = "01059" then RES_CODE_HCV = 8;
else if closest_zip = "01810" then RES_CODE_HCV = 9;
else if closest_zip = "01812" then RES_CODE_HCV = 9;
else if closest_zip = "01899" then RES_CODE_HCV = 9;
else if closest_zip = "02174" then RES_CODE_HCV = 10;
else if closest_zip = "02175" then RES_CODE_HCV = 10;
else if closest_zip = "02474" then RES_CODE_HCV = 10;
else if closest_zip = "02475" then RES_CODE_HCV = 10;
else if closest_zip = "02476" then RES_CODE_HCV = 10;
else if closest_zip = "01430" then RES_CODE_HCV = 11;
else if closest_zip = "01466" then RES_CODE_HCV = 11;
else if closest_zip = "01431" then RES_CODE_HCV = 12;
else if closest_zip = "01330" then RES_CODE_HCV = 13;
else if closest_zip = "01721" then RES_CODE_HCV = 14;
else if closest_zip = "01331" then RES_CODE_HCV = 15;
else if closest_zip = "02703" then RES_CODE_HCV = 16;
else if closest_zip = "02760" then RES_CODE_HCV = 16;
else if closest_zip = "02763" then RES_CODE_HCV = 16;
else if closest_zip = "01501" then RES_CODE_HCV = 17;
else if closest_zip = "02322" then RES_CODE_HCV = 18;
else if closest_zip = "01432" then RES_CODE_HCV = 19;
else if closest_zip = "01433" then RES_CODE_HCV = 19;
else if closest_zip = "02601" then RES_CODE_HCV = 20;
else if closest_zip = "02630" then RES_CODE_HCV = 20;
else if closest_zip = "02632" then RES_CODE_HCV = 20;
else if closest_zip = "02634" then RES_CODE_HCV = 20;
else if closest_zip = "02635" then RES_CODE_HCV = 20;
else if closest_zip = "02636" then RES_CODE_HCV = 20;
else if closest_zip = "02637" then RES_CODE_HCV = 20;
else if closest_zip = "02647" then RES_CODE_HCV = 20;
else if closest_zip = "02648" then RES_CODE_HCV = 20;
else if closest_zip = "02655" then RES_CODE_HCV = 20;
else if closest_zip = "02668" then RES_CODE_HCV = 20;
else if closest_zip = "02672" then RES_CODE_HCV = 20;
else if closest_zip = "01005" then RES_CODE_HCV = 21;
else if closest_zip = "01074" then RES_CODE_HCV = 21;
else if closest_zip = "01223" then RES_CODE_HCV = 22;
else if closest_zip = "01730" then RES_CODE_HCV = 23;
else if closest_zip = "01731" then RES_CODE_HCV = 23;
else if closest_zip = "01007" then RES_CODE_HCV = 24;
else if closest_zip = "02019" then RES_CODE_HCV = 25;
else if closest_zip = "02178" then RES_CODE_HCV = 26;
else if closest_zip = "02179" then RES_CODE_HCV = 26;
else if closest_zip = "02478" then RES_CODE_HCV = 26;
else if closest_zip = "02479" then RES_CODE_HCV = 26;
else if closest_zip = "02779" then RES_CODE_HCV = 27;
else if closest_zip = "01503" then RES_CODE_HCV = 28;
else if closest_zip = "01337" then RES_CODE_HCV = 29;
else if closest_zip = "01915" then RES_CODE_HCV = 30;
else if closest_zip = "01965" then RES_CODE_HCV = 30;
else if closest_zip = "01821" then RES_CODE_HCV = 31;
else if closest_zip = "01822" then RES_CODE_HCV = 31;
else if closest_zip = "01862" then RES_CODE_HCV = 31;
else if closest_zip = "01865" then RES_CODE_HCV = 31;
else if closest_zip = "01866" then RES_CODE_HCV = 31;
else if closest_zip = "01504" then RES_CODE_HCV = 32;
else if closest_zip = "01008" then RES_CODE_HCV = 33;
else if closest_zip = "01740" then RES_CODE_HCV = 34;
else if closest_zip = "02101" then RES_CODE_HCV = 35;
else if closest_zip = "02102" then RES_CODE_HCV = 35;
else if closest_zip = "02103" then RES_CODE_HCV = 35;
else if closest_zip = "02104" then RES_CODE_HCV = 35;
else if closest_zip = "02105" then RES_CODE_HCV = 35;
else if closest_zip = "02106" then RES_CODE_HCV = 35;
else if closest_zip = "02107" then RES_CODE_HCV = 35;
else if closest_zip = "02108" then RES_CODE_HCV = 35;
else if closest_zip = "02109" then RES_CODE_HCV = 35;
else if closest_zip = "02110" then RES_CODE_HCV = 35;
else if closest_zip = "02111" then RES_CODE_HCV = 35;
else if closest_zip = "02112" then RES_CODE_HCV = 35;
else if closest_zip = "02113" then RES_CODE_HCV = 35;
else if closest_zip = "02114" then RES_CODE_HCV = 35;
else if closest_zip = "02115" then RES_CODE_HCV = 35;
else if closest_zip = "02116" then RES_CODE_HCV = 35;
else if closest_zip = "02117" then RES_CODE_HCV = 35;
else if closest_zip = "02118" then RES_CODE_HCV = 35;
else if closest_zip = "02119" then RES_CODE_HCV = 35;
else if closest_zip = "02120" then RES_CODE_HCV = 35;
else if closest_zip = "02121" then RES_CODE_HCV = 35;
else if closest_zip = "02122" then RES_CODE_HCV = 35;
else if closest_zip = "02123" then RES_CODE_HCV = 35;
else if closest_zip = "02124" then RES_CODE_HCV = 35;
else if closest_zip = "02125" then RES_CODE_HCV = 35;
else if closest_zip = "02126" then RES_CODE_HCV = 35;
else if closest_zip = "02127" then RES_CODE_HCV = 35;
else if closest_zip = "02128" then RES_CODE_HCV = 35;
else if closest_zip = "02129" then RES_CODE_HCV = 35;
else if closest_zip = "02130" then RES_CODE_HCV = 35;
else if closest_zip = "02131" then RES_CODE_HCV = 35;
else if closest_zip = "02132" then RES_CODE_HCV = 35;
else if closest_zip = "02133" then RES_CODE_HCV = 35;
else if closest_zip = "02134" then RES_CODE_HCV = 35;
else if closest_zip = "02135" then RES_CODE_HCV = 35;
else if closest_zip = "02136" then RES_CODE_HCV = 35;
else if closest_zip = "02137" then RES_CODE_HCV = 35;
else if closest_zip = "02163" then RES_CODE_HCV = 35;
else if closest_zip = "02196" then RES_CODE_HCV = 35;
else if closest_zip = "02199" then RES_CODE_HCV = 35;
else if closest_zip = "02201" then RES_CODE_HCV = 35;
else if closest_zip = "02202" then RES_CODE_HCV = 35;
else if closest_zip = "02203" then RES_CODE_HCV = 35;
else if closest_zip = "02204" then RES_CODE_HCV = 35;
else if closest_zip = "02205" then RES_CODE_HCV = 35;
else if closest_zip = "02206" then RES_CODE_HCV = 35;
else if closest_zip = "02207" then RES_CODE_HCV = 35;
else if closest_zip = "02208" then RES_CODE_HCV = 35;
else if closest_zip = "02209" then RES_CODE_HCV = 35;
else if closest_zip = "02210" then RES_CODE_HCV = 35;
else if closest_zip = "02211" then RES_CODE_HCV = 35;
else if closest_zip = "02212" then RES_CODE_HCV = 35;
else if closest_zip = "02215" then RES_CODE_HCV = 35;
else if closest_zip = "02216" then RES_CODE_HCV = 35;
else if closest_zip = "02217" then RES_CODE_HCV = 35;
else if closest_zip = "02222" then RES_CODE_HCV = 35;
else if closest_zip = "02241" then RES_CODE_HCV = 35;
else if closest_zip = "02266" then RES_CODE_HCV = 35;
else if closest_zip = "02293" then RES_CODE_HCV = 35;
else if closest_zip = "02295" then RES_CODE_HCV = 35;
else if closest_zip = "02297" then RES_CODE_HCV = 35;
else if closest_zip = "02562" then RES_CODE_HCV = 36;
else if closest_zip = "02532" then RES_CODE_HCV = 36;
else if closest_zip = "02534" then RES_CODE_HCV = 36;
else if closest_zip = "02553" then RES_CODE_HCV = 36;
else if closest_zip = "02559" then RES_CODE_HCV = 36;
else if closest_zip = "02561" then RES_CODE_HCV = 36;
else if closest_zip = "01719" then RES_CODE_HCV = 37;
else if closest_zip = "01885" then RES_CODE_HCV = 38;
else if closest_zip = "01921" then RES_CODE_HCV = 38;
else if closest_zip = "01505" then RES_CODE_HCV = 39;
else if closest_zip = "02184" then RES_CODE_HCV = 40;
else if closest_zip = "02185" then RES_CODE_HCV = 40;
else if closest_zip = "02631" then RES_CODE_HCV = 41;
else if closest_zip = "02324" then RES_CODE_HCV = 42;
else if closest_zip = "02325" then RES_CODE_HCV = 42;
else if closest_zip = "01010" then RES_CODE_HCV = 43;
else if closest_zip = "02301" then RES_CODE_HCV = 44;
else if closest_zip = "02302" then RES_CODE_HCV = 44;
else if closest_zip = "02303" then RES_CODE_HCV = 44;
else if closest_zip = "02304" then RES_CODE_HCV = 44;
else if closest_zip = "02401" then RES_CODE_HCV = 44;
else if closest_zip = "02402" then RES_CODE_HCV = 44;
else if closest_zip = "02403" then RES_CODE_HCV = 44;
else if closest_zip = "02404" then RES_CODE_HCV = 44;
else if closest_zip = "02405" then RES_CODE_HCV = 44;
else if closest_zip = "01506" then RES_CODE_HCV = 45;
else if closest_zip = "02146" then RES_CODE_HCV = 46;
else if closest_zip = "02147" then RES_CODE_HCV = 46;
else if closest_zip = "02445" then RES_CODE_HCV = 46;
else if closest_zip = "02446" then RES_CODE_HCV = 46;
else if closest_zip = "02447" then RES_CODE_HCV = 46;
else if closest_zip = "02467" then RES_CODE_HCV = 46;
else if closest_zip = "01338" then RES_CODE_HCV = 47;
else if closest_zip = "01803" then RES_CODE_HCV = 48;
else if closest_zip = "01805" then RES_CODE_HCV = 48;
else if closest_zip = "02138" then RES_CODE_HCV = 49;
else if closest_zip = "02139" then RES_CODE_HCV = 49;
else if closest_zip = "02140" then RES_CODE_HCV = 49;
else if closest_zip = "02141" then RES_CODE_HCV = 49;
else if closest_zip = "02142" then RES_CODE_HCV = 49;
else if closest_zip = "02238" then RES_CODE_HCV = 49;
else if closest_zip = "02239" then RES_CODE_HCV = 49;
else if closest_zip = "02021" then RES_CODE_HCV = 50;
else if closest_zip = "01741" then RES_CODE_HCV = 51;
else if closest_zip = "02330" then RES_CODE_HCV = 52;
else if closest_zip = "02355" then RES_CODE_HCV = 52;
else if closest_zip = "02366" then RES_CODE_HCV = 52;
else if closest_zip = "01339" then RES_CODE_HCV = 53;
else if closest_zip = "01507" then RES_CODE_HCV = 54;
else if closest_zip = "01508" then RES_CODE_HCV = 54;
else if closest_zip = "01509" then RES_CODE_HCV = 54;
else if closest_zip = "02633" then RES_CODE_HCV = 55;
else if closest_zip = "02650" then RES_CODE_HCV = 55;
else if closest_zip = "02659" then RES_CODE_HCV = 55;
else if closest_zip = "02669" then RES_CODE_HCV = 55;
else if closest_zip = "01824" then RES_CODE_HCV = 56;
else if closest_zip = "01863" then RES_CODE_HCV = 56;
else if closest_zip = "02150" then RES_CODE_HCV = 57;
else if closest_zip = "01225" then RES_CODE_HCV = 58;
else if closest_zip = "01011" then RES_CODE_HCV = 59;
else if closest_zip = "01050" then RES_CODE_HCV = 143;
else if closest_zip = "01012" then RES_CODE_HCV = 60;
else if closest_zip = "01026" then RES_CODE_HCV = 60;
else if closest_zip = "01084" then RES_CODE_HCV = 60;
else if closest_zip = "01013" then RES_CODE_HCV = 61;
else if closest_zip = "01014" then RES_CODE_HCV = 61;
else if closest_zip = "01020" then RES_CODE_HCV = 61;
else if closest_zip = "01021" then RES_CODE_HCV = 61;
else if closest_zip = "01022" then RES_CODE_HCV = 61;
else if closest_zip = "02535" then RES_CODE_HCV = 62;
else if closest_zip = "02552" then RES_CODE_HCV = 62;
else if closest_zip = "01247" then RES_CODE_HCV = 63;
else if closest_zip = "01510" then RES_CODE_HCV = 64;
else if closest_zip = "02025" then RES_CODE_HCV = 65;
else if closest_zip = "01340" then RES_CODE_HCV = 66;
else if closest_zip = "01369" then RES_CODE_HCV = 66;
else if closest_zip = "01742" then RES_CODE_HCV = 67;
else if closest_zip = "01341" then RES_CODE_HCV = 68;
else if closest_zip = "01226" then RES_CODE_HCV = 70;
else if closest_zip = "01227" then RES_CODE_HCV = 70;
else if closest_zip = "01923" then RES_CODE_HCV = 71;
else if closest_zip = "01937" then RES_CODE_HCV = 71;
else if closest_zip = "02714" then RES_CODE_HCV = 72;
else if closest_zip = "02747" then RES_CODE_HCV = 72;
else if closest_zip = "02748" then RES_CODE_HCV = 72;
else if closest_zip = "02026" then RES_CODE_HCV = 73;
else if closest_zip = "02027" then RES_CODE_HCV = 73;
else if closest_zip = "01342" then RES_CODE_HCV = 74;
else if closest_zip = "02638" then RES_CODE_HCV = 75;
else if closest_zip = "02639" then RES_CODE_HCV = 75;
else if closest_zip = "02641" then RES_CODE_HCV = 75;
else if closest_zip = "02660" then RES_CODE_HCV = 75;
else if closest_zip = "02670" then RES_CODE_HCV = 75;
else if closest_zip = "02715" then RES_CODE_HCV = 76;
else if closest_zip = "02754" then RES_CODE_HCV = 76;
else if closest_zip = "02764" then RES_CODE_HCV = 76;
else if closest_zip = "01516" then RES_CODE_HCV = 77;
else if closest_zip = "02030" then RES_CODE_HCV = 78;
else if closest_zip = "01826" then RES_CODE_HCV = 79;
else if closest_zip = "01571" then RES_CODE_HCV = 80;
else if closest_zip = "01827" then RES_CODE_HCV = 81;
else if closest_zip = "02331" then RES_CODE_HCV = 82;
else if closest_zip = "02332" then RES_CODE_HCV = 82;
else if closest_zip = "02333" then RES_CODE_HCV = 83;
else if closest_zip = "02337" then RES_CODE_HCV = 83;
else if closest_zip = "01515" then RES_CODE_HCV = 84;
else if closest_zip = "01028" then RES_CODE_HCV = 85;
else if closest_zip = "02642" then RES_CODE_HCV = 86;
else if closest_zip = "02651" then RES_CODE_HCV = 86;
else if closest_zip = "01027" then RES_CODE_HCV = 87;
else if closest_zip = "02334" then RES_CODE_HCV = 88;
else if closest_zip = "02356" then RES_CODE_HCV = 88;
else if closest_zip = "02357" then RES_CODE_HCV = 88;
else if closest_zip = "02375" then RES_CODE_HCV = 88;
else if closest_zip = "02539" then RES_CODE_HCV = 89;
else if closest_zip = "01252" then RES_CODE_HCV = 90;
else if closest_zip = "01344" then RES_CODE_HCV = 91;
else if closest_zip = "01929" then RES_CODE_HCV = 92;
else if closest_zip = "02149" then RES_CODE_HCV = 93;
else if closest_zip = "02719" then RES_CODE_HCV = 94;
else if closest_zip = "02720" then RES_CODE_HCV = 95;
else if closest_zip = "02721" then RES_CODE_HCV = 95;
else if closest_zip = "02722" then RES_CODE_HCV = 95;
else if closest_zip = "02723" then RES_CODE_HCV = 95;
else if closest_zip = "02724" then RES_CODE_HCV = 95;
else if closest_zip = "02536" then RES_CODE_HCV = 96;
else if closest_zip = "02540" then RES_CODE_HCV = 96;
else if closest_zip = "02541" then RES_CODE_HCV = 96;
else if closest_zip = "02543" then RES_CODE_HCV = 96;
else if closest_zip = "02556" then RES_CODE_HCV = 96;
else if closest_zip = "02565" then RES_CODE_HCV = 96;
else if closest_zip = "02574" then RES_CODE_HCV = 96;
else if closest_zip = "01420" then RES_CODE_HCV = 97;
else if closest_zip = "01343" then RES_CODE_HCV = 98;
else if closest_zip = "02035" then RES_CODE_HCV = 99;
else if closest_zip = "01701" then RES_CODE_HCV = 100;
else if closest_zip = "01702" then RES_CODE_HCV = 100;
else if closest_zip = "01703" then RES_CODE_HCV = 100;
else if closest_zip = "01705" then RES_CODE_HCV = 100;
else if closest_zip = "02038" then RES_CODE_HCV = 101;
else if closest_zip = "02702" then RES_CODE_HCV = 102;
else if closest_zip = "02717" then RES_CODE_HCV = 102;
else if closest_zip = "01440" then RES_CODE_HCV = 103;
else if closest_zip = "01441" then RES_CODE_HCV = 103;
else if closest_zip = "02535" then RES_CODE_HCV = 104;
else if closest_zip = "01833" then RES_CODE_HCV = 105;
else if closest_zip = "01354" then RES_CODE_HCV = 106;
else if closest_zip = "01376" then RES_CODE_HCV = 192;
else if closest_zip = "01930" then RES_CODE_HCV = 107;
else if closest_zip = "01931" then RES_CODE_HCV = 107;
else if closest_zip = "01032" then RES_CODE_HCV = 108;
else if closest_zip = "01096" then RES_CODE_HCV = 108;
else if closest_zip = "02713" then RES_CODE_HCV = 109;
else if closest_zip = "01519" then RES_CODE_HCV = 110;
else if closest_zip = "01536" then RES_CODE_HCV = 110;
else if closest_zip = "01560" then RES_CODE_HCV = 110;
else if closest_zip = "01033" then RES_CODE_HCV = 111;
else if closest_zip = "01034" then RES_CODE_HCV = 112;
else if closest_zip = "01230" then RES_CODE_HCV = 113;
else if closest_zip = "01244" then RES_CODE_HCV = 203;
else if closest_zip = "01301" then RES_CODE_HCV = 114;
else if closest_zip = "01302" then RES_CODE_HCV = 114;
else if closest_zip = "01450" then RES_CODE_HCV = 115;
else if closest_zip = "01470" then RES_CODE_HCV = 115;
else if closest_zip = "01471" then RES_CODE_HCV = 115;
else if closest_zip = "01472" then RES_CODE_HCV = 115;
else if closest_zip = "01834" then RES_CODE_HCV = 116;
else if closest_zip = "01035" then RES_CODE_HCV = 117;
else if closest_zip = "02338" then RES_CODE_HCV = 118;
else if closest_zip = "01936" then RES_CODE_HCV = 119;
else if closest_zip = "01982" then RES_CODE_HCV = 119;
else if closest_zip = "01036" then RES_CODE_HCV = 120;
else if closest_zip = "01201" then RES_CODE_HCV = 121;
else if closest_zip = "02339" then RES_CODE_HCV = 122;
else if closest_zip = "02340" then RES_CODE_HCV = 122;
else if closest_zip = "02341" then RES_CODE_HCV = 123;
else if closest_zip = "02350" then RES_CODE_HCV = 123;
else if closest_zip = "01031" then RES_CODE_HCV = 124;
else if closest_zip = "01037" then RES_CODE_HCV = 124;
else if closest_zip = "01094" then RES_CODE_HCV = 124;
else if closest_zip = "01434" then RES_CODE_HCV = 125;
else if closest_zip = "01451" then RES_CODE_HCV = 125;
else if closest_zip = "01467" then RES_CODE_HCV = 125;
else if closest_zip = "02645" then RES_CODE_HCV = 126;
else if closest_zip = "02646" then RES_CODE_HCV = 126;
else if closest_zip = "02661" then RES_CODE_HCV = 126;
else if closest_zip = "02671" then RES_CODE_HCV = 126;
else if closest_zip = "01038" then RES_CODE_HCV = 127;
else if closest_zip = "01066" then RES_CODE_HCV = 127;
else if closest_zip = "01088" then RES_CODE_HCV = 127;
else if closest_zip = "01830" then RES_CODE_HCV = 128;
else if closest_zip = "01831" then RES_CODE_HCV = 128;
else if closest_zip = "01832" then RES_CODE_HCV = 128;
else if closest_zip = "01835" then RES_CODE_HCV = 128;
else if closest_zip = "01339" then RES_CODE_HCV = 128;
else if closest_zip = "01070" then RES_CODE_HCV = 129;
else if closest_zip = "01346" then RES_CODE_HCV = 130;
else if closest_zip = "02043" then RES_CODE_HCV = 131;
else if closest_zip = "02044" then RES_CODE_HCV = 131;
else if closest_zip = "01226" then RES_CODE_HCV = 132;
else if closest_zip = "02343" then RES_CODE_HCV = 133;
else if closest_zip = "01520" then RES_CODE_HCV = 134;
else if closest_zip = "01522" then RES_CODE_HCV = 134;
else if closest_zip = "01521" then RES_CODE_HCV = 135;
else if closest_zip = "01746" then RES_CODE_HCV = 136;
else if closest_zip = "01040" then RES_CODE_HCV = 137;
else if closest_zip = "01041" then RES_CODE_HCV = 137;
else if closest_zip = "01747" then RES_CODE_HCV = 138;
else if closest_zip = "01748" then RES_CODE_HCV = 139;
else if closest_zip = "01784" then RES_CODE_HCV = 139;
else if closest_zip = "01452" then RES_CODE_HCV = 140;
else if closest_zip = "01749" then RES_CODE_HCV = 141;
else if closest_zip = "02045" then RES_CODE_HCV = 142;
else if closest_zip = "01050" then RES_CODE_HCV = 143;
else if closest_zip = "01938" then RES_CODE_HCV = 144;
else if closest_zip = "02364" then RES_CODE_HCV = 145;
else if closest_zip = "02347" then RES_CODE_HCV = 146;
else if closest_zip = "01523" then RES_CODE_HCV = 147;
else if closest_zip = "01561" then RES_CODE_HCV = 147;
else if closest_zip = "01224" then RES_CODE_HCV = 148;
else if closest_zip = "01237" then RES_CODE_HCV = 148;
else if closest_zip = "01840" then RES_CODE_HCV = 149;
else if closest_zip = "01841" then RES_CODE_HCV = 149;
else if closest_zip = "01842" then RES_CODE_HCV = 149;
else if closest_zip = "01843" then RES_CODE_HCV = 149;
else if closest_zip = "01238" then RES_CODE_HCV = 150;
else if closest_zip = "01260" then RES_CODE_HCV = 150;
else if closest_zip = "01524" then RES_CODE_HCV = 151;
else if closest_zip = "01542" then RES_CODE_HCV = 151;
else if closest_zip = "01611" then RES_CODE_HCV = 151;
else if closest_zip = "01240" then RES_CODE_HCV = 152;
else if closest_zip = "01242" then RES_CODE_HCV = 152;
else if closest_zip = "01453" then RES_CODE_HCV = 153;
else if closest_zip = "01054" then RES_CODE_HCV = 154;
else if closest_zip = "02173" then RES_CODE_HCV = 155;
else if closest_zip = "02420" then RES_CODE_HCV = 155;
else if closest_zip = "02421" then RES_CODE_HCV = 155;
else if closest_zip = "01301" then RES_CODE_HCV = 156;
else if closest_zip = "01773" then RES_CODE_HCV = 157;
else if closest_zip = "01460" then RES_CODE_HCV = 158;
else if closest_zip = "01106" then RES_CODE_HCV = 159;
else if closest_zip = "01116" then RES_CODE_HCV = 159;
else if closest_zip = "01850" then RES_CODE_HCV = 160;
else if closest_zip = "01851" then RES_CODE_HCV = 160;
else if closest_zip = "01852" then RES_CODE_HCV = 160;
else if closest_zip = "01853" then RES_CODE_HCV = 160;
else if closest_zip = "01854" then RES_CODE_HCV = 160;
else if closest_zip = "01056" then RES_CODE_HCV = 161;
else if closest_zip = "01462" then RES_CODE_HCV = 162;
else if closest_zip = "01901" then RES_CODE_HCV = 163;
else if closest_zip = "01902" then RES_CODE_HCV = 163;
else if closest_zip = "01903" then RES_CODE_HCV = 163;
else if closest_zip = "01904" then RES_CODE_HCV = 163;
else if closest_zip = "01905" then RES_CODE_HCV = 163;
else if closest_zip = "01910" then RES_CODE_HCV = 163;
else if closest_zip = "01940" then RES_CODE_HCV = 164;
else if closest_zip = "02148" then RES_CODE_HCV = 165;
else if closest_zip = "01944" then RES_CODE_HCV = 166;
else if closest_zip = "02031" then RES_CODE_HCV = 167;
else if closest_zip = "02048" then RES_CODE_HCV = 167;
else if closest_zip = "01945" then RES_CODE_HCV = 168;
else if closest_zip = "01947" then RES_CODE_HCV = 168;
else if closest_zip = "02738" then RES_CODE_HCV = 169;
else if closest_zip = "01752" then RES_CODE_HCV = 170;
else if closest_zip = "02020" then RES_CODE_HCV = 171;
else if closest_zip = "02041" then RES_CODE_HCV = 171;
else if closest_zip = "02047" then RES_CODE_HCV = 264;
else if closest_zip = "02050" then RES_CODE_HCV = 171;
else if closest_zip = "02051" then RES_CODE_HCV = 171;
else if closest_zip = "02059" then RES_CODE_HCV = 171;
else if closest_zip = "02065" then RES_CODE_HCV = 171;
else if closest_zip = "02649" then RES_CODE_HCV = 172;
else if closest_zip = "02739" then RES_CODE_HCV = 173;
else if closest_zip = "01754" then RES_CODE_HCV = 174;
else if closest_zip = "02052" then RES_CODE_HCV = 175;
else if closest_zip = "02153" then RES_CODE_HCV = 176;
else if closest_zip = "02155" then RES_CODE_HCV = 176;
else if closest_zip = "02156" then RES_CODE_HCV = 176;
else if closest_zip = "02053" then RES_CODE_HCV = 177;
else if closest_zip = "02176" then RES_CODE_HCV = 178;
else if closest_zip = "02177" then RES_CODE_HCV = 178;
else if closest_zip = "01756" then RES_CODE_HCV = 179;
else if closest_zip = "01860" then RES_CODE_HCV = 180;
else if closest_zip = "01844" then RES_CODE_HCV = 181;
else if closest_zip = "02344" then RES_CODE_HCV = 182;
else if closest_zip = "02346" then RES_CODE_HCV = 182;
else if closest_zip = "02348" then RES_CODE_HCV = 182;
else if closest_zip = "02349" then RES_CODE_HCV = 182;
else if closest_zip = "01243" then RES_CODE_HCV = 183;
else if closest_zip = "01949" then RES_CODE_HCV = 184;
else if closest_zip = "01757" then RES_CODE_HCV = 185;
else if closest_zip = "01527" then RES_CODE_HCV = 186;
else if closest_zip = "01586" then RES_CODE_HCV = 186;
else if closest_zip = "02054" then RES_CODE_HCV = 187;
else if closest_zip = "01529" then RES_CODE_HCV = 188;
else if closest_zip = "02186" then RES_CODE_HCV = 189;
else if closest_zip = "02187" then RES_CODE_HCV = 189;
else if closest_zip = "01350" then RES_CODE_HCV = 190;
else if closest_zip = "01057" then RES_CODE_HCV = 191;
else if closest_zip = "01347" then RES_CODE_HCV = 192;
else if closest_zip = "01349" then RES_CODE_HCV = 192;
else if closest_zip = "01351" then RES_CODE_HCV = 192;
else if closest_zip = "01245" then RES_CODE_HCV = 193;
else if closest_zip = "01050" then RES_CODE_HCV = 194;
else if closest_zip = "01258" then RES_CODE_HCV = 195;
else if closest_zip = "01908" then RES_CODE_HCV = 196;
else if closest_zip = "02554" then RES_CODE_HCV = 197;
else if closest_zip = "02564" then RES_CODE_HCV = 197;
else if closest_zip = "02584" then RES_CODE_HCV = 197;
else if closest_zip = "01760" then RES_CODE_HCV = 198;
else if closest_zip = "02192" then RES_CODE_HCV = 199;
else if closest_zip = "02194" then RES_CODE_HCV = 199;
else if closest_zip = "02492" then RES_CODE_HCV = 199;
else if closest_zip = "02494" then RES_CODE_HCV = 199;
else if closest_zip = "01220" then RES_CODE_HCV = 200;
else if closest_zip = "02740" then RES_CODE_HCV = 201;
else if closest_zip = "02741" then RES_CODE_HCV = 201;
else if closest_zip = "02742" then RES_CODE_HCV = 201;
else if closest_zip = "02744" then RES_CODE_HCV = 201;
else if closest_zip = "02745" then RES_CODE_HCV = 201;
else if closest_zip = "02746" then RES_CODE_HCV = 201;
else if closest_zip = "01531" then RES_CODE_HCV = 202;
else if closest_zip = "01259" then RES_CODE_HCV = 203;
else if closest_zip = "01355" then RES_CODE_HCV = 204;
else if closest_zip = "01922" then RES_CODE_HCV = 205;
else if closest_zip = "01951" then RES_CODE_HCV = 205;
else if closest_zip = "01950" then RES_CODE_HCV = 206;
else if closest_zip = "02158" then RES_CODE_HCV = 207;
else if closest_zip = "02159" then RES_CODE_HCV = 207;
else if closest_zip = "02160" then RES_CODE_HCV = 207;
else if closest_zip = "02161" then RES_CODE_HCV = 207;
else if closest_zip = "02162" then RES_CODE_HCV = 207;
else if closest_zip = "02164" then RES_CODE_HCV = 207;
else if closest_zip = "02165" then RES_CODE_HCV = 207;
else if closest_zip = "02166" then RES_CODE_HCV = 207;
else if closest_zip = "02167" then RES_CODE_HCV = 207;
else if closest_zip = "02168" then RES_CODE_HCV = 207;
else if closest_zip = "02195" then RES_CODE_HCV = 207;
else if closest_zip = "02258" then RES_CODE_HCV = 207;
else if closest_zip = "02456" then RES_CODE_HCV = 207;
else if closest_zip = "02458" then RES_CODE_HCV = 207;
else if closest_zip = "02459" then RES_CODE_HCV = 207;
else if closest_zip = "02460" then RES_CODE_HCV = 207;
else if closest_zip = "02461" then RES_CODE_HCV = 207;
else if closest_zip = "02462" then RES_CODE_HCV = 207;
else if closest_zip = "02464" then RES_CODE_HCV = 207;
else if closest_zip = "02465" then RES_CODE_HCV = 207;
else if closest_zip = "02466" then RES_CODE_HCV = 207;
else if closest_zip = "02468" then RES_CODE_HCV = 207;
else if closest_zip = "02495" then RES_CODE_HCV = 207;
else if closest_zip = "02056" then RES_CODE_HCV = 208;
else if closest_zip = "01247" then RES_CODE_HCV = 209;
else if closest_zip = "01845" then RES_CODE_HCV = 210;
else if closest_zip = "02760" then RES_CODE_HCV = 211;
else if closest_zip = "02761" then RES_CODE_HCV = 211;
else if closest_zip = "02763" then RES_CODE_HCV = 211;
else if closest_zip = "02739" then RES_CODE_HCV = 211;
else if closest_zip = "01535" then RES_CODE_HCV = 212;
else if closest_zip = "01864" then RES_CODE_HCV = 213;
else if closest_zip = "01889" then RES_CODE_HCV = 213;
else if closest_zip = "01053" then RES_CODE_HCV = 214;
else if closest_zip = "01060" then RES_CODE_HCV = 214;
else if closest_zip = "01061" then RES_CODE_HCV = 214;
else if closest_zip = "01062" then RES_CODE_HCV = 214;
else if closest_zip = "01063" then RES_CODE_HCV = 214;
else if closest_zip = "01532" then RES_CODE_HCV = 215;
else if closest_zip = "01534" then RES_CODE_HCV = 216;
else if closest_zip = "01588" then RES_CODE_HCV = 216;
else if closest_zip = "01360" then RES_CODE_HCV = 217;
else if closest_zip = "02712" then RES_CODE_HCV = 218;
else if closest_zip = "02766" then RES_CODE_HCV = 218;
else if closest_zip = "02018" then RES_CODE_HCV = 219;
else if closest_zip = "02061" then RES_CODE_HCV = 219;
else if closest_zip = "02062" then RES_CODE_HCV = 220;
else if closest_zip = "02557" then RES_CODE_HCV = 221;
else if closest_zip = "01068" then RES_CODE_HCV = 222;
else if closest_zip = "01364" then RES_CODE_HCV = 223;
else if closest_zip = "02643" then RES_CODE_HCV = 224;
else if closest_zip = "02653" then RES_CODE_HCV = 224;
else if closest_zip = "02662" then RES_CODE_HCV = 223;
else if closest_zip = "01029" then RES_CODE_HCV = 225;
else if closest_zip = "01253" then RES_CODE_HCV = 225;
else if closest_zip = "01537" then RES_CODE_HCV = 226;
else if closest_zip = "01540" then RES_CODE_HCV = 226;
else if closest_zip = "01009" then RES_CODE_HCV = 227;
else if closest_zip = "01069" then RES_CODE_HCV = 227;
else if closest_zip = "01079" then RES_CODE_HCV = 227;
else if closest_zip = "01080" then RES_CODE_HCV = 227;
else if closest_zip = "01612" then RES_CODE_HCV = 228;
else if closest_zip = "01960" then RES_CODE_HCV = 229;
else if closest_zip = "01961" then RES_CODE_HCV = 229;
else if closest_zip = "01964" then RES_CODE_HCV = 229;
else if closest_zip = "01002" then RES_CODE_HCV = 230;
else if closest_zip = "02327" then RES_CODE_HCV = 231;
else if closest_zip = "02358" then RES_CODE_HCV = 231;
else if closest_zip = "02359" then RES_CODE_HCV = 231;
else if closest_zip = "01463" then RES_CODE_HCV = 232;
else if closest_zip = "01235" then RES_CODE_HCV = 233;
else if closest_zip = "01366" then RES_CODE_HCV = 234;
else if closest_zip = "01201" then RES_CODE_HCV = 236;
else if closest_zip = "01202" then RES_CODE_HCV = 236;
else if closest_zip = "01203" then RES_CODE_HCV = 236;
else if closest_zip = "01070" then RES_CODE_HCV = 237;
else if closest_zip = "02762" then RES_CODE_HCV = 238;
else if closest_zip = "02345" then RES_CODE_HCV = 239;
else if closest_zip = "02360" then RES_CODE_HCV = 239;
else if closest_zip = "02361" then RES_CODE_HCV = 239;
else if closest_zip = "02362" then RES_CODE_HCV = 239;
else if closest_zip = "02363" then RES_CODE_HCV = 239;
else if closest_zip = "02381" then RES_CODE_HCV = 239;
else if closest_zip = "02367" then RES_CODE_HCV = 240;
else if closest_zip = "01517" then RES_CODE_HCV = 241;
else if closest_zip = "01541" then RES_CODE_HCV = 241;
else if closest_zip = "02657" then RES_CODE_HCV = 242;
else if closest_zip = "02169" then RES_CODE_HCV = 243;
else if closest_zip = "02170" then RES_CODE_HCV = 243;
else if closest_zip = "02171" then RES_CODE_HCV = 243;
else if closest_zip = "02269" then RES_CODE_HCV = 243;
else if closest_zip = "02368" then RES_CODE_HCV = 244;
else if closest_zip = "02767" then RES_CODE_HCV = 245;
else if closest_zip = "02768" then RES_CODE_HCV = 245;
else if closest_zip = "01867" then RES_CODE_HCV = 246;
else if closest_zip = "02769" then RES_CODE_HCV = 247;
else if closest_zip = "02151" then RES_CODE_HCV = 248;
else if closest_zip = "01254" then RES_CODE_HCV = 249;
else if closest_zip = "02770" then RES_CODE_HCV = 250;
else if closest_zip = "02370" then RES_CODE_HCV = 251;
else if closest_zip = "01966" then RES_CODE_HCV = 252;
else if closest_zip = "01367" then RES_CODE_HCV = 253;
else if closest_zip = "01969" then RES_CODE_HCV = 254;
else if closest_zip = "01368" then RES_CODE_HCV = 255;
else if closest_zip = "01071" then RES_CODE_HCV = 256;
else if closest_zip = "01097" then RES_CODE_HCV = 256;
else if closest_zip = "01543" then RES_CODE_HCV = 257;
else if closest_zip = "01970" then RES_CODE_HCV = 258;
else if closest_zip = "01971" then RES_CODE_HCV = 258;
else if closest_zip = "01952" then RES_CODE_HCV = 259;
else if closest_zip = "01255" then RES_CODE_HCV = 260;
else if closest_zip = "02537" then RES_CODE_HCV = 261;
else if closest_zip = "02542" then RES_CODE_HCV = 261;
else if closest_zip = "02563" then RES_CODE_HCV = 261;
else if closest_zip = "02644" then RES_CODE_HCV = 261;
else if closest_zip = "01906" then RES_CODE_HCV = 262;
else if closest_zip = "01256" then RES_CODE_HCV = 263;
else if closest_zip = "02040" then RES_CODE_HCV = 264;
else if closest_zip = "02055" then RES_CODE_HCV = 264;
else if closest_zip = "02060" then RES_CODE_HCV = 264;
else if closest_zip = "02066" then RES_CODE_HCV = 264;
else if closest_zip = "02771" then RES_CODE_HCV = 265;
else if closest_zip = "02067" then RES_CODE_HCV = 266;
else if closest_zip = "01222" then RES_CODE_HCV = 267;
else if closest_zip = "01257" then RES_CODE_HCV = 267;
else if closest_zip = "01370" then RES_CODE_HCV = 268;
else if closest_zip = "01770" then RES_CODE_HCV = 269;
else if closest_zip = "01464" then RES_CODE_HCV = 270;
else if closest_zip = "01545" then RES_CODE_HCV = 271;
else if closest_zip = "01546" then RES_CODE_HCV = 271;
else if closest_zip = "01072" then RES_CODE_HCV = 272;
else if closest_zip = "02725" then RES_CODE_HCV = 273;
else if closest_zip = "02726" then RES_CODE_HCV = 273;
else if closest_zip = "02143" then RES_CODE_HCV = 274;
else if closest_zip = "02144" then RES_CODE_HCV = 274;
else if closest_zip = "02145" then RES_CODE_HCV = 274;
else if closest_zip = "01075" then RES_CODE_HCV = 275;
else if closest_zip = "01073" then RES_CODE_HCV = 276;
else if closest_zip = "01745" then RES_CODE_HCV = 277;
else if closest_zip = "01772" then RES_CODE_HCV = 277;
else if closest_zip = "01550" then RES_CODE_HCV = 278;
else if closest_zip = "01077" then RES_CODE_HCV = 279;
else if closest_zip = "01562" then RES_CODE_HCV = 280;
else if closest_zip = "01101" then RES_CODE_HCV = 281;
else if closest_zip = "01102" then RES_CODE_HCV = 281;
else if closest_zip = "01103" then RES_CODE_HCV = 281;
else if closest_zip = "01104" then RES_CODE_HCV = 281;
else if closest_zip = "01105" then RES_CODE_HCV = 281;
else if closest_zip = "01107" then RES_CODE_HCV = 281;
else if closest_zip = "01108" then RES_CODE_HCV = 281;
else if closest_zip = "01109" then RES_CODE_HCV = 281;
else if closest_zip = "01111" then RES_CODE_HCV = 281;
else if closest_zip = "01114" then RES_CODE_HCV = 281;
else if closest_zip = "01115" then RES_CODE_HCV = 281;
else if closest_zip = "01118" then RES_CODE_HCV = 281;
else if closest_zip = "01119" then RES_CODE_HCV = 281;
else if closest_zip = "01128" then RES_CODE_HCV = 281;
else if closest_zip = "01129" then RES_CODE_HCV = 281;
else if closest_zip = "01133" then RES_CODE_HCV = 281;
else if closest_zip = "01138" then RES_CODE_HCV = 281;
else if closest_zip = "01139" then RES_CODE_HCV = 281;
else if closest_zip = "01144" then RES_CODE_HCV = 281;
else if closest_zip = "01151" then RES_CODE_HCV = 281;
else if closest_zip = "01152" then RES_CODE_HCV = 281;
else if closest_zip = "01199" then RES_CODE_HCV = 281;
else if closest_zip = "01564" then RES_CODE_HCV = 282;
else if closest_zip = "01229" then RES_CODE_HCV = 283;
else if closest_zip = "01262" then RES_CODE_HCV = 283;
else if closest_zip = "01263" then RES_CODE_HCV = 283;
else if closest_zip = "02180" then RES_CODE_HCV = 284;
else if closest_zip = "02072" then RES_CODE_HCV = 285;
else if closest_zip = "01775" then RES_CODE_HCV = 286;
else if closest_zip = "01518" then RES_CODE_HCV = 287;
else if closest_zip = "01566" then RES_CODE_HCV = 287;
else if closest_zip = "01776" then RES_CODE_HCV = 288;
else if closest_zip = "01375" then RES_CODE_HCV = 289;
else if closest_zip = "01526" then RES_CODE_HCV = 290;
else if closest_zip = "01590" then RES_CODE_HCV = 290;
else if closest_zip = "01907" then RES_CODE_HCV = 291;
else if closest_zip = "02777" then RES_CODE_HCV = 292;
else if closest_zip = "02718" then RES_CODE_HCV = 293;
else if closest_zip = "02780" then RES_CODE_HCV = 293;
else if closest_zip = "01436" then RES_CODE_HCV = 294;
else if closest_zip = "01438" then RES_CODE_HCV = 294;
else if closest_zip = "01468" then RES_CODE_HCV = 294;
else if closest_zip = "01876" then RES_CODE_HCV = 295;
else if closest_zip = "02568" then RES_CODE_HCV = 296;
else if closest_zip = "02573" then RES_CODE_HCV = 296;
else if closest_zip = "01983" then RES_CODE_HCV = 298;
else if closest_zip = "01469" then RES_CODE_HCV = 299;
else if closest_zip = "01474" then RES_CODE_HCV = 299;
else if closest_zip = "02652" then RES_CODE_HCV = 300;
else if closest_zip = "02666" then RES_CODE_HCV = 300;
else if closest_zip = "01879" then RES_CODE_HCV = 301;
else if closest_zip = "01264" then RES_CODE_HCV = 302;
else if closest_zip = "01568" then RES_CODE_HCV = 303;
else if closest_zip = "01525" then RES_CODE_HCV = 304;
else if closest_zip = "01538" then RES_CODE_HCV = 304;
else if closest_zip = "01569" then RES_CODE_HCV = 304;
else if closest_zip = "01880" then RES_CODE_HCV = 305;
else if closest_zip = "01081" then RES_CODE_HCV = 306;
else if closest_zip = "02032" then RES_CODE_HCV = 307;
else if closest_zip = "02071" then RES_CODE_HCV = 307;
else if closest_zip = "02081" then RES_CODE_HCV = 307;
else if closest_zip = "02154" then RES_CODE_HCV = 308;
else if closest_zip = "02254" then RES_CODE_HCV = 308;
else if closest_zip = "02451" then RES_CODE_HCV = 308;
else if closest_zip = "02452" then RES_CODE_HCV = 308;
else if closest_zip = "02453" then RES_CODE_HCV = 308;
else if closest_zip = "02454" then RES_CODE_HCV = 308;
else if closest_zip = "02455" then RES_CODE_HCV = 308;
else if closest_zip = "01082" then RES_CODE_HCV = 309;
else if closest_zip = "02538" then RES_CODE_HCV = 310;
else if closest_zip = "02558" then RES_CODE_HCV = 310;
else if closest_zip = "02571" then RES_CODE_HCV = 310;
else if closest_zip = "02576" then RES_CODE_HCV = 310;
else if closest_zip = "01083" then RES_CODE_HCV = 311;
else if closest_zip = "01092" then RES_CODE_HCV = 311;
else if closest_zip = "01378" then RES_CODE_HCV = 312;
else if closest_zip = "01223" then RES_CODE_HCV = 313;
else if closest_zip = "02172" then RES_CODE_HCV = 314;
else if closest_zip = "02272" then RES_CODE_HCV = 314;
else if closest_zip = "02277" then RES_CODE_HCV = 314;
else if closest_zip = "02471" then RES_CODE_HCV = 314;
else if closest_zip = "02472" then RES_CODE_HCV = 314;
else if closest_zip = "01778" then RES_CODE_HCV = 315;
else if closest_zip = "01570" then RES_CODE_HCV = 316;
else if closest_zip = "02157" then RES_CODE_HCV = 317;
else if closest_zip = "02181" then RES_CODE_HCV = 317;
else if closest_zip = "02457" then RES_CODE_HCV = 317;
else if closest_zip = "02481" then RES_CODE_HCV = 317;
else if closest_zip = "02482" then RES_CODE_HCV = 317;
else if closest_zip = "02663" then RES_CODE_HCV = 318;
else if closest_zip = "02667" then RES_CODE_HCV = 318;
else if closest_zip = "01379" then RES_CODE_HCV = 319;
else if closest_zip = "01380" then RES_CODE_HCV = 319;
else if closest_zip = "01984" then RES_CODE_HCV = 320;
else if closest_zip = "01539" then RES_CODE_HCV = 321;
else if closest_zip = "01583" then RES_CODE_HCV = 321;
else if closest_zip = "02379" then RES_CODE_HCV = 322;
else if closest_zip = "01585" then RES_CODE_HCV = 323;
else if closest_zip = "01985" then RES_CODE_HCV = 324;
else if closest_zip = "01089" then RES_CODE_HCV = 113;
else if closest_zip = "01090" then RES_CODE_HCV = 113;
else if closest_zip = "01236" then RES_CODE_HCV = 325;
else if closest_zip = "01266" then RES_CODE_HCV = 326;
else if closest_zip = "02575" then RES_CODE_HCV = 327;
else if closest_zip = "01580" then RES_CODE_HCV = 328;
else if closest_zip = "01581" then RES_CODE_HCV = 328;
else if closest_zip = "01582" then RES_CODE_HCV = 328;
else if closest_zip = "01085" then RES_CODE_HCV = 329;
else if closest_zip = "01086" then RES_CODE_HCV = 329;
else if closest_zip = "01886" then RES_CODE_HCV = 330;
else if closest_zip = "01027" then RES_CODE_HCV = 331;
else if closest_zip = "01473" then RES_CODE_HCV = 332;
else if closest_zip = "02193" then RES_CODE_HCV = 333;
else if closest_zip = "02493" then RES_CODE_HCV = 333;
else if closest_zip = "02790" then RES_CODE_HCV = 334;
else if closest_zip = "02791" then RES_CODE_HCV = 334;
else if closest_zip = "02090" then RES_CODE_HCV = 335;
else if closest_zip = "02188" then RES_CODE_HCV = 336;
else if closest_zip = "02189" then RES_CODE_HCV = 336;
else if closest_zip = "02190" then RES_CODE_HCV = 336;
else if closest_zip = "02191" then RES_CODE_HCV = 336;
else if closest_zip = "01093" then RES_CODE_HCV = 337;
else if closest_zip = "01373" then RES_CODE_HCV = 337;
else if closest_zip = "02382" then RES_CODE_HCV = 338;
else if closest_zip = "01095" then RES_CODE_HCV = 339;
else if closest_zip = "01039" then RES_CODE_HCV = 340;
else if closest_zip = "01267" then RES_CODE_HCV = 341;
else if closest_zip = "01887" then RES_CODE_HCV = 342;
else if closest_zip = "01475" then RES_CODE_HCV = 343;
else if closest_zip = "01477" then RES_CODE_HCV = 343;
else if closest_zip = "01890" then RES_CODE_HCV = 344;
else if closest_zip = "01270" then RES_CODE_HCV = 345;
else if closest_zip = "02152" then RES_CODE_HCV = 346;
else if closest_zip = "01801" then RES_CODE_HCV = 347;
else if closest_zip = "01806" then RES_CODE_HCV = 347;
else if closest_zip = "01807" then RES_CODE_HCV = 347;
else if closest_zip = "01808" then RES_CODE_HCV = 347;
else if closest_zip = "01813" then RES_CODE_HCV = 347;
else if closest_zip = "01814" then RES_CODE_HCV = 347;
else if closest_zip = "01815" then RES_CODE_HCV = 347;
else if closest_zip = "01888" then RES_CODE_HCV = 347;
else if closest_zip = "01601" then RES_CODE_HCV = 348;
else if closest_zip = "01602" then RES_CODE_HCV = 348;
else if closest_zip = "01603" then RES_CODE_HCV = 348;
else if closest_zip = "01604" then RES_CODE_HCV = 348;
else if closest_zip = "01605" then RES_CODE_HCV = 348;
else if closest_zip = "01606" then RES_CODE_HCV = 348;
else if closest_zip = "01607" then RES_CODE_HCV = 348;
else if closest_zip = "01608" then RES_CODE_HCV = 348;
else if closest_zip = "01609" then RES_CODE_HCV = 348;
else if closest_zip = "01610" then RES_CODE_HCV = 348;
else if closest_zip = "01613" then RES_CODE_HCV = 348;
else if closest_zip = "01614" then RES_CODE_HCV = 348;
else if closest_zip = "01615" then RES_CODE_HCV = 348;
else if closest_zip = "01653" then RES_CODE_HCV = 348;
else if closest_zip = "01654" then RES_CODE_HCV = 348;
else if closest_zip = "01655" then RES_CODE_HCV = 348;
else if closest_zip = "01098" then RES_CODE_HCV = 349;
else if closest_zip = "02070" then RES_CODE_HCV = 350;
else if closest_zip = "02093" then RES_CODE_HCV = 350;
else if closest_zip = "02664" then RES_CODE_HCV = 351;
else if closest_zip = "02673" then RES_CODE_HCV = 351;
else if closest_zip = "02675" then RES_CODE_HCV = 351;
else if missing(closest_zip) then RES_CODE_HCV  = 999;
    end;
run;

data FINAL_COHORT;
   set FINAL_COHORT;
	if RES_CODE_HCV in (1,2,3,5,7,8,9,10,14,16,17,18,20,23,25,26,30,31,
	32,35,36,40,42,44,46,48,49,50,52,56,57,61,65,67,71,72,73,75,79,
	80,82,83,85,87,88,93,94,95,96,97,99,100,101,103,105,107,110,115,
	116,119,122,123,126,128,131,133,134,136,137,138,139,141,142,144,
	145,146,149,151,153,155,158,159,160,161,162,163,164,165,166,167,
	168,170,171,172,174,175,176,177,178,180,181,182,184,185,186,187,
	188,189,196,198,199,201,206,207,208,210,211,213,214,215,216,218,
	219,220,226,229,231,232,236,238,239,243,244,245,246,248,251,252,
	258,259,261,262,264,265,266,271,273,274,275,277,278,280,281,284,
	285,288,291,292,293,295,298,301,304,305,307,308,310,314,315,316,
	317,320,321,325,328,329,330,333,334,335,336,338,339,342,344,
	346,347,348,350,351) then rural=0;
	
	else if RES_CODE_HCV in (4,11,12,13,19,21,22,24,27,28,33,34,37,38,39,
	41,43,45,51,54,55,58,59,60,64,68,69,70,74,76,77,78,81,84,86,92,
	102,108,111,112,117,118,120,125,127,132,135,140,143,147,148,154,
	157,169,173,179,183,191,194,200,205,212,222,224,227,228,230,240,
	241,247,249,250,254,255,256,257,263,269,270,272,276,279,282,286,
	287,289,290,294,297,299,303,306,309,311,313,322,323,324,331,332,
	337,340, 343,345,349) then rural =1;
	
	else if RES_CODE_HCV in (6,104,15,29,47,53,62,63,66,89,90,91,98,106,
	109,113,114,121,124,129,130,150,152,156,190,192,193,195,197,202,
	203,204,209,217,221,223,225,233,234,235,237,242,253,260,267,268,
	283,296,300,302,312,318,319,326,327,341) then rural =2;
run;

data FINAL_COHORT;
    set FINAL_COHORT;
    if rural = 0 then rural_group = 'Urban';
    else if rural = 1 then rural_group = 'Rural';
    else if rural = 2 then rural_group = 'Rural';
    else rural_group = 'Unknown';
run;

data FINAL_COHORT;
    length HOMELESS_HISTORY_GROUP $10;
    set FINAL_COHORT;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

data FINAL_COHORT;
    length LANGUAGE_SPOKEN_GROUP $30;
    set FINAL_COHORT;
    if LANGUAGE = 1 then LANGUAGE_SPOKEN_GROUP = 'English';
    else if LANGUAGE = 2 then LANGUAGE_SPOKEN_GROUP = 'English and Another Language';
    else if LANGUAGE = 3 then LANGUAGE_SPOKEN_GROUP = 'Another Language';
    else LANGUAGE_SPOKEN_GROUP = 'Refused or Unknown';
run;

data FINAL_COHORT;
    length EDUCATION_GROUP $30;
    set FINAL_COHORT;
    if EDUCATION = 1 then EDUCATION_GROUP = 'HS or less';
    else if EDUCATION = 2 then EDUCATION_GROUP = '13+ years';
    else EDUCATION_GROUP = 'Other or Unknown';
run;

data FINAL_COHORT;
    set FINAL_COHORT;
    if EVER_IDU_HCV_MAT = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;

/* ================================================= */
/* 6. EXPLORATORY TABLES AND SUM STATS, OUD Cohort   */
/* ================================================= */

proc means data=FINAL_COHORT;
    var oud_age;
    where oud_age ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc means data=FINAL_COHORT;
    var AGE_HCV;
    where AGE_HCV ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc means data=FINAL_COHORT;
    var AGE_BIRTH;
    where AGE_BIRTH ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

/* ================================= */
/* 7. TABLE 1, OUD Cohort            */
/* ================================= */

%macro Table1Freqs(var, format);
    title "Table 1, OUD Cohort, Unstratified";
    proc freq data=FINAL_COHORT;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY_GROUP);
%Table1Freqs(LANGUAGE_SPOKEN_GROUP);
%Table1Freqs(EDUCATION_GROUP);
%Table1Freqs(FOREIGN_BORN, fbornf.);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(HCV_DIAG, flagf.);
%Table1Freqs(EVER_IDU_HCV_MAT, flagf.);
%Table1Freqs(mental_health_diag, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(OCCUPATION_CODE, flagf.);
%Table1Freqs(EVER_MOUD, flagf.);
%Table1Freqs(INSURANCE_CAT);
/* %Table1Freqs(LD_PAY, ld_pay_fmt.);
%Table1Freqs(KOTELCHUCK);
%Table1Freqs(prenat_site); */
%Table1Freqs(rural_group);

/* ==================================== */
/* 8. RESTRICT TO CONFIRMED HEPC CASES  */
/* ==================================== */

data FINAL_HCV_COHORT;
    set FINAL_COHORT;
    where CONFIRMED_HCV_INDICATOR = 1;
run;

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FINAL_HCV_COHORT;
QUIT;

%put Number of unique IDs in FINAL_HCV_COHORT table: &num_unique_ids;

/* ================================================= */
/* 9. EXPLORATORY TABLES AND SUM STATS, HCV Cohort   */
/* ================================================= */

proc means data=FINAL_HCV_COHORT;
    var oud_age;
    where oud_age ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc means data=FINAL_HCV_COHORT;
    var AGE_HCV;
    where AGE_HCV ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc means data=FINAL_HCV_COHORT;
    var AGE_BIRTH;
    where AGE_BIRTH ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

data FINAL_HCV_COHORT;
	set FINAL_HCV_COHORT;
	AGE_HCV  = put(AGE_HCV, age_grps_five.);
run;

DATA FINAL_HCV_COHORT;
  SET FINAL_HCV_COHORT;
    AGE_HCV_GRP = INPUT(AGE_HCV, best12.);
RUN;

/* ================================= */
/* 10. TABLES 1 AND 2, HCV Cohort    */
/* ================================= */

%macro Table1Freqs(var, format);
    title "Table 1, HCV Cohort, Unstratified";
    proc freq data=FINAL_HCV_COHORT;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs(AGE_HCV_GRP, age_grps.);
%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY_GROUP);
%Table1Freqs(LANGUAGE_SPOKEN_GROUP);
%Table1Freqs(EDUCATION_GROUP);
%Table1Freqs(FOREIGN_BORN, fbornf.);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(HCV_DIAG, flagf.);
%Table1Freqs(EVER_IDU_HCV_MAT, flagf.);
%Table1Freqs(mental_health_diag, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(OCCUPATION_CODE, flagf.);
%Table1Freqs(EVER_MOUD, flagf.);
%Table1Freqs(INSURANCE_CAT);
/* %Table1Freqs(LD_PAY, ld_pay_fmt.);
%Table1Freqs(KOTELCHUCK, kotel_fmt.);
%Table1Freqs(prenat_site, prenat_site_fmt.); */
%Table1Freqs(rural_group);
%Table1Freqs(EVENT_YEAR_HCV);

%macro Table1Freqs(var, format);

    proc sort data=FINAL_HCV_COHORT;
        by HCV_PRIMARY_DIAG;
    run;
    
    title "Table 1, HCV Cohort, Stratified by HCV_PRIMARY_DIAG";
    proc freq data=FINAL_HCV_COHORT;
        by HCV_PRIMARY_DIAG;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs(AGE_HCV_GRP, age_grps.);
%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY_GROUP);
%Table1Freqs(LANGUAGE_SPOKEN_GROUP);
%Table1Freqs(EDUCATION_GROUP);
%Table1Freqs(FOREIGN_BORN, fbornf.);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(HCV_DIAG, flagf.);
%Table1Freqs(EVER_IDU_HCV_MAT, flagf.);
%Table1Freqs(mental_health_diag, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(OCCUPATION_CODE, flagf.);
%Table1Freqs(EVER_MOUD, flagf.);
%Table1Freqs(INSURANCE_CAT);
/* %Table1Freqs(LD_PAY, ld_pay_fmt.);
%Table1Freqs(KOTELCHUCK);
%Table1Freqs(prenat_site); */
%Table1Freqs(rural_group);
%Table1Freqs(EVENT_YEAR_HCV);

%macro Table1Freqs(var, format);

    proc sort data=FINAL_HCV_COHORT;
        by DAA_START_INDICATOR;
    run;
    
    title "Table 1, HCV Cohort, Stratified by DAA_START_INDICATOR";
    proc freq data=FINAL_HCV_COHORT;
        by DAA_START_INDICATOR;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs(AGE_HCV_GRP, age_grps.);
%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY_GROUP);
%Table1Freqs(LANGUAGE_SPOKEN_GROUP);
%Table1Freqs(EDUCATION_GROUP);
%Table1Freqs(FOREIGN_BORN, fbornf.);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(HCV_DIAG, flagf.);
%Table1Freqs(EVER_IDU_HCV_MAT, flagf.);
%Table1Freqs(mental_health_diag, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(OCCUPATION_CODE, flagf.);
%Table1Freqs(EVER_MOUD, flagf.);
%Table1Freqs(INSURANCE_CAT);
/* %Table1Freqs(LD_PAY, ld_pay_fmt.);
%Table1Freqs(KOTELCHUCK);
%Table1Freqs(prenat_site); */
%Table1Freqs(rural_group);
%Table1Freqs(EVENT_YEAR_HCV);

%macro Table2Linkage(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_HCV_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model HCV_PRIMARY_DIAG(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2Linkage(AGE_HCV_GRP, ref ='3');
%Table2Linkage(FINAL_RE, ref ='1');
%Table2Linkage(EVER_INCARCERATED, ref ='0');
%Table2Linkage(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2Linkage(LANGUAGE_SPOKEN_GROUP, ref = 'English');
%Table2Linkage(EDUCATION_GROUP, ref ='HS or less');
%Table2Linkage(FOREIGN_BORN, ref ='0');
%Table2Linkage(HIV_DIAG, ref ='0');
%Table2Linkage(HCV_DIAG, ref ='0');
%Table2Linkage(EVER_IDU_HCV_MAT, ref ='0');
%Table2Linkage(mental_health_diag, ref ='0');
%Table2Linkage(OTHER_SUBSTANCE_USE, ref ='0');
%Table2Linkage(iji_diag, ref ='0');
%Table2Linkage(IDU_EVIDENCE, ref ='0');
%Table2Linkage(OCCUPATION_CODE, ref ='0');
%Table2Linkage(EVER_MOUD, ref ='0');
%Table2Linkage(INSURANCE_CAT, ref ='Medicaid');
/* %Table2Linkage(LD_PAY, ref ='1');
%Table2Linkage(KOTELCHUCK, ref ='3');
%Table2Linkage(prenat_site, ref ='1'); */
%Table2Linkage(rural_group, ref ='Urban');
%Table2Linkage(EVENT_YEAR_HCV, ref ='2014');

%macro Table2Treatment(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_HCV_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model DAA_START_INDICATOR(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2Treatment(AGE_HCV_GRP, ref ='3');
%Table2Treatment(FINAL_RE, ref ='1');
%Table2Treatment(EVER_INCARCERATED, ref ='0');
%Table2Treatment(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2Treatment(LANGUAGE_SPOKEN_GROUP, ref='English');
%Table2Treatment(EDUCATION_GROUP, ref ='HS or less');
%Table2Treatment(FOREIGN_BORN, ref ='0');
%Table2Treatment(HIV_DIAG, ref ='0');
%Table2Treatment(HCV_DIAG, ref ='0');
%Table2Treatment(EVER_IDU_HCV_MAT, ref ='0');
%Table2Treatment(mental_health_diag, ref ='0');
%Table2Treatment(OTHER_SUBSTANCE_USE, ref ='0');
%Table2Treatment(iji_diag, ref ='0');
%Table2Treatment(IDU_EVIDENCE, ref ='0');
%Table2Treatment(OCCUPATION_CODE, ref ='0');
%Table2Treatment(EVER_MOUD, ref ='0');
%Table2Treatment(INSURANCE_CAT, ref ='Medicaid');
/* %Table2Treatment(LD_PAY, ref ='1');
%Table2Treatment(KOTELCHUCK, ref ='3');
%Table2Treatment(prenat_site, ref ='1'); */
%Table2Treatment(rural_group, ref ='Urban');
%Table2Treatment(EVENT_YEAR_HCV, ref ='2014');
title;

data FINAL_HCV_COHORT_FILT;
    set FINAL_HCV_COHORT;
    if FINAL_RE NE 9 and EDUCATION_GROUP NE 'Other or Unknown' and HOMELESS_HISTORY_GROUP NE 'Unknown' and INSURANCE_CAT NE 'Other/Missing';
run;

proc glimmix data=FINAL_HCV_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') EVER_MOUD (ref='0') IDU_EVIDENCE (ref='0') mental_health_diag (ref='0') OTHER_SUBSTANCE_USE (ref='0') EDUCATION_GROUP (ref='HS or less') HOMELESS_HISTORY_GROUP (ref='No') EVENT_YEAR_HCV (ref='2014');
    model HCV_PRIMARY_DIAG(event='1') = FINAL_RE INSURANCE_CAT EVER_MOUD IDU_EVIDENCE mental_health_diag OTHER_SUBSTANCE_USE EDUCATION_GROUP HOMELESS_HISTORY_GROUP EVENT_YEAR_HCV / dist=binary link=logit solution oddsratio;
run;

proc glimmix data=FINAL_HCV_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') EVER_MOUD (ref='0') IDU_EVIDENCE (ref='0') EDUCATION_GROUP (ref='HS or less') HOMELESS_HISTORY_GROUP (ref='No') EVER_INCARCERATED (ref='0') mental_health_diag (ref='0');
    model DAA_START_INDICATOR(event='1') = FINAL_RE INSURANCE_CAT EVER_MOUD IDU_EVIDENCE EDUCATION_GROUP HOMELESS_HISTORY_GROUP EVER_INCARCERATED mental_health_diag / dist=binary link=logit solution oddsratio;
run;
title;

/* ==================================================================== */
/* Part 4: Calculate Linkage to Care and DAA Treatment Initiation Rates */
/* ==================================================================== */

/* =============================================== */
/* 1. Compile births and define pregnancy periods  */
/* =============================================== */
/* Extract relevant birth and infant records for the specified years and merge maternal and infant data based on birth link ID. 
Then, determine pregnancy start and end dates based on gestational age and flag monthly pregnancy and post-partum states */

data all_births;
    set PHDBIRTH.BIRTH_MOM (keep = ID BIRTH_LINK_ID MONTH_BIRTH YEAR_BIRTH where=(YEAR_BIRTH IN &year));
run;

data infants;
    set PHDBIRTH.BIRTH_INFANT (keep = ID BIRTH_LINK_ID GESTATIONAL_AGE);
run;

proc sql;
    create table merged_births_infants as
    select 
        a.ID as MATERNAL_ID,
        a.BIRTH_LINK_ID,
        a.MONTH_BIRTH,
        a.YEAR_BIRTH,
        b.ID as INFANT_ID,
        b.GESTATIONAL_AGE
    from all_births as a
    left join infants as b
    on a.BIRTH_LINK_ID = b.BIRTH_LINK_ID;
quit;

data fetal_deaths_renamed;
    set PHDFETAL.FETALDEATH;
    rename ID = MATERNAL_ID
           GESTATIONAL_AGE_FD = GESTATIONAL_AGE
           FETAL_DEATH_MONTH = MONTH_BIRTH
           FETAL_DEATH_YEAR = YEAR_BIRTH
           MOTHER_AGE_FD = AGE_BIRTH;
run;

proc sql;
    create table merged_births_infants as
    select 
        a.MATERNAL_ID, 
        a.MONTH_BIRTH, 
        a.YEAR_BIRTH, 
        a.GESTATIONAL_AGE
    from merged_births_infants as a
    union all
    select 
        put(b.MATERNAL_ID, $10.), 
        b.MONTH_BIRTH, 
        b.YEAR_BIRTH,
        b.GESTATIONAL_AGE
    from fetal_deaths_renamed as b;
quit;

data pregnancy_flags;
    set merged_births_infants; 
    length month year flag 8;
        
    if GESTATIONAL_AGE => 39 then pregnancy_months = 9;
    else if GESTATIONAL_AGE >= 35 and GESTATIONAL_AGE <= 38 then pregnancy_months = 8;
    else if GESTATIONAL_AGE >= 31 and GESTATIONAL_AGE <= 34 then pregnancy_months = 7;
    else if GESTATIONAL_AGE >= 26 and GESTATIONAL_AGE <= 30 then pregnancy_months = 6;
    else if GESTATIONAL_AGE >= 22 and GESTATIONAL_AGE <= 25 then pregnancy_months = 5;
    else if GESTATIONAL_AGE >= 18 and GESTATIONAL_AGE <= 21 then pregnancy_months = 4;
    else if GESTATIONAL_AGE >= 13 and GESTATIONAL_AGE <= 17 then pregnancy_months = 3;
    else if GESTATIONAL_AGE >= 9 and GESTATIONAL_AGE <= 12 then pregnancy_months = 2;
    else pregnancy_months = 1;
        
    pregnancy_start_month = MONTH_BIRTH - pregnancy_months + 1;
    pregnancy_start_year = YEAR_BIRTH;
    if pregnancy_start_month <= 0 then do;
        pregnancy_start_year = YEAR_BIRTH - 1;
        pregnancy_start_month = 12 + pregnancy_start_month;
    end;

    pregnancy_end_month = MONTH_BIRTH;
    pregnancy_end_year = YEAR_BIRTH;

    month = pregnancy_start_month;
    year = pregnancy_start_year;
    do while ((year < pregnancy_end_year) or (year = pregnancy_end_year and month <= pregnancy_end_month));
        flag = 1;
        output;

        month + 1;
        if month > 12 then do;
            month = 1;
            year + 1;
        end;
    end;

    array post_partum_end_months[4] (6, 12, 18, 24);
    array post_partum_flags[4] (2, 3, 4, 5);

    do i = 1 to 4;
        post_partum_end_month = MONTH_BIRTH + post_partum_end_months[i];
        post_partum_end_year = YEAR_BIRTH;
        if post_partum_end_month > 12 then do;
            post_partum_end_year = post_partum_end_year + floor((post_partum_end_month-1) / 12);
            post_partum_end_month = mod(post_partum_end_month, 12);
        end;

     month = (ifn(i=1, pregnancy_end_month + 1, month));
     year = (ifn(i=1, pregnancy_end_year, year));
     if month > 12 then do;
         month = 1;
         year + 1;
     end;
	
     do while ((year < post_partum_end_year) or (year = post_partum_end_year and month <= post_partum_end_month));
         flag = post_partum_flags[i];
         output;
	
         month + 1;
         if month > 12 then do;
            month = 1;
             year + 1;
         end;
     end;
end;
	
keep MATERNAL_ID month year flag;
run;
	
data pregnancy_flags;
	set pregnancy_flags;
	rename MATERNAL_ID = ID;
run;
	
proc sort data=pregnancy_flags;
    by ID year month flag;
run;
	
data pregnancy_flags;
    set pregnancy_flags;
    by ID year month;
	
    if first.month then output;
run;

/* =============================================== */
/* 2. Pivot long and join to exisitng HCH Cohort   */
/* =============================================== */
/* This section of code creates a cartesian product where every birth record has 108 rows, one row for every month between Jan 2014 and Dec 2021.
This long birth table is left joined onto the existing cohort of reproductive age womwn with Hepatitis C and OUD which is similarly pivoted long so that every
case record of Hepatitis C has 108 rows, now joined with preganancy and birth data. Those who did not have a birth are assigned preg_flag = 9999. 
This pivot long is necessary so that we can summarize time-varying data (pregnancy status) and assigned associated linkage and treatment starts to the correct preganancy state */

%let start_year=%scan(%substr(&year,2,%length(&year)-2),1,':');
%let end_year=%scan(%substr(&year,2,%length(&year)-2),2,':');

DATA months; DO month = 1 to 12; OUTPUT; END; RUN;

DATA years; DO year = &start_year to &end_year; OUTPUT; END; RUN;

proc sql;
    create table LONG_FINAL_HCV_COHORT as
    select 
        a.ID,
        a.EVENT_MONTH_HCV,
        a.EVENT_YEAR_HCV,
        b.MONTH, 
        c.YEAR
    from 
        FINAL_HCV_COHORT as a, 
        MONTHS as b, 
        YEARS as c
    order by 
        a.ID, c.YEAR, b.MONTH;
quit;

proc sql;
   create table LONG_FINAL_HCV_COHORT as
   select a.*, 
          case when b.flag is not null then b.flag 
               else 9999 end as preg_flag
   from LONG_FINAL_HCV_COHORT a
   left join pregnancy_flags b
   on a.ID = b.ID 
      and a.month = b.month 
      and a.year = b.year;
quit;

/* ========================= */
/* 3. Pull Linkage to Care   */
/* ========================= */
/* Pull intial (first) linkage to care (claim with Hepatitis C as primary diagnosis) data and merge linkage to care claims data in the long cohort to: 
1. Ensure that the case report preceeds the claim of diagnosis because we begin eligible persom-time for linkage to care at the case report date, and censor when the person links;
2. Assign inital linkage event HCV_PRIMARY_DIAG1 = 1;
and 3. Pull in all other remaining claims with Hepatitis C as primary diagnosis. From these data, we begin counting the months lapsed between visits. If time lapsed between visits exceeds 18 months, we deem 
that person loss-to-follow-up. If that person then has a subsequnt claim with Hepatitis C as primary diagnosis follow that 18-month period, that indicates a relinkage event HCV_PRIMARY_DIAG2 = 1 */

DATA HCV_LINKED_SAS;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_FROM_DATE_MONTH MED_FROM_DATE_YEAR MED_ADM_TYPE MED_ICD1
  					 WHERE = (MED_ICD1 IN &HCV_ICD));  
RUN;

PROC SORT DATA=HCV_LINKED_SAS;
    BY ID MED_FROM_DATE;
RUN;

DATA HCV_LINKED_FIRST;
    SET HCV_LINKED_SAS;
    BY ID MED_FROM_DATE;
    IF FIRST.ID THEN DO;
        HCV_PRIMARY_DIAG1 = 1;
        OUTPUT;
    END;
KEEP ID MED_FROM_DATE_MONTH MED_FROM_DATE_YEAR HCV_PRIMARY_DIAG1;
RUN;

proc sql;
    create table linkage_analysis as
    select 
        a.ID,
        a.MED_FROM_DATE_MONTH,
        a.MED_FROM_DATE_YEAR,
        b.EVENT_MONTH_HCV,
        b.EVENT_YEAR_HCV,
        ((b.EVENT_YEAR_HCV - a.MED_FROM_DATE_YEAR) * 12 + (b.EVENT_MONTH_HCV - a.MED_FROM_DATE_MONTH)) as months_between
    from HCV_LINKED_FIRST as a
    inner join LONG_FINAL_HCV_COHORT as b 
    on a.ID = b.ID
    where a.MED_FROM_DATE_YEAR is not missing 
      and a.MED_FROM_DATE_MONTH is not missing
      and b.EVENT_YEAR_HCV is not missing
      and b.EVENT_MONTH_HCV is not missing;
quit;

proc sql;
    select 
        sum(case when months_between < 0 then 1 else 0 end) as count_early_report,
        count(*) as total_cases,
        calculated count_early_report / calculated total_cases as percent_early_report format=percent8.2
    from linkage_analysis;
quit;

proc means data=linkage_analysis mean median std min max;
    var months_between;
run;

proc sort data=LONG_FINAL_HCV_COHORT;
    by ID year month;
run;

proc sort data=HCV_LINKED_FIRST nodupkey;
    by ID MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH;
run;

data HCV_LINKED_FIRST;
    set HCV_LINKED_FIRST;
    month = MED_FROM_DATE_MONTH; 
    year = MED_FROM_DATE_YEAR;   
run;

data LONG_FINAL_HCV_COHORT;
    merge LONG_FINAL_HCV_COHORT (in=a)
          HCV_LINKED_FIRST (in=b);
    by ID year month;
    
    if b then do;
        HCV_PRIMARY_DIAG1 = 1;
        MED_FROM_DATE_MONTH = MED_FROM_DATE_MONTH;
        MED_FROM_DATE_YEAR = MED_FROM_DATE_YEAR;
    end;
    else HCV_PRIMARY_DIAG1 = 0;

    if a;
run;

DATA HCV_LINKED_SAS;
	SET HCV_LINKED_SAS (KEEP = ID MED_FROM_DATE_MONTH MED_FROM_DATE_YEAR);
RUN;

proc sort data=HCV_LINKED_SAS nodupkey;
    by ID MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH;
run;

data HCV_LINKED_SAS;
    set HCV_LINKED_SAS;
    month = MED_FROM_DATE_MONTH;
    year = MED_FROM_DATE_YEAR; 
run;

data LONG_FINAL_HCV_COHORT;
    merge LONG_FINAL_HCV_COHORT (in=a)
          HCV_LINKED_SAS (in=b);
    by ID year month;

    if a;

run;

data LONG_FINAL_HCV_COHORT;
    set LONG_FINAL_HCV_COHORT;
    by ID year month;

    retain months_lapsed;

    if first.ID then do;
        months_lapsed = .;
    end;

    HCV_PRIMARY_DIAG2 = 0;

    if HCV_PRIMARY_DIAG1 = 1 then months_lapsed = 0;

    else if not missing(MED_FROM_DATE_MONTH) and not missing(MED_FROM_DATE_YEAR) then do;
        if months_lapsed >= 18 then do;
            HCV_PRIMARY_DIAG2 = 1; 
            months_lapsed = 0;
        end;
        else months_lapsed = 0;
    end;
    
    else if missing(MED_FROM_DATE_MONTH) and missing(MED_FROM_DATE_YEAR) then do;
        if not missing(months_lapsed) then months_lapsed + 1;
    end;
run;

/* ================================== */
/* 4. Pull DAA Treatment Initiation   */
/* ================================== */
/* Pull in DAA treatment starts claims data and summarize the prescritpions by ID. Outcomes inlcude the frequency of DAA initaitons without prior linkage.
The section of code that is commented out previoulsy explored the mean and median starts and overall distirbution of DAA epidsodes per ID as well as
the distribution of months between consecutive DAA starts to better define refills of primary prescription compared to retreatment. 
That output showed that 85.8% of DAA restarts occurred after just 1 month and over 92.99% restarted within 2 months  
i.e. these were prescription refills for the same treatment episode; 61.9% of individuals had exactly 2 prescription claims and 89.9% had 3 prescription claims. 
So, we updated the code logic to only retain the first DAA start in our final analysis */

DATA DAA; SET PHDAPCD.MOUD_PHARM (KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_MONTH PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
 								 WHERE = (PHARM_NDC IN &DAA_CODES));  
RUN;

PROC SORT DATA=DAA;
    BY ID PHARM_FILL_DATE;
RUN;

DATA DAA_STARTS;
    SET DAA;
    BY ID PHARM_FILL_DATE;
    IF FIRST.ID THEN DO;
        DAA_START_INDICATOR = 1;
        OUTPUT;
    END;
KEEP ID PHARM_FILL_DATE_MONTH PHARM_FILL_DATE_YEAR DAA_START_INDICATOR;
RUN;

proc sort data=LONG_FINAL_HCV_COHORT;
    by ID year month;
run;

proc sort data=DAA_STARTS nodupkey;
    by ID PHARM_FILL_DATE_YEAR PHARM_FILL_DATE_MONTH;
run;

data LONG_FINAL_HCV_COHORT;
    merge LONG_FINAL_HCV_COHORT (in=a)
          DAA_STARTS (rename=(PHARM_FILL_DATE_MONTH=month 
                              PHARM_FILL_DATE_YEAR=year) in=b);
    by ID year month;

    if b then DAA_START_INDICATOR = 1;
    else DAA_START_INDICATOR = 0;

    if a;
run;

proc sort data=LONG_FINAL_HCV_COHORT;
  by ID;
run;

proc sql;
    create table HCV_LINKED_FILTERED as 
    select a.*
    from HCV_LINKED_FIRST as a
    inner join FINAL_HCV_COHORT as b
    on a.ID = b.ID;

    create table DAA_STARTS_FILTERED as 
    select a.*
    from DAA_STARTS as a
    inner join FINAL_HCV_COHORT as b
    on a.ID = b.ID;
quit;

proc sql;
    create table HCV_DAA_TIMING as
    select coalesce(a.ID, b.ID) as ID, 
           a.MED_FROM_DATE_MONTH, a.MED_FROM_DATE_YEAR, 
           b.PHARM_FILL_DATE_MONTH, b.PHARM_FILL_DATE_YEAR,
           case 
               when b.ID is null then 'No DAA Record, Linked'
               when a.ID is null then 'No Linkage Record, DAA'
               when (b.PHARM_FILL_DATE_YEAR < a.MED_FROM_DATE_YEAR) then 'Before'
               when (b.PHARM_FILL_DATE_YEAR = a.MED_FROM_DATE_YEAR and 
                     b.PHARM_FILL_DATE_MONTH < a.MED_FROM_DATE_MONTH) then 'Before'
               when (b.PHARM_FILL_DATE_YEAR = a.MED_FROM_DATE_YEAR and 
                     b.PHARM_FILL_DATE_MONTH = a.MED_FROM_DATE_MONTH) then 'Same Month'
               else 'After'
           end as DAA_Timing
    from HCV_LINKED_FILTERED as a
    full join DAA_STARTS_FILTERED as b
    on a.ID = b.ID;
quit;

title "Timing of DAA Initaitons Relative to Linkage";
proc freq data=HCV_DAA_TIMING;
    tables DAA_Timing;
run;
title;

proc sql;
    create table FINAL_HCV_COHORT as
    select a.*, 
           b.DAA_Timing
    from FINAL_HCV_COHORT as a
    left join HCV_DAA_TIMING as b
    on a.ID = b.ID;
quit;

/* data want(keep=ID cnt_DAA_starts);
  set LONG_FINAL_HCV_COHORT;
  by ID;
  
  retain cnt_DAA_starts 0;
  
  if first.ID then cnt_DAA_starts = 0;
  
  if DAA_START_INDICATOR = 1 then cnt_DAA_starts = cnt_DAA_starts + 1;
  
  if last.ID then output;
run;

data want_nonzero;
  set want;
  if cnt_DAA_starts > 0;
run;

proc univariate data=want_nonzero noprint;
  var cnt_DAA_starts;
  output out=summary_stats_nonzero mean=mean_DAA_starts median=median_DAA_starts range=range_DAA_starts;
run;

proc print data=summary_stats_nonzero;
  title 'Summary Statistics of Number of DAA Starts per ID (Only IDs with at least 1 DAA Start)';
run;

data daa_intervals (keep=ID months_between DAA_order);
  set LONG_FINAL_HCV_COHORT;
  by ID;

  retain prev_DAA_month DAA_order;

  if first.ID then do;
    prev_DAA_month = .;
    DAA_order = 0;
  end;

  if DAA_START_INDICATOR = 1 then do;
    DAA_order + 1;

    if prev_DAA_month ne . then do;
      months_between = (YEAR * 12 + MONTH) - prev_DAA_month;
      output;
    end;

    prev_DAA_month = YEAR * 12 + MONTH;
  end;
run;

proc univariate data=daa_intervals noprint;
  var months_between;
  output out=summary_intervals mean=mean_months median=median_months range=range_months;
run;

proc print data=summary_intervals;
  title 'Summary Statistics of Months Between Consecutive DAA Starts';
run;

proc freq data=daa_intervals;
  tables months_between / missing;
  title 'Distribution of Months Between Consecutive DAA Starts';
run;

proc freq data=daa_intervals;
  tables DAA_order;
  title 'Distribution of Number of DAA Starts per Individual';
run; */

/* ========================= */
/* 5. Define pregnany states */
/* ========================= */
/* This section is somewhat unnecessary, but allows for ease in changing the group_by variable in the rate calculations (we explored many different combinations of grouping 
different post-partum periods together */

proc sort data=LONG_FINAL_HCV_COHORT;
	by ID year month;
run;

data LONG_FINAL_HCV_COHORT;
	set LONG_FINAL_HCV_COHORT;
		
	time_index = (year - 2014) * 12 + month;
		   
	if preg_flag = 1 then group = 1; /* Pregnant */
	else if preg_flag = 2 then group = 2; /* 0-6 months post-partum */
	else if preg_flag = 3 then group = 2; /* 7-12 months post-partum */
	else if preg_flag = 4 then group = 3; /* 13-18 months post-partum */
	else if preg_flag = 5 then group = 3; /* 19-24 months post-partum */
	else if preg_flag = 9999 then group = 0; /* Non-pregnant */
run;

/* ================================== */
/* 6. Censor linkage eligbility     */
/* ================================== */
/* Note: the long cohort is forward censored on case report date in step 9 below after all relinkage, ltfu, and treatment data are integrated into the full long table.
Thus, a person begins eligble for linkage because their first records is their case report date and will stop contribtuing person-time once they link to care (i.e. if they are diagnosed or start DAAs, they are no longer eligble for linkage as event = 1)
Another note: We use flags = 1 for every month of contributing person-time and sum(flags) to determine our denomiator rather than deleting rows because there are four different event outcomes: 1. linkage, 2. relinkage, 3, ltfu, and 4. DAA initiation.
Each rate caluclation uses a different sum(flag) as the denominaotr rather than deleting rows from the dataset */

data LONG_FINAL_HCV_COHORT;
    set LONG_FINAL_HCV_COHORT;
    by ID YEAR MONTH;

    retain link_eligible link_censor;

    if first.ID then do;
        link_eligible = 1;
        link_censor = 0;
    end;

    if HCV_PRIMARY_DIAG1 = 1 or DAA_START_INDICATOR = 1 then do;
        link_censor = 1;
    end;
    
    if link_censor = 1 and not (HCV_PRIMARY_DIAG1 = 1 or DAA_START_INDICATOR = 1) then do;
        link_eligible = 0;
    end;

run;

/* ================================== */
/* 7. Censor relinkage eligbility     */
/* ================================== */
/* A person is eligble for relinkage when 18 months has lapsed between visits with a primary diagnosis of Hepatitis C. If they are relinked to care or intitate DAAs, they are censored for relinkage outcomes */

data LONG_FINAL_HCV_COHORT; 
    set LONG_FINAL_HCV_COHORT;
    by ID YEAR MONTH;

    retain relinkage_eligible relinkage_censor; 

    if first.ID then do;
        relinkage_eligible = 0;  
        relinkage_censor = 0; 
    end;

    if months_lapsed >= 18 then do;
        relinkage_eligible = 1;
    end;

    if HCV_PRIMARY_DIAG2 = 1 or DAA_START_INDICATOR = 1 then do;
        relinkage_censor = 1;
    end;

    if relinkage_censor = 1 and not (HCV_PRIMARY_DIAG2 = 1 or DAA_START_INDICATOR = 1) then do;
        relinkage_eligible = 0;
    end;

run;

/* ================================== */
/* 8. Censor LTFU eligbility          */
/* ================================== */
/* A person is eligible for ltfu as soon as they link to care. You are considered ltfu when 18 months has lapsed between visits with a primary diagnosis of Hepatitis C. 
If they are ltfu or intitate DAAs, they are censored */

data LONG_FINAL_HCV_COHORT; 
    set LONG_FINAL_HCV_COHORT;
    by ID YEAR MONTH;

    retain ltfu_flag ltfu_eligible ltfu_censor;  

    if first.ID then do;
        ltfu_flag = 0; 
        ltfu_eligible = 0;
        ltfu_censor = 0; 
    end;

    if months_lapsed = 18 and relinkage_censor = 0 then ltfu_flag = 1;
    else ltfu_flag = 0;

    if ltfu_flag = 1 then ltfu_censor = 1;

	if link_censor = 1 and relinkage_censor = 0 then
        ltfu_eligible = 1;
        
    if ltfu_censor = 1 and not (ltfu_flag = 1) then do;
    	ltfu_eligible = 0;
    end;

run;

/* =================================== */
/* 8. Censor DAA Initiation eligbility */
/* =================================== */
/* A person is eligble for treatment the month that they link to care (i.e. have a primary diagnosis claim) and are censored once they start DAAs because treatment event = 1.
We do not include retreatment or multiple treatment outcomes */

data LONG_FINAL_HCV_COHORT;
    set LONG_FINAL_HCV_COHORT;
    by ID YEAR MONTH;

    retain treatment_eligible DAA_censor;

    if first.ID then do;
        treatment_eligible = 0;
        DAA_censor = 0;
    end;

    if HCV_PRIMARY_DIAG1 = 1 then treatment_eligible = 1;

    if DAA_START_INDICATOR = 1 then do;
        if HCV_PRIMARY_DIAG1 = 1 or link_eligible = 1 then do;
            treatment_eligible = 1;
        end;
        DAA_censor = 1;
    end;
    
    if DAA_censor = 1 and not (DAA_START_INDICATOR = 1 or link_eligible = 1) then do;
        treatment_eligible = 0;
    end;

run;

/* =================================== */
/* 9. Censor on case report date       */
/* =================================== */
/* A person is eligble for linkage to care at their case report date. This proc makes the first row of data for an individual the month/year of their case report, forward censoring the start of the follow-up period.
 All three event outcomes should censor on case report date, so delete rows that preceed the case report as to not inflate the denominator with non-contirbuting person-time.
 Exploratory analysis to see the temporality of claims and case report date (these Ns help us understand why the event count in the rate calculation mahy differ from what was reported in the cascade outcomes above) */
 
proc sql;
    create table case_report_events as 
    select ID, min(EVENT_YEAR_HCV*12 + EVENT_MONTH_HCV) as case_report_period
    from LONG_FINAL_HCV_COHORT
    group by ID;
quit;

proc sql;
    create table pre_case_report_claims as
    select a.ID, count(*) as claims_before_case_report
    from LONG_FINAL_HCV_COHORT as a
    inner join case_report_events as c
    on a.ID = c.ID
    where (a.year*12 + a.month) < c.case_report_period
        and not missing(a.MED_FROM_DATE_MONTH)
        and not missing(a.MED_FROM_DATE_YEAR)
    group by a.ID;
quit;

title "Frequency of Claims Processed Before Case Report";
proc freq data=pre_case_report_claims;
    tables claims_before_case_report;
run;
title;

proc sql;
    create table pre_case_report_counts as
    select 
        sum(HCV_PRIMARY_DIAG1) as early_HCV_PRIMARY_DIAG1,
        sum(HCV_PRIMARY_DIAG2) as early_HCV_PRIMARY_DIAG2,
        sum(DAA_START_INDICATOR) as early_DAA_START_INDICATOR,
        sum(LTFU_FLAG) as early_LTFU_FLAG
    from LONG_FINAL_HCV_COHORT as a
    inner join case_report_events as c
    on a.ID = c.ID
    where (a.year*12 + a.month) < c.case_report_period;
quit;

title "Counts of Events Occurring Before Case Report";
proc print data=pre_case_report_counts noobs;
run;
title;

proc sql;
    create table LONG_FINAL_HCV_COHORT as
    select *
    from LONG_FINAL_HCV_COHORT
    where (YEAR > EVENT_YEAR_HCV) 
        or (YEAR = EVENT_YEAR_HCV and MONTH >= EVENT_MONTH_HCV)
    order by ID, YEAR, MONTH;
quit;

/* ==================== */
/* 10. Censor on death  */
/* ==================== */
/* As well as censooring for event = 1, censor for comepting causes of death to end follow-up. All three event outcomes should censor on death, so delete the rows that follow a death as to not inflate the denominator with non-contirbuting person-time.
We do take caution to delete only the ros that follow death, so that if a linkage or DAA event occurs in the same month, it is counted in the num and person-time in the denom.
Again exploratory analysis to see the temporality of claims and death date (these Ns help us understand why the event count in the rate calculation mahy differ from what was reported in the cascade outcomes above) */

proc sql;
    create table deaths_filtered as
    select 
        ID, 
        YEAR_DEATH, 
        MONTH_DEATH
    from PHDDEATH.DEATH
    where YEAR_DEATH in &year;
 quit;

 proc sql;
    create table LONG_FINAL_HCV_COHORT as
    select a.*, 
           b.YEAR_DEATH, 
           b.MONTH_DEATH,
           case 
               when b.YEAR_DEATH = a.year and b.MONTH_DEATH = a.month then 1
               else 0
           end as death_flag
    from LONG_FINAL_HCV_COHORT as a
    left join deaths_filtered as b
    on a.ID = b.ID;
quit;

proc sql;
    create table death_events as 
    select ID, min(year*12 + month) as death_period
    from LONG_FINAL_HCV_COHORT
    where death_flag = 1
    group by ID;
quit;

proc sql;
    create table post_death_claims as
    select a.ID, count(*) as claims_after_death
    from LONG_FINAL_HCV_COHORT as a
    inner join death_events as d
    on a.ID = d.ID
    where (a.year*12 + a.month) > d.death_period
        and not missing(a.MED_FROM_DATE_MONTH)
        and not missing(a.MED_FROM_DATE_YEAR)
    group by a.ID;
quit;

title "Frequency of claims processed after death";
proc freq data=post_death_claims;
    tables claims_after_death;
run;
title;

proc sql;
    create table post_death_counts as
    select 
        sum(HCV_PRIMARY_DIAG1) as HCV_PRIMARY_DIAG1_after_death,
        sum(HCV_PRIMARY_DIAG2) as HCV_PRIMARY_DIAG2_after_death,
        sum(DAA_START_INDICATOR) as DAA_START_INDICATOR_after_death,
        sum(LTFU_FLAG) as LTFU_FLAG_after_death
    from LONG_FINAL_HCV_COHORT as a
    inner join death_events as d
    on a.ID = d.ID
    where (a.year*12 + a.month) > d.death_period;
quit;

title "Counts of Events Occurring After Death";
proc print data=post_death_counts noobs;
run;
title;

data LONG_FINAL_HCV_COHORT;
    set LONG_FINAL_HCV_COHORT;
    retain death_flag_forward 0;
    by ID;

    if first.ID then death_flag_forward = 0;
    if death_flag = 1 then death_flag_forward = 1;

    if death_flag_forward = 1 and (year > YEAR_DEATH or (year = YEAR_DEATH and month > MONTH_DEATH)) then delete;

    drop death_flag_forward;
run;

/* ========================== */
/* 11. Calculate person time  */
/* ========================== */
/* Summarize the person-time contributing to the denominator for each of the three outcomes, separately, by pregnany status. Each month had a flag = 1, so person-months is the reporting metric.
Each record will now be reduced from 108 rows for evry month of the full APCD follow-up period, to 4 rows, one row per preganncy state defined */

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        sum(case when link_eligible = 1 then 1 else 0 end) as person_time_link,
        sum(case when relinkage_eligible = 1 then 1 else 0 end) as person_time_relink, 
        sum(case when treatment_eligible = 1 then 1 else 0 end) as person_time_txt, 
        sum(case when ltfu_eligible = 1 then 1 else 0 end) as person_time_ltfu
    from LONG_FINAL_HCV_COHORT
    group by ID, group;
quit;

/* ========================== */
/* 12. Calculate events       */
/* ========================== */
/* Count the number of linkages, relinkages, ltfu, and daa starts that occured, summarized by person and by pregannacy status. Again, each record will now be reduced from 108 rows, to 4 rows, one row per preganncy state defined */

proc sql;
    create table PERIOD_SUMMARY as
    select ID,
           group,
           sum(HCV_PRIMARY_DIAG1) as hcv_diagnosis1,
           sum(DAA_START_INDICATOR) as daa_start,
           sum(HCV_PRIMARY_DIAG2) as hcv_diagnosis2,
           sum(ltfu_flag) as ltfu_flag
    from LONG_FINAL_HCV_COHORT
    group by ID, group;
 quit;

/* ============================ */
/* 13. Create Final Rate Table  */
/* ============================ */
/* Combine the reported person-time that each ID contibuted to each preganncy state and pull in demographic variables for rate stratification */

proc sort data=PERSON_TIME;
    by ID group;
run;

proc sort data=PERIOD_SUMMARY;
    by ID group;
run;

data PERIOD_SUMMARY;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID group;
run;

proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY.*,
           cov.AGE_HCV_GRP,
           cov.FINAL_RE,
           cov.INSURANCE_CAT,
           cov.HOMELESS_HISTORY_GROUP,
           cov.EVER_INCARCERATED,
           cov.AGE_HCV,
           cov.EVER_IDU_HCV_MAT,
           cov.IJI_DIAG,
           cov.rural_group,
           cov.EVENT_YEAR_HCV,
           cov.EVENT_MONTH_HCV,
           cov.DAA_Timing
    from PERIOD_SUMMARY
    left join FINAL_HCV_COHORT as cov
    on PERIOD_SUMMARY.ID = cov.ID;
quit;

data PERIOD_SUMMARY_FINAL;
	set PERIOD_SUMMARY_FINAL;
	age_grp_five  = put(AGE_HCV, age_grps_five.);
run;

data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV_MAT = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;

proc sql;
    create table summed_data as
    select 
        ID,
        sum(person_time_link) as total_person_time_link,
        sum(person_time_relink) as total_person_time_relink,
        sum(person_time_txt) as total_person_time_txt,
        sum(person_time_ltfu) as total_person_time_ltfu
    from 
        PERIOD_SUMMARY_FINAL
    group by 
        ID;
quit;

title "Summary statistics for Overall Follow-up Time";
proc means data=summed_data mean std min max q1 median q3;
    var total_person_time_link total_person_time_relink total_person_time_txt total_person_time_ltfu;
run;

/* ================================================================= */
/* 14. Final Rates for Linkage, Reinkage, and Treatment Initiation   */
/* ================================================================== */
/* The first two PROC SQL steps generate reates for our four key HCV-related events, HCV diagnoses (both primary and secondary), loss-to-follow-up, and DAA treatment starts. 
The first query provides overall summaries, while the second stratifies these statistics by pregnancy group.
The macro integrates additional demographic and social determinant variables. This avoids repetitive code while allowing flexibility in stratifications. 
The macro takes two parameters:
   - group_by_vars: the variable to stratify by
   - mytitle: the title for the output
The PROC SQL block inside the macro calculates the same key HCV diagnosis and treatment measures as before, along with their confidence intervals.
The final rate calculation looks at trends of time by year of Hepatitis C diagnosis, not by preganancy status */  

title 'Linkage and Treatment Starts, Overall';
proc sql;
    select 
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink, 
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu   
    from PERIOD_SUMMARY_FINAL;
quit;

title 'Linkage and Treatment Starts by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,  
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,
        
        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,
        
        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,
        
        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4
        
    from PERIOD_SUMMARY_FINAL
    group by group;
quit;

%macro calculate_rates(group_by_vars, mytitle);
title &mytitle;
proc sql;
    select 
        group,
        &group_by_vars,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,

        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,

        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,

        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4

    from PERIOD_SUMMARY_FINAL
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(AGE_HCV_GRP, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by AGE_HCV_GRP');
%calculate_rates(FINAL_RE, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(INSURANCE_CAT, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by INSURANCE_CAT');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by HOMELESS_HISTORY');
%calculate_rates(EVER_INCARCERATED, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(age_grp_five, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by Age');
%calculate_rates(IDU_EVIDENCE, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by IDU_EVIDENCE');
%calculate_rates(rural_group, 'Linkage and Treatment Starts by Pregnancy Group, Stratified by rural_group');

title 'Treatment Starts by DAA Timing';
proc sql;
    select 
        DAA_Timing,
        count(*) as total_n,
        sum(daa_start) as daa_start,
        sum(person_time_txt) as person_time_txt,
        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by DAA_Timing;
quit;
title;

title 'Linkage and Treatment Starts by Year of Diagnosis';
proc sql;
    select 
        EVENT_YEAR_HCV,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,

        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,

        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,

        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by EVENT_YEAR_HCV;
quit;
title;

/* ================================================================== */
/* 15. Sensitivity Anlysis: Restrict to Cases after August 2016       */
/* ================================================================== */

data PERIOD_SUMMARY_FINAL_SENS;
    set PERIOD_SUMMARY_FINAL;
    if EVENT_YEAR_HCV > 2016 or (EVENT_YEAR_HCV = 2016 and EVENT_MONTH_HCV >= 8);
run;

title 'Restricted to Aug 2016: Linkage and Treatment Starts, Overall';
proc sql;
    select 
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink, 
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu   
    from PERIOD_SUMMARY_FINAL_SENS;
quit;

title 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,  
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,
        
        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,
        
        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,
        
        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4
        
    from PERIOD_SUMMARY_FINAL_SENS
    group by group;
quit;

%macro calculate_rates(group_by_vars, mytitle);
title &mytitle;
proc sql;
    select 
        group,
        &group_by_vars,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,

        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,

        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,

        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4

    from PERIOD_SUMMARY_FINAL_SENS
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(AGE_HCV_GRP, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by AGE_HCV_GRP');
%calculate_rates(FINAL_RE, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(INSURANCE_CAT, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by INSURANCE_CAT');
%calculate_rates(HOMELESS_HISTORY, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by HOMELESS_HISTORY');
%calculate_rates(EVER_INCARCERATED, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(age_grp_five, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by Age');
%calculate_rates(IDU_EVIDENCE, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by IDU_EVIDENCE');
%calculate_rates(rural_group, 'Restricted to Aug 2016: Linkage and Treatment Starts by Pregnancy Group, Stratified by rural_group');

title 'Restricted to Aug 2016: Treatment Starts by DAA_Timing';
proc sql;
    select 
        DAA_Timing,
        count(*) as total_n,
        sum(daa_start) as daa_start,
        sum(person_time_txt) as person_time_txt,
        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL_SENS
    group by DAA_Timing;
quit;
title;

title 'Restricted to Aug 2016: Linkage and Treatment Starts by Year of Diagnosis';
proc sql;
    select 
        EVENT_YEAR_HCV,
        count(*) as total_n,
        sum(hcv_diagnosis1) as hcv_diagnosis1,
        sum(hcv_diagnosis2) as hcv_diagnosis2,
        sum(daa_start) as daa_start,
        sum(ltfu_flag) as ltfu_flag,
        sum(person_time_link) as person_time_link,
        sum(person_time_relink) as person_time_relink,
        sum(person_time_txt) as person_time_txt,
        sum(person_time_ltfu) as person_time_ltfu,
        
        calculated hcv_diagnosis1 / calculated person_time_link as hcv_diagnosis1_rate format=8.4,
        (calculated hcv_diagnosis1 - 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_lower format=8.4,
        (calculated hcv_diagnosis1 + 1.96 * sqrt(calculated hcv_diagnosis1)) / calculated person_time_link as hcv_diagnosis1_rate_upper format=8.4,

        calculated hcv_diagnosis2 / calculated person_time_relink as hcv_diagnosis2_rate format=8.4,
        (calculated hcv_diagnosis2 - 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_lower format=8.4,
        (calculated hcv_diagnosis2 + 1.96 * sqrt(calculated hcv_diagnosis2)) / calculated person_time_relink as hcv_diagnosis2_rate_upper format=8.4,

        calculated daa_start / calculated person_time_txt as daa_start_rate format=8.4,
        (calculated daa_start - 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_lower format=8.4,
        (calculated daa_start + 1.96 * sqrt(calculated daa_start)) / calculated person_time_txt as daa_start_rate_upper format=8.4,

        calculated ltfu_flag / calculated person_time_ltfu as ltfu_rate format=8.4,
        (calculated ltfu_flag - 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_lower format=8.4,
        (calculated ltfu_flag + 1.96 * sqrt(calculated ltfu_flag)) / calculated person_time_ltfu as ltfu_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL_SENS
    group by EVENT_YEAR_HCV;
quit;
title;