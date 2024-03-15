/*==============================*/
/* Project: OUD Cascade 	    */
/* Author: Ryan O'Dea  		    */ 
/* Created: 4/27/2023 		    */
/* Updated: 12/20/2023 by SJM	*/
/*==============================*/

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
/*  	GLOBAL VARIABLES   	 */
/*==============================*/
%LET year = (2015:2021);
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
	'T40691D','T40692D','T40693D','T40694D' /* Overdose Codes */);
           
%LET PROC = ('G2067','G2068','G2069','G2070', 
	'G2071','G2072','G2073','G2074', 
	'G2075', /* MAT Opioid */
	'G2076','G2077','G2078','G2079', 
	'G2080', /*Opioid Trt */
 	'H0020','HZ81ZZZ','HZ84ZZZ','HZ91ZZZ','HZ94ZZZ',
    'J0570','J0571','J0572','J0573', 
 	'J0574','J0575','J2315','Q9991','Q9992''S0109'/* Naloxone*/);

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
            
/*===============================*/            
/* DATA PULL			 */
/*===============================*/ 

/*======DEMOGRAPHIC DATA=========*/
DATA demographics;
    SET PHDSPINE.DEMO (KEEP= ID FINAL_RE FINAL_SEX);
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
DATA apcd (KEEP= ID oud_apcd year_apcd age_apcd month_apcd);
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

	age_apcd = MED_AGE;
	year_apcd = MED_FROM_DATE_YEAR;
    month_apcd = MED_FROM_DATE_MONTH;
RUN;

DATA pharm (KEEP= year_pharm month_pharm oud_pharm ID age_pharm);
    SET PHDAPCD.MOUD_PHARM(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH PHARM_AGE
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);
    month_pharm = PHARM_FILL_DATE_MONTH;
    year_pharm = PHARM_FILL_DATE_YEAR;

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;

    IF oud_pharm > 0 THEN age_pharm = PHARM_AGE;
RUN;

/*======CASEMIX DATA==========*/
/* ED */
DATA casemix_ed (KEEP= ID oud_cm_ed ED_ID year_cm age_ed month_cm);
	SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
				  WHERE= (ED_ADMIT_YEAR IN &year));
	IF ED_DIAG1 in &ICD OR 
        ED_PRINCIPLE_ECODE IN &ICD THEN oud_cm_ed = 1;
	ELSE oud_cm_ed = 0;
	
	IF oud_cm_ed > 0 THEN do;
	age_ed = ED_AGE;
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

DATA casemix (KEEP= ID oud_ed year_cm age_ed month_cm);
	SET casemix;
	IF SUM(oud_cm_ed_proc, oud_cm_ed_diag, oud_cm_ed) > 0 THEN oud_ed = 1;
	ELSE oud_ed = 0;
	
	IF oud_ed = 0 THEN DELETE;
RUN;

/* HD DATA */
DATA hd (KEEP= HD_ID ID oud_hd_raw year_hd age_hd month_hd);
	SET PHDCM.HD (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH HD_ECODE
					WHERE= (HD_ADMIT_YEAR IN &year));
	IF HD_DIAG1 in &ICD OR
     HD_PROC1 in &PROC OR
     HD_ECODE IN &ICD THEN oud_hd_raw = 1;
	ELSE oud_hd_raw = 0;

IF oud_hd_raw > 0 THEN do;
    age_hd = HD_AGE;
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

DATA hd (KEEP= ID oud_hd year_hd age_hd month_hd);
	SET hd;
	IF SUM(oud_hd_diag, oud_hd_raw, oud_hd_proc) > 0 THEN oud_hd = 1;
	ELSE oud_hd = 0;
	
	IF oud_hd = 0 THEN DELETE;
RUN;

/* OO */
DATA oo (KEEP= ID oud_oo year_oo age_oo month_oo);
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

    age_oo = OO_AGE;
    year_oo = OO_ADMIT_YEAR;
    month_oo = OO_ADMIT_MONTH;
RUN;


/* MERGE ALL CM */
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

DATA casemix (KEEP = ID oud_cm year_cm age_cm month_cm);
    SET casemix;

    IF oud_ed = 9999 THEN oud_ed = 0;
    IF oud_hd = 9999 THEN oud_hd = 0;
    IF oud_oo = 9999 THEN oud_oo = 0;

    IF sum(oud_ed, oud_hd, oud_oo) > 0 THEN oud_cm = 1;
    ELSE oud_cm = 0;
    IF oud_cm = 0 THEN DELETE;

	age_cm = min(age_ed, age_hd, age_oo);
	year_cm = min(year_oo, year_hd, year_cm);
    month_cm = min(month_oo, month_hd, month_cm);
RUN;

/* BSAS */
DATA bsas (KEEP= ID oud_bsas year_bsas month_bsas age_bsas);
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
    month_bsas = ENR_MONTH_BSAS;;
RUN;

/* MATRIS */
DATA matris (KEEP= ID oud_matris year_matris month_matris age_matris);
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

	IF AGE_UNITS_MATRIS = 1 THEN age_matris = AGE_MATRIS/525600;
	ELSE IF AGE_UNITS_MATRIS = 2 THEN age_matris = AGE_MATRIS/8760;
	ELSE IF AGE_UNITS_MATRIS = 3 THEN age_matris = AGE_MATRIS/365.25;
	ELSE IF AGE_UNITS_MATRIS = 4 THEN age_matris = AGE_MATRIS/52;
	ELSE IF AGE_UNITS_MATRIS = 5 THEN age_matris = AGE_MATRIS/12;
	ELSE IF AGE_UNITS_MATRIS = 6 THEN age_matris = AGE_MATRIS;
	ELSE age_matris = 999;

	year_matris = inc_year_matris;
    month_matris = inc_month_matris;
RUN;

/* DEATH */
DATA death (KEEP= ID oud_death year_death month_death age_death);
    SET PHDDEATH.DEATH (KEEP= ID OPIOID_DEATH YEAR_DEATH AGE_DEATH
                        WHERE= (YEAR_DEATH IN &year));
    IF OPIOID_DEATH = 1 THEN oud_death = 1;
    ELSE oud_death = 0;
    IF oud_death = 0 THEN DELETE;

	year_death = YEAR_DEATH;
    month_death = MONTH_DEATH;
RUN;

