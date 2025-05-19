/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 4/27/2023 			*/
/* Updated: 12/30/2024   		*/
/*==============================*/
/* 
Overall, the logic behind the known capture is fairly simple: 
search through individual databases and flag if an ICD9, ICD10, 
CPT, NDC, or other specialized code matches our lookup table. 
If a record has one of these codes, it is 'flagged' for OUD. 
The utilized databases are then joined onto the SPINE demographics 
dataset and if the sum of flags is greater than zero, then the 
record is flagged with OUD.  
At current iteration, data being pulled through this method is 
stratified by Year (or Year and Month), Race, Sex, and Age 
(where age groups are defined in the table below).
*/
/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
%LET year = (2015:2022);
%LET MOUD_leniency = 30;
%LET DOC_leniency = 35;
%LET today = %sysfunc(today(), date9.);
%LET formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

/*===========AGE================*/
PROC FORMAT;
	VALUE age_grps_five
		low-5 = '1' 6-10 = '2'
		11-15 = '3' 16-20 = '4'
		21-25 = '5' 26-30 = '6'
		31-35 = '7' 36-40 = '8'
		41-45 = '9' 46-50 = '10'
		51-55 = '11' 56-60 = '12'
		61-65 = '13' 66-70 = '14'
		71-75 = '15' 76-80 = '16'
		81-85 = '17' 86-90 = '18'
		91-95 = '19' 96-998 = '20'
		999 = '999';

PROC FORMAT;
    VALUE age_grps_twenty
    low-20 = '1' 21-40 = '2'
    41-60 = '3' 61-80 = '4'
    81-998 = '5' 999 = '999';

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
	    'T40691D','T40692D','T40693D','T40694D', /* Overdose Codes */ 
	    'F1193','F1199'/* Additional RESPOND */);
           
%LET PROC = ('G2067','G2068','G2069','G2070', 
	    'G2071','G2072','G2073','G2074', 
	    'G2075', /* MAT Opioid */
	    'G2076','G2077','G2078','G2079', 
	    'G2080','G2081', /*Opioid Trt */
 	    'J0570','J0571','J0572','J0573', 
 	    'J0574','J0575','J0592','S0109', 
        'G2215','G2216','G1028', /* Naloxone*/
        'Q9991','Q9992','H0020','HZ81ZZZ','HZ91ZZZ');

%LET bsas_drugs = (5,6,7,21,22,23,24,26);

/* 
Take NDC codes where buprenorphine has been identified,
insert them into BUP_NDC as a macro variable 
*/
PROC SQL;
    CREATE TABLE ndc AS
    SELECT DISTINCT NDC 
    FROM PHDPMP.PMP
    WHERE BUP_CAT_PMP = 1;
QUIT;

PROC SQL noprint;
    SELECT quote(trim(ndc), "'") into :BUP_NDC separated by ','
    FROM ndc;
QUIT;
            
/*===============================*/            
/*			DATA PULL			 */
/*===============================*/ 
/*======DEMOGRAPHIC DATA=========*/
/* 
Using data from DEMO, take the cartesian coordinate of years
(as defined above) and months 1:12 to construct a shell table
*/
DATA demographics;
    SET PHDSPINE.DEMO (KEEP= ID FINAL_RE FINAL_SEX YOB);
    IF FINAL_RE = 9 THEN DELETE;
    IF FINAL_RE = 99 THEN DELETE;

    IF FINAL_SEX = 9 THEN DELETE;
    IF FINAL_SEX = 99 THEN DELETE;
RUN;

%let start_year=%scan(%substr(&year,2,%length(&year)-2),1,':');
%let end_year=%scan(%substr(&year,2,%length(&year)-2),2,':');

DATA months; DO month = 1 to 12; OUTPUT; END; RUN;
DATA years; DO year = &start_year to &end_year; OUTPUT; END; RUN;

PROC SQL;
    CREATE TABLE demographics_monthly AS
    SELECT * FROM demographics, months, years;
QUIT;

PROC SQL;
    CREATE TABLE demographics_yearly AS
    SELECT * FROM demographics, years;
QUIT;

