/*==============================================*/
/* Project: Infant Cascade      				*/
/* Author:  BB / SM 		                    */ 
/* Created: 12/16/2022 							*/
/* Updated: 10/02/2024 by SM           			*/
/*==============================================*/

/*	Project Goal:
	Characterize and model the HCV care cascade of infants and children born to mothers seropositive for HCV

    Part 1: Construct OUD cohort to eventually link maternal OUD and injection states to deliveries
        Note: This is a large portion of Ryan's RESPOND code. Part 1, though quite long and ancillary to the infant analysis, 
        is necessary so that we can include OUD_CAPTURE and EVER_IDU_HCV_MAT variables in the cohort chracteristic tables and regression
    Part 2: HCV Care Cascade for Infants
    Part 3: HCV Care Cascade for Children <= 15 years of age
    Part 4: Cohort Tables for manuscript
    Part 5: Collinearity and MV Regressions

	Cleaning notes: Multiple INFANT_IDS matched to more than one BIRTH_LINK_ID
					Multiple BIRTH_LINK_IDs matched to more than one mom

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

/* HD PROC DATA */

DATA hd_proc(KEEP= HD_ID oud_hd_proc);
	SET PHDCM.HD_PROC(KEEP = HD_ID HD_PROC);
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
        IF SUBSTR(VNAME(vars2[k]), 1) = 'OO_PROC' THEN 
            IF vars2[k] IN &PROC THEN 
                cnt_oud_oo = cnt_oud_oo + 1;
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
    SELECT DISTINCT ID, oud_age, age_grp_five as agegrp, FINAL_RE FROM oud;
QUIT;

/*============================ */
/* 12. ADD PREGANANCY          */
/*============================ */

DATA all_births (keep = ID BIRTH_INDICATOR YEAR_BIRTH);
	SET PHDBIRTH.BIRTH_MOM (KEEP = ID YEAR_BIRTH
							WHERE= (2014 <= YEAR_BIRTH <= 2021));
	BIRTH_INDICATOR = 1;
run;

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
	CASE WHEN min(DISEASE_STATUS_HCV) = 1 THEN 1 ELSE 0 END as CONFIRMED_HCV_INDICATOR FROM PHDHEPC.HCV
	GROUP BY ID;
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
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_ADM_TYPE MED_ICD1
					 
					 WHERE = (MED_ICD1 IN &HCV_ICD));
RUN;

PROC SQL;
CREATE TABLE HCV_LINKED AS 
SELECT ID,
 1 as HCV_PRIMARY_DIAG,
 min(MED_FROM_DATE) as FIRST_HCV_PRIMARY_DIAG_DATE
from HCV_LINKED_SAS
GROUP BY ID;
QUIT;

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

DATA DAA; SET PHDAPCD.MOUD_PHARM (KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
								WHERE = (PHARM_NDC IN &DAA_CODES));
RUN;

PROC SQL;
CREATE TABLE DAA_STARTS as
SELECT ID,
	   min(PHARM_AGE) as PHARM_AGE,
	   min(PHARM_FILL_DATE_YEAR) as FIRST_DAA_START_YEAR,
	   min(PHARM_FILL_DATE) as FIRST_DAA_DATE,
	   1 as DAA_START_INDICATOR from DAA
GROUP BY ID;
QUIT;

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

/*====================*/
/* 18. Final OUD cohort */
/*====================*/

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM OUD_HCV_DAA;
QUIT;

%put Number of unique IDs in OUD_HCV_DAA table: &num_unique_ids;

data OUD_HCV_DAA;
    set OUD_HCV_DAA(rename=(ID=MOM_ID));
run;

/*============================ */
/*  Part 2: HCV Care Cascade for Infants */
/*============================ */

/*====================*/
/* 1. HCV Diagnosis and Serostatus Information */
/*====================*/
/* This step collects all HCV seropositive patients, ensuring only the first HCV event for each (ID) is retained: 
   It aggregates by ID (renamed MOM_ID) and removes duplicates using the MIN function to select the earliest 
   EVENT_DATE_HCV (the date of diagnosis/first symptom) and DISEASE_STATUS_HCV (1 for confirmed, 2 if probable ). */
   
PROC SQL;
CREATE TABLE HCV
AS SELECT ID as MOM_ID,
		  MIN(EVENT_DATE_HCV) as MOM_EVENT_DATE_HCV,
		  MIN(DISEASE_STATUS_HCV) as MOM_DISEASE_STATUS_HCV
FROM PHDHEPC.HCV
GROUP BY MOM_ID;
run;

/*====================*/
/* 2. Collect Birth Records for Mothers */
/*====================*/
/* This step collects all birth records for mothers, aggregating birth data by BIRTH_LINK_ID. 
   For each mother, we calculate the earliest infant birth date (DOB_MOM_TBL) and count the number of mothers associated with each birth.
   We then filter the birth records to keep only cases where a single MOM_ID is associated with each BIRTH_LINK_ID, ensuring one mother per birth.
   Notes: DOB_MOM_TBL must be defined separately from DOB_INFANT_TBL because the anchor proxy date is unique to each individual. */

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

DATA MOMS; SET MOMS (WHERE = (num_moms = 1));
run;

/*====================*/
/* 3. Collect Birth Records for Infants */
/*====================*/
/* This step collects infant birth records, aggregating by INFANT_ID and BIRTH_LINK_ID. 
   It retains the earliest birth date for each infant (DOB_INFANT_TBL) and counts the number of births associated with each BIRTH_LINK_ID.
   Then, we filter the infant records to ensure that each INFANT_ID is associated with only one BIRTH_LINK_ID. */

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

DATA INFANTS; SET INFANTS (WHERE = (num_births = 1));
run;

/*====================*/
/* 4. Combine HCV, Mother, and Infant Data */
/*====================*/
/* Here, we merge the HCV data with mother and infant data using MOM_ID and BIRTH_LINK_ID as keys. 
   This results in a dataset that links HCV diagnosis data for mothers to their corresponding births and infants.
   We then count how many BIRTH_LINK_IDs are associated with each infant to track multiple births per infant and
   delete all non-mothers by restricting the dataset to mothers with only one associated BIRTH_LINK_ID. */

PROC SQL; 
 CREATE TABLE HCV_MOMS 
 AS SELECT DISTINCT * FROM HCV 
 LEFT JOIN MOMS on HCV.MOM_ID = MOMS.MOM_ID 
 LEFT JOIN INFANTS on MOMS.BIRTH_LINK_ID = INFANTS.BIRTH_LINK_ID; 
 quit; 

PROC SQL;
CREATE TABLE HCV_MOMS
AS SELECT DISTINCT *, COUNT(DISTINCT BIRTH_LINK_ID) as num_infant_birth_ids FROM HCV_MOMS
GROUP BY INFANT_ID;
quit;

DATA HCV_MOMS; SET HCV_MOMS (WHERE = (num_infant_birth_ids = 1)); 
run;

/*====================*/
/* 5. Filter for women who were seropositive prior to birth */
/*====================*/
/* This step removes observations if the HCV case report occured after delivery. */

DATA HCV_MOMS; SET HCV_MOMS;
	IF  BIRTH_INDICATOR = . THEN DELETE;
	IF  DOB_MOM_TBL < MOM_EVENT_DATE_HCV THEN DELETE;
run;

/*====================*/
/* 6. Add MOUD Data and Flag MOUD Episodes */
/*====================*/
/* This step adds MOUD varaibles to calculate whether the MOUD occurred during pregnancy or at delivery. */

proc sql;
    create table HCV_MOMS as
    select HCV_MOMS.*,
           moud.DATE_START_MOUD,
           moud.DATE_END_MOUD
    from HCV_MOMS
    left join PHDSPINE.MOUD as moud 
    on moud.ID = HCV_MOMS.MOM_ID;
quit;

/* This step checks the time difference between the mother's date of birth (DOB_MOM_TBL) and the start/end dates of MOUD (DATE_START_MOUD, DATE_END_MOUD). 
Flags are created for MOUD during pregnancy (MOUD_DURING_PREG) and MOUD at delivery (MOUD_AT_DELIVERY). */

data HCV_MOMS;
    set HCV_MOMS;

    if missing(DOB_MOM_TBL) then do;
        MOUD_DURING_PREG = .;
        MOUD_AT_DELIVERY = .;
    end;
    else do;

    days_difference_start = DATE_START_MOUD - DOB_MOM_TBL ;

        days_difference_end = DATE_END_MOUD - DOB_MOM_TBL ;

        MOUD_DURING_PREG = (days_difference_start >= -280 AND days_difference_start <= 0) OR
                                 (days_difference_end >= -280 AND days_difference_end <= 0) OR
                                 (days_difference_start <= -280 AND DATE_END_MOUD > DOB_MOM_TBL);

        MOUD_AT_DELIVERY = 	(days_difference_start >= -60 AND days_difference_start <= 0) OR
                            (days_difference_end >= -60 AND days_difference_end <= 0) OR
                            (days_difference_start <= -60 AND DATE_END_MOUD > DOB_MOM_TBL);

        drop days_difference_start days_difference_end;
    end;
run;

/* Group multiple records by the same BIRTH_LINK_ID for deduplication. */

proc sort data=HCV_MOMS;
    by BIRTH_LINK_ID;
run;

/* This step processes each group of MOUD episodes related to the same BIRTH_LINK_ID. 
For each group, it sets flags (`any_MOUD_DURING_PREG`, `any_MOUD_AT_DELIVERY`) to 1 if any episode in the group meets the conditions for MOUD during pregnancy or at delivery. 
It then retains these flags for each group and outputs only the final observation for each group to deduplicate the dataset, accounting for multiple births (twins, triplets).
We only want to count one infant per BIRTH because we would be overrepresenting covariates in the regressions */

data HCV_MOMS;
    set HCV_MOMS;
    by BIRTH_LINK_ID;
    
    retain any_MOUD_DURING_PREG any_MOUD_AT_DELIVERY 0;
    
    if first.BIRTH_LINK_ID then do;
        any_MOUD_DURING_PREG = 0;
        any_MOUD_AT_DELIVERY = 0;
    end;
    
    if MOUD_DURING_PREG = 1 then any_MOUD_DURING_PREG = 1;
    if MOUD_AT_DELIVERY = 1 then any_MOUD_AT_DELIVERY = 1;
    
    if last.BIRTH_LINK_ID then do;
        output;
    end;
    
    drop MOUD_DURING_PREG MOUD_AT_DELIVERY;
run;

data HCV_MOMS;
    set HCV_MOMS;
    rename any_MOUD_DURING_PREG = MOUD_DURING_PREG
           any_MOUD_AT_DELIVERY = MOUD_AT_DELIVERY;
run;

/*====================*/
/* 7. Calculate HCV Duration */
/*====================*/
/* This step calculates the duration of time between HCV diagnosis and birth for each mother. */

data HCV_MOMS;
    set HCV_MOMS;

    hcv_duration_count = MOM_EVENT_DATE_HCV - DOB_MOM_TBL ;

run;

/*====================*/
/* 8. Add HIV Diagnosis Data */
/*====================*/
/* This step adds HIV diagnosis data for each mother and flags whether HIV was diagnosed before the infant's birth. */

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

    if DIAGNOSIS_DATE_HIV < DOB_MOM_TBL and DIAGNOSIS_DATE_HIV ne . then
        HIV_DIAGNOSIS = 1;
    else
        HIV_DIAGNOSIS = 0;
        
run;

proc sort data=HCV_MOMS;
    by BIRTH_LINK_ID;
run;

/* This step processes each HIV diagnosis related to the same BIRTH_LINK_ID. 
For each BIRTH_LINK_ID, it flags (any_HIV_DIAGNOSIS) to 1 if any observation flags for diagnsosis within the BIRTH_LINK_ID.
It then retains these flags for each group and outputs only the final observation for each group to deduplicate multiple diagnoses back to a unqiue BIRTH_LINK_ID. */

data HCV_MOMS;
    set HCV_MOMS;
    by BIRTH_LINK_ID;
    
    retain any_HIV_DIAGNOSIS 0;
    
    if first.BIRTH_LINK_ID then any_HIV_DIAGNOSIS = 0;
    
    if HIV_DIAGNOSIS = 1 then any_HIV_DIAGNOSIS = 1;
    
    if last.BIRTH_LINK_ID then do;
        output;
    end;
    
    drop HIV_DIAGNOSIS;
run;

data HCV_MOMS;
    set HCV_MOMS;
    rename any_HIV_DIAGNOSIS = HIV_DIAGNOSIS;
run;

/*====================*/
/* 9. Add Demographic Data */
/*====================*/
/* This step merges demographic information, such as race, sex, and insurance status, for each mother-infant pair and restricts the cohort to exposed infants (delivery of a liveborn) born 2014-2021 */

PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX, YOB, APCD_anyclaim, SELF_FUNDED, LANGUAGE, FOREIGN_BORN
	FROM PHDSPINE.DEMO;
	QUIT;

