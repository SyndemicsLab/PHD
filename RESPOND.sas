/* Step 1: Clear the log and output */
dm 'log' clear;
dm 'output' clear;

/* Step 2: Delete all datasets in the WORK library */
proc datasets lib=work nolist kill;
quit;

/* Step 3: Clear any user-defined formats (if applicable) */
proc datasets lib=work memtype=catalog nolist;
   delete formats;
quit;

/*==============================*/
/* Project: OUD Cascade 	    */
/* Author: Ryan O'Dea  		    */ 
/* Created: 4/27/2023 		    */
/* Updated: 04/30/2024 by SJM	*/
/*==============================*/

LIBNAME PHD '/home/u63539700/PHD/';

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
%LET year = (2014:2021);
%LET MOUD_leniency = 7;
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
from PHD.PMP_SYN
where BUP_CAT_PMP = 1;
quit;

proc sql noprint;
select quote(trim(ndc),"'") into :BUP_NDC separated by ','
from bupndcf;
quit;
            
/*===============================*/            
/* DATA PULL			         */
/*===============================*/ 

/*======DEMOGRAPHIC DATA=========*/
/* Using data from DEMO, take the cartesian coordinate of years
(as defined above) and months 1:12 to construct a shell table */

PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, YOB, FINAL_SEX, SELF_FUNDED
	FROM PHD.SPINE_DEMO_SYN2
	WHERE FINAL_SEX = 2 & SELF_FUNDED = 0;
QUIT;

