options obs=100;

/*==============================================================*/
/* Bundle setup for the RESPOND.sas incarceration (DOC) block.  */
/* doc_monthly is the table the corrections section derives from */
/* PHDDOC.DOC joined to the cohort: one row per admission with    */
/* SAS month-year dates (YYMMN6.) for admission and release,      */
/* plus race, sex, and year-of-birth. Seeded with a person whose  */
/* two stays fall within the leniency window (so they merge) and  */
/* a second person with one stay.                                 */
/*==============================================================*/

data doc_monthly;
    input ID admission release YOB FINAL_RE FINAL_SEX;
    format admission release yymmn6.;
    datalines;
1 20100 20300 1985 1 1
1 20320 20500 1985 1 1
2 20800 21200 1990 2 2
3 21000 21250 1972 3 1
;
run;