/* PMP */
DATA pmp (KEEP= ID oud_pmp year_pmp month_pmp age_pmp);
    SET PHDPMP.PMP (KEEP= ID BUPRENORPHINE_PMP date_filled_year AGE_PMP date_filled_month
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
    LEFT JOIN bsas ON bsas.ID = demographics.ID
    LEFT JOIN matris ON matris.ID = demographics.ID
    LEFT JOIN pmp ON pmp.ID = demographics.ID;
QUIT;

DATA oud;
    SET oud;
	if oud_apcd = . then oud_apcd=0;
	if oud_bsas = . then oud_bsas=0;
	if oud_cm = . then oud_cm=0;
	if oud_matris = . then oud_matris=0;
	if oud_pmp = . then oud_pmp=0;

    oud_cnt = sum(oud_apcd, oud_cm, oud_matris, oud_pmp, oud_bsas);
    IF oud_cnt > 0 
    THEN oud_master = 1;
    ELSE oud_master = 0;
    IF oud_master = 0 THEN DELETE;

	oud_age = min(age_apcd, age_cm, age_matris, age_bsas, age_pmp);
    oud_age = round(oud_age); /* Round oud_age to nearest whole number */
    age_grp_five  = put(oud_age, age_grps_five.);
	IF age_grp_five  = 999 THEN DELETE;
RUN;

/*=========================================*/
/*    FINAL COHORT DATASET: oud_distinct   */
/*=========================================*/

PROC SQL;
    CREATE TABLE oud_distinct AS
    SELECT DISTINCT ID, oud_age, min(age_grp_five) as agegrp, FINAL_RE FROM oud 
    GROUP BY ID;
QUIT;

/*==============================*/
/*         MOUD Counts          */
/*==============================*/

/* Age Demography Creation */

PROC SQL;
    CREATE TABLE demographics_monthly AS
    SELECT * FROM demographics, months, years;
    
PROC SQL;
    CREATE TABLE medical_age AS 
    SELECT ID, 
           MED_AGE AS age_apcd, 
           MED_FROM_DATE_MONTH AS month_apcd,
           MED_FROM_DATE_YEAR AS year_apcd
    FROM PHDAPCD.MOUD_MEDICAL;

    CREATE TABLE pharm_age AS
    SELECT ID, 
           PHARM_AGE AS age_pharm, 
           PHARM_FILL_DATE_MONTH AS month_pharm, 
           PHARM_FILL_DATE_YEAR AS year_pharm
    FROM PHDAPCD.MOUD_PHARM;

    CREATE TABLE bsas_age AS
    SELECT ID, 
           AGE_BSAS AS age_bsas,
           ENR_YEAR_BSAS AS year_bsas,
           ENR_MONTH_BSAS AS month_bsas
    FROM PHDBSAS.BSAS;

    CREATE TABLE hocmoud_age AS 
    SELECT ID,
           enroll_age AS age_hocmoud,
           enroll_year AS year_hocmoud,
           enroll_month AS month_hocmoud
    FROM PHDBSAS.HOCMOUD;
    
    CREATE TABLE doc_age AS
    SELECT ID,
           ADMIT_RECENT_AGE_DOC AS age_doc,
           ADMIT_RECENT_MONTH_DOC AS month_doc,
           ADMIT_RECENT_YEAR_DOC AS year_doc
    FROM PHDDOC.DOC;

    CREATE TABLE pmp_age AS 
    SELECT ID,
           AGE_PMP AS age_pmp,
           DATE_FILLED_MONTH AS month_pmp,
           DATE_FILLED_YEAR AS year_pmp
    FROM PHDPMP.PMP; 

    CREATE TABLE age AS
    SELECT * FROM demographics_monthly
    LEFT JOIN medical_age ON medical_age.ID = demographics_monthly.ID 
                          AND medical_age.year_apcd = demographics_monthly.year
                          AND medical_age.month_apcd = demographics_monthly.month
    LEFT JOIN pharm_age ON pharm_age.ID = demographics_monthly.ID
                          AND pharm_age.year_pharm = demographics_monthly.year
                          AND pharm_age.month_pharm = demographics_monthly.month
    LEFT JOIN bsas_age ON bsas_age.ID = demographics_monthly.ID
                          AND bsas_age.year_bsas = demographics_monthly.year
                          AND bsas_age.month_bsas = demographics_monthly.month
    LEFT JOIN hocmoud_age ON hocmoud_age.ID = demographics_monthly.ID
                          AND hocmoud_age.year_hocmoud = demographics_monthly.year
                          AND hocmoud_age.month_hocmoud = demographics_monthly.month
    LEFT JOIN doc_age ON doc_age.ID = demographics_monthly.ID
                          AND doc_age.year_doc = demographics_monthly.year
                          AND doc_age.month_doc = demographics_monthly.month
    LEFT JOIN pmp_age ON pmp_age.ID = demographics_monthly.ID
                          AND pmp_age.year_pmp = demographics_monthly.year
                          AND pmp_age.month_pmp = demographics_monthly.month;      
QUIT;

DATA age (KEEP= ID age_grp_five year month);
    SET age;
    ARRAY age_flags {*} age_apcd age_pharm
    					age_bsas age_hocmoud
    					age_doc age_pmp;
                        
    DO i = 1 TO dim(age_flags);
        IF missing(age_flags[i]) THEN age_flags[i] = 9999;
    END;
    
    age_raw = min(age_apcd, age_pharm, age_bsas, age_hocmoud, age_doc, age_pmp);
    age_grp_five = put(age_raw, age_grps_five.);
RUN;

DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

PROC SQL;
    CREATE TABLE age AS 
    SELECT DISTINCT * FROM age;
    
    CREATE TABLE moud_demo AS
    SELECT *, DEMO.FINAL_RE, DEMO.FINAL_SEX
    FROM moud
    LEFT JOIN PHDSPINE.DEMO ON moud.ID = DEMO.ID;
QUIT;

PROC SORT DATA=moud_demo;
    by ID DATE_START_MOUD TYPE_MOUD;
RUN;

DATA moud_demo;
    SET moud_demo;
    by ID;
    retain episode_num;

    lag_date = lag(DATE_END_MOUD);
    IF FIRST.ID THEN lag_date = .;
    IF FIRST.ID THEN episode_num = 1;
    
    diff = DATE_START_MOUD - lag_date;
    
    IF diff >= &MOUD_leniency THEN flag = 1; ELSE flag = 0;
    IF flag = 1 THEN episode_num = episode_num + 1;

    episode_id = catx("_", ID, episode_num);
RUN;

PROC SORT data=moud_demo; 
    BY episode_id;
RUN;

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

PROC SORT data=moud_demo (KEEP= start_date start_month start_year
					  			end_date end_month end_year 
					  			ID FINAL_RE FINAL_SEX TYPE_MOUD);
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
	
	IF FIRST.ID THEN diff = .; 
	ELSE diff = start_date - lag(end_date);
    IF end_date > lag(end_date) THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;
RUN;

DATA moud_expanded(KEEP= ID month year treatment FINAL_SEX FINAL_RE age_grp_five);
    SET moud_demo;
    treatment = TYPE_MOUD;

    FORMAT year 4. month 2.;
    
    num_months = intck('month', input(put(start_year, 4.) || put(start_month, z2.), yymmn6.), 
                       input(put(end_year, 4.) || put(end_month, z2.), yymmn6.));

    DO i = 0 to num_months;
      new_date = intnx('month', input(put(start_year, 4.) || put(start_month, z2.), yymmn6.), i);
      year = year(new_date);
      month = month(new_date);
      OUTPUT;
    END;
RUN;

PROC SQL;
	CREATE TABLE moud_demo AS
	SELECT DISTINCT * FROM moud_demo
	LEFT JOIN age ON age.ID = moud_demo.ID AND 
					 age.month = moud_demo.start_month AND 
					 age.year = moud_demo.start_year;
QUIT;

DATA moud_expanded;
	SET moud_expanded;
	WHERE year IN &year;
RUN;

PROC SQL;
    CREATE TABLE moud_demo AS 
    SELECT * 
    FROM moud_demo
    LEFT JOIN age ON age.ID = moud_demo.ID 
                  AND age.year = moud_demo.start_year
                  AND age.month = moud_demo.start_month;
    
    CREATE TABLE moud_expanded AS 
    SELECT * 
    FROM moud_expanded 
    LEFT JOIN age ON age.ID = moud_expanded.ID 
                  AND age.year = moud_expanded.year
                  AND age.month = moud_expanded.month;
QUIT;

DATA moud_demo;
    SET moud_demo;
    WHERE age_grp_five ne ' ' and age_grp_five ne '999';
RUN;

DATA moud_expanded;
    SET moud_expanded;
    WHERE age_grp_five ne ' ' and age_grp_five ne '999';
RUN;

PROC SQL;                  
    CREATE TABLE moud_starts AS
    SELECT start_month AS month,
           start_year AS year,
           TYPE_MOUD AS treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD;

    CREATE TABLE stratif_moud_starts_age AS
    SELECT start_month AS month,
           start_year AS year,
           TYPE_MOUD AS treatment,
           FINAL_SEX, age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD, age_grp_five;

    CREATE TABLE stratif_moud_starts_RE AS
    SELECT start_month AS month,
           start_year AS year,
           TYPE_MOUD AS treatment,
           FINAL_SEX, FINAL_RE,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD, FINAL_RE;
    
    CREATE TABLE moud_counts AS
    SELECT year, month, treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment;

    CREATE TABLE stratif_moud_counts_age AS
    SELECT year, month, treatment, FINAL_SEX, age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, age_grp_five;
    
    CREATE TABLE stratif_moud_counts_RE AS
    SELECT year, month, treatment, FINAL_SEX, FINAL_RE,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, FINAL_RE;
QUIT;

PROC EXPORT
	DATA= moud_counts
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDCounts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_counts_age
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDCounts_AgeStratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_counts_RE
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDCounts_REStratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDStarts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_starts_age
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDStarts_AgeStratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_starts_RE
	OUTFILE= "/sas/data/DPH/OPH/SAP/FOLDERS/LIZ/Epstein/Sarah/MOUDStarts_REStratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

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

/* ========================================================== */
/*                       HCV TESTING                          */
/* ========================================================== */

/* =========== */
/* AB TESTING */
/* ========== */

DATA ab;
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE MED_FROM_DATE_YEAR
					 
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
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
					 WHERE = (MED_PROC_CODE IN  &RNA_CPT));
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
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_PROC_CODE
					 
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
	MIN(EVER_IDU_HCV) as EVER_IDU_HCV,
	1 as HCV_SEROPOSITIVE_INDICATOR,
	CASE WHEN min(DISEASE_STATUS_HCV) = 1 THEN 1 ELSE 0 END as CONFIRMED_HCV_INDICATOR FROM PHDHEPC.HCV
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
SET PHDAPCD.MOUD_MEDICAL (KEEP = ID MED_FROM_DATE MED_ADM_TYPE MED_ICD1
					 
					 WHERE = (MED_ICD1 IN &HCV_ICD));
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

