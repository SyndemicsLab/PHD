options obs=100;

/*==============================================================*/
/* Bundle setup for the RESPOND.sas incarceration-length block. */
/* doc_frq_tmp is the per-person table the corrections section  */
/* derives from PHDDOC.DOC joined to the cohort: one row per ID  */
/* with the length of stay (n_days), race, sex, and age band.   */
/* We seed it directly with realistic stay lengths so the PROC  */
/* FREQ distribution + small-cell suppression run as written.   */
/*==============================================================*/

data doc_frq_tmp;
    input ID n_days FINAL_RE FINAL_SEX age_grp_twenty $ age_grp_five $;
    datalines;
1 35 1 1 2 5
2 35 1 2 2 6
3 90 2 1 3 9
4 90 2 2 3 10
5 35 1 1 2 5
6 120 1 1 4 13
7 35 1 1 2 5
8 60 2 2 3 8
9 90 1 1 3 9
10 35 1 2 2 6
11 200 3 1 4 14
12 60 1 1 3 8
13 35 2 1 2 5
14 90 1 2 3 10
15 35 1 1 2 5
;
run;