/*=========APCD DATA=============*/
/* 
The APCD consists of the Medical and Pharmacy Claims datasets and, 
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
then our `OUD_PHARM` flag is set to 1.
*/
DATA apcd (KEEP= ID oud_apcd year_apcd month_apcd);
	SET PHDAPCD.MEDICAL (KEEP= ID MED_ECODE MED_ADM_DIAGNOSIS
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
		IF icd_fields[i] IN &ICD THEN cnt_oud_apcd = cnt_oud_apcd + 1;
	END;
	
    DO j = 1 TO dim(proc_fields);
        IF proc_fields[j] IN &PROC THEN cnt_oud_apcd = cnt_oud_apcd + 1;
    END;

	IF cnt_oud_apcd > 0 THEN oud_apcd = 1;
	IF oud_apcd = 0 THEN DELETE;

	year_apcd = MED_FROM_DATE_YEAR;
    month_apcd = MED_FROM_DATE_MONTH;
    DROP i j;
RUN;

DATA pharm (KEEP= year_pharm month_pharm oud_pharm ID);
    SET PHDAPCD.PHARMACY(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);
    month_pharm = PHARM_FILL_DATE_MONTH;
    year_pharm = PHARM_FILL_DATE_YEAR;

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;

    IF oud_pharm = 0 THEN DELETE;
RUN;

/*======CASEMIX DATA==========*/
/* 
### Emergency Department
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
than one then our `OUD_CM_OO` flag is set to 1.
*/

/* ED */
DATA casemix_ed (KEEP= ID oud_cm_ed ED_ID year_cm month_cm);
	SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
				  WHERE= (ED_ADMIT_YEAR IN &year));
	IF ED_DIAG1 in &ICD OR 
        ED_PRINCIPLE_ECODE IN &ICD THEN oud_cm_ed = 1;
	ELSE oud_cm_ed = 0;
	
	year_cm = ED_ADMIT_YEAR;
    month_cm = ED_ADMIT_MONTH;
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

DATA casemix (KEEP= ID oud_ed year_cm age_ed month_cm);
	SET casemix;
	IF SUM(oud_cm_ed_proc, oud_cm_ed_diag, oud_cm_ed) > 0 THEN oud_ed = 1;
	ELSE oud_ed = 0;
	
	IF oud_ed = 0 THEN DELETE;
RUN;

/* HD DATA */
DATA hd (KEEP= HD_ID ID oud_hd_raw year_hd month_hd);
	SET PHDCM.HD (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH HD_ECODE
					WHERE= (HD_ADMIT_YEAR IN &year));
	IF HD_DIAG1 in &ICD OR
     HD_PROC1 in &PROC OR
     HD_ECODE IN &ICD THEN oud_hd_raw = 1;
	ELSE oud_hd_raw = 0;

    year_hd = HD_ADMIT_YEAR;
    month_hd = HD_ADMIT_MONTH;
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

/* OO */
DATA oo (KEEP= ID oud_oo year_oo month_oo);
    SET PHDCM.OO (KEEP= ID OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4
                        OO_ADMIT_YEAR OO_ADMIT_MONTH
                        OO_CPT1-OO_CPT10
                        OO_PRINCIPALEXTERNAL_CAUSECODE
                    WHERE= (OO_ADMIT_YEAR IN &year));
	cnt_oud_oo = 0;
    ARRAY vars2 {*} OO_DIAG1-OO_DIAG16 
                    OO_PROC1-OO_PROC4
                    OO_CPT1-OO_CPT10
                    OO_PRINCIPALEXTERNAL_CAUSECODE;

    DO k = 1 TO dim(vars2);
        IF SUBSTR(VNAME(vars2[k]), 1) in ('OO_PROC', 'OO_CPT') THEN DO; 
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

/* MERGE ALL CM */
/* Perform full join for all casemix tables */
PROC SQL;
    CREATE TABLE casemix AS
    SELECT *
    FROM casemix
    FULL JOIN hd ON casemix.ID = hd.ID
		AND casemix.year_cm = hd.year_hd
        AND casemix.month_cm = hd.month_hd
    FULL JOIN oo ON hd.ID = oo.ID
		AND casemix.year_cm = oo.year_oo
        AND casemix.month_cm = oo.month_oo;
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
RUN;

