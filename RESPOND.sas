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
	'T40691D','T40692D','T40693D','T40694D', /* Overdose Codes */ 
        'G2067','G2068','G2069','G2070','G2071',
	'G2072','G2074','G2075','G2076','G2077', 
	'G2078','G2079','G2080','H0020','HZ81ZZZ',
 	'HZ91ZZZ','HZ94ZZZ','J0570','J0571','J0572',
  	'J0573','J0574','J0575','J2315','Q9991',
   	'Q9992','S0109', /* MOUD */
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

    /*IF oud_oo = 0 THEN DELETE;*/

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
    /*IF oud_cm = 0 THEN DELETE;*/

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
    /*IF oud_pmp = 0 THEN DELETE;*/

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
    age_grp_five  = put(age, age_grps_five.);
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
    FROM HOCMOUD_SYN2;
    
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
    SELECT moud.*, PHDSPINE.DEMO.FINAL_RE, PHDSPINE.DEMO.FINAL_SEX
    FROM moud
    LEFT JOIN PHDSPINE.DEMO ON moud.ID = PHDSPINE.DEMO.ID;
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
    WHERE FINAL_SEX = 2 and age_grp_five ne ' ' and age_grp_five ne '999';
RUN;

DATA moud_expanded;
    SET moud_expanded;
    WHERE FINAL_SEX = 2 and age_grp_five ne ' ' and age_grp_five ne '999';
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

/* Extract all relevant data */
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

/* ========================================================== */
/*                       Pull Covariates                      */
/* ========================================================== */

/* Join to add covariates */

proc sql;
    create table OUD_HCV_DAA_with_covariates as
    select OUD_HCV_DAA.*, 
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
           birthsmoms.MOTHER_EDU,
           hcv.EVER_IDU_HCV
    from OUD_HCV_DAA
    left join PHDSPINE.DEMO as demographics
    on OUD_HCV_DAA.ID = demographics.ID 
    left join PHDBIRTH.BIRTH_MOM as birthsmoms
    on OUD_HCV_DAA.ID = birthsmoms.ID
    left join PHDHEPC.HCV as hcv
    on OUD_HCV_DAA.ID = hcv.ID;
quit;

%LET MENTAL_HEALTH = ('F20', 'F21', 'F22', 'F23', 'F24', 'F25', 'F28', 'F29',
                      'F30', 'F31', 'F32', 'F33', 'F34', 'F39', 'F40', 'F41',
                      'F42', 'F43', 'F44', 'F45', 'F48');

proc sql;
    create table OUD_HCV_DAA_with_covariates as
    select OUD_HCV_DAA_with_covariates.*,
           case
               when apcd.MED_PROC_CODE in &MENTAL_HEALTH then 1
               when substr(apcd.MED_PROC_CODE, 1, 3) in ('295', '296', '297', '298', '300', '311') then 1
               else 0
           end as mental_health_diag
    from OUD_HCV_DAA_with_covariates
    left join PHDAPCD.MOUD_MEDICAL as apcd
    on OUD_HCV_DAA_with_covariates.ID = apcd.ID;
quit;

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
    create table OUD_HCV_DAA_with_covariates as
    select OUD_HCV_DAA_with_covariates.*, 
           case when apcd.MED_PROC_CODE in &IJI then 1 else 0 end as iji_diag
    from OUD_HCV_DAA_with_covariates
    left join PHDAPCD.MOUD_MEDICAL as apcd
    on OUD_HCV_DAA_with_covariates.ID = apcd.ID;
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
    create table OUD_HCV_DAA_with_covariates as
    select OUD_HCV_DAA_with_covariates.*,
           case 
               when apcd.MED_PROC_CODE in &OTHER_SUBSTANCE_USE then 1
               else
                   case 
                       when exists (
                           select * 
                           from PHDBSAS.BSAS 
                           where ID = OUD_HCV_DAA_with_covariates.ID
                       ) then 1
                       else 0
                   end
           end as OTHER_SUBSTANCE_USE
    from OUD_HCV_DAA_with_covariates
    left join PHDAPCD.MOUD_MEDICAL as apcd on apcd.ID = OUD_HCV_DAA_with_covariates.ID;
quit;

proc sql;
    create table OUD_HCV_DAA_with_covariates as
    select OUD_HCV_DAA_with_covariates.*,
           case
               when apcd.MED_PROC_CODE in &OTHER_SUBSTANCE_USE then 1
               when BSAS.CLT_ENR_PRIMARY_DRUG in (1,2,3,10,11,12) or
                    BSAS.CLT_ENR_SECONDARY_DRUG in (1,2,3,10,11,12) or
                    BSAS.CLT_ENR_TERTIARY_DRUG in (1,2,3,10,11,12) then 1
               else
                   case
                       when exists (
                           select *
                           from PHDBSAS.BSAS
                           where ID = OUD_HCV_DAA_with_covariates.ID
                       ) then 1
                       else 0
                   end
           end as OTHER_SUBSTANCE_USE
    from OUD_HCV_DAA_with_covariates
    left join PHDBSAS.BSAS as bsas on bsas.ID = OUD_HCV_DAA_with_covariates.ID
    left join PHDAPCD.MOUD_MEDICAL as apcd on apcd.ID = OUD_HCV_DAA_with_covariates.ID;
quit;

/* ========================================================== */
/*                       Table 1 and Regressions              */
/* ========================================================== */

%macro Table1Freqs (var);
proc freq data=OUD_HCV_DAA_with_covariates; tables &var / missing; run;
%mend;

%Table1freqs (AGE_BIRTH);
%Table1freqs (FINAL_RE);
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