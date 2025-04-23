/*==============================================*/
/* Project: PHD Maternal OUD Analysis    	    */
/* Author: Ryan O'Dea and Sarah Munroe          */ 
/* Created: 4/27/2023 		                    */
/* Updated: 03/2025 by SJM  	                */
/*==============================================*/

/*	Project Goal:
	Characterize a cohort of reproductive age women with OUD and Hepatitis C
    Describe MOUD and overdose epiosdes by pregnancy status, race/ethnictiy, and age of OUD diagnosis
    Calculate rates of MOUD initaiton and cesation and fatal and non-fatal overdoses by pregnancy status, important covariate strata and temporality re: MOUD initation and cesssation

    Part 1: Construct OUD cohort
    Part 2: Summary Stats: MOUD and Overdoses
    Part 3: Table 1
    Part 4: Calculate MOUD Rates
    Part 5: Calculate Overdose Rates

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
/*	Overall, the logic behind the known capture is fairly simple: 
search through individual databases and flag if an ICD9, ICD10, 
CPT, NDC, or other specialized code matches our lookup table. 
If a record has one of these codes, it is 'flagged' for OUD. 
The utilized databases are then joined onto the SPINE demographics 
dataset and if the sum of flags is greater than zero, then the 
record is flagged with OUD.  
At current iteration, data being pulled through this method is 
stratified by Year (or Year and Month), Race, Sex, and Age 
(where age groups are defined in the table below). */

/*====================*/
/* 1. Demographics    */
/*====================*/
/* Using data from DEMO, take the cartesian coordinate of years
(as defined above) and months 1:12 to construct a shell table */

PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, YOB, FINAL_SEX, SELF_FUNDED
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

DATA apcd (KEEP= ID oud_apcd year_apcd month_apcd);
	SET PHDAPCD.MOUD_MEDICAL (KEEP= ID MED_ECODE MED_ADM_DIAGNOSIS MED_AGE
								MED_ICD_PROC1-MED_ICD_PROC7
								MED_ICD1-MED_ICD25
								MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH
								MED_DIS_DIAGNOSIS
                                MED_PROC_CODE
                        WHERE= (MED_FROM_DATE_YEAR IN &year));

    cnt_oud_apcd = 0;
    oud_apcd = 0;

    ARRAY icd_fields {*} MED_ECODE MED_ADM_DIAGNOSIS
                         MED_ICD1-MED_ICD25
                         MED_DIS_DIAGNOSIS;

    ARRAY proc_fields {*} MED_ICD_PROC1-MED_ICD_PROC7
                          MED_PROC_CODE;

    DO i = 1 TO dim(icd_fields);
        IF icd_fields[i] IN &ICD THEN cnt_oud_apcd + 1;
    END;

    DO j = 1 TO dim(proc_fields);
        IF proc_fields[j] IN &PROC THEN cnt_oud_apcd + 1;
    END;

	IF cnt_oud_apcd > 0 THEN oud_apcd = 1;
	IF oud_apcd = 0 THEN DELETE;

    year_apcd = MED_FROM_DATE_YEAR;
    month_apcd = MED_FROM_DATE_MONTH;

    DROP i j;
RUN;

