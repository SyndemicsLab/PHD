options obs=100;

/*==============================================================*/
/* Bundle setup for the Detox.sas demographic-shell step.       */
/* Stands in for PHDSPINE.DEMO (the linked demographics spine). */
/* The KEEP/exclusion logic and the cartesian shell build that  */
/* follow are the script's own, unchanged.                      */
/*==============================================================*/
libname PHDSPINE "./phdspine_lib";

data PHDSPINE.DEMO;
    input ID FINAL_RE FINAL_SEX;
    datalines;
1 1 1
2 2 2
3 1 1
4 3 2
5 1 1
6 2 1
7 9 1
8 1 99
9 1 1
10 2 2
;
run;
