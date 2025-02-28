/*==============================================*/
/* Project: PHD Maternal Analysis Cascade 	    */
/* Author: Ryan O'Dea and Sarah Munroe          */ 
/* Created: 4/27/2023 		                    */
/* Updated: 01/2025 by SJM  	                */
/*==============================================*/

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
	month_apcd = MED_FROM_DATE_MONTH;
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

IF oud_pharm > 0 then

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

   year_cm = min(year_oo, year_hd, year_cm);
   
    /* Assign month_cm based on the corresponding year */
    IF year_cm = year_oo THEN month_cm = month_oo;
    ELSE IF year_cm = year_hd THEN month_cm = month_hd;
    ELSE IF year_cm = year_cm THEN month_cm = month_cm;
    
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
    
    IF oud_year = year_apcd THEN oud_month = month_apcd;
    ELSE IF oud_year = year_cm THEN oud_month = month_cm;
    ELSE IF oud_year = year_matris THEN oud_month = month_matris;
    ELSE IF oud_year = year_bsas THEN oud_month = month_bsas;
    ELSE IF oud_year = year_pmp THEN oud_month = month_pmp;

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

/*============================*/
/* 12. Add Pregancy Covariates  */
/*============================*/

DATA all_births (keep = ID BIRTH_INDICATOR YEAR_BIRTH);
	SET PHDBIRTH.BIRTH_MOM (KEEP = ID YEAR_BIRTH
							WHERE= (YEAR_BIRTH IN &year));
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
proc means data=oud_preg mean median std;
    var TOTAL_BIRTHS;
run;

/*==============================*/
/* MOUD Table Creation          */
/*==============================*/

DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

PROC SQL;
    CREATE TABLE moud_demo AS
    SELECT moud.*, demographics.FINAL_RE, demographics.FINAL_SEX
    FROM moud
    LEFT JOIN PHDSPINE.DEMO AS demographics 
    ON moud.ID = demographics.ID;
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

PROC SORT DATA=moud_demo;
    BY ID TYPE_MOUD DATE_START_MOUD;
RUN;

DATA moud_demo;
    SET moud_demo;
    by ID TYPE_MOUD;
    retain episode_num;

    lag_date = lag(DATE_END_MOUD);
    IF FIRST.TYPE_MOUD THEN lag_date = .;
    IF FIRST.TYPE_MOUD THEN episode_num = 1;
    
    diff = DATE_START_MOUD - lag_date;

    IF diff >= &MOUD_leniency THEN flag = 1; ELSE flag = 0;
    IF flag = 1 THEN episode_num = episode_num + 1;

    episode_id = catx("_", ID, episode_num);
RUN;

PROC SORT data=moud_demo; 
    BY episode_id;
RUN;

PROC SQL;
    CREATE TABLE moud_demo AS 
    SELECT * 
    FROM moud_demo
    WHERE ID IN (SELECT DISTINCT ID FROM oud_distinct);
QUIT;

proc format;
    value moud_typef
    
		1='Likely Methadone'
		2='Buprenorphine'
		3='Naltrexone';

title "Distribution of MOUD Types";
proc freq data=moud_demo;
    table TYPE_MOUD;
    format TYPE_MOUD moud_typef.;
run;

DATA moud_demo; 
    SET moud_demo;

    by episode_id;
    retain DATE_START_MOUD;

    IF FIRST.episode_id THEN DO;
        start_month = DATE_START_MONTH_MOUD;
        start_year = DATE_START_YEAR_MOUD;
        start_date = DATE_START_MOUD;
    END;
    IF LAST.episode_id THEN DO;
        end_month = DATE_END_MONTH_MOUD;
        end_year = DATE_END_YEAR_MOUD;
        end_date = DATE_END_MOUD;
    END;
        
   	IF end_date - start_date < &MOUD_leniency THEN DELETE;
RUN;

PROC SORT data=moud_demo;
    BY ID;
RUN;

PROC SQL;
 CREATE TABLE moud_demo 
 AS SELECT DISTINCT * FROM moud_demo;
QUIT;

DATA moud_demo;
    SET moud_demo;
    BY ID;
	
	IF end_date - start_date < &MOUD_leniency THEN DELETE;

    LAG_ED = LAG(END_DATE);
	
	IF FIRST.ID THEN diff = .; 
	ELSE diff = start_date - LAG_ED;
    IF end_date < LAG_ED THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;

    age = start_year - YOB;
    age_grp_five = put(age, age_grps_five.);
    
    drop diff;

RUN;

PROC SQL;                    
    CREATE TABLE moud_starts AS
    SELECT ID,
           1 AS moud_start
    FROM moud_demo
    ORDER BY start_month, start_year, TYPE_MOUD, ID;
QUIT;

proc sql;
create table moud_preg as select *,
case
when ID in (select ID from moud_starts) then 1
else 0
end as moud_start
from oud_preg;
quit;

data episode_length;
    set moud_demo;

    episode_length = end_date - start_date;

    episode_0months = 0;
    episode_6months = 0;
    episode_12months = 0;
    episode_24months = 0;

    if episode_length < 180 then episode_0months = 1;
    if episode_length >= 180 and episode_length < 365 then episode_6months = 1; /* 6 months */
    if episode_length >= 365 and episode_length < 730 then episode_12months = 1; /* 1 year */
    if episode_length >= 730 then episode_24months = 1; /* 2 years */
run;

proc sql;
    create table episode_counts as
    select ID,
    	   BIRTH_INDICATOR,
           count(*) as num_episodes
    from episode_length
    group by ID;
quit;

proc sql;
    create table episode_counts as
    select distinct ID, BIRTH_INDICATOR, num_episodes
    from episode_counts;
quit;

title "Summary stats: Mean number of MOUD episodes per person";
proc means data=episode_counts mean median std;
    var num_episodes;
run;

proc means data=episode_counts mean median std;
    class BIRTH_INDICATOR;
    var num_episodes;
run;

title "Summary stats: MOUD episode duration (days)";
proc means data=episode_length mean median std;
    var episode_length;
run;

proc means data=episode_length mean median std;
    class BIRTH_INDICATOR;
    var episode_length;
run;

proc sql;
    create table aggregated_episode as
    select ID,
           sum(episode_0months) as episode_0months_sum,
           sum(episode_6months) as episode_6months_sum,
           sum(episode_12months) as episode_12months_sum,
           sum(episode_24months) as episode_24months_sum
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

data check_moud_count;
    set moud_preg;
    
    MOUD_Sum = sum(episode_0months_sum, episode_6months_sum, episode_12months_sum, episode_24months_sum);

    if MOUD_Sum = num_episodes then MOUD_Match = 1;
    else MOUD_Match = 0;
run;

title "Check that the sum of MOUD_duration variables = number MOUD episodes";
proc freq data=check_moud_count;
   tables MOUD_Match;