PROC SQL;
CREATE TABLE TOTAL_APCD_INFANT_COHORT AS
SELECT DISTINCT 
    M.MOM_ID,
    M.INFANT_ID,
    M.BIRTH_LINK_ID,
    M.INFANT_YEAR_BIRTH,
    M.MONTH_BIRTH,
    M.DOB_INFANT_TBL,
    M.DOB_MOM_TBL,
    M.MOM_DISEASE_STATUS_HCV,
    M.MOM_EVENT_DATE_HCV,
    D.FINAL_RE,
    D.FINAL_SEX,
    M.HIV_DIAGNOSIS,
    M.MOUD_DURING_PREG,
    M.MOUD_AT_DELIVERY,
    D.APCD_anyclaim,
    D.SELF_FUNDED
FROM HCV_MOMS AS M
LEFT JOIN demographics AS D
    ON M.INFANT_ID = D.ID;
QUIT;

data TOTAL_APCD_INFANT_COHORT;
    set TOTAL_APCD_INFANT_COHORT;
    where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2021;
run;

/* ========================================================== */
/* 10. Extract AB/RNA/GENOTYPE Testing Data                    */
/* ========================================================== */
/* Extract antibody/rna/genotype testing records (CPT codes) from the PHDAPCD.MOUD_MEDICAL dataset.
Then, remove duplicate testing records based on unique combinations of ID and testing date and sort by ID and testing date in ascending order. 
Transpose the testing dates for each individual into wide format to create multiple columns for testing dates. 
Extract the year from the testing records for each ID and creates a new dataset that includes distinct IDs, testing years, and age at testing.
Select the earliest testing year for each ID and output the frequency of tests occurring in infants under the age of 4. */

/* AB */

DATA ab;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR MED_AGE					 
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

/* RNA */

DATA rna;
SET PHDAPCD.MOUD_MEDICAL(KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR MED_AGE
					 
					 WHERE = (MED_PROC_CODE IN  &RNA_CPT));
run;

proc sql;
create table rna1 as
select distinct ID, MED_FROM_DATE, *
from rna;
quit;

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

/* GENOTYPE */

DATA geno;
SET PHDAPCD.MOUD_MEDICAL(KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
					 WHERE = (MED_PROC_CODE IN  &GENO_CPT));
run;

PROC SORT data=geno;
  by ID MED_FROM_DATE;
RUN;

PROC TRANSPOSE data=geno out=geno_wide (KEEP = ID GENO_TEST_DATE:) PREFIX=GENO_TEST_DATE_;
BY ID;
VAR MED_FROM_DATE;
RUN;

/* ========================================================== */
/* 11. Join All Testing Data with Infant Cohort and Create HCV Testing Indicators */
/* ========================================================== */
/* This step joins antibody, RNA, and genotype testing data to the main TOTAL_APCD_INFANT_COHORT dataset based on the INFANT_ID and
creates indicators for whether infants had antibody, RNA, and any HCV testing. */

PROC SQL;
    CREATE TABLE INFANT_TESTING AS
    SELECT * FROM TOTAL_APCD_INFANT_COHORT 
    LEFT JOIN ab_wide ON ab_wide.ID = TOTAL_APCD_INFANT_COHORT.INFANT_ID
    LEFT JOIN rna_wide ON rna_wide.ID = TOTAL_APCD_INFANT_COHORT.INFANT_ID
    LEFT JOIN geno_wide ON geno_wide.ID = TOTAL_APCD_INFANT_COHORT.INFANT_ID;
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

Proc sort data=INFANT_TESTING; by INFANT_ID; run;

/* ========================================================== */
/* 12. Create HCV Testing Indicators and Appropriate Testing Flags */
/* ========================================================== */
/* This step processes the joined infant cohort data to create indicators for appropriate HCV testing, 
calculates age at first HCV test, and determines if testing meets specific timing criteria. */

DATA INFANT_TESTING;
    SET INFANT_TESTING;
    by INFANT_ID;

    array RNA_TESTS (*) RNA_TEST_DATE_:;
    array AB_TESTS (*) AB_TEST_DATE_:;
    num_rna_tests = dim(RNA_TESTS);
    num_ab_tests = dim(AB_TESTS);

    retain APPROPRIATE_AB_Testing APPROPRIATE_RNA_Testing APPROPRIATE_Testing 
           AGE_AT_FIRST_TEST AGE_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST;

    IF first.INFANT_ID THEN DO;
        APPROPRIATE_AB_Testing = 0; APPROPRIATE_RNA_Testing = 0;
        APPROPRIATE_Testing = 0; AGE_AT_FIRST_TEST = .; AGE_AT_FIRST_AB_TEST = .; AGE_AT_FIRST_RNA_TEST = .;
    END;

    DO i=1 TO num_rna_tests;
        IF AGE_AT_FIRST_RNA_TEST = . AND RNA_TESTS(i) NE . THEN
            AGE_AT_FIRST_RNA_TEST = FLOOR((RNA_TESTS(i) - DOB_INFANT_TBL)/30.4);
        IF (RNA_TESTS(i) - DOB_INFANT_TBL) > 60 THEN
            APPROPRIATE_RNA_Testing = 1;
    END;

    DO i=1 TO num_ab_tests;
        IF AGE_AT_FIRST_AB_TEST = . AND AB_TESTS(i) NE . THEN
            AGE_AT_FIRST_AB_TEST = FLOOR((AB_TESTS(i) - DOB_INFANT_TBL)/30.4);
        IF (AB_TESTS(i) - DOB_INFANT_TBL) > 547 THEN
            APPROPRIATE_AB_Testing = 1;
    END;

    IF APPROPRIATE_AB_Testing = 1 OR APPROPRIATE_RNA_Testing = 1 THEN
        APPROPRIATE_Testing = 1;

    IF AGE_AT_FIRST_AB_TEST NE . AND AGE_AT_FIRST_RNA_TEST NE . THEN
        AGE_AT_FIRST_TEST = MIN(AGE_AT_FIRST_AB_TEST, AGE_AT_FIRST_RNA_TEST);
    ELSE IF AGE_AT_FIRST_AB_TEST NE . THEN
        AGE_AT_FIRST_TEST = AGE_AT_FIRST_AB_TEST;
    ELSE IF AGE_AT_FIRST_RNA_TEST NE . THEN
        AGE_AT_FIRST_TEST = AGE_AT_FIRST_RNA_TEST;

    IF AGE_AT_FIRST_AB_TEST > 30 THEN AGE_YRS_AT_FIRST_AB_TEST = FLOOR(AGE_AT_FIRST_AB_TEST/12);
    IF AGE_AT_FIRST_RNA_TEST > 18 THEN AGE_YRS_AT_FIRST_RNA_TEST = FLOOR(AGE_AT_FIRST_RNA_TEST/12);
    IF AGE_AT_FIRST_TEST > 30 THEN AGE_YRS_AT_FIRST_TEST = FLOOR(AGE_AT_FIRST_TEST/12);

    DROP i;

RUN;

/* ========================================================== */
/* 13. Extract HCV Status from MAVEN Database                  */
/* ========================================================== */
/* This section retrieves the HCV diagnosis status for each infant from the MAVEN database,
   calculates the age at diagnosis, and creates indicators for HCV seropositivity and confirmed HCV. */

PROC SQL;
    CREATE TABLE HCV_STATUS AS
    SELECT DISTINCT 
        ID,
        MIN(EVENT_YEAR_HCV) AS EVENT_YEAR_HCV,
        MIN(EVENT_DATE_HCV) AS EVENT_DATE_HCV,
        MIN(AGE_HCV) AS AGE_AT_DX,
        1 AS HCV_SEROPOSITIVE_INDICATOR,
        CASE 
            WHEN MIN(DISEASE_STATUS_HCV) = 1 THEN 1 
            ELSE 0 
        END AS CONFIRMED_HCV_INDICATOR 
    FROM 
        PHDHEPC.HCV
    GROUP BY 
        ID;
QUIT;

PROC SQL;
    CREATE TABLE INFANT_HCV_STATUS AS
    SELECT * FROM INFANT_TESTING 
    LEFT JOIN HCV_STATUS ON HCV_STATUS.ID = INFANT_TESTING.INFANT_ID;
QUIT;

/* ========================================================== */
/* 14. Linkage to HCV Care                                     */
/* ========================================================== */
/* This section retrieves medical records related to HCV care from the MOUD_MEDICAL dataset,
   filters based on relevant ICD codes, and creates a dataset for infants linked to HCV care. */

DATA HCV_LINKED_SAS;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_ADM_TYPE MED_ICD1
					 
					 WHERE = (MED_ICD1 IN &HCV_ICD));
RUN;

PROC SQL;
CREATE TABLE HCV_LINKED AS 
SELECT ID,
 	   1 as HCV_PRIMARY_DIAG,
       min(MED_FROM_DATE) as FIRST_HCV_PRIMARY_DIAG_DATE
from HCV_LINKED_SAS
GROUP BY ID;
QUIT;

PROC SQL;
    CREATE TABLE INFANT_LINKED AS
    SELECT * FROM INFANT_HCV_STATUS
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = INFANT_HCV_STATUS.INFANT_ID;
QUIT;
  
DATA INFANT_LINKED; SET INFANT_LINKED;
IF HCV_PRIMARY_DIAG = . THEN HCV_PRIMARY_DIAG = 0;
IF HCV_SEROPOSITIVE_INDICATOR = . THEN HCV_SEROPOSITIVE_INDICATOR = 0;
run;

/* ========================================================== */
/* 15. DAA (Direct-Acting Antiviral) Treatment Starts          */
/* ========================================================== */
/* This section identifies infants who started DAA treatment, reatins the first DAA start, calculates the age at DAA start,
   and creates indicators for DAA initiation. Additionally information of MOM DAA treatment is retained to exclude infants 
   whose mothers were treated prior to delivery in the final filtering criteria */

DATA DAA; SET PHDAPCD.MOUD_PHARM(KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
								WHERE = (PHARM_NDC IN &DAA_CODES));
RUN;

PROC SQL;
CREATE TABLE DAA_STARTS as
SELECT distinct ID,
	   min(PHARM_FILL_DATE_YEAR) as FIRST_DAA_START_YEAR,
	   min(PHARM_FILL_DATE) as FIRST_DAA_DATE,
       min(PHARM_AGE) as AGE_DAA_START,
		
	   1 as DAA_START_INDICATOR from DAA
GROUP BY ID;
QUIT;

PROC SQL;
   CREATE TABLE INFANT_DAA AS
   SELECT a.*, 
          b.FIRST_DAA_START_YEAR AS MOM_FIRST_DAA_START_YEAR,
          b.FIRST_DAA_DATE AS MOM_FIRST_DAA_DATE,
          b.AGE_DAA_START AS MOM_AGE_DAA_START,
          b.DAA_START_INDICATOR AS MOM_DAA_START_INDICATOR
   FROM INFANT_LINKED a
   LEFT JOIN DAA_STARTS b
   ON a.MOM_ID = b.ID;
QUIT;

PROC SQL;
   CREATE TABLE INFANT_DAA AS
   SELECT a.*, 
          c.FIRST_DAA_START_YEAR AS INFANT_FIRST_DAA_START_YEAR,
          c.FIRST_DAA_DATE AS INFANT_FIRST_DAA_DATE,
          c.AGE_DAA_START AS INFANT_AGE_DAA_START,
          c.DAA_START_INDICATOR AS INFANT_DAA_START_INDICATOR
   FROM INFANT_DAA a
   LEFT JOIN DAA_STARTS c
   ON a.INFANT_ID = c.ID;
QUIT;

DATA INFANT_DAA; SET INFANT_DAA;
IF MOM_DAA_START_INDICATOR = . THEN MOM_DAA_START_INDICATOR = 0;
IF INFANT_DAA_START_INDICATOR = . THEN INFANT_DAA_START_INDICATOR = 0;
run;

/* ========================================================== */
/* 16. End of Treatment (EOT) and Sustained Virologic Response (SVR12) RNA Testing */
/* ========================================================== */
/* This section processes the RNA test dates to determine if infants received an EOT or SVR12 RNA test after starting DAA treatment. */

DATA TESTING;
    SET INFANT_DAA;
    EOT_RNA_TEST = 0;
    SVR12_RNA_TEST = 0;

    array test_date_array (*) RNA_TEST_DATE_:;
    num_tests = dim(test_date_array);

    do i = 1 to num_tests;
        if test_date_array{i} > 0 and INFANT_FIRST_DAA_DATE > 0 then do;
            time_since = test_date_array{i} - INFANT_FIRST_DAA_DATE;

            if time_since > 84 then EOT_RNA_TEST = 1;
            if time_since >= 140 then SVR12_RNA_TEST = 1;
        end;
    end;

    DROP i time_since;
RUN;