/*=========APCD DATA=============*/

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
	SET PHD.APCD_MEDICAL_SYN (KEEP= ID MED_ECODE MED_ADM_DIAGNOSIS MED_AGE
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
    SET PHD.APCD_PHARMACY_SYN(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH PHARM_AGE
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;
    IF oud_pharm = 0 THEN DELETE;

IF oud_pharm > 0 THEN year_pharm = PHARM_FILL_DATE_YEAR;

RUN;

/*======CASEMIX DATA==========*/

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
	SET PHD.CASEMIX_ED_PHD_SYN2 (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
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
	SET PHD.CASEMIX_ED_DIAG_PHD_SYN2 (KEEP= ED_ID ED_DIAG);
	IF ED_DIAG in &ICD THEN oud_cm_ed_diag = 1;
	ELSE oud_cm_ed_diag = 0;
RUN;

/* ED_PROC */
DATA casemix_ed_proc (KEEP= oud_cm_ed_proc ED_ID);
	SET PHD.CASEMIX_ED_PROC_PHD_SYN2 (KEEP= ED_ID ED_PROC);
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

/* HD DATA */
DATA hd (KEEP= HD_ID ID oud_hd_raw year_hd);
	SET PHD.CASEMIX_HD_PHD_SYN2 (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH HD_ECODE
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
	SET PHD.CASEMIX_HD_DIAG_PHD_SYN2 (KEEP= HD_ID HD_DIAG);
	IF HD_DIAG in &ICD THEN oud_hd_diag = 1;
	ELSE oud_hd_diag = 0;
RUN;

/* HD PROC DATA */
DATA hd_proc(KEEP= HD_ID oud_hd_proc);
	SET PHD.CASEMIX_HD_PROC_PHD_SYN22(KEEP = HD_ID HD_PROC);
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

/* OO */
DATA oo (KEEP= ID oud_oo year_oo);
    SET PHD.CASEMIX_OO_PHD_SYN2 (KEEP= ID OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4
                        OO_ADMIT_YEAR OO_ADMIT_MONTH OO_AGE
                        OO_CPT1-OO_CPT10
                        OO_PRINCIPALEXTERNAL_CAUSECODE
                    WHERE= (OO_ADMIT_YEAR IN &year));
	cnt_oud_oo = 0;
    
    ARRAY vars2 {*} OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4 OO_CPT1-OO_CPT10 OO_PRINCIPALEXTERNAL_CAUSECODE;
    
    DO k = 1 TO dim(vars2);
        IF SUBSTR(VNAME(vars2[k]), 1) = 'OO_PROC' THEN 
            IF vars2[k] IN &PROC THEN 
                cnt_oud_oo = cnt_oud_oo + 1;
            ELSE IF vars2[k] IN &ICD THEN 
                cnt_oud_oo = cnt_oud_oo + 1;
    END;

    DROP k;

/*     IF cnt_oud_oo > 0 THEN */ oud_oo = 1; 
/*     ELSE oud_oo = 0; */
/*  */
/*     IF oud_oo = 0 THEN DELETE; */

    year_oo = OO_ADMIT_YEAR;
RUN;

/* MERGE ALL CM */
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

/* BSAS */

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
    SET PHD.BSAS_SYN (KEEP= ID CLT_ENR_OVERDOSES_LIFE
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

/* MATRIS */

/* The MATRIS Dataset depends on PHD level encoding of variables 
`OPIOID_ORI_MATRIS` and `OPIOID_ORISUBCAT_MATRIS` to 
construct our flag variable, `OUD_MATRIS`. */

DATA matris (KEEP= ID oud_matris year_matris);
SET PHD.MATRIS_SYN (KEEP= ID OPIOID_ORI_MATRIS
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

/* DEATH */

/* The Death dataset holds the official cause and manner of 
death assigned by physicians and medical examiners. For our 
purposes, we are only interested in the variable `OPIOID_DEATH` 
which is based on 'ICD10 codes or literal search' from other 
PHD sources.*/

DATA death (KEEP= ID oud_death year_death);
    SET PHD.DEATHS_SYN2 (KEEP= ID OPIOID_DEATH YEAR_DEATH AGE_DEATH
                        WHERE= (YEAR_DEATH IN &year));
    IF OPIOID_DEATH = 1 THEN oud_death = 1;
    ELSE oud_death = 0;
    IF oud_death = 0 THEN DELETE;

    year_death = YEAR_DEATH;

RUN;

/* PMP */

/* Within the PMP dataset, we only use the `BUPRENORPHINE_PMP` 
to define the flag `OUD_PMP` - conditioned on BUP_CAT_PMP = 1. */

DATA pmp (KEEP= ID oud_pmp year_pmp);
    SET PHD.PMP_SYN (KEEP= ID BUPRENORPHINE_PMP date_filled_year AGE_PMP date_filled_month BUP_CAT_PMP
                    WHERE= (date_filled_year IN &year));
    IF BUPRENORPHINE_PMP = 1 AND 
        BUP_CAT_PMP = 1 THEN oud_pmp = 1;
    ELSE oud_pmp = 0;
    IF oud_pmp = 0 THEN DELETE;

    year_pmp = date_filled_year;

RUN;

/*===========================*/
/*      MAIN MERGE           */
/*===========================*/

/* As a final series of steps:
1. APCD-Pharm, APCD-Medical, Casemix, Death, PMP, Matris, 
   BSAS are joined together on the cartesian coordinate of Months 
   (1:12), Year (2015:2021), and SPINE (Race, Sex, ID)
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

/*=========================================*/
/*    FINAL COHORT DATASET: oud_distinct   */
/*=========================================*/

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

/*==============================*/
/* Project: Maternal Cascade    */
/* Author:  Ben Buzzee  	    */ 
/* Created: 12/16/2022 		    */
/* Updated: 12/20/23 by SJM     */
/*==============================*/

/* ======= HCV TESTING CPT CODES ========  */
%LET AB_CPT = ('G0472','86803','86804','80074');
%LET RNA_CPT = ('87520','87521','87522');
%LET GENO_CPT = ('87902','3266F');

/* === HCV DIAGNOSIS CODES ====== */
%LET HCV_ICD = ('7051',  '7054','707',
		'7041',  '7044','7071',
		'B1710','B182','B1920',
		'B1711','B1921');
								
%LET DAA_CODES = ('00003021301','00003021501',
		'61958220101','61958180101','61958180301',
		'61958180401','61958180501','61958150101',
		'61958150401','61958150501','72626260101',
		'00074262501','00074262528','00074262556',
		'00074262580','00074262584','00074260028',
		'72626270101','00074308228','00074006301',
		'00074006328','00074309301','00074309328',
		'61958240101','61958220101','61958220301',
		'61958220401','61958220501','00006307402',
		'51167010001','51167010003','59676022507',
		'59676022528','00085031402');
  
%LET bsas_drugs = (5,6,7,21,22,23,24,26);

  /*============================*/
 /*   Add Pregancy Covariates  */
/*============================*/

DATA all_births (keep = ID INFANT_DOB BIRTH_INDICATOR YEAR_BIRTH AGE_BIRTH LD_PAY KOTELCHUCK prenat_site);
   SET PHD.BIRTHSMOMS_SYN2 (KEEP = ID INFANT_DOB YEAR_BIRTH AGE_BIRTH LD_PAY KOTELCHUCK prenat_site
                            WHERE= (YEAR_BIRTH IN &year));
   BIRTH_INDICATOR = 1;
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

/* RECODE MISSING VALUES AS 0  */

DATA oud_preg;
SET oud_preg;
	IF BIRTH_INDICATOR = . THEN BIRTH_INDICATOR = 0;
run;

proc sort data=all_births;
    by ID INFANT_DOB;
run;

data birthsmoms_first;
    set all_births;
    by ID INFANT_DOB;
    if first.ID; /* Keeps only the first row for each ID */
run;

proc sql;
    create table oud_preg as
    select oud_preg.*,
           birthsmoms_first.AGE_BIRTH,
           birthsmoms_first.LD_PAY,
           birthsmoms_first.KOTELCHUCK,
           birthsmoms_first.prenat_site
    from oud_preg
    left join birthsmoms_first
    on oud_preg.ID = birthsmoms_first.ID;
quit;

/* ========================================================== */
/*                       HCV TESTING                          */
/* ========================================================== */

/* =========== */
/* AB TESTING */
/* ========== */

DATA ab;
SET PHD.APCD_MEDICAL_SYN (KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR
					 
/* 					 WHERE = (MED_PROC_CODE IN  &AB_CPT)*/);
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

/* ======================================= */
/* PREP DATASET FOR AB_TESTING BY YEAR  */
/* ==================================== */

PROC SQL;
create table AB_YEARS as
SELECT DISTINCT ID, MED_FROM_DATE_YEAR as AB_TEST_YEAR
FROM AB1;
quit;

/* Restrict AB testing to just those in our cohort */
PROC SQL;
create table AB_YEARS_COHORT as
SELECT *
FROM OUD_DISTINCT
LEFT JOIN AB_YEARS on OUD_DISTINCT.ID = AB_YEARS.ID;
quit;

/* =========== */
/* RNA TESTING */
/* =========== */

DATA rna;
SET PHD.APCD_MEDICAL_SYN (KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
/* 					 WHERE = (MED_PROC_CODE IN  &RNA_CPT)*/); 
run;

/* Sort the data by ID in ascending order */
PROC SORT data=rna;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=rna out=rna_wide (KEEP = ID RNA_TEST_DATE:) PREFIX=RNA_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

/* ================ */
/* GENOTYPE TESTING */
/* ================ */

DATA geno;
SET PHD.APCD_MEDICAL_SYN (KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
/* 					 WHERE = (MED_PROC_CODE IN  &GENO_CPT)*/); 
run;

/* Sort the data by ID in ascending order */
PROC SORT data=geno;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=geno out=geno_wide (KEEP = ID GENO_TEST_DATE:) PREFIX=GENO_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

/* ================ */
/* HCV CODES CHECK  */
/* ================ */

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

/*  Join all labs to OUD PREG, which is our oud cohort with pregnancy covariates added */
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
/*                   HCV STATUS FROM MAVEN                    */
/* ========================================================== */

/* This reduced the dataset to one row person  */
PROC SQL;
	CREATE TABLE HCV_STATUS AS
	SELECT ID,
	min(AGE_HCV) as AGE_HCV,
	min(EVENT_YEAR_HCV) as EVENT_YEAR_HCV,
	min(EVENT_DATE_HCV) as EVENT_DATE_HCV,
	CASE 
            WHEN SUM(EVER_IDU_HCV = 1) > 0 THEN 1 
            WHEN SUM(EVER_IDU_HCV = 0) > 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 0 
            WHEN SUM(EVER_IDU_HCV = 9) > 0 AND SUM(EVER_IDU_HCV = 0) <= 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 9 
            ELSE 9
        END AS EVER_IDU_HCV_MAT,
	1 as HCV_SEROPOSITIVE_INDICATOR,
	CASE WHEN min(DISEASE_STATUS_HCV) = 1 THEN 1 ELSE 0 END as CONFIRMED_HCV_INDICATOR FROM PHD.HCV_SYN2
	GROUP BY ID;
QUIT;

/*  JOIN TO LARGER TABLE */
PROC SQL;
    CREATE TABLE OUD_HCV_STATUS AS
    SELECT * FROM OUD_HCV 
    LEFT JOIN HCV_STATUS ON HCV_STATUS.ID = OUD_HCV.ID;
QUIT;

/* ========================================================== */
/*                      LINKAGE TO CARE                       */
/* ========================================================== */

/* FILTER WHOLE DATASET */
DATA HCV_LINKED_SAS;
SET PHD.APCD_MEDICAL_SYN (KEEP = ID MED_FROM_DATE MED_ADM_TYPE MED_ICD1
					 
/* 					 WHERE = (MED_ICD1 IN &HCV_ICD)*/); 
RUN;

/* FINAL LINKAGE TO CARE DATASET */
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
    CREATE TABLE OUD_HCV_LINKED AS
    SELECT * FROM OUD_HCV_STATUS 
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = OUD_HCV_STATUS.ID;
QUIT;
  
/* Add 0's to those without linkage indicator */
DATA OUD_HCV_LINKED; SET OUD_HCV_LINKED;
IF HCV_PRIMARY_DIAG = . THEN HCV_PRIMARY_DIAG = 0;
IF HCV_SEROPOSITIVE_INDICATOR = . THEN HCV_SEROPOSITIVE_INDICATOR = 0;
run;

/* ========================================================== */
/*                       DAA STARTS                           */
/* ========================================================== */

DATA DAA; SET PHD.APCD_PHARMACY_SYN (KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
/* 								WHERE = (PHARM_NDC IN &DAA_CODES)*/); 
RUN;

/* Reduce to one row per person */
PROC SQL;
CREATE TABLE DAA_STARTS as
SELECT ID,
	   min(PHARM_AGE) as PHARM_AGE,
	   min(PHARM_FILL_DATE_YEAR) as FIRST_DAA_START_YEAR,
	   min(PHARM_FILL_DATE) as FIRST_DAA_DATE,
	   1 as DAA_START_INDICATOR from DAA
GROUP BY ID;
QUIT;

/* Join to main dataset */
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
  DROP agegrp; /* Drop the original character variable */
RUN;

/* Step 1: Extract IDs from HCV dataset with DISEASE_STATUS_HCV = 1 or 2 */
proc sql;
    create table HCV_IDS as
    select distinct ID
    from PHD.HCV_SYN2
    where DISEASE_STATUS_HCV in (1, 2); /* Only Confirmed and Probable */
quit;

/* Step 2: Cross-reference with OUD cohort */
proc sql;
    create table OUD_HCV_CROSS as
    select a.ID,
           (case when b.ID is not null then 1 else 0 end) as HCV_FLAG
    from OUD_HCV_DAA as a
    left join HCV_IDS as b
    on a.ID = b.ID; /* Match IDs */
quit;

/* Step 3: Generate Frequency Table for HCV_Flag */
title "Total # of Confirmed and Probable HCV cases diagnosed with OUD";
proc freq data=OUD_HCV_CROSS;
    tables HCV_FLAG / missing;
run;
title;

DATA TESTING; 
SET OUD_HCV_DAA;
	EOT_RNA_TEST = 0;
	SVR12_RNA_TEST = 0;
	IF RNA_TEST_DATE_1 = .  THEN DELETE;
	IF FIRST_DAA_DATE = .  THEN DELETE;

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

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM TESTING;
QUIT;

%put Number of unique IDs in TESTING table: &num_unique_ids;

PROC CONTENTS data=TESTING;
title "Contents of Final Dataset";
run;

/*====================*/
/*  FREQUENCY TABLES */
/*==================*/

/* Recode Formats */

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

/* Race/Ethnicity coding https://www.mass.gov/doc/phd-20-analytic-data-dictionaries-part1-v6-122022/download */
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

/*  NONSTRATIFIED CARE CASCADE TABLES */
/* Sorting the dataset by CONFIRMED_HCV_INDICATOR */
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
           FIRST_DAA_START_YEAR / missing norow nocol nopercent;
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
		FIRST_DAA_START_YEAR / missing norow nopercent nocol;
run;

%macro CascadeTestFreq(strata, mytitle, ageformat, raceformat);
    TITLE &mytitle;
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

/*  Age stratification */
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
%YearFreq(FIRST_DAA_START_YEAR, num_agegrp, 1, "Counts per year among confirmed, by Age", agefmt_comb., racefmt_all.)

/*  Race Stratification */
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
%YearFreq(FIRST_DAA_START_YEAR, final_re, 1, "Counts per year among confirmed, by Race", agefmt_comb., racefmt_all.)

/*  Birth Stratification */
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
%YearFreq(FIRST_DAA_START_YEAR, birth_indicator, 1, "Counts per year among confirmed, by Birth", agefmt_comb., racefmt_all.)

/* ========================================================== */
/* Pull Covariates 											  */
/* ========================================================== */

/* Create a new dataset FINAL_DEDUP */
proc sort data=PHD.SPINE_DEMO_SYN2;
   by ID;
run;

data PHD.SPINE_DEMO_SYN2;
    set PHD.SPINE_DEMO_SYN2;
    by ID;
    if first.ID;
run;

/* Join to add covariates */

proc sql;
    create table FINAL_COHORT as
    select OUD_HCV_DAA.*,
           demographics.FINAL_RE, 
           demographics.HOMELESS_HISTORY,
           demographics.EVER_INCARCERATED,
           demographics.FOREIGN_BORN,
           demographics.LANGUAGE,
           demographics.EDUCATION,
           demographics.OCCUPATION_CODE
    from OUD_HCV_DAA
    left join PHD.SPINE_DEMO_SYN2 as demographics
    on OUD_HCV_DAA.ID = demographics.ID;
quit;

proc sql;
create table MENTAL_HEALTH_COHORT(where=(MENTAL_HEALTH_DIAG=1)) as
select distinct FINAL_COHORT.ID,
       case
           when prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ECODE) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ADM_DIAGNOSIS) > 0 or
                prxmatch('/^V(6|20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD1) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD2) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD3) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD4) > 0 or
                prxmatch('/^E(88|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD5) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD6) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD7) > 0 or
                prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD8) > 0 or
                prxmatch('/^E(0|21|22|23|24|25|28|29|30|31|32|33|34|39)/', apcd.MED_ICD9) > 0 or
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
left join PHD.APCD_MEDICAL_SYN as apcd
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
left join PHD.APCD_MEDICAL_SYN as apcd
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
        from PHD.HIV_INC_SYN2
        group by ID
    ) as min_hiv
    on FINAL_COHORT.ID = min_hiv.ID;
quit;

proc sql;
    create table FINAL_COHORT as
    select 
        FINAL_COHORT.*, 
        moud.*, 
        (case when moud.ID is not null then 1 else 0 end) as EVER_MOUD
    from FINAL_COHORT
    left join PHD.MOUD_SYN as moud
    on FINAL_COHORT.ID = moud.ID;
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
left join PHD.APCD_MEDICAL_SYN as apcd on FINAL_COHORT.ID = apcd.ID
left join PHD.BSAS_SYN as bsas on FINAL_COHORT.ID = bsas.ID;
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
left join PHD.APCD_MEDICAL_SYN as apcd on FINAL_COHORT.ID = apcd.ID;
quit;

proc sql;
create table FINAL_COHORT as select *,
case
when ID in (select ID from HCV_DIAG_COHORT) then 1
else 0
end as HCV_DIAG
from FINAL_COHORT;
quit;

/* Step 1: Sort the datasets by ID and date variables */
proc sort data=PHD.HCV_SYN2;
    by ID EVENT_DATE_HCV;
run;

proc sort data=PHD.APCD_MEDICAL_SYN;
    by ID MED_FROM_DATE;
run;

/* Step 2: Merge and find closest past and future MED_FROM_DATE */
data closest_date;
length closest_past_type closest_future_type closest_type $2 closest_past_city closest_future_city $50;
    merge PHD.HCV_SYN2 (in=a)
          PHD.APCD_MEDICAL_SYN (in=b);
    by ID;
    
    if a; /* Only process cohort IDs */

    retain closest_past_date closest_past_type min_past_diff closest_past_city;
    retain closest_future_date closest_future_type min_future_diff closest_future_city;

    /* Initialize for each ID group */
    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        closest_past_city = "";
        min_past_diff = .;
        closest_future_date = .;
        closest_future_type = "";
        closest_future_city = "";
        min_future_diff = .;
    end;

    /* Check and update for closest past date */
    if MED_FROM_DATE < EVENT_DATE_HCV then do;
        past_diff = EVENT_DATE_HCV - MED_FROM_DATE;
        if min_past_diff = . or past_diff < min_past_diff then do;
            min_past_diff = past_diff;
            closest_past_date = MED_FROM_DATE;
            closest_past_type = MED_INSURANCE_TYPE;
            closest_past_city = MED_PROV_CITY; /* Retain the city for the closest past date */
        end;
    end;

    /* Check and update for closest future date */
    else do; /* Only consider MED_FROM_DATE >= EVENT_DATE_HCV */
        future_diff = MED_FROM_DATE - EVENT_DATE_HCV;
        if min_future_diff = . or future_diff < min_future_diff then do;
            min_future_diff = future_diff;
            closest_future_date = MED_FROM_DATE;
            closest_future_type = MED_INSURANCE_TYPE;
            closest_future_city = MED_PROV_CITY; /* Retain the city for the closest future date */
        end;
    end;

    /* Output when processing the last record of each ID */
    if last.ID then do;
        /* Choose the closest available date */
        if min_past_diff ne . then do;
            closest_date = closest_past_date;
            closest_type = closest_past_type;
            closest_city = closest_past_city; /* Assign city for the closest past date */
        end;
        else do;
            closest_date = closest_future_date;
            closest_type = closest_future_type;
            closest_city = closest_future_city; /* Assign city for the closest future date */
        end;
        output;
    end;
run;


/* Step 3: Select and display relevant variables */
data final_output;
    set closest_date;
    keep ID EVENT_DATE_HCV closest_date closest_type closest_city;
run;

/* Step 1: Add closest_type from final_output to FINAL_COHORT */
proc sort data=FINAL_COHORT;
    by ID;
run;

proc sort data=final_output;
    by ID;
run;

data FINAL_COHORT;
    merge FINAL_COHORT (in=a)
          final_output (keep=ID closest_type closest_city rename=(closest_type=INSURANCE) rename=(closest_city=MED_PROV_CITY));
    by ID;
    if a; /* Keep all records from FINAL_COHORT */
run;

/* Step 1: Identify missing IDs from HCV dataset */
proc sql;
    create table missing_hcv as
    select f.ID, f.YOB, f.OUD_AGE,
           (f.YOB + f.OUD_AGE) as OUD_DIAGNOSIS_YEAR
    from FINAL_COHORT as f
    left join PHD.HCV_SYN2 as h on f.ID = h.ID
    where h.ID is null; /* Select IDs that are not in the HCV dataset */
quit;

/* Step 1: Sort the APCD dataset by ID and MED_FROM_DATE_YEAR (and MED_FROM_DATE_MONTH for earliest record) */
proc sort data=PHD.APCD_MEDICAL_SYN;
    by ID MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH;
run;

/* Step 2: Merge and find closest past and future MED_FROM_DATE */
data closest_date;
length closest_past_type closest_future_type closest_type $2 closest_past_city closest_future_city $50;
    merge missing_hcv (in=a)
          PHD.APCD_MEDICAL_SYN (in=b);
    by ID;
    
    if a; /* Only process matching IDs */

    retain closest_past_date closest_past_type min_past_diff closest_past_city;
    retain closest_future_date closest_future_type min_future_diff closest_future_city;

    /* Initialize for each ID group */
    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        closest_past_city = "";
        min_past_diff = .;
        closest_future_date = .;
        closest_future_type = "";
        closest_future_city = "";
        min_future_diff = .;
    end;

    /* Check and update for closest past date */
    if MED_FROM_DATE_YEAR < OUD_DIAGNOSIS_YEAR then do;
        past_diff = OUD_DIAGNOSIS_YEAR - MED_FROM_DATE_YEAR;
        if min_past_diff = . or past_diff < min_past_diff then do;
            min_past_diff = past_diff;
            closest_past_date = MED_FROM_DATE_YEAR;
            closest_past_type = MED_INSURANCE_TYPE;
            closest_past_city = MED_PROV_CITY; /* Retain the city for the closest past date */
        end;
    end;

    /* Check and update for closest future date */
    else do; /* Only consider MED_FROM_DATE_YEAR >= OUD_DIAGNOSIS_YEAR */
        future_diff = MED_FROM_DATE_YEAR - OUD_DIAGNOSIS_YEAR;
        if min_future_diff = . or future_diff < min_future_diff then do;
            min_future_diff = future_diff;
            closest_future_date = MED_FROM_DATE_YEAR;
            closest_future_type = MED_INSURANCE_TYPE;
            closest_future_city = MED_PROV_CITY; /* Retain the city for the closest future date */
        end;
    end;

    /* Output when processing the last record of each ID */
    if last.ID then do;
        /* Choose the closest available date */
        if min_past_diff ne . then do;
            closest_date = closest_past_date;
            closest_type = closest_past_type;
            closest_city = closest_past_city; /* Assign city for the closest past date */
        end;
        else do;
            closest_date = closest_future_date;
            closest_type = closest_future_type;
            closest_city = closest_future_city; /* Assign city for the closest future date */
        end;
        output;
    end;
run;

/* Step 3: Select and display relevant variables */
data final_output;
    set closest_date;
    keep ID closest_type closest_city;
run;

/* Step 1: Add closest_type from final_output to FINAL_COHORT */
proc sort data=FINAL_COHORT;
    by ID;
run;

proc sort data=final_output;
    by ID;
run;

data FINAL_COHORT;
    merge FINAL_COHORT (in=a)
          final_output (keep=ID closest_type closest_city rename=(closest_type=INSURANCE) rename=(closest_city=MED_PROV_CITY));
    by ID;
    if a; /* Keep all records from FINAL_COHORT */
run;

data FINAL_COHORT;
   set FINAL_COHORT;

   /* Create the new INSURANCE_CAT variable */
   length INSURANCE_CAT $10.; /* Allocate space for the new variable */
   
   /* Assign categories based on INSURANCE variable */
   if INSURANCE in ('12', '13', '14', '15', 'CE', 'CI', 'HM') then INSURANCE_CAT = 'Private'; /* Commercial Plans */
   else if INSURANCE in ('16', '20, 21', '30', 'HN', 'IC', 'MA', 'MB', 'MC', 'MD', 'MO', 'MP', 'MS', 'QM', 'SC') then INSURANCE_CAT = 'Public'; /* Medicare Plans */
   else INSURANCE_CAT = 'Other'; /* All other insurance types */

run;

data FINAL_COHORT;
   set FINAL_COHORT;
   
	if MED_PROV_CITY in (1,2,3,5,7,8,9,10,14,16,17,18,20,23,25,26,30,31,
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
	
	
	else if MED_PROV_CITY in (4,11,12,13,19,21,22,24,27,28,33,34,37,38,39,
	41,43,45,51,54,55,58,59,60,64,68,69,70,74,76,77,78,81,84,86,92,
	102,108,111,112,117,118,120,125,127,132,135,140,143,147,148,154,
	157,169,173,179,183,191,194,200,205,212,222,224,227,228,230,240,
	241,247,249,250,254,255,256,257,263,269,270,272,276,279,282,286,
	287,289,290,294,297,299,303,306,309,311,313,322,323,324,331,332,
	337,340, 343,345,349) then rural =1;
	
	else if MED_PROV_CITY in (6,104,15,29,47,53,62,63,66,89,90,91,98,106,
	109,113,114,121,124,129,130,150,152,156,190,192,193,195,197,202,
	203,204,209,217,221,223,225,233,234,235,237,242,253,260,267,268,
	283,296,300,302,312,318,319,326,327,341) then rural =2;
run;

/*====================*/
/*  TABLE 1			  */
/*====================*/

/* Define formats for various variables */
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
        3 = 'Another Language';

    value edu_fmt
        1 = 'HS or less'
        2 = '13+ years'
        3 = 'Not of School Age'
        8 = 'Missing in dataset'
        9 = 'Not collected'
        10 = 'Special Education';
run;

/* Macro to create frequency tables */
%macro Table1Freqs(var, format);
    title "Table 1, Unstratified";
    proc freq data=FINAL_COHORT;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

/* Calculate mean age excluding specific values */
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

/* Call macro for frequency tables */
%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY, flagf.);
%Table1Freqs(LANGUAGE, langfsecondary.);
%Table1Freqs(EDUCATION, edu_fmt.);
%Table1Freqs(FOREIGN_BORN, fbornf.);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(HCV_DIAG, flagf.);
%Table1Freqs(EVER_IDU_HCV_MAT, flagf.);
%Table1Freqs(mental_health_diag, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(OCCUPATION_CODE);
%Table1Freqs(EVER_MOUD, flagf.);
%Table1Freqs(INSURANCE_CAT);
%Table1Freqs(LD_PAY);
%Table1Freqs(KOTELCHUCK);
%Table1Freqs(prenat_site);
%Table1Freqs(rural);

data FINAL_COHORT;
    set FINAL_COHORT;

    /* Generate random numbers for each variable */
    random_number_HCV = rand("Uniform");
    random_number_DAA = rand("Uniform");
    random_number_MOUD = rand("Uniform");
    random_number_HIV = rand("Uniform");

    /* Impute values based on the random numbers */
    HCV_PRIMARY_DIAG = (random_number_HCV >= 0.5);
    DAA_START_INDICATOR = (random_number_DAA >= 0.5);
    EVER_MOUD = (random_number_MOUD >= 0.5);
    HIV_DIAG = (random_number_HIV >= 0.5);

    /* Drop the random number variables */
    drop random_number_HCV random_number_DAA random_number_MOUD random_number_HIV;
run;

%macro Table2Linkage(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model HCV_PRIMARY_DIAG(event='1') = &var / dist=binary link=logit solution oddsratio;
    		random intercept;
	run;
%mend;

%Table2Linkage(FINAL_RE, ref ='1');
%Table2Linkage(EVER_INCARCERATED, ref ='0');
%Table2Linkage(HOMELESS_HISTORY, ref ='0');
%Table2Linkage(LANGUAGE, ref ='1');
%Table2Linkage(EDUCATION, ref ='1');
%Table2Linkage(FOREIGN_BORN, ref ='0');
%Table2Linkage(HIV_DIAG, ref ='0');
%Table2Linkage(HCV_DIAG, ref ='0');
%Table2Linkage(EVER_IDU_HCV_MAT, ref ='0');
%Table2Linkage(mental_health_diag, ref ='0');
%Table2Linkage(OTHER_SUBSTANCE_USE, ref ='0');
%Table2Linkage(iji_diag, ref ='0');
%Table2Linkage(OCCUPATION_CODE, ref ='0');
%Table2Linkage(EVER_MOUD, ref ='0');
%Table2Linkage(INSURANCE_CAT, ref ='Public');
%Table2Linkage(LD_PAY, ref ='1');
%Table2Linkage(KOTELCHUCK, ref ='3');
%Table2Linkage(prenat_site, ref ='1');
%Table2Linkage(rural, ref ='1');

%macro Table2Treatment(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model DAA_START_INDICATOR(event='1') = &var / dist=binary link=logit solution oddsratio;
    		random intercept;
	run;
%mend;

%Table2Treatment(FINAL_RE, ref ='1');
%Table2Treatment(EVER_INCARCERATED, ref ='0');
%Table2Treatment(HOMELESS_HISTORY, ref ='0');
%Table2Treatment(LANGUAGE, ref ='1');
%Table2Treatment(EDUCATION, ref ='1');
%Table2Treatment(FOREIGN_BORN, ref ='0');
%Table2Treatment(HIV_DIAG, ref ='0');
%Table2Treatment(HCV_DIAG, ref ='0');
%Table2Treatment(EVER_IDU_HCV_MAT, ref ='0');
%Table2Treatment(mental_health_diag, ref ='0');
%Table2Treatment(OTHER_SUBSTANCE_USE, ref ='0');
%Table2Treatment(iji_diag, ref ='0');
%Table2Treatment(OCCUPATION_CODE, ref ='0');
%Table2Treatment(EVER_MOUD, ref ='0');
%Table2Treatment(INSURANCE_CAT, ref ='Public');
%Table2Treatment(LD_PAY, ref ='1');
%Table2Treatment(KOTELCHUCK, ref ='3');
%Table2Treatment(prenat_site, ref ='1');
%Table2Treatment(rural, ref ='1');