run;
title;

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
 proc means data=overdose_counts mean median std;
    var OD_Count;
 run;
 
 proc means data=overdose_counts mean median std;
    class BIRTH_INDICATOR;
    var OD_Count;
 run;
 
 * Step 1: Transpose DATE_START_MOUD;
 PROC SORT data=moud_demo (KEEP= ID DATE_START_MOUD DATE_END_MOUD);
   by ID DATE_START_MOUD;
 RUN;
 
 PROC TRANSPOSE data=moud_demo out=moud_demo_wide_start (KEEP = ID DATE_START_MOUD:) PREFIX=DATE_START_MOUD_;
   BY ID;
   VAR DATE_START_MOUD;
 RUN;
 
 * Step 2: Transpose DATE_END_MOUD;
 PROC SORT data=moud_demo (KEEP= ID DATE_START_MOUD DATE_END_MOUD);
   by ID DATE_END_MOUD;
 RUN;
 
 PROC TRANSPOSE data=moud_demo out=moud_demo_wide_end (KEEP = ID DATE_END_MOUD:) PREFIX=DATE_END_MOUD_;
   BY ID;
   VAR DATE_END_MOUD;
 RUN;
 
 * Step 3: Merge the transposed datasets;
 DATA moud_demo_final;
   MERGE moud_demo_wide_start (IN=a) moud_demo_wide_end (IN=b);
   BY ID;
 RUN;
 
 DATA moud_od_demo;
   MERGE overdose_spine (IN=a) moud_demo_final (IN=b);
   BY ID;
   IF a;  /* Keeps only records from overdose_spine */
 RUN;
 
 DATA moud_od_demo;
     SET moud_od_demo;
     by ID;
 
     * Define arrays for MOUD episode dates;
     array MOUD_START (*) DATE_START_MOUD_:; /* Adjust the number 10 as needed based on your dataset */
     array MOUD_END (*) DATE_END_MOUD_:; /* Adjust the number 10 as needed based on your dataset */
 
     num_moud_episodes = dim(MOUD_START);
 
     * Retain the classification flags;
     retain OD_during_MOUD OD_after_MOUD OD_no_MOUD;
 
     IF first.ID THEN DO;
         OD_during_MOUD = 0;  * Initialize to 0 (not during any MOUD episode);
         OD_after_MOUD = 0; * Initialize to 0 (OD not within 30 days of end of MOUD episode);
         OD_no_MOUD = 0; * Initialize to 0 (OD not during or near any MOUD episode);
     END;
 
     * Loop through the MOUD episodes for each ID;
     DO i = 1 TO num_moud_episodes;
         * Check if OD_DATE is within the range of this episode;
         IF OD_DATE >= MOUD_START(i) AND OD_DATE <= MOUD_END(i) THEN DO;
             OD_during_MOUD = 1; * Mark as during MOUD episode;
             LEAVE; * Exit the loop as we've found a match;
         END;
 
         * Check if OD_DATE is within 30 days after the end of this MOUD episode;
         IF OD_DATE > MOUD_END(i) AND OD_DATE <= MOUD_END(i) + 30 THEN DO;
             OD_after_MOUD = 1; * OD occurred within 30 days of the end of a MOUD episode;
             LEAVE; * Exit the loop as we've found a match;
         END;
     END;
 
     * If the overdose did not occur during or within 30 days of a MOUD episode, set the flag to 1;
     IF OD_during_MOUD = 0 AND OD_after_MOUD = 0 THEN OD_no_MOUD = 1;
 
     DROP i;
 
 RUN;
 
 proc sql;
     create table overdose_summary as 
     select 
         ID, 
         max(OD_COUNT) as TOTAL_OD_COUNT,
         sum(OD_during_MOUD) as N_OD_during_MOUD,
         sum(OD_after_MOUD) as N_OD_after_MOUD,
         sum(OD_no_MOUD) as N_OD_no_MOUD
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
     IF TOTAL_OD_COUNT = . THEN TOTAL_OD_COUNT = 0;
     IF TOTAL_OD_COUNT = 0 THEN OD_no_MOUD = 0 AND OD_during_MOUD = 0 AND OD_after_MOUD = 0;
 run;
 
 data check_od_count;
     set moud_preg;
     
     OD_Sum = sum(OD_no_MOUD, OD_during_MOUD, OD_after_MOUD);
 
     if OD_Sum = TOTAL_OD_COUNT then OD_Match = 1;
     else OD_Match = 0;
 run;
 
 title "Check that the sum of OD_during_MOUD variables = TOTAL_OD_COUNT";
 proc freq data=check_od_count;
    tables OD_Match;
 run;
 title;
 
 PROC SQL;
     SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
     INTO :num_unique_ids
     FROM moud_preg;
 QUIT;
 
 %put Number of Unique IDs in Main Dataset: &num_unique_ids; 

/* ========================================================== */
/* Table 1 */
/* ========================================================== */

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
    else if EDUCATION = 3 then EDUCATION_GROUP = 'Other';
    else if EDUCATION = 10 then EDUCATION_GROUP = 'Other';
    else EDUCATION_GROUP = 'Missing or Unknown';
run;

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
    if EVER_IDU_HCV_MAT = 1 or IJI_DIAG = 1 then IDU_EVIDENCE = 1;
    else IDU_EVIDENCE = 0;
run;

proc sort data=FINAL_COHORT;
    by ID oud_year oud_month;
run;

proc sort data=PHDAPCD.MOUD_MEDICAL;
    by ID MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH;
run;

data closest_insurance;
    length closest_past_type closest_future_type closest_type $2;
    merge FINAL_COHORT (in=a)
          PHDAPCD.MOUD_MEDICAL (in=b);
    by ID;
    
    if a;

    retain closest_past_date closest_past_type min_past_diff;
    retain closest_future_date closest_future_type min_future_diff;
    retain found_exact_match;

    if first.ID then do;
        closest_past_date = .;
        closest_past_type = "";
        min_past_diff = .;
        closest_future_date = .;
        closest_future_type = "";
        min_future_diff = .;
        found_exact_match = 0;
    end;

    if MED_FROM_DATE_YEAR = oud_year and MED_FROM_DATE_MONTH = oud_month then do;
        if found_exact_match = 0 then do; 
            closest_type = MED_INSURANCE_TYPE;
            found_exact_match = 1;
            output;
        end;
    end;

    else if found_exact_match = 0 then do;
        if MED_FROM_DATE_YEAR < oud_year or (MED_FROM_DATE_YEAR = oud_year and MED_FROM_DATE_MONTH < oud_month) then do;
            past_diff = (oud_year - MED_FROM_DATE_YEAR) * 12 + (oud_month - MED_FROM_DATE_MONTH);
            if min_past_diff = . or past_diff < min_past_diff then do;
                min_past_diff = past_diff;
                closest_past_date = MED_FROM_DATE;
                closest_past_type = MED_INSURANCE_TYPE;
            end;
        end;

        else do;
            future_diff = (MED_FROM_DATE_YEAR - oud_year) * 12 + (MED_FROM_DATE_MONTH - oud_month);
            if min_future_diff = . or future_diff < min_future_diff then do;
                min_future_diff = future_diff;
                closest_future_date = MED_FROM_DATE;
                closest_future_type = MED_INSURANCE_TYPE;
            end;
        end;
    end;

    if last.ID and found_exact_match = 0 then do;
        if min_past_diff ne . then do;
            closest_date = closest_past_date;
            closest_type = closest_past_type;
        end;
        else do;
            closest_date = closest_future_date;
            closest_type = closest_future_type;
        end;
        
        if closest_type ne "" then output;
    end;