DATA DAA; SET PHDAPCD.MOUD_PHARM (KEEP  = ID PHARM_FILL_DATE PHARM_FILL_DATE_YEAR PHARM_NDC PHARM_AGE
								WHERE = (PHARM_NDC IN &DAA_CODES));
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

PROC CONTENTS data=OUD_HCV_DAA;
title "Contents of Final Dataset";
run;

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
proc freq data=OUD_HCV_DAA;
title "HCV Care Cascade, OUD Cohort, Overall";
tables ANY_HCV_TESTING_INDICATOR
	   AB_TEST_INDICATOR
	   RNA_TEST_INDICATOR
	   HCV_SEROPOSITIVE_INDICATOR
	   CONFIRMED_HCV_INDICATOR
	   HCV_PRIMARY_DIAG
	   CONFIRMED_HCV_INDICATOR*HCV_PRIMARY_DIAG
       CONFIRMED_HCV_INDICATOR*GENO_TEST_INDICATOR
	   DAA_START_INDICATOR
	   DAA_START_INDICATOR*CONFIRMED_HCV_INDICATOR
	   HCV_SEROPOSITIVE_INDICATOR*HCV_PRIMARY_DIAG
	   BIRTH_INDICATOR
	   EVENT_YEAR_HCV
	   FIRST_DAA_START_YEAR / norow nopercent nocol;
run;

PROC FREQ data = AB_YEARS_COHORT;
title "AB Tests Per Year, In Cohort";
table  AB_TEST_YEAR / norow nocol nopercent;
run;

PROC FREQ data = AB_YEARS;
title "AB Tests Per Year, All MA Res.";
table  AB_TEST_YEAR / norow nocol nopercent;
run;

proc freq data=Testing;
title   "Testing Among Confirmed HCV";
where   CONFIRMED_HCV_INDICATOR = 1;
tables  EOT_RNA_TEST
		SVR12_RNA_TEST
		FIRST_DAA_START_YEAR / norow nopercent nocol;
run;

/*  Create macros to generate all the sets of table for each type of strata*/

/* CascadeTestFreq will output the stratified overall testing 
   Counts stratified according to 'strata'
   Note: We will use raw race formats here */
%macro CascadeTestFreq(strata, mytitle, ageformat, raceformat);
	   	PROC FREQ DATA = OUD_HCV_DAA;
	   	TITLE  &mytitle;
	   	TABLES ANY_HCV_TESTING_INDICATOR*&strata
			   AB_TEST_INDICATOR*&strata
			   RNA_TEST_INDICATOR*&strata
			   HCV_SEROPOSITIVE_INDICATOR*&strata 
			   CONFIRMED_HCV_INDICATOR*&strata / nocol nopercent norow;
		FORMAT num_agegrp &ageformat 
			   final_re &raceformat
			   BIRTH_INDICATOR birthfmt.;
