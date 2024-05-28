/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 4/27/2023 			*/
/* Updated: 5/28/2024   		*/
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
    VALUE age_grps_ten
        low-10 = '1' 11-20 = '2'
        21-30 = '3' 31-40 = '4'
        41-50 = '5' 51-60 = '6'
        61-70 = '7' 71-80 = '8'
        81-90 = '9' 91-998 = '10'
        999 = '999';

PROC FORMAT;
    VALUE age_grps_fifteen
        low-15 = '1' 16-30 = '2'
        31-45 = '3' 46-60 = '4'
        61-75 = '5' 76-90 = '6'
        90-998 = '7' 999 = '999';

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
	age_grp_ten = put(age, age_grps_ten.);
	age_grp_fifteen = put(age, age_grps_fifteen.);
	age_grp_twenty = put(age, age_grps_twenty.);
	
	IF FINAL_RE = 9 THEN DELETE;
	IF FINAL_RE = 99 THEN DELETE;
	IF FINAL_SEX = 9 THEN DELETE;
	IF FINAL_SEX = 99 THEN DELETE;
RUN;

PROC SQL;
	CREATE TABLE overdose_five AS 
	SELECT age_grp_five, FINAL_RE, FINAL_SEX, fod,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_five, FINAL_RE, FINAL_SEX, fod;
	
	CREATE TABLE overdose_ten AS 
	SELECT age_grp_ten, FINAL_RE, FINAL_SEX, fod,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_ten, FINAL_RE, FINAL_SEX, fod;
	
	CREATE TABLE overdose_fifteen AS 
	SELECT age_grp_fifteen, FINAL_RE, FINAL_SEX, fod,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_fifteen, FINAL_RE, FINAL_SEX, fod;
	
	CREATE TABLE overdose_twenty AS 
	SELECT age_grp_twenty, FINAL_RE, FINAL_SEX, fod,
	IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
	FROM OD
	GROUP BY age_grp_twenty, FINAL_RE, FINAL_SEX, fod;
QUIT;

PROC EXPORT
	DATA= overdose_five
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseFive_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_ten
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseTen_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_fifteen
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseFifteen_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= overdose_twenty
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/OverdoseTwenty_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;