/*==============================================*/
/* Project: RESPOND    			                */
/* Author: Ryan O'Dea  			                */ 
/* Created: 1/18/2023		                	*/
/* Updated: 8/24/2023   			            */
/*==============================================*/

/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
%LET years = (2014:2021);

%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));
/*===========AGE================*/
PROC FORMAT;
	VALUE age_grps_ten
		low-10 = '1'
		11-20 = '2'
		21-30 = '3'
		31-40 = '4'
		41-50 = '5'
		51-60 = '6'
		61-70 = '7'
		71-80 = '8'
		81-90 = '9'
		91-high = '10';

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

/*=======NDC CODES========= */
%LET nalt_codes = ('G2073', 'HZ94ZZZ', 'HZ84ZZZ',
                   '65757030001', '63459030042', 'J2315', '54868557400',
                   '54569913900''54569672000','50090307600','50090286600',
                   '16729008101','16729008110','52152010502','52152010530',
                   '53217026130','68084029111','68084029121','52152010504',
                   '42291063230','63629104701','63629104601','68115068030',
                   '65694010010','65694010003','00904703604','43063059115',
                   '76519116005','68094085359','68094085362','00185003930',
                   '00185003901','00406117001','00406117003','47335032688',
                   '47335032683','51224020650','51224020630','00555090201',
                   '00555090202','50436010501','00056001170','00056001130',
                   '00056007950','00056001122','51285027502','51285027501',
                   '00056008050','65757030001','63459030042');

%LET meth_codes = ('G2067', 'G2078', 'H0020', 'HZ81ZZZ', 'HZ91ZZZ', 'S0109');

%LET extra_bup = ('G2068', 'G2069', 'G2070', 'G2071', 'G2072', 'G2079', 
                   'J0570', 'J0571', 'J0572', 'J0573', 'J0574', 'J0575',
                   'Q9991', 'Q9992');

PROC SQL;
    CREATE TABLE bupndc AS
    SELECT DISTINCT NDC 
    FROM PHDPMP.PMP
    WHERE BUP_CAT_PMP = 1;
QUIT;

PROC SQL noprint;
    SELECT quote(trim(NDC), "'") INTO :bup_codes separated by ','
    FROM bupndc;
QUIT;

/*======DEMOGRAPHIC DATA=========*/
DATA demographics;
    SET PHDSPINE.DEMO (KEEP= ID FINAL_RE FINAL_SEX);
RUN;

%let start_year=%scan(%substr(&years,2,%length(&years)-2),1,':');
%let end_year=%scan(%substr(&years,2,%length(&years)-2),2,':');

DATA months; DO month = 1 to 12; OUTPUT; END; RUN;
DATA years; DO year = &start_year to &end_year; OUTPUT; END; RUN;

/*=========APCD DATA=============*/
DATA pharm (KEEP= ID year_pharm month_pharm nalt_pharm age_pharm bup_pharm);
    SET PHDAPCD.PHARMACY(KEEP= PHARM_NDC PHARM_FILL_DATE_MONTH
                               PHARM_FILL_DATE_YEAR ID PHARM_AGE);
    IF PHARM_NDC IN &nalt_codes 
        THEN nalt_pharm = 1;
    ELSE nalt_pharm = 0;

    IF PHARM_NDC IN (&bup_codes) OR 
        PHARM_NDC IN &extra_bup 
        THEN bup_pharm = 1;

    IF PHARM_NDC IN &nalt_codes THEN nalt_pharm = 1;
    ELSE nalt_pharm = 0;

    month_pharm = PHARM_FILL_DATE_MONTH;
    year_pharm = PHARM_FILL_DATE_YEAR;
    age_pharm = PHARM_AGE;
RUN;

DATA apcd (KEEP= ID year_apcd month_apcd nalt_apcd meth_apcd age_apcd);
    SET PHDAPCD.MEDICAL(KEEP= ID MED_AGE MED_FROM_DATE_YEAR MED_FROM_DATE_MONTH
                              MED_PROC_CODE MED_ICD_PROC1-MED_ICD_PROC7);
    cnt_meth = 0;
    cnt_nalt = 0;
    
    ARRAY vars{*} MED_PROC_CODE MED_ICD_PROC1-MED_ICD_PROC7;
        DO i=1 TO dim(vars);
        IF vars[i] IN &meth_codes THEN cnt_meth = cnt_meth + 1;
        IF vars[i] IN &nalt_codes THEN cnt_nalt = cnt_nalt + 1;
        END;
    DROP=i;

    IF cnt_nalt > 0 THEN nalt_apcd = 1;
        ELSE nalt_apcd = 0;
    IF cnt_meth > 0 THEN meth_apcd = 1;
        ELSE meth_apcd = 0;

    age_apcd = MED_AGE;
	year_apcd = MED_FROM_DATE_YEAR;
    month_apcd = MED_FROM_DATE_MONTH;
