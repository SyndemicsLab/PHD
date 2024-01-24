/*==============================================*/
/* Project: RESPOND    			                */
/* Author: Ryan O'Dea  			                */ 
/* Created: 12/26/2022 		                	*/
/* Updated: 2/8/2023   			                */
/*==============================================*/
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
		91-998 = '10'
		999 = '999';

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
	VALUE age_grps
		low-17 = '1'
		18-30 = '2'
		31-60 = '3'
		61-90 = '4'
		91-998 = '5'
		999 = '999';
/*==============DEMO DATA=====================*/
PROC SQL;
	CREATE TABLE demographics AS
	SELECT DISTINCT ID, FINAL_RE, FINAL_SEX
	FROM PHDSPINE.DEMO;
QUIT;

/*==============DEATH COUNT=====================*/
DATA death_raw (KEEP= ID od_death year month age_grp age_grp_ten age_grp_five);
    SET PHDDEATH.DEATH (KEEP= ID OPIOID_DEATH YEAR_DEATH AGE_DEATH MONTH_DEATH);
    IF OPIOID_DEATH = 1 THEN od_death = 1;
    ELSE od_death = 0;
    
    age = AGE_DEATH;
    year = YEAR_DEATH;
	month = MONTH_DEATH;

    age_grp_ten = put(age, age_grps_ten.);
    age_grp_five = put(age, age_grps_five.);
	age_grp = put(age, age_grps.);
RUN;

PROC SQL;
    CREATE TABLE out AS 
    SELECT * FROM death_raw
    LEFT JOIN demographics ON death_raw.ID = demographics.ID;

	CREATE TABLE death_ten AS
    SELECT age_grp_ten, FINAL_RE, FINAL_SEX, year, od_death,
    IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
    FROM out
    GROUP BY od_death, year, age_grp_ten, FINAL_RE, FINAL_SEX;

	CREATE TABLE death_five AS
    SELECT age_grp_five, FINAL_RE, FINAL_SEX, year, od_death,
    IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
    FROM out
    GROUP BY od_death, year, age_grp_five, FINAL_RE, FINAL_SEX;

	CREATE TABLE death_monthly AS
	SELECT age_grp, FINAL_RE, FINAL_SEX, year, month, od_death,
	IFN(count(DISTINCT ID) IN (1:10), -1, count(DISTINCT ID)) AS N_ID
	FROM out
	GROUP BY od_death, year, month, age_grp, FINAL_RE, FINAL_SEX;
QUIT;

PROC EXPORT DATA = death_ten
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Ten_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_five
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Five_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;

PROC EXPORT DATA = death_monthly
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCountMonthly_&formatted_date..csv"
	DBMS = csv REPLACE;
RUN;