run;

data final_output;
    set closest_insurance;
    keep ID oud_year oud_month closest_type;
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

data FINAL_COHORT;
    set FINAL_COHORT;
    length INSURANCE_CAT $10.;
    if INSURANCE in ('12', '13', '14', '15', 'CE', 'CI', 'HM') then INSURANCE_CAT = 'Private';
    else if INSURANCE in ('16', '20, 21', '30', 'HN', 'IC', 'MA', 'MB', 'MC', 'MD', 'MO', 'MP', 'MS', 'QM', 'SC') then INSURANCE_CAT = 'Public';
    else INSURANCE_CAT = 'Other';
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
    	0 = "Probable"
    	1 = "Confirmed"
    	. = "No Case Report";
    
    VALUE age_grps
		1 = '15-18'
		2 = '19-25'
		3 = '26-30'
		4 = '31-35'
		5 = '36-45';

run;

data FINAL_COHORT;
    set FINAL_COHORT;
    agegrp_num = input(agegrp, 8.); /* Convert character to numeric */
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
%Table1Freqs(IDU_EVIDENCE, flagf.);
%Table1Freqs(MENTAL_HEALTH_DIAG, flagf.);
%Table1Freqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1Freqs(INSURANCE_CAT);

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
%Table1StrataFreqs(IDU_EVIDENCE, flagf.);
%Table1StrataFreqs(MENTAL_HEALTH_DIAG, flagf.);
%Table1StrataFreqs(OTHER_SUBSTANCE_USE, flagf.);
%Table1StrataFreqs(INSURANCE_CAT);

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS Number_of_Unique_IDs
    INTO :num_unique_ids
    FROM FINAL_COHORT;
QUIT;

%put Number of unique Infant IDs in FINAL_COHORT table: &num_unique_ids;

/*==============================================*/ 
/* Project: MOUD/OD By Pregnancy Status         */
/* Author: SM                         		    */ 
/* Created: 11/26/2024				            */ 
/*==============================================*/

/*	Project Goal:
	Characterize and model the differecnes between pregnant and non-pregnant women's 
	initiation and cessation of opioid use disorder treatment (MOUD) episodes 
    and non-fatal and fatal overdose events.

    Part 1: This portion of the code processes the `PHDSPINE.MOUD` dataset by first sorting and 
    creating a unique `episode_id` for each treatment episode based on treatment start and end dates, 
    with episodes being flagged when a significant gap is detected between consecutive treatment episodes. 
    It also merges treatment episode data, calculates start and end months/years, removes short treatment 
    episodes based on the specified leniency, and eliminates any overlapping episodes. The dataset is then 
    cleaned for missing values and sorted for further analysis.

    Part 2: This section of the code defines a macro that merges demographic data from `PHDSPINE.DEMO` 
    to the input dataset, filters based on gender, and creates a table that flags the presence of treatment 
    episodes across a specified range of months and years. It also handles the creation of flags for pregnancy 
    and post-partum periods by calculating the relevant months based on gestational age, ensuring the correct assignment 
    of treatment and post-partum periods across multiple years. The final output includes flags for each month indicating 
    the stage of pregnancy or post-partum status for each individual. THe code potion is wrapped in a macro so that two datasets,
    moud_init and moud_duration, can be run sequentially through the same data manipulation steps. Dataset moud_init includes
    all IDs in the Maternal OUD cohort while dataset moud_duration is a subset of only those that had an MOUD episode.

    Part 3: MOUD Duration Model: A Poisson regression is used to examine the relationship between MOUD duration 
	and variables like group and time_index, incorporating an autoregressive correlation structure for repeated measures.
	MOUD Initialization Model: A logistic regression model analyzes the probability of initiating MOUD, considering group, 
	time_index, and interaction terms with an exchangeable correlation structure.

    Part 4: This portion of the code processes the `PHDSPINE.OVERDOSE` dataset by first sorting and 
    creating a unique `episode_id` for each overdose episode. Missing IDs from the moud dataset are identified and added 
    with placeholder episode_id values to the overdose data (to recpatilate the structure of the moud_init dataset). 
    Demographic information is merged with the overdose dataset and filtered filtered to include only female subjects. 
    The overdose data is sorted and merged with month and year flags to create the final cartesian overdose table, 
    combining relevant flags such as pregnancy_flags, moud_flag, and posttxt_flag.

    Part 5: Participants are categorized into groups based on their MOUD and post-TXT status. Logistic regression models 
    are used to assess the impact of group and time_index on the likelihood of overdose (od_flag) and fatal overdose (fod_flag),
    both with autoregressive correlation structures.

	Detailed documentation of all datasets and variables used:
	https://www.mass.gov/info-details/public-health-data-warehouse-phd-technical-documentation */

/*=============================*/
/*  Part 1: MOUD Treatment Episodes */
/*=============================*/

/*====================*/
/* 1. Initial Data Setup */
/*====================*/
DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT DATA=moud;
    BY ID TYPE_MOUD DATE_START_MOUD;
RUN;

/*====================*/
/* 2. Creating Episode IDs */
/*====================*/
/* The goal of this step is to create a unique `episode_id` for each treatment episode 
   based on the treatment start and end dates for each individual. The new episode ID 
   will be used for further merging and analysis. */
DATA moud;
    SET moud;
    by ID TYPE_MOUD;
    retain episode_num; /* Retain the episode number across records for the same ID */
    
    lag_date = lag(DATE_END_MOUD); /* Get the previous treatment end date */
    IF FIRST.TYPE_MOUD THEN lag_date = .; /* Reset lag_date at the start of each new treatment type */
    IF FIRST.TYPE_MOUD THEN episode_num = 1; /* Start a new episode for the first treatment of the type */
    
    diff = DATE_START_MOUD - lag_date; /* Calculate the difference in days between current and previous treatment start */
    
    /* If the difference is greater than a specified leniency, assume it is a new treatment episode */
    IF diff >= &MOUD_leniency THEN flag = 1; ELSE flag = 0;
    IF flag = 1 THEN episode_num = episode_num + 1; /* Increment the episode number when a gap is detected */
    
    /* Create a unique episode_id combining ID and episode number */
    episode_id = catx("_", ID, episode_num);
RUN;

PROC SORT data=moud; 
    BY episode_id;
RUN;