/* BSAS */
/* 
Like Matris, the BSAS dataset involves some PHD level encoding. 
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
8. 26: Fentanyl
*/
DATA bsas (KEEP= ID oud_bsas year_bsas month_bsas);
    SET PHDBSAS.BSAS (KEEP= ID CLT_ENR_OVERDOSES_LIFE
                             CLT_ENR_PRIMARY_DRUG
                             CLT_ENR_SECONDARY_DRUG
                             CLT_ENR_TERTIARY_DRUG
                             PDM_PRV_SERV_CAT
                             ENR_YEAR_BSAS 
                             ENR_MONTH_BSAS
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

/* MATRIS */
/* 
The MATRIS Dataset depends on PHD level encoding of variables 
`OPIOID_ORI_MATRIS` and `OPIOID_ORISUBCAT_MATRIS` to 
construct our flag variable, `OUD_MATRIS`.
*/
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

/* DEATH */
/* 
The Death dataset holds the official cause and manner of 
death assigned by physicians and medical examiners. For our 
purposes, we are only interested in the variable `OPIOID_DEATH` 
which is based on 'ICD10 codes or literal search' from other 
PHD sources.
*/
DATA death (KEEP= ID oud_death year_death month_death);
    SET PHDDEATH.DEATH (KEEP= ID OPIOID_DEATH YEAR_DEATH AGE_DEATH
                        WHERE= (YEAR_DEATH IN &year));
    IF OPIOID_DEATH = 1 THEN oud_death = 1;
    ELSE oud_death = 0;
    IF oud_death = 0 THEN DELETE;

	year_death = YEAR_DEATH;
    month_death = MONTH_DEATH;
RUN;

/* PMP */
/* 
Within the PMP dataset, we only use the `BUPRENORPHINE_PMP` 
to define the flag `OUD_PMP` - conditioned on BUP_CAT_PMP = 1.
*/
DATA pmp (KEEP= ID oud_pmp year_pmp month_pmp);
    SET PHDPMP.PMP (KEEP= ID BUPRENORPHINE_PMP date_filled_year date_filled_month BUP_CAT_PMP
                    WHERE= (date_filled_year IN &year));
    IF BUPRENORPHINE_PMP = 1 AND 
        BUP_CAT_PMP = 1 THEN oud_pmp = 1;
    ELSE oud_pmp = 0;
    IF oud_pmp = 0 THEN DELETE;

	year_pmp = date_filled_year;
    month_pmp = date_filled_month;
RUN;

/*===========================*/
/*      MAIN MERGE           */
/*===========================*/
/* 
As a final series of steps:
1. APCD-Pharm, APCD-Medical, Casemix, Death, PMP, Matris, 
   BSAS are joined together on the cartesian coordinate of Months 
   (1:12), Year (2015:2021), and SPINE (Race, Sex, ID)
2. The sum of the fabricated flags is taken. If the sum is strictly
   greater than zero, then the master flag is set to 1. 
   Zeros are deleted
4. We select distinct ID, Age Bins, Race, Year, and Month and 
   output the count of those detected with OUD
5. Any count that is between 1 and 10 are suppressed and set to -1,
   any zeros are true zeros
*/
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

    CREATE TABLE oud_monthly AS
    SELECT * FROM demographics_monthly
    LEFT JOIN apcd ON apcd.ID = demographics_monthly.ID
        AND apcd.year_apcd = demographics_monthly.year
        AND apcd.month_apcd = demographics_monthly.month
    LEFT JOIN casemix ON casemix.ID = demographics_monthly.ID
		AND casemix.year_cm = demographics_monthly.year
        AND casemix.month_cm = demographics_monthly.month
    LEFT JOIN bsas ON bsas.ID = demographics_monthly.ID
        AND bsas.year_bsas = demographics_monthly.year
        AND bsas.month_bsas = demographics_monthly.month
    LEFT JOIN matris ON matris.ID = demographics_monthly.ID
		AND matris.year_matris = demographics_monthly.year
        AND matris.month_matris = demographics_monthly.month
    LEFT JOIN death ON death.ID = demographics_monthly.ID
        AND death.year_death = demographics_monthly.year
        AND death.month_death = demographics_monthly.month
    LEFT JOIN pmp ON pmp.ID = demographics_monthly.ID
		AND pmp.year_pmp = demographics_monthly.year
        AND pmp.month_pmp = demographics_monthly.month
    LEFT JOIN pharm ON pharm.ID = demographics_monthly.ID
        AND pharm.year_pharm = demographics_monthly.year
        AND pharm.month_pharm = demographics_monthly.month;

    CREATE TABLE oud_yearly AS
    SELECT * FROM demographics_yearly
    LEFT JOIN apcd ON apcd.ID = demographics_yearly.ID
        AND apcd.year_apcd = demographics_yearly.year
    LEFT JOIN casemix ON casemix.ID = demographics_yearly.ID
		AND casemix.year_cm = demographics_yearly.year
    LEFT JOIN bsas ON bsas.ID = demographics_yearly.ID
        AND bsas.year_bsas = demographics_yearly.year
    LEFT JOIN matris ON matris.ID = demographics_yearly.ID
		AND matris.year_matris = demographics_yearly.year
    LEFT JOIN death ON death.ID = demographics_yearly.ID
        AND death.year_death = demographics_yearly.year
    LEFT JOIN pmp ON pmp.ID = demographics_yearly.ID
		AND pmp.year_pmp = demographics_yearly.year
    LEFT JOIN pharm ON pharm.ID = demographics_yearly.ID
        AND pharm.year_pharm = demographics_yearly.year;

    CREATE TABLE oud_yearly AS
    SELECT DISTINCT * 
    FROM oud_yearly;
QUIT;

PROC STDIZE DATA = oud_monthly OUT = oud_monthly reponly missing = 9999; RUN;
PROC STDIZE DATA = oud_yearly OUT = oud_yearly reponly missing = 9999; RUN;

DATA oud_monthly;
    SET oud_monthly;

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

	age = year - YOB;
    age_grp_five = put(age, age_grps_five.);
    age_grp_twenty = put(age, age_grps_twenty.);
RUN;

DATA oud_yearly;
    SET oud_yearly;

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

    age = year - YOB;
    age_grp_five = put(age, age_grps_five.);
    age_grp_twenty = put(age, age_grps_twenty.);
RUN;

PROC SQL;
    CREATE TABLE oud_out_yearly AS 
    SELECT DISTINCT year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY year;

    CREATE TABLE oud_out_monthly AS 
    SELECT DISTINCT year, month,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY year, month;

    CREATE TABLE oud_five_yearly AS
    SELECT DISTINCT age_grp_five, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY age_grp_five, year, FINAL_SEX, FINAL_RE;

    CREATE TABLE oud_twenty_yearly AS
    SELECT DISTINCT age_grp_twenty, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY age_grp_twenty, year;

    CREATE TABLE oud_five_monthly AS
    SELECT DISTINCT age_grp_five, year, month,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY age_grp_five, year, month;

    CREATE TABLE oud_twenty_monthly AS
    SELECT DISTINCT age_grp_twenty, year, month,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY age_grp_twenty, year, month;

    CREATE TABLE oud_sex_yearly AS
    SELECT DISTINCT year, FINAL_SEX,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY year, FINAL_SEX;

    CREATE TABLE oud_sex_monthly AS
    SELECT DISTINCT year, month, FINAL_SEX,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY year, month, FINAL_SEX;

    CREATE TABLE oud_race_yearly AS
    SELECT DISTINCT year, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY year, FINAL_RE;

    CREATE TABLE oud_race_monthly AS
    SELECT DISTINCT year, month, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY year, month, FINAL_RE;
QUIT;

PROC EXPORT
	DATA= oud_out_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_out_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_five_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Five_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_twenty_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Twenty_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_five_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Five_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_twenty_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Twenty_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_sex_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Sex_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_sex_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Sex_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_race_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Race_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_race_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Race_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/* Data Origin Location */
/* 
Data used by the Capture Re-Capture Method (CRC) is pulled from 
the Public Health Data Warehouse (PHDW) and is non-stratified. 
This data details how many people are within the combination of
databases we pull from. For example, a row detailing '1' in the 
APCD and Casemix column would indicate that 'x' people in the 
N_ID column were 'captured' in both APCD and Casemix in the time
of interest (a given year.) This extends to all six of the 
databases we currently pull from.
*/
PROC SQL;
    CREATE TABLE oud_origin_five AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death,
                    year,
                    age_grp_five,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, year, age_grp_five;

    CREATE TABLE oud_origin_twenty AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death,
                    year,
                    age_grp_twenty,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, year, age_grp_twenty;

    CREATE TABLE oud_origin_race AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death,
                    FINAL_RE, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, year, FINAL_RE;

    CREATE TABLE oud_origin_sex AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death,
                    FINAL_SEX, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, year, FINAL_SEX;

    CREATE TABLE oud_origin AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, year;
QUIT;

PROC EXPORT
	DATA= oud_origin
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_origin_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_origin_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_Twenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_origin_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_Race_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_origin_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_Sex_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/*==============================*/
/*         MOUD Counts          */
/*==============================*/
/* 
The goal of this portion of the script is to extract MOUD counts and 
starts while treating it as a formal subset of the code defined above 
(OUDCounts.) The table most used in this portion is the relatively-new
SPINE.MOUD table. 
MOUD Starts are immediately given through SPINE.MOUD's DATE_START_*_MOUD
MOUD Counts, on the other hand, require a type of 'expansion', where we
create a new dataset filling out the months inbetween DATE_START_*_MOUD and 
DATE_END_*_MOUD.

Restrictions: 
1. If the lapse between a record's end date and the next record's
   start date is < 7, we merge the two records together.
2. After this merge, if there are any more records which are <7 they 
   are removed from counts/starts tabulation
3. If medication A is found to be completely encompassed by another 
   medication B, then we remove the record of medication A.
*/
DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

PROC SQL;    
    CREATE TABLE moud_demo AS
    SELECT moud.DATE_START_MOUD as start_date, moud.DATE_END_MOUD as end_date,
    	   moud.DATE_START_YEAR_MOUD as start_year, moud.DATE_END_YEAR_MOUD as end_year,
    	   moud.DATE_START_MONTH_MOUD as start_month, moud.DATE_END_MONTH_MOUD as end_month,
    	   moud.TYPE_MOUD, DEMO.FINAL_RE, MOUD.ID, DEMO.FINAL_SEX, DEMO.YOB
    FROM moud
    LEFT JOIN PHDSPINE.DEMO ON moud.ID = DEMO.ID;
QUIT;

PROC SORT DATA=moud_demo;
    by ID TYPE_MOUD start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID TYPE_MOUD;
    RETAIN new_start_date new_end_date new_start_month new_start_year 
           new_end_month new_end_year YOB FINAL_RE FINAL_SEX;

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
					  			ID FINAL_RE FINAL_SEX TYPE_MOUD YOB);
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

    age = new_start_year - YOB;
    age_grp_five = put(age, age_grps_five.);
    age_grp_twenty = put(age, age_grps_twenty.);