/*====================*/
/* 17. Filter final TESTING cohort */
/*====================*/
/* NOTE: The HCV dataset is only updated through 2021, so our inclusion criteria remains :
HCV case report data between 2011-2021 (inherently from HEPC dataset) and a delivery of a liveborn between 2014-2021;
Testing cohort includes infants born 2014 (first year APCD in dataset) through 2020 (at least 18mo old by study end);
Linkage to care and treatment cohorts inlcudes children born January 2014 - June 2019 (at least 3 yo by study end); */

/* So, in this step, we create FILTERED_INFANT_COHORT that retains only infants with insurance claims (APCD_anyclaim) born 2014-2021 (we restict on YOB in the precursor TOTAL_APCD_INFANT_COHORT), 
excluding those who died before reaching 18 months of age. We also filter the FILTERED_INFANT_COHORT dataset to exlcude infants whose mothers had a DAA prescription prior to the time of birth.
We can then restrict linkage to care and treatment cohorts further to children born January 2014 - June 2019. Then, Count Unique Infants in Final Dataset. */

DATA FILTERED_INFANT_COHORT;
    SET TESTING;
    IF APCD_anyclaim = 1 AND SELF_FUNDED = 0 THEN OUTPUT;
RUN;

PROC SQL;
    CREATE TABLE FILTERED_INFANT_COHORT AS
    SELECT cohort.*
    FROM FILTERED_INFANT_COHORT AS cohort
    LEFT JOIN PHDDEATH.DEATH AS death
    ON cohort.INFANT_ID = death.ID
    WHERE (death.DOD - cohort.DOB_INFANT_TBL) >= 30 * 18
       OR death.DOD IS NULL;
QUIT;

data delivery_counts_by_daa;
    set FILTERED_INFANT_COHORT;

    if missing(MOM_FIRST_DAA_DATE) then Treatment_Status = "Untreated";
    else if MOM_FIRST_DAA_DATE <= DOB_MOM_TBL then Treatment_Status = "Tx Before Delivery";
    else if MOM_FIRST_DAA_DATE > DOB_MOM_TBL then Treatment_Status = "Tx After Delivery";
run;

proc freq data=delivery_counts_by_daa;
    tables Treatment_Status / nocum;
    title "Counts of Infants Born to Untreated vs. Treated Mothers";
run;

DATA FILTERED_INFANT_COHORT;
    SET FILTERED_INFANT_COHORT;
    IF MOM_FIRST_DAA_DATE NE . THEN DO;
        IF DOB_MOM_TBL > MOM_FIRST_DAA_DATE THEN DELETE;
    END;
RUN;