PROC SQL;
    CREATE TABLE apcd AS
    SELECT a.ID, 
           a.year_apcd, 
           a.month_apcd, 
           MAX(a.oud_apcd) AS oud_apcd
    FROM apcd a
    INNER JOIN 
        (SELECT ID, MIN(year_apcd) AS year_apcd
         FROM apcd
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_apcd = b.year_apcd
    GROUP BY a.ID, a.year_apcd, a.month_apcd;
QUIT;

DATA pharm (KEEP= oud_pharm ID year_pharm month_pharm);
    SET  PHDAPCD.MOUD_PHARM(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH PHARM_AGE
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;
    IF oud_pharm = 0 THEN DELETE;

year_pharm = PHARM_FILL_DATE_YEAR;
month_pharm = PHARM_FILL_DATE_MONTH;

RUN;

PROC SQL;
    CREATE TABLE pharm AS
    SELECT a.ID, 
           a.year_pharm, 
           a.month_pharm, 
           MAX(a.oud_pharm) AS oud_pharm
    FROM pharm a
    INNER JOIN 
        (SELECT ID, MIN(year_pharm) AS year_pharm
         FROM pharm
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_pharm = b.year_pharm
    GROUP BY a.ID, a.year_pharm, a.month_pharm;
QUIT;

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

DATA casemix_ed (KEEP= ID oud_cm_ed year_cm month_cm ED_ID);
	SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
				  WHERE= (ED_ADMIT_YEAR IN &year));
	IF ED_DIAG1 in &ICD OR 
        ED_PRINCIPLE_ECODE IN &ICD THEN oud_cm_ed = 1;
	ELSE oud_cm_ed = 0;

	IF oud_cm_ed > 0 THEN do;
	year_cm = ED_ADMIT_YEAR;
	month_cm = ED_ADMIT_MONTH;
end;
RUN;

/* ED_DIAG */

DATA casemix_ed_diag (KEEP= oud_cm_ed_diag ED_ID);
	SET PHDCM.ED_DIAG (KEEP= ED_ID ED_DIAG);
	IF ED_DIAG in &ICD THEN oud_cm_ed_diag = 1;
	ELSE oud_cm_ed_diag = 0;

    IF oud_cm_ed_diag = 0 THEN DELETE;

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
    
    IF oud_cm_ed_proc = 0 THEN DELETE;

RUN;

PROC SQL;
    CREATE TABLE casemix_ed_proc AS
    SELECT a.ID, a.ED_ID, a.ED_ADMIT_YEAR, b.oud_cm_ed_proc
    FROM PHDCM.ED AS a
    RIGHT JOIN casemix_ed_proc AS b
    ON a.ED_ID = b.ED_ID
    WHERE a.ED_ADMIT_YEAR IN &year;
QUIT;

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

DATA casemix (KEEP= ID oud_ed year_cm month_cm);
	SET casemix;
	IF SUM(oud_cm_ed_proc, oud_cm_ed_diag, oud_cm_ed) > 0 THEN oud_ed = 1;
	ELSE oud_ed = 0;
	
	IF oud_ed = 0 THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE casemix AS
    SELECT a.ID, 
           a.year_cm, 
           a.month_cm, 
           MAX(a.oud_ed) AS oud_ed
    FROM casemix a
    INNER JOIN 
        (SELECT ID, MIN(year_cm) AS year_cm
         FROM casemix
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_cm = b.year_cm
    GROUP BY a.ID, a.year_cm, a.month_cm;
QUIT;

/*====================*/
/* 4. HD              */
/*====================*/

DATA hd (KEEP= HD_ID ID oud_hd_raw year_hd month_hd);
	SET PHDCM.HD (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH HD_ECODE
					WHERE= (HD_ADMIT_YEAR IN &year));
	IF HD_DIAG1 in &ICD OR
     HD_PROC1 in &PROC OR
     HD_ECODE IN &ICD THEN oud_hd_raw = 1;
	ELSE oud_hd_raw = 0;

	IF oud_hd_raw > 0 THEN do;
    year_hd = HD_ADMIT_YEAR;
    month_hd = HD_ADMIT_MONTH;
end;
RUN;

/* HD DIAG DATA */

DATA hd_diag (KEEP= HD_ID oud_hd_diag);
	SET PHDCM.HD_DIAG (KEEP= HD_ID HD_DIAG);
	IF HD_DIAG in &ICD THEN oud_hd_diag = 1;
	ELSE oud_hd_diag = 0;

    IF oud_hd_diag = 0 THEN DELETE;

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
	SET PHDCM.HD_PROC(KEEP = HD_ID HD_PROC);
	IF HD_PROC IN &PROC THEN oud_hd_proc = 1;
	ELSE oud_hd_proc = 0;
    
    IF oud_hd_proc = 0 THEN DELETE;

RUN;

PROC SQL;
    CREATE TABLE hd_proc AS
    SELECT a.ID, a.HD_ID, a.HD_ADMIT_YEAR, b.oud_hd_proc
    FROM PHDCM.HD AS a
    RIGHT JOIN hd_proc AS b
    ON a.HD_ID = b.HD_ID
    WHERE a.HD_ADMIT_YEAR IN &year;
QUIT;

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

DATA hd (KEEP= ID oud_hd year_hd month_hd);
	SET hd;
	IF SUM(oud_hd_diag, oud_hd_raw, oud_hd_proc) > 0 THEN oud_hd = 1;
	ELSE oud_hd = 0;
	
	IF oud_hd = 0 THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE hd AS
    SELECT a.ID, 
           a.year_hd, 
           a.month_hd, 
           MAX(a.oud_hd) AS oud_hd
    FROM hd a
    INNER JOIN 
        (SELECT ID, MIN(year_hd) AS year_hd
         FROM hd
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_hd = b.year_hd
    GROUP BY a.ID, a.year_hd, a.month_hd;
QUIT;

/*====================*/
/* 5. OO              */
/*====================*/

DATA oo (KEEP= ID oud_oo year_oo month_oo);
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
    month_oo = OO_ADMIT_MONTH;
RUN;

PROC SQL;
    CREATE TABLE oo AS
    SELECT a.ID, 
           a.year_oo, 
           a.month_oo, 
           MAX(a.oud_oo) AS oud_oo
    FROM oo a
    INNER JOIN 
        (SELECT ID, MIN(year_oo) AS year_oo
         FROM oo
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_oo = b.year_oo
    GROUP BY a.ID, a.year_oo, a.month_oo;
QUIT;

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

DATA casemix (KEEP = ID oud_cm year_cm month_cm);
    SET casemix;

    IF oud_ed = 9999 THEN oud_ed = 0;
    IF oud_hd = 9999 THEN oud_hd = 0;
    IF oud_oo = 9999 THEN oud_oo = 0;

    IF sum(oud_ed, oud_hd, oud_oo) > 0 THEN oud_cm = 1;
    ELSE oud_cm = 0;
    IF oud_cm = 0 THEN DELETE;

    oo_date = year_oo + month_oo * 0.01;
    hd_date = year_hd + month_hd * 0.01;
    cm_date = year_cm + month_cm * 0.01;

    min_date = min(oo_date, hd_date, cm_date);

    year_cm = floor(min_date);
    month_cm = round((min_date - year_cm) * 100);
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

DATA bsas (KEEP= ID oud_bsas year_bsas month_bsas);
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
    month_bsas = ENR_MONTH_BSAS;

RUN;

PROC SQL;
    CREATE TABLE bsas AS
    SELECT a.ID, 
           a.year_bsas, 
           a.month_bsas, 
           MAX(a.oud_bsas) AS oud_bsas
    FROM bsas a
    INNER JOIN 
        (SELECT ID, MIN(year_bsas) AS year_bsas
         FROM bsas
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_bsas = b.year_bsas
    GROUP BY a.ID, a.year_bsas, a.month_bsas;
QUIT;

/*====================*/
/* 8. MATRIS          */
/*====================*/
/* The MATRIS Dataset depends on PHD level encoding of variables 
`OPIOID_ORI_MATRIS` and `OPIOID_ORISUBCAT_MATRIS` to 
construct our flag variable, `OUD_MATRIS`. */

DATA matris (KEEP= ID oud_matris year_matris month_matris);
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
    month_matris = inc_month_matris;

RUN;

PROC SQL;
    CREATE TABLE matris AS
    SELECT a.ID, 
           a.year_matris, 
           a.month_matris, 
           MAX(a.oud_matris) AS oud_matris
    FROM matris a
    INNER JOIN 
        (SELECT ID, MIN(year_matris) AS year_matris
         FROM matris
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_matris = b.year_matris
    GROUP BY a.ID, a.year_matris, a.month_matris;
QUIT;

/*====================*/
/* 9. DEATH           */
/*====================*/
/* The Death dataset holds the official cause and manner of 
death assigned by physicians and medical examiners. For our 
purposes, we are only interested in the variable `OPIOID_DEATH` 
which is based on 'ICD10 codes or literal search' from other 
PHD sources.*/

DATA death (KEEP= ID oud_death year_death month_death);
    SET PHDDEATH.DEATH (KEEP= ID OPIOID_DEATH YEAR_DEATH MONTH_DEATH AGE_DEATH
                        WHERE= (YEAR_DEATH IN &year));
    IF OPIOID_DEATH = 1 THEN oud_death = 1;
    ELSE oud_death = 0;
    IF oud_death = 0 THEN DELETE;

    year_death = YEAR_DEATH;
    month_death = MONTH_DEATH;

RUN;

PROC SQL;
    CREATE TABLE death AS
    SELECT a.ID, 
           a.year_death, 
           a.month_death, 
           MAX(a.oud_death) AS oud_death
    FROM death a
    INNER JOIN 
        (SELECT ID, MIN(year_death) AS year_death
         FROM death
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_death = b.year_death
    GROUP BY a.ID, a.year_death, a.month_death;
QUIT;

/*====================*/
/* 10. PMP            */
/*====================*/
/* Within the PMP dataset, we only use the `BUPRENORPHINE_PMP` 
to define the flag `OUD_PMP` - conditioned on BUP_CAT_PMP = 1. */

DATA pmp (KEEP= ID oud_pmp year_pmp month_pmp);
    SET PHDPMP.PMP (KEEP= ID BUPRENORPHINE_PMP date_filled_year AGE_PMP date_filled_month BUP_CAT_PMP
                    WHERE= (date_filled_year IN &year));
    IF BUPRENORPHINE_PMP = 1 AND 
        BUP_CAT_PMP = 1 THEN oud_pmp = 1;
    ELSE oud_pmp = 0;
    IF oud_pmp = 0 THEN DELETE;

    year_pmp = date_filled_year;
    month_pmp = date_filled_month;

RUN;

PROC SQL;
    CREATE TABLE pmp AS
    SELECT a.ID, 
           a.year_pmp, 
           a.month_pmp, 
           MAX(a.oud_pmp) AS oud_pmp
    FROM pmp a
    INNER JOIN 
        (SELECT ID, MIN(year_pmp) AS year_pmp
         FROM pmp
         GROUP BY ID) b
    ON a.ID = b.ID AND a.year_pmp = b.year_pmp
    GROUP BY a.ID, a.year_pmp, a.month_pmp;
QUIT;

DATA pmp;
SET pmp;
BY ID; 
IF first.ID then output;
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

    oud_cnt = sum(of oud_flags[*]);
    IF oud_cnt > 0 THEN oud_master = 1;
    ELSE oud_master = 0;
    IF oud_master = 0 THEN DELETE;

    apcd_date   = year_apcd   + month_apcd   * 0.01;
    cm_date     = year_cm     + month_cm     * 0.01;
    matris_date = year_matris + month_matris * 0.01;
    bsas_date   = year_bsas   + month_bsas   * 0.01;
    pmp_date    = year_pmp    + month_pmp    * 0.01;

    min_date = min(apcd_date, cm_date, matris_date, bsas_date, pmp_date);

    oud_year = floor(min_date);
    oud_month = round((min_date - oud_year) * 100);

    IF oud_year = 9999 THEN oud_age = 999;
    ELSE oud_age = oud_year - YOB;

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
    SELECT DISTINCT ID, oud_year, oud_month, oud_age, age_grp_five as agegrp, FINAL_RE FROM oud;
QUIT;

title "Number of unique IDs in Spine Dataset";
PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM oud_distinct;
QUIT;

%put Number of unique IDs in Spine Dataset: &num_unique_ids;

/*==============================*/
/* 12. Add Pregancy Covariates  */
/*==============================*/

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

title "Number of unique IDs in births table";
PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM births;
QUIT;

%put Number of unique IDs in births table: &num_unique_ids;
title;

PROC SQL;
    CREATE TABLE oud_preg AS
    SELECT * FROM oud_distinct
    LEFT JOIN births ON oud_distinct.ID = births.ID;
QUIT;

DATA oud_preg;
SET oud_preg;
	IF BIRTH_INDICATOR = . THEN BIRTH_INDICATOR = 0;
run;

title "Summary stats: Number of Deliveries per Mom";
proc means data=oud_preg mean median std min max q1 q3;
    var TOTAL_BIRTHS;
run;

/*=====================================*/
/* Part 2: Summary Stats: MOUD         */
/*=====================================*/

/*==============================*/
/* 1.  Import data/demographics */
/*==============================*/
/* This section processes the MOUD dataset, merges it with demographic, age group, and birth data. */

DATA moud;
    SET PHDSPINE.MOUD3;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

PROC SQL;
    CREATE TABLE moud_demo AS
    SELECT moud.*, demographics.FINAL_RE, demographics.YOB
    FROM moud
    LEFT JOIN PHDSPINE.DEMO AS demographics 
    ON moud.ID = demographics.ID;
QUIT;

PROC SQL;
    CREATE TABLE moud_demo AS
    SELECT moud_demo.*, oud.age_grp_five
    FROM moud_demo
    LEFT JOIN oud
    ON moud_demo.ID = oud.ID;
QUIT;

PROC SQL;
    CREATE TABLE moud_demo AS
    SELECT * FROM moud_demo
    LEFT JOIN births ON moud_demo.ID = births.ID;
QUIT;

DATA moud_demo;
    SET moud_demo;
        IF BIRTH_INDICATOR = . THEN BIRTH_INDICATOR = 0;
run;

/*=====================================*/
/* 2. Filter, Deduplicate, and Refine  */
/*=====================================*/
/* This section sorts the MOUD dataset by episode ID, type, and date. It defines start and end dates 
   for each episode, removes short episodes, ensures uniqueness, and resolves overlapping treatment periods. Then,
   it filters for records starting in 2014 or later, and retains only individuals present in the `oud_distinct` dataset */

data moud_demo;
    set moud_demo;
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
    RETAIN new_start_date new_end_date new_start_month new_start_year 
           new_end_month new_end_year YOB FINAL_RE age_grp_five BIRTH_INDICATOR;

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
					  			ID FINAL_RE TYPE_MOUD YOB age_grp_five BIRTH_INDICATOR);
    BY ID new_start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID;

    IF new_end_date - new_start_date < &MOUD_leniency THEN DELETE;

    NED = LAG(new_end_date);

    IF FIRST.ID THEN diff = .; 
    ELSE diff = new_start_date - NED;

    IF new_end_date < NED THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF FIRST.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;

    DROP NED;
RUN;

PROC SORT data=moud_demo;
    BY ID new_start_date;
RUN;

data moud_demo;
    set moud_demo;
    retain episode_num;
    by ID;
    if first.ID then episode_num = 1; 
    else episode_num + 1;
    episode_id = catx("_", ID, episode_num);
run;

proc sql;
    select count(*) as missing_new_end_date
    from moud_demo
    where new_end_date is missing;
quit;

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

proc sql;
    create table moud_demo as
    select moud_demo.*,
           cov.oud_year,
           cov.oud_month
    from moud_demo
    left join oud_distinct as cov
    on moud_demo.ID = cov.ID;
quit;

proc sql;
    create table moud_demo as
    select *
    from moud_demo
    where (new_start_year > oud_year) 
        or (new_start_year = oud_year and new_start_month >= oud_month)
    order by ID, new_start_year, new_start_month;
quit;

/*===============================================*/
/* 3. Summary Statistics for MOUD Participants  */
/*===============================================*/
/* This section calculates the number of unique individuals who experienced MOUD overall and 
   stratifies them by pregnancy status, race/ethnicity, and age at OUD diagnosis. It also 
   generates frequency distributions of MOUD types overall and stratified by these demographics. */

title "Number of persons that experienced MOUD";
PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM moud_demo;
QUIT;

title "Number of persons that experienced MOUD by Pregnancy";
PROC SQL;
    SELECT BIRTH_INDICATOR, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM moud_demo
    GROUP BY BIRTH_INDICATOR;
QUIT;

title "Number of persons that experienced MOUD by FINAL_RE";
PROC SQL;
    SELECT FINAL_RE, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM moud_demo
    GROUP BY FINAL_RE;
QUIT;

title "Number of persons that experienced MOUD by Age at OUD Diagnosis";
PROC SQL;
    SELECT age_grp_five, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM moud_demo
    GROUP BY age_grp_five;
QUIT;

proc format;
    value moud_typef
        1='Likely Methadone'
        2='Buprenorphine'
        3='Naltrexone';
run;

title "Overall Distribution of MOUD Types per episode";
proc freq data=moud_demo;
    table TYPE_MOUD;
    format TYPE_MOUD moud_typef.;
run;

title "Overall Distribution of MOUD episodes Stratified by Pregnancy";
proc sort data=moud_demo;
    by BIRTH_INDICATOR;
run;

proc freq data=moud_demo;
    table TYPE_MOUD;
    format TYPE_MOUD moud_typef.;
    by BIRTH_INDICATOR;
run;

proc sort data=moud_demo;
   by FINAL_RE;
run;

title "Overall Distribution of MOUD episodes Stratified by Race/Ethnicity";
proc freq data=moud_demo;
   by FINAL_RE;
    table TYPE_MOUD;
    format TYPE_MOUD moud_typef.;
run;

proc sort data=moud_demo;
   by age_grp_five;
run;

title "Overall Distribution of MOUD episodes Stratified by Age at OUD Diagnosis";
proc freq data=moud_demo;
   by age_grp_five;
    table TYPE_MOUD;
    format TYPE_MOUD moud_typef.;
run;
title;

/*=======================================*/
/* 4. Identify MOUD Initiation Events   */
/*=======================================*/
/* This section creates a dataset identifying individuals who initiated MOUD, 
   assigning a flag (`moud_start = 1`). It then integrates this information 
   into the `oud_preg` dataset to indicate whether each individual had a MOUD start
   We consider two MOUD start outcomes 1. EVER_MOUD which is simply and ID that exists in
   the MOUD dataset. The other is indicated here, meaning they exist in the cleaned MOUD dataset. */

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
create table moud_preg as select *,
case
when ID in (select ID from moud_starts) then 1
else 0
end as moud_start
from oud_preg;
quit;

/*========================================*/
/* 5. Calculate MOUD Episode Durations   */
/*========================================*/
/* This section calculates the length of each MOUD episode and categorizes 
   them into duration groups (0-1 month, 2-6 months, 6-12 months, 1-2 years, 2+ years, and entire follow-up period). 
   It then summarizes the number of episodes overall and per individual, stratified by 
   pregnancy status, race/ethnicity, and age group. */

data episode_length;
    set moud_demo;

    episode_length = new_end_date - new_start_date;

    episode_1month = 0;
    episode_6months = 0;
    episode_12months = 0;
    episode_24months = 0;
    episode_gt24months = 0;
    episode_full_followup = 0;

    if (new_start_year < 2014 or (new_start_year = 2014 and new_start_month <= 1)) and 
       (new_end_year > 2022 or (new_end_year = 2022 and new_end_month >= 12)) then 
        episode_full_followup = 1;
    else do;
        if episode_length < 30 then episode_1month = 1; /* 0-1 month */
        else if episode_length >= 30 and episode_length < 180 then episode_6months = 1; /* 2-6 months */
        else if episode_length >= 180 and episode_length < 365 then episode_12months = 1; /* 6-12 months */
        else if episode_length >= 365 and episode_length < 730 then episode_24months = 1; /* 1-2 years */
        else if episode_length >= 730 then episode_gt24months = 1; /* 2+ years */
    end;

run;

title "Frequency Distribution of Episode Length";
proc freq data=episode_length;
    tables episode_1month episode_6months episode_12months 
           episode_24months episode_gt24months episode_full_followup;
run;

proc sort data=episode_length;
    by TYPE_MOUD;
run;

title "Frequency Distribution of Episode Length by MOUD Type";
proc freq data=episode_length;
    by TYPE_MOUD;
    tables episode_1month episode_6months episode_12months 
           episode_24months episode_gt24months episode_full_followup;
run;
title;

proc sort data=episode_length;
    by ID descending episode_length;
run;

data episode_length_personlvl;
    set episode_length;
    by ID;
    if first.ID;
run;	

title "Frequency Distribution of Episode Length - Person-Level Data";
proc freq data=episode_length_personlvl;
    tables episode_1month episode_6months episode_12months 
           episode_24months episode_gt24months episode_full_followup;
run;

proc sort data=episode_length_personlvl;
    by TYPE_MOUD;
run;

title "Frequency Distribution of Episode Length by MOUD Type - Person-Level Data ";
proc freq data=episode_length_personlvl;
    by TYPE_MOUD;
    tables episode_1month episode_6months episode_12months 
           episode_24months episode_gt24months episode_full_followup;
run;
title;

proc sql;
    create table episode_counts as
    select ID,
    	   BIRTH_INDICATOR,
    	   FINAL_RE,
    	   age_grp_five,
           count(*) as num_episodes
    from episode_length
    group by ID;
quit;

proc sql;
    create table episode_counts as
    select distinct ID, BIRTH_INDICATOR, FINAL_RE, age_grp_five, num_episodes
    from episode_counts;
quit;

title "Summary stats: Mean number of MOUD episodes per person";
proc means data=episode_counts mean median std min max q1 q3;
    var num_episodes;
run;

title "Summary stats: Mean number of MOUD episodes per person by BIRTH_INDICATOR";
proc means data=episode_counts mean median std min max q1 q3;
    class BIRTH_INDICATOR;
    var num_episodes;
run;

title "Summary stats: Mean number of MOUD episodes per person by FINAL_RE";
proc means data=episode_counts mean median std min max q1 q3;
    class FINAL_RE;
    var num_episodes;
run;

title "Summary stats: Mean number of MOUD episodes per person by Age at OUD Diagnosis";
proc means data=episode_counts mean median std min max q1 q3;
    class age_grp_five;
    var num_episodes;
run;

title "Summary stats: MOUD episode duration (days)";
proc means data=episode_length mean median std min max q1 q3;
    var episode_length;
run;

title "Summary stats: MOUD episode duration (days) by BIRTH_INDICATOR";
proc means data=episode_length mean median std min max q1 q3;
    class BIRTH_INDICATOR;
    var episode_length;
run;

title "Summary stats: MOUD episode duration (days) by FINAL_RE";
proc means data=episode_length mean median std min max q1 q3;
    class FINAL_RE;
    var episode_length;
run;

title "Summary stats: MOUD episode duration (days) by Age at OUD Diagnosis";
proc means data=episode_length mean median std min max q1 q3;
    class age_grp_five;
    var episode_length;
run;

/*===============================================*/
/* 7. Aggregating MOUD Episodes and Validation  */
/*===============================================*/
/* This section aggregates the duration-based classification of MOUD episodes 
   per individual, merges the episode counts into the pregnancy dataset, 
   and performs validation checks to ensure consistency in episode classification. */

proc sql;
    create table aggregated_episode as
    select ID,
           sum(episode_1month) as episode_1month_sum,
           sum(episode_6months) as episode_6months_sum,
           sum(episode_12months) as episode_12months_sum,
           sum(episode_24months) as episode_24months_sum,
           sum(episode_gt24months) as episode_gt24months_sum,
           sum(episode_full_followup) as episode_full_followup_sum
    from episode_length
    group by ID;
quit;

data moud_preg;
    merge moud_preg (in=a) episode_counts (in=b);
    by ID;
    if a;
run;

data moud_preg;
    merge moud_preg (in=a) aggregated_episode (in=b);
    by ID;
    if a;
run;

data moud_preg;
    set moud_preg;
    
    if episode_12months_sum > 0 or episode_24months_sum > 0 or 
       episode_gt24months_sum > 0 or episode_full_followup_sum > 0 then
        EVER_6MO = 1;
    else
        EVER_6MO = 0;
run;

data check_moud_count;
    set moud_preg;
    
    MOUD_Sum = sum(episode_1month_sum, episode_6months_sum, 
                   episode_12months_sum, episode_24months_sum, 
                   episode_gt24months_sum, episode_full_followup_sum);

    if MOUD_Sum = num_episodes then MOUD_Match = 1;
    else MOUD_Match = 0;
run;

title "Check that the sum of MOUD_duration variables = number MOUD episodes";
proc freq data=check_moud_count;
   tables MOUD_Match;
run;
title;

/*================================================*/
/* 9. Processing Overdose Data and Merging Demographics */
/*================================================*/
/* This section processes the overdose dataset, filters it for data from 2014 onwards, 
   merges with the MOUD pregnancy data, and joins additional demographic information. */

DATA overdose_spine (KEEP=ID OD_YEAR OD_RACE OD_COUNT OD_AGE OD_DATE FATAL_OD_DEATH);
    SET PHDSPINE.OVERDOSE;
RUN;

data overdose_spine;
    set overdose_spine;
    where OD_YEAR >= 2014;
run;

PROC SQL;
    CREATE TABLE overdose_spine AS 
    SELECT * 
    FROM overdose_spine
    WHERE ID IN (SELECT DISTINCT ID FROM moud_preg);
QUIT;

PROC SQL;
    CREATE TABLE overdose_spine AS
    SELECT * FROM overdose_spine
    LEFT JOIN births ON overdose_spine.ID = births.ID;
QUIT;

DATA overdose_spine;
    SET overdose_spine;
        IF BIRTH_INDICATOR = . THEN BIRTH_INDICATOR = 0;
run;

PROC SQL;
    CREATE TABLE overdose_spine AS
    SELECT overdose_spine.*, demographics.FINAL_RE, demographics.YOB
    FROM overdose_spine
    LEFT JOIN PHDSPINE.DEMO AS demographics 
    ON overdose_spine.ID = demographics.ID;
QUIT;

PROC SQL;
    CREATE TABLE overdose_spine AS
    SELECT overdose_spine.*, oud.age_grp_five
    FROM overdose_spine
    LEFT JOIN oud
    ON overdose_spine.ID = oud.ID;
QUIT;

/*==============================================*/
/* 10. Overdose Summary and Counts by Demographics */
/*==============================================*/
/* This section calculates and displays the number of unique IDs that experienced an overdose,
   stratified by BIRTH_INDICATOR, FINAL_RE, and age group. */

title "Number of persons that experienced overdose";
PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM overdose_spine;
QUIT;

proc sort data=overdose_spine;
    by BIRTH_INDICATOR;
run;

PROC SQL;
    CREATE TABLE overdose_summary AS
    SELECT BIRTH_INDICATOR, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM overdose_spine
    GROUP BY BIRTH_INDICATOR;
QUIT;

PROC PRINT DATA=overdose_summary;
    TITLE 'Number of Unique IDs that Experienced Overdoses by BIRTH_INDICATOR';
RUN;

PROC SQL;
    CREATE TABLE overdose_summary AS
    SELECT FINAL_RE, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM overdose_spine
    GROUP BY FINAL_RE;
QUIT;

PROC PRINT DATA=overdose_summary;
    TITLE 'Number of Unique IDs that Experienced Overdoses by FINAL_RE';
RUN;

PROC SQL;
    CREATE TABLE overdose_summary AS
    SELECT age_grp_five, 
           COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    FROM overdose_spine
    GROUP BY age_grp_five;
QUIT;

PROC PRINT DATA=overdose_summary;
    TITLE 'Number of Unique IDs that Experienced Overdoses by Age at OUD Diagnosis';
RUN;

/*====================================================*/
/* 11. Overdose Flag Summary and Counts by Demographics */
/*====================================================*/
/* This section generates and summarizes overdose data by creating an "overdose flag" based on the fatality status,
   and then stratifies this data by key demographic factors including pregnancy status, race/ethnicity, and age at OUD diagnosis. 
   The summary statistics for overdose counts per person are also calculated, both overall and stratified by pregnancy status. */

proc sort data=overdose_spine;
   by ID OD_DATE;
run;

proc sql;
    create table overdose_summary as
    select ID,
           BIRTH_INDICATOR,
           OD_RACE,
           OD_AGE,
           FATAL_OD_DEATH,
           case when FATAL_OD_DEATH = 1 then 2
                else 1 end as overdose_flag
    from overdose_spine
 quit;
 
data overdose_summary;
     set overdose_summary;
     OD_AGE = put(OD_AGE, age_grps_five.);
run;
 
title "Overall Distribution of Overdose Flag";
proc freq data=overdose_summary;
    tables overdose_flag;
run;
 
title "Overall Distribution of Overdose Flag Stratified by Pregnancy";
proc sort data=overdose_summary;
     by BIRTH_INDICATOR;
run;
 
proc freq data=overdose_summary;
     tables overdose_flag;
     by BIRTH_INDICATOR;
run;
 
proc sort data=overdose_summary;
    by OD_RACE;
run;

title "Distribution of Overdose Flag Stratified by Race/Ethnicity";
proc freq data=overdose_summary;
    by OD_RACE;
    tables overdose_flag;
run;
 
proc sort data=overdose_summary;
    by OD_AGE;
run;
 
title "Distribution of Overdose Flag Stratified by Age at OUD Diagnosis";
proc freq data=overdose_summary;
    by OD_AGE;
    tables overdose_flag;
run;
 
proc sql;
    create table overdose_counts as
    select ID, 
    max(BIRTH_INDICATOR) as BIRTH_INDICATOR, 
    max(OD_Count) as OD_Count
    from overdose_spine
    group by ID;
quit;
 
title "Summary stats: Overdose counts per person";
proc means data=overdose_counts mean median std min max q1 q3;
    var OD_Count;
run;
 
proc means data=overdose_counts mean median std min max q1 q3;
    class BIRTH_INDICATOR;
    var OD_Count;
run;
 
/*==========================================================*/
/* 12. MOUD Episodes and Overdose During/After MOUD         */
/*==========================================================*/
/* This section processes the MOUD start and end dates for each individual, and identifies episodes of overdose during and after MOUD treatment. 
The array is necessary to pivot from episode-level to person-level data to allow the calculation of overdose occurrences during the treatment period, 
within 30 days after treatment, or with no MOUD treatment. */

PROC SORT data=moud_demo;
  by ID new_start_date;
RUN;

PROC TRANSPOSE data=moud_demo out=moud_demo_wide_start (KEEP = ID new_start_date:) PREFIX=new_start_date_;
  BY ID;
  VAR new_start_date;
RUN;

PROC TRANSPOSE data=moud_demo out=moud_demo_wide_end (KEEP = ID new_end_date:) PREFIX=new_end_date_;
  BY ID;
  VAR new_end_date;
RUN;

DATA moud_demo_final;
  MERGE moud_demo_wide_start (IN=a) moud_demo_wide_end (IN=b);
  BY ID;
RUN;

 DATA moud_od_demo;
   MERGE overdose_spine (IN=a) moud_demo_final (IN=b);
   BY ID;
   IF a;  
 RUN;
 
DATA moud_od_demo;
    SET moud_od_demo;
    BY ID;

    ARRAY MOUD_START (*) new_start_date_:;
    ARRAY MOUD_END (*) new_end_date_:;

    num_moud_episodes = DIM(MOUD_START);

    RETAIN OD_during_MOUD OD_after_MOUD OD_no_MOUD OD_COUNT_CHECK;

    IF FIRST.ID THEN DO;
        OD_during_MOUD = 0;  
        OD_after_MOUD = 0;  
        OD_no_MOUD = 0;  
        OD_COUNT_CHECK = 0; /*  This variable is to check the total N ODs per person since OD_COUNT is persistent through whole OD table, while we clean the table and filter short episodes */
    END;

    DO i = 1 TO num_moud_episodes;
        /* Case 1: Both MOUD_START(i) and MOUD_END(i) are present */
        IF NOT MISSING(MOUD_START(i)) AND NOT MISSING(MOUD_END(i)) THEN DO;
            IF OD_DATE >= MOUD_START(i) AND OD_DATE <= MOUD_END(i) THEN DO;
                OD_during_MOUD + 1;
                OD_COUNT_CHECK + 1;
            END;
            ELSE IF OD_DATE > MOUD_END(i) AND OD_DATE <= MOUD_END(i) + 30 THEN DO;
                OD_after_MOUD + 1;
                OD_COUNT_CHECK + 1;
            END;
        END;

        /* Case 2: MOUD_END(i) is present, but MOUD_START(i) is missing */
        ELSE IF MISSING(MOUD_START(i)) AND NOT MISSING(MOUD_END(i)) THEN DO;
            IF OD_DATE <= MOUD_END(i) THEN DO;
                OD_during_MOUD + 1;
                OD_COUNT_CHECK + 1;
            END;
            ELSE IF OD_DATE > MOUD_END(i) AND OD_DATE <= MOUD_END(i) + 30 THEN DO;
                OD_after_MOUD + 1;
                OD_COUNT_CHECK + 1;
            END;
        END;

        /* Case 3: MOUD_START(i) is present, but MOUD_END(i) is missing */
        ELSE IF NOT MISSING(MOUD_START(i)) AND MISSING(MOUD_END(i)) THEN DO;
            IF OD_DATE >= MOUD_START(i) THEN DO;
                OD_during_MOUD + 1;
                OD_COUNT_CHECK + 1;
            END;
        END;
		END;
      
    IF OD_during_MOUD = . THEN OD_during_MOUD = 0;
    IF OD_after_MOUD = . THEN OD_after_MOUD = 0;

    IF OD_during_MOUD = 0 AND OD_after_MOUD = 0 THEN DO;
    OD_no_MOUD + 1;
    OD_COUNT_CHECK + 1;
    END; 

    DROP i;
RUN;

proc sql;
    create table overdose_summary as 
    select 
        ID, 
        max(OD_COUNT) as TOTAL_OD_COUNT,
        max(OD_during_MOUD) as N_OD_during_MOUD,
        max(OD_after_MOUD) as N_OD_after_MOUD,
        max(OD_no_MOUD) as N_OD_no_MOUD,
        max(OD_COUNT_CHECK) as OD_COUNT_CHECK
    from moud_od_demo
    group by ID;
quit;

proc sql;
    create table overdose_summary as
    select distinct *
    from overdose_summary;
quit;

PROC SQL;
    CREATE TABLE moud_preg AS
    SELECT * FROM moud_preg
    LEFT JOIN overdose_summary ON moud_preg.ID = overdose_summary.ID;
QUIT;

DATA moud_preg;
SET moud_preg;
IF TOTAL_OD_COUNT = . THEN DO;
    TOTAL_OD_COUNT = 0;
    N_OD_no_MOUD = 0;
    N_OD_during_MOUD = 0;
    N_OD_after_MOUD = 0;
    OD_COUNT_CHECK = 0;
END;
RUN;

DATA check_od_count;
    set moud_preg;

    if missing(N_OD_no_MOUD) then N_OD_no_MOUD = 0;
    if missing(N_OD_during_MOUD) then N_OD_during_MOUD = 0;
    if missing(N_OD_after_MOUD) then N_OD_after_MOUD = 0;

    OD_Sum = sum(N_OD_no_MOUD, N_OD_during_MOUD, N_OD_after_MOUD);

    if OD_Sum = TOTAL_OD_COUNT then OD_Match = 1;
    else OD_Match = 0;
    
    if OD_COUNT_CHECK = OD_Sum then OD_COUNT_MATCH = 1;
    else OD_COUNT_MATCH = 0;

RUN;

/*==========================================================*/
/* 14. Overdose Validation and Distribution Analysis          */
/*==========================================================*/
/* This section validates that the sum of overdose occurrences (during, after, and without MOUD treatment) matches the total overdose count. The frequency distribution of OD_Match is checked, 
   and summary statistics for overdose counts are calculated to examine the distribution of overdoses relative to MOUD treatment status. */

title "Check that the sum of OD_during_MOUD variables = TOTAL_OD_COUNT and OD_COUNT_CHECK consistency";
proc freq data=check_od_count;
   tables OD_Match OD_COUNT_MATCH;
run;
title;
 
title "Distribution of OD relative to MOUD";
data check_od_count;
   set check_od_count;
   total_overdoses = sum(of N_OD_no_MOUD N_OD_during_MOUD N_OD_after_MOUD);
run;

proc means data=check_od_count sum;
   var N_OD_no_MOUD N_OD_during_MOUD N_OD_after_MOUD total_overdoses;
run;
title;

 PROC SQL;
     SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
     INTO :num_unique_ids
     FROM moud_preg;
 QUIT;
 
 %put Number of Unique IDs in Main Dataset: &num_unique_ids; 

/* ======================= */
/* Part 3: Table 1         */
/* ======================= */

proc sql;
    create table FINAL_COHORT as
    select moud_preg.*,
           demographics.HOMELESS_EVER,
           demographics.EVER_INCARCERATED,
           demographics.FOREIGN_BORN,
           demographics.LANGUAGE,
           demographics.EDUCATION,
           demographics.YOB,
           demographics.OCCUPATION_CODE
    from moud_preg
    left join PHDSPINE.DEMO as demographics
    on moud_preg.ID = demographics.ID;
quit;

data FINAL_COHORT;
    length LANGUAGE_SPOKEN_GROUP $30;
    set FINAL_COHORT;
    if LANGUAGE = 1 then LANGUAGE_SPOKEN_GROUP = 'English';
    else if LANGUAGE = 2 then LANGUAGE_SPOKEN_GROUP = 'English and Another Language';
    else if LANGUAGE = 3 then LANGUAGE_SPOKEN_GROUP = 'Another Language';
    else LANGUAGE_SPOKEN_GROUP = 'Refused or Unknown';
run;

data FINAL_COHORT;
    length HOMELESS_HISTORY_GROUP $10;
    set FINAL_COHORT;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

data FINAL_COHORT;
    length EDUCATION_GROUP $30;
    set FINAL_COHORT;
    if EDUCATION = 1 then EDUCATION_GROUP = 'HS or less';
    else if EDUCATION = 2 then EDUCATION_GROUP = '13+ years';
    else EDUCATION_GROUP = 'Other or Unknown';
run;

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

PROC SORT DATA=PHDHEPC.HCV;
    BY ID EVENT_DATE_HCV;
RUN;

DATA HCV_STATUS;
    SET PHDHEPC.HCV;
    BY ID EVENT_DATE_HCV;
    IF FIRST.ID THEN DO;
        HCV_SEROPOSITIVE_INDICATOR = 1;
        CONFIRMED_HCV_INDICATOR = (DISEASE_STATUS_HCV = 1);
        OUTPUT;
    END;
KEEP ID AGE_HCV EVENT_MONTH_HCV EVENT_YEAR_HCV EVENT_DATE_HCV HCV_SEROPOSITIVE_INDICATOR CONFIRMED_HCV_INDICATOR;
RUN;

PROC SQL;
    CREATE TABLE IDU_STATUS AS 
    SELECT ID,
        CASE 
            WHEN SUM(EVER_IDU_HCV = 1) > 0 THEN 1 
            WHEN SUM(EVER_IDU_HCV = 0) > 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 0 
            WHEN SUM(EVER_IDU_HCV = 9) > 0 AND SUM(EVER_IDU_HCV = 0) <= 0 AND SUM(EVER_IDU_HCV = 1) <= 0 THEN 9 
            ELSE 9 
        END AS EVER_IDU_HCV
    FROM PHDHEPC.HCV
    GROUP BY ID;
QUIT;

PROC SQL;
    CREATE TABLE HCV_STATUS AS 
    SELECT A.*, B.EVER_IDU_HCV
    FROM HCV_STATUS A
    LEFT JOIN IDU_STATUS B ON A.ID = B.ID;
QUIT;

PROC SQL;
    CREATE TABLE FINAL_COHORT AS
    SELECT * FROM FINAL_COHORT 
    LEFT JOIN HCV_STATUS ON HCV_STATUS.ID = FINAL_COHORT.ID;
QUIT;

data FINAL_COHORT;
    set FINAL_COHORT;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;

proc sort data=FINAL_COHORT;
    by ID oud_year oud_month;
run;

DATA apcd;
    SET PHDAPCD.ME_MTH;
RUN;

proc sort data=apcd;
    by ID ME_MEM_YEAR ME_MEM_MONTH;
run;

data closest_insurance;
    length closest_past_type closest_future_type closest_type $2;
    length closest_past_zip closest_future_zip closest_zip $10;
    format closest_past_zip closest_future_zip closest_zip $5.;
    
    merge FINAL_COHORT (in=a)
          apcd (in=b);
    by ID;
    
    if a;

    retain closest_past_date closest_past_type closest_past_zip min_past_diff;
    retain closest_future_date closest_future_type closest_future_zip min_future_diff;
    retain found_exact_match;

    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        closest_past_zip = "";
        min_past_diff = .;
        
        closest_future_date = .;
        closest_future_type = "";
        closest_future_zip = "";
        min_future_diff = .;
        
        found_exact_match = 0;
    end;

    /* If claim is from the exact same month/year, take the first one and stop searching */
    if ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH = EVENT_MONTH_HCV then do;
        if found_exact_match = 0 then do; 
            closest_type = ME_INSURANCE_PRODUCT;
            closest_zip = RES_ZIP_APCD_ME;
            found_exact_match = 1;
            output;
        end;
    end;

    /* Only process past/future claims if no exact match was found */
    else if found_exact_match = 0 then do;
        /* Identify the closest past claim */
        if ME_MEM_YEAR < EVENT_YEAR_HCV or (ME_MEM_YEAR = EVENT_YEAR_HCV and ME_MEM_MONTH < EVENT_MONTH_HCV) then do;
            past_diff = (EVENT_YEAR_HCV - ME_MEM_YEAR) * 12 + (EVENT_MONTH_HCV - ME_MEM_MONTH);
            if min_past_diff = . or past_diff < min_past_diff then do;
                min_past_diff = past_diff;
                closest_past_date = ME_MEM_YEAR * 100 + ME_MEM_MONTH; 
                closest_past_type = ME_INSURANCE_PRODUCT;
                closest_past_zip = RES_ZIP_APCD_ME;
            end;
        end;

        /* Identify the closest future claim */
        else do;
            future_diff = (ME_MEM_YEAR - EVENT_YEAR_HCV) * 12 + (ME_MEM_MONTH - EVENT_MONTH_HCV);
            if min_future_diff = . or future_diff < min_future_diff then do;
                min_future_diff = future_diff;
                closest_future_date = ME_MEM_YEAR * 100 + ME_MEM_MONTH;
                closest_future_type = ME_INSURANCE_PRODUCT;
                closest_future_zip = RES_ZIP_APCD_ME;
            end;
        end;
    end;

    if last.ID and found_exact_match = 0 then do;
        /* Ensure only one claim per ID */
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
        
        /* Prevent duplicates by outputting only once per ID */
        if closest_type ne "" then output;
    end;

run;

data final_output;
    set closest_insurance;
    keep ID EVENT_YEAR_HCV EVENT_MONTH_HCV closest_type closest_zip;
run;

proc sort data=final_output;
    by ID;
run;

data FINAL_COHORT;
    merge FINAL_COHORT (in=a)
          final_output (keep=ID closest_type closest_zip
                       rename=(closest_type=INSURANCE));
    by ID;
    if a;
run;

data FINAL_COHORT;
   set FINAL_COHORT;
	 if closest_zip = "02351" then RES_CODE = 1;
else if closest_zip = "01718" then RES_CODE = 2;
else if closest_zip = "01720" then RES_CODE = 2;
else if closest_zip = "02743" then RES_CODE = 3;
else if closest_zip = "01220" then RES_CODE = 4;
else if closest_zip = "01001" then RES_CODE = 5;
else if closest_zip = "01030" then RES_CODE = 5;
else if closest_zip = "01230" then RES_CODE = 6;
else if closest_zip = "01913" then RES_CODE = 7;
else if closest_zip = "01003" then RES_CODE = 8;
else if closest_zip = "01004" then RES_CODE = 8;
else if closest_zip = "01059" then RES_CODE = 8;
else if closest_zip = "01810" then RES_CODE = 9;
else if closest_zip = "01812" then RES_CODE = 9;
else if closest_zip = "01899" then RES_CODE = 9;
else if closest_zip = "02174" then RES_CODE = 10;
else if closest_zip = "02175" then RES_CODE = 10;
else if closest_zip = "02474" then RES_CODE = 10;
else if closest_zip = "02475" then RES_CODE = 10;
else if closest_zip = "02476" then RES_CODE = 10;
else if closest_zip = "01430" then RES_CODE = 11;
else if closest_zip = "01466" then RES_CODE = 11;
else if closest_zip = "01431" then RES_CODE = 12;
else if closest_zip = "01330" then RES_CODE = 13;
else if closest_zip = "01721" then RES_CODE = 14;
else if closest_zip = "01331" then RES_CODE = 15;
else if closest_zip = "02703" then RES_CODE = 16;
else if closest_zip = "02760" then RES_CODE = 16;
else if closest_zip = "02763" then RES_CODE = 16;
else if closest_zip = "01501" then RES_CODE = 17;
else if closest_zip = "02322" then RES_CODE = 18;
else if closest_zip = "01432" then RES_CODE = 19;
else if closest_zip = "01433" then RES_CODE = 19;
else if closest_zip = "02601" then RES_CODE = 20;
else if closest_zip = "02630" then RES_CODE = 20;
else if closest_zip = "02632" then RES_CODE = 20;
else if closest_zip = "02634" then RES_CODE = 20;
else if closest_zip = "02635" then RES_CODE = 20;
else if closest_zip = "02636" then RES_CODE = 20;
else if closest_zip = "02637" then RES_CODE = 20;
else if closest_zip = "02647" then RES_CODE = 20;
else if closest_zip = "02648" then RES_CODE = 20;
else if closest_zip = "02655" then RES_CODE = 20;
else if closest_zip = "02668" then RES_CODE = 20;
else if closest_zip = "02672" then RES_CODE = 20;
else if closest_zip = "01005" then RES_CODE = 21;
else if closest_zip = "01074" then RES_CODE = 21;
else if closest_zip = "01223" then RES_CODE = 22;
else if closest_zip = "01730" then RES_CODE = 23;
else if closest_zip = "01731" then RES_CODE = 23;
else if closest_zip = "01007" then RES_CODE = 24;
else if closest_zip = "02019" then RES_CODE = 25;
else if closest_zip = "02178" then RES_CODE = 26;
else if closest_zip = "02179" then RES_CODE = 26;
else if closest_zip = "02478" then RES_CODE = 26;
else if closest_zip = "02479" then RES_CODE = 26;
else if closest_zip = "02779" then RES_CODE = 27;
else if closest_zip = "01503" then RES_CODE = 28;
else if closest_zip = "01337" then RES_CODE = 29;
else if closest_zip = "01915" then RES_CODE = 30;
else if closest_zip = "01965" then RES_CODE = 30;
else if closest_zip = "01821" then RES_CODE = 31;
else if closest_zip = "01822" then RES_CODE = 31;
else if closest_zip = "01862" then RES_CODE = 31;
else if closest_zip = "01865" then RES_CODE = 31;
else if closest_zip = "01866" then RES_CODE = 31;
else if closest_zip = "01504" then RES_CODE = 32;
else if closest_zip = "01008" then RES_CODE = 33;
else if closest_zip = "01740" then RES_CODE = 34;
else if closest_zip = "02101" then RES_CODE = 35;
else if closest_zip = "02102" then RES_CODE = 35;
else if closest_zip = "02103" then RES_CODE = 35;
else if closest_zip = "02104" then RES_CODE = 35;
else if closest_zip = "02105" then RES_CODE = 35;
else if closest_zip = "02106" then RES_CODE = 35;
else if closest_zip = "02107" then RES_CODE = 35;
else if closest_zip = "02108" then RES_CODE = 35;
else if closest_zip = "02109" then RES_CODE = 35;
else if closest_zip = "02110" then RES_CODE = 35;
else if closest_zip = "02111" then RES_CODE = 35;
else if closest_zip = "02112" then RES_CODE = 35;
else if closest_zip = "02113" then RES_CODE = 35;
else if closest_zip = "02114" then RES_CODE = 35;
else if closest_zip = "02115" then RES_CODE = 35;
else if closest_zip = "02116" then RES_CODE = 35;
else if closest_zip = "02117" then RES_CODE = 35;
else if closest_zip = "02118" then RES_CODE = 35;
else if closest_zip = "02119" then RES_CODE = 35;
else if closest_zip = "02120" then RES_CODE = 35;
else if closest_zip = "02121" then RES_CODE = 35;
else if closest_zip = "02122" then RES_CODE = 35;
else if closest_zip = "02123" then RES_CODE = 35;
else if closest_zip = "02124" then RES_CODE = 35;
else if closest_zip = "02125" then RES_CODE = 35;
else if closest_zip = "02126" then RES_CODE = 35;
else if closest_zip = "02127" then RES_CODE = 35;
else if closest_zip = "02128" then RES_CODE = 35;
else if closest_zip = "02129" then RES_CODE = 35;
else if closest_zip = "02130" then RES_CODE = 35;
else if closest_zip = "02131" then RES_CODE = 35;
else if closest_zip = "02132" then RES_CODE = 35;
else if closest_zip = "02133" then RES_CODE = 35;
else if closest_zip = "02134" then RES_CODE = 35;
else if closest_zip = "02135" then RES_CODE = 35;
else if closest_zip = "02136" then RES_CODE = 35;
else if closest_zip = "02137" then RES_CODE = 35;
else if closest_zip = "02163" then RES_CODE = 35;
else if closest_zip = "02196" then RES_CODE = 35;
else if closest_zip = "02199" then RES_CODE = 35;
else if closest_zip = "02201" then RES_CODE = 35;
else if closest_zip = "02202" then RES_CODE = 35;
else if closest_zip = "02203" then RES_CODE = 35;
else if closest_zip = "02204" then RES_CODE = 35;
else if closest_zip = "02205" then RES_CODE = 35;
else if closest_zip = "02206" then RES_CODE = 35;
else if closest_zip = "02207" then RES_CODE = 35;
else if closest_zip = "02208" then RES_CODE = 35;
else if closest_zip = "02209" then RES_CODE = 35;
else if closest_zip = "02210" then RES_CODE = 35;
else if closest_zip = "02211" then RES_CODE = 35;
else if closest_zip = "02212" then RES_CODE = 35;
else if closest_zip = "02215" then RES_CODE = 35;
else if closest_zip = "02216" then RES_CODE = 35;
else if closest_zip = "02217" then RES_CODE = 35;
else if closest_zip = "02222" then RES_CODE = 35;
else if closest_zip = "02241" then RES_CODE = 35;
else if closest_zip = "02266" then RES_CODE = 35;
else if closest_zip = "02293" then RES_CODE = 35;
else if closest_zip = "02295" then RES_CODE = 35;
else if closest_zip = "02297" then RES_CODE = 35;
else if closest_zip = "02562" then RES_CODE = 36;
else if closest_zip = "02532" then RES_CODE = 36;
else if closest_zip = "02534" then RES_CODE = 36;
else if closest_zip = "02553" then RES_CODE = 36;
else if closest_zip = "02559" then RES_CODE = 36;
else if closest_zip = "02561" then RES_CODE = 36;
else if closest_zip = "01719" then RES_CODE = 37;
else if closest_zip = "01885" then RES_CODE = 38;
else if closest_zip = "01921" then RES_CODE = 38;
else if closest_zip = "01505" then RES_CODE = 39;
else if closest_zip = "02184" then RES_CODE = 40;
else if closest_zip = "02185" then RES_CODE = 40;
else if closest_zip = "02631" then RES_CODE = 41;
else if closest_zip = "02324" then RES_CODE = 42;
else if closest_zip = "02325" then RES_CODE = 42;
else if closest_zip = "01010" then RES_CODE = 43;
else if closest_zip = "02301" then RES_CODE = 44;
else if closest_zip = "02302" then RES_CODE = 44;
else if closest_zip = "02303" then RES_CODE = 44;
else if closest_zip = "02304" then RES_CODE = 44;
else if closest_zip = "02401" then RES_CODE = 44;
else if closest_zip = "02402" then RES_CODE = 44;
else if closest_zip = "02403" then RES_CODE = 44;
else if closest_zip = "02404" then RES_CODE = 44;
else if closest_zip = "02405" then RES_CODE = 44;
else if closest_zip = "01506" then RES_CODE = 45;
else if closest_zip = "02146" then RES_CODE = 46;
else if closest_zip = "02147" then RES_CODE = 46;
else if closest_zip = "02445" then RES_CODE = 46;
else if closest_zip = "02446" then RES_CODE = 46;
else if closest_zip = "02447" then RES_CODE = 46;
else if closest_zip = "02467" then RES_CODE = 46;
else if closest_zip = "01338" then RES_CODE = 47;
else if closest_zip = "01803" then RES_CODE = 48;
else if closest_zip = "01805" then RES_CODE = 48;
else if closest_zip = "02138" then RES_CODE = 49;
else if closest_zip = "02139" then RES_CODE = 49;
else if closest_zip = "02140" then RES_CODE = 49;
else if closest_zip = "02141" then RES_CODE = 49;
else if closest_zip = "02142" then RES_CODE = 49;
else if closest_zip = "02238" then RES_CODE = 49;
else if closest_zip = "02239" then RES_CODE = 49;
else if closest_zip = "02021" then RES_CODE = 50;
else if closest_zip = "01741" then RES_CODE = 51;
else if closest_zip = "02330" then RES_CODE = 52;
else if closest_zip = "02355" then RES_CODE = 52;
else if closest_zip = "02366" then RES_CODE = 52;
else if closest_zip = "01339" then RES_CODE = 53;
else if closest_zip = "01507" then RES_CODE = 54;
else if closest_zip = "01508" then RES_CODE = 54;
else if closest_zip = "01509" then RES_CODE = 54;
else if closest_zip = "02633" then RES_CODE = 55;
else if closest_zip = "02650" then RES_CODE = 55;
else if closest_zip = "02659" then RES_CODE = 55;
else if closest_zip = "02669" then RES_CODE = 55;
else if closest_zip = "01824" then RES_CODE = 56;
else if closest_zip = "01863" then RES_CODE = 56;
else if closest_zip = "02150" then RES_CODE = 57;
else if closest_zip = "01225" then RES_CODE = 58;
else if closest_zip = "01011" then RES_CODE = 59;
else if closest_zip = "01050" then RES_CODE = 143;
else if closest_zip = "01012" then RES_CODE = 60;
else if closest_zip = "01026" then RES_CODE = 60;
else if closest_zip = "01084" then RES_CODE = 60;
else if closest_zip = "01013" then RES_CODE = 61;
else if closest_zip = "01014" then RES_CODE = 61;
else if closest_zip = "01020" then RES_CODE = 61;
else if closest_zip = "01021" then RES_CODE = 61;
else if closest_zip = "01022" then RES_CODE = 61;
else if closest_zip = "02535" then RES_CODE = 62;
else if closest_zip = "02552" then RES_CODE = 62;
else if closest_zip = "01247" then RES_CODE = 63;
else if closest_zip = "01510" then RES_CODE = 64;
else if closest_zip = "02025" then RES_CODE = 65;
else if closest_zip = "01340" then RES_CODE = 66;
else if closest_zip = "01369" then RES_CODE = 66;
else if closest_zip = "01742" then RES_CODE = 67;
else if closest_zip = "01341" then RES_CODE = 68;
else if closest_zip = "01226" then RES_CODE = 70;
else if closest_zip = "01227" then RES_CODE = 70;
else if closest_zip = "01923" then RES_CODE = 71;
else if closest_zip = "01937" then RES_CODE = 71;
else if closest_zip = "02714" then RES_CODE = 72;
else if closest_zip = "02747" then RES_CODE = 72;
else if closest_zip = "02748" then RES_CODE = 72;
else if closest_zip = "02026" then RES_CODE = 73;
else if closest_zip = "02027" then RES_CODE = 73;
else if closest_zip = "01342" then RES_CODE = 74;
else if closest_zip = "02638" then RES_CODE = 75;
else if closest_zip = "02639" then RES_CODE = 75;
else if closest_zip = "02641" then RES_CODE = 75;
else if closest_zip = "02660" then RES_CODE = 75;
else if closest_zip = "02670" then RES_CODE = 75;
else if closest_zip = "02715" then RES_CODE = 76;
else if closest_zip = "02754" then RES_CODE = 76;
else if closest_zip = "02764" then RES_CODE = 76;
else if closest_zip = "01516" then RES_CODE = 77;
else if closest_zip = "02030" then RES_CODE = 78;
else if closest_zip = "01826" then RES_CODE = 79;
else if closest_zip = "01571" then RES_CODE = 80;
else if closest_zip = "01827" then RES_CODE = 81;
else if closest_zip = "02331" then RES_CODE = 82;
else if closest_zip = "02332" then RES_CODE = 82;
else if closest_zip = "02333" then RES_CODE = 83;
else if closest_zip = "02337" then RES_CODE = 83;
else if closest_zip = "01515" then RES_CODE = 84;
else if closest_zip = "01028" then RES_CODE = 85;
else if closest_zip = "02642" then RES_CODE = 86;
else if closest_zip = "02651" then RES_CODE = 86;
else if closest_zip = "01027" then RES_CODE = 87;
else if closest_zip = "02334" then RES_CODE = 88;
else if closest_zip = "02356" then RES_CODE = 88;
else if closest_zip = "02357" then RES_CODE = 88;
else if closest_zip = "02375" then RES_CODE = 88;
else if closest_zip = "02539" then RES_CODE = 89;
else if closest_zip = "01252" then RES_CODE = 90;
else if closest_zip = "01344" then RES_CODE = 91;
else if closest_zip = "01929" then RES_CODE = 92;
else if closest_zip = "02149" then RES_CODE = 93;
else if closest_zip = "02719" then RES_CODE = 94;
else if closest_zip = "02720" then RES_CODE = 95;
else if closest_zip = "02721" then RES_CODE = 95;
else if closest_zip = "02722" then RES_CODE = 95;
else if closest_zip = "02723" then RES_CODE = 95;
else if closest_zip = "02724" then RES_CODE = 95;
else if closest_zip = "02536" then RES_CODE = 96;
else if closest_zip = "02540" then RES_CODE = 96;
else if closest_zip = "02541" then RES_CODE = 96;
else if closest_zip = "02543" then RES_CODE = 96;
else if closest_zip = "02556" then RES_CODE = 96;
else if closest_zip = "02565" then RES_CODE = 96;
else if closest_zip = "02574" then RES_CODE = 96;
else if closest_zip = "01420" then RES_CODE = 97;
else if closest_zip = "01343" then RES_CODE = 98;
else if closest_zip = "02035" then RES_CODE = 99;
else if closest_zip = "01701" then RES_CODE = 100;
else if closest_zip = "01702" then RES_CODE = 100;
else if closest_zip = "01703" then RES_CODE = 100;
else if closest_zip = "01705" then RES_CODE = 100;
else if closest_zip = "02038" then RES_CODE = 101;
else if closest_zip = "02702" then RES_CODE = 102;
else if closest_zip = "02717" then RES_CODE = 102;
else if closest_zip = "01440" then RES_CODE = 103;
else if closest_zip = "01441" then RES_CODE = 103;
else if closest_zip = "02535" then RES_CODE = 104;
else if closest_zip = "01833" then RES_CODE = 105;
else if closest_zip = "01354" then RES_CODE = 106;
else if closest_zip = "01376" then RES_CODE = 192;
else if closest_zip = "01930" then RES_CODE = 107;
else if closest_zip = "01931" then RES_CODE = 107;
else if closest_zip = "01032" then RES_CODE = 108;
else if closest_zip = "01096" then RES_CODE = 108;
else if closest_zip = "02713" then RES_CODE = 109;
else if closest_zip = "01519" then RES_CODE = 110;
else if closest_zip = "01536" then RES_CODE = 110;
else if closest_zip = "01560" then RES_CODE = 110;
else if closest_zip = "01033" then RES_CODE = 111;
else if closest_zip = "01034" then RES_CODE = 112;
else if closest_zip = "01230" then RES_CODE = 113;
else if closest_zip = "01244" then RES_CODE = 203;
else if closest_zip = "01301" then RES_CODE = 114;
else if closest_zip = "01302" then RES_CODE = 114;
else if closest_zip = "01450" then RES_CODE = 115;
else if closest_zip = "01470" then RES_CODE = 115;
else if closest_zip = "01471" then RES_CODE = 115;
else if closest_zip = "01472" then RES_CODE = 115;
else if closest_zip = "01834" then RES_CODE = 116;
else if closest_zip = "01035" then RES_CODE = 117;
else if closest_zip = "02338" then RES_CODE = 118;
else if closest_zip = "01936" then RES_CODE = 119;
else if closest_zip = "01982" then RES_CODE = 119;
else if closest_zip = "01036" then RES_CODE = 120;
else if closest_zip = "01201" then RES_CODE = 121;
else if closest_zip = "02339" then RES_CODE = 122;
else if closest_zip = "02340" then RES_CODE = 122;
else if closest_zip = "02341" then RES_CODE = 123;
else if closest_zip = "02350" then RES_CODE = 123;
else if closest_zip = "01031" then RES_CODE = 124;
else if closest_zip = "01037" then RES_CODE = 124;
else if closest_zip = "01094" then RES_CODE = 124;
else if closest_zip = "01434" then RES_CODE = 125;
else if closest_zip = "01451" then RES_CODE = 125;
else if closest_zip = "01467" then RES_CODE = 125;
else if closest_zip = "02645" then RES_CODE = 126;
else if closest_zip = "02646" then RES_CODE = 126;
else if closest_zip = "02661" then RES_CODE = 126;
else if closest_zip = "02671" then RES_CODE = 126;
else if closest_zip = "01038" then RES_CODE = 127;
else if closest_zip = "01066" then RES_CODE = 127;
else if closest_zip = "01088" then RES_CODE = 127;
else if closest_zip = "01830" then RES_CODE = 128;
else if closest_zip = "01831" then RES_CODE = 128;
else if closest_zip = "01832" then RES_CODE = 128;
else if closest_zip = "01835" then RES_CODE = 128;
else if closest_zip = "01339" then RES_CODE = 128;
else if closest_zip = "01070" then RES_CODE = 129;
else if closest_zip = "01346" then RES_CODE = 130;
else if closest_zip = "02043" then RES_CODE = 131;
else if closest_zip = "02044" then RES_CODE = 131;
else if closest_zip = "01226" then RES_CODE = 132;
else if closest_zip = "02343" then RES_CODE = 133;
else if closest_zip = "01520" then RES_CODE = 134;
else if closest_zip = "01522" then RES_CODE = 134;
else if closest_zip = "01521" then RES_CODE = 135;
else if closest_zip = "01746" then RES_CODE = 136;
else if closest_zip = "01040" then RES_CODE = 137;
else if closest_zip = "01041" then RES_CODE = 137;
else if closest_zip = "01747" then RES_CODE = 138;
else if closest_zip = "01748" then RES_CODE = 139;
else if closest_zip = "01784" then RES_CODE = 139;
else if closest_zip = "01452" then RES_CODE = 140;
else if closest_zip = "01749" then RES_CODE = 141;
else if closest_zip = "02045" then RES_CODE = 142;
else if closest_zip = "01050" then RES_CODE = 143;
else if closest_zip = "01938" then RES_CODE = 144;
else if closest_zip = "02364" then RES_CODE = 145;
else if closest_zip = "02347" then RES_CODE = 146;
else if closest_zip = "01523" then RES_CODE = 147;
else if closest_zip = "01561" then RES_CODE = 147;
else if closest_zip = "01224" then RES_CODE = 148;
else if closest_zip = "01237" then RES_CODE = 148;
else if closest_zip = "01840" then RES_CODE = 149;
else if closest_zip = "01841" then RES_CODE = 149;
else if closest_zip = "01842" then RES_CODE = 149;
else if closest_zip = "01843" then RES_CODE = 149;
else if closest_zip = "01238" then RES_CODE = 150;
else if closest_zip = "01260" then RES_CODE = 150;
else if closest_zip = "01524" then RES_CODE = 151;
else if closest_zip = "01542" then RES_CODE = 151;
else if closest_zip = "01611" then RES_CODE = 151;
else if closest_zip = "01240" then RES_CODE = 152;
else if closest_zip = "01242" then RES_CODE = 152;
else if closest_zip = "01453" then RES_CODE = 153;
else if closest_zip = "01054" then RES_CODE = 154;
else if closest_zip = "02173" then RES_CODE = 155;
else if closest_zip = "02420" then RES_CODE = 155;
else if closest_zip = "02421" then RES_CODE = 155;
else if closest_zip = "01301" then RES_CODE = 156;
else if closest_zip = "01773" then RES_CODE = 157;
else if closest_zip = "01460" then RES_CODE = 158;
else if closest_zip = "01106" then RES_CODE = 159;
else if closest_zip = "01116" then RES_CODE = 159;
else if closest_zip = "01850" then RES_CODE = 160;
else if closest_zip = "01851" then RES_CODE = 160;
else if closest_zip = "01852" then RES_CODE = 160;
else if closest_zip = "01853" then RES_CODE = 160;
else if closest_zip = "01854" then RES_CODE = 160;
else if closest_zip = "01056" then RES_CODE = 161;
else if closest_zip = "01462" then RES_CODE = 162;
else if closest_zip = "01901" then RES_CODE = 163;
else if closest_zip = "01902" then RES_CODE = 163;
else if closest_zip = "01903" then RES_CODE = 163;
else if closest_zip = "01904" then RES_CODE = 163;
else if closest_zip = "01905" then RES_CODE = 163;
else if closest_zip = "01910" then RES_CODE = 163;
else if closest_zip = "01940" then RES_CODE = 164;
else if closest_zip = "02148" then RES_CODE = 165;
else if closest_zip = "01944" then RES_CODE = 166;
else if closest_zip = "02031" then RES_CODE = 167;
else if closest_zip = "02048" then RES_CODE = 167;
else if closest_zip = "01945" then RES_CODE = 168;
else if closest_zip = "01947" then RES_CODE = 168;
else if closest_zip = "02738" then RES_CODE = 169;
else if closest_zip = "01752" then RES_CODE = 170;
else if closest_zip = "02020" then RES_CODE = 171;
else if closest_zip = "02041" then RES_CODE = 171;
else if closest_zip = "02047" then RES_CODE = 264;
else if closest_zip = "02050" then RES_CODE = 171;
else if closest_zip = "02051" then RES_CODE = 171;
else if closest_zip = "02059" then RES_CODE = 171;
else if closest_zip = "02065" then RES_CODE = 171;
else if closest_zip = "02649" then RES_CODE = 172;
else if closest_zip = "02739" then RES_CODE = 173;
else if closest_zip = "01754" then RES_CODE = 174;
else if closest_zip = "02052" then RES_CODE = 175;
else if closest_zip = "02153" then RES_CODE = 176;
else if closest_zip = "02155" then RES_CODE = 176;
else if closest_zip = "02156" then RES_CODE = 176;
else if closest_zip = "02053" then RES_CODE = 177;
else if closest_zip = "02176" then RES_CODE = 178;
else if closest_zip = "02177" then RES_CODE = 178;
else if closest_zip = "01756" then RES_CODE = 179;
else if closest_zip = "01860" then RES_CODE = 180;
else if closest_zip = "01844" then RES_CODE = 181;
else if closest_zip = "02344" then RES_CODE = 182;
else if closest_zip = "02346" then RES_CODE = 182;
else if closest_zip = "02348" then RES_CODE = 182;
else if closest_zip = "02349" then RES_CODE = 182;
else if closest_zip = "01243" then RES_CODE = 183;
else if closest_zip = "01949" then RES_CODE = 184;
else if closest_zip = "01757" then RES_CODE = 185;
else if closest_zip = "01527" then RES_CODE = 186;
else if closest_zip = "01586" then RES_CODE = 186;
else if closest_zip = "02054" then RES_CODE = 187;
else if closest_zip = "01529" then RES_CODE = 188;
else if closest_zip = "02186" then RES_CODE = 189;
else if closest_zip = "02187" then RES_CODE = 189;
else if closest_zip = "01350" then RES_CODE = 190;
else if closest_zip = "01057" then RES_CODE = 191;
else if closest_zip = "01347" then RES_CODE = 192;
else if closest_zip = "01349" then RES_CODE = 192;
else if closest_zip = "01351" then RES_CODE = 192;
else if closest_zip = "01245" then RES_CODE = 193;
else if closest_zip = "01050" then RES_CODE = 194;
else if closest_zip = "01258" then RES_CODE = 195;
else if closest_zip = "01908" then RES_CODE = 196;
else if closest_zip = "02554" then RES_CODE = 197;
else if closest_zip = "02564" then RES_CODE = 197;
else if closest_zip = "02584" then RES_CODE = 197;
else if closest_zip = "01760" then RES_CODE = 198;
else if closest_zip = "02192" then RES_CODE = 199;
else if closest_zip = "02194" then RES_CODE = 199;
else if closest_zip = "02492" then RES_CODE = 199;
else if closest_zip = "02494" then RES_CODE = 199;
else if closest_zip = "01220" then RES_CODE = 200;
else if closest_zip = "02740" then RES_CODE = 201;
else if closest_zip = "02741" then RES_CODE = 201;
else if closest_zip = "02742" then RES_CODE = 201;
else if closest_zip = "02744" then RES_CODE = 201;
else if closest_zip = "02745" then RES_CODE = 201;
else if closest_zip = "02746" then RES_CODE = 201;
else if closest_zip = "01531" then RES_CODE = 202;
else if closest_zip = "01259" then RES_CODE = 203;
else if closest_zip = "01355" then RES_CODE = 204;
else if closest_zip = "01922" then RES_CODE = 205;
else if closest_zip = "01951" then RES_CODE = 205;
else if closest_zip = "01950" then RES_CODE = 206;
else if closest_zip = "02158" then RES_CODE = 207;
else if closest_zip = "02159" then RES_CODE = 207;
else if closest_zip = "02160" then RES_CODE = 207;
else if closest_zip = "02161" then RES_CODE = 207;
else if closest_zip = "02162" then RES_CODE = 207;
else if closest_zip = "02164" then RES_CODE = 207;
else if closest_zip = "02165" then RES_CODE = 207;
else if closest_zip = "02166" then RES_CODE = 207;
else if closest_zip = "02167" then RES_CODE = 207;
else if closest_zip = "02168" then RES_CODE = 207;
else if closest_zip = "02195" then RES_CODE = 207;
else if closest_zip = "02258" then RES_CODE = 207;
else if closest_zip = "02456" then RES_CODE = 207;
else if closest_zip = "02458" then RES_CODE = 207;
else if closest_zip = "02459" then RES_CODE = 207;
else if closest_zip = "02460" then RES_CODE = 207;
else if closest_zip = "02461" then RES_CODE = 207;
else if closest_zip = "02462" then RES_CODE = 207;
else if closest_zip = "02464" then RES_CODE = 207;
else if closest_zip = "02465" then RES_CODE = 207;
else if closest_zip = "02466" then RES_CODE = 207;
else if closest_zip = "02468" then RES_CODE = 207;
else if closest_zip = "02495" then RES_CODE = 207;
else if closest_zip = "02056" then RES_CODE = 208;
else if closest_zip = "01247" then RES_CODE = 209;
else if closest_zip = "01845" then RES_CODE = 210;
else if closest_zip = "02760" then RES_CODE = 211;
else if closest_zip = "02761" then RES_CODE = 211;
else if closest_zip = "02763" then RES_CODE = 211;
else if closest_zip = "02739" then RES_CODE = 211;
else if closest_zip = "01535" then RES_CODE = 212;
else if closest_zip = "01864" then RES_CODE = 213;
else if closest_zip = "01889" then RES_CODE = 213;
else if closest_zip = "01053" then RES_CODE = 214;
else if closest_zip = "01060" then RES_CODE = 214;
else if closest_zip = "01061" then RES_CODE = 214;
else if closest_zip = "01062" then RES_CODE = 214;
else if closest_zip = "01063" then RES_CODE = 214;
else if closest_zip = "01532" then RES_CODE = 215;
else if closest_zip = "01534" then RES_CODE = 216;
else if closest_zip = "01588" then RES_CODE = 216;
else if closest_zip = "01360" then RES_CODE = 217;
else if closest_zip = "02712" then RES_CODE = 218;
else if closest_zip = "02766" then RES_CODE = 218;
else if closest_zip = "02018" then RES_CODE = 219;
else if closest_zip = "02061" then RES_CODE = 219;
else if closest_zip = "02062" then RES_CODE = 220;
else if closest_zip = "02557" then RES_CODE = 221;
else if closest_zip = "01068" then RES_CODE = 222;
else if closest_zip = "01364" then RES_CODE = 223;
else if closest_zip = "02643" then RES_CODE = 224;
else if closest_zip = "02653" then RES_CODE = 224;
else if closest_zip = "02662" then RES_CODE = 223;
else if closest_zip = "01029" then RES_CODE = 225;
else if closest_zip = "01253" then RES_CODE = 225;
else if closest_zip = "01537" then RES_CODE = 226;
else if closest_zip = "01540" then RES_CODE = 226;
else if closest_zip = "01009" then RES_CODE = 227;
else if closest_zip = "01069" then RES_CODE = 227;
else if closest_zip = "01079" then RES_CODE = 227;
else if closest_zip = "01080" then RES_CODE = 227;
else if closest_zip = "01612" then RES_CODE = 228;
else if closest_zip = "01960" then RES_CODE = 229;
else if closest_zip = "01961" then RES_CODE = 229;
else if closest_zip = "01964" then RES_CODE = 229;
else if closest_zip = "01002" then RES_CODE = 230;
else if closest_zip = "02327" then RES_CODE = 231;
else if closest_zip = "02358" then RES_CODE = 231;
else if closest_zip = "02359" then RES_CODE = 231;
else if closest_zip = "01463" then RES_CODE = 232;
else if closest_zip = "01235" then RES_CODE = 233;
else if closest_zip = "01366" then RES_CODE = 234;
else if closest_zip = "01201" then RES_CODE = 236;
else if closest_zip = "01202" then RES_CODE = 236;
else if closest_zip = "01203" then RES_CODE = 236;
else if closest_zip = "01070" then RES_CODE = 237;
else if closest_zip = "02762" then RES_CODE = 238;
else if closest_zip = "02345" then RES_CODE = 239;
else if closest_zip = "02360" then RES_CODE = 239;
else if closest_zip = "02361" then RES_CODE = 239;
else if closest_zip = "02362" then RES_CODE = 239;
else if closest_zip = "02363" then RES_CODE = 239;
else if closest_zip = "02381" then RES_CODE = 239;
else if closest_zip = "02367" then RES_CODE = 240;
else if closest_zip = "01517" then RES_CODE = 241;
else if closest_zip = "01541" then RES_CODE = 241;
else if closest_zip = "02657" then RES_CODE = 242;
else if closest_zip = "02169" then RES_CODE = 243;
else if closest_zip = "02170" then RES_CODE = 243;
else if closest_zip = "02171" then RES_CODE = 243;
else if closest_zip = "02269" then RES_CODE = 243;
else if closest_zip = "02368" then RES_CODE = 244;
else if closest_zip = "02767" then RES_CODE = 245;
else if closest_zip = "02768" then RES_CODE = 245;
else if closest_zip = "01867" then RES_CODE = 246;
else if closest_zip = "02769" then RES_CODE = 247;
else if closest_zip = "02151" then RES_CODE = 248;
else if closest_zip = "01254" then RES_CODE = 249;
else if closest_zip = "02770" then RES_CODE = 250;
else if closest_zip = "02370" then RES_CODE = 251;
else if closest_zip = "01966" then RES_CODE = 252;
else if closest_zip = "01367" then RES_CODE = 253;
else if closest_zip = "01969" then RES_CODE = 254;
else if closest_zip = "01368" then RES_CODE = 255;
else if closest_zip = "01071" then RES_CODE = 256;
else if closest_zip = "01097" then RES_CODE = 256;
else if closest_zip = "01543" then RES_CODE = 257;
else if closest_zip = "01970" then RES_CODE = 258;
else if closest_zip = "01971" then RES_CODE = 258;
else if closest_zip = "01952" then RES_CODE = 259;
else if closest_zip = "01255" then RES_CODE = 260;
else if closest_zip = "02537" then RES_CODE = 261;
else if closest_zip = "02542" then RES_CODE = 261;
else if closest_zip = "02563" then RES_CODE = 261;
else if closest_zip = "02644" then RES_CODE = 261;
else if closest_zip = "01906" then RES_CODE = 262;
else if closest_zip = "01256" then RES_CODE = 263;
else if closest_zip = "02040" then RES_CODE = 264;
else if closest_zip = "02055" then RES_CODE = 264;
else if closest_zip = "02060" then RES_CODE = 264;
else if closest_zip = "02066" then RES_CODE = 264;
else if closest_zip = "02771" then RES_CODE = 265;
else if closest_zip = "02067" then RES_CODE = 266;
else if closest_zip = "01222" then RES_CODE = 267;
else if closest_zip = "01257" then RES_CODE = 267;
else if closest_zip = "01370" then RES_CODE = 268;
else if closest_zip = "01770" then RES_CODE = 269;
else if closest_zip = "01464" then RES_CODE = 270;
else if closest_zip = "01545" then RES_CODE = 271;
else if closest_zip = "01546" then RES_CODE = 271;
else if closest_zip = "01072" then RES_CODE = 272;
else if closest_zip = "02725" then RES_CODE = 273;
else if closest_zip = "02726" then RES_CODE = 273;
else if closest_zip = "02143" then RES_CODE = 274;
else if closest_zip = "02144" then RES_CODE = 274;
else if closest_zip = "02145" then RES_CODE = 274;
else if closest_zip = "01075" then RES_CODE = 275;
else if closest_zip = "01073" then RES_CODE = 276;
else if closest_zip = "01745" then RES_CODE = 277;
else if closest_zip = "01772" then RES_CODE = 277;
else if closest_zip = "01550" then RES_CODE = 278;
else if closest_zip = "01077" then RES_CODE = 279;
else if closest_zip = "01562" then RES_CODE = 280;
else if closest_zip = "01101" then RES_CODE = 281;
else if closest_zip = "01102" then RES_CODE = 281;
else if closest_zip = "01103" then RES_CODE = 281;
else if closest_zip = "01104" then RES_CODE = 281;
else if closest_zip = "01105" then RES_CODE = 281;
else if closest_zip = "01107" then RES_CODE = 281;
else if closest_zip = "01108" then RES_CODE = 281;
else if closest_zip = "01109" then RES_CODE = 281;
else if closest_zip = "01111" then RES_CODE = 281;
else if closest_zip = "01114" then RES_CODE = 281;
else if closest_zip = "01115" then RES_CODE = 281;
else if closest_zip = "01118" then RES_CODE = 281;
else if closest_zip = "01119" then RES_CODE = 281;
else if closest_zip = "01128" then RES_CODE = 281;
else if closest_zip = "01129" then RES_CODE = 281;
else if closest_zip = "01133" then RES_CODE = 281;
else if closest_zip = "01138" then RES_CODE = 281;
else if closest_zip = "01139" then RES_CODE = 281;
else if closest_zip = "01144" then RES_CODE = 281;
else if closest_zip = "01151" then RES_CODE = 281;
else if closest_zip = "01152" then RES_CODE = 281;
else if closest_zip = "01199" then RES_CODE = 281;
else if closest_zip = "01564" then RES_CODE = 282;
else if closest_zip = "01229" then RES_CODE = 283;
else if closest_zip = "01262" then RES_CODE = 283;
else if closest_zip = "01263" then RES_CODE = 283;
else if closest_zip = "02180" then RES_CODE = 284;
else if closest_zip = "02072" then RES_CODE = 285;
else if closest_zip = "01775" then RES_CODE = 286;
else if closest_zip = "01518" then RES_CODE = 287;
else if closest_zip = "01566" then RES_CODE = 287;
else if closest_zip = "01776" then RES_CODE = 288;
else if closest_zip = "01375" then RES_CODE = 289;
else if closest_zip = "01526" then RES_CODE = 290;
else if closest_zip = "01590" then RES_CODE = 290;
else if closest_zip = "01907" then RES_CODE = 291;
else if closest_zip = "02777" then RES_CODE = 292;
else if closest_zip = "02718" then RES_CODE = 293;
else if closest_zip = "02780" then RES_CODE = 293;
else if closest_zip = "01436" then RES_CODE = 294;
else if closest_zip = "01438" then RES_CODE = 294;
else if closest_zip = "01468" then RES_CODE = 294;
else if closest_zip = "01876" then RES_CODE = 295;
else if closest_zip = "02568" then RES_CODE = 296;
else if closest_zip = "02573" then RES_CODE = 296;
else if closest_zip = "01983" then RES_CODE = 298;
else if closest_zip = "01469" then RES_CODE = 299;
else if closest_zip = "01474" then RES_CODE = 299;
else if closest_zip = "02652" then RES_CODE = 300;
else if closest_zip = "02666" then RES_CODE = 300;
else if closest_zip = "01879" then RES_CODE = 301;
else if closest_zip = "01264" then RES_CODE = 302;
else if closest_zip = "01568" then RES_CODE = 303;
else if closest_zip = "01525" then RES_CODE = 304;
else if closest_zip = "01538" then RES_CODE = 304;
else if closest_zip = "01569" then RES_CODE = 304;
else if closest_zip = "01880" then RES_CODE = 305;
else if closest_zip = "01081" then RES_CODE = 306;
else if closest_zip = "02032" then RES_CODE = 307;
else if closest_zip = "02071" then RES_CODE = 307;
else if closest_zip = "02081" then RES_CODE = 307;
else if closest_zip = "02154" then RES_CODE = 308;
else if closest_zip = "02254" then RES_CODE = 308;
else if closest_zip = "02451" then RES_CODE = 308;
else if closest_zip = "02452" then RES_CODE = 308;
else if closest_zip = "02453" then RES_CODE = 308;
else if closest_zip = "02454" then RES_CODE = 308;
else if closest_zip = "02455" then RES_CODE = 308;
else if closest_zip = "01082" then RES_CODE = 309;
else if closest_zip = "02538" then RES_CODE = 310;
else if closest_zip = "02558" then RES_CODE = 310;
else if closest_zip = "02571" then RES_CODE = 310;
else if closest_zip = "02576" then RES_CODE = 310;
else if closest_zip = "01083" then RES_CODE = 311;
else if closest_zip = "01092" then RES_CODE = 311;
else if closest_zip = "01378" then RES_CODE = 312;
else if closest_zip = "01223" then RES_CODE = 313;
else if closest_zip = "02172" then RES_CODE = 314;
else if closest_zip = "02272" then RES_CODE = 314;
else if closest_zip = "02277" then RES_CODE = 314;
else if closest_zip = "02471" then RES_CODE = 314;
else if closest_zip = "02472" then RES_CODE = 314;
else if closest_zip = "01778" then RES_CODE = 315;
else if closest_zip = "01570" then RES_CODE = 316;
else if closest_zip = "02157" then RES_CODE = 317;
else if closest_zip = "02181" then RES_CODE = 317;
else if closest_zip = "02457" then RES_CODE = 317;
else if closest_zip = "02481" then RES_CODE = 317;
else if closest_zip = "02482" then RES_CODE = 317;
else if closest_zip = "02663" then RES_CODE = 318;
else if closest_zip = "02667" then RES_CODE = 318;
else if closest_zip = "01379" then RES_CODE = 319;
else if closest_zip = "01380" then RES_CODE = 319;
else if closest_zip = "01984" then RES_CODE = 320;
else if closest_zip = "01539" then RES_CODE = 321;
else if closest_zip = "01583" then RES_CODE = 321;
else if closest_zip = "02379" then RES_CODE = 322;
else if closest_zip = "01585" then RES_CODE = 323;
else if closest_zip = "01985" then RES_CODE = 324;
else if closest_zip = "01089" then RES_CODE = 113;
else if closest_zip = "01090" then RES_CODE = 113;
else if closest_zip = "01236" then RES_CODE = 325;
else if closest_zip = "01266" then RES_CODE = 326;
else if closest_zip = "02575" then RES_CODE = 327;
else if closest_zip = "01580" then RES_CODE = 328;
else if closest_zip = "01581" then RES_CODE = 328;
else if closest_zip = "01582" then RES_CODE = 328;
else if closest_zip = "01085" then RES_CODE = 329;
else if closest_zip = "01086" then RES_CODE = 329;
else if closest_zip = "01886" then RES_CODE = 330;
else if closest_zip = "01027" then RES_CODE = 331;
else if closest_zip = "01473" then RES_CODE = 332;
else if closest_zip = "02193" then RES_CODE = 333;
else if closest_zip = "02493" then RES_CODE = 333;
else if closest_zip = "02790" then RES_CODE = 334;
else if closest_zip = "02791" then RES_CODE = 334;
else if closest_zip = "02090" then RES_CODE = 335;
else if closest_zip = "02188" then RES_CODE = 336;
else if closest_zip = "02189" then RES_CODE = 336;
else if closest_zip = "02190" then RES_CODE = 336;
else if closest_zip = "02191" then RES_CODE = 336;
else if closest_zip = "01093" then RES_CODE = 337;
else if closest_zip = "01373" then RES_CODE = 337;
else if closest_zip = "02382" then RES_CODE = 338;
else if closest_zip = "01095" then RES_CODE = 339;
else if closest_zip = "01039" then RES_CODE = 340;
else if closest_zip = "01267" then RES_CODE = 341;
else if closest_zip = "01887" then RES_CODE = 342;
else if closest_zip = "01475" then RES_CODE = 343;
else if closest_zip = "01477" then RES_CODE = 343;
else if closest_zip = "01890" then RES_CODE = 344;
else if closest_zip = "01270" then RES_CODE = 345;
else if closest_zip = "02152" then RES_CODE = 346;
else if closest_zip = "01801" then RES_CODE = 347;
else if closest_zip = "01806" then RES_CODE = 347;
else if closest_zip = "01807" then RES_CODE = 347;
else if closest_zip = "01808" then RES_CODE = 347;
else if closest_zip = "01813" then RES_CODE = 347;
else if closest_zip = "01814" then RES_CODE = 347;
else if closest_zip = "01815" then RES_CODE = 347;
else if closest_zip = "01888" then RES_CODE = 347;
else if closest_zip = "01601" then RES_CODE = 348;
else if closest_zip = "01602" then RES_CODE = 348;
else if closest_zip = "01603" then RES_CODE = 348;
else if closest_zip = "01604" then RES_CODE = 348;
else if closest_zip = "01605" then RES_CODE = 348;
else if closest_zip = "01606" then RES_CODE = 348;
else if closest_zip = "01607" then RES_CODE = 348;
else if closest_zip = "01608" then RES_CODE = 348;
else if closest_zip = "01609" then RES_CODE = 348;
else if closest_zip = "01610" then RES_CODE = 348;
else if closest_zip = "01613" then RES_CODE = 348;
else if closest_zip = "01614" then RES_CODE = 348;
else if closest_zip = "01615" then RES_CODE = 348;
else if closest_zip = "01653" then RES_CODE = 348;
else if closest_zip = "01654" then RES_CODE = 348;
else if closest_zip = "01655" then RES_CODE = 348;
else if closest_zip = "01098" then RES_CODE = 349;
else if closest_zip = "02070" then RES_CODE = 350;
else if closest_zip = "02093" then RES_CODE = 350;
else if closest_zip = "02664" then RES_CODE = 351;
else if closest_zip = "02673" then RES_CODE = 351;
else if closest_zip = "02675" then RES_CODE = 351;
else if missing(closest_zip) then RES_CODE  = 999;
run;

data FINAL_COHORT;
   set FINAL_COHORT;
	if RES_CODE in (1,2,3,5,7,8,9,10,14,16,17,18,20,23,25,26,30,31,
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
	
	else if RES_CODE in (4,11,12,13,19,21,22,24,27,28,33,34,37,38,39,
	41,43,45,51,54,55,58,59,60,64,68,69,70,74,76,77,78,81,84,86,92,
	102,108,111,112,117,118,120,125,127,132,135,140,143,147,148,154,
	157,169,173,179,183,191,194,200,205,212,222,224,227,228,230,240,
	241,247,249,250,254,255,256,257,263,269,270,272,276,279,282,286,
	287,289,290,294,297,299,303,306,309,311,313,322,323,324,331,332,
	337,340, 343,345,349) then rural =1;
	
	else if RES_CODE in (6,104,15,29,47,53,62,63,66,89,90,91,98,106,
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
   set FINAL_COHORT;
   length INSURANCE_CAT $10.;
   if INSURANCE = 1 then INSURANCE_CAT = 'Commercial';
   else if INSURANCE = 2 then INSURANCE_CAT = 'Medicaid';
   else if INSURANCE = 3 then INSURANCE_CAT = 'Medicare';
   else INSURANCE_CAT = 'Other/Missing';
run;

data FINAL_COHORT;
   set FINAL_COHORT;
   if CONFIRMED_HCV_INDICATOR = 1 then CONFIRMED_HCV_INDICATOR = 1;
   else if CONFIRMED_HCV_INDICATOR = 0 then CONFIRMED_HCV_INDICATOR = 2;
   else if CONFIRMED_HCV_INDICATOR = . then CONFIRMED_HCV_INDICATOR = 0;
   else CONFIRMED_HCV_INDICATOR = 999;
run;

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
    
    value hcv_reportf
    	0 = "No Case Report"
    	1 = "Confirmed"
    	2 = "Probable";
    
    VALUE age_grps
		1 = '15-18'
		2 = '19-25'
		3 = '26-30'
		4 = '31-35'
		5 = '36-45';

run;

data FINAL_COHORT;
    set FINAL_COHORT;
    agegrp_num = input(agegrp, 8.);
run;

proc means data=FINAL_COHORT;
    var oud_age;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

proc sort data=FINAL_COHORT;
    by BIRTH_INDICATOR;
run;

proc means data=FINAL_COHORT;
    by BIRTH_INDICATOR;
    var oud_age;
    output out=mean_age(drop=_TYPE_ _FREQ_) mean=mean_age;
run;

%macro Table1Freqs(var, format);
    title "Table 1, Unstratified";
    proc freq data=FINAL_COHORT;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1Freqs(FINAL_RE, raceef.);
%Table1Freqs(agegrp_num, age_grps.);
%Table1Freqs(EVER_INCARCERATED, flagf.);
%Table1Freqs(HOMELESS_HISTORY_GROUP);
%Table1Freqs(LANGUAGE_SPOKEN_GROUP);
%Table1Freqs(EDUCATION_GROUP);
%Table1Freqs(HIV_DIAG, flagf.);
%Table1Freqs(CONFIRMED_HCV_INDICATOR, hcv_reportf.);
%Table1Freqs(iji_diag, flagf.);
%Table1Freqs(EVER_IDU_HCV, flagf.);
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(MENTAL_HEALTH_DIAG, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(INSURANCE_CAT);
%Table1Freqs(rural_group);

%macro Table1StrataFreqs(var, format);
    title "Table 1, Stratified by BIRTH_INDICATOR";
    
    /* Sort the dataset by BIRTH_INDICATOR */
    proc sort data=FINAL_COHORT;
        by BIRTH_INDICATOR;
    run;

    /* Run PROC FREQ with BY statement */
    proc freq data=FINAL_COHORT;
        by BIRTH_INDICATOR;
        tables &var / missing norow nopercent nocol;
        format &var &format.;
    run;
%mend;

%Table1StrataFreqs(FINAL_RE, raceef.);
%Table1StrataFreqs(agegrp_num, age_grps.);
%Table1StrataFreqs(EVER_INCARCERATED, flagf.);
%Table1StrataFreqs(HOMELESS_HISTORY_GROUP);
%Table1StrataFreqs(LANGUAGE_SPOKEN_GROUP);
%Table1StrataFreqs(EDUCATION_GROUP);
%Table1StrataFreqs(HIV_DIAG, flagf.);
%Table1StrataFreqs(CONFIRMED_HCV_INDICATOR, hcv_reportf.);
%Table1StrataFreqs(iji_diag, flagf.);
%Table1StrataFreqs(EVER_IDU_HCV, flagf.);
%Table1StrataFreqs(IDU_EVIDENCE, flagf.);
%Table1StrataFreqs(MENTAL_HEALTH_DIAG, flagf.);
%Table1StrataFreqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1StrataFreqs(INSURANCE_CAT);
%Table1StrataFreqs(rural_group);

proc sql;
    create table FINAL_COHORT as
    select 
        FINAL_COHORT.*, 
        (case when moud.ID is not null then 1 else 0 end) as EVER_MOUD
    from FINAL_COHORT
    left join 
        (select distinct ID 
         from PHDSPINE.MOUD3 
         where DATE_START_YEAR_MOUD >= 2014) as moud
    on FINAL_COHORT.ID = moud.ID;
quit;

%macro Table2MOUD(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model EVER_MOUD(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2MOUD(FINAL_RE, ref ='1');
%Table2MOUD(agegrp_num, ref ='3');
%Table2MOUD(EVER_INCARCERATED, ref ='0');
%Table2MOUD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2MOUD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2MOUD(EDUCATION_GROUP, ref ='HS or less');
%Table2MOUD(HIV_DIAG, ref ='0');
%Table2MOUD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2MOUD(IJI_DIAG, ref ='0');
%Table2MOUD(EVER_IDU_HCV, ref ='0');
%Table2MOUD(IDU_EVIDENCE, ref ='0');
%Table2MOUD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2MOUD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2MOUD(INSURANCE_CAT, ref ='Medicaid');
%Table2MOUD(rural_group, ref ='Urban');

proc sql;
    create table FINAL_COHORT as
    select 
        A.*, 
        (case when B.ID is not null then 1 else 0 end) as EVER_MOUD_CLEAN
    from FINAL_COHORT as A
    left join moud_starts as B
    on A.ID = B.ID;
quit;

%macro Table2MOUD(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model EVER_MOUD_CLEAN(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2MOUD(FINAL_RE, ref ='1');
%Table2MOUD(agegrp_num, ref ='3');
%Table2MOUD(EVER_INCARCERATED, ref ='0');
%Table2MOUD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2MOUD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2MOUD(EDUCATION_GROUP, ref ='HS or less');
%Table2MOUD(HIV_DIAG, ref ='0');
%Table2MOUD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2MOUD(IJI_DIAG, ref ='0');
%Table2MOUD(EVER_IDU_HCV, ref ='0');
%Table2MOUD(IDU_EVIDENCE, ref ='0');
%Table2MOUD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2MOUD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2MOUD(INSURANCE_CAT, ref ='Medicaid');
%Table2MOUD(rural_group, ref ='Urban');

proc sql;
    create table FINAL_COHORT as
    select 
        FINAL_COHORT.*, 
        (case when od.ID is not null then 1 else 0 end) as EVER_OD
    from FINAL_COHORT
    left join 
        (select distinct ID 
         from PHDSPINE.OVERDOSE
         where OD_YEAR >= 2014) as od
    on FINAL_COHORT.ID = od.ID;
quit;

%macro Table2OD(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model EVER_OD(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2OD(FINAL_RE, ref ='1');
%Table2OD(agegrp_num, ref ='3');
%Table2OD(EVER_INCARCERATED, ref ='0');
%Table2OD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2OD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2OD(EDUCATION_GROUP, ref ='HS or less');
%Table2OD(HIV_DIAG, ref ='0');
%Table2OD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2OD(IJI_DIAG, ref ='0');
%Table2OD(EVER_IDU_HCV, ref ='0');
%Table2OD(IDU_EVIDENCE, ref ='0');
%Table2OD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2OD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2OD(INSURANCE_CAT, ref ='Medicaid');
%Table2OD(rural_group, ref ='Urban');

proc sql;
    create table FINAL_COHORT as
    select 
        FINAL_COHORT.*, 
        (case when fod.ID is not null then 1 else 0 end) as EVER_FOD
    from FINAL_COHORT
    left join 
        (select distinct ID 
         from PHDSPINE.OVERDOSE
         where FATAL_OD_DEATH = 1) as fod
    on FINAL_COHORT.ID = fod.ID;
quit;

%macro Table2OD(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model EVER_FOD(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table2OD(FINAL_RE, ref ='1');
%Table2OD(agegrp_num, ref ='3');
%Table2OD(EVER_INCARCERATED, ref ='0');
%Table2OD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2OD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2OD(EDUCATION_GROUP, ref ='HS or less');
%Table2OD(HIV_DIAG, ref ='0');
%Table2OD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2OD(IJI_DIAG, ref ='0');
%Table2OD(EVER_IDU_HCV, ref ='0');
%Table2OD(IDU_EVIDENCE, ref ='0');
%Table2OD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2OD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2OD(INSURANCE_CAT, ref ='Medicaid');
%Table2OD(rural_group, ref ='Urban');

%macro Table26MO(var, ref=);
	title "Table 2, Crude";
	proc glimmix data=FINAL_COHORT noclprint noitprint;
	        class &var (ref=&ref);
	        model EVER_6MO(event='1') = &var / dist=binary link=logit solution oddsratio;
	run;
%mend;

%Table26MO(FINAL_RE, ref ='1');
%Table26MO(agegrp_num, ref ='3');
%Table26MO(EVER_INCARCERATED, ref ='0');
%Table26MO(HOMELESS_HISTORY_GROUP, ref ='No');
%Table26MO(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table26MO(EDUCATION_GROUP, ref ='HS or less');
%Table26MO(HIV_DIAG, ref ='0');
%Table26MO(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table26MO(IJI_DIAG, ref ='0');
%Table26MO(EVER_IDU_HCV, ref ='0');
%Table26MO(IDU_EVIDENCE, ref ='0');
%Table26MO(MENTAL_HEALTH_DIAG, ref ='0');
%Table26MO(OTHER_SUBSTANCE_USE, ref ='0');
%Table26MO(INSURANCE_CAT, ref ='Medicaid');
%Table26MO(rural_group, ref ='Urban');

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FINAL_COHORT;
QUIT;

%put Number of unique Infant IDs in FINAL_COHORT table: &num_unique_ids;

%macro ChiSquareTest(var1, var2);
    title "Chi-Square Test between &var1 and &var2";
    proc freq data=FINAL_COHORT;
        tables &var1*(&var2) / chisq nopercent nocol;
    run;
    title;
%mend;

%ChiSquareTest(EVER_INCARCERATED, HOMELESS_HISTORY_GROUP);
%ChiSquareTest(EVER_INCARCERATED, CONFIRMED_HCV_INDICATOR);
%ChiSquareTest(EVER_INCARCERATED, IDU_EVIDENCE);
%ChiSquareTest(EVER_INCARCERATED, OTHER_SUBSTANCE_USE);
%ChiSquareTest(HOMELESS_HISTORY_GROUP, CONFIRMED_HCV_INDICATOR);
%ChiSquareTest(HOMELESS_HISTORY_GROUP, IDU_EVIDENCE);
%ChiSquareTest(HOMELESS_HISTORY_GROUP, OTHER_SUBSTANCE_USE);
%ChiSquareTest(CONFIRMED_HCV_INDICATOR, IDU_EVIDENCE);
%ChiSquareTest(CONFIRMED_HCV_INDICATOR, OTHER_SUBSTANCE_USE);
%ChiSquareTest(IDU_EVIDENCE, OTHER_SUBSTANCE_USE);

/*===============================*/
/*  Part 4: Calculate MOUD Rates */
/*===============================*/

/*  Goal:
	Characterize and model the differecnes between pregnant and non-pregnant women's 
	initiation and cessation of opioid use disorder treatment (MOUD) episodes

    This portion of the code processes the `PHDSPINE.MOUD3` dataset by first sorting and 
    creating a unique `episode_id` for each treatment episode based on treatment start and end dates, 
    with episodes being flagged when a significant gap is detected between consecutive treatment episodes. 
    It also merges treatment episode data, calculates start and end months/years, removes short treatment 
    episodes based on the specified leniency, and eliminates any overlapping episodes. The dataset is then 
    cleaned for missing values and sorted for further analysis */

/*====================*/
/* 1. Identifying Missing IDs */
/*====================*/
/* This step identifies IDs in the FINAL_COHORT that do not have matching records in the cleaned
   `moud` dataset. The result is saved in the `missing_ids` table. */

proc sql;
   create table missing_ids as
   select ID
   from FINAL_COHORT
   where EVER_MOUD_CLEAN = 0;
quit;

/*====================*/
/* 2. Creating Two MOUD Datasets */
/*====================*/
/* This dataset contains all records from the cleaned MOUD dataset, which will be used for further analysis of MOUD cessation
because you are only eligble for MOUD cessation if you are currently taking MOUD */

DATA moud_duration;
    SET moud_demo;
RUN;

/* This step makes an expanded `moud_full` dataset by taking the cleaned moud dataset and creating additional observations 
for those in the OUD cohort that did not have a clean MOUD episode. This dataset will be used to assess MOUD initiation
because all with OUD contiribute eligblie person-time toward MOUD initation */

DATA moud_full;
    SET moud_demo;
RUN;

proc sql;
   insert into moud_full (ID)
   select ID
   from missing_ids;
quit;

/*=====================================*/
/* 3. Prepare Pregnancy Tables         */
/*=====================================*/
/* This portion processes birth and infant data to generate monthly pregnancy and postpartum period flags for each birth. It first extracts relevant birth records from `PHDBIRTH.BIRTH_MOM` based on a specified year range and 
retrieves gestational age from `PHDBIRTH.BIRTH_INFANT`, merging them using `BIRTH_LINK_ID`. The script then estimates pregnancy duration based on gestational age and determines the start and end months of pregnancy. 
It iterates through months to flag each as part of the pregnancy period, then defines postpartum periods (6, 12, 18, and 24 months after birth) with specific flags. The dataset is sorted by mother ID, year, and month, 
keeping only the earliest flag for each month. Finally, the script extracts the start and end years from a macro variable and generates datasets for months (1–12) and the range of years within the study period.
Thus, the outcome is a long table, where each birth has 108 rows (one row per month Jan 2014-Dec 2022) that is flagged either pregnant or post-partum. */

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
	
    keep MATERNAL_ID pregnancy_start_month pregnancy_start_year month year flag;
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

%let start_year=%scan(%substr(&year,2,%length(&year)-2),1,':');
%let end_year=%scan(%substr(&year,2,%length(&year)-2),2,':');

DATA months; DO month = 1 to 12; OUTPUT; END; RUN;

DATA years; DO year = &start_year to &end_year; OUTPUT; END; RUN;

/*=====================================*/
/* 4. Macro for flag generation       */
/*=====================================*/
/* This section of the code defines a macro that merges creates the cartesian produce of the input moud datasets for Jan 2014-Dec 2022.
It merges demographic data from `PHDSPINE.DEMO` to the long dataset, and creates a table that flags the presence of treatment 
episodes across a specified range of months and years. It also merges flags for pregnancy and post-partum periods. The final output includes flags for each month indicating 
the stage of pregnancy or post-partum status, an onoging MOUD episode, an MOUD initation, or an MOUD cessation event for each individual. 
The code potion is wrapped in a macro so that two datasets, moud_init and moud_duration, can be run sequentially through the same data manipulation steps. Dataset moud_init includes
all IDs in the Maternal OUD cohort (to analyze MOUD initation outcomes since all with OUD are eligible) while dataset moud_duration 
is a subset of only those that had an MOUD episode (to analyze MOUD duration and cessation since being on MOUD is required to eligiblity) */

%macro moud_table_creation(input_dataset);

    /* Create the cartesian product of our input dataset, months, and years to represent every month in our study period */
    PROC SQL;
        CREATE TABLE moud_table AS
        SELECT * FROM &input_dataset, months, years;
    QUIT;

	/* Pull in pregnancy and post-partum flags and pregnancy date information */
	proc sql;
	    create table moud_table as
	    select a.*, 
	           case when b.flag is not null then b.flag 
	                else 9999 end as preg_flag,
	           case when b.pregnancy_start_month is not null then b.pregnancy_start_month 
	                else . end as pregnancy_start_month,
	           case when b.pregnancy_start_year is not null then b.pregnancy_start_year 
	                else . end as pregnancy_start_year
	    from moud_table a
	    left join pregnancy_flags b
	    on a.ID = b.ID 
	       and a.month = b.month 
	       and a.year = b.year;
	quit;
	
	proc sort data=moud_table;
	by ID year month;
	run;
	
    proc sql;
        create table pregnancy_summary as 
        select ID, 
            min(pregnancy_start_month) as first_preg_month, 
            min(pregnancy_start_year) as first_preg_year
        from pregnancy_flags
        group by ID;
    quit;

    proc sql;
        create table moud_table as 
        select a.*, 
            coalesce(b.first_preg_month, .) as first_preg_month, 
            coalesce(b.first_preg_year, .) as first_preg_year,
            case when b.ID is not null then 1 else 0 end as has_pregnancy
        from moud_table a
        left join pregnancy_summary b
        on a.ID = b.ID;
    quit;
	
	/* Create a summary dataset with a flag indicating whether a month overlaps with the MOUD episode */
    data moud_summary;
        set moud_table;
        start_month_year = mdy(new_start_month, 1, new_start_year);
        end_month_year = mdy(new_end_month, 1, new_end_year);
        target_month_year = mdy(month, 1, year);

        if start_month_year <= target_month_year <= end_month_year then
            moud_flag = 1;
        else
            moud_flag = 0;
    run;

	/* Create a dataset with post-treatment overlap flag */
	data moud_spine_posttxt;
	    set moud_table;
	
	    start_month_year = mdy(new_start_month, 1, new_start_year);
	    end_month_year = mdy(new_end_month, 1, new_end_year);
	    target_month_year = mdy(month, 1, year);
	
	    if target_month_year = end_month_year then
	        posttxt_flag = 1;
	    else
	        posttxt_flag = 0;
	run;

    proc sort data=moud_summary;
        by episode_id year month;
    run;

    /* Create moud initiation flag */
    data moud_table;
        set moud_summary;
        by episode_id year month;

        retain moud_init lag_moud_flag;
        
        if first.episode_id then do;
            moud_init = 0;
            lag_moud_flag = .;
        end;

        if moud_flag = 1 then do;
            if lag_moud_flag = 0 or lag_moud_flag = . then moud_init = 1;
            else if lag_moud_flag = 1 then moud_init = 0;
        end;

        if moud_flag = 0 then moud_init = 0;

        lag_moud_flag = moud_flag;

    run;
    
	proc sort data=moud_table;
	    by episode_id year month;
	run;
	
	data moud_spine_preg;
	    set moud_table;
	    by episode_id year month;
	
	    moud_start_month_year = mdy(new_start_month, 1, new_start_year);
	    pregnancy_start_month_year = mdy(pregnancy_start_month, 1, pregnancy_start_year);
	    first_preg_start_month_year = mdy(first_preg_month, 1, first_preg_year);

        if first.episode_id then do;
	        if moud_init ne 1 then moud_start_group = .; 
	    end;
	
	    if moud_init = 1 then do;
	        if missing(pregnancy_start_month_year) and has_pregnancy = 1 then do;
	            pregnancy_start_month_year = first_preg_start_month_year;
	        end;
	
	        if moud_start_month_year < pregnancy_start_month_year then 
	            moud_start_group = 1; /* MOUD initiation before pregnancy */
	        else if preg_flag = 1 then 
	            moud_start_group = 2; /* MOUD initiation during pregnancy */
	        else if moud_start_month_year > pregnancy_start_month_year and preg_flag ne 1 then
	            moud_start_group = 3; /* MOUD initiation after pregnancy */
	        else
	            moud_start_group = .; 
	    end;
	    else moud_start_group = .;
	
	    keep episode_id ID year month moud_init preg_flag moud_start_group pregnancy_start_month pregnancy_start_year has_pregnancy first_preg_month first_preg_year;
	run;
	
	proc sort data=moud_table;
	by ID year month;
	run;	
	
    /* Create moud duration variable */
	proc sql;
	    create table moud_table as
	    select a.*, 
	           case 
	               when a.moud_flag = 0 then 0
	               else b.moud_duration
	           end as moud_duration
	    from moud_table as a
	    left join (
	        select EPISODE_ID, sum(moud_flag) as moud_duration
	        from moud_table
	        group by EPISODE_ID
	    ) as b
	    on a.EPISODE_ID = b.EPISODE_ID;
	quit;

    title "MOUD Duration Sum Stats";
    proc sql;
        create table duration_means as
        SELECT distinct episode_id, moud_duration, preg_flag
        from moud_table
        where moud_duration is not missing and moud_duration ne 0;
	quit;

	proc means data=duration_means sum mean median std min max q1 q3;
	    var moud_duration;
	run;
	
	proc sort data=duration_means;
	    by preg_flag;
	run;
	
	proc means data=duration_means sum mean median std min max q1 q3;
	    by preg_flag;
	    var moud_duration;
	run;
    title;
    
    /* Create moud cessation variable */
	data MOUD_TABLE;
	    set MOUD_TABLE;
	    if new_end_month = MONTH and new_start_year = YEAR then moud_cessation = 1;
	    else moud_cessation = 0;
	run;

    proc sort data=moud_table;
    	by episode_id year month;
	run;
	
	data check_overlap;
	    set moud_table;
	    by episode_id year month;
	    
	    retain ongoing_episode count;
	    
	    if first.episode_id then ongoing_episode = 0;
	
	    if moud_init = 1 then do;
	        if ongoing_episode = 1 then count + 1;
	        ongoing_episode = 1;
	    end;
	    
	    if moud_cessation = 1 then ongoing_episode = 0;
	
	run;
	
	title "Check Overlap in MOUD starts";
	proc means data=check_overlap max;
	    var count;
	run;
	title;

	data prepared_data;
    	set moud_table;
    	drop episode_id;
	run;
	
	data PREPARED_DATA;
		set PREPARED_DATA;
		
		/* Create a unique time index */
		time_index = (year - 2014) * 12 + month;
		   
		if preg_flag = 1 then group = 1; /* Pregnant */
		else if preg_flag = 2 then group = 2; /* 0-6 months post-partum */
		else if preg_flag = 3 then group = 3; /* 7-12 months post-partum */
		else if preg_flag = 4 then group = 4; /* 13-18 months post-partum */
		else if preg_flag = 5 then group = 4; /* 19-24 months post-partum */
		else if preg_flag = 9999 then group = 0; /* Non-pregnant */
	run;
	
	/* Reduce from EPISODE_LEVEL to PERSON_LEVEL */
	proc sql;
    create table PREPARED_DATA as
    select distinct
        ID,
        month,
        year,
        group,
        max(moud_flag) as moud_flag,
        max(moud_init) as moud_init,
        max(moud_duration) as moud_duration,
        max(moud_cessation) as moud_cessation,
        min(preg_flag) as preg_flag
    from PREPARED_DATA
    group by ID, month, year;
	quit;

    /* Censor on death and assess event temporality with regard to death date (i.e. claims processed after death)  */
	proc sql;
	   create table deaths_filtered as
	   select 
	       ID, 
	       YEAR_DEATH, 
	       MONTH_DEATH
	   from PHDDEATH.DEATH
	   where YEAR_DEATH in &year;
	quit;
	
	proc sort data=PREPARED_DATA;
	by ID year month;
	run;

    proc sql;
        create table PREPARED_DATA as
        select a.*, 
            b.YEAR_DEATH, 
            b.MONTH_DEATH,
            case 
                when b.YEAR_DEATH = a.year and b.MONTH_DEATH = a.month then 1
                else 0
            end as death_flag
        from PREPARED_DATA as a
        left join deaths_filtered as b
        on a.ID = b.ID;
    quit;

    proc sql;
    create table death_events as 
    select ID, min(year*12 + month) as death_period
    from PREPARED_DATA
    where death_flag = 1
    group by ID;
	quit;
	
	proc sql;
	    create table post_death_counts as
	    select 
        	sum(moud_init) as moud_init_before_case
	    from PREPARED_DATA as a
	    inner join death_events as d
	    on a.ID = d.ID
	    where (a.year*12 + a.month) > d.death_period;
	quit;
	
	title "Counts of Events Occurring After Death";
	proc print data=post_death_counts noobs;
	run;
	title;
	
    data PREPARED_DATA;
        set PREPARED_DATA;
        retain death_flag_forward 0;
        by ID;

        if first.ID then death_flag_forward = 0;
        if death_flag = 1 then death_flag_forward = 1;

        if death_flag_forward = 1 and (year > YEAR_DEATH or (year = YEAR_DEATH and month > MONTH_DEATH)) then delete;

        drop death_flag_forward;
    run;

	/* Add covariates for rate stratification  */
	PROC SQL;
    CREATE TABLE PREPARED_DATA AS
    SELECT a.*, 
           demographics.FINAL_RE, 
           demographics.FINAL_SEX,
           demographics.EDUCATION,
           demographics.EVER_INCARCERATED,
           demographics.FOREIGN_BORN,
           demographics.HOMELESS_EVER,
           demographics.YOB
    FROM PREPARED_DATA AS a
    LEFT JOIN PHDSPINE.DEMO AS demographics 
    ON a.ID = demographics.ID;
	QUIT;

    data PREPARED_DATA;
    length HOMELESS_HISTORY_GROUP $10;
    set PREPARED_DATA;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
    run;
	
	data PREPARED_DATA;
	    set PREPARED_DATA;
	    where FINAL_SEX = 2;
	run;

    PROC SQL;
        CREATE TABLE PREPARED_DATA AS
        SELECT a.*, 
               cov.IJI_DIAG,
               cov.OTHER_SUBSTANCE_USE,
               cov.IDU_EVIDENCE
        FROM PREPARED_DATA AS a
        LEFT JOIN FINAL_COHORT AS cov 
        ON a.ID = cov.ID;
    QUIT;
	
	PROC SQL;
        CREATE TABLE PREPARED_DATA AS
        SELECT a.*, 
               cov.agegrp
        FROM PREPARED_DATA AS a
        LEFT JOIN oud_distinct AS cov 
        ON a.ID = cov.ID;
    QUIT;
	
%mend;

/*=================================================================*/
/* 5. MOUD Duration Stats and Cessation Rates by Pregnancy Status */
/*=================================================================*/
/* This section creates summary tables (`PERSON_TIME` and `PERIOD_SUMMARY`) to calculate the number of eligible cessation periods and actual MOUD cessation events for each individual. 
These tables are merged with demographic data, including variables such as race, sex, education, incarceration history, and homelessness status. Additional variables are created, including an indicator for injection drug use (`IDU_EVIDENCE`) and age groups. 
Next, generates summary tables and calculates MOUD cessation rates overall and by stratified groups, providing confidence intervals for cessation rates. The macro `%calculate_rates` automates the stratified rate calculations across multiple demographic factors. */

%moud_table_creation(moud_duration);

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        sum(case when moud_flag = 1 then 1 else 0 end) as eligble_cessation
    from PREPARED_DATA
    group by ID, group;
quit;

proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          group,
          sum(moud_cessation) as moud_stops
   from PREPARED_DATA
   group by ID, group;
quit;
	
proc sort data=PERSON_TIME;
    by ID group;
run;
	
proc sort data=PERIOD_SUMMARY;
    by ID group;
run;
	
data PERIOD_SUMMARY_FINAL;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID group;
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          demographics.FINAL_RE, 
          demographics.FINAL_SEX,
          demographics.EDUCATION,
          demographics.EVER_INCARCERATED,
          demographics.FOREIGN_BORN,
          demographics.HOMELESS_EVER,
          demographics.YOB
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN PHDSPINE.DEMO AS demographics 
   ON a.ID = demographics.ID;
QUIT;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT, 
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

/* ods exclude CensoredSummary;
title "Cox Proportional Hazard by Pregnancy Group";
proc phreg data=PREPARED_DATA;
   class group (ref="0");
   model moud_duration*moud_cessation(1) = group;
   strata ID;
   hazardratio group / diff=ref;
   
   assess ph;
   
   output out=surv_data survival=survival;
run;

%macro cox_prop(group_by_vars, mytitle); 
ods exclude CensoredSummary;
title &mytitle;

proc phreg data=PREPARED_DATA;
   class group (ref="0") &group_by_vars;
   model moud_duration*moud_cessation(1) = group &group_by_vars;
   strata ID;
   hazardratio group / diff=ref;

   assess ph;
   
   output out=surv_data survival=survival;
run;
%mend cox_prop;

%cox_prop(age_grp, "Cox Proportional Hazard by Pregnancy Group, Stratified by Age");
%cox_prop(FINAL_RE, "Cox Proportional Hazard by Pregnancy Group, Stratified by FINAL_RE");
%cox_prop(IDU_EVIDENCE, "Cox Proportional Hazard by Pregnancy Group, Stratified by IDU_EVIDENCE");

ods select all; */

proc sql;
    create table summed_data as
    select 
        ID,
        sum(eligble_cessation) as total_person_time_cessation
    from 
        PERIOD_SUMMARY_FINAL
    group by 
        ID;
quit;

title "Summary statistics for Overall Follow-up Time";
proc means data=summed_data mean median std min max q1 q3;
    var total_person_time_cessation;
run;

title 'Moud Cessation, Overall';
proc sql;
    select 
        sum(moud_stops) as moud_stops,
        sum(eligble_cessation) as eligble_cessation
    from PERIOD_SUMMARY_FINAL
quit;

title 'Moud Cessation by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        sum(moud_stops) as moud_stops,
        sum(eligble_cessation) as eligble_cessation,
        calculated moud_stops / calculated eligble_cessation as moud_stops_rate format=8.4,
        (calculated moud_stops - 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_lower format=8.4,
        (calculated moud_stops + 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_upper format=8.4
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
        sum(moud_stops) as moud_stops,
        sum(eligble_cessation) as eligble_cessation,
        calculated moud_stops / calculated eligble_cessation as moud_stops_rate format=8.4,
        (calculated moud_stops - 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_lower format=8.4,
        (calculated moud_stops + 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Moud Cessation by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Moud Cessation by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Moud Cessation by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Moud Cessation by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Moud Cessation by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Moud Cessation by Pregnancy Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Moud Cessation by Pregnancy Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Moud Cessation by Pregnancy Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Moud Cessation by Pregnancy Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Moud Cessation by Pregnancy Group, Stratified by rural_group');
title;

/*=================================================================*/
/* 6. MOUD Duration Stats and Cessation Rates by MOUD Start Time  */
/*=================================================================*/
/* This section does the same thing as section 11 but rather than pregnancy status as the group of analysis, it uses MOUD start time relative to pregnancy as the group of analysis (i.e. MOUD start before, during, or after pregnancy)
So, it begins with summarized MOUD start group information, merging this with a prepared dataset that tracks individuals by ID, month, and year. The script then calculates person-time eligible for cessation and summarizes cessation events by MOUD start group. 
Demographic and clinical data, including homelessness history, incarceration, birth indicators, and HCV status, are integrated into the final dataset. Additional derived variables, such as age and an indicator for injection drug use (IDU) evidence, are created. 
Next, generate statistical summaries of MOUD cessation rates overall and stratified by key demographic and clinical characteristics using a macro for automated subgroup analysis. */

proc sql;
    create table moud_spine_preg as
    select distinct
        ID,
        month,
        year,
        max(moud_start_group) as moud_start_group
    from moud_spine_preg
    group by ID, month, year;
quit;

proc sql;
    create table PREPARED_DATA as
    select a.*, 
           coalesce(b.moud_start_group, 0) as moud_start_group
    from PREPARED_DATA a
    left join moud_spine_preg b 
    on a.ID = b.ID and a.month = b.month and a.year = b.year;
quit;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        moud_start_group,
        sum(case when moud_flag = 1 then 1 else 0 end) as eligble_cessation
    from PREPARED_DATA
    group by ID, moud_start_group;
quit;

proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          moud_start_group,
          sum(moud_cessation) as moud_stops
   from PREPARED_DATA
   group by ID, moud_start_group;
quit;
	
proc sort data=PERSON_TIME;
    by ID moud_start_group;
run;
	
proc sort data=PERIOD_SUMMARY;
    by ID moud_start_group;
run;
	
data PERIOD_SUMMARY_FINAL;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID moud_start_group;
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          demographics.FINAL_RE, 
          demographics.FINAL_SEX,
          demographics.EDUCATION,
          demographics.EVER_INCARCERATED,
          demographics.FOREIGN_BORN,
          demographics.HOMELESS_EVER,
          demographics.YOB
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN PHDSPINE.DEMO AS demographics 
   ON a.ID = demographics.ID;
QUIT;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT,
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select a.*, b.BIRTH_INDICATOR
    from PERIOD_SUMMARY_FINAL a
    left join births b
    on a.ID = b.ID;
quit;

PROC SQL;
	CREATE TABLE PERIOD_SUMMARY_FINAL AS
	SELECT DISTINCT *
	FROM PERIOD_SUMMARY_FINAL
	WHERE BIRTH_INDICATOR = 1;
QUIT;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

title 'Moud Cessation by moud_start_group Group, Overall';
proc sql;
    select 
        moud_start_group,
        count(*) as total_n,
        sum(moud_stops) as moud_stops,
        sum(eligble_cessation) as eligble_cessation,
        calculated moud_stops / calculated eligble_cessation as moud_stops_rate format=8.4,
        (calculated moud_stops - 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_lower format=8.4,
        (calculated moud_stops + 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by moud_start_group;
quit;

%macro calculate_rates(group_by_vars, mytitle);
title &mytitle;
proc sql;
    select 
        moud_start_group,
        &group_by_vars,
        count(*) as total_n,
        sum(moud_stops) as moud_stops,
        sum(eligble_cessation) as eligble_cessation,
        calculated moud_stops / calculated eligble_cessation as moud_stops_rate format=8.4,
        (calculated moud_stops - 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_lower format=8.4,
        (calculated moud_stops + 1.96 * sqrt(calculated moud_stops)) / calculated eligble_cessation as moud_stops_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by moud_start_group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Moud Cessation by moud_start_group Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Moud Cessation by moud_start_group Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Moud Cessation by moud_start_group Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Moud Cessation by moud_start_group Group, Stratified by HOMELESS_HISTORY');
%calculate_rates(EVER_INCARCERATED, 'Moud Cessation by moud_start_group Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Moud Cessation by moud_start_group Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Moud Cessation by moud_start_group Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Moud Cessation by moud_start_group Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Moud Cessation by moud_start_group Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Moud Cessation by moud_start_group Group, Stratified by rural_group');
title;

/*============================================*/
/* 7. MOUD Primary and Secondary Initation   */
/*============================================*/
/* This section again repeats the previous sections on a different dataset. MOUD_FULL contains all IDs from the cohort (both those who did and did not have MOUD episodes) compared to MOUD_DURATION that only contained IDs that had an episode of MOUD.
This section begins by merging OUD-related information into a prepared dataset and calculates the earliest OUD case report period for each individual. It then determines the number of events (e.g., MOUD initiation) occurring before the case report. 
The dataset is further refined by filtering records based on time criteria and calculating eligibility and censoring variables related to MOUD initiation and reinitiation. 
The code then aggregates person-time data for MOUD initiation and reinitiation, merges demographic data, and categorizes homelessness history. 
It also identifies individuals with IDU history based on available datasets. Age groups are assigned, and overall follow-up time statistics are calculated. 
Finally, it generates summary statistics and stratified analyses of MOUD initiation and reinitiation rates by key demographic variables (e.g., age, race, education, homelessness, incarceration, foreign-born status, and IDU history). 
The analysis uses a macro to generate stratified tables efficiently. */

%moud_table_creation(moud_full); 

proc sql;
    create table PREPARED_DATA as
    select PREPARED_DATA.*,
           cov.oud_year,
           cov.oud_month
    from PREPARED_DATA
    left join oud_preg as cov
    on PREPARED_DATA.ID = cov.ID;
quit;

proc sql;
    create table case_report_events as 
    select ID, min(OUD_YEAR*12 + OUD_MONTH) as case_report_period
    from PREPARED_DATA
    group by ID;
quit;

proc sql;
    create table pre_case_report_counts as
    select 
        sum(moud_init) as moud_init_before_case
    from PREPARED_DATA as a
    inner join case_report_events as c
    on a.ID = c.ID
    where (a.year*12 + a.month) < c.case_report_period;
quit;

title "Counts of Events Occurring Before Case Report";
proc print data=pre_case_report_counts noobs;
run;
title;

proc sql;
    create table PREPARED_DATA as
    select *
    from PREPARED_DATA
    where (YEAR > oud_year) 
        or (YEAR = oud_year and MONTH >= oud_month)
    order by ID, YEAR, MONTH;
quit;

data PREPARED_DATA; 
    set PREPARED_DATA;
    by ID year month;

    retain censor_init eligible_init moud_reinit eligible_reinit moud_primaryinit flag_reset_reinit;

    if first.ID then do;
        eligible_init = 1; 
        censor_init = 0;
        moud_reinit = 0; 
        eligible_reinit = 0;  
        moud_primaryinit = 0;
        flag_reset_reinit = 0;
    end;

    /* Reset eligible_reinit if the previous month had a flagged reinitiation */
    if flag_reset_reinit = 1 then do;
        eligible_reinit = 0;
        flag_reset_reinit = 0; /* Reset the flag after applying */
    end;

    /* Flag primary initiation only once for the first instance of moud_init = 1 */
    if moud_init = 1 and eligible_init = 1 then do;
        moud_primaryinit = 1;  /* Set primary initiation flag */
        censor_init = 1;       /* Mark as censored after primary initiation */
    end;
    
    else if moud_init = 0 then moud_primaryinit = 0;
    
    if censor_init = 1 and not (moud_init = 1) then do;
        eligible_init = 0;     /* Prevent further flagging for primary init */
    end;
    
    /* After moud_cessation = 1, mark as eligible for re-initiation */
    if moud_cessation = 1 then eligible_reinit = 1;

    /* Flag re-initiation only if eligible_reinit = 1 and moud_init = 1 occurs again */
    if moud_init = 1 and eligible_reinit = 1 and moud_primaryinit = 0 then do;
        moud_reinit = 1;       /* Set re-initiation flag */
        flag_reset_reinit = 1; /* Set flag to reset eligible_reinit next month */
    end;
    
    else if moud_init = 0 then moud_reinit = 0;

    if moud_cessation = 1 and moud_reinit = 1 then do;
	    eligible_reinit = 1;
	    flag_reset_reinit = 0;
    end;

run;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        sum(eligible_init+eligible_reinit) as total_eligible_init,
        sum(eligible_init) as eligible_init,
        sum(eligible_reinit) as eligible_reinit
    from PREPARED_DATA
    group by ID, group;
quit;
	
proc sql;
    create table PERIOD_SUMMARY as
    select ID,
           group,
           sum(moud_init) as moud_init,
           sum(moud_primaryinit) as moud_primaryinit,
           sum(moud_reinit) as moud_reinit
    from PREPARED_DATA
    group by ID, group;
quit;
	
proc sort data=PERSON_TIME;
    by ID group;
run;
	
proc sort data=PERIOD_SUMMARY;
    by ID group;
run;
	
data PERIOD_SUMMARY_FINAL;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID group;
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          demographics.FINAL_RE, 
          demographics.FINAL_SEX,
          demographics.EDUCATION,
          demographics.EVER_INCARCERATED,
          demographics.FOREIGN_BORN,
          demographics.HOMELESS_EVER,
          demographics.YOB
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN PHDSPINE.DEMO AS demographics 
   ON a.ID = demographics.ID;
QUIT;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT,
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

proc sql;
    create table summed_data as
    select 
        ID,
        sum(total_eligible_init) as total_eligible_init,
        sum(eligible_init) as total_person_time_init,
        sum(eligible_reinit) as total_person_time_reinit
    from 
        PERIOD_SUMMARY_FINAL
    group by 
        ID;
quit;

title "Summary statistics for Overall Follow-up Time";
proc means data=summed_data mean median std min max q1 q3;
    var total_eligible_init total_person_time_init total_person_time_reinit;
run;

title 'Moud Initiation and Reinitiation, Overall';
proc sql;
    select
        sum(moud_init) as moud_init,
        sum(total_eligible_init) as total_eligible_init,
        sum(moud_primaryinit) as moud_primaryinit,
        sum(eligible_init) as eligible_init,
        sum(moud_reinit) as moud_reinit,
        sum(eligible_reinit) as eligible_reinit
    from PERIOD_SUMMARY_FINAL;
quit;
title;

title 'Moud Initiation by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        
        sum(moud_init) as moud_init,
        sum(total_eligible_init) as total_eligible_init,
        calculated moud_init / calculated total_eligible_init as moud_init_rate format=8.4,
        (calculated moud_init - 1.96 * sqrt(calculated moud_init)) / calculated total_eligible_init as moud_init_rate_lower format=8.4,
        (calculated moud_init + 1.96 * sqrt(calculated moud_init)) / calculated total_eligible_init as moud_init_rate_upper format=8.4,


        sum(moud_primaryinit) as moud_primaryinit,
        sum(eligible_init) as eligible_init,
        calculated moud_primaryinit / calculated eligible_init as moud_primaryinit_rate format=8.4,
        (calculated moud_primaryinit - 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_lower format=8.4,
        (calculated moud_primaryinit + 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_upper format=8.4,
        
        sum(moud_reinit) as moud_reinit,
        sum(eligible_reinit) as eligible_reinit,
        calculated moud_reinit / calculated eligible_reinit as moud_reinit_rate format=8.4,
        (calculated moud_reinit - 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_reinit as moud_reinit_rate_lower format=8.4,
        (calculated moud_reinit + 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_reinit as moud_reinit_rate_upper format=8.4
        
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
        
        sum(moud_init) as moud_init,
        sum(total_eligible_init) as total_eligible_init,
        calculated moud_init / calculated total_eligible_init as moud_init_rate format=8.4,
        (calculated moud_init - 1.96 * sqrt(calculated moud_init)) / calculated total_eligible_init as moud_init_rate_lower format=8.4,
        (calculated moud_init + 1.96 * sqrt(calculated moud_init)) / calculated total_eligible_init as moud_init_rate_upper format=8.4,


        sum(moud_primaryinit) as moud_primaryinit,
        sum(eligible_init) as eligible_init,
        calculated moud_primaryinit / calculated eligible_init as moud_primaryinit_rate format=8.4,
        (calculated moud_primaryinit - 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_lower format=8.4,
        (calculated moud_primaryinit + 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_upper format=8.4,
        
        sum(moud_reinit) as moud_reinit,
        sum(eligible_reinit) as eligible_reinit,
        calculated moud_reinit / calculated eligible_reinit as moud_reinit_rate format=8.4,
        (calculated moud_reinit - 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_reinit as moud_reinit_rate_lower format=8.4,
        (calculated moud_reinit + 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_reinit as moud_reinit_rate_upper format=8.4
        
    from PERIOD_SUMMARY_FINAL
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by rural_group');
title;

/*===================================*/
/* Part 5: Calculate Overdose Rates  */
/*===================================*/
/* This portion of the code processes the `PHDSPINE.OVERDOSE` dataset by first sorting and 
creating a unique `episode_id` for each overdose episode. Missing IDs from the moud dataset are identified and added 
with placeholder episode_id values to the overdose data (to recpatilate the structure of the moud_init dataset). 
Demographic information is merged with the overdose dataset and filtered filtered to include only female subjects. 
The overdose data is sorted and merged with month and year flags to create the final cartesian overdose table, 
combining relevant flags such as pregnancy_flags, moud_flag, and posttxt_flag. */

/*==========================*/
/* 1. Prepare Overdose Data */
/*==========================*/
/* This section prepares the overdose data by selecting relevant variables from the source dataset 
   and ensures that only the necessary columns are retained. The dataset is then sorted by ID and overdose date (OD_DATE) to organize the data for further analysis. */

DATA overdose;
    SET PHDSPINE.OVERDOSE;
    KEEP ID OD_MONTH OD_YEAR OD_DATE FATAL_OD_DEATH OD_COUNT;
RUN;

PROC SORT data=overdose; 
    BY ID OD_DATE;
RUN;

/*===========================*/
/* 2. Create Episode Numbers */
/*===========================*/
/* This step assigns an episode number to each overdose event for each individual. The episode number is initialized to 1 for the first record and incremented for subsequent records within the same ID. 
   A new variable, 'episode_id', is created by concatenating the individual ID and the episode number to uniquely identify each episode. */

DATA overdose;
    SET overdose;
    by ID OD_DATE; 
    retain episode_num;

    if first.ID then episode_num = 1; 
    else episode_num + 1;

    episode_id = catx("_", ID, episode_num);
    
    drop episode_num;
RUN;

PROC SORT data=overdose; 
    BY EPISODE_ID;
RUN;

/*==========================*/
/* 3. Filter by Year and ID */
/*==========================*/
/* Filter the overdose data to keep only records from our cohort and from the year 2014 and onwards */

data overdose;
    set overdose;
    where OD_YEAR >= 2014;
run;

PROC SQL;
    CREATE TABLE overdose AS 
    SELECT * 
    FROM overdose
    WHERE ID IN (SELECT DISTINCT ID FROM oud_distinct);
QUIT;

/*======================================*/
/* 4. Identify Missing IDs in MOUD Data */
/*======================================*/
/* This SQL procedure identifies individuals (IDs) who appear in the pregnancy data (oud_preg) but do not have corresponding entries in the MOUD data */

proc sql;
   create table missing_ids as
   select a.ID
   from oud_preg as a
   where not exists (select 1 from overdose as b where a.ID = b.ID);
quit;

/*=========================================*/
/* 5. Merge Missing IDs into Overdose Data */
/*=========================================*/
/* The next step merges the missing IDs into the overdose data, where a placeholder value (".") is assigned to the episode_id for these missing records. 
   This ensures that all IDs are accounted for in the dataset, even if no MOUD data is available. */

DATA overdose_full;
    SET overdose; 
RUN;

proc sql;
   insert into overdose_full (ID, episode_id)
   select ID, "." 
   from missing_ids;
quit;

/*===========================*/
/* 8. Sort Data for Analysis */
/*===========================*/
/* Sorting the overdose dataset by ID, OD_YEAR, and OD_MONTH to facilitate time-series analysis and ensure chronological order of overdose events. */

PROC SORT DATA=overdose_full;
by ID OD_YEAR OD_MONTH;
run;

/*====================*/
/* 9. Create OD Table */
/*====================*/
/* This SQL procedure creates an initial table, combining the overdose data with month and year information. The table is used to track overdose flags for each month/year combination. */

PROC SQL;
    CREATE TABLE od_table AS
    SELECT * FROM overdose_full, months, years;
QUIT;

/*==============================================*/
/* 10. Flag Overdoses by Month-Year Combination */
/*==============================================*/
/* This step creates an "od_flag" variable indicating whether a particular overdose event matches a given month and year. The flag is set to 1 if there's a match, otherwise 0. */

data od_table;
    set od_table;
    if OD_MONTH = month and OD_YEAR = year then od_flag = 1;
    else od_flag = 0;
run;

/*==========================*/
/* 11. Flag Fatal Overdoses */
/*==========================*/
/* This step creates a "fod_flag" variable to flag fatal overdoses. The flag is set to 1 for fatal overdoses (FATAL_OD_DEATH = 1) and 0 otherwise.
Observations are censored after their fatal overdose and then explore whether overdoses were flagged after death date.
Lastly, forward censor on earliest date of evidence of OUD to begin eligble period. */

data od_table;
    set od_table;
    if OD_MONTH = month and OD_YEAR = year and FATAL_OD_DEATH = 1 then fod_flag = 1;
    else fod_flag = 0;
run;

proc sort data=od_table;
by ID year month;
run;

data od_table;
    set od_table;
    by ID;
    
    retain censor_fod 0 fod_month od_after_fod_count 0;
   
    if first.ID then do;
      censor_fod = 0;
      fod_month = .; 
      od_after_fod_count = 0; 
    end;
    

    if fod_flag = 1 then do;
        censor_fod = 1;
        fod_month = month; 
    end; 
    

    if censor_fod = 1 and od_flag = 1 and month > fod_month then od_after_fod_count + 1;

run;

proc sql;
    create table max_counts as
    select id, max(od_after_fod_count) as od_after_fod_max
    from od_table
    group by id;
quit;

proc summary data=max_counts;
    var od_after_fod_max;
    output out=sum_counts (drop=_type_ _freq_) sum=od_after_fod_max;
run;

proc print data=sum_counts;
run;

data od_table;
    set od_table;
    by ID;
    
    if censor_fod = 1 and fod_flag = 0 then delete;

run;

proc sql;
    create table od_table as
    select od_table.*,
           cov.oud_year,
           cov.oud_month
    from od_table
    left join oud_preg as cov
    on od_table.ID = cov.ID;
quit;

proc sql;
    create table case_report_events as 
    select ID, min(OUD_YEAR*12 + OUD_MONTH) as case_report_period
    from od_table
    group by ID;
quit;

proc sql;
    create table pre_case_report_counts as
    select 
        sum(od_flag) as od_flag_before_case,
        sum(fod_flag) as fod_flag_before_case
    from od_table as a
    inner join case_report_events as c
    on a.ID = c.ID
    where (a.year*12 + a.month) < c.case_report_period;
quit;

title "Counts of Events Occurring Before Case Report";
proc print data=pre_case_report_counts noobs;
run;
title;

proc sql;
    create table od_table as
    select *
    from od_table
    where (YEAR > oud_year) 
        or (YEAR = oud_year and MONTH >= oud_month)
    order by ID, YEAR, MONTH;
quit;

/*=========================*/
/* 12. Sort Final OD Table */
/*=========================*/
/* Sorting the final overdose table by ID, year, and month */

proc sort data=od_table;
    by ID year month; 
run;

/*========================================*/
/* 13. Merge Pregnancy Flags with OD Data */
/*========================================*/
/* Merge pregnancy flags with the overdose data. For any month/year combination, if a pregnancy flag exists, it's added to the table, otherwise the flag is set to a default value (9999). */

proc sql;
    create table od_table as
    select a.*, 
           case when b.flag is not null then b.flag 
                else 9999 end as preg_flag
    from od_table a
    left join pregnancy_flags b
    on a.ID = b.ID 
       and a.month = b.month 
       and a.year = b.year;
quit;

/*=============================================*/
/* 14. Summarize MOUD Flag for Each Month-Year */
/*=============================================*/
/* This step reduces the dataset to unique ID-month-year combinations and retains the maximum MOUD flag value for each combination. */

proc sql;
    create table moud_summary as
    select distinct
        ID,
        month,
        year,
        max(moud_flag) as moud_flag 
    from moud_summary
    group by ID, month, year;
quit;

/*====================================================*/
/* 15. Reduce Post-Treatment Flag for Each Month-Year */
/*====================================================*/
/* Similar to the MOUD flag, we reduce the spine data to distinct ID-month-year combinations, keeping the maximum post-treatment flag for each combination. */

proc sql;
    create table moud_spine_posttxt as
    select distinct
        ID,
        month,
        year,
        max(posttxt_flag) as posttxt_flag 
    from moud_spine_posttxt
    group by ID, month, year;
quit;

/*======================================================*/
/* 16. Merge MOUD and Post-Treatment Flags with OD Data */
/*======================================================*/
/* This final merge combines both the MOUD and post-treatment flags with the overdose data, ensuring that missing flags are replaced with default values (0) where applicable. */

proc sql;
    create table od_table_full as
    select a.*, 
           coalesce(b.moud_flag, 0) as moud_flag,
           coalesce(c.posttxt_flag, 0) as posttxt_flag
    from od_table a
    left join moud_summary b 
    on a.ID = b.ID and a.month = b.month and a.year = b.year
    left join moud_spine_posttxt c
    on a.ID = c.ID and a.month = c.month and a.year = c.year;
quit;

/*===============================*/
/* 17. Prepare Data for Analysis */
/*===============================*/
/* This step prepares the data by creating a unique time index based on the month and year, and categorizes individuals into different groups based on pregnancy and post-partum status. 
The 'group' variable is used to distinguish between different states, such as pregnant, post-partum, and non-pregnant. 
It then filters death records (`deaths_filtered`) and merges them with the treatment dataset to flag deaths (`death_flag`). A new dataset (`death_events`) identifies the earliest death date per individual, and post-death events such as overdoses are counted (`post_death_counts`). 
The dataset is then cleaned to remove records occurring after death. */

data prepared_data;
    set od_table_full;

    time_index = (year - 2014) * 12 + month;
   
    if preg_flag = 1 then group = 1; /* Pregnant */
    else if preg_flag = 2 then group = 2; /* 0-6 months post-partum */
    else if preg_flag = 3 then group = 3; /* 7-12 months post-partum */
    else if preg_flag = 4 then group = 4; /* 13-18 months post-partum */
    else if preg_flag = 5 then group = 4; /* 19-24 months post-partum */
    else if preg_flag = 9999 then group = 0; /* Non-pregnant */
   
    /* Categorize individuals based on MOUD and post-treatment flags */
    if moud_flag = 1 and posttxt_flag = 0 then treat_group = 1; /* On MOUD */
    else if moud_flag = 1 and posttxt_flag = 1 then treat_group = 2; /* Post-TXT */
    else if moud_flag = 0 and posttxt_flag = 0 then treat_group = 0; /* No MOUD */
   
run;

/* Reduce from EPISODE_LEVEL to PERSON_LEVEL */
PROC SORT DATA=prepared_data;
BY ID YEAR MONTH;
RUN;

proc sql;
   create table deaths_filtered as
   select 
       ID, 
       YEAR_DEATH, 
       MONTH_DEATH
   from PHDDEATH.DEATH
   where YEAR_DEATH in &year;
quit;
	
proc sort data=PREPARED_DATA;
by ID year month;
run;

 proc sql;
    create table PREPARED_DATA as
    select a.*, 
           b.YEAR_DEATH, 
           b.MONTH_DEATH,
           case 
               when b.YEAR_DEATH = a.year and b.MONTH_DEATH = a.month then 1
               else 0
           end as death_flag
    from PREPARED_DATA as a
    left join deaths_filtered as b
    on a.ID = b.ID;
quit;

proc sql;
    create table death_events as 
    select ID, min(year*12 + month) as death_period
    from PREPARED_DATA
    where death_flag = 1
    group by ID;
quit;

proc sql;
    create table post_death_counts as
    select 
        sum(od_flag) as od_flag_after_death,
        sum(fod_flag) as fod_flag_after_death
    from PREPARED_DATA as a
    inner join death_events as d
    on a.ID = d.ID
    where (a.year*12 + a.month) > d.death_period;
quit;

title "Counts of Events Occurring After Death";
proc print data=post_death_counts noobs;
run;
title;

data PREPARED_DATA;
    set PREPARED_DATA;
    retain death_flag_forward 0;
    by ID;

    if first.ID then death_flag_forward = 0;
    if death_flag = 1 then death_flag_forward = 1;

    if death_flag_forward = 1 and (year > YEAR_DEATH or (year = YEAR_DEATH and month > MONTH_DEATH)) then delete;

    drop death_flag_forward;
run;

/*=====================================*/
/* 18. Overdoses by Pregnancy Status   */
/*=====================================*/
/* This section again repeats on above section by preparing the dataset for rate calculation. It begins by aggregating treatment data (`PREPARED_DATA`), ensuring unique records per individual and time period. 
Next, person-time (`PERSON_TIME`) is calculated for each individual, and summary statistics on overdoses and fatal overdoses are generated (`PERIOD_SUMMARY`). 
This summary is merged with demographic data (`PHDSPINE.DEMO`) to create the final dataset (`PERIOD_SUMMARY_FINAL`). Additional variables, including homelessness history and injection drug use evidence (`IDU_EVIDENCE`), are derived. 
Age is computed, and individuals are grouped into age categories. The final step involves calculating overdose rates, stratified by various demographic and risk factors using a macro (`calculate_rates`). 
Overdose rates and confidence intervals are computed for different groups, including pregnancy status, education, incarceration history, and homelessness */

proc sql;
   create table PREPARED_DATA_preg as
   select distinct
      ID, 
      YEAR, 
      MONTH,
      group,
      max(moud_flag) as moud_flag,
      max(posttxt_flag) as posttxt_flag,
      sum(od_flag) as od_flag,
      max(fod_flag) as fod_flag,
      min(preg_flag) as preg_flag
   from PREPARED_DATA
   group by ID, YEAR, MONTH;
quit;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        count(month) as person_time
    from PREPARED_DATA_preg
    group by ID, group;
quit;

proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          group,
          sum(od_flag) as overdoses,
          sum(fod_flag) as fatal_overdoses
   from PREPARED_DATA_preg
   group by ID, group;
quit;
	
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
           cov.FINAL_RE,
           cov.EDUCATION,
           cov.HOMELESS_EVER,
           cov.EVER_INCARCERATED,
           cov.FOREIGN_BORN,
           cov.YOB
    from PERIOD_SUMMARY
    left join PHDSPINE.DEMO as cov
    on PERIOD_SUMMARY.ID = cov.ID;
quit;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT,
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

title 'Overdoses, Overall; Note: Fatal Overdoses counted in Non-fatal overdoses';
proc sql;
    select 
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time
    from PERIOD_SUMMARY_FINAL;
quit;

title 'Overdoses by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
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
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Overdoses by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Overdoses by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Overdoses by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Overdoses by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Overdoses by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Overdoses by Pregnancy Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Overdoses by Pregnancy Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Overdoses by Pregnancy Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Overdoses by Pregnancy Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Overdoses by Pregnancy Group, Stratified by rural_group');
title;

/*==========================================*/
/* 19. Overdoses by MOUD Treatment Status   */
/*==========================================*/
/* The same process is repeated for `treat_group`, segmenting individuals based on treatment received. The output consists of tables summarizing overdoses, person-time, and risk factors, providing insights into overdose patterns among individuals with OUD. */

proc sql;
   create table PREPARED_DATA_treat as
   select distinct
      ID, 
      YEAR, 
      MONTH,
      treat_group,
      max(moud_flag) as moud_flag,
      max(posttxt_flag) as posttxt_flag,
      sum(od_flag) as od_flag,
      max(fod_flag) as fod_flag,
      min(preg_flag) as preg_flag
   from PREPARED_DATA
   group by ID, YEAR, MONTH;
quit;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        treat_group,
        count(month) as person_time
    from PREPARED_DATA_treat
    group by ID, treat_group;
quit;
	
proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          treat_group,
          sum(od_flag) as overdoses,
          sum(fod_flag) as fatal_overdoses
   from PREPARED_DATA_treat
   group by ID, treat_group;
quit;
	
proc sort data=PERSON_TIME;
    by ID treat_group;
run;

proc sort data=PERIOD_SUMMARY;
    by ID treat_group;
run;
	
data PERIOD_SUMMARY;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID treat_group;
run;

proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY.*,
           cov.FINAL_RE,
           cov.EDUCATION,
           cov.HOMELESS_EVER,
           cov.EVER_INCARCERATED,
           cov.FOREIGN_BORN,
           cov.YOB
    from PERIOD_SUMMARY
    left join PHDSPINE.DEMO as cov
    on PERIOD_SUMMARY.ID = cov.ID;
quit;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT,
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.BIRTH_INDICATOR,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

title 'Overdoses by Treatment Group, Overall';
proc sql;
    select 
        treat_group,
        count(*) as total_n,
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by treat_group;
quit;

%macro calculate_rates(group_by_vars, mytitle);
title &mytitle;
proc sql;
    select 
        treat_group,
        &group_by_vars,
        count(*) as total_n,
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by treat_group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Overdoses by Treatment Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Overdoses by Treatment Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Overdoses by Treatment Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Overdoses by Treatment Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Overdoses by Treatment Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Overdoses by Treatment Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Overdoses by Treatment Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Overdoses by Treatment Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Overdoses by Treatment Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Overdoses by Treatment Group, Stratified by rural_group');
%calculate_rates(BIRTH_INDICATOR, 'Overdoses by Treatment Group, Stratified by BIRTH_INDICATOR');
title;

proc sql;
    create table moud_spine_preg as
    select distinct
        ID,
        month,
        year,
        max(moud_start_group) as moud_start_group
    from moud_spine_preg
    group by ID, month, year;
quit;

proc sql;
    create table PREPARED_DATA as
    select a.*, 
           coalesce(b.moud_start_group, 0) as moud_start_group
    from PREPARED_DATA a
    left join moud_spine_preg b 
    on a.ID = b.ID and a.month = b.month and a.year = b.year;
quit;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        moud_start_group,
        count(month) as person_time
    from PREPARED_DATA
    group by ID, moud_start_group;
quit;

proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          moud_start_group,
          sum(od_flag) as overdoses,
          sum(fod_flag) as fatal_overdoses
   from PREPARED_DATA
   group by ID, moud_start_group;
quit;

proc sort data=PERSON_TIME;
    by ID moud_start_group;
run;
	
proc sort data=PERIOD_SUMMARY;
    by ID moud_start_group;
run;
	
data PERIOD_SUMMARY_FINAL;
    merge PERIOD_SUMMARY
          PERSON_TIME;
    by ID moud_start_group;
run;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          demographics.FINAL_RE, 
          demographics.FINAL_SEX,
          demographics.EDUCATION,
          demographics.EVER_INCARCERATED,
          demographics.FOREIGN_BORN,
          demographics.HOMELESS_EVER,
          demographics.YOB
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN PHDSPINE.DEMO AS demographics 
   ON a.ID = demographics.ID;
QUIT;

PROC SQL;
   CREATE TABLE PERIOD_SUMMARY_FINAL AS
   SELECT a.*, 
          cov.INSURANCE_CAT,
          cov.OTHER_SUBSTANCE_USE,
          cov.rural_group,
          cov.HCV_SEROPOSITIVE_INDICATOR
   FROM PERIOD_SUMMARY_FINAL AS a
   LEFT JOIN FINAL_COHORT AS cov 
   ON a.ID = cov.ID;
QUIT;

proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select a.*, b.BIRTH_INDICATOR
    from PERIOD_SUMMARY_FINAL a
    left join births b
    on a.ID = b.ID;
quit;

PROC SQL;
	CREATE TABLE PERIOD_SUMMARY_FINAL AS
	SELECT DISTINCT *
	FROM PERIOD_SUMMARY_FINAL
	WHERE BIRTH_INDICATOR = 1;
QUIT;

data PERIOD_SUMMARY_FINAL;
    length HOMELESS_HISTORY_GROUP $10;
    set PERIOD_SUMMARY_FINAL;
    if HOMELESS_EVER = 0 then HOMELESS_HISTORY_GROUP = 'No';
    else if 1 <= HOMELESS_EVER <= 5 then HOMELESS_HISTORY_GROUP = 'Yes';
    else HOMELESS_HISTORY_GROUP = 'Unknown';
run;

proc sql;
create table PERIOD_SUMMARY_FINAL as select *,
case
when ID in (select ID from IJI_COHORT) then 1
else 0
end as IJI_DIAG
from PERIOD_SUMMARY_FINAL;
quit;
		
proc sql;
    create table PERIOD_SUMMARY_FINAL as
    select PERIOD_SUMMARY_FINAL.*,
           hcv.EVER_IDU_HCV
    from PERIOD_SUMMARY_FINAL
    left join HCV_STATUS as hcv
    on PERIOD_SUMMARY_FINAL.ID = hcv.ID;
quit;
		
data PERIOD_SUMMARY_FINAL;
    set PERIOD_SUMMARY_FINAL;
    if EVER_IDU_HCV = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;
	
PROC SQL;
    CREATE TABLE PERIOD_SUMMARY_FINAL AS
    SELECT a.*, 
           cov.agegrp
    FROM PERIOD_SUMMARY_FINAL AS a
    LEFT JOIN oud_distinct AS cov 
    ON a.ID = cov.ID;
QUIT;

title 'Overdoses by moud_start_group Group, Overall';
proc sql;
    select 
        moud_start_group,
        count(*) as total_n,
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by moud_start_group;
quit;

%macro calculate_rates(group_by_vars, mytitle);
title &mytitle;
proc sql;
    select 
        moud_start_group,
        &group_by_vars,
        count(*) as total_n,
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time,
        calculated overdoses / calculated total_person_time as overdoses_rate format=8.4,
        (calculated overdoses - 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_lower format=8.4,
        (calculated overdoses + 1.96 * sqrt(calculated overdoses)) / calculated total_person_time as overdoses_rate_upper format=8.4,
        calculated fatal_overdoses / calculated total_person_time as fatal_overdoses_rate format=8.4,
        (calculated fatal_overdoses - 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_lower format=8.4,
        (calculated fatal_overdoses + 1.96 * sqrt(calculated fatal_overdoses)) / calculated total_person_time as fatal_overdoses_rate_upper format=8.4
    from PERIOD_SUMMARY_FINAL
    group by moud_start_group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(agegrp, 'Overdoses by moud_start_group Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Overdoses by moud_start_group Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Overdoses by moud_start_group Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Overdoses by moud_start_group Group, Stratified by HOMELESS_HISTORY');
%calculate_rates(EVER_INCARCERATED, 'Overdoses by moud_start_group Group, Stratified by EVER_INCARCERATED');
%calculate_rates(IDU_EVIDENCE, 'Overdoses by moud_start_group Group, Stratified by IDU_EVIDENCE');
%calculate_rates(INSURANCE_CAT, 'Overdoses by moud_start_group Group, Stratified by INSURANCE_CAT');
%calculate_rates(HCV_SEROPOSITIVE_INDICATOR, 'Overdoses by moud_start_group Group, Stratified by HCV_SEROPOSITIVE_INDICATOR');
%calculate_rates(OTHER_SUBSTANCE_USE, 'Overdoses by moud_start_group Group, Stratified by OTHER_SUBSTANCE_USE');
%calculate_rates(rural_group, 'Overdoses by moud_start_group Group, Stratified by rural_group');
title;

/*==========================================*/
/* MV Model Arrays and                      */
/* Test to see if Log-Binomials Converge    */
/*==========================================*/

data FINAL_COHORT_FILT;
    set FINAL_COHORT;
    if FINAL_RE NE 9 and EDUCATION_GROUP NE 'Other or Unknown' and HOMELESS_HISTORY_GROUP NE 'Unknown' and INSURANCE_CAT NE 'Other/Missing';
run;

title "Table 2, MV EVER_MOUD w/ agegrp_num";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;

title "Table 2, MV EVER_MOUD w/ oud_age";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
title;

title "Table 2, MV EVER_MOUD_CLEAN w/ agegrp_num";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;

title "Table 2, MV EVER_MOUD_CLEAN w/ oud_age";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_MOUD_CLEAN(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
title;

title "Table 2, MV EVER_OD w/ agegrp_num";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;

title "Table 2, MV EVER_OD w/ oud_age";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_OD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
title;

title "Table 2, MV EVER_FOD w/ agegrp_num";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;

title "Table 2, MV EVER_FOD w/ oud_age";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_FOD(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
title;

title "Table 2, MV EVER_6MO w/ agegrp_num";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') agegrp_num (ref='3') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT agegrp_num OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;

title "Table 2, MV EVER_6MO w/ oud_age";
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP IDU_EVIDENCE rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') HOMELESS_HISTORY_GROUP (ref='No') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE HOMELESS_HISTORY_GROUP CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
proc glimmix data=FINAL_COHORT_FILT noclprint noitprint;
    class FINAL_RE (ref='1') INSURANCE_CAT (ref='Medicaid') OTHER_SUBSTANCE_USE (ref='0') EVER_INCARCERATED (ref='0') HOMELESS_HISTORY_GROUP (ref='No') IDU_EVIDENCE (ref='0') CONFIRMED_HCV_INDICATOR (ref='0') rural_group (ref='Urban');
    model EVER_6MO(event='1') = FINAL_RE INSURANCE_CAT oud_age OTHER_SUBSTANCE_USE EVER_INCARCERATED HOMELESS_HISTORY_GROUP IDU_EVIDENCE CONFIRMED_HCV_INDICATOR rural_group / dist=binary link=logit solution oddsratio;
run;
title;

%macro Table2MOUD(var, ref=);
    title "Table 2, Crude, Log-Binomial";
    proc glimmix data=FINAL_COHORT noclprint noitprint;
        class &var (ref=&ref);
        model EVER_MOUD(event='1') = &var / dist=binomial link=log solution;
        lsmeans &var / ilink cl; 
    run;
%mend;

%Table2MOUD(FINAL_RE, ref ='1');
%Table2MOUD(agegrp_num, ref ='3');
%Table2MOUD(EVER_INCARCERATED, ref ='0');
%Table2MOUD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2MOUD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2MOUD(EDUCATION_GROUP, ref ='HS or less');
%Table2MOUD(HIV_DIAG, ref ='0');
%Table2MOUD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2MOUD(IJI_DIAG, ref ='0');
%Table2MOUD(EVER_IDU_HCV, ref ='0');
%Table2MOUD(IDU_EVIDENCE, ref ='0');
%Table2MOUD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2MOUD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2MOUD(INSURANCE_CAT, ref ='Medicaid');
%Table2MOUD(rural_group, ref ='Urban');

%macro Table2MOUD(var, ref=);
    title "Table 2, Crude, Log-Binomial";
    proc glimmix data=FINAL_COHORT noclprint noitprint;
        class &var (ref=&ref);
        model EVER_MOUD_CLEAN(event='1') = &var / dist=binomial link=log solution;
        lsmeans &var / ilink cl; 
    run;
%mend;

%Table2MOUD(FINAL_RE, ref ='1');
%Table2MOUD(agegrp_num, ref ='3');
%Table2MOUD(EVER_INCARCERATED, ref ='0');
%Table2MOUD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2MOUD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2MOUD(EDUCATION_GROUP, ref ='HS or less');
%Table2MOUD(HIV_DIAG, ref ='0');
%Table2MOUD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2MOUD(IJI_DIAG, ref ='0');
%Table2MOUD(EVER_IDU_HCV, ref ='0');
%Table2MOUD(IDU_EVIDENCE, ref ='0');
%Table2MOUD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2MOUD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2MOUD(INSURANCE_CAT, ref ='Medicaid');
%Table2MOUD(rural_group, ref ='Urban');

%macro Table2OD(var, ref=);
    title "Table 2, Crude, Log-Binomial";
    proc glimmix data=FINAL_COHORT noclprint noitprint;
        class &var (ref=&ref);
        model EVER_OD(event='1') = &var / dist=binomial link=log solution;
        lsmeans &var / ilink cl; 
    run;
%mend;

%Table2OD(FINAL_RE, ref ='1');
%Table2OD(agegrp_num, ref ='3');
%Table2OD(EVER_INCARCERATED, ref ='0');
%Table2OD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2OD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2OD(EDUCATION_GROUP, ref ='HS or less');
%Table2OD(HIV_DIAG, ref ='0');
%Table2OD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2OD(IJI_DIAG, ref ='0');
%Table2OD(EVER_IDU_HCV, ref ='0');
%Table2OD(IDU_EVIDENCE, ref ='0');
%Table2OD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2OD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2OD(INSURANCE_CAT, ref ='Medicaid');
%Table2OD(rural_group, ref ='Urban');

%macro Table2OD(var, ref=);
    title "Table 2, Crude, Log-Binomial";
    proc glimmix data=FINAL_COHORT noclprint noitprint;
        class &var (ref=&ref);
        model EVER_FOD(event='1') = &var / dist=binomial link=log solution;
        lsmeans &var / ilink cl; 
    run;
%mend;

%Table2OD(FINAL_RE, ref ='1');
%Table2OD(agegrp_num, ref ='3');
%Table2OD(EVER_INCARCERATED, ref ='0');
%Table2OD(HOMELESS_HISTORY_GROUP, ref ='No');
%Table2OD(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table2OD(EDUCATION_GROUP, ref ='HS or less');
%Table2OD(HIV_DIAG, ref ='0');
%Table2OD(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table2OD(IJI_DIAG, ref ='0');
%Table2OD(EVER_IDU_HCV, ref ='0');
%Table2OD(IDU_EVIDENCE, ref ='0');
%Table2OD(MENTAL_HEALTH_DIAG, ref ='0');
%Table2OD(OTHER_SUBSTANCE_USE, ref ='0');
%Table2OD(INSURANCE_CAT, ref ='Medicaid');
%Table2OD(rural_group, ref ='Urban');


%macro Table26MO(var, ref=);
    title "Table 2, Crude, Log-Binomial";
    proc glimmix data=FINAL_COHORT noclprint noitprint;
        class &var (ref=&ref);
        model EVER_6MO(event='1') = &var / dist=binomial link=log solution;
        lsmeans &var / ilink cl; 
    run;
%mend;

%Table26MO(FINAL_RE, ref ='1');
%Table26MO(agegrp_num, ref ='3');
%Table26MO(EVER_INCARCERATED, ref ='0');
%Table26MO(HOMELESS_HISTORY_GROUP, ref ='No');
%Table26MO(LANGUAGE_SPOKEN_GROUP, ref ='English');
%Table26MO(EDUCATION_GROUP, ref ='HS or less');
%Table26MO(HIV_DIAG, ref ='0');
%Table26MO(CONFIRMED_HCV_INDICATOR, ref ='0');
%Table26MO(IJI_DIAG, ref ='0');
%Table26MO(EVER_IDU_HCV, ref ='0');
%Table26MO(IDU_EVIDENCE, ref ='0');
%Table26MO(MENTAL_HEALTH_DIAG, ref ='0');
%Table26MO(OTHER_SUBSTANCE_USE, ref ='0');
%Table26MO(INSURANCE_CAT, ref ='Medicaid');
%Table26MO(rural_group, ref ='Urban');