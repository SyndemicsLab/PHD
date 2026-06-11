/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/
/* Source: Detox.sas            */
/*==============================*/
/* Builds the monthly and yearly demographic shell tables: the cohort */
/* demographics crossed against every month (1-12) and every year in  */
/* the configured range, so later joins have a complete time scaffold  */
/* to populate. The year range is parsed out of the &year macro range. */

/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/
%LET year = (2015:2023);

/*===============================*/
/*			DATA PULL			 */
/*===============================*/
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

PROC SQL;
    CREATE TABLE shell_summary AS
    SELECT COUNT(*) AS monthly_rows FROM demographics_monthly;
QUIT;

PROC PRINT DATA= years; TITLE "Configured year scaffold"; RUN;
PROC PRINT DATA= shell_summary; TITLE "Monthly shell row count (demographics x 12 months x years)"; RUN;

PROC EXPORT
	DATA= demographics_yearly
	OUTFILE= "./output/demographics_yearly_shell.csv"
	DBMS= csv REPLACE;
RUN;