/*====================*/
/* 3. Merging Start and End Dates for Each Episode */
/*====================*/
/* In this step, we retain the start and end dates of each treatment episode. 
   The start date for each episode is taken from the first record in the episode, 
   and the end date is taken from the last record. This allows us to capture the full 
   duration of each treatment episode. */
DATA moud; 
    SET moud;

    by episode_id;
    retain DATE_START_MOUD; /* Retain the start date across all records within the same episode */
    
    IF FIRST.episode_id THEN DO;
        start_month = DATE_START_MONTH_MOUD;
        start_year = DATE_START_YEAR_MOUD;
        start_date = DATE_START_MOUD; /* Capture the start date for the first record of the episode */
    END;
    IF LAST.episode_id THEN DO;
        end_month = DATE_END_MONTH_MOUD;
        end_year = DATE_END_YEAR_MOUD;
        end_date = DATE_END_MOUD; /* Capture the end date for the last record of the episode */
    END;
    
    /* If the duration of the treatment episode is shorter than the specified leniency, 
       the episode is excluded from further analysis. */
    IF end_date - start_date < &MOUD_leniency THEN DELETE;
RUN;

/*====================*/
/* 4. Final Sorting and Removing Duplicates */
/*====================*/
/* Sorting by ID ensures that data is properly organized for the next steps. 
   The SQL step below removes any duplicate records to ensure that each episode 
   is uniquely represented. */
PROC SORT data=moud;
    BY ID;
RUN;

PROC SQL;
   CREATE TABLE moud 
   AS SELECT DISTINCT * 
   FROM moud;
QUIT;

/*====================*/
/* 5. Removing Episodes with Short Durations */
/*====================*/
/* In this step, treatment episodes with durations shorter than the leniency threshold 
   are removed to ensure the dataset only contains valid treatment episodes. */
DATA moud;
    SET moud;
    BY ID;
    
    /* If the duration between treatment start and end is less than the leniency threshold, 
       the episode is excluded. */
    IF end_date - start_date < &MOUD_leniency THEN DELETE;

    /* Calculate the difference in start date between consecutive treatment episodes for each ID. */
    LAG_ED = LAG(END_DATE);
    
    IF FIRST.ID THEN diff = .; /* Reset diff at the start of each new ID */
    ELSE diff = start_date - LAG_ED; /* Calculate the difference for subsequent episodes */
    
    /* Flag episodes with overlapping dates or inconsistencies in treatment duration. */
    IF end_date < LAG_ED THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF FIRST.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1; /* Flag as invalid if conditions are met */
    ELSE flag_mim = 0;

    /* Delete flagged episodes to clean the data */
    IF flag_mim = 1 THEN DELETE;
RUN;

/*====================*/
/* 6. Filtering Data by Date Range and ID */
/*====================*/
/* Finally, we filter the data to only include treatment episodes that ended in or after 2014. */
data moud;
    set moud;
    where DATE_END_YEAR_MOUD >= 2014;
run;

PROC SQL;
    CREATE TABLE moud AS 
    SELECT * 
    FROM moud
    WHERE ID IN (SELECT DISTINCT ID FROM oud_distinct);
QUIT;

/*====================*/
/* 7. Identifying Missing IDs */
/*====================*/
/* This step identifies IDs in the `oud_preg` dataset that do not have matching records in the 
   `moud` dataset. The result is saved in the `missing_ids` table. */
proc sql;
   create table missing_ids as
   select a.ID
   from oud_preg as a
   where not exists (select 1 from moud as b where a.ID = b.ID);
quit;

/*====================*/
/* 8. Creating Two MOUD Datasets */
/*====================*/
/* This dataset contains all records from `moud`, which will be used for further analysis of MOUD duration. */
DATA moud_duration;
    SET moud;
RUN;

/* This step completes the final dataset `moud_full` by taking the moud dataset and creating additional observations 
for those in the OUD cohort that did not have a record from the `moud` dataset. This dataset will be used to assess MOUD initiation */
DATA moud_full;
    SET moud;
RUN;

proc sql;
   insert into moud_full (ID, episode_id)
   select ID, "."
   from missing_ids;
quit;

/*=============================*/
/*  Part 2: Macro for flag generation */
/*=============================*/
data all_births;
    set PHDBIRTH.BIRTH_MOM (keep = ID BIRTH_LINK_ID MONTH_BIRTH YEAR_BIRTH where=(YEAR_BIRTH IN &year));
run;

data infants;
    set PHDBIRTH.BIRTH_INFANT (keep = ID BIRTH_LINK_ID GESTATIONAL_AGE);
run;

/* Step 13: Merge birth and infant data based on BIRTH_LINK_ID */
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

/* Step 14: Flag months within pregnancy and post-partum periods */
data pregnancy_flags;
    set merged_births_infants; /* Assume your birth data is named 'merged_births_infants' */
    length month year flag 8;
        
/* Calculate pregnancy duration based on gestational age (weeks) */
    if GESTATIONAL_AGE => 39 then pregnancy_months = 9;
    else if GESTATIONAL_AGE >= 35 and GESTATIONAL_AGE <= 38 then pregnancy_months = 8;
    else if GESTATIONAL_AGE >= 31 and GESTATIONAL_AGE <= 34 then pregnancy_months = 7;
    else if GESTATIONAL_AGE >= 26 and GESTATIONAL_AGE <= 30 then pregnancy_months = 6;
    else if GESTATIONAL_AGE >= 22 and GESTATIONAL_AGE <= 25 then pregnancy_months = 5;
    else if GESTATIONAL_AGE >= 18 and GESTATIONAL_AGE <= 21 then pregnancy_months = 4;
    else if GESTATIONAL_AGE >= 13 and GESTATIONAL_AGE <= 17 then pregnancy_months = 3;
    else if GESTATIONAL_AGE >= 9 and GESTATIONAL_AGE <= 12 then pregnancy_months = 2;
    else pregnancy_months = 1; /* For extremely preterm cases */
        
/* Calculate pregnancy start based on gestational months */
    pregnancy_start_month = MONTH_BIRTH - pregnancy_months + 1; /* Delivery month is included */
    pregnancy_start_year = YEAR_BIRTH;
    if pregnancy_start_month <= 0 then do;
        pregnancy_start_year = YEAR_BIRTH - 1;
        pregnancy_start_month = 12 + pregnancy_start_month;
    end;

/* Define pregnancy end as the birth month */
    pregnancy_end_month = MONTH_BIRTH;
    pregnancy_end_year = YEAR_BIRTH;

/* Flag each month in the pregnancy period */
    month = pregnancy_start_month;
    year = pregnancy_start_year;
    do while ((year < pregnancy_end_year) or (year = pregnancy_end_year and month <= pregnancy_end_month));
       flag = 1; /* Pregnancy flag */
       output;

/* Increment the month and year */
       month + 1;
       if month > 12 then do;
            month = 1;
            year + 1;
        end;
    end;

/* Flag each post-partum period */
    array post_partum_end_months[4] (6, 12, 18, 24);
    array post_partum_flags[4] (2, 3, 4, 5);