RUN;

/*======CASEMIX DATA==========*/
/* ED */
DATA casemix_ed (KEEP= ID ED_ID year_cm month_cm age_ed);
	SET PHDCM.ED (KEEP= ID ED_ADMIT_YEAR ED_AGE ED_ID ED_ADMIT_MONTH
				  WHERE= (ED_ADMIT_YEAR IN &years));
	
	age_ed = ED_AGE;
	year_cm = ED_ADMIT_YEAR;
    month_cm = ED_ADMIT_MONTH;
RUN;

/* ED_PROC */
DATA casemix_ed_proc (KEEP= nalt_ed ED_ID meth_ed bup_ed);
	SET PHDCM.ED_PROC (KEEP= ED_ID ED_PROC);

    IF ED_PROC IN &nalt_codes THEN nalt_ed = 1;
    ELSE nalt_ed = 0;

    IF ED_PROC IN &meth_codes THEN meth_ed = 1;
    ELSE meth_ed = 0;

    IF ED_PROC IN (&bup_codes) OR 
        ED_PROC IN &extra_bup THEN bup_ed = 1;
    ELSE bup_ed = 0;
RUN;

/* HD DATA */
DATA hd (KEEP= HD_ID ID year_hd month_hd age_hd);
	SET PHDCM.HD (KEEP= ID HD_ADMIT_YEAR HD_AGE HD_ID HD_ADMIT_MONTH
					WHERE= (HD_ADMIT_YEAR IN &years));
    month_hd = HD_ADMIT_MONTH;
	age_hd = HD_AGE;
	year_hd = HD_ADMIT_YEAR;
RUN;

DATA hd_proc(KEEP = HD_ID nalt_hd meth_hd bup_hd);
    SET PHDCM.HD_PROC (KEEP = HD_ID HD_PROC);

    IF HD_PROC IN &nalt_codes THEN nalt_hd = 1;
    ELSE nalt_hd = 0;

    IF HD_PROC IN &meth_codes THEN meth_hd = 1;
    ELSE meth_hd = 0;

    IF HD_PROC IN (&bup_codes) OR
       HD_PROC IN &extra_bup THEN bup_hd = 1;
    ELSE bup_hd = 0;
RUN;

PROC SQL;
    CREATE TABLE demographics AS
    SELECT * FROM demographics, months, years;

	CREATE TABLE casemix AS 
	SELECT DISTINCT *
	FROM casemix_ed
	LEFT JOIN casemix_ed_proc ON casemix_ed.ED_ID = casemix_ed_proc.ED_ID;

    CREATE TABLE hd AS 
    SELECT DISTINCT * FROM hd
    LEFT JOIN hd_proc ON hd.HD_ID = hd_proc.HD_ID;
QUIT;

/* OO */
DATA oo (KEEP= ID year_oo month_oo age_oo nalt_oo meth_oo bup_oo);
    SET PHDCM.OO (KEEP= ID OO_CPT1-OO_CPT10 OO_ADMIT_YEAR OO_AGE OO_ADMIT_MONTH
                    WHERE= (OO_ADMIT_YEAR IN &years));
    cnt_nalt = 0;
    cnt_meth = 0;
    cnt_bup = 0;

    nalt_oo = 0;
    meth_oo = 0;
    bup_oo = 0;

    ARRAY vars {*} OO_CPT1-OO_CPT10;
        DO i = 1 TO dim(vars);
            IF vars[i] IN &nalt_codes THEN cnt_nalt = cnt_nalt + 1;
            IF vars[i] IN &meth_codes THEN cnt_meth = cnt_meth + 1;
            IF vars[i] IN (&bup_codes) OR vars[i] IN &extra_bup THEN cnt_bup = cnt_bup + 1;
        END;
    
    IF cnt_nalt > 0 THEN nalt_oo = 1;
    IF cnt_meth > 0 THEN meth_oo = 1;
    IF cnt_bup > 0 THEN bup_oo = 1;

    month_oo = OO_ADMIT_MONTH;
	age_oo = OO_AGE;
	year_oo = OO_ADMIT_YEAR;