%mend CascadeTestFreq;

/* For outcomes we'll collapse the formats to avoid low counts  */
%macro CascadeCareFreq(strata, mytitle, ageformat, raceformat);
	   	PROC FREQ DATA = OUD_HCV_DAA;
	   	TITLE  &mytitle;
	   	TABLES GENO_TEST_INDICATOR*&strata
	   		   HCV_PRIMARY_DIAG*&strata
	           DAA_START_INDICATOR*&strata / nocol nopercent norow;
		WHERE CONFIRMED_HCV_INDICATOR=1;
		FORMAT num_agegrp &ageformat 
			   final_re &raceformat
			   BIRTH_INDICATOR birthfmt.;
%mend CascadeCareFreq;

/* End of Treatment */
%macro EndofTrtFreq(strata, mytitle, ageformat, raceformat);
	   	PROC FREQ DATA = TESTING;
	   	WHERE  CONFIRMED_HCV_INDICATOR = 1;
	   	TITLE  &mytitle;
	   	TABLES DAA_START_INDICATOR*&strata
	   		   HCV_PRIMARY_DIAG*&strata
	   		   EOT_RNA_TEST*&strata
			   SVR12_RNA_TEST*&strata / nocol nopercent norow;
		FORMAT num_agegrp &ageformat 
			   final_re &raceformat
			   BIRTH_INDICATOR birthfmt.;
%mend EndofTrtFreq;

/* Confirmed HCV and DAA Starts by YEAR */
%macro YearFreq(var, strata, confirm_status, mytitle, ageformat, raceformat);
	   	PROC FREQ DATA = OUD_HCV_DAA;
	   	WHERE  CONFIRMED_HCV_INDICATOR = &confirm_status;
	   	TITLE  &mytitle;
		table  &var*&strata / norow nocol nopercent;
		FORMAT num_agegrp &ageformat
			   final_re &raceformat
			   BIRTH_INDICATOR birthfmt.;
%mend YearFreq;

/* Finally create the stratified tables  */

/*  Age stratification */
%CascadeTestFreq(num_agegrp, "HCV Testing: Stratified by Age", agefmt_all., racefmt_all.);   
%CascadeCareFreq(num_agegrp, "HCV Care: Stratified by Age", agefmt_all., racefmt_all.);
%EndofTrtFreq(num_agegrp, "HCV EOT/SVR Testing Among Confirmed HCV by Age", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, num_agegrp, 1, "Counts per year among confirmed, by Age", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, num_agegrp, 0, "Counts per year among probable, by Age", agefmt_comb., racefmt_all.)
%YearFreq(FIRST_DAA_START_YEAR, num_agegrp, 1, "Counts per year among confirmed, by Age", agefmt_comb., racefmt_all.)

/*  Race Stratification */
%CascadeTestFreq(final_re, "HCV Testing: Stratified by Race", agefmt_all., racefmt_all.);   
%CascadeCareFreq(final_re, "HCV Care: Stratified by Race", agefmt_all., racefmt_all.);
%EndofTrtFreq(final_re, "HCV EOT/SVR Testing Among Confirmed HCV by Race - all", agefmt_all., racefmt_all.)
%EndofTrtFreq(final_re, "HCV EOT/SVR Testing Among Confirmed HCV by Race -combined", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, final_re, 1, "Counts per year among confirmed, by Race", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, final_re, 0, "Counts per year among probable, by Race", agefmt_comb., racefmt_all.)
%YearFreq(FIRST_DAA_START_YEAR, final_re, 1, "Counts per year among confirmed, by Race", agefmt_comb., racefmt_all.)

/*  Birth Stratification */
%CascadeTestFreq(birth_indicator, "HCV Testing: Stratified by Birth", agefmt_all., racefmt_all.);   
%CascadeCareFreq(birth_indicator, "HCV Care: Stratified by Birth", agefmt_all., racefmt_comb.);
%EndofTrtFreq(birth_indicator, "HCV EOT/SVR Testing Among Confirmed HCV by Birth", agefmt_all., racefmt_comb.)
%YearFreq(EVENT_YEAR_HCV, birth_indicator, 1, "Counts per year among confirmed, by Birth", agefmt_comb., racefmt_all.)
%YearFreq(EVENT_YEAR_HCV, birth_indicator, 0, "Counts per year among probable, by Birth", agefmt_comb., racefmt_all.)
%YearFreq(FIRST_DAA_START_YEAR, birth_indicator, 1, "Counts per year among confirmed, by Birth", agefmt_comb., racefmt_all.)

/* Rename to merge with infant cascade for OUD_Capture */
data OUD_HCV_DAA;
    set OUD_HCV_DAA(rename=(ID=MOM_ID));
run;

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

/*============================ */
/*     Global Variables        */
/*============================ */
		
/* ======= HCV TESTING CPT CODES ========  */
%LET AB_CPT = ('G0472', '86803',
			   '86804', '80074');
			   
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
data HCV_MOMS;
    set HCV_MOMS;

    /* Calculate the difference in days */
    hcv_duration_count = MOM_EVENT_DATE_HCV - DOB_INFANT_TBL ;

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
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX, APCD_anyclaim
	FROM PHDSPINE.DEMO;
	QUIT;

/* Merge cohorts */
PROC SQL;
CREATE TABLE MERGED_COHORT AS
SELECT DISTINCT 
    M.MOM_ID,
    M.INFANT_ID,
    M.BIRTH_LINK_ID,
    M.INFANT_YEAR_BIRTH,
    M.MONTH_BIRTH,
    M.DOB_INFANT_TBL,
    M.MOM_DISEASE_STATUS_HCV,
    M.MOM_EVENT_DATE_HCV,
    D.FINAL_RE,
    D.FINAL_SEX,
    M.HIV_DIAGNOSIS,
    M.MOUD_DURING_PREG,
    M.MOUD_AT_DELIVERY,
    D.APCD_anyclaim
FROM HCV_MOMS AS M
LEFT JOIN demographics AS D
    ON M.INFANT_ID = D.ID;
QUIT;

/* Sort the dataset by INFANT_ID and MOUD_DURING_PREG */
proc sort data=MERGED_COHORT;
  by INFANT_ID descending HIV_DIAGNOSIS descending MOUD_DURING_PREG;
run;

/* Create a new dataset to store the reduced output */
data MERGED_COHORT;
  /* Set the first row as the initial values */
  set MERGED_COHORT;
  by INFANT_ID;

  /* Retain the first row for each INFANT_ID */
  if first.INFANT_ID then output;