/* Loop through the post-partum groups */
    do i = 1 to 4;
       post_partum_end_month = MONTH_BIRTH + post_partum_end_months[i];
       post_partum_end_year = YEAR_BIRTH;
       if post_partum_end_month > 12 then do;
            post_partum_end_year = post_partum_end_year + floor((post_partum_end_month-1) / 12);
            post_partum_end_month = mod(post_partum_end_month, 12);
       end;

/* Start from the month after delivery */
     month = (ifn(i=1, pregnancy_end_month + 1, month));
     year = (ifn(i=1, pregnancy_end_year, year));
     if month > 12 then do;
         month = 1;
         year + 1;
     end;
	
     do while ((year < post_partum_end_year) or (year = post_partum_end_year and month <= post_partum_end_month));
        flag = post_partum_flags[i]; /* Post-partum flag: 2, 3, 4, or 5 */
        output;
	
/* Increment the month and year */
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
	
/* Sort the data by ID, month, year, and flag to ensure the lowest flag is first */
proc sort data=pregnancy_flags;
    by ID year month flag;
run;
	
/* Keep only the first row for each ID, year, month combination */
data pregnancy_flags;
    set pregnancy_flags;
    by ID year month;
	
/* Retain only the first row for each ID, year, month combination */
    if first.month then output;
run;

/* Step 4: Extract start and end years from a macro variable &year */
%let start_year=%scan(%substr(&year,2,%length(&year)-2),1,':');
%let end_year=%scan(%substr(&year,2,%length(&year)-2),2,':');

/* Step 5: Create a dataset for months (1 to 12) */
DATA months; DO month = 1 to 12; OUTPUT; END; RUN;

/* Step 6: Create a dataset for the range of years */
DATA years; DO year = &start_year to &end_year; OUTPUT; END; RUN;
    
%macro moud_table_creation(input_dataset);

    /* Step 7: Cross join moud_demo, months, and years to create a dataset with all combinations */
    PROC SQL;
        CREATE TABLE moud_table AS
        SELECT * FROM &input_dataset, months, years;
    QUIT;

	/* Merge pregnancy and post-partum flags with the MOUD episodes without duplicating rows */
	proc sql;
	    create table moud_table as
	    select a.*, 
	           case when b.flag is not null then b.flag 
	                else 9999 end as preg_flag
	    from moud_table a /* Original MOUD data */
	    left join pregnancy_flags b
	    on a.ID = b.ID 
	       and a.month = b.month 
	       and a.year = b.year;
	quit;
	
	    /* Step 8: Create a summary dataset with a flag indicating whether a month overlaps with the MOUD episode */
    data moud_summary;
        set moud_table;
        /* Convert the start and end month/year into a single month-year value */
        start_month_year = mdy(DATE_START_MONTH_MOUD, 1, DATE_START_YEAR_MOUD);
        end_month_year = mdy(DATE_END_MONTH_MOUD, 1, DATE_END_YEAR_MOUD);
        target_month_year = mdy(month, 1, year);

        /* Flag for overlap */
        if start_month_year <= target_month_year <= end_month_year then
            moud_flag = 1;
        else
            moud_flag = 0;
    run;

	/* Step 9: Create a dataset with post-treatment overlap flag (posttxt_flag) */
	data moud_spine_posttxt;
	    set moud_table;
	
	    /* Create start/end month-year variables for comparison */
	    start_month_year = mdy(DATE_START_MONTH_MOUD, 1, DATE_START_YEAR_MOUD);
	    end_month_year = mdy(DATE_END_MONTH_MOUD, 1, DATE_END_YEAR_MOUD);
	    target_month_year = mdy(month, 1, year);
	
	    /* Flag for posttxt overlap */
	    if target_month_year = end_month_year then
	        posttxt_flag = 1;
	    else
	        posttxt_flag = 0;
	run;

    /* Step 10: Sort moud_summary by ID, year, and month */
    proc sort data=moud_summary;
        by ID year month;
    run;

    /* Step 11: Create final moud_table, retaining lag information for moud_flag */
    data moud_table;
        set moud_summary;
        by ID year month;

        retain moud_init lag_moud_flag; /* Retain lag_moud_flag within ID */
        
        /* Initialize for each new ID */
        if first.ID then do;
            moud_init = 0;
            lag_moud_flag = .; /* Reset lag_moud_flag at the start of a new ID */
        end;

        /* Mark the first month of each new episode */
        if moud_flag = 1 then do;
            /* For the first record of the new ID or when lag_moud_flag is missing */
            if lag_moud_flag = 0 or lag_moud_flag = . then moud_init = 1;
            else if lag_moud_flag = 1 then moud_init = 0;
        end;

        /* Reset moud_init when not in a new episode */
        if moud_flag = 0 then moud_init = 0;

        /* Update lag_moud_flag after the logic to ensure it applies to the next record */
        lag_moud_flag = moud_flag;

        keep ID EPISODE_ID DATE_START_MONTH_MOUD DATE_START_YEAR_MOUD DATE_END_MONTH_MOUD DATE_END_YEAR_MOUD month year moud_flag moud_init preg_flag;
    run;
	
	proc sort data=moud_table;
	by ID year month;
	run;
	
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

	data MOUD_TABLE;
	    set MOUD_TABLE;
	    if DATE_END_MONTH_MOUD = MONTH and DATE_END_YEAR_MOUD = YEAR then moud_cessation = 1;
	    else moud_cessation = 0;
	run;

	data prepared_data;
    	set moud_table;
    	drop episode_id;
	run;
	
	data PREPARED_DATA;
		set PREPARED_DATA;
		
		/* Create a unique time index */
		time_index = (year - 2014) * 12 + month;
		   
		/* Categorize individuals based on pregnancy and post-partum status */
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
	           case 
	               when b.YEAR_DEATH = a.year and b.MONTH_DEATH = a.month then 1
	               else 0
	           end as death_flag
	    from PREPARED_DATA as a
	    left join deaths_filtered as b
	    on a.ID = b.ID
	    ;
	quit;
	
	data PREPARED_DATA;
	    set PREPARED_DATA;
	    retain death_flag_forward 0;
	    by ID;
	    
	    if death_flag = 1 then death_flag_forward = 1;
	    
	    if first.ID then death_flag_forward = death_flag;
	    
	    death_flag = death_flag_forward;
	    
	    drop death_flag_forward;
	run;
	
	data PREPARED_DATA;
	    set PREPARED_DATA;
	    if death_flag = 1 then delete;
	run;
	
	proc sort data=PREPARED_DATA;
		by ID year month;
	run;
	
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
               cov.IDU_EVIDENCE
        FROM PREPARED_DATA AS a
        LEFT JOIN FINAL_COHORT AS cov 
        ON a.ID = cov.ID;
    QUIT;
	
	DATA PREPARED_DATA;
	    SET PREPARED_DATA;
		    
	    age = YEAR(TODAY()) - YOB;
		    
	    age_grp = PUT(age, age_grps_five.); 
	RUN;
	