RUN;

/* MERGE ALL CM */
PROC SQL;
    CREATE TABLE casemix AS
    SELECT DISTINCT *
    FROM casemix
    FULL JOIN hd ON casemix.ID = hd.ID
		AND casemix.year_cm = hd.year_hd
        AND casemix.month_cm = hd.month_hd
    FULL JOIN oo ON hd.ID = oo.ID
		AND casemix.year_cm = oo.year_oo
        AND casemix.month_cm = oo.month_oo;
QUIT;

DATA casemix (KEEP = ID nalt_cm year_cm month_cm age_cm meth_cm bup_cm);
    SET casemix;
    IF nalt_oo = 1 OR 
    	nalt_hd = 1 OR 
    	nalt_ed = 1 THEN nalt_cm = 1;
    ELSE nalt_cm = 0;

    IF meth_oo = 1 OR 
    	meth_hd = 1 OR 
    	meth_ed = 1 THEN meth_cm = 1;
    ELSE meth_cm = 0;

    IF bup_oo = 1 OR 
    	bup_hd = 1 OR 
    	bup_ed = 1 THEN bup_cm = 1;
    ELSE bup_cm = 0;

    age_cm = min(age_oo, age_hd, age_ed);
    month_cm = min(month_oo, month_cm, month_hd);
    year_cm = min(year_oo, year_cm, year_hd);
RUN;

/* BSAS */
DATA bsas;
    SET PHDBSAS.BSAS(KEEP= ID ENR_YEAR_BSAS ENR_MONTH_BSAS
                           CLT_ENR_PRIMARY_DRUG
                           CLT_ENR_SECONDARY_DRUG
                           CLT_ENR_TERTIARY_DRUG
                           PDM_PRV_SERV_CAT
                           PDM_PRV_SERV_TYPE
                           AGE_BSAS
                           METHADONE_BSAS
                    WHERE=(ENR_YEAR_BSAS IN &years));
    month_bsas = ENR_MONTH_BSAS;
    year_bsas = ENR_YEAR_BSAS;
RUN;

/* PMP */

DATA pmp;
    SET PHDPMP.PMP (KEEP=ID DATE_FILLED_YEAR DATE_FILLED_MONTH
                         BUP_CAT_PMP
                         OPIOID_PMP
                         AGE_PMP
                         NDC);
    month_pmp = DATE_FILLED_MONTH;
    year_pmp = DATE_FILLED_YEAR;
RUN;

PROC SQL;
    CREATE TABLE treatment AS
    SELECT DISTINCT * FROM demographics
    LEFT JOIN apcd ON apcd.ID = demographics.ID AND
                      apcd.year_apcd = demographics.year AND 
                      apcd.month_apcd = demographics.month
    LEFT JOIN bsas ON bsas.ID = demographics.ID AND 
                      bsas.year_bsas = demographics.year AND 
                      bsas.month_bsas = demographics.month
    LEFT JOIN pmp ON pmp.ID = demographics.ID AND
                     pmp.year_pmp = demographics.year AND
                     pmp.month_pmp = demographics.month
    LEFT JOIN pharm ON pharm.ID = demographics.ID AND 
                     pharm.year_pharm = demographics.year AND
                     pharm.month_pharm = demographics.month
    LEFT JOIN casemix ON casemix.ID = demographics.ID AND
                     casemix.year_cm = demographics.year AND
                     casemix.month_cm = demographics.month;
QUIT;

PROC STDIZE DATA = treatment OUT = treatment reponly missing = 9999; RUN;

