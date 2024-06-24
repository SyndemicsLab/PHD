/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 4/27/2023 			*/
/* Updated: 6/24/2024   		*/
/*==============================*/

/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
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

PROC SQL;
	CREATE TABLE OD_demo AS
	SELECT overdose.OD_YEAR, overdose.OD_MONTH, overdose.FATAL_OD_DEATH AS fod, overdose.ID,
		   demo.FINAL_RE, demo.FINAL_SEX, demo.YOB
	FROM PHDSPINE.OVERDOSE
	LEFT JOIN PHDSPINE.DEMO ON demo.ID = overdose.ID;
QUIT;

DATA OD;
	SET OD_demo;
	
	age = OD_YEAR - YOB;
	age_grp_five = put(age, age_grps_five.);
	age_grp_twenty = put(age, age_grps_twenty.);
	
	IF FINAL_RE = 9 THEN DELETE;
	IF FINAL_RE = 99 THEN DELETE;
	IF FINAL_SEX = 9 THEN DELETE;
	IF FINAL_SEX = 99 THEN DELETE;
RUN;

PROC SQL;
	CREATE TABLE overdose_five_monthly AS 
	SELECT age_grp_five, fod, OD_YEAR AS year, OD_MONTH AS month,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_five, fod, OD_YEAR, OD_MONTH;
	
	CREATE TABLE overdose_twenty_monthly AS 
	SELECT age_grp_twenty, fod, OD_YEAR AS year, OD_MONTH AS month,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_twenty, fod, OD_YEAR, OD_MONTH;

	CREATE TABLE overdose_five_yearly AS 
	SELECT age_grp_five, fod, OD_YEAR AS year,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_five, fod, OD_YEAR;
	
	CREATE TABLE overdose_twenty_yearly AS 
	SELECT age_grp_twenty, fod, OD_YEAR AS year,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_twenty, fod, OD_YEAR;

	CREATE TABLE overdose_race_monthly AS 
	SELECT fod, OD_YEAR AS year, OD_MONTH AS month, FINAL_RE,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY fod, OD_YEAR, OD_MONTH, FINAL_RE;

	CREATE TABLE overdose_race_yearly AS
	SELECT fod, OD_YEAR AS year, FINAL_RE,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY fod, OD_YEAR, FINAL_RE;

	CREATE TABLE overdose_sex_monthly AS 
	SELECT fod, OD_YEAR AS year, OD_MONTH AS month, FINAL_SEX,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY fod, OD_YEAR, OD_MONTH, FINAL_SEX;

	CREATE TABLE overdose_sex_yearly AS 
	SELECT fod, OD_YEAR AS year, FINAL_SEX,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY fod, OD_YEAR, FINAL_SEX;
QUIT;

PROC EXPORT
	DATA= overdose_five_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseFive_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_twenty_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseTwenty_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_five_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseFive_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_twenty_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseTwenty_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_race_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseRace_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_race_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseRace_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_sex_monthly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseSex_Monthly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_sex_yearly
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseSex_Yearly_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;