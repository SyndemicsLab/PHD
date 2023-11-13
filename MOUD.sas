/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 11/13/2023 			*/
/* Updated:            			*/
/*==============================*/
%LET year = (2015:2021)
%LET today = %sysfunc(today(), date9.);
%LET formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

DATA moud_expanded(KEEP= ID month year treatment);
    SET PHDSPINE.MOUD;
    treatment = TYPE_MOUD;

    FORMAT year 4. month 2.;
    
    num_months = intck('month', input(put(DATE_START_YEAR_MOUD, 4.) || put(DATE_START_MONTH_MOUD, z2.), yymmn6.), 
                       input(put(DATE_END_YEAR_MOUD, 4.) || put(DATE_END_MONTH_MOUD, z2.), yymmn6.));

    DO i = 0 to num_months;
      new_date = intnx('month', input(put(DATE_START_YEAR_MOUD, 4.) || put(DATE_START_MONTH_MOUD, z2.), yymmn6.), i);
      year = year(new_date);
      month = month(new_date);
      OUTPUT;
    END;
RUN;

PROC SQL;
    CREATE TABLE moud_starts AS
    SELECT DATE_START_MONTH_MOUD AS month,
           DATE_START_YEAR_MOUD AS year,
           TYPE_MOUD AS treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM PHDSPINE.MOUD
    WHERE year BETWEEN %SCAN(&year,1,':') AND %SCAN(&year,2,':')
    GROUP BY month, year, treatment;

    CREATE TABLE moud_counts AS
    SELECT year, month, treatment,
           IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM moud_expanded
    WHERE year BETWEEN %SCAN(&year,1,':') AND %SCAN(&year,2,':')
    GROUP BY month, year, treatment;
QUIT;

PROC EXPORT
	DATA= moud_counts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDCounts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= moud_starts
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MOUDStarts_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;