PROC SQL;
    SELECT COUNT(DISTINCT BIRTH_LINK_ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FILTERED_INFANT_COHORT;
QUIT;

%put Number of unique BIRTH_LINK_IDs in FILTERED_INFANT_COHORT table: &num_unique_ids;

PROC CONTENTS data=FILTERED_INFANT_COHORT;
title "Contents of Final FILTERED_INFANT_COHORT Dataset";
run;

/* ========================================================== */
/* 18. FOMRAT CASCADE TABLES                                   */
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
/* 19. OUTPUT: HCV-EXPOSED INFANT TESTING CARE CASCADE TABLES */
/* ========================================================== */

title "Total Exposed Cohort: Infants born to moms with HCV born 2014-2021";
proc freq data=TOTAL_APCD_INFANT_COHORT;
    tables INFANT_YEAR_BIRTH / missing norow nopercent nocol; 
run;

title "Filtered Cohort: Infants born to moms with HCV born 2014-2021";
proc freq data=FILTERED_INFANT_COHORT;
    tables INFANT_YEAR_BIRTH / missing norow nopercent nocol; 
run;

title "Testing Cohort: Infants born to moms with HCV, Testing and Diagnosis, Overall, born 2014-2020";
proc freq data=FILTERED_INFANT_COHORT;
    tables ANY_HCV_TESTING_INDICATOR
           APPROPRIATE_Testing
           CONFIRMED_HCV_INDICATOR
           INFANT_DAA_START_INDICATOR / missing norow nopercent nocol;
           where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020;
run;

proc sort data=FILTERED_INFANT_COHORT;
	by APPROPRIATE_RNA_Testing;
run;

proc freq data=FILTERED_INFANT_COHORT;
    by APPROPRIATE_RNA_Testing;
    tables APPROPRIATE_AB_Testing
    		CONFIRMED_HCV_INDICATOR / missing norow nopercent nocol;
            where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020;
run;

proc sort data=FILTERED_INFANT_COHORT;
    by INFANT_YEAR_BIRTH APPROPRIATE_AB_TESTING;
run;

proc freq data=FILTERED_INFANT_COHORT;
    by INFANT_YEAR_BIRTH APPROPRIATE_AB_TESTING;
    tables APPROPRIATE_RNA_Testing / missing norow nopercent nocol;
            where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020;
run;

title "Testing Cohort: Infants with confirmed perinatal HCV only, unstratified, born 2014-2020 - ie age at dx <3";
proc freq data=FILTERED_INFANT_COHORT;
    tables ANY_HCV_TESTING_INDICATOR GENO_TEST_INDICATOR HCV_PRIMARY_DIAG INFANT_DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST / missing norow nopercent nocol;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2020 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3;
run;

title "Treatment Cohort: Infants with confirmed perinatal HCV only, unstratified, born 1/2014-6/2019, Confirmed HCV";
proc freq data=FILTERED_INFANT_COHORT;
    tables ANY_HCV_TESTING_INDICATOR GENO_TEST_INDICATOR HCV_PRIMARY_DIAG INFANT_DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST / missing norow nopercent nocol;
    Where (INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <=2018 OR (INFANT_YEAR_BIRTH=2019 AND MONTH_BIRTH<=6))
    AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
run;

title "Total Exposed Cohort: Total Number of EXPOSED Infants in Cohort, By Race, born 2014-2021";
proc freq data=TOTAL_APCD_INFANT_COHORT;
	table final_re / missing norow nopercent nocol;
	FORMAT final_re racefmt_all.;
run;

proc sort data=FILTERED_INFANT_COHORT;
    by final_re;
run;

title "Testing Cohort: Infants born to moms with HCV, TESTING/DIAGNOSIS Care Cascade, By Race, 2014-2020";
proc freq data=FILTERED_INFANT_COHORT;
    by final_re;
    tables ANY_HCV_TESTING_INDICATOR
           APPROPRIATE_Testing
           CONFIRMED_HCV_INDICATOR / missing norow nopercent nocol;
           where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020;

run;

title "Testing Cohort: Infants born to moms with HCV, Care Cascade, By Race/Hispanic Ethnicity, born 2014-2020 - ie age at dx <3";
proc freq data=FILTERED_INFANT_COHORT;
    by final_re;
    tables CONFIRMED_HCV_INDICATOR
           HCV_PRIMARY_DIAG
           GENO_TEST_INDICATOR / missing norow nopercent nocol;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2020 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3;
run;

title "Treatment Cohort: Infants born to moms with HCV, Care Cascade, By Race/Hispanic Ethnicity, born 2014-2020, Confirmed Perinatal HCV";
proc freq data=FILTERED_INFANT_COHORT;
    by final_re;
    tables CONFIRMED_HCV_INDICATOR
           HCV_PRIMARY_DIAG
           GENO_TEST_INDICATOR / missing norow nopercent nocol;
    Where (INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <=2018 OR (INFANT_YEAR_BIRTH=2019 AND MONTH_BIRTH<=6))
    AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
run;

title "Testing Cohort: Number of Infants Born by YEAR & Age at first appropriate Ab, RNA testing, 2014-2020";
proc freq data=FILTERED_INFANT_COHORT;
    TABLES INFANT_YEAR_BIRTH AGE_AT_FIRST_AB_TEST AGE_YRS_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST AGE_YRS_AT_FIRST_RNA_TEST AGE_AT_FIRST_TEST AGE_YRS_AT_FIRST_TEST / missing norow nopercent nocol;
    where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020;
run;

title "Total Number of Birth Records by Year";
proc freq data=PHDBIRTH.BIRTH_INFANT;
    TABLE YEAR_BIRTH / missing norow nopercent nocol;
run;

title "Filtered Cohort: Total Number of Appropriately Tested Infants by YEAR";
proc freq data=FILTERED_INFANT_COHORT;
    TABLES INFANT_YEAR_BIRTH / missing norow nopercent nocol;
    where APPROPRIATE_Testing = 1;
run;

data Perinatally_Infected;
    set FILTERED_INFANT_COHORT;
    where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2020 
          and CONFIRMED_HCV_INDICATOR = 1 
          and AGE_AT_DX < 3;
    
    /* Identify test type while handling missing values */
    if missing(AGE_AT_FIRST_AB_TEST) and missing(AGE_AT_FIRST_RNA_TEST) then TEST_TYPE = "Unknown";
    else if not missing(AGE_AT_FIRST_AB_TEST) and missing(AGE_AT_FIRST_RNA_TEST) then TEST_TYPE = "Antibody";
    else if missing(AGE_AT_FIRST_AB_TEST) and not missing(AGE_AT_FIRST_RNA_TEST) then TEST_TYPE = "RNA";
    else if AGE_AT_FIRST_AB_TEST < AGE_AT_FIRST_RNA_TEST then TEST_TYPE = "Antibody";
    else if AGE_AT_FIRST_RNA_TEST < AGE_AT_FIRST_AB_TEST then TEST_TYPE = "RNA";
    else if AGE_AT_FIRST_AB_TEST = AGE_AT_FIRST_RNA_TEST then TEST_TYPE = "Both";
    else TEST_TYPE = "Unknown";
run;

proc sql;
    create table Test_Proportions as
    select 
        TEST_TYPE,
        count(*) as N,
        sum(HCV_PRIMARY_DIAG) as Linked_To_Care,
        sum(GENO_TEST_INDICATOR) as Genotype_Test,
        sum(INFANT_DAA_START_INDICATOR) as Treated_With_DAAs
    from Perinatally_Infected
    group by TEST_TYPE;
quit;

proc sql;
    create table Test_Proportions_Final as
    select 
        a.TEST_TYPE,
        a.N,
        a.Linked_To_Care,
        a.Genotype_Test,
        a.Treated_With_DAAs,
        (a.N / b.Total_Count) as Proportion format=percent8.2,
        (a.Linked_To_Care / a.N) as Proportion_Linked_To_Care format=percent8.2,
        (a.Genotype_Test / a.N) as Proportion_Genotype_Test format=percent8.2,
        (a.Treated_With_DAAs / a.N) as Proportion_Treated_With_DAAs format=percent8.2
    from Test_Proportions as a
    cross join 
        (select sum(N) as Total_Count from Test_Proportions) as b;
quit;

title "Perinatally Infected Children First Test Ab vs. RNA vs. Both: Linkage, GT, DAA Outcomes";
proc print data=Test_Proportions_Final noobs label;
    label TEST_TYPE = "Test Type"
          N = "Number of Children"
          Proportion = "Proportion of Total"
          Proportion_Linked_To_Care = "Proportion Linked to Care"
          Proportion_Genotype_Test = "Proportion with Genotype Test"
          Proportion_Treated_With_DAAs = "Proportion Treated with DAAs";
run;

/* ========================================================== */
/* Part 3: HCV Care Cascade for Children <= 15 years of age   */
/* ========================================================== */
/* This section creates a dataset (COHORT15) that includes unique IDs of children aged 15 or younger 
   diagnosed with HCV. It computes the minimum age, disease status, and event year for each ID and 
   assesses their history of injection drug use (IDU) based on the EVER_IDU_HCV variable. */

PROC SQL;
    CREATE TABLE COHORT15 AS
    SELECT DISTINCT 
        ID, 
        min(AGE_HCV) as AGE_HCV, 
        min(DISEASE_STATUS_HCV) as DISEASE_STATUS_HCV, 
        min(EVENT_YEAR_HCV) as EVENT_YEAR_HCV,
	CASE 
            WHEN SUM(EVER_IDU_HCV = 1) > 0 THEN 1 
            WHEN SUM(EVER_IDU_HCV = 0) > 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 0 
            WHEN SUM(EVER_IDU_HCV = 9) > 0 AND SUM(EVER_IDU_HCV = 0) <= 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 9 
            ELSE 9
       END AS EVER_IDU_HCV
    FROM PHDHEPC.HCV
    WHERE AGE_HCV <= 15 AND AGE_HCV NE .
    GROUP BY ID;
QUIT;

/* ========================================================== */
/* 2. Testing for HCV Testing Indicators                       */
/* ========================================================== */
/* This section merges the COHORT15 dataset with additional testing datasets (ab_wide, rna_wide, geno_wide)
   to identify HCV testing indicators for antibody, RNA, and genotype tests. */

PROC SQL;
    CREATE TABLE TESTING15 AS
    SELECT * FROM COHORT15 
    LEFT JOIN ab_wide ON ab_wide.ID = COHORT15.ID
    LEFT JOIN rna_wide ON rna_wide.ID = COHORT15.ID
    LEFT JOIN geno_wide ON geno_wide.ID = COHORT15.ID;
QUIT;

/* ========================================================== */
/* 3. Create HCV Testing Indicators                            */
/* ========================================================== */
/* This section initializes testing indicators for AB, RNA, and genotype tests, and 
creates a general indicator for any HCV testing performed. */

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

/* ========================================================== */
/* 4. Linkage to Care                                        */
/* ========================================================== */
/* This section links the testing data with HCV linkage data 
   to create a comprehensive dataset on HCV status for children. */

   PROC SQL;
    CREATE TABLE HCV_STATUS15 AS
    SELECT * FROM TESTING15 
    LEFT JOIN HCV_LINKED ON HCV_LINKED.ID = TESTING15.ID;
QUIT;

/* ========================================================== */
/* 5. DAA (Direct-Acting Antiviral) Treatment Starts         */
/* ========================================================== */
/* This section merges DAA treatment data with the HCV status dataset, 
   retaining information about when DAA treatment starts for each child and categorizing age at DAA start into groups. */

PROC SQL;
    CREATE TABLE DAA15 AS
    SELECT * FROM HCV_STATUS15 
    LEFT JOIN DAA_STARTS ON DAA_STARTS.ID = HCV_STATUS15.ID;
QUIT;

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

/* ========================================================== */
/* 6. Merge with Demographic Data                             */
/* ========================================================== */
/* This section adds demographic information to the DAA dataset 
   to provide context for treatment and health outcomes. */

PROC SQL;
    CREATE TABLE DAA15 AS
    SELECT * FROM DAA15 
    LEFT JOIN demographics ON demographics.ID = DAA15.ID;
QUIT;

/* ========================================================== */
/* 7. Calculate EOT and SVR12 RNA Test Indicators           */
/* ========================================================== */
/* This section assesses the time since the first DAA treatment 
   and sets indicators for end-of-treatment (EOT) and sustained virologic response 
   at 12 weeks (SVR12) based on RNA test dates. */

DATA TRT_TESTING15;
    SET DAA15;
    EOT_RNA_TEST = 0;
    SVR12_RNA_TEST = 0;

    array test_date_array (*) RNA_TEST_DATE_:;
    num_tests = dim(test_date_array);

    do i = 1 to num_tests;
            if test_date_array{i} > 0 and FIRST_DAA_DATE > 0 then do;
                time_since = test_date_array{i} - FIRST_DAA_DATE;

                if time_since > 84 then EOT_RNA_TEST = 1;
                if time_since >= 140 then SVR12_RNA_TEST = 1;
            end;
            else time_since = .;
        end;

    DROP i time_since;
RUN;

data DAA15;
    set DAA15;
    if DISEASE_STATUS_HCV = 1 and YOB <= 2018;
run;

data TRT_TESTING15;
    set TRT_TESTING15;
    if DISEASE_STATUS_HCV = 1 and YOB <= 2018;
run;

/* ========================================================== */
/* 8. OUTPUT: Frequency Tables for HCV Care Cascade          */
/* ========================================================== */

title "HCV Care Cascade for children diagnosed with HCV at age <=15 years between 2011-2021, Overall";
proc freq data=DAA15;
    tables DISEASE_STATUS_HCV DAA_START_INDICATOR FIRST_DAA_START_YEAR / missing norow nopercent nocol;
run;

title "<=15 HCV Care Cascade, DAA starts pre 2021";
proc freq data=DAA15;
    tables DAA_START_INDICATOR / missing norow nopercent nocol;
    Where FIRST_DAA_START_YEAR < 2021;
run;

title "<=15 HCV Care Cascade, Among Confirmed";
proc freq data=DAA15;
    tables HCV_PRIMARY_DIAG RNA_TEST_INDICATOR GENO_TEST_INDICATOR
           DAA_START_INDICATOR EVENT_YEAR_HCV AGE_HCV / missing norow nopercent nocol;
 	WHERE DISEASE_STATUS_HCV = 1;
run;

title "<=15 HCV Care Cascade, Among Confirmed & >=3 at study end";
proc freq data=DAA15;
    tables HCV_PRIMARY_DIAG RNA_TEST_INDICATOR GENO_TEST_INDICATOR
           DAA_START_INDICATOR EVENT_YEAR_HCV AGE_HCV / missing norow nopercent nocol;
 	WHERE DISEASE_STATUS_HCV = 1 and YOB <=2018;
run;

title "HCV Diagnoses made among children 4-10yo between 2011-2021";
proc freq data=DAA15;
    tables DISEASE_STATUS_HCV / missing norow nopercent nocol;
    WHERE DISEASE_STATUS_HCV = 1 and 3 < AGE_HCV < 11;
run;

title "HCV Diagnoses made among children 11-15yo between 2011-2021";
proc freq data=DAA15;
    tables DISEASE_STATUS_HCV / missing norow nopercent nocol;
    WHERE DISEASE_STATUS_HCV = 1 and 10 < AGE_HCV <= 15;
run;

title "EOT/SVR12 & age at treatment, Among those treated";
proc freq data=TRT_TESTING15;
    tables EOT_RNA_TEST SVR12_RNA_TEST AGE_DAA_START_group / missing norow nopercent nocol;
    WHERE DAA_START_INDICATOR = 1;
    format AGE_DAA_START_group pharmagegroupf.;
run;

title "EOT/SVR12 & age at treatment, Among those treated & w confirmed HCV - dup in case age daa start group errors out again to get eot and svr";
proc freq data=TRT_TESTING15;
    tables EOT_RNA_TEST SVR12_RNA_TEST / missing norow nopercent nocol;
    WHERE DISEASE_STATUS_HCV = 1 and DAA_START_INDICATOR = 1;
run;

proc sort data=DAA15;
    by final_re;
run;

title "HCV Care Cascade, by race/ethnicity (<=15)";
proc freq data=DAA15;
    by final_re;
    tables DISEASE_STATUS_HCV / missing norow nopercent nocol;
run;

title "<=15 HCV Care Cascade, by race/ethnicity, Among Confirmed";
proc freq data=DAA15;
    by final_re;
    tables HCV_PRIMARY_DIAG
           GENO_TEST_INDICATOR
           DAA_START_INDICATOR / missing norow nopercent nocol;
    Where DISEASE_STATUS_HCV = 1;
run;
title;

/* ========================================================== */
/* Part 4: Cohort Tables for manuscript                       */
/* ========================================================== */
/* Aggregate Covariates: HOMELESS_EVER, DISCH_WITH_MOM, FACILITY_ID_BIRTH, GESTATIONAL_AGE, INF_VAC_HBIG, NAS_BC, NAS_BC_NEW, RES_ZIP_BIRTH, Res_Code_Birth,
NAS_BC_TOTAL, county, MOMS_FINAL_RE, EVER_INCARCERATED, MOMS_HOMELESS_HISTORY, FOREIGN_BORN, AGE_BIRTH, LD_PAY, KOTELCHUCK, PRENAT_SITE, LANGUAGE_SPOKEN, MATINF_HEPC, MATINF_HEPB,
MOTHER_EDU, MENTAL_HEALTH_DIAG, IJI_DIAG, OTHER_SUBSTANCE_USE, WELL_CHILD, MED_PROV_CITY, MED_PROV_ZIP, HCV_DIAG, OUD_CAPTURE, EVER_IDU_HCV_MAT */

proc sql noprint;
select cats('WORK.',memname) into :to_delete separated by ' '
from dictionary.tables
where libname = 'WORK' and memname not in ('FILTERED_INFANT_COHORT', 'OUD_HCV_DAA', 'TRT_TESTING15');
quit;

proc delete data=&to_delete.;
run;

proc sql;
    create table FILTERED_INFANT_COHORT as
    select *
    from FILTERED_INFANT_COHORT
    where INFANT_YEAR_BIRTH between 2014 and 2020;
quit;

proc sql;
    create table FINAL_INFANT_COHORT as
    select FILTERED_INFANT_COHORT.*,
           demographics.HOMELESS_EVER,
           birthsinfants.DISCH_WITH_MOM,
           birthsinfants.FACILITY_ID_BIRTH,
           birthsinfants.GESTATIONAL_AGE,
           birthsinfants.INF_VAC_HBIG,
           birthsinfants.NAS_BC,
           birthsinfants.NAS_BC_NEW,
           birthsinfants.RES_ZIP_BIRTH,
           birthsinfants.Res_Code_Birth as res_code,
       case 
           when birthsinfants.NAS_BC = 1 or birthsinfants.NAS_BC_NEW = 1 then 1
           when birthsinfants.NAS_BC = 9 or birthsinfants.NAS_BC_NEW = 9 then 9
           when birthsinfants.NAS_BC = 0 or birthsinfants.NAS_BC_NEW = 0 then 0
           when birthsinfants.NAS_BC = . or birthsinfants.NAS_BC_NEW = . then .
           else .
           end as NAS_BC_TOTAL
    from FILTERED_INFANT_COHORT
    left join PHDSPINE.DEMO as demographics
    on FILTERED_INFANT_COHORT.INFANT_ID = demographics.ID
    left join PHDBIRTH.BIRTH_INFANT as birthsinfants
    on FILTERED_INFANT_COHORT.INFANT_ID = birthsinfants.ID;

    data FINAL_INFANT_COHORT;
        set FINAL_INFANT_COHORT;
        if res_code = 999 then county = "Missing/Unknown/Invalid";
        else if res_code in (20,36,41,55,75,86,96,126,172,224,242,261,300,318,351) then county='BARNSTABLE';
        else if res_code in (4,6,22,58,63,70,90,98,113,121,132,148,150,152,193,195,
                             200,203,209,225,233,236,249,260,263,267,283,302,313,326,341,345) then county='BERKSHIRE';
        else if res_code in (3, 16,27,72,76,88,94,95,102,167,201,211,218,245,247,265,273,292,293,334) then county='BRISTOL';
        else if res_code in (62,89,104,109,221,296,327) then county='DUKES';
        else if res_code in (7,9,30,38,71,92,105,107,116,119,128,144,149,
                             163,164,166,168,180,181,184,196,205,206,210,229,252,254,258,259,262,291,298,320,324) then county='ESSEX';
        else if res_code in (13,29,47,53,66,68,74,91,106,114,129,130,154,156,190,192,204,217,223,253,
                             268,272,289,312,319,337) then county='FRANKLIN';
        else if res_code in (5,33,43,59,61,85,112,120,135,137,159,161,191,194,227,256,279,281,297,306,325,329,339) then county='HAMPDEN';
        else if res_code in (8,24,60,69,87,108,111,117,127,143,183,214,230,237,275,276,309,331,340,349) then county='HAMPSHIRE';
        else if res_code in (2,10,12,14,19,23,26,31,37,48,49,51,56,67,79,81,93,100,115,
                             136,139,141,155,157,158,160,165,170,174,176,178,198,207,213,232,246,269,270,274,284,286,288,295,299,301,
                             305,308,314,315,330,333,342,344,347) then county='MIDDLESEX';
        else if res_code=197 then county='NANTUCKET';
        else if res_code in (18,25,40,46,50,65,73,78,99,101,133,175,177,187,189,199,208,220,238,243,
                             244,266,285,307,317,335,336,350) then county='NORFOLK';
        else if res_code in (1,42,44,52,82,83,118,122,123,131,142,145,146,169,171,173,182,219,231,239,
                             240,250,251,264,310,322,338) then county='PLYMOUTH';
        else if res_code in (35,57,248,346) then county='SUFFOLK';
        else if res_code in (11,15,17,21,28,32,34,39,45,54,64,77,80,84,97,103,110,124,125,134,
                             138,140,147,151,153,162,179,185,186,188,202,212,215,216,222,226,228,234,235,241,255,257,
                             271,277,278,280,282,287,290,294,303,304,311,316,321,323,328,332,343,348) then county='WORCESTER';
    run;
quit;

proc sql;
    create table FINAL_INFANT_COHORT as
    select FINAL_INFANT_COHORT.*,
           demographics.FINAL_RE as MOMS_FINAL_RE, 
           demographics.EVER_INCARCERATED,
           demographics.HOMELESS_EVER as MOMS_HOMELESS_HISTORY,
           demographics.FOREIGN_BORN,
           birthsmoms.AGE_BIRTH,
           birthsmoms.LD_PAY,
           birthsmoms.KOTELCHUCK,
           birthsmoms.prenat_site,
           birthsmoms.LANGUAGE_SPOKEN,
           birthsmoms.MATINF_HEPC,
           birthsmoms.MATINF_HEPB,
           birthsmoms.MOTHER_EDU
    from FINAL_INFANT_COHORT
    left join PHDSPINE.DEMO as demographics
    on FINAL_INFANT_COHORT.MOM_ID = demographics.ID 
    left join PHDBIRTH.BIRTH_MOM as birthsmoms
    on FINAL_INFANT_COHORT.BIRTH_LINK_ID = birthsmoms.BIRTH_LINK_ID;
quit;

proc sort data=FINAL_INFANT_COHORT;
   by birth_link_id;
run;

data FINAL_INFANT_COHORT;
    set FINAL_INFANT_COHORT;
    by birth_link_id;
    if first.birth_link_id;
run;

proc sql;
create table MENTAL_HEALTH_COHORT(where=(MENTAL_HEALTH_DIAG=1)) as
select distinct FINAL_INFANT_COHORT.MOM_ID,
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
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_INFANT_COHORT.MOM_ID = apcd.ID;
quit;

proc sql;
create table FINAL_INFANT_COHORT_COV as select *,
case
when MOM_ID in (select MOM_ID from MENTAL_HEALTH_COHORT) then 1
else 0
end as MENTAL_HEALTH_DIAG
from FINAL_INFANT_COHORT;
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
select distinct FINAL_INFANT_COHORT.MOM_ID,
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
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_INFANT_COHORT.MOM_ID = apcd.ID;
quit;

proc sql;
create table FINAL_INFANT_COHORT_COV as select *,
case
when MOM_ID in (select MOM_ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from FINAL_INFANT_COHORT_COV;
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
select distinct FINAL_INFANT_COHORT.MOM_ID,
  case
       when apcd.MED_ECODE in &OTHER_SUBSTANCE_USE or
                        apcd.MED_ADM_DIAGNOSIS in &OTHER_SUBSTANCE_USE or
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
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd on FINAL_INFANT_COHORT.MOM_ID = apcd.ID
left join PHDBSAS.BSAS as bsas on FINAL_INFANT_COHORT.MOM_ID = bsas.ID;
quit;

proc sql;
create table FINAL_INFANT_COHORT_COV as select *,
case
when MOM_ID in (select MOM_ID from OTHER_SUBSTANCE_USE_COHORT) then 1
else 0
end as OTHER_SUBSTANCE_USE
from FINAL_INFANT_COHORT_COV;
quit;

%let well_child = ('99381', '99391', '99381', '99391', '99381', '99391', '99382', '99392');

proc sql;
create table ALL_WELL_CHILD_COHORT(where=(WELL_CHILD=1)) as
select distinct FINAL_INFANT_COHORT.INFANT_ID,
    case
       when apcd.MED_PROC_CODE in &WELL_CHILD
           and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_INFANT_TBL) >= 18*30 
           and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_INFANT_TBL) <= 36*30 then 1
       else 0
    end as WELL_CHILD
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_INFANT_COHORT.INFANT_ID = apcd.ID;
quit;