RUN;

DATA moud_expanded(KEEP= ID month year treatment FINAL_SEX FINAL_RE age_grp_five age_grp_twenty);
    SET moud_demo;
    treatment = TYPE_MOUD;

    FORMAT year 4. month 2.;
    
    num_months = intck('month', input(put(new_start_year, 4.) || put(new_start_month, z2.), yymmn6.), 
                       input(put(new_end_year, 4.) || put(new_end_month, z2.), yymmn6.));

    DO i = 0 to num_months;
      new_date = intnx('month', input(put(new_start_year, 4.) || put(new_start_month, z2.), yymmn6.), i);
      year = year(new_date);
      month = month(new_date);
      postexp_age = year - YOB;
      age_grp_five = put(postexp_age, age_grps_five.);
      age_grp_twenty = put(postexp_age, age_grps_twenty.);
      OUTPUT;
    END;
RUN;

DATA moud_expanded;
	SET moud_expanded;
	WHERE year IN &year;
RUN;

PROC SQL;
    CREATE TABLE moud_expanded AS 
    SELECT DISTINCT * FROM moud_expanded;
QUIT;

PROC SQL;
    CREATE TABLE moud_starts AS
    SELECT new_start_month AS month,
           new_start_year AS year,
           TYPE_MOUD AS treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_start_month, new_start_year, TYPE_MOUD;

    CREATE TABLE moud_starts_five AS
    SELECT new_start_month AS month,
           new_start_year AS year,
           TYPE_MOUD AS treatment,
           age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_start_month, new_start_year, TYPE_MOUD, age_grp_five;

    CREATE TABLE moud_starts_twenty AS
    SELECT new_start_month AS month,
           new_start_year AS year,
           TYPE_MOUD AS treatment,
           age_grp_twenty,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_start_month, new_start_year, TYPE_MOUD, age_grp_twenty;

    CREATE TABLE moud_starts_sex AS
    SELECT new_start_month AS month,
           new_start_year AS year,
           TYPE_MOUD AS treatment,
           FINAL_SEX,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_start_month, new_start_year, TYPE_MOUD, FINAL_SEX;

    CREATE TABLE moud_starts_race AS
    SELECT new_start_month AS month,
           new_start_year AS year,
           TYPE_MOUD AS treatment,
           FINAL_RE,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_start_month, new_start_year, TYPE_MOUD, FINAL_RE;

    CREATE TABLE moud_ends AS
    SELECT new_end_month AS end_month, 
           new_end_year AS end_year, 
           TYPE_moud AS treatment,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_end_month, new_end_year, TYPE_MOUD;

    CREATE TABLE moud_ends_five AS
    SELECT new_end_month AS end_month, 
           new_end_year AS end_year, 
           TYPE_moud AS treatment,
           age_grp_five,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_end_month, new_end_year, TYPE_MOUD, age_grp_five;

    CREATE TABLE moud_ends_twenty AS
    SELECT new_end_month AS end_month, 
           new_end_year AS end_year, 
           TYPE_moud AS treatment,
           age_grp_twenty,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_end_month, new_end_year, TYPE_MOUD, age_grp_twenty;

    CREATE TABLE moud_ends_sex AS
    SELECT new_end_month AS end_month, 
           new_end_year AS end_year, 
           TYPE_moud AS treatment,
           FINAL_SEX,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_end_month, new_end_year, TYPE_MOUD, FINAL_SEX;

    CREATE TABLE moud_ends_race AS
    SELECT new_end_month AS end_month, 
           new_end_year AS end_year, 
           TYPE_moud AS treatment,
           FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY new_end_month, new_end_year, TYPE_MOUD, FINAL_RE;