run;

/* Going to look at all exposed infants, but filter of APCD_anyclaim for testing and tratment cascade  */
/* Filter into two datasets based on conditions */
DATA INFANT_COHORT;
    SET MERGED_COHORT;
    IF APCD_anyclaim ne 1 THEN OUTPUT;
RUN;

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

    /* Drop the variable i */
    DROP i;

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

/* Extract all relevant data */
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

/*Exposed infants inlcude APCD_anyclaim = 0 */
proc freq data=MERGED_COHORT;
    where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2022;
    title "EXPOSED Infants born to moms with HCV born 2014-2022";
    tables INFANT_YEAR_BIRTH / out=Table0 norow nopercent nocol; 
run;

proc print data=Table0; 
run;

/* Newly in July 2023, excluding those diagnosed at age >=3 or only probable status because they are 
not technically perinatal cases */

title "Infants born to moms with HCV, Testing and Diagnosis, Overall, born 2014-2019";
proc freq data=TESTING;
    tables ANY_HCV_TESTING_INDICATOR
           AB_TEST_INDICATOR*RNA_TEST_INDICATOR
           APPROPRIATE_Testing
           APPROPRIATE_AB_Testing*APPROPRIATE_RNA_Testing
           CONFIRMED_HCV_INDICATOR
           DAA_START_INDICATOR
           CONFIRMED_HCV_INDICATOR*RNA_TEST_INDICATOR /missing;
    where INFANT_YEAR_BIRTH >= 2014 and INFANT_YEAR_BIRTH <= 2019;
    ods output CrossTabFreqs=Table1;
run;

data Table1;
    set Table1;
    format frequency best32.;
    keep INFANT_YEAR_BIRTH ANY_HCV_TESTING_INDICATOR AB_TEST_INDICATOR RNA_TEST_INDICATOR APPROPRIATE_Testing APPROPRIATE_AB_Testing APPROPRIATE_RNA_Testing CONFIRMED_HCV_INDICATOR DAA_START_INDICATOR frequency rowpercent;
run;

proc print data=Table1;
run;

proc freq data=TESTING;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3;
    title "Infants with confirmed perinatal HCV only, unstratified, born 2014-2019 - ie age at dx <3";
    tables ANY_HCV_TESTING_INDICATOR GENO_TEST_INDICATOR HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
           / out=Table2 norow nopercent nocol; 
run;

proc print data=Table2; 
run;

proc freq data=TESTING;
    Where (INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <=2017 OR (INFANT_YEAR_BIRTH=2018 AND MONTH_BIRTH<=6))
    AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
    title "Infants with confirmed perinatal HCV only, unstratified, born 1/2014-6/2018, Confirmed HCV";
    tables ANY_HCV_TESTING_INDICATOR HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
           / out=Table3 norow nopercent nocol; 
run;

proc print data=Table3; 
run;

proc freq data=TESTING;
    Where INFANT_YEAR_BIRTH >= 2011 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
    title "Infants with confirmed perinatal HCV only, unstratified, born 2011-2021";
    tables HCV_PRIMARY_DIAG DAA_START_INDICATOR EOT_RNA_TEST SVR12_RNA_TEST
           / out=Table4 norow nopercent nocol; 
run;

proc print data=Table4; 
run;

/*Exposed infants inlcude APCD_anyclaim = 0 */
proc freq data=MERGED_COHORT;
WHERE INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2021;
title "Total Number of EXPOSED Infants in Cohort, By Race, born 2014-2021";
table final_re / out=Table5 norow nopercent nocol;
FORMAT final_re racefmt_all.;
run;

proc print data=Table5; 
run;

title "Infants born to moms with HCV, TESTing/DIAGNOSIS Care Cascade, By Race, 2014-2019";
proc freq data=INFANT_DAA;
    tables ANY_HCV_TESTING_INDICATOR*final_re APPROPRIATE_Testing*final_re CONFIRMED_HCV_INDICATOR*final_re /missing;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019;
    ods output CrossTabFreqs=Table6;
run;

data Table6;
    set Table6;
    format frequency best32.;
    keep INFANT_YEAR_BIRTH ANY_HCV_TESTING_INDICATOR final_re APPROPRIATE_Testing CONFIRMED_HCV_INDICATOR frequency rowpercent;
run;

proc print data=Table6;
run;

title "Infants born to moms with HCV, Care Cascade, By Race/Hispance Ethnicity, born 2014-2019, Confirmed Perinatal HCV";
proc freq data=INFANT_DAA;
        tables CONFIRMED_HCV_INDICATOR*final_re HCV_PRIMARY_DIAG*final_re GENO_TEST_INDICATOR*final_re /missing;
    Where INFANT_YEAR_BIRTH >= 2014 AND INFANT_YEAR_BIRTH <= 2019 AND CONFIRMED_HCV_INDICATOR=1 AND AGE_AT_DX < 3 AND AGE_AT_DX GE 0;
    ods output CrossTabFreqs=Table7;
run;

data Table7;
    set Table7;
    format frequency best32.;
    keep INFANT_YEAR_BIRTH CONFIRMED_HCV_INDICATOR AGE_AT_DX final_re HCV_PRIMARY_DIAG GENO_TEST_INDICATOR frequency rowpercent;
run;

proc print data=Table7;
run;

proc freq data=INFANT_DAA;
    Where INFANT_YEAR_BIRTH >= 2014; /*to exclude those born 2011-13 whose first test occurred pre-APCD start;*/
    TITLE "Number of Infants Born by YEAR & Age at first appropriate Ab, RNA testing, 2014-2021";
    TABLES INFANT_YEAR_BIRTH AGE_AT_FIRST_AB_TEST AGE_YRS_AT_FIRST_AB_TEST AGE_AT_FIRST_RNA_TEST AGE_YRS_AT_FIRST_RNA_TEST AGE_AT_FIRST_TEST AGE_YRS_AT_FIRST_TEST
        / out=Table8 nocol nopercent norow;
run;

proc print data=Table8; 
run;

proc freq data=PHDBIRTH.BIRTH_INFANT;
    TITLE "Total Number of Infants Born by YEAR, 2014-2021";
    TABLE YEAR_BIRTH / out=Table9 nocol nopercent norow;
run;

proc print data=Table9; 
run;

proc freq data=INFANT_DAA;
    where APPROPRIATE_Testing = 1;
    Title "Number of appropriately tested infants by infant year of birth ie in each year how many infants born that year were ultimately appropriately tested bt 2014-2021";
    TABLES INFANT_YEAR_BIRTH / out=Table10 nocol nopercent norow;
run;

proc print data=Table10; 
run;

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