proc sql;
create table ALL_WELL_CHILD_COHORT as
select distinct a.INFANT_ID,
       b.MED_PROV_CITY,
       b.MED_PROV_ZIP
from ALL_WELL_CHILD_COHORT as a
left join PHDAPCD.MOUD_MEDICAL as b
on a.INFANT_ID = b.ID
where b.MED_FROM_DATE is not missing
    and (b.MED_FROM_DATE - (select DOB_INFANT_TBL from FINAL_INFANT_COHORT where INFANT_ID = a.INFANT_ID)) >= 18*30
    and (b.MED_FROM_DATE - (select DOB_INFANT_TBL from FINAL_INFANT_COHORT where INFANT_ID = a.INFANT_ID)) <= 36*30
order by a.INFANT_ID, b.MED_FROM_DATE;
quit;

data DEDUP_WELL_CHILD_COHORT;
set ALL_WELL_CHILD_COHORT;
by INFANT_ID;
if first.INFANT_ID;
run;

proc sql;
create table FINAL_INFANT_COHORT_COV as 
    select FINAL_INFANT_COHORT_COV.*, 
           case 
               when DEDUP_WELL_CHILD_COHORT.INFANT_ID is not null then 1 
               else 0 
           end as WELL_CHILD,
           DEDUP_WELL_CHILD_COHORT.MED_PROV_CITY,
           DEDUP_WELL_CHILD_COHORT.MED_PROV_ZIP
    from FINAL_INFANT_COHORT_COV
    left join DEDUP_WELL_CHILD_COHORT on FINAL_INFANT_COHORT_COV.INFANT_ID = DEDUP_WELL_CHILD_COHORT.INFANT_ID;
quit;

data FINAL_INFANT_COHORT_COV;
    set FINAL_INFANT_COHORT_COV;
    if MED_PROV_CITY = 999 then MED_PROV_COUNTY = "Missing/Unknown/Invalid";
    else if MED_PROV_CITY in (20,36,41,55,75,86,96,126,172,224,242,261,300,318,351) then MED_PROV_COUNTY='BARNSTABLE';
    else if MED_PROV_CITY in (4,6,22,58,63,70,90,98,113,121,132,148,150,152,193,195,
                             200,203,209,225,233,236,249,260,263,267,283,302,313,326,341,345) then MED_PROV_COUNTY='BERKSHIRE';
    else if MED_PROV_CITY in (3, 16,27,72,76,88,94,95,102,167,201,211,218,245,247,265,273,292,293,334) then MED_PROV_COUNTY='BRISTOL';
    else if MED_PROV_CITY in (62,89,104,109,221,296,327) then MED_PROV_COUNTY='DUKES';
    else if MED_PROV_CITY in (7,9,30,38,71,92,105,107,116,119,128,144,149,
                             163,164,166,168,180,181,184,196,205,206,210,229,252,254,258,259,262,291,298,320,324) then MED_PROV_COUNTY='ESSEX';
    else if MED_PROV_CITY in (13,29,47,53,66,68,74,91,106,114,129,130,154,156,190,192,204,217,223,253,
                             268,272,289,312,319,337) then MED_PROV_COUNTY='FRANKLIN';
    else if MED_PROV_CITY in (5,33,43,59,61,85,112,120,135,137,159,161,191,194,227,256,279,281,297,306,325,329,339) then MED_PROV_COUNTY='HAMPDEN';
    else if MED_PROV_CITY in (8,24,60,69,87,108,111,117,127,143,183,214,230,237,275,276,309,331,340,349) then MED_PROV_COUNTY='HAMPSHIRE';
    else if MED_PROV_CITY in (2,10,12,14,19,23,26,31,37,48,49,51,56,67,79,81,93,100,115,
                             136,139,141,155,157,158,160,165,170,174,176,178,198,207,213,232,246,269,270,274,284,286,288,295,299,301,
                             305,308,314,315,330,333,342,344,347) then MED_PROV_COUNTY='MIDDLESEX';
    else if MED_PROV_CITY=197 then MED_PROV_COUNTY='NANTUCKET';
    else if MED_PROV_CITY in (18,25,40,46,50,65,73,78,99,101,133,175,177,187,189,199,208,220,238,243,
                             244,266,285,307,317,335,336,350) then MED_PROV_COUNTY='NORFOLK';
    else if MED_PROV_CITY in (1,42,44,52,82,83,118,122,123,131,142,145,146,169,171,173,182,219,231,239,
                             240,250,251,264,310,322,338) then MED_PROV_COUNTY='PLYMOUTH';
    else if MED_PROV_CITY in (35,57,248,346) then MED_PROV_COUNTY='SUFFOLK';
    else if MED_PROV_CITY in (11,15,17,21,28,32,34,39,45,54,64,77,80,84,97,103,110,124,125,134,
                             138,140,147,151,153,162,179,185,186,188,202,212,215,216,222,226,228,234,235,241,255,257,
                             271,277,278,280,282,287,290,294,303,304,311,316,321,323,328,332,343,348) then MED_PROV_COUNTY='WORCESTER';
run;

proc sql;
    update FINAL_INFANT_COHORT_COV 
    set MED_PROV_COUNTY = county
    where MED_PROV_COUNTY is missing;
 quit;

%LET HCV_ICD = ('7051', '7054', '707',
				'7041', '7044', '7071',
				'B1710','B182', 'B1920',
				'B1711','B1921');
                
proc sql;
create table HCV_DIAG_COHORT (where=(HCV_DIAG=1)) as
select distinct FINAL_INFANT_COHORT.MOM_ID,
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
                        and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_MOM_TBL) >= 30 and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_MOM_TBL) <= 30 
                   then 1
           else 0
       end as HCV_DIAG
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd on FINAL_INFANT_COHORT.MOM_ID = apcd.ID;
quit;

proc sql;
create table FINAL_INFANT_COHORT_COV as select *,
case
when MOM_ID in (select MOM_ID from HCV_DIAG_COHORT) then 1
else 0
end as HCV_DIAG
from FINAL_INFANT_COHORT_COV;
quit;

proc sql;
    create table FINAL_INFANT_COHORT_COV as
    select 
        A.*, 
        (case when B.MOM_ID is not null and B.OUD_AGE < A.AGE_BIRTH then 1 else 0 end) as OUD_CAPTURE,
        B.EVER_IDU_HCV_MAT
    from FINAL_INFANT_COHORT_COV as A
    left join (select distinct MOM_ID, OUD_AGE, EVER_IDU_HCV_MAT from OUD_HCV_DAA) as B
    on A.MOM_ID = B.MOM_ID;
quit;