%mend;

/*=============================*/
/*  Part 3: MOUD Regressions   */
/*=============================*/

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
	
DATA PERIOD_SUMMARY_FINAL;
    SET PERIOD_SUMMARY_FINAL;
		    
	    /* Calculate the age using the current year dynamically */
    age = YEAR(TODAY()) - YOB;
		    
	    /* Apply the format to create the age_grp variable */
    age_grp = PUT(age, age_grps_five.); 
RUN;

proc sql;
    create table PREPARED_DATA as
    SELECT *
    from PREPARED_DATA
    where moud_flag = 1;
quit;

proc means data=PREPARED_DATA mean median min max std;
   var moud_duration;
run;

proc sort data=PREPARED_DATA;
	by group;
run;

proc means data=PREPARED_DATA mean median min max std;
	by group;
    var moud_duration;
run;

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
proc means data=summed_data mean std min max q1 median q3;
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

%calculate_rates(age_grp, 'Moud Cessation by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Moud Cessation by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Moud Cessation by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Moud Cessation by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Moud Cessation by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(FOREIGN_BORN, 'Moud Cessation by Pregnancy Group, Stratified by FOREIGN_BORN');
%calculate_rates(IDU_EVIDENCE, 'Moud Cessation by Pregnancy Group, Stratified by IDU_EVIDENCE');
title;

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

proc freq data=PREPARED_DATA;
    tables OUD_YEAR OUD_MONTH / missing;
run;

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

    retain censor_init eligible_init censor_reinit moud_reinit eligible_reinit moud_primaryinit;

    /* Reset for a new ID */
    if first.ID then do;
        eligible_init = 1;  /* Start counting person-time */
        censor_init = 0;
        censor_reinit = 0;    /* Reset reinitiation flag */
        moud_reinit = 0; /* Temporary flag to track the reset */
        eligible_reinit = 0;  /* Initialize eligible_reinit */
        moud_primaryinit = 0; /* Initialize moud_primaryinit */
    end;

    /* Censor at first occurrence of moud_init = 1 */
    if moud_init = 1 then censor_init = 1;
    
    /* Only count person-time before censorship */
    if censor_init = 1 then eligible_init = 0;

    /* Set reinitiation flag only for the month when moud_init = 1 */
    if moud_init = 1 and lag(eligible_init) = 0 and moud_reinit = 0 then do;
        censor_reinit = 1;  /* Set reinitiation flag for the month */
        moud_reinit = 1;  /* Set the flag to prevent further reinitiation */
    end;
    
    /* Reset moud_reinit once the reinitiation is flagged for the month */
    if moud_init = 0 then moud_reinit = 0;

    /* Set eligible_reinit = 1 when moud_cessation is flagged */
    if moud_cessation = 1 then eligible_reinit = 1;

    /* Set eligible_reinit = 0 when moud_reinit is flagged */
    if moud_reinit = 1 then eligible_reinit = 0;

    /* Set moud_primaryinit = 1 for the first occurrence of moud_init = 1 */
    if moud_init = 1 and lag(eligible_init) = 1 and moud_primaryinit = 0 then do;
        moud_primaryinit = 1;  /* Set the flag for the first occurrence */
    end;
    
    /* Reset moud_reinit once the reinitiation is flagged for the month */
    if moud_init = 0 then moud_primaryinit = 0;

run;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        sum(eligible_init) as eligible_init,
        sum(eligible_reinit) as eligible_reinit
    from PREPARED_DATA
    group by ID, group;
quit;
	
proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          group,
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
	
DATA PERIOD_SUMMARY_FINAL;
    SET PERIOD_SUMMARY_FINAL;
		    
	    /* Calculate the age using the current year dynamically */
    age = YEAR(TODAY()) - YOB;
		    
	    /* Apply the format to create the age_grp variable */
    age_grp = PUT(age, age_grps_five.); 
RUN;

proc sql;
    create table summed_data as
    select 
        ID,
        sum(eligible_init) as total_person_time_init,
        sum(eligible_reinit) as total_person_time_reinit
    from 
        PERIOD_SUMMARY_FINAL
    group by 
        ID;
quit;

title "Summary statistics for Overall Follow-up Time";
proc means data=summed_data mean std min max q1 median q3;
    var total_person_time_init total_person_time_reinit;
run;

title 'Moud Initiation by Pregnancy Group, Overall';
proc sql;
    select 
        group,
        count(*) as total_n,
        sum(moud_primaryinit) as moud_primaryinit,
        sum(eligible_init) as eligible_init,
        calculated moud_primaryinit / calculated eligible_init as moud_primaryinit_rate format=8.4,
        (calculated moud_primaryinit - 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_lower format=8.4,
        (calculated moud_primaryinit + 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_upper format=8.4,
        
        sum(moud_reinit) as moud_reinit,
        sum(eligible_init) as eligible_init,
        calculated moud_reinit / calculated eligible_init as moud_reinit_rate format=8.4,
        (calculated moud_reinit - 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_init as moud_reinit_rate_lower format=8.4,
        (calculated moud_reinit + 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_init as moud_reinit_rate_upper format=8.4
        
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
        sum(moud_primaryinit) as moud_primaryinit,
        sum(eligible_init) as eligible_init,
        calculated moud_primaryinit / calculated eligible_init as moud_primaryinit_rate format=8.4,
        (calculated moud_primaryinit - 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_lower format=8.4,
        (calculated moud_primaryinit + 1.96 * sqrt(calculated moud_primaryinit)) / calculated eligible_init as moud_primaryinit_rate_upper format=8.4,
        
        sum(moud_reinit) as moud_reinit,
        sum(eligible_init) as eligible_init,
        calculated moud_reinit / calculated eligible_init as moud_reinit_rate format=8.4,
        (calculated moud_reinit - 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_init as moud_reinit_rate_lower format=8.4,
        (calculated moud_reinit + 1.96 * sqrt(calculated moud_reinit)) / calculated eligible_init as moud_reinit_rate_upper format=8.4
        
    from PERIOD_SUMMARY_FINAL
    group by group, &group_by_vars;
quit;
%mend calculate_rates;

%calculate_rates(age_grp, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(FOREIGN_BORN, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by FOREIGN_BORN');
%calculate_rates(IDU_EVIDENCE, 'Moud Initiation and Reinitiation by Pregnancy Group, Stratified by IDU_EVIDENCE');
title;

/*=============================*/
/*  Part 4: Overdose Episodes  */
/*=============================*/

/*====================*/
/* 1. Prepare Overdose Data */
/*====================*/
/* This section prepares the overdose data by selecting relevant variables from the source dataset 
   and ensures that only the necessary columns are retained. The dataset is then sorted by ID and overdose date (OD_DATE) to organize the data for further analysis. */

DATA overdose;
    SET PHDSPINE.OVERDOSE;
    KEEP ID OD_MONTH OD_YEAR OD_DATE FATAL_OD_DEATH OD_COUNT;  /* Retain only the required columns for further analysis */
RUN;

/* Sorting the overdose data by ID and OD_DATE */
PROC SORT data=overdose; 
    BY ID OD_DATE;  /* Sorting by ID ensures that the data for each individual is in order by date */
RUN;

/*====================*/
/* 2. Create Episode Numbers */
/*====================*/
/* This step assigns an episode number to each overdose event for each individual. The episode number is initialized to 1 for the first record and incremented for subsequent records within the same ID. 
   A new variable, 'episode_id', is created by concatenating the individual ID and the episode number to uniquely identify each episode. */

DATA overdose;
    SET overdose;
    by ID OD_DATE;  /* Ensure that the data is processed in order for each ID */
    retain episode_num;  /* Retain the episode_num variable across rows for each ID */

    /* Initialize the episode number for the first occurrence of each ID */
    if first.ID then episode_num = 1; 
    else episode_num + 1;  /* Increment the episode number for subsequent rows */

    /* Create episode_id by concatenating ID and episode_num */
    episode_id = catx("_", ID, episode_num);
    
    drop episode_num;  /* Drop episode_num as it's no longer needed after creating episode_id */
RUN;

/* Sorting the data again by the newly created episode_id for future analysis */
PROC SORT data=overdose; 
    BY EPISODE_ID;  /* Sort by episode_id for efficient access */
RUN;

/*==========================*/
/* 3. Filter by Year and ID */
/*==========================*/
/* Filter the overdose data to keep only records from the year 2014 and onwards, ensuring the analysis is limited to more recent data. */

data overdose;
    set overdose;
    where OD_YEAR >= 2014;  /* Filter for overdose events occurring from 2014 onwards */
run;

PROC SQL;
    CREATE TABLE overdose AS 
    SELECT * 
    FROM overdose
    WHERE ID IN (SELECT DISTINCT ID FROM oud_distinct);
QUIT;

/*====================*/
/* 4. Identify Missing IDs in MOUD Data */
/*====================*/
/* This SQL procedure identifies individuals (IDs) who appear in the pregnancy data (oud_preg) but do not have corresponding entries in the MOUD data, 
   helping to identify records that may require further attention or imputation. */

proc sql;
   create table missing_ids as
   select a.ID
   from oud_preg as a
   where not exists (select 1 from moud as b where a.ID = b.ID);  /* Select IDs with no match in MOUD dataset */
quit;

/*====================*/
/* 5. Merge Missing IDs into Overdose Data */
/*====================*/
/* The next step merges the missing IDs into the overdose data, where a placeholder value (".") is assigned to the episode_id for these missing records. 
   This ensures that all IDs are accounted for in the dataset, even if no MOUD data is available. */

DATA overdose_full;
    SET overdose;  /* Keep all original overdose data */
RUN;

proc sql;
   insert into overdose_full (ID, episode_id)
   select ID, "."  /* Insert placeholder for missing IDs */
   from missing_ids;
quit;

/*====================*/
/* 8. Sort Data for Analysis */
/*====================*/
/* Sorting the overdose dataset by ID, OD_YEAR, and OD_MONTH to facilitate time-series analysis and ensure chronological order of overdose events. */

PROC SORT DATA=overdose_full;
by ID OD_YEAR OD_MONTH;  /* Sorting by ID and date variables to maintain chronological order */
run;

/*====================*/
/* 9. Create OD Table */
/*====================*/
/* This SQL procedure creates an initial table, combining the overdose data with month and year information. The table is used to track overdose flags for each month/year combination. */

PROC SQL;
    CREATE TABLE od_table AS
    SELECT * FROM overdose_full, months, years;  /* Create the basic table structure, merging with month and year variables */
QUIT;

/*====================*/
/* 10. Flag Overdoses by Month-Year Combination */
/*====================*/
/* This step creates an "od_flag" variable indicating whether a particular overdose event matches a given month and year. The flag is set to 1 if there's a match, otherwise 0. */

data od_table;
    set od_table;
    if OD_MONTH = month and OD_YEAR = year then od_flag = 1;  /* Flag overdose events for the exact month/year combination */
    else od_flag = 0;  /* Flag as 0 if no match */
run;

/*====================*/
/* 11. Flag Fatal Overdoses */
/*====================*/
/* This step creates a "fod_flag" variable to flag fatal overdoses. The flag is set to 1 for fatal overdoses (FATAL_OD_DEATH = 1) and 0 otherwise. */

data od_table;
    set od_table;
    if OD_MONTH = month and OD_YEAR = year and FATAL_OD_DEATH = 1 then fod_flag = 1;  /* Flag fatal overdoses for the exact month/year combination */
    else fod_flag = 0;  /* Flag as 0 if no match or non-fatal overdose */
run;

proc sort data=od_table;
by ID;
run;

data od_table;
    set od_table;
    by ID;
    
    /* If a fatal overdose is found, delete all rows after for that ID */
    retain censor_fod 0;  /* Track whether a fatal overdose has occurred */
   
    if first.ID then do;
      censor_fod = 0; 
    end;
    
    if fod_flag = 1 then censor_fod = 1;  /* Set flag when a fatal overdose is encountered */
    
    /* Delete all subsequent rows for this ID after a fatal overdose, except the one with fod_flag = 1 */
    if censor_fod = 1 and fod_flag = 0 then delete;  /* Corrected condition */
   
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

proc freq data=od_table;
    tables OUD_YEAR OUD_MONTH / missing;
run;

proc sql;
    create table od_table as
    select *
    from od_table
    where (YEAR > oud_year) 
        or (YEAR = oud_year and MONTH >= oud_month)
    order by ID, YEAR, MONTH;
quit;

/*====================*/
/* 12. Sort Final OD Table */
/*====================*/
/* Sorting the final overdose table by ID, year, and month, and keeping only relevant variables for further analysis. */

proc sort data=od_table;
    by ID year month;  /* Sort by ID and month-year for chronological analysis */
run;

/*====================*/
/* 13. Merge Pregnancy Flags with OD Data */
/*====================*/
/* Merge pregnancy flags with the overdose data. For any month/year combination, if a pregnancy flag exists, it's added to the table, otherwise the flag is set to a default value (9999). */

proc sql;
    create table od_table as
    select a.*, 
           case when b.flag is not null then b.flag 
                else 9999 end as preg_flag  /* Add pregnancy flag, defaulting to 9999 if missing */
    from od_table a
    left join pregnancy_flags b
    on a.ID = b.ID 
       and a.month = b.month 
       and a.year = b.year;
quit;

/*====================*/
/* 14. Summarize MOUD Flag for Each Month-Year */
/*====================*/
/* This step reduces the dataset to unique ID-month-year combinations and retains the maximum MOUD flag value for each combination. */

proc sql;
    create table moud_summary as
    select distinct
        ID,
        month,
        year,
        max(moud_flag) as moud_flag  /* Retain the maximum MOUD flag for each ID-month-year combination */
    from moud_summary
    group by ID, month, year;
quit;

/*====================*/
/* 15. Reduce Post-Treatment Flag for Each Month-Year */
/*====================*/
/* Similar to the MOUD flag, we reduce the spine data to distinct ID-month-year combinations, keeping the maximum post-treatment flag for each combination. */

proc sql;
    create table moud_spine_posttxt as
    select distinct
        ID,
        month,
        year,
        max(posttxt_flag) as posttxt_flag  /* Keep maximum post-treatment flag for each month/year */
    from moud_spine_posttxt
    group by ID, month, year;
quit;

/*====================*/
/* 16. Merge MOUD and Post-Treatment Flags with OD Data */
/*====================*/
/* This final merge combines both the MOUD and post-treatment flags with the overdose data, ensuring that missing flags are replaced with default values (0) where applicable. */

proc sql;
    create table od_table_full as
    select a.*, 
           coalesce(b.moud_flag, 0) as moud_flag,  /* Use coalesce to replace missing MOUD flags with 0 */
           coalesce(c.posttxt_flag, 0) as posttxt_flag  /* Use coalesce to replace missing post-treatment flags with 0 */
    from od_table a
    left join moud_summary b 
    on a.ID = b.ID and a.month = b.month and a.year = b.year
    left join moud_spine_posttxt c
    on a.ID = c.ID and a.month = c.month and a.year = c.year;
quit;

/*=============================*/
/*  Part 5: Overdose Regressions by Pregnancy and Treatment */
/*=============================*/

/*====================*/
/* 1. Prepare Data for Analysis */
/*====================*/
/* This step prepares the data by creating a unique time index based on the month and year, 
   and categorizes individuals into different groups based on pregnancy and post-partum status. 
   The 'group' variable is used to distinguish between different states, such as pregnant, post-partum, and non-pregnant. */

data prepared_data;
    set od_table_full;

    /* Create a unique time index based on year and month */
    time_index = (year - 2014) * 12 + month; /* Convert year and month into a unique index starting from 2014 */
   
    /* Categorize individuals based on pregnancy and post-partum status */
    if preg_flag = 1 then group = 1; /* Pregnant */
    else if preg_flag = 2 then group = 2; /* 0-6 months post-partum */
    else if preg_flag = 3 then group = 2; /* 7-12 months post-partum */
    else if preg_flag = 4 then group = 3; /* 13-18 months post-partum */
    else if preg_flag = 5 then group = 3; /* 19-24 months post-partum */
    else if preg_flag = 9999 then group = 0; /* Non-pregnant */
   
    /* Categorize individuals based on MOUD and post-treatment flags */
    if moud_flag = 1 then treat_group = 1; /* On MOUD */
    else if moud_flag = 0 and posttxt_flag = 1 then treat_group = 2; /* Post-TXT */
    else if moud_flag = 0 and posttxt_flag = 0 then treat_group = 0; /* No MOUD */
   
run;

/* Reduce from EPISODE_LEVEL to PERSON_LEVEL */
PROC SORT DATA=prepared_data;
BY ID YEAR MONTH;
RUN;

proc sql;
   create table PREPARED_DATA as
   select distinct
      ID, 
      YEAR, 
      MONTH,
      group,
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
           case 
               when b.YEAR_DEATH = a.year and b.MONTH_DEATH = a.month then 1
               else 0
           end as death_flag
    from PREPARED_DATA as a
    left join deaths_filtered as b
    on a.ID = b.ID
    ;
quit;
	
data PREPARED_DATA;
    set PREPARED_DATA;
    retain death_flag_forward 0;
    by ID;
    
    if death_flag = 1 then death_flag_forward = 1;
    
    if first.ID then death_flag_forward = death_flag;
    
    death_flag = death_flag_forward;
	    
    drop death_flag_forward;
run;
	
data PREPARED_DATA;
    set PREPARED_DATA;
    if death_flag = 1 then delete;
run;
	
proc sort data=PREPARED_DATA;
	by ID year month;
run;
	
proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        group,
        count(month) as person_time
    from PREPARED_DATA
    group by ID, group;
quit;

proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          group,
          sum(od_flag) as overdoses,
          sum(fod_flag) as fatal_overdoses
   from PREPARED_DATA
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
	
DATA PERIOD_SUMMARY_FINAL;
    SET PERIOD_SUMMARY_FINAL;
		    
	    /* Calculate the age using the current year dynamically */
    age = YEAR(TODAY()) - YOB;
		    
	    /* Apply the format to create the age_grp variable */
    age_grp = PUT(age, age_grps_five.); 
RUN;

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

%calculate_rates(age_grp, 'Overdoses by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Overdoses by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Overdoses by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Overdoses by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Overdoses by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(FOREIGN_BORN, 'Overdoses by Pregnancy Group, Stratified by FOREIGN_BORN');
%calculate_rates(IDU_EVIDENCE, 'Overdoses by Pregnancy Group, Stratified by IDU_EVIDENCE');
title;

proc sql;
    create table PERSON_TIME as
    select 
        ID, 
        treat_group,
        count(month) as person_time
    from PREPARED_DATA
    group by ID, treat_group;
quit;
	
proc sql;
   create table PERIOD_SUMMARY as
   select ID,
          treat_group,
          sum(od_flag) as overdoses,
          sum(fod_flag) as fatal_overdoses
   from PREPARED_DATA
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
	
DATA PERIOD_SUMMARY_FINAL;
    SET PERIOD_SUMMARY_FINAL;
		    
	    /* Calculate the age using the current year dynamically */
    age = YEAR(TODAY()) - YOB;
		    
	    /* Apply the format to create the age_grp variable */
    age_grp = PUT(age, age_grps_five.); 
RUN;

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

%calculate_rates(age_grp, 'Overdoses by Pregnancy Group, Stratified by Age');
%calculate_rates(FINAL_RE, 'Overdoses by Pregnancy Group, Stratified by FINAL_RE');
%calculate_rates(EDUCATION, 'Overdoses by Pregnancy Group, Stratified by EDUCATION');
%calculate_rates(HOMELESS_HISTORY_GROUP, 'Overdoses by Pregnancy Group, Stratified by HOMELESS_HISTORY_GROUP');
%calculate_rates(EVER_INCARCERATED, 'Overdoses by Pregnancy Group, Stratified by EVER_INCARCERATED');
%calculate_rates(FOREIGN_BORN, 'Overdoses by Pregnancy Group, Stratified by FOREIGN_BORN');
%calculate_rates(IDU_EVIDENCE, 'Overdoses by Pregnancy Group, Stratified by IDU_EVIDENCE');
title;

title 'Overdoses, Overall';
proc sql;
    select 
        sum(overdoses) as overdoses,
        sum(fatal_overdoses) as fatal_overdoses,
        sum(person_time) as total_person_time
    from PERIOD_SUMMARY_FINAL;
quit;