DATA treatment(KEEP= ID FINAL_RE FINAL_SEX age_grp_ten age_grp_five treatment age
                     month year);
    SET treatment;

    age = min(age_bsas, age_pmp, age_cm, age_apcd, age_pharm);
    age_grp_ten = put(age, age_grps_ten.);
    age_grp_five = put(age, age_grps_five.);

    IF CLT_ENR_PRIMARY_DRUG IN (5:7, 21, 22, 24, 26) OR
       CLT_ENR_SECONDARY_DRUG IN (5:7, 21, 22, 24, 26) OR
       CLT_ENR_TERTIARY_DRUG IN (5:7, 21, 22, 24, 26) AND 
       PDM_PRV_SERV_TYPE = 30 THEN detox = 1;
    ELSE detox = 0;

    IF BUP_CAT_PMP = 1 OR
        bup_pharm = 1 OR
        bup_cm = 1 OR 
        METHADONE_BSAS = 2 THEN bup = 1;
    ELSE bup = 0;

    IF METHADONE_BSAS = 1 OR
        meth_apcd = 1 OR
        meth_cm = 1 THEN methadone = 1;
    ELSE methadone = 0;

    IF NDC IN &nalt_codes OR 
        nalt_apcd = 1 OR 
        nalt_pharm = 1 OR
        nalt_cm = 1  OR 
        METHADONE_BSAS = 3 THEN naltrexone = 1;
    ELSE naltrexone = 0;

    tx_sum = sum(methadone, bup, naltrexone);

    treatment = "None";
    IF detox = 1 THEN treatment = "Detox";
    IF methadone = 1 THEN treatment = "Methadone";
    IF bup = 1 THEN treatment = "Buprenorphine";
    IF naltrexone = 1 THEN treatment = "Naltrexone";
    IF detox = 0 AND tx_sum > 1 THEN treatment = "Multiple MOUD";
    IF detox = 1 AND tx_sum > 1 THEN treatment = "Detox and MOUD";
    
    IF treatment = "None" THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE treatment_dis AS
    SELECT DISTINCT * FROM treatment;
QUIT;

PROC SORT data = treatment_dis;
    BY ID year month;
RUN;

DATA out_sorted;
    SET treatment_dis;
    BY ID;

    last_month = lag(month);
    last_year = lag(year);

    IF FIRST.ID THEN DO;
        month_diff = .;
        year_diff = .;
    END;
    ELSE DO;
        month_diff = month - last_month;
        year_diff = year - last_year;
    END;

    flag = 0;
    IF missing(month_diff) THEN flag = flag + 1;

    IF treatment IN ("Methadone", "Buprenorphine") AND year_diff = 0 AND month_diff > 0 THEN flag = flag + 1;
        ELSE IF treatment IN ("Methadone", "Buprenorphine") AND year_diff = 1 AND month_diff < 0 THEN flag = flag + 1;
        ELSE IF treatment IN ("Methadone", "Buprenorphine") AND year_diff > 1 THEN flag = flag + 1;
        
    IF treatment = "Detox" THEN flag = flag + 1;

    IF treatment = "Naltrexone" AND year_diff = 0 AND month_diff > 1 THEN flag = flag + 1;
        ELSE IF treatment = "Naltrexone" AND year_diff = 1 AND month_diff < -1 THEN flag = flag + 1;
        ELSE IF treatment = "Naltrexone" AND year_diff > 1 THEN flag = flag + 1;

    IF flag = 0 THEN DELETE;
RUN;

/* Treatment COUNTS Per Year-Month */
PROC SQL;
    CREATE TABLE out_10 AS
    SELECT DISTINCT age_grp_ten, FINAL_RE, FINAL_SEX, year, month, treatment,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM treatment
    GROUP BY year, month, treatment, age_grp_ten, FINAL_SEX, FINAL_RE;

    CREATE TABLE out_5 AS
    SELECT DISTINCT age_grp_five, FINAL_RE, FINAL_SEX, year, month, treatment,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM treatment
    GROUP BY year, month, treatment, age_grp_five, FINAL_SEX, FINAL_RE;

/* Treatment STARTS Per Year-Month */
    CREATE TABLE out_table_10 AS
    SELECT DISTINCT age_grp_ten, FINAL_RE, FINAL_SEX, year, month, treatment,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM out_sorted
    GROUP BY year, month, treatment, age_grp_ten, FINAL_SEX, FINAL_RE;

    CREATE TABLE out_table_5 AS
    SELECT DISTINCT age_grp_five, FINAL_RE, FINAL_SEX, year, month, treatment,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM out_sorted
    GROUP BY year, month, treatment, age_grp_five, FINAL_SEX, FINAL_RE;
QUIT;

PROC EXPORT
	DATA= out_table_10
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TreatmentStarts_Ten_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= out_table_5
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TreatmentStarts_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= out_10
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TreatmentCounts_Ten_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= out_5
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TreatmentCounts_Five_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;