QUIT;
PROC SQL;
    CREATE TABLE moud_counts AS
    SELECT year, month, treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment;

    CREATE TABLE moud_counts_five AS
    SELECT year, month, treatment, age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, age_grp_five;

    CREATE TABLE moud_counts_twenty AS
    SELECT year, month, treatment, age_grp_twenty,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, age_grp_twenty;

    CREATE TABLE moud_counts_sex AS
    SELECT year, month, treatment, FINAL_SEX,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, FINAL_SEX;

    CREATE TABLE moud_counts_race AS
    SELECT year, month, treatment, FINAL_RE,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, FINAL_RE;

QUIT;

PROC EXPORT
	DATA= moud_counts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCount_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_counts_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCount_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_counts_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCount_Twenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_counts_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCount_Sex_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_counts_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCount_Race_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_Twenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_Sex_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_Race_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_ends
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDEnds_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_ends_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDEnds_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_ends_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDEnds_Twenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_ends_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDEnds_Sex_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_ends_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDEnds_Race_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/*==============================*/
/*  	CORRECTIONS        		*/
/*==============================*/
/*
This portion of the script is designed to take the OUD cohort we've built above
and observe corrections only after someone has been identified as having OUD.
Then, using the department of corrections dates, we build out the times each ID is 
inside of DOC to obtain the counts.

It should be noted that individuals only appear in the DOC database AFTER their release
therefore, we also extract the distribution of time spent inside of a correctional facility 
in order to estimate how many people we may be missing from the data as the date grows closer
to the last date of data available in the PHD
*/
PROC SQL;
	CREATE TABLE monthly_min_date AS 
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX, YOB,
					MIN(INPUT(CAT(year, PUT(month, Z2.)), YYMMN6.)) AS min_date FORMAT = YYMMN6.
	FROM oud_monthly
	GROUP BY ID;

	CREATE TABLE doc_monthly AS
	SELECT DISTINCT doc.ID,
					INPUT(CAT(doc.ADMIT_RECENT_YEAR_DOC, PUT(doc.ADMIT_RECENT_MONTH_DOC, Z2.)), YYMMN6.) AS admission FORMAT=YYMMN6.,
					INPUT(CAT(doc.RELEASE_YEAR_DOC, PUT(doc.RELEASE_MONTH_DOC, Z2.)), YYMMN6.) AS release FORMAT=YYMMN6.,
					coh.min_date, coh.FINAL_RE, coh.FINAL_SEX, coh.YOB,
					doc.RELEASE_DATE_DOC - doc.ADMIT_RECENT_DATE_DOC AS n_days
	FROM PHDDOC.DOC doc
	INNER JOIN monthly_min_date coh ON doc.ID = coh.ID
	WHERE INPUT(CAT(doc.ADMIT_RECENT_YEAR_DOC, PUT(doc.ADMIT_RECENT_MONTH_DOC, Z2.)), YYMMN6.) >= coh.min_date
		  AND doc.RELEASE_DATE_DOC - doc.ADMIT_RECENT_DATE_DOC >= &DOC_leniency;

    CREATE TABLE doc_frq_tmp AS
    SELECT DISTINCT ID, n_days, FINAL_RE, FINAL_SEX,
                    PUT(year(admission) - YOB, age_grps_twenty.) AS age_grp_twenty,
                    PUT(year(admission) - YOB, age_grps_five.) AS age_grp_five
    FROM doc_monthly;
