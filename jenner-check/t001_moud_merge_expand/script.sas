/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/
/* Source: RESPOND.sas (MOUD)   */
/*==============================*/
/* Medications for Opioid Use Disorder (MOUD) count expansion.          */
/* Episodes closer together than the leniency window are merged, then   */
/* short residual records and records fully encompassed by another are  */
/* dropped. Each surviving episode is "expanded" into one row per month */
/* it spans, so monthly treatment counts can be tabulated downstream.   */

%LET MOUD_leniency = 30;

PROC SORT data=moud_demo;
    BY ID new_start_date;
RUN;

DATA moud_demo;
    SET moud_demo;
    BY ID;

	IF new_end_date - new_start_date < &MOUD_leniency THEN DELETE;
	NED = lag(new_end_date);

	IF FIRST.ID THEN diff = .;
	ELSE diff = new_start_date - NED;
    IF new_end_date < NED THEN temp_flag = 1;
    ELSE temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    ELSE IF diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    ELSE flag_mim = 0;

    IF flag_mim = 1 THEN DELETE;

    DROP NED;
RUN;

DATA moud_expanded(KEEP= ID month year treatment FINAL_SEX FINAL_RE);
    SET moud_demo;
    treatment = TYPE_MOUD;

    FORMAT year 4. month 2.;

    num_months = intck('month', input(put(new_start_year, 4.) || put(new_start_month, z2.), yymmn6.),
                       input(put(new_end_year, 4.) || put(new_end_month, z2.), yymmn6.));

    DO i = 0 to num_months;
      new_date = intnx('month', input(put(new_start_year, 4.) || put(new_start_month, z2.), yymmn6.), i);
      year = year(new_date);
      month = month(new_date);
      OUTPUT;
    END;
RUN;

PROC SQL;
    CREATE TABLE moud_expanded AS
    SELECT DISTINCT * FROM moud_expanded;
QUIT;

PROC PRINT DATA= moud_expanded; TITLE "MOUD episodes expanded to monthly rows"; RUN;

PROC EXPORT
	DATA= moud_expanded
	OUTFILE= "./output/moud_expanded.csv"
	DBMS= csv REPLACE;
RUN;
