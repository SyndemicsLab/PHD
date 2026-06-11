/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/
/* Source: RESPOND.sas (DOC)    */
/*==============================*/
/* Incarceration expansion. Stays closer together than the leniency     */
/* window are merged into a single span, then each span is walked        */
/* day-by-day; a row is emitted on the first day of every month it        */
/* covers, giving the months a person was incarcerated. Counts can then  */
/* be tabulated per month and stratum downstream.                        */

%LET DOC_leniency = 35;

PROC SORT data=doc_monthly;
    BY ID admission;
RUN;

DATA doc_monthly;
    SET doc_monthly;
    BY ID;
    RETAIN new_admission new_release YOB FINAL_RE FINAL_SEX;

    IF FIRST.ID THEN DO;
        new_admission = admission;
        new_release = release;
    END;
    ELSE DO;
        diff = admission - new_release;

        IF diff < &DOC_leniency THEN DO;
            new_release = release;
        END;
        ELSE DO;
            OUTPUT;
            new_admission = admission;
            new_release = release;
        END;
    END;
    IF LAST.ID THEN OUTPUT;
    new_admission = admission;
    new_release = release;

    DROP diff admission release;
RUN;

DATA incar_monthly;
    SET doc_monthly;
    DO date = new_admission TO new_release BY 1;
        IF DAY(INTNX('MONTH', date, 0, 'SAME')) = 1 THEN OUTPUT;
    END;
    FORMAT date YYMMN6.;
RUN;

PROC SQL;
	CREATE TABLE incar_monthly AS
	SELECT DISTINCT ID, date, FINAL_RE, FINAL_SEX
	FROM incar_monthly;
QUIT;

PROC PRINT DATA= incar_monthly; VAR ID date FINAL_RE FINAL_SEX; TITLE "Months of incarceration per person"; RUN;

PROC EXPORT
	DATA= incar_monthly
	OUTFILE= "./output/incar_monthly.csv"
	DBMS= csv REPLACE;
RUN;