QUIT;

PROC FREQ DATA=doc_frq_tmp;
	TABLES n_days / OUT=doc_length;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES FINAL_RE*n_days / OUT=doc_length_race;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES FINAL_SEX*n_days / OUT=doc_length_sex;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES age_grp_twenty*n_days / OUT=doc_length_twenty;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES age_grp_five*n_days / OUT=doc_length_five;
RUN;

DATA doc_length_twenty(KEEP=n_days COUNT); SET doc_length_twenty; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_five(KEEP=n_days COUNT); SET doc_length_five; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_sex(KEEP=n_days COUNT); SET doc_length_sex; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_race(KEEP=n_days COUNT); SET doc_length_race; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length(KEEP=n_days COUNT); SET doc_length; IF COUNT < 10 THEN COUNT = -1; RUN;

PROC SORT data=doc_monthly;
    by ID admission;
RUN;

DATA doc_monthly;
    SET doc_monthly;
    BY ID;
    RETAIN new_admission new_release YOB FINAL_RE FINAL_SEX;

    IF FIRST.ID THEN DO;
        new_admission = admission;
        new_release = release;
    END;
    ELSE DO;
        diff = admission - new_release;

        IF diff < &DOC_leniency THEN DO;
            new_release = release;
        END;
        ELSE DO;
            OUTPUT;
            new_admission = admission;
            new_release = release;
        END;
    END;
    IF LAST.ID THEN OUTPUT;
    new_admission = admission;
    new_release = release;

    DROP diff admission release;
