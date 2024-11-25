/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 11/25/2024 			*/
/* Updated:                		*/
/*==============================*/
/* 
Pulls detox admissions to BSAS - intended to extend to detox admission to the APCD
*/
/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
%LET year = (2015:2022);
%LET today = %sysfunc(today(), date9.);
%LET formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));
/* future use with apcd */
%LET proc_codes = ('H0008', 'H00009', 'H0010', 'H0011', 'H0012', 'H0013'); 

/*===========AGE================*/
PROC FORMAT;
    VALUE age_grps_twenty
    low-20 = '1' 21-40 = '2'
    41-60 = '3' 61-80 = '4'
    81-998 = '5' 999 = '999';

/*===============================*/            
/*			DATA PULL			 */
/*===============================*/ 
/*======DEMOGRAPHIC DATA=========*/

DATA demographics;
    SET PHDSPINE.DEMO (KEEP= ID FINAL_RE FINAL_SEX);
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

/*======BSAS DATA=========*/
DATA bsas_detox(KEEP = ID year_bsas month_bsas age_bsas);
    SET PHDBSAS.BSAS;
    IF PDM_PRV_SERV_TYPE IN (5, 52) AND CLT_ENR_SECTION35_BSAS NE 1 THEN detox_flag = 1;
    ELSE detox_flag = 0;

    IF detox_flag = 0 THEN DELETE;
    year_bsas = ENR_YEAR_BSAS;
    month_bsas = ENR_MONTH_BSAS;
RUN; 

/*===============================*/            
/*			DATA MERGE			 */
/*===============================*/ 

PROC SQL;
    CREATE TABLE bsas_detox AS
    SELECT DISTINCT * 
    FROM bsas_detox;

    CREATE TABLE detox_admits_monthly AS
    SELECT * FROM demographics_monthly
    LEFT JOIN bsas_detox on bsas_detox.ID = demographics_monthly.ID
        AND bsas_detox.year_bsas = demographics_monthly.year
        AND bsas_detox.month_bsas = demographics_monthly.month;
    
    CREATE TABLE detox_admits_yearly AS 
    SELECT * FROM demographics_yearly
    LEFT JOIN bsas_detox on bsas_detox.ID = demographics_yearly.ID
        AND bsas_detox.year_bsas = demographics_yearly.year;
QUIT;


DATA detox_admits_monthly;
    SET detox_admits_monthly;
    age_grp_twenty = put(age_bsas, age_grps_twenty.);
RUN;

DATA detox_admits_yearly;
    SET detox_admits_yearly;
    age_grp_twenty = put(age_bsas, age_grps_twenty.);
RUN;

PROC SQL;
    CREATE TABLE detox_out_yearly AS
    SELECT DISTINCT year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_yearly
    GROUP BY year;

    CREATE TABLE detox_out_monthly AS
    SELECT DISTINCT year, month,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_monthly
    GROUP BY year, month;

    CREATE TABLE detox_twenty_monthly AS 
    SELECT DISTINCT age_grp_twenty, year, month,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_monthly
    GROUP BY year, month, age_grp_twenty;

    CREATE TABLE detox_twenty_yearly AS 
    SELECT DISTINCT age_grp_twenty, year,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_yearly
    GROUP BY year, month, age_grp_twenty;
    
    CREATE TABLE detox_race_monthly AS
    SELECT DISTINCT year, month, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_monthly
    GROUP BY year, month, FINAL_RE;

    CREATE TABLE detox_race_yearly AS 
    SELECT DISTINCT year, FINAL_RE,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_yearly
    GROUP BY year, FINAL_RE;

    CREATE TABLE detox_sex_yearly AS 
    SELECT DISTINCT year, FINAL_SEX,
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_yearly
    GROUP BY year, FINAL_SEX;

    CREATE TABLE detox_sex_monthly AS 
    SELECT DISTINCT year, month, FINAL_SEX, 
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM detox_admits_monthly
    GROUP BY year, month, FINAL_SEX;
QUIT;

PROC EXPORT
	DATA= detox_out_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_out_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_twenty_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Twenty_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_twenty_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Twenty_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_sex_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Sex_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_sex_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Sex_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= detox_race_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Race_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= Detox_race_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/Detox_Race_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;