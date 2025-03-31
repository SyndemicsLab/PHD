/*==============================================*/
/* Project: RESPOND    			                */
/* Author: Ryan O'Dea  			                */ 
/* Created: 12/26/2022 		                	*/
/* Updated: 4/15/2024  			                */
/*==============================================*/
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

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
/*==============DEMO DATA=====================*/
DATA demographics;
    SET PHDSPINE.DEMO (KEEP= ID FINAL_RE FINAL_SEX YOB);
    IF FINAL_RE = 9 THEN DELETE;
    IF FINAL_RE = 99 THEN DELETE;

    IF FINAL_SEX = 9 THEN DELETE;
    IF FINAL_SEX = 99 THEN DELETE;
RUN;


/*==============DEATH COUNT=====================*/
PROC SQL;
	CREATE TABLE death_raw AS 
	SELECT death.OPIOID_DEATH AS od_death, death.YEAR_DEATH AS year, death.MONTH_DEATH AS month,
		   demo.YOB, demo.FINAL_RE, demo.FINAL_SEX, demo.ID
	FROM PHDDEATH.DEATH death
	LEFT JOIN demographics demo ON death.ID = demo.ID;
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

PROC EXPORT DATA = death_yearly_race
	OUTFILE = "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/DeathCount_Race_Yearly_&formatted_date..csv"
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
