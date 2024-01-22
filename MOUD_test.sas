%LET MOUD_leniency = 7;
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

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

PROC SQL;
    CREATE TABLE medical_age AS 
    SELECT ID, 
           MED_AGE AS age_apcd, 
           MED_ADM_DATE_MONTH AS month_apcd,
           MED_ADM_DATE_YEAR AS year_apcd
    FROM PHDAPCD.MEDICAL;

    CREATE TABLE pharm_age AS
    SELECT ID, 
           PHARM_AGE AS age_pharm, 
           PHARM_FILL_DATE_MONTH AS month_pharm, 
           PHARM_FILL_DATE_YEAR AS year_pharm
    FROM PHDAPCD.PHARMACY;

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
    BY ID;

    RETAIN start_date start_month start_year
    	   end_date end_month end_year  
    	   TYPE_MOUD lag_end;

    IF first.ID THEN DO;
        start_date = DATE_START_MOUD;
        start_month = DATE_START_MONTH_MOUD;
        start_year = DATE_START_YEAR_MOUD;
        end_date = DATE_END_MOUD;
        end_month = DATE_END_MONTH_MOUD;
        end_year = DATE_END_YEAR_MOUD;
        lag_end = .;
        treatment = TYPE_MOUD;
    END;
    ELSE DO;
        diff = DATE_START_MOUD - lag_end;

        IF diff <= &MOUD_leniency THEN DO;
            end_date = DATE_END_MOUD;
            end_month = DATE_END_MONTH_MOUD;
            end_year = DATE_END_YEAR_MOUD;
        END;
        ELSE DO;
            OUTPUT;
            start_date = DATE_START_MOUD;
            start_month = DATE_START_MONTH_MOUD;
            start_year = DATE_START_YEAR_MOUD;
            end_date = DATE_END_MOUD;
            end_month = DATE_END_MONTH_MOUD;
            end_year = DATE_END_YEAR_MOUD;
        END;
    END;

    lag_end = DATE_END_MOUD;

    IF last.ID THEN OUTPUT;

    KEEP ID start_date start_month start_year
            end_date end_month end_year  
            TYPE_MOUD FINAL_RE FINAL_SEX;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID;
	
	IF end_date - start_date < &MOUD_leniency THEN DELETE;
	
    diff = start_date- lag(end_date);
    IF end_date > lag(end_date) THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;
RUN;

PROC SQL;
	CREATE TABLE moud_demo AS
	SELECT DISTINCT * FROM moud_demo
	LEFT JOIN age ON age.ID = moud_demo.ID AND 
					 age.month = moud_demo.start_month AND 
					 age.year = moud_demo.start_year;
QUIT;

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
           FINAL_RE, FINAL_SEX, age,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_demo
    GROUP BY start_month, start_year, TYPE_MOUD, FINAL_RE, FINAL_SEX, age_grp_five;


    CREATE TABLE moud_counts AS
    SELECT year, month, treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    GROUP BY month, year, treatment;

    CREATE TABLE stratif_moud_counts AS
    SELECT year, month, treatment, FINAL_RE, FINAL_SEX, age,
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