proc freq data=DAA15;
    title "HCV Care Cascade for children diagnosed with HCV at age <=15 years between 2011-2021, Overall";
    tables DISEASE_STATUS_HCV DAA_START_INDICATOR FIRST_DAA_START_YEAR
           / out=Table11 norow nopercent nocol;
run;

proc print data=Table11; 
run;

proc freq data=DAA15;
    Where FIRST_DAA_START_YEAR < 2020;
    title "<=15 HCV Care Cascade, DAA starts pre 2020";
    tables DAA_START_INDICATOR
           / out=Table12 norow nopercent nocol;
run;

proc print data=Table12; 
run;

proc freq data=DAA15;
    WHERE DISEASE_STATUS_HCV = 1;
    title "<=15 HCV Care Cascade, Among Confirmed";
    tables HCV_PRIMARY_DIAG RNA_TEST_INDICATOR GENO_TEST_INDICATOR
           DAA_START_INDICATOR EVENT_YEAR_HCV AGE_HCV
           / out=Table13 norow nopercent nocol;
run;

proc print data=Table13; 
run;

proc freq data=DAA15;
    WHERE DISEASE_STATUS_HCV = 1 and 3 < AGE_HCV < 11;
    title "HCV Diagnoses made among children 4-10yo between 2011-2021";
    tables DISEASE_STATUS_HCV
           / out=Table14 norow nopercent nocol;
run;

proc print data=Table14; 
run;

proc freq data=DAA15;
    WHERE DISEASE_STATUS_HCV = 1 and 10 < AGE_HCV <= 15;
    title "HCV Diagnoses made among children 11-15yo between 2011-2021";
    tables DISEASE_STATUS_HCV / out=Table15 norow nopercent nocol;
run;

proc print data=Table15; 
run;

proc freq data=TRT_TESTING15;
    WHERE DAA_START_INDICATOR = 1;
    title "EOT/SVR12 & age at treatment, Among those treated";
    tables EOT_RNA_TEST SVR12_RNA_TEST AGE_DAA_START_group
           / out=Table16 norow nopercent nocol;
    format AGE_DAA_START_group pharmagegroupf.;
run;

proc print data=Table16; 
run;

proc freq data=TRT_TESTING15;
    WHERE DISEASE_STATUS_HCV = 1 and DAA_START_INDICATOR = 1;
    title "EOT/SVR12 & age at treatment, Among those treated & w confirmed HCV - dup in case age daa start group errors out again to get eot and svr";
    tables EOT_RNA_TEST SVR12_RNA_TEST
           / out=Table17 norow nopercent nocol;
run;

proc print data=Table17; 
run;

title "HCV Care Cascade, by race/ethnicity (<=15)";
proc freq data=DAA15;
    where DISEASE_STATUS_HCV = 1 and DAA_START_INDICATOR = 1;
    tables DISEASE_STATUS_HCV*final_re /missing;
    ods output CrossTabFreqs=Table18;
run;

data Table18;
    set Table18;
    format frequency best32.;
    keep DISEASE_STATUS_HCV DAA_START_INDICATOR final_re frequency;
run;

proc print data=Table18;
run;

title "<=15 HCV Care Cascade, by race/ethnicity, Among Confirmed";
proc freq data=DAA15;
    tables HCV_PRIMARY_DIAG*final_re
           GENO_TEST_INDICATOR*final_re
           DAA_START_INDICATOR*final_re /missing;
        Where DISEASE_STATUS_HCV = 1;
    ods output CrossTabFreqs=Table19;
run;

data Table19;
    set Table19;
    format frequency best32.;
    keep DISEASE_STATUS_HCV HCV_PRIMARY_DIAG final_re GENO_TEST_INDICATOR DAA_START_INDICATOR frequency rowpercent;
run;

proc print data=Table19;
run;

/* ========================================================== */
/*                       Pull Covariates                      */
/* ========================================================== */

proc sql noprint;
select cats('WORK.',memname) into :to_delete separated by ' '
from dictionary.tables
where libname = 'WORK' and memname ne 'INFANT_DAA';
quit;

proc delete data=&to_delete.;
run;

/* Join to add covariates */

proc sql;
    create table FINAL_INFANT_COHORT as
    select INFANT_DAA.*,
           birthsinfants.DISCH_WITH_MOM,
           birthsinfants.FACILITY_ID_BIRTH,
           birthsinfants.GESTATIONAL_AGE,
           birthsinfants.INF_VAC_HBIG,
           birthsinfants.NAS_BC,
           birthsinfants.NAS_BC_NEW,
           birthsinfants.RES_ZIP_BIRTH,
           birthsinfants.Res_Code_Birt as res_code,
           case 
               when birthsinfants.NAS_BC = 1 or birthsinfants.NAS_BC_NEW = 1 then 1
               else .
           end as NAS_BC_TOTAL
    from INFANT_DAA
    left join PHDBIRTH.BIRTH_INFANT as birthsinfants
    on INFANT_DAA.ID = birthsinfants.ID;

    /* Create county from res_code */
    data FINAL_INFANT_COHORT;
        set FINAL_INFANT_COHORT;
        if res_code in (20,36,41,55,75,86,96,126,172,224,242,261,300,318,351) then county='BARNSTABLE';
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
           demographics.FOREIGN_BORN,
           demographics.HOMELESS_HISTORY,
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

%LET MENTAL_HEALTH = ('F20', 'F21', 'F22', 'F23', 'F24', 'F25', 'F28', 'F29',
                      'F30', 'F31', 'F32', 'F33', 'F34', 'F39', 'F40', 'F41',
                      'F42', 'F43', 'F44', 'F45', 'F48');