PROC SQL;
    SELECT COUNT(DISTINCT INFANT_ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FINAL_INFANT_COHORT_COV;
QUIT;

%put Number of unique Infant IDs in FINAL_INFANT_COHORT_COV table: &num_unique_ids;

/* ================================= */
/* 2. FORMATS                        */
/* ================================= */

proc format;
    value flagf
    0 = 'No'
    1 = 'Yes'
    9 = 'Unknown';

proc format;
    value sexf
    1 = 'Male'
    2 = 'Female'
    9 = 'Missing'
    99 = 'Not an MA resident';

proc format;
    value raceef
    1 = 'White Non-Hispanic'
    2 = 'Black non-Hispanic'
    3 = 'Asian/PI non-Hispanic'
    4 = 'Hispanic'
    5 = 'American Indian or Other non-Hispanic '
    9 = 'Missing'
    99 = 'Not an MA resident';

proc format;
value fbornf
    0 = 'No'
    1 = 'Yes'
    8 = 'Missing in dataset'
    9 = 'Not collected';

proc format;
value langf
	0 = 'Not Provided' | 'Unknown/missing'
    1 = 'English Only'
    2 = 'English and Another Language'
    3 = 'Another Language';

proc format;
value ld_pay_fmt
    1 = 'Public'
    2 = 'Private'
    9 = 'Unknown';

proc format;
value kotel_fmt
    0 = 'Missing/Unknown'
    1 = 'Inadequate'
    2 = 'Intermediate'
    3 = 'Adequate'
    4 = 'Intensive';

proc format;
value prenat_site_fmt
    1 = 'Private Physicians Office'
    2 = 'Community Health Center'
    3 = 'HMO'
    4 = 'Hospital Clinic'
    5 = 'Other'
    9 = 'Unknown';

/* ================================= */
/* 3. RECATEGORIZE                   */
/* ================================= */

data FINAL_INFANT_COHORT_COV;
    length LANGUAGE_SPOKEN_GROUP $30;
    set FINAL_INFANT_COHORT_COV;
    if LANGUAGE_SPOKEN = 1 then LANGUAGE_SPOKEN_GROUP = 'English';
    else if LANGUAGE_SPOKEN = 2 then LANGUAGE_SPOKEN_GROUP = 'Spanish';
    else if 3 <= LANGUAGE_SPOKEN <= 15 then LANGUAGE_SPOKEN_GROUP = 'Other';
    else if LANGUAGE_SPOKEN >= 88 then LANGUAGE_SPOKEN_GROUP = 'Refused or Unknown';
    else LANGUAGE_SPOKEN_GROUP = 'N/A (MF Record)';
run;

data FINAL_INFANT_COHORT_COV;
    length MOTHER_EDU_GROUP $30;
    set FINAL_INFANT_COHORT_COV;
    if MOTHER_EDU = 1 then MOTHER_EDU_GROUP = 'No HS';
    else if MOTHER_EDU = 2 then MOTHER_EDU_GROUP = 'HS or GED';
    else if MOTHER_EDU = 3 then MOTHER_EDU_GROUP = 'Associate or Bachelor';
    else if MOTHER_EDU = 4 then MOTHER_EDU_GROUP = 'Post graduate';
    else MOTHER_EDU_GROUP = 'Other or Unknown';
run;

data FINAL_INFANT_COHORT_COV;
    set FINAL_INFANT_COHORT_COV;
    if AGE_BIRTH = 9999 then AGE_BIRTH_GROUP = 'Unknown';
    else if AGE_BIRTH <= 18 then AGE_BIRTH_GROUP = '<=18';
    else if AGE_BIRTH <= 25 then AGE_BIRTH_GROUP = '19-25';
    else if AGE_BIRTH <= 35 then AGE_BIRTH_GROUP = '26-35';
    else AGE_BIRTH_GROUP = '>35';

data FINAL_INFANT_COHORT_COV;
    set FINAL_INFANT_COHORT_COV;
    if GESTATIONAL_AGE = 99 then GESTATIONAL_AGE_CAT = 'Unknown';
    else if GESTATIONAL_AGE >= 37 then GESTATIONAL_AGE_CAT = 'Term';
    else if GESTATIONAL_AGE < 37 then GESTATIONAL_AGE_CAT = 'Preterm';
    else GESTATIONAL_AGE_CAT = 'Missing';
run;

data FINAL_INFANT_COHORT_COV;
    length HOMELESS_HISTORY_GROUP $10;
    set FINAL_INFANT_COHORT_COV;
    if MOMS_HOMELESS_HISTORY = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= MOMS_HOMELESS_HISTORY <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by MOM_DISEASE_STATUS_HCV;
run;

/* ================================= */
/* 4. EXPLORATORY TABLES AND SUM STATS  */
/* ================================= */

title "HCV Diagnosis by ICD Code/Birth Certificate by MOM_DISEASE_STATUS_HCV";
proc freq data=FINAL_INFANT_COHORT_COV;
    by MOM_DISEASE_STATUS_HCV;
tables HCV_DIAG MATINF_HEPC / missing norow nocol nopercent;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by MATINF_HEPC ;
run;

title "HCV Diagnosis by ICD Code/Birth Certificate by MATINF_HEPC";
proc freq data=FINAL_INFANT_COHORT_COV;
    by MATINF_HEPC ;
tables HCV_DIAG / missing norow nocol nopercent;
run;
title;

proc means data=FINAL_INFANT_COHORT_COV;
    var AGE_BIRTH;
    where AGE_BIRTH ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by APPROPRIATE_Testing;
run;

proc means data=FINAL_INFANT_COHORT_COV;
    by APPROPRIATE_Testing;
    var AGE_BIRTH;
    where AGE_BIRTH ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

proc means data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
    var AGE_BIRTH;
    where AGE_BIRTH ne 9999;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc means data=FINAL_INFANT_COHORT_COV mean median q1 q3;
    where AGE_AT_FIRST_TEST ne . and AGE_AT_FIRST_TEST ne -16;
    var AGE_AT_FIRST_TEST;
run;

proc means data=FINAL_INFANT_COHORT_COV mean median q1 q3;
    where AGE_AT_FIRST_TEST ne . and AGE_AT_FIRST_TEST ne -16;
    class INFANT_YEAR_BIRTH;
    var AGE_AT_FIRST_TEST;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
  by MOM_ID;
run;

data want(keep=MOM_ID cnt_deliveries);
  set FINAL_INFANT_COHORT_COV;
  by MOM_ID;

  retain cnt_deliveries 0;

  if first.MOM_ID then cnt_deliveries = 0;

  if not missing(INFANT_ID) then cnt_deliveries = cnt_deliveries + 1;

  if last.MOM_ID then output;
run;

proc univariate data=want noprint;
  var cnt_deliveries;
  output out=summary_stats mean=mean_cnt_deliveries median=median_cnt_deliveries range=range_cnt_deliveries;
run;

proc print data=summary_stats;
  title 'Summary Statistics of Number of Deliveries per MOM_ID';
run;

PROC SQL;
    SELECT COUNT(DISTINCT MOM_ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FINAL_INFANT_COHORT_COV;
QUIT;

%put Number of unique MOM_ID in FINAL_INFANT_COHORT_COV table: &num_unique_ids;

data UNIQUE_MOMS(keep= MOM_ID MOMS_FINAL_RE FOREIGN_BORN OUD_CAPTURE APPROPRIATE_Testing);
    set FINAL_INFANT_COHORT_COV;
    by MOM_ID;
    if first.MOM_ID;
run;

/* ================================= */
/* 5. TABLES                         */
/* ================================= */

%macro Table1Freqs_UniqueMoms(var, format);
    title "Table 1, Unstratified, Unique Moms";
    proc freq data=UNIQUE_MOMS;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs_UniqueMoms (MOMS_FINAL_RE, raceef.);
%Table1Freqs_UniqueMoms (FOREIGN_BORN, fbornf.);
%Table1Freqs_UniqueMoms (OUD_CAPTURE, flagf.);

%macro Table1Freqs(var, format);
    title "Table 1, Unstratified";
    proc freq data=FINAL_INFANT_COHORT_COV;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1freqs (FINAL_SEX, sexf.);
%Table1freqs (GESTATIONAL_AGE_CAT);
%Table1freqs (FINAL_RE, raceef.);
%Table1freqs (MOMS_FINAL_RE, raceef.);
%Table1freqs (FOREIGN_BORN, fbornf.);
%Table1freqs (OUD_CAPTURE, flagf.);
%Table1freqs (FACILITY_ID_BIRTH);
%Table1freqs (MED_PROV_COUNTY);
%Table1freqs (MED_PROV_ZIP);
%Table1freqs (county);
%Table1freqs (well_child, flagf.);
%Table1freqs (NAS_BC_TOTAL, flagf.);
%Table1freqs (DISCH_WITH_MOM, flagf.);
%Table1freqs (INF_VAC_HBIG, flagf.);
%Table1freqs (HIV_DIAGNOSIS, flagf.);
%Table1freqs (MOUD_DURING_PREG, flagf.);
%Table1freqs (MOUD_AT_DELIVERY, flagf.);
%Table1freqs (AGE_BIRTH_GROUP);
%Table1freqs (EVER_INCARCERATED, flagf.);
%Table1freqs (HOMELESS_HISTORY_GROUP);
%Table1freqs (LANGUAGE_SPOKEN_GROUP);
%Table1freqs (MOTHER_EDU_GROUP);
%Table1freqs (LD_PAY, ld_pay_fmt.);
%Table1freqs (KOTELCHUCK, kotel_fmt.);
%Table1freqs (prenat_site, prenat_site_fmt.);
%Table1freqs (MATINF_HEPC, flagf.);
%Table1freqs (MOM_DISEASE_STATUS_HCV, momhcvfmt.);
%Table1freqs (HCV_DIAG, flagf.);
%Table1freqs (MATINF_HEPB, flagf.);
%Table1freqs (EVER_IDU_HCV_MAT, flagf.);
%Table1freqs (mental_health_diag, flagf.);
%Table1freqs (OTHER_SUBSTANCE_USE, flagf.);
%Table1freqs (iji_diag, flagf.);

%macro Table1Freqs0_15(var, format);
    title "Table 1, 0-15 Cohort, Unstratified";
    proc freq data=TRT_TESTING15;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs0_15 (FINAL_SEX, sexf.);
%Table1Freqs0_15 (FINAL_RE, raceef.);
%Table1Freqs0_15 (LANGUAGE, langf.);
%Table1Freqs0_15 (FOREIGN_BORN, fbornf.);
%Table1Freqs0_15 (EVER_IDU_HCV, flagf.);
%Table1Freqs0_15 (AGE_HCV);

%macro Table1StrataFreqs(var, format);
    title "Table 1, Stratified by APPROPRIATE_Testing";
    
    /* Sort the dataset by APPROPRIATE_Testing */
    proc sort data=FINAL_INFANT_COHORT_COV;
        by APPROPRIATE_Testing;
    run;

    /* Run PROC FREQ with BY statement */
    proc freq data=FINAL_INFANT_COHORT_COV;
        by APPROPRIATE_Testing;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Stratafreqs (FINAL_SEX, sexf.);
%Table1Stratafreqs (GESTATIONAL_AGE_CAT);
%Table1Stratafreqs (FINAL_RE, raceef.);
%Table1Stratafreqs (MOMS_FINAL_RE, raceef.);
%Table1Stratafreqs (FACILITY_ID_BIRTH);
%Table1Stratafreqs (MED_PROV_COUNTY);
%Table1Stratafreqs (MED_PROV_ZIP);
%Table1Stratafreqs (county);
%Table1Stratafreqs (well_child, flagf.);
%Table1Stratafreqs (NAS_BC_TOTAL, flagf.);
%Table1Stratafreqs (DISCH_WITH_MOM, flagf.);
%Table1Stratafreqs (INF_VAC_HBIG, flagf.);
%Table1Stratafreqs (HIV_DIAGNOSIS, flagf.);
%Table1Stratafreqs (MOUD_DURING_PREG, flagf.);
%Table1Stratafreqs (MOUD_AT_DELIVERY, flagf.);
%Table1Stratafreqs (OUD_CAPTURE, flagf.);
%Table1Stratafreqs (AGE_BIRTH_GROUP);
%Table1Stratafreqs (EVER_INCARCERATED, flagf.);
%Table1Stratafreqs (FOREIGN_BORN, fbornf.);
%Table1Stratafreqs (HOMELESS_HISTORY_GROUP);
%Table1Stratafreqs (LANGUAGE_SPOKEN_GROUP);
%Table1Stratafreqs (MOTHER_EDU_GROUP);
%Table1Stratafreqs (LD_PAY, ld_pay_fmt.);
%Table1Stratafreqs (KOTELCHUCK, kotel_fmt.);
%Table1Stratafreqs (prenat_site, prenat_site_fmt.);
%Table1Stratafreqs (MATINF_HEPC, flagf.);
%Table1Stratafreqs (MOM_DISEASE_STATUS_HCV, momhcvfmt.);
%Table1Stratafreqs (HCV_DIAG, flagf.);
%Table1Stratafreqs (MATINF_HEPB, flagf.);
%Table1Stratafreqs (EVER_IDU_HCV_MAT, flagf.);
%Table1Stratafreqs (mental_health_diag, flagf.);
%Table1Stratafreqs (OTHER_SUBSTANCE_USE, flagf.);
%Table1Stratafreqs (iji_diag, flagf.);

%macro Table1StrataFreqs0_15(var, format);
    title "Table 1, 0-15 Cohort, Stratified";
    
    /* Sort the dataset by DAA_START_INDICATOR */
    proc sort data=TRT_TESTING15;
        by DAA_START_INDICATOR;
    run;

    /* Run PROC FREQ with BY statement */
    proc freq data=TRT_TESTING15;
        by DAA_START_INDICATOR;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1StrataFreqs0_15 (FINAL_SEX, sexf.);
%Table1StrataFreqs0_15 (FINAL_RE, raceef.);
%Table1StrataFreqs0_15 (LANGUAGE, langf.);
%Table1StrataFreqs0_15 (FOREIGN_BORN, fbornf.);
%Table1StrataFreqs0_15 (EVER_IDU_HCV, flagf.);
%Table1StrataFreqs0_15 (AGE_HCV);

%macro Table2Crude(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
	        class &var (ref=&ref) MOM_ID;
	        model APPROPRIATE_Testing(event='1') = &var / dist=binary link=logit solution oddsratio;
    		random intercept / subject=MOM_ID;
	run;
%mend;

DATA FINAL_INFANT_COHORT_COV;
    SET FINAL_INFANT_COHORT_COV;
    IF AGE_BIRTH_GROUP NOT IN ('Unknown', '<=18') AND FOREIGN_BORN NE 8 
    AND GESTATIONAL_AGE_CAT NE 'Unknown' AND MATINF_HEPC NE 9 AND MATINF_HEPB NE 9;
RUN;

data FINAL_INFANT_COHORT_COV;
    length LANGUAGE_SPOKEN_GROUP $30;
    set FINAL_INFANT_COHORT_COV;
    if LANGUAGE_SPOKEN = 1 then LANGUAGE_SPOKEN_GROUP = 'English';
    else if 2 <= LANGUAGE_SPOKEN <= 15 then LANGUAGE_SPOKEN_GROUP = 'Other';
    else if LANGUAGE_SPOKEN >= 88 then LANGUAGE_SPOKEN_GROUP = 'Refused or Unknown';
    else LANGUAGE_SPOKEN_GROUP = 'N/A (MF Record)';
run;

%Table2Crude(FINAL_SEX, ref='1');
%Table2Crude(GESTATIONAL_AGE_CAT, ref='Term');
%Table2Crude(FINAL_RE, ref='1');
%Table2Crude(MOMS_FINAL_RE, ref='1');
%Table2Crude(county, ref='MIDDLESEX');
%Table2Crude(MED_PROV_COUNTY, ref='MIDDLESEX');
%Table2Crude(well_child, ref='0');
%Table2Crude(NAS_BC_TOTAL, ref='0');
%Table2Crude(INF_VAC_HBIG, ref='0');
%Table2Crude(HIV_DIAGNOSIS, ref='0');
%Table2Crude(FOREIGN_BORN, ref='0');
%Table2Crude(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2Crude(EVER_IDU_HCV_MAT, ref='0');
%Table2Crude(MENTAL_HEALTH_DIAG, ref='0');
%Table2Crude(OTHER_SUBSTANCE_USE, ref='0');
%Table2Crude(MATINF_HEPB, ref='0');
%Table2Crude(MOUD_DURING_PREG, ref='0');
%Table2Crude(MOUD_AT_DELIVERY, ref='0');
%Table2Crude(OUD_CAPTURE, ref='0');
%Table2Crude(IJI_DIAG, ref='0');
%Table2Crude(EVER_INCARCERATED, ref='0');
%Table2Crude(MATINF_HEPC, ref='0');
%Table2Crude(MOM_DISEASE_STATUS_HCV, ref='1');
%Table2Crude(HCV_DIAG, ref='0');
%Table2Crude(AGE_BIRTH_GROUP, ref='19-25');
%Table2Crude(LANGUAGE_SPOKEN_GROUP, ref='English');
%Table2Crude(MOTHER_EDU_GROUP, ref='HS or GED');
%Table2Crude(LD_PAY, ref='1');
%Table2Crude(KOTELCHUCK, ref='3');
%Table2Crude(prenat_site, ref='1');
%Table2Crude(DISCH_WITH_MOM, ref='0');

title "Table 2, Crude";
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
     class MOM_ID;
	 model APPROPRIATE_Testing(event='1') = AGE_BIRTH / dist=binary link=logit solution oddsratio;
	 random intercept / subject=MOM_ID;
run;

data FINAL_INFANT_COHORT_COV;
    set FINAL_INFANT_COHORT_COV;
    if FINAL_RE NE 9 and DISCH_WITH_MOM NE 9 and not (FACILITY_ID_BIRTH in (0, 70, 80));
run;

%macro Table2Crude_Strat(var, ref= );
    title "Table 2, Crude, Stratified";
    
    /* Sort the dataset by DISCH_WITH_MOM */
    proc sort data=FINAL_INFANT_COHORT_COV;
        by DISCH_WITH_MOM;
    run;
    
    /* Run logistic regression */
    title "Table 2, Crude";
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
	        class &var (ref=&ref) MOM_ID;
	        model APPROPRIATE_Testing(event='1') = &var / dist=binary link=logit solution oddsratio;
	        by DISCH_WITH_MOM;
    		random intercept / subject=MOM_ID;
	run;
%mend;

%Table2Crude_Strat(FINAL_SEX, ref='1');
%Table2Crude_Strat(GESTATIONAL_AGE_CAT, ref='Term');
%Table2Crude_Strat(FINAL_RE, ref='1');
%Table2Crude_Strat(MOMS_FINAL_RE, ref='1');
%Table2Crude_Strat(county, ref='MIDDLESEX');
%Table2Crude_Strat(MED_PROV_COUNTY, ref='MIDDLESEX');
%Table2Crude_Strat(well_child, ref='0');
%Table2Crude_Strat(NAS_BC_TOTAL, ref='0');
%Table2Crude_Strat(INF_VAC_HBIG, ref='0');
%Table2Crude_Strat(HIV_DIAGNOSIS, ref='0');
%Table2Crude_Strat(FOREIGN_BORN, ref='0');
%Table2Crude_Strat(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2Crude_Strat(EVER_IDU_HCV_MAT, ref='0');
%Table2Crude_Strat(MENTAL_HEALTH_DIAG, ref='0');
%Table2Crude_Strat(OTHER_SUBSTANCE_USE, ref='0');
%Table2Crude_Strat(MATINF_HEPB, ref='0');
%Table2Crude_Strat(MOUD_DURING_PREG, ref='0');
%Table2Crude_Strat(MOUD_AT_DELIVERY, ref='0');
%Table2Crude_Strat(OUD_CAPTURE, ref='0');
%Table2Crude_Strat(IJI_DIAG, ref='0');
%Table2Crude_Strat(EVER_INCARCERATED, ref='0');
%Table2Crude_Strat(MATINF_HEPC, ref='0');
%Table2Crude_Strat(MOM_DISEASE_STATUS_HCV, ref='1');
%Table2Crude_Strat(HCV_DIAG, ref='0');
%Table2Crude_Strat(AGE_BIRTH_GROUP, ref='19-25');
%Table2Crude_Strat(LANGUAGE_SPOKEN_GROUP, ref='English');
%Table2Crude_Strat(MOTHER_EDU_GROUP, ref='HS or GED');
%Table2Crude_Strat(LD_PAY, ref='1');
%Table2Crude_Strat(KOTELCHUCK, ref='3');
%Table2Crude_Strat(prenat_site, ref='1');

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;
    
title "Table 2, Crude";
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
     class MOM_ID;
	 model APPROPRIATE_Testing(event='1') = AGE_BIRTH / dist=binary link=logit solution oddsratio;
	 by DISCH_WITH_MOM;
	 random intercept / subject=MOM_ID;
run;

data TRT_TESTING15;
    set TRT_TESTING15;
    
    if AGE_HCV in (0, 1, 2) then AGE_HCV_CAT = 1;
    else if AGE_HCV in (3, 4, 5, 6, 7, 8, 9, 10) then AGE_HCV_CAT = 2;
    else if AGE_HCV in (11, 12, 13, 14, 15) then AGE_HCV_CAT = 3;
run;

%macro Table2Crude0_15(var, ref=);
	title "Table 2, 0-15 Cohort, Crude";
	proc glimmix data=TRT_TESTING15 noclprint noitprint;
	        class &var (ref=&ref);
	        model DAA_START_INDICATOR(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2Crude0_15 (FINAL_SEX, ref='1');
%Table2Crude0_15 (FINAL_RE, ref='1');
%Table2Crude0_15 (LANGUAGE, ref='1');
%Table2Crude0_15 (FOREIGN_BORN, ref='0');
%Table2Crude0_15 (EVER_IDU_HCV, ref='0');
%Table2Crude0_15 (AGE_HCV_CAT, ref='1');

/* ========================================================== */
/* Part 5: Collinearity and MV Regressions                    */
/* ========================================================== */
/* Step 1: Assess collinearity among selected variables using chi-square tests */

%macro ChiSquareTest(var1, var2);
    title "Chi-Square Test between &var1 and &var2";
    proc freq data=FINAL_INFANT_COHORT_COV;
        tables &var1*(&var2) / chisq nopercent nocol;
    run;
    title;
%mend;

%ChiSquareTest(HCV_DIAG, MOMS_FINAL_RE);
%ChiSquareTest(HCV_DIAG, FOREIGN_BORN);
%ChiSquareTest(HCV_DIAG, COUNTY);
%ChiSquareTest(HCV_DIAG, AGE_BIRTH_GROUP);
%ChiSquareTest(HCV_DIAG, LANGUAGE_SPOKEN_GROUP);
%ChiSquareTest(HCV_DIAG, LD_PAY);
%ChiSquareTest(HCV_DIAG, MOUD_DURING_PREG);
%ChiSquareTest(HCV_DIAG, MOUD_AT_DELIVERY);
%ChiSquareTest(HCV_DIAG, MATINF_HEPC);
%ChiSquareTest(HCV_DIAG, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(HCV_DIAG, GESTATIONAL_AGE_CAT);
%ChiSquareTest(HCV_DIAG, NAS_BC_TOTAL);
%ChiSquareTest(HCV_DIAG, WELL_CHILD);
%ChiSquareTest(HCV_DIAG, DISCH_WITH_MOM);
%ChiSquareTest(LD_PAY, MOMS_FINAL_RE);
%ChiSquareTest(WELL_CHILD, DISCH_WITH_MOM);
%ChiSquareTest(AGE_BIRTH_GROUP, MOUD_DURING_PREG);

%macro TableDISCH_WITH_MOM(var, format, strata1, strata2);
    title "Table, Stratified by &strata1 and &strata2";

    proc sort data=FINAL_INFANT_COHORT_COV;
        by &strata1 &strata2;
    run;

    proc freq data=FINAL_INFANT_COHORT_COV;
        by &strata1 &strata2;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%TableDISCH_WITH_MOM(FINAL_RE, raceef., APPROPRIATE_Testing, DISCH_WITH_MOM);
%TableDISCH_WITH_MOM(county, $20., APPROPRIATE_Testing, DISCH_WITH_MOM);
%TableDISCH_WITH_MOM(MED_PROV_COUNTY, $30., APPROPRIATE_Testing, DISCH_WITH_MOM);

/* %macro ChiSquareTest(var1, var2);
    title "Chi-Square Test between &var1 and &var2";
    proc freq data=FINAL_INFANT_COHORT_COV;
        tables &var1*(&var2) * DISCH_WITH_MOM / chisq nopercent nocol;
    run;
    title;
%mend;

%ChiSquareTest(MOMS_FINAL_RE, FOREIGN_BORN);
%ChiSquareTest(MOMS_FINAL_RE, COUNTY);
%ChiSquareTest(MOMS_FINAL_RE, AGE_BIRTH_GROUP);
%ChiSquareTest(MOMS_FINAL_RE, LANGUAGE_SPOKEN_GROUP);
%ChiSquareTest(MOMS_FINAL_RE, LD_PAY);
%ChiSquareTest(MOMS_FINAL_RE, MOUD_DURING_PREG);
%ChiSquareTest(MOMS_FINAL_RE, MOUD_AT_DELIVERY);
%ChiSquareTest(MOMS_FINAL_RE, MATINF_HEPC);
%ChiSquareTest(MOMS_FINAL_RE, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(MOMS_FINAL_RE, HCV_DIAG);


%ChiSquareTest(FOREIGN_BORN, COUNTY);
%ChiSquareTest(FOREIGN_BORN, AGE_BIRTH_GROUP);
%ChiSquareTest(FOREIGN_BORN, LANGUAGE_SPOKEN_GROUP);
%ChiSquareTest(FOREIGN_BORN, LD_PAY);
%ChiSquareTest(FOREIGN_BORN, MOUD_DURING_PREG);
%ChiSquareTest(FOREIGN_BORN, MOUD_AT_DELIVERY);
%ChiSquareTest(FOREIGN_BORN, MATINF_HEPC);
%ChiSquareTest(FOREIGN_BORN, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(FOREIGN_BORN, HCV_DIAG);

%ChiSquareTest(COUNTY, AGE_BIRTH_GROUP);
%ChiSquareTest(COUNTY, LANGUAGE_SPOKEN_GROUP);
%ChiSquareTest(COUNTY, LD_PAY);
%ChiSquareTest(COUNTY, MOUD_DURING_PREG);
%ChiSquareTest(COUNTY, MOUD_AT_DELIVERY);
%ChiSquareTest(COUNTY, MATINF_HEPC);
%ChiSquareTest(COUNTY, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(COUNTY, HCV_DIAG);

%ChiSquareTest(AGE_BIRTH_GROUP, LANGUAGE_SPOKEN_GROUP);
%ChiSquareTest(AGE_BIRTH_GROUP, LD_PAY);
%ChiSquareTest(AGE_BIRTH_GROUP, MOUD_DURING_PREG);
%ChiSquareTest(AGE_BIRTH_GROUP, MOUD_AT_DELIVERY);
%ChiSquareTest(AGE_BIRTH_GROUP, MATINF_HEPC);
%ChiSquareTest(AGE_BIRTH_GROUP, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(AGE_BIRTH_GROUP, HCV_DIAG);

%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, LD_PAY);
%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, MOUD_DURING_PREG);
%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, MOUD_AT_DELIVERY);
%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, MATINF_HEPC);
%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(LANGUAGE_SPOKEN_GROUP, HCV_DIAG);

%ChiSquareTest(LD_PAY, MOUD_DURING_PREG);
%ChiSquareTest(LD_PAY, MOUD_AT_DELIVERY);
%ChiSquareTest(LD_PAY, MATINF_HEPC);
%ChiSquareTest(LD_PAY, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(LD_PAY, HCV_DIAG);

%ChiSquareTest(MOUD_DURING_PREG, MOUD_AT_DELIVERY);
%ChiSquareTest(MOUD_DURING_PREG, MATINF_HEPC);
%ChiSquareTest(MOUD_DURING_PREG, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(MOUD_DURING_PREG, HCV_DIAG);

%ChiSquareTest(MOUD_AT_DELIVERY, MATINF_HEPC);
%ChiSquareTest(MOUD_AT_DELIVERY, MOM_DISEASE_STATUS_HCV);
%ChiSquareTest(MOUD_AT_DELIVERY, HCV_DIAG); */

%macro ChiSquareTest0_15(var1, var2);
    title "Chi-Square Test between &var1 and &var2 for 0-15 Cohort";
    proc freq data=TRT_TESTING15;
        tables &var1*(&var2) / chisq nopercent nocol;
    run;
    title;
%mend;

%ChiSquareTest0_15(FINAL_RE, FOREIGN_BORN);
%ChiSquareTest0_15(FINAL_RE, LANGUAGE);
%ChiSquareTest0_15(FINAL_RE, FINAL_SEX);
%ChiSquareTest0_15(FINAL_RE, EVER_IDU_HCV);
%ChiSquareTest0_15(FINAL_RE, AGE_HCV_CAT);

%ChiSquareTest0_15(FOREIGN_BORN, LANGUAGE);
%ChiSquareTest0_15(FOREIGN_BORN, FINAL_SEX);
%ChiSquareTest0_15(FOREIGN_BORN, EVER_IDU_HCV);
%ChiSquareTest0_15(FOREIGN_BORN, AGE_HCV_CAT);

%ChiSquareTest0_15(LANGUAGE, FINAL_SEX);
%ChiSquareTest0_15(LANGUAGE, EVER_IDU_HCV);
%ChiSquareTest0_15(LANGUAGE, AGE_HCV_CAT);

%ChiSquareTest0_15(FINAL_SEX, EVER_IDU_HCV);
%ChiSquareTest0_15(FINAL_SEX, AGE_HCV_CAT);

%ChiSquareTest0_15(EVER_IDU_HCV, AGE_HCV_CAT);

/* title 'Crosstabulation of Variables by FACILITY_ID_BIRTH';
proc freq data=FINAL_INFANT_COHORT_COV;
  tables APPROPRIATE_Testing*FACILITY_ID_BIRTH
         MOMS_FINAL_RE*FACILITY_ID_BIRTH
         FOREIGN_BORN*FACILITY_ID_BIRTH
         LD_PAY*FACILITY_ID_BIRTH
         MOUD_DURING_PREG*FACILITY_ID_BIRTH
         MATINF_HEPC*FACILITY_ID_BIRTH
         MOM_DISEASE_STATUS_HCV*FACILITY_ID_BIRTH
         HCV_DIAG*FACILITY_ID_BIRTH
         DISCH_WITH_MOM*FACILITY_ID_BIRTH;
run;

title 'Crosstabulation of Variables by MED_PROV_COUNTY';
proc freq data=FINAL_INFANT_COHORT_COV;
  tables APPROPRIATE_Testing*MED_PROV_COUNTY
         MOMS_FINAL_RE*MED_PROV_COUNTY
         FOREIGN_BORN*MED_PROV_COUNTY
         LD_PAY*MED_PROV_COUNTY
         MOUD_DURING_PREG*MED_PROV_COUNTY
         MATINF_HEPC*MED_PROV_COUNTY
         MOM_DISEASE_STATUS_HCV*MED_PROV_COUNTY
         HCV_DIAG*MED_PROV_COUNTY
         DISCH_WITH_MOM*MED_PROV_COUNTY;
run;

title 'Crosstabulation of Variables by MED_PROV_ZIP';
proc freq data=FINAL_INFANT_COHORT_COV;
  tables APPROPRIATE_Testing*MED_PROV_ZIP
         MOMS_FINAL_RE*MED_PROV_ZIP
         FOREIGN_BORN*MED_PROV_ZIP
         LD_PAY*MED_PROV_ZIP
         MOUD_DURING_PREG*MED_PROV_ZIP
         MATINF_HEPC*MED_PROV_ZIP
         MOM_DISEASE_STATUS_HCV*MED_PROV_ZIP
         HCV_DIAG*MED_PROV_ZIP
         DISCH_WITH_MOM*MED_PROV_ZIP;
run;
title; */

/* Step 2: Based on chi-square test results, decide which variables to keep for multivariable analysis */

/* Step 3: Run multivariable analysis with selected variables */

title 'GliMMIX Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH w/ cluster SE by MOM_ID';
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

/* title 'GENMOD Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH with GEE by MOM_ID';
proc genmod data=FINAL_INFANT_COHORT_COV;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH / dist=binomial link=logit;
    repeated subject=MOM_ID / type=cs;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run; */

proc sort data=FINAL_INFANT_COHORT_COV;
    by WELL_CHILD;
run;

title 'GLIMMIX Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM AGE_BIRTH w/ cluster SE by MOM_ID where WCC =1';
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
	by WELL_CHILD;
    where WELL_CHILD = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM AGE_BIRTH / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

/* title 'GENMOD Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM AGE_BIRTH with GEE by MOM_ID where WELL_CHILD=1';
proc genmod data=FINAL_INFANT_COHORT_COV;
    by WELL_CHILD;
    where WELL_CHILD = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM AGE_BIRTH / dist=binomial link=logit;
    repeated subject=MOM_ID / type=cs;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
run; */

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

title 'GLIMMIX Logistic: Stratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG GESTATIONAL_AGE_CAT WELL_CHILD AGE_BIRTH w/ cluster SE by MOM_ID where DISCH_WITH_MOM = 1';
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG GESTATIONAL_AGE_CAT WELL_CHILD AGE_BIRTH / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run;

/* title 'GENMOD Logistic: Stratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG GESTATIONAL_AGE_CAT WELL_CHILD AGE_BIRTH with GEE by MOM_ID where DISCH_WITH_MOM=1';
proc genmod data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG GESTATIONAL_AGE_CAT WELL_CHILD AGE_BIRTH / dist=binomial link=logit;
    repeated subject=MOM_ID / type=cs;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run;

title 'GENMOD Logistic: Stratified MV; adjusted for FINAL_RE COUNTY MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD with GEE by MOM_ID where DISCH_WITH_MOM=0';
proc genmod data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 0;
    class FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') MOUD_DURING_PREG (ref='No') MATINF_HEPC (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = FINAL_RE COUNTY MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD / dist=binomial link=logit;
    repeated subject=MOM_ID / type=cs;
    format FINAL_RE raceef. MOUD_DURING_PREG flagf. MATINF_HEPC flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run; */

data FINAL_INFANT_COHORT_COV;
    length INFANT_FINAL_RE $30;
    set FINAL_INFANT_COHORT_COV;
    if FINAL_RE = 1 then INFANT_FINAL_RE = 'White Non-Hispanic';
    else if FINAL_RE = 2 then INFANT_FINAL_RE = 'Black non-Hispanic';
    else if FINAL_RE = 4 then INFANT_FINAL_RE = 'Hispanic';
    else if FINAL_RE = 3 then INFANT_FINAL_RE = 'Other non-Hispanic (Asian/PI/AI)';
    else if FINAL_RE = 5 then INFANT_FINAL_RE = 'Other non-Hispanic (Asian/PI/AI)';
    else INFANT_FINAL_RE = 'Missing';
run;

data FINAL_INFANT_COHORT_COV;
    set FINAL_INFANT_COHORT_COV;
    if county NOT IN ('DUKES', 'NANTUCKET') and MED_PROV_COUNTY NOT IN ('DUKES', 'NANTUCKET', 'FRANKLIN');
run;

%Table2Crude_Strat(INFANT_FINAL_RE, ref='White Non-Hispanic');
%Table2Crude_Strat(county, ref='MIDDLESEX');
%Table2Crude_Strat(MED_PROV_COUNTY, ref='MIDDLESEX');

title 'GLIMMIX Logistic: Stratified MV; adjusted for INFANT_FINAL_RE COUNTY MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD w/ cluster SE by MOM_ID where DISCH_WITH_MOM = 0';
	proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 0;
    class INFANT_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') MOUD_DURING_PREG (ref='No') MATINF_HEPC (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing(event='1') = INFANT_FINAL_RE COUNTY MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOUD_DURING_PREG flagf. MATINF_HEPC flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run;

/* OLD REGRESSIONS FOR NOTES:

title 'OUT Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD w/ cluster SE by MOM_ID and FACILITY_ID_BIRTH';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') FACILITY_ID_BIRTH (ref='2010') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=FACILITY_ID_BIRTH(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

title 'OUT Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by WELL_CHILD;
run;

title 'OUT Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM where WELL_CHILD = 1 w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by WELL_CHILD;
    where WELL_CHILD = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
run;

title 'OUT Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

title 'OUT Logistic: Unstratified MV; adjusted for MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH_GROUP w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') COUNTY (ref='MIDDLESEX') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') DISCH_WITH_MOM (ref='No') WELL_CHILD (ref='No') AGE_BIRTH_GROUP (ref ='19-25') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE COUNTY FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM WELL_CHILD AGE_BIRTH_GROUP / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf. WELL_CHILD flagf.;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

title 'OUT Logistic: Stratified MV; adjusted for Maternal Race/Ethnicity, Foreign Born, County, Insurance, MOUD during Pregnancy, HCV Diagnosis (APCD), NAS, Preterm, and WCC w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') COUNTY (ref='MIDDLESEX') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') NAS_BC_TOTAL (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN COUNTY LD_PAY MOUD_DURING_PREG HCV_DIAG NAS_BC_TOTAL GESTATIONAL_AGE_CAT WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. NAS_BC_TOTAL flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run;

title 'OUT Logistic: Stratified MV; adjusted for Maternal Race/Ethnicity, Foreign Born, County, Insurance, MOUD during Pregnancy, HCV Diagnosis (APCD), and WCC w/ cluster SE by MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 1;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') COUNTY (ref='MIDDLESEX') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') WELL_CHILD (ref='No') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN COUNTY LD_PAY MOUD_DURING_PREG HCV_DIAG WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=MOM_ID;
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run;

title 'OUT Logistic: Stratified MV; adjusted for INFANT_FINAL_RE, MOUD_DURING_PREG, MATINF_HEPC, GESTATIONAL_AGE_CAT, and WELL_CHILD w/ cluster SE by FACILITY_ID_BIRTH and MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 0;
    class INFANT_FINAL_RE (ref='White Non-Hispanic') MOUD_DURING_PREG (ref='No') MATINF_HEPC (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') FACILITY_ID_BIRTH (ref='2010') MOM_ID;
    model APPROPRIATE_Testing = INFANT_FINAL_RE MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=FACILITY_ID_BIRTH(MOM_ID);
    format MOUD_DURING_PREG flagf. MATINF_HEPC flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run; 

title 'OUT Logistic: Stratified MV; adjusted for INFANT_FINAL_RE, FOREIGN_BORN, LD_PAY, MOUD_DURING_PREG, MATINF_HEPC, GESTATIONAL_AGE_CAT, and WELL_CHILD w/ cluster SE by FACILITY_ID_BIRTH and MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    where DISCH_WITH_MOM = 0;
    class INFANT_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') MATINF_HEPC (ref='No') GESTATIONAL_AGE_CAT (ref='Term') WELL_CHILD (ref='No') FACILITY_ID_BIRTH (ref='2010') MOM_ID;
    model APPROPRIATE_Testing(event='1') = INFANT_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG MATINF_HEPC GESTATIONAL_AGE_CAT WELL_CHILD / dist=binary link=logit solution oddsratio;
    random intercept / subject=FACILITY_ID_BIRTH(MOM_ID);
    format FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. MATINF_HEPC flagf. WELL_CHILD flagf. DISCH_WITH_MOM flagf.;
run; 

==========================================================
MED_PROV_COUNTY, complete case                            
==========================================================
title 'Logisitic: Unstratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM w/ cluster SE by MOM_ID and MED_PROV_COUNTY';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') MED_PROV_COUNTY (ref='MIDDLESEX') DISCH_WITH_MOM (ref='Yes') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM / solution ddfm=kr;
    random intercept / subject=MED_PROV_COUNTY(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

title 'Logisitic: Stratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG w/ cluster SE by MED_PROV_COUNTY and MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') MED_PROV_COUNTY (ref='MIDDLESEX') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG / solution ddfm=kr;
    random intercept / subject=MED_PROV_COUNTY(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

==========================================================
Log-Binomial Models                         
==========================================================

title 'Log-Binomial: Unstratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM w/ cluster SE by MOM_ID and FACILITY_ID_BIRTH';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') FACILITY_ID_BIRTH (ref='2010') DISCH_WITH_MOM (ref='Yes') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM / solution dist=binomial link=log ddfm=kr;
    random intercept / subject=FACILITY_ID_BIRTH(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

title 'Log-Binomial: Stratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG w/ cluster SE by FACILITY_ID_BIRTH and MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') FACILITY_ID_BIRTH (ref='2010') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG / solution dist=binomial link=log ddfm=kr;
    random intercept / subject=FACILITY_ID_BIRTH(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

title 'Log-Binomial: Unstratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM w/ cluster SE by MOM_ID and MED_PROV_COUNTY';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') MED_PROV_COUNTY (ref='MIDDLESEX') DISCH_WITH_MOM (ref='Yes') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG DISCH_WITH_MOM / solution dist=binomial link=log ddfm=kr;
    random intercept / subject=MED_PROV_COUNTY(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

proc sort data=FINAL_INFANT_COHORT_COV;
    by DISCH_WITH_MOM;
run;

title 'Log-Binomial: Stratified MV; adjusted for MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG w/ cluster SE by MED_PROV_COUNTY and MOM_ID';
proc glimmix data=FINAL_INFANT_COHORT_COV noclprint noitprint;
    by DISCH_WITH_MOM;
    class MOMS_FINAL_RE (ref='White Non-Hispanic') FOREIGN_BORN (ref='No') LD_PAY (ref='Public') MOUD_DURING_PREG (ref='No') HCV_DIAG (ref='No') MED_PROV_COUNTY (ref='MIDDLESEX') MOM_ID;
    model APPROPRIATE_Testing = MOMS_FINAL_RE FOREIGN_BORN LD_PAY MOUD_DURING_PREG HCV_DIAG / solution dist=binomial link=log ddfm=kr;
    random intercept / subject=MED_PROV_COUNTY(MOM_ID);
    format MOMS_FINAL_RE raceef. FOREIGN_BORN fbornf. LD_PAY ld_pay_fmt. MOUD_DURING_PREG flagf. HCV_DIAG flagf. DISCH_WITH_MOM flagf.;
	ods output ParameterEstimates=ParameterEstimates;
run;

*/