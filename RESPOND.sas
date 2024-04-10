/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 4/27/2023 			*/
/* Updated: 11/26/2023  		*/
/*==============================*/

/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
%LET year = (2015:2021);
%LET MOUD_leniency = 7;
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

DATA pharm (KEEP= year_pharm month_pharm oud_pharm ID);
    SET PHDAPCD.PHARMACY(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH
                               PHARM_FILL_DATE_YEAR PHARM_ICD ID);
    month_pharm = PHARM_FILL_DATE_MONTH;
    year_pharm = PHARM_FILL_DATE_YEAR;

    IF  PHARM_ICD IN &ICD OR 
        PHARM_NDC IN (&BUP_NDC) THEN oud_pharm = 1;
    ELSE oud_pharm = 0;
RUN;

/*======CASEMIX DATA==========*/
/* ED */
DATA casemix_ed (KEEP= ID oud_cm_ed ED_ID year_cm month_cm);
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

DATA casemix (KEEP = ID oud_cm year_cm month_cm);
    SET casemix;

    IF oud_ed = 9999 THEN oud_ed = 0;
    IF oud_hd = 9999 THEN oud_hd = 0;
    IF oud_oo = 9999 THEN oud_oo = 0;

    IF sum(oud_ed, oud_hd, oud_oo) > 0 THEN oud_cm = 1;
    ELSE oud_cm = 0;
    IF oud_cm = 0 THEN DELETE;

	year_cm = min(year_oo, year_hd, year_cm);
    month_cm = min(month_oo, month_hd, month_cm);
RUN;

/* BSAS */
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
RUN;

PROC SQL;
    CREATE TABLE oud_out AS 
    SELECT DISTINCT year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY year;

    CREATE TABLE stratif_oud_out AS
    SELECT DISTINCT age_grp_five, year, FINAL_SEX, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY age_grp_five, year, FINAL_SEX, FINAL_RE;

    CREATE TABLE oud_monthly_out AS 
    SELECT DISTINCT year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY year;

    CREATE TABLE stratif_oud_monthly_out AS
    SELECT DISTINCT age_grp_five, year, month, FINAL_SEX, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_monthly
    GROUP BY age_grp_five, year, month, FINAL_SEX, FINAL_RE;
QUIT;

PROC EXPORT
	DATA= oud_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_oud_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCount_Stratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_monthly_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCountMonthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_oud_monthly_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDCountMonthly_Stratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/* Data Origin Location */
PROC SQL;
    CREATE TABLE stratif_oud_origin_yearly AS
    SELECT DISTINCT oud_cm AS Casemix,
                    IFN(sum(oud_apcd, oud_pharm)>0, 1, 0) AS APCD,
                    oud_bsas AS BSAS,
                    oud_pmp AS PMP,
                    oud_matris AS Matris,
                    oud_death AS Death,
                    FINAL_RE, FINAL_SEX, year,
                    age_grp_five,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM oud_yearly
    GROUP BY Casemix, APCD, BSAS, PMP, Matris, Death, FINAL_RE, FINAL_SEX, year, age_grp_five;

    CREATE TABLE oud_origin_yearly AS
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
	DATA= stratif_oud_origin_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_Stratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= oud_origin_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OUDOrigin_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

/*==============================*/
/*         MOUD Counts          */
/*==============================*/
DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

PROC SQL;    
    CREATE TABLE moud_demo AS
    SELECT *, DEMO.FINAL_RE, DEMO.FINAL_SEX, DEMO.YOB
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

PROC SQL;
    CREATE TABLE moud_demo AS 
    SELECT * 
    FROM moud_demo
    WHERE ID IN (SELECT DISTINCT ID FROM oud_yearly);
QUIT;

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
					  			ID FINAL_RE FINAL_SEX TYPE_MOUD YOB);
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
    IF end_date < lag(end_date) THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;

    age = start_year - YOB;
    age_grp_five = put(age, age_grps_five.);
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
      postexp_age = year - YOB;
      age_grp_five = put(postexp_age, age_grps_five.);
      OUTPUT;
    END;
RUN;

DATA moud_expanded;
	SET moud_expanded;
	WHERE year IN &year;
RUN;

PROC SQL;                    
    CREATE TABLE moud_starts AS
    SELECT start_month AS month,
           start_year AS year,
           TYPE_MOUD AS treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD;

    CREATE TABLE stratif_moud_starts AS
    SELECT start_month AS month,
           start_year AS year,
           TYPE_MOUD AS treatment,
           FINAL_RE, FINAL_SEX, age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD, FINAL_RE, FINAL_SEX, age_grp_five;

    CREATE TABLE moud_counts AS
    SELECT year, month, treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment;

    CREATE TABLE stratif_moud_counts AS
    SELECT year, month, treatment, FINAL_RE, FINAL_SEX, age_grp_five,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment, FINAL_RE, FINAL_SEX, age_grp_five;
QUIT;

PROC EXPORT
	DATA= moud_counts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCounts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_counts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCounts_Stratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= stratif_moud_starts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_Stratif_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;