proc sql;
create table MENTAL_HEALTH_COHORT(where=(MENTAL_HEALTH_DIAG=1)) as
select distinct FINAL_INFANT_COHORT.MOM_ID,
  case
       when apcd.MED_ECODE in &MENTAL_HEALTH or
                       apcd.MED_ADM_DIAGNOSIS in &MENTAL_HEALTH or
                       apcd.MED_PROC_CODE in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC1 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC2 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC3 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC4 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC5 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC6 in &MENTAL_HEALTH or
                       apcd.MED_ICD_PROC7 in &MENTAL_HEALTH or
                       apcd.MED_ICD1 in &MENTAL_HEALTH or
                       apcd.MED_ICD2 in &MENTAL_HEALTH or
                       apcd.MED_ICD3 in &MENTAL_HEALTH or
                       apcd.MED_ICD4 in &MENTAL_HEALTH or
                       apcd.MED_ICD5 in &MENTAL_HEALTH or
                       apcd.MED_ICD6 in &MENTAL_HEALTH or
                       apcd.MED_ICD7 in &MENTAL_HEALTH or
                       apcd.MED_ICD8 in &MENTAL_HEALTH or
                       apcd.MED_ICD9 in &MENTAL_HEALTH or
                       apcd.MED_ICD10 in &MENTAL_HEALTH or
                       apcd.MED_ICD11 in &MENTAL_HEALTH or
                       apcd.MED_ICD12 in &MENTAL_HEALTH or
                       apcd.MED_ICD13 in &MENTAL_HEALTH or
                       apcd.MED_ICD14 in &MENTAL_HEALTH or
                       apcd.MED_ICD15 in &MENTAL_HEALTH or
                       apcd.MED_ICD16 in &MENTAL_HEALTH or
                       apcd.MED_ICD17 in &MENTAL_HEALTH or
                       apcd.MED_ICD18 in &MENTAL_HEALTH or
                       apcd.MED_ICD19 in &MENTAL_HEALTH or
                       apcd.MED_ICD20 in &MENTAL_HEALTH or
                       apcd.MED_ICD21 in &MENTAL_HEALTH or
                       apcd.MED_ICD22 in &MENTAL_HEALTH or
                       apcd.MED_ICD23 in &MENTAL_HEALTH or
                       apcd.MED_ICD24 in &MENTAL_HEALTH or
                       apcd.MED_ICD25 in &MENTAL_HEALTH or
                       apcd.MED_DIS_DIAGNOSIS in &MENTAL_HEALTH or
                       substr(apcd.MED_PROC_CODE, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ECODE, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ADM_DIAGNOSIS, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC1, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC2, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC3, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC4, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC5, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC6, 1, 3) in ('295', '296', '297', '298', '300', '311') 
                       or substr(apcd.MED_ICD_PROC7, 1, 3) in ('295', '296', '297', '298', '300', '311') 
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
left join PHDAPCD.MEDICAL as apcd
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
/* Searching in full dataset because mental health codes are starts_with strings */

%let IJI = ('3642', '9884', '11281', '11504', '11514', '11594',
           '421', '4211', '4219', '4249*', 'A382', 'B376', 'I011', 'I059',
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
                    apcd.MED_ADM_DIAGNOSIS in &IJI or
                    apcd.MED_PROC_CODE in &IJI or
                    apcd.MED_ICD_PROC1 in &IJI or
                    apcd.MED_ICD_PROC2 in &IJI or
                    apcd.MED_ICD_PROC3 in &IJI or
                    apcd.MED_ICD_PROC4 in &IJI or
                    apcd.MED_ICD_PROC5 in &IJI or
                    apcd.MED_ICD_PROC6 in &IJI or
                    apcd.MED_ICD_PROC7 in &IJI or
                    apcd.MED_ICD1 in &IJI or
                    apcd.MED_ICD2 in &IJI or
                    apcd.MED_ICD3 in &IJI or
                    apcd.MED_ICD4 in &IJI or
                    apcd.MED_ICD5 in &IJI or
                    apcd.MED_ICD6 in &IJI or
                    apcd.MED_ICD7 in &IJI or
                    apcd.MED_ICD8 in &IJI or
                    apcd.MED_ICD9 in &IJI or
                    apcd.MED_ICD10 in &IJI or
                    apcd.MED_ICD11 in &IJI or
                    apcd.MED_ICD12 in &IJI or
                    apcd.MED_ICD13 in &IJI or
                    apcd.MED_ICD14 in &IJI or
                    apcd.MED_ICD15 in &IJI or
                    apcd.MED_ICD16 in &IJI or
                    apcd.MED_ICD17 in &IJI or
                    apcd.MED_ICD18 in &IJI or
                    apcd.MED_ICD19 in &IJI or
                    apcd.MED_ICD20 in &IJI or
                    apcd.MED_ICD21 in &IJI or
                    apcd.MED_ICD22 in &IJI or
                    apcd.MED_ICD23 in &IJI or
                    apcd.MED_ICD24 in &IJI or
                    apcd.MED_ICD25 in &IJI or
                    apcd.MED_DIS_DIAGNOSIS in &IJI then 1
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

%let well_child = ('Z00129', 'Z00121', /* ICD-10 codes */
                    'V202', 'V700', 'V703', 'V705', 'V706', 'V708', 'V709'); /* ICD-9 codes */

proc sql;
create table WELL_CHILD_COHORT(where=(WELL_CHILD=1)) as
select distinct FINAL_INFANT_COHORT.INFANT_ID,
  case
       when apcd.MED_ECODE in &WELL_CHILD or
                        apcd.MED_ADM_DIAGNOSIS in &WELL_CHILD or
                        apcd.MED_PROC_CODE in &WELL_CHILD or
                        apcd.MED_ICD_PROC1 in &WELL_CHILD or
                        apcd.MED_ICD_PROC2 in &WELL_CHILD or
                        apcd.MED_ICD_PROC3 in &WELL_CHILD or
                        apcd.MED_ICD_PROC4 in &WELL_CHILD or
                        apcd.MED_ICD_PROC5 in &WELL_CHILD or
                        apcd.MED_ICD_PROC6 in &WELL_CHILD or
                        apcd.MED_ICD_PROC7 in &WELL_CHILD or
                        apcd.MED_ICD1 in &WELL_CHILD or
                        apcd.MED_ICD2 in &WELL_CHILD or
                        apcd.MED_ICD3 in &WELL_CHILD or
                        apcd.MED_ICD4 in &WELL_CHILD or
                        apcd.MED_ICD5 in &WELL_CHILD or
                        apcd.MED_ICD6 in &WELL_CHILD or
                        apcd.MED_ICD7 in &WELL_CHILD or
                        apcd.MED_ICD8 in &WELL_CHILD or
                        apcd.MED_ICD9 in &WELL_CHILD or
                        apcd.MED_ICD10 in &WELL_CHILD or
                        apcd.MED_ICD11 in &WELL_CHILD or
                        apcd.MED_ICD12 in &WELL_CHILD or
                        apcd.MED_ICD13 in &WELL_CHILD or
                        apcd.MED_ICD14 in &WELL_CHILD or
                        apcd.MED_ICD15 in &WELL_CHILD or
                        apcd.MED_ICD16 in &WELL_CHILD or
                        apcd.MED_ICD17 in &WELL_CHILD or
                        apcd.MED_ICD18 in &WELL_CHILD or
                        apcd.MED_ICD19 in &WELL_CHILD or
                        apcd.MED_ICD20 in &WELL_CHILD or
                        apcd.MED_ICD21 in &WELL_CHILD or
                        apcd.MED_ICD22 in &WELL_CHILD or
                        apcd.MED_ICD23 in &WELL_CHILD or
                        apcd.MED_ICD24 in &WELL_CHILD or
                        apcd.MED_ICD25 in &WELL_CHILD or
                        apcd.MED_DIS_DIAGNOSIS in &WELL_CHILD
           and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_INFANT_TBL) >= 18*30 and (apcd.MED_FROM_DATE - FINAL_INFANT_COHORT.DOB_INFANT_TBL) <= 36*30 then 1
           else 0
       end as WELL_CHILD
