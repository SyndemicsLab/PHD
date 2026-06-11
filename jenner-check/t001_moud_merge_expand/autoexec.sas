options obs=100;

/*==============================================================*/
/* Bundle setup for the RESPOND.sas MOUD count-expansion block. */
/* moud_demo is the per-treatment-episode table the script      */
/* derives from PHDSPINE.MOUD joined to demographics: one row    */
/* per (ID, treatment type) with a start and end (date / month / */
/* year) plus race, sex, year-of-birth. We seed it directly with */
/* a few realistic episodes — including two methadone episodes    */
/* less than the leniency window apart, to exercise the merge —   */
/* so the record-merge and month-by-month expansion run as        */
/* written upstream.                                              */
/*==============================================================*/

data moud_demo;
    input ID TYPE_MOUD $ new_start_date new_start_month new_start_year
          new_end_date new_end_month new_end_year FINAL_RE FINAL_SEX YOB;
    datalines;
1 Methadone 20500 3 2016 20650 8 2016 1 1 1985
1 Methadone 20660 8 2016 20800 1 2017 1 1 1985
1 Buprenorphine 21000 7 2017 21200 1 2018 1 1 1985
2 Naltrexone 21500 6 2018 21900 7 2019 2 2 1990
3 Buprenorphine 20800 1 2017 21100 11 2017 3 1 1972
;
run;