RUN;

DATA incar_monthly;
    SET doc_monthly;
    DO date = new_admission TO new_release BY 1;
        IF DAY(INTNX('MONTH', date, 0, 'SAME')) = 1 THEN OUTPUT;
    END;
    FORMAT date YYMMN6.;
RUN;

PROC SQL;
	CREATE TABLE incar_yearly AS 
	SELECT DISTINCT ID, year(date) AS year, FINAL_RE, FINAL_SEX, 
					PUT(year(date) - YOB, age_grps_twenty.) as age_grp_twenty,
					PUT(year(date) - YOB, age_grps_five.) as age_grp_five
	FROM incar_monthly;
	
	CREATE TABLE incar_monthly AS 
	SELECT DISTINCT ID, date, FINAL_RE, FINAL_SEX,
					PUT(year(date) - YOB, age_grps_twenty.) as age_grp_twenty,
					PUT(year(date) - YOB, age_grps_five.) as age_grp_five
	FROM incar_monthly;

	CREATE TABLE incar_yearly_out AS 
	SELECT DISTINCT year, 
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_yearly
	GROUP BY year;

	CREATE TABLE incar_yearly_race AS 
	SELECT DISTINCT year, FINAL_RE,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_yearly
	GROUP BY year, FINAL_RE;

	CREATE TABLE incar_yearly_sex AS 
	SELECT DISTINCT year, FINAL_SEX,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_yearly
	GROUP BY year, FINAL_SEX;

	CREATE TABLE incar_yearly_twenty AS 
	SELECT DISTINCT year, age_grp_twenty,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_yearly
	GROUP BY year, age_grp_twenty;

	CREATE TABLE incar_yearly_five AS 
	SELECT DISTINCT year, age_grp_five,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_yearly
	GROUP BY year, age_grp_five;

	CREATE TABLE incar_monthly_out AS
	SELECT DISTINCT YEAR(date) AS year, MONTH(date) AS month,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_monthly
	GROUP BY YEAR(date), MONTH(date);

	CREATE TABLE incar_monthly_race AS
	SELECT DISTINCT YEAR(date) AS year, MONTH(date) AS month, FINAL_RE,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_monthly
	GROUP BY YEAR(date), MONTH(date), FINAL_RE;

	CREATE TABLE incar_monthly_sex AS
	SELECT DISTINCT YEAR(date) AS year, MONTH(date) AS month, FINAL_SEX,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_monthly
	GROUP BY YEAR(date), MONTH(date), FINAL_SEX;

	CREATE TABLE incar_monthly_twenty AS
	SELECT DISTINCT YEAR(date) AS year, MONTH(date) AS month, age_grp_twenty,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_monthly
	GROUP BY YEAR(date), MONTH(date), age_grp_twenty;

	CREATE TABLE incar_monthly_five AS
	SELECT DISTINCT YEAR(date) AS year, MONTH(date) AS month, age_grp_five,
		   IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM incar_monthly
	GROUP BY YEAR(date), MONTH(date), age_grp_five;