from FINAL_INFANT_COHORT
left join PHDAPCD.MOUD_MEDICAL as apcd
on FINAL_INFANT_COHORT.INFANT_ID = apcd.ID;
quit;

proc sql;
create table FINAL_INFANT_COHORT_COV as select *,
case
when INFANT_ID in (select INFANT_ID from WELL_CHILD_COHORT) then 1
else 0
end as WELL_CHILD
from FINAL_INFANT_COHORT_COV;
quit;

data FINAL_INFANT_COHORT_COV;
    merge FINAL_INFANT_COHORT_COV (in=a)
          OUD_HCV_DAA (in=b);
    by MOM_ID;

    OUD_capture = (b = 1) and oud_age < AGE_BIRTH;
    
    drop b;
    if missing(OUD_capture) then OUD_capture = 0;
run;

/* ========================================================== */
/*                       Table 1 and Regressions              */
/* ========================================================== */

%macro Table1Freqs (var);
proc freq data=FINAL_INFANT_COHORT_COV; tables &var / missing; run;
%mend;

%Table1freqs (FINAL_SEX);
%Table1freqs (GESTATIONAL_AGE);
%Table1freqs (FINAL_RE);
%Table1freqs (MOMS_FINAL_RE);
%Table1freqs (FACILITY_ID_BIRTH);
%Table1freqs (Res_Code_Birth);
%Table1freqs (well_child);
%Table1freqs (NAS_BC_TOTAL);
%Table1freqs (DISCH_WITH_MOM);
%Table1freqs (INF_VAC_HBIG);
%Table1freqs (HIV_DIAGNOSIS);
%Table1freqs (MOUD_DURING_PREG);
%Table1freqs (MOUD_AT_DELIVERY);
%Table1freqs (OUD_CAPTURE);
%Table1freqs (AGE_BIRTH);
%Table1freqs (EVER_INCARCERATED);
%Table1freqs (FOREIGN_BORN);
%Table1freqs (HOMELESS_HISTORY);
%Table1freqs (LANGUAGE_SPOKEN);
%Table1freqs (MOTHER_EDU);
%Table1freqs (LD_PAY);
%Table1freqs (KOTELCHUCK);
%Table1freqs (prenat_site);
%Table1freqs (MATINF_HEPC);
%Table1freqs (MATINF_HEPB);
%Table1freqs (EVER_IDU_HCV);
%Table1freqs (mental_health_diag);
%Table1freqs (OTHER_SUBSTANCE_USE);
%Table1freqs (iji_diag);

%macro Table1StrataFreqs(var);
    /* Sort the dataset by APPROPRIATE_Testing */
    proc sort data=FINAL_INFANT_COHORT_COV;
        by APPROPRIATE_Testing;
    run;

    /* Run PROC FREQ with BY statement */
    proc freq data=FINAL_INFANT_COHORT_COV;
        by APPROPRIATE_Testing;
        tables &var / missing;
    run;
%mend;

%Table1Stratafreqs (FINAL_SEX);
%Table1Stratafreqs (GESTATIONAL_AGE);
%Table1Stratafreqs (FINAL_RE);
%Table1Stratafreqs (MOMS_FINAL_RE);
%Table1Stratafreqs (FACILITY_ID_BIRTH);
%Table1Stratafreqs (Res_Code_Birth);
%Table1Stratafreqs (well_child);
%Table1Stratafreqs (NAS_BC_TOTAL);
%Table1Stratafreqs (DISCH_WITH_MOM);
%Table1Stratafreqs (INF_VAC_HBIG);
%Table1Stratafreqs (HIV_DIAGNOSIS);
%Table1Stratafreqs (MOUD_DURING_PREG);
%Table1Stratafreqs (MOUD_AT_DELIVERY);
%Table1Stratafreqs (OUD_CAPTURE);
%Table1Stratafreqs (AGE_BIRTH);
%Table1Stratafreqs (EVER_INCARCERATED);
%Table1Stratafreqs (FOREIGN_BORN);
%Table1Stratafreqs (HOMELESS_HISTORY);
%Table1Stratafreqs (LANGUAGE_SPOKEN);
%Table1Stratafreqs (MOTHER_EDU);
%Table1Stratafreqs (LD_PAY);
%Table1Stratafreqs (KOTELCHUCK);
%Table1Stratafreqs (prenat_site);
%Table1Stratafreqs (MATINF_HEPC);
%Table1Stratafreqs (MATINF_HEPB);
%Table1Stratafreqs (EVER_IDU_HCV);
%Table1Stratafreqs (mental_health_diag);
%Table1Stratafreqs (OTHER_SUBSTANCE_USE);
%Table1Stratafreqs (iji_diag);

%macro Table2Crude (var);
proc logistic data=FINAL_INFANT_COHORT_COV desc; 
	class &var (param=ref);
	model APPROPRIATE_Testing=&var;
	run;
%mend;

%Table2Crude (FINAL_SEX);
%Table2Crude (GESTATIONAL_AGE);
%Table2Crude (FINAL_RE);
%Table2Crude (MOMS_FINAL_RE);
%Table2Crude (FACILITY_ID_BIRTH);
%Table2Crude (Res_Code_Birth);
%Table2Crude (well_child);
%Table2Crude (NAS_BC_TOTAL);
%Table2Crude (DISCH_WITH_MOM);
%Table2Crude (INF_VAC_HBIG);
%Table2Crude (HIV_DIAGNOSIS);
%Table2Crude (MOUD_DURING_PREG);
%Table2Crude (MOUD_AT_DELIVERY);
%Table2Crude (OUD_CAPTURE);
%Table2Crude (AGE_BIRTH);
%Table2Crude (EVER_INCARCERATED);
%Table2Crude (FOREIGN_BORN);
%Table2Crude (HOMELESS_HISTORY);
%Table2Crude (LANGUAGE_SPOKEN);
%Table2Crude (MOTHER_EDU);
%Table2Crude (LD_PAY);
%Table2Crude (KOTELCHUCK);
%Table2Crude (prenat_site);
%Table2Crude (MATINF_HEPC);
%Table2Crude (MATINF_HEPB);
%Table2Crude (EVER_IDU_HCV);
%Table2Crude (mental_health_diag);
%Table2Crude (OTHER_SUBSTANCE_USE);
%Table2Crude (iji_diag);
