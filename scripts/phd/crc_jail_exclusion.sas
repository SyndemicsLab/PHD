/*============================================================================*/
/* File: crc_jail_exclusion.sas                                               */
/* Project: PHD                                                               */
/* Author: Grace Namirembe                                                    */
/* -----                                                                      */
/* Modified By: Grace Namirembe                                               */
/* -----                                                                      */
/* Copyright (c) 2026 Massaschusetts Department of Public Health              */
/*============================================================================*/
/* Purpose: To remove people who were in jail everyday from the BSAS dataset */
/* Author: GEN, 03/13/26 */
%let year=2015;

/* BSAS subset of IDs in jail/prison */
data bsas_jail;
    set PHDBSAS.BSAS (keep=ID ENR_YEAR_BSAS PDM_PRV_SERV_TYPE);
    where PDM_PRV_SERV_TYPE in (15,98) & ENR_YEAR_BSAS=&year.;
run;

/* Bring in the HOC file */

/* Keeping individuals who were in jail throughout the year */
data hoc_all_&year. (keep=ID los_hoc);
    set PHDHOC.HOC;
    los_hoc=release_date_hoc - admit_date_hoc;
    where admit_year_hoc < &year. & release_year_hoc > &year.;
run;

/* Minimum LOS is 385 days - all were in jail throughout the year */
proc univariate data=hoc_all_&year.;
    var los_hoc;
run;

/* We have repeat incarcerations within this period. Dedup */
proc sort data=hoc_all_&year. nodupkey;
    by ID /*admit_date_hoc release_date_hoc*/;
run;
/* these are unique IDs in jail throughout 2020*/

/* Check DOC */
data doc_all_&year. (keep=ID los_doc);
    set PHDDOC.DOC;
    los_doc=release_date_doc - admit_recent_date_doc;
    where admit_recent_year_doc < &year. & release_year_doc > &year.;
run;

proc means data=doc_all_&year.;
    var los_doc;
run;

proc sort data=doc_all_&year. nodupkey;
    by ID ;
run;

/* Combine HOC and DOC */
data hoc_doc_&year.;
    set hoc_all_&year. (rename=(los_hoc=los)) doc_all_&year. (rename=(los_doc=
        los));
run;

/* Dedup */
proc sql;
    create table hoc_doc_&year. as select distinct ID, los from hoc_doc_&year.;
quit;

proc contents data=hoc_doc_&year.;
run;

/* Confirm that there are individuals from BSAS who were in jail/prison everyday? */
proc sort data=bsas_jail nodupkey;
    by ID;
run;

proc sql;
    create table bsas_hocdoc_&year. as select distinct a.*, b.* from bsas_jail
        as a left join hoc_doc_&year. as b on a.id=b.id where b.id is not null;
quit;

/* IDs in BSAS were in jail/prison everyday of the year */
proc print data=bsas_hocdoc_&year. (obs=100);
run;

/* Remove these from the main BSAS dataset in the OUD definition */