QUIT;

PROC EXPORT
	DATA= incar_yearly_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_yearly_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Race_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_yearly_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Sex_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_yearly_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Twenty_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_yearly_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Five_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_monthly_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_monthly_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Race_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_monthly_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Sex_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_monthly_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Twenty_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= incar_monthly_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Incarcerations_Five_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= doc_length
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/IncarcerationsLength_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= doc_length_race
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/IncarcerationsLength_Race_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= doc_length_sex
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/IncarcerationsLength_Sex_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= doc_length_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/IncarcerationsLength_Twenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= doc_length_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/IncarcerationsLength_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/*==============================*/
/*     All Cause Mortality      */
/*==============================*/

PROC SQL;
    CREATE TABLE death_raw AS
    SELECT DISTINCT death.MONTH_DEATH AS month, death.YEAR_DEATH AS year,
                    death.ID, death.opioid_death as od_death,
                    demo.FINAL_RE, demo.FINAL_SEX, demo.YOB
    FROM PHDDEATH.DEATH death
    LEFT JOIN PHDSPINE.DEMO demo ON demo.ID = death.ID
    INNER JOIN oud_yearly oud ON oud.ID = death.ID;
QUIT;

DATA death_raw;
    SET death_raw;

	age_grp_five = put(year - YOB, age_grps_five.);
	age_grp_twenty = put(year - YOB, age_grps_twenty.);
RUN;

PROC SQL;
    CREATE TABLE death_yearly AS 
    SELECT DISTINCT od_death, year,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year;

	CREATE TABLE death_monthly AS 
	SELECT DISTINCT od_death, year, month, 
		   		   IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw 
	GROUP BY od_death, year, month;

	CREATE TABLE death_yearly_sex AS 
	SELECT DISTINCT od_death, year, FINAL_SEX,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, FINAL_SEX;

	CREATE TABLE death_monthly_sex AS 
	SELECT DISTINCT od_death, year, month, FINAL_SEX,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, month, FINAL_SEX;

	CREATE TABLE death_yearly_race AS 
	SELECT DISTINCT od_death, year, FINAL_RE,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, FINAL_RE;

	CREATE TABLE death_monthly_race AS 
	SELECT DISTINCT od_death, year, month, FINAL_RE,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, month, FINAL_RE;

	CREATE TABLE death_yearly_twenty AS 
	SELECT DISTINCT od_death, year, age_grp_twenty,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, age_grp_twenty;

	CREATE TABLE death_monthly_twenty AS 
	SELECT DISTINCT od_death, year, month, age_grp_twenty,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, month, age_grp_twenty;

	CREATE TABLE death_yearly_five AS 
	SELECT DISTINCT od_death, year, age_grp_five,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, age_grp_five;

	CREATE TABLE death_monthly_five AS 
	SELECT DISTINCT od_death, year, month, age_grp_five,
		   			IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM death_raw
	GROUP BY od_death, year, month, age_grp_five;
QUIT;

PROC EXPORT DATA = death_yearly
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Yearly_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_yearly_sex
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Yearly_Sex_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_yearly_five
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Yearly_Five_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_yearly_twenty
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Yearly_Twenty_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly_race
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_Race_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly_sex
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_Sex_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly_twenty
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_Twenty_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly_five
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Monthly_Five_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;