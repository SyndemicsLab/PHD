/*============================================================================*/
/* File: crc_2020_on.sas                                                      */
/* Project: PHD                                                               */
/* Author: Jianing Wang                                                       */
/* -----                                                                      */
/* Modified By: Grace Namirembe                                               */
/* -----                                                                      */
/* Copyright (c) 2026 Massaschusetts Department of Public Health              */
/*============================================================================*/
/*MACROS TO UPDATE*/
%LET FOURYR=2022;
%LET TWOYR=22;

/* Obtain the sex and race information from the master demographic dataset */

/* PHDSPINE.DEMO */
DATA demo_race_sex;
    SET PHDSPINE.DEMO (KEEP=ID FINAL_SEX FINAL_RE);
RUN;

PROC SQL;
    CREATE TABLE demo_race_sex AS SELECT DISTINCT ID, FINAL_SEX, FINAL_RE FROM
        demo_race_sex ;
QUIT;

/* Remove labels */
PROC DATASETS LIBRARY=WORK NOLIST;
    MODIFY demo_race_sex;
    ATTRIB _all_ label='';
QUIT;

/* Identify OUD cases from individual data source */

/* APCD MEDICAL*/
DATA apcd_&TWOYR. (KEEP=ID oud_apcd) apcd_&TWOYR._OD (keep=ID MED_FROM_DATE);
    SET PHDAPCD.MEDICAL (KEEP=ID MED_ECODE MED_ADM_DIAGNOSIS MED_DIS_DIAGNOSIS
        MED_ICD_PROC1-MED_ICD_PROC7 MED_PROC_CODE MED_ICD1-MED_ICD25 MED_AGE
        MED_SEX MED_FROM_DATE_YEAR MED_FROM_DATE WHERE=(MED_FROM_DATE_YEAR=
        &fouryr.));
    ct_oud_apcd1=0;
    ct_oud_apcd2=0;
    ct_oud_apcd3=0;

    oud_apcd=0;

    ARRAY vars1 {*} MED_ECODE MED_ADM_DIAGNOSIS MED_DIS_DIAGNOSIS
        MED_ICD1-MED_ICD25;
    ARRAY var_new{1} MED_PROC_CODE;
    ARRAY var_new2 {7} MED_ICD_PROC1-MED_ICD_PROC7;

    /* Demography */
    /* Age */
    agenum_apcd=.;
    agenum_apcd=MED_AGE;
    IF agenum_apcd < 18 OR agenum_apcd > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
    DO i=1 TO dim(vars1);
        IF vars1[i] in ("30400", "30401", "30402", "30470", "30471", "30472",
            "30550", "30551", "30552", "F1110", "F11120", "F11121", "F11122",
            "F11129", "F1113", "F1114", "F11150", "F11151", "F11159", "F11181",
            "F11182", "F11188", "F1119", "F1120", "F11220", "F11221", "F11222",
            "F11229", "F1123", "F1124", "F11250", "F11251", "F11259", "F11281",
            "F11282", "F11288", "F1129") THEN ct_oud_apcd1 + 1;

        IF vars1[i] in ( "E8500", "E8501", "E8502", "96500", "96501", "96502",
            "96509", "9701", "T400X1A", "T400X2A", "T400X3A", "T400X4A",
            "T400X1D", "T400X2D", "T400X3D", "T400X4D", "T401X1A", "T401X2A",
            "T401X3A", "T401X4A", "T401X1D", "T401X2D", "T401X3D", "T401X4D",
            "T402X1A", "T402X2A", "T402X3A", "T402X4A", "T402X1D", "T402X2D",
            "T402X3D", "T402X4D", "T403X1A", "T403X2A", "T403X3A", "T403X4A",
            "T403X1D", "T403X2D", "T403X3D", "T403X4D", "T404X1A", "T404X2A",
            "T404X3A", "T404X4A", "T404X1D", "T404X2D", "T404X3D", "T404X4D",
            "T40601A", "T40601D", "T40602A", "T40602D", "T40603A", "T40603D",
            "T40604A", "T40604D", "T40691A", "T40692A", "T40693A", "T40694A",
            "T40691D", "T40692D", "T40693D", "T40694D") THEN OUTPUT
            apcd_&TWOYR._OD;
    END;

    DO j=1 TO dim(var_new2);
        IF var_new2[j] in ("HZ91ZZZ", "HZ81ZZZ") THEN ct_oud_apcd2 + 1;
    END;

    DO k=1 TO dim(var_new);
        IF var_new[k] in ("G2215", "G2216", "G1028", "J0592", "G2068", "G2069",
            "G2070", "G2071", "G2072", "G2079", "J0570", "J0571", "J0572",
            "J0573", "J0574", "J0575", "Q9991", "Q9992", "H0020", "G2067",
            "G2078", "S0109") THEN ct_oud_apcd3 + 1;
    END;

    DROP i j k;
    IF ct_oud_apcd1 > 0 OR ct_oud_apcd2 > 0 OR ct_oud_apcd3 > 0 THEN DO;
        oud_apcd=1;
        OUTPUT apcd_&TWOYR.;
    end;

    IF oud_apcd=0 THEN DELETE;
    /* Can delete because the contingency table would refill 0 */
RUN;

/*deduplicate the OD count to remove extra APCD claim rows*/
Proc sql;
    Create table apcd_&TWOYR._OD2 as Select distinct ID, MED_FROM_DATE from
        apcd_&TWOYR._OD order by id, med_from_date;
quit;

data apcd_&TWOYR._OD3 (keep=id oud_apcd);
    set apcd_&TWOYR._OD2;
    by id med_from_date;
    retain startdt;
    oud_apcd=1;
    if first.id=last.id then delete;
    if first.id then startdt=med_from_date;
    else if last.id then diff=med_from_date-startdt;
    if diff>1 then output;
run;

data apcd_&TWOYR;
    set apcd_&TWOYR._OD3 /*(drop =oud_apcd)*/ apcd_&TWOYR;
run;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE apcd_&TWOYR. AS SELECT DISTINCT ID, oud_apcd FROM apcd_&TWOYR.
        ;
QUIT;

/* Print the total observed counts */
PROC SQL;
    TITLE "APCD Crude - oud_apcd(&fouryr.)";
    SELECT oud_apcd, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10,
        -1, COUNT(distinct ID)) AS N_ID_supp FROM apcd_&TWOYR. GROUP BY oud_apcd
        /* This is dummy (same as follows), this is useful if we do not remove oud_apcd = 0 in the previous step */
        ;
    TITLE;
QUIT;

**PHDAPCD.PHARMACY**;
proc sql;
    create table temp_bup as select distinct ndc as noq_NDC from PHDPMP.PMP
        where BUP_CAT_PMP=1;
quit;

data temp_bup2;
    set temp_bup;
    ndc=cats("'",noq_NDC,"'");
    keep ndc;
run;

proc sql noprint;
    select distinct ndc into :bup_ndc separated by ',' from temp_bup2;
quit;

data pharm_&twoyr. (keep=ID oud_pharm);
    set phdapcd.pharmacy;
    if pharm_ndc in (&bup_ndc) then oud_pharm=1;
    else oud_pharm=0;
    if oud_pharm=0 then delete;
    if PHARM_AGE < 18 OR PHARM_AGE > 64 THEN DELETE;
    where PHARM_FILL_DATE_YEAR=&fouryr.;
run;

/* Remove the duplicated ID */
PROC SQL;
    CREATE TABLE pharm2_&twoyr. AS SELECT DISTINCT ID, oud_pharm FROM
        pharm_&twoyr. /* WHERE oud_pharm = 1 GRACE: YOU DELETED THE 0s ABOVE*/ ;
QUIT;

/* Print the total observed counts - PHARMACY */
TITLE "PHARMACY Crude - oud_pharm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_pharm, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM pharm2_&twoyr. GROUP BY
        oud_pharm ;
QUIT;
TITLE;

/* Merge PHARMACY with MEDICAL*/
PROC SQL;
    CREATE TABLE apcd_pharm_&TWOYR. AS SELECT DISTINCT apcd_pharm.apcd_pharm_ID
        AS ID, apcd_pharm.oud_apcd, apcd_pharm.oud_pharm FROM (SELECT
        coalesce(apcd.ID, pharm.ID) AS apcd_pharm_ID, apcd.*, pharm.* FROM
        apcd_&TWOYR. AS apcd FULL JOIN pharm2_&twoyr. AS pharm on apcd.ID=
        pharm.ID ) AS apcd_pharm ;
QUIT;

/* Mark OUD */
DATA apcd_pharm_&TWOYR. (KEEP=ID oud_apcd_pharm);
    SET apcd_pharm_&TWOYR.;
    IF SUM(oud_apcd, oud_pharm) > 0 THEN oud_apcd_pharm=1;
    ELSE oud_apcd_pharm=0;
    IF oud_apcd_pharm=0 THEN DELETE;
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE apcd_pharm_&TWOYR. AS SELECT DISTINCT ID, oud_apcd_pharm FROM
        apcd_pharm_&TWOYR. ;
QUIT;

/* Print the total observed counts - APCD_PHARM all merged */
TITLE "APCD_PHARM Crude - oud_apcd_pharm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_apcd_pharm, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        apcd_pharm_&TWOYR. GROUP BY oud_apcd_pharm ;
QUIT;
TITLE;

/* Print the observed counts from APCD_PHARM by Race and Sex */
PROC SQL;
    CREATE TABLE apcd_pharm_sex_race_&TWOYR. AS SELECT DISTINCT
        apcd_pharm_&TWOYR..ID, apcd_pharm_&TWOYR..oud_apcd_pharm,
        demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE FROM apcd_pharm_&TWOYR.
        LEFT JOIN demo_race_sex ON apcd_pharm_&TWOYR..ID=demo_race_sex.ID ;
QUIT;

TITLE "APCD_PHARM(by sex, race) - oud_apcd_pharm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_apcd_pharm, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID)
        > 0 AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp
        FROM apcd_pharm_sex_race_&TWOYR. GROUP BY oud_apcd_pharm, FINAL_SEX,
        FINAL_RE ;
QUIT;
TITLE;

/* CASEMIX */
/* Notes:
The algorithm to identify cases from CASE MIX is that:
(1) Identify cases from ED, ED_DIAG, ED_PROC, HD, HD_DIAG, HD_PROC and OO in separate
(2) Combine (link) them by ID
(3) Create a single data summarizing the identified cases from these subfiles
 */

/* ED */
DATA cm_ed_&TWOYR. (KEEP=ID oud_cm_ed);
    SET PHDCM.ED (KEEP=ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_AGE ED_RACE ED_SEX
        ED_ADMIT_YEAR WHERE=(ED_ADMIT_YEAR=&fouryr.));
    IF ED_DIAG1 in ("30400", "30401", "30402", "30470", "30471", "30472",
        "30550", "30551", "30552", "F1110", "F11120", "F11121", "F11122",
        "F11129", "F1113", "F1114", "F11150", "F11151", "F11159", "F11181",
        "F11182", "F11188", "F1119", "F1120", "F11220", "F11221", "F11222",
        "F11229", "F1123", "F1124", "F11250", "F11251", "F11259", "F11281",
        "F11282", "F11288", "F1129") THEN oud_cm_ed=1;
    ELSE oud_cm_ed=0;
    IF oud_cm_ed=0 THEN DELETE;
RUN;

/*searching for ODs separately and only counting if there are 2 or more per ID*/
PROC SQL;
    CREATE TABLE cm_ed_diag_&TWOYR._0OD AS SELECT DISTINCT ed.ID,
        ed.ed_admit_date FROM PHDCM.ED_DIAG AS ed_diag LEFT JOIN PHDCM.ED AS ed
        on ed_diag.ED_ID=ed.ED_ID WHERE (ed.ED_ADMIT_YEAR=&fouryr. AND
        (ed_diag.ED_DIAG in ("E8500", "E8501", "E8502", "96500", "96501",
        "96502", "96509", "9701", "T400X1A", "T400X2A", "T400X3A", "T400X4A",
        "T400X1D", "T400X2D", "T400X3D", "T400X4D", "T401X1A", "T401X2A",
        "T401X3A", "T401X4A", "T401X1D", "T401X2D", "T401X3D", "T401X4D",
        "T402X1A", "T402X2A", "T402X3A", "T402X4A", "T402X1D", "T402X2D",
        "T402X3D", "T402X4D", "T403X1A", "T403X2A", "T403X3A", "T403X4A",
        "T403X1D", "T403X2D", "T403X3D", "T403X4D", "T404X1A", "T404X2A",
        "T404X3A", "T404X4A", "T404X1D", "T404X2D", "T404X3D", "T404X4D",
        "T40601A", "T40601D", "T40602A", "T40602D", "T40603A", "T40603D",
        "T40604A", "T40604D", "T40691A", "T40692A", "T40693A", "T40694A",
        "T40691D", "T40692D", "T40693D", "T40694D") OR ed.ED_DIAG1 in ("E8500",
        "E8501", "E8502", "96500", "96501", "96502", "96509", "9701", "T400X1A",
        "T400X2A", "T400X3A", "T400X4A", "T400X1D", "T400X2D", "T400X3D",
        "T400X4D", "T401X1A", "T401X2A", "T401X3A", "T401X4A", "T401X1D",
        "T401X2D", "T401X3D", "T401X4D", "T402X1A", "T402X2A", "T402X3A",
        "T402X4A", "T402X1D", "T402X2D", "T402X3D", "T402X4D", "T403X1A",
        "T403X2A", "T403X3A", "T403X4A", "T403X1D", "T403X2D", "T403X3D",
        "T403X4D", "T404X1A", "T404X2A", "T404X3A", "T404X4A", "T404X1D",
        "T404X2D", "T404X3D", "T404X4D", "T40601A", "T40601D", "T40602A",
        "T40602D", "T40603A", "T40603D", "T40604A", "T40604D", "T40691A",
        "T40692A", "T40693A", "T40694A", "T40691D", "T40692D", "T40693D",
        "T40694D")));
QUIT;

/*GRACE: DEDUPLICATE TO REMOVE EXTRA ROWS*/
Proc sql;
    Create table cm_ed_diag_&TWOYR._1OD as Select distinct ID, ED_ADMIT_DATE
        from cm_ed_diag_&TWOYR._0OD order by id, ED_ADMIT_DATE;
quit;

proc sql;
    create table cm_ed_diag_&TWOYR._0OD2 as select distinct id, ed_admit_date,
        count(*) as totalods from cm_ed_diag_&TWOYR._1OD group by id having
        calculated totalods>1;
quit;

/* GRACE: Create oud_cm_ed for overdoses for dates that are at least 2 days apart */
data cm_ed_diag_&TWOYR._0OD3 (keep=id oud_cm_ed);
    set cm_ed_diag_&TWOYR._0OD2;
    by id ed_admit_date;
    retain startdt;
    oud_cm_ed=1;
    if first.id=last.id then delete;
    if first.id then startdt=ed_admit_date;
    else if last.id then diff=ed_admit_date-startdt;
    if diff>1 then output;
run;

data cm_ed_&TWOYR.;
    set cm_ed_diag_&TWOYR._0OD3 cm_ed_&TWOYR.;
run;

/* Remove the duplication of ID */
PROC SQL;
    CREATE TABLE cm_ed_&TWOYR. AS SELECT DISTINCT ID, oud_cm_ed FROM
        cm_ed_&TWOYR. ;
QUIT;

/* Print the total observed counts - ED */
TITLE "ED Crude - oud_cm_ed(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_ed, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM cm_ed_&TWOYR. GROUP BY
        oud_cm_ed ;
QUIT;
TITLE;

/* ED_DIAG */
PROC SQL;
    CREATE TABLE cm_ed_diag_&TWOYR._0 AS SELECT DISTINCT ed_diag.ED_ID, ed.ID, 1
        AS oud_cm_ed_diag FROM PHDCM.ED_DIAG AS ed_diag LEFT JOIN PHDCM.ED AS ed
        on ed_diag.ED_ID=ed.ED_ID WHERE ed.ED_ADMIT_YEAR=&fouryr. AND
        ed_diag.ED_DIAG in ("30400", "30401", "30402", "30470", "30471",
        "30472", "30550", "30551", "30552", "F1110", "F11120", "F11121",
        "F11122", "F11129", "F1113", "F1114", "F11150", "F11151", "F11159",
        "F11181", "F11182", "F11188", "F1119", "F1120", "F11220", "F11221",
        "F11222", "F11229", "F1123", "F1124", "F11250", "F11251", "F11259",
        "F11281", "F11282", "F11288", "F1129" ) ;
QUIT;

/* Remove the duplicated ID */
PROC SQL;
    CREATE TABLE cm_ed_diag_&TWOYR. AS SELECT DISTINCT ID, oud_cm_ed_diag FROM
        cm_ed_diag_&TWOYR._0 WHERE oud_cm_ed_diag=1 ;
QUIT;

/* Print the total observed counts - ED_DIAG */
TITLE "ED DIAG Crude - oud_cm_ed_diag(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_ed_diag, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_ed_diag_&TWOYR. GROUP BY oud_cm_ed_diag ;
QUIT;
TITLE;

/* ED_PROC */
PROC SQL;
    CREATE TABLE cm_ed_proc_&TWOYR._0 AS SELECT DISTINCT ed_proc.ED_ID, ed.ID, 1
        AS oud_cm_ed_proc FROM PHDCM.ED_PROC AS ed_proc LEFT JOIN PHDCM.ED AS ed
        on ed_proc.ED_ID=ed.ED_ID WHERE ed.ED_ADMIT_YEAR=&fouryr. AND
        ed_proc.ED_PROC in ("G2215", "G2216", "G1028", "J0592", "G2068",
        "G2069", "G2070", "G2071", "G2072", "G2079", "J0570", "J0571", "J0572",
        "J0573", "J0574", "J0575", "Q9991", "Q9992", "H0020", "G2067", "G2078",
        "S0109", "HZ91ZZZ", "HZ81ZZZ" ) ;
QUIT;

/* Remove the duplicated ID */
PROC SQL;
    CREATE TABLE cm_ed_proc_&TWOYR. AS SELECT DISTINCT ID, oud_cm_ed_proc FROM
        cm_ed_proc_&TWOYR._0 WHERE oud_cm_ed_proc=1 ;
QUIT;

/* Print the total observed counts - ED_PROC */
TITLE "ED PROC Crude - oud_cm_ed_proc(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_ed_proc, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_ed_proc_&TWOYR. GROUP BY oud_cm_ed_proc ;
QUIT;
TITLE;

/* Merge ED, ED_DIAG and ED_PROC, with demographic from raw ED*/
PROC SQL;
    CREATE TABLE cm_merge_ed_&TWOYR. AS SELECT DISTINCT merge_ed.*,
        raw_ed.ED_AGE, raw_ed.ED_RACE, raw_ed.ED_SEX FROM (SELECT
        coalesce(cm_ed.rawID, cm_ed_diag_proc.ed_diag_proc_ID) AS ID, oud_cm_ed,
        oud_cm_ed_diag, oud_cm_ed_proc FROM cm_ed_&TWOYR. (RENAME=(ID=rawID)) AS
        cm_ed FULL JOIN (/* Merge ED DIAG AND ED PROC */ SELECT
        coalesce(cm_ed_diag.rawID, cm_ed_proc.rawID) AS ed_diag_proc_ID,
        oud_cm_ed_diag, oud_cm_ed_proc FROM cm_ed_diag_&TWOYR.
        (RENAME=(ID=rawID)) AS cm_ed_diag full join cm_ed_proc_&TWOYR.
        (RENAME=(ID=rawID)) AS cm_ed_proc on cm_ed_diag_&TWOYR..rawID=
        cm_ed_proc_&TWOYR..rawID ) AS cm_ed_diag_proc on cm_ed.rawID=
        cm_ed_diag_proc.ed_diag_proc_ID ) AS merge_ed left join PHDCM.ED AS
        raw_ed on merge_ed.ID=raw_ed.ID ;
QUIT;

/* Mark OUD */
DATA cm_merge_ed_&TWOYR. (KEEP=ID oud_cm_merge_ed);
    SET cm_merge_ed_&TWOYR.;
    IF SUM(oud_cm_ed, oud_cm_ed_diag, oud_cm_ed_proc) > 0 THEN oud_cm_merge_ed=
        1;
    ELSE oud_cm_merge_ed=0;
    IF oud_cm_merge_ed=0 THEN DELETE;

    /* Demography */
    /* Age */
    agenum_ed=ED_AGE;
    IF agenum_ed < 18 OR agenum_ed > 64 THEN DELETE;
    /* Remove age<18 OR age>64*/
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE cm_merge_ed_&TWOYR. AS SELECT DISTINCT ID, oud_cm_merge_ed FROM
        cm_merge_ed_&TWOYR. ;
QUIT;

/* Print the total observed counts - ED merged */
TITLE "CM_ED Crude - oud_cm_merge_ed(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_merge_ed, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_merge_ed_&TWOYR. GROUP BY oud_cm_merge_ed ;
QUIT;
TITLE;

/* HD */
DATA cm_hd_&TWOYR. (KEEP=ID oud_cm_hd);
    SET PHDCM.HD (KEEP=ID HD_DIAG1 HD_PROC1 HD_ECODE HD_ADMIT_YEAR WHERE=
        (HD_ADMIT_YEAR=&fouryr.));
    IF HD_DIAG1 in ("30400", "30401", "30402", "30470", "30471", "30472",
        "30550", "30551", "30552", "F1110", "F11120", "F11121", "F11122",
        "F11129", "F1113", "F1114", "F11150", "F11151", "F11159", "F11181",
        "F11182", "F11188", "F1119", "F1120", "F11220", "F11221", "F11222",
        "F11229", "F1123", "F1124", "F11250", "F11251", "F11259", "F11281",
        "F11282", "F11288", "F1129") or HD_PROC1 in ("G2215", "G2216", "G1028",
        "J0592", "G2068", "G2069", "G2070", "G2071", "G2072", "G2079", "J0570",
        "J0571", "J0572", "J0573", "J0574", "J0575", "Q9991", "Q9992", "H0020",
        "G2067", "G2078", "S0109", "HZ91ZZZ", "HZ81ZZZ") or HD_ECODE in
        ("30400", "30401", "30402", "30470", "30471", "30472", "30550", "30551",
        "30552", "F1110", "F11120", "F11121", "F11122", "F11129", "F1113",
        "F1114", "F11150", "F11151", "F11159", "F11181", "F11182", "F11188",
        "F1119", "F1120", "F11220", "F11221", "F11222", "F11229", "F1123",
        "F1124", "F11250", "F11251", "F11259", "F11281", "F11282", "F11288",
        "F1129") THEN oud_cm_hd=1;
    ELSE oud_cm_hd=0;
    IF oud_cm_hd=0 THEN DELETE;
RUN;

/*Searching for ODs separately and only counting if there are 2 or more per ID*/
PROC SQL;
    CREATE TABLE cm_hd_hd_diag_&TWOYR._0OD AS SELECT DISTINCT hd.ID,
        hd.hd_admit_date FROM PHDCM.HD_DIAG AS hd_diag LEFT JOIN PHDCM.HD AS hd
        on hd_diag.HD_ID=hd.HD_ID WHERE (hd.HD_ADMIT_YEAR=&fouryr. AND
        (hd_diag.HD_DIAG in ("E8500", "E8501", "E8502", "96500", "96501",
        "96502", "96509", "9701", "T400X1A", "T400X2A", "T400X3A", "T400X4A",
        "T400X1D", "T400X2D", "T400X3D", "T400X4D", "T401X1A", "T401X2A",
        "T401X3A", "T401X4A", "T401X1D", "T401X2D", "T401X3D", "T401X4D",
        "T402X1A", "T402X2A", "T402X3A", "T402X4A", "T402X1D", "T402X2D",
        "T402X3D", "T402X4D", "T403X1A", "T403X2A", "T403X3A", "T403X4A",
        "T403X1D", "T403X2D", "T403X3D", "T403X4D", "T404X1A", "T404X2A",
        "T404X3A", "T404X4A", "T404X1D", "T404X2D", "T404X3D", "T404X4D",
        "T40601A", "T40601D", "T40602A", "T40602D", "T40603A", "T40603D",
        "T40604A", "T40604D", "T40691A", "T40692A", "T40693A", "T40694A",
        "T40691D", "T40692D", "T40693D", "T40694D") OR hd.HD_DIAG1 in ("E8500",
        "E8501", "E8502", "96500", "96501", "96502", "96509", "9701", "T400X1A",
        "T400X2A", "T400X3A", "T400X4A", "T400X1D", "T400X2D", "T400X3D",
        "T400X4D", "T401X1A", "T401X2A", "T401X3A", "T401X4A", "T401X1D",
        "T401X2D", "T401X3D", "T401X4D", "T402X1A", "T402X2A", "T402X3A",
        "T402X4A", "T402X1D", "T402X2D", "T402X3D", "T402X4D", "T403X1A",
        "T403X2A", "T403X3A", "T403X4A", "T403X1D", "T403X2D", "T403X3D",
        "T403X4D", "T404X1A", "T404X2A", "T404X3A", "T404X4A", "T404X1D",
        "T404X2D", "T404X3D", "T404X4D", "T40601A", "T40601D", "T40602A",
        "T40602D", "T40603A", "T40603D", "T40604A", "T40604D", "T40691A",
        "T40692A", "T40693A", "T40694A", "T40691D", "T40692D", "T40693D",
        "T40694D")));
QUIT;

/*DEDUPLICATE TO REMOVE EXTRA ROWS*/
Proc sql;
    Create table cm_hd_hd_diag_&TWOYR._1OD as Select distinct ID, HD_ADMIT_DATE
        from cm_hd_hd_diag_&TWOYR._0OD order by id, HD_ADMIT_DATE;
quit;

proc sql;
    create table cm_hd_hd_diag_&TWOYR._2OD as select distinct id, hd_admit_date,
        count(*) as totalods from cm_hd_hd_diag_&TWOYR._1OD group by id having
        calculated totalods>1;
quit;

/*Create oud_cm_ed for overdoses for dates that are at least 2 days apart*/

/* Then combine with OUD codes  */
data cm_hd_hd_diag_&TWOYR._3OD (keep=id oud_cm_hd);
    set cm_hd_hd_diag_&TWOYR._2OD;
    by id hd_admit_date;
    retain startdt;
    oud_cm_hd=1;
    if first.id=last.id then delete;
    if first.id then startdt=hd_admit_date;
    else if last.id then diff=hd_admit_date-startdt;
    if diff>1 then output;
run;

data cm_hd_&TWOYR.;
    set cm_hd_hd_diag_&TWOYR._3OD cm_hd_&TWOYR.;
run;

/* Remove the duplication of ID */
PROC SQL;
    CREATE TABLE cm_hd_&TWOYR. AS SELECT DISTINCT ID, oud_cm_hd FROM
        cm_hd_&TWOYR. ;
QUIT;
/* Print the total observed counts - HD */
TITLE "HD Crude - oud_cm_hd(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_hd, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM cm_hd_&TWOYR. GROUP BY
        oud_cm_hd ;
QUIT;
TITLE;

/* HD DIAG */
PROC SQL;
    CREATE TABLE cm_hd_diag_&TWOYR._0 AS SELECT DISTINCT hd_diag.HD_ID, hd.ID, 1
        AS oud_cm_hd_diag FROM PHDCM.HD_DIAG AS hd_diag left join PHDCM.HD AS hd
        on hd_diag.HD_ID=hd.HD_ID WHERE hd.HD_ADMIT_YEAR=&fouryr. AND
        hd_diag.HD_DIAG in ("30400", "30401", "30402", "30470", "30471",
        "30472", "30550", "30551", "30552", "F1110", "F11120", "F11121",
        "F11122", "F11129", "F1113", "F1114", "F11150", "F11151", "F11159",
        "F11181", "F11182", "F11188", "F1119", "F1120", "F11220", "F11221",
        "F11222", "F11229", "F1123", "F1124", "F11250", "F11251", "F11259",
        "F11281", "F11282", "F11288", "F1129") ;
QUIT;

/* Remove the duplicated ID */
PROC SQL;
    CREATE TABLE cm_hd_diag_&TWOYR. AS SELECT DISTINCT ID, oud_cm_hd_diag FROM
        cm_hd_diag_&TWOYR._0 WHERE oud_cm_hd_diag=1 ;
QUIT;

/* Print the total observed counts - HD_DIAG */
TITLE "HD DIAG Crude - oud_cm_hd_diag(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_hd_diag, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_hd_diag_&TWOYR. GROUP BY oud_cm_hd_diag ;
QUIT;
TITLE;

/* HD_PROC */
PROC SQL;
    CREATE TABLE cm_hd_proc_&TWOYR._0 AS SELECT DISTINCT hd_proc.HD_ID, hd.ID, 1
        AS oud_cm_hd_proc FROM PHDCM.HD_PROC AS hd_proc LEFT JOIN PHDCM.HD AS hd
        on hd_proc.HD_ID=hd.HD_ID WHERE hd.HD_ADMIT_YEAR=&fouryr. AND
        hd_proc.HD_PROC in ("G2215", "G2216", "G1028", "J0592", "G2068",
        "G2069", "G2070", "G2071", "G2072", "G2079", "J0570", "J0571", "J0572",
        "J0573", "J0574", "J0575", "Q9991", "Q9992", "H0020", "G2067", "G2078",
        "S0109", "HZ91ZZZ", "HZ81ZZZ") ;
QUIT;

/* Remove the duplicated ID */
PROC SQL;
    CREATE TABLE cm_hd_proc_&TWOYR. AS SELECT DISTINCT ID, oud_cm_hd_proc FROM
        cm_hd_proc_&TWOYR._0 WHERE oud_cm_hd_proc=1 ;
QUIT;

/* Print the total observed counts - HD_PROC */
TITLE "HD PROC Crude - oud_cm_hd_proc(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_hd_proc, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_hd_proc_&TWOYR. GROUP BY oud_cm_hd_proc ;
QUIT;
TITLE;

/* Merge HD, HD_DIAG, and HD_PROC with demographic from raw HD */
PROC SQL;
    CREATE TABLE cm_merge_hd_&TWOYR. AS SELECT DISTINCT merge_hd.*,
        raw_hd.HD_AGE, raw_hd.HD_RACE, raw_hd.HD_SEX FROM ( SELECT
        COALESCE(cm_hd.rawID, cm_hd_diag.hd_diag_ID, cm_hd_proc.hd_proc_ID) AS
        ID, oud_cm_hd, oud_cm_hd_diag, oud_cm_hd_proc FROM cm_hd_&TWOYR.
        (RENAME=(ID=rawID)) AS cm_hd FULL JOIN cm_hd_diag_&TWOYR.
        (RENAME=(ID=hd_diag_ID)) AS cm_hd_diag ON cm_hd.rawID=
        cm_hd_diag.hd_diag_ID FULL JOIN cm_hd_proc_&TWOYR.
        (RENAME=(ID=hd_proc_ID)) AS cm_hd_proc ON COALESCE(cm_hd.rawID,
        cm_hd_diag.hd_diag_ID)=cm_hd_proc.hd_proc_ID ) AS merge_hd LEFT JOIN
        PHDCM.HD AS raw_hd ON merge_hd.ID=raw_hd.ID ;
QUIT;

/* Mark OUD */
DATA cm_merge_hd_&TWOYR. (KEEP=ID oud_cm_merge_hd);
    SET cm_merge_hd_&TWOYR.;
    IF SUM(oud_cm_hd, oud_cm_hd_diag, oud_cm_hd_proc) > 0 THEN oud_cm_merge_hd=
        1;
    ELSE oud_cm_merge_hd=0;
    IF oud_cm_merge_hd=0 THEN DELETE;

    /* Demography */
    /* Age */
    agenum_hd=HD_AGE;
    IF agenum_hd < 18 OR agenum_hd > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE cm_merge_hd_&TWOYR. AS SELECT DISTINCT ID, oud_cm_merge_hd FROM
        cm_merge_hd_&TWOYR. ;
QUIT;

/* Print the total observed counts - HD merged */
TITLE "CM_HD Crude - oud_cm_merge_hd(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_merge_hd, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_merge_hd_&TWOYR. GROUP BY oud_cm_merge_hd ;
QUIT;
TITLE;

/* OO */
DATA cm_oo_&TWOYR. (KEEP=ID oud_cm_oo) OO_0OD_&TWOYR. (keep=ID OO_ADMIT_DATE);
    SET PHDCM.OO (KEEP=ID OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4 OO_ADMIT_YEAR
        OO_AGE OO_RACE OO_SEX OO_CPT1-OO_CPT10 OO_ADMIT_DATE WHERE=
        (OO_ADMIT_YEAR=&fouryr.));
    ct_cm_oo=0;
    ct_cm_oo2=0;
    ct_cm_oo3=0;

    oud_cm_oo=0;

    /* Demography */
    /* Age */
    agenum_oo=OO_AGE;
    IF agenum_oo < 18 OR agenum_oo > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
    ARRAY vars3 {*}
        OO_DIAG1-OO_DIAG16;/*GRACE: UPDATED TO INCLUDE 7 - 17 WHICH APPEAR IN LATER YEARS*/
    ARRAY vars4 {*} OO_CPT1-OO_CPT10;
    ARRAY vars5 {*} OO_PROC1-OO_PROC4;

    DO k=1 TO DIM(vars3);
        IF vars3[k] IN ( "30400", "30401", "30402", "30470", "30471", "30472",
            "30550", "30551", "30552", "F1110", "F11120", "F11121", "F11122",
            "F11129", "F1113", "F1114", "F11150", "F11151", "F11159", "F11181",
            "F11182", "F11188", "F1119", "F1120", "F11220", "F11221", "F11222",
            "F11229", "F1123", "F1124", "F11250", "F11251", "F11259", "F11281",
            "F11282", "F11288", "F1129") THEN ct_cm_oo + 1;
        IF vars3[k] IN ("E8500", "E8501", "E8502", "96500", "96501", "96502",
            "96509", "9701", "T400X1A", "T400X2A", "T400X3A", "T400X4A",
            "T400X1D", "T400X2D", "T400X3D", "T400X4D", "T401X1A", "T401X2A",
            "T401X3A", "T401X4A", "T401X1D", "T401X2D", "T401X3D", "T401X4D",
            "T402X1A", "T402X2A", "T402X3A", "T402X4A", "T402X1D", "T402X2D",
            "T402X3D", "T402X4D", "T403X1A", "T403X2A", "T403X3A", "T403X4A",
            "T403X1D", "T403X2D", "T403X3D", "T403X4D", "T404X1A", "T404X2A",
            "T404X3A", "T404X4A", "T404X1D", "T404X2D", "T404X3D", "T404X4D",
            "T40601A", "T40601D", "T40602A", "T40602D", "T40603A", "T40603D",
            "T40604A", "T40604D", "T40691A", "T40692A", "T40693A", "T40694A",
            "T40691D", "T40692D", "T40693D", "T40694D") THEN output
            OO_0OD_&TWOYR.;
    END;

    DO j=1 TO DIM(vars4);
        IF vars4[j] IN ("G2215", "G2216", "G1028", "J0592", "G2068", "G2069",
            "G2070", "G2071", "G2072", "G2079", "J0570", "J0571", "J0572",
            "J0573", "J0574", "J0575", "Q9991", "Q9992", "H0020", "G2067",
            "G2078", "S0109") THEN ct_cm_oo2 + 1;
    END;

    DO i=1 to DIM(vars5);
        IF vars5[i] IN ("HZ91ZZZ", "HZ81ZZZ") THEN ct_cm_oo3 + 1;
    END;

    IF ct_cm_oo > 0 OR ct_cm_oo2 > 0 OR ct_cm_oo3 > 0 THEN DO;
        oud_cm_oo=1;
        OUTPUT CM_OO_&TWOYR.;
    END;

RUN;

/*DEDUPLICATE TO REMOVE EXTRA ROWS*/
Proc sql;
    Create table OO_1OD_&TWOYR. as Select distinct ID, OO_ADMIT_DATE from
        OO_0OD_&TWOYR. order by id, OO_ADMIT_DATE;
quit;

proc sql;
    create table OO_2OD_&TWOYR. as select distinct id, oo_admit_date, count(*)
        as totalods from OO_1OD_&TWOYR. group by id having calculated
        totalods>1;
quit;

/*Create oud_cm_ed for overdoses for dates that are at least 2 days apart*/

/* Then combine with OUD codes  */
data OO_3OD_&TWOYR. (keep=id oud_cm_oo);
    set OO_2OD_&TWOYR.;
    by id oo_admit_date;
    retain startdt;
    oud_cm_oo=1;
    if first.id=last.id then delete;
    if first.id then startdt=oo_admit_date;
    else if last.id then diff=oo_admit_date-startdt;
    if diff>1 then output;
run;

data cm_oo_&TWOYR.;
    set OO_3OD_&TWOYR. cm_oo_&TWOYR.;
run;

/* Remove the duplication of ID*/
PROC SQL;
    CREATE TABLE cm_oo_&TWOYR. AS SELECT DISTINCT ID, oud_cm_oo FROM
        cm_oo_&TWOYR. ;
QUIT;
/* Print the total observed counts - OO */
TITLE "OO Crude - oud_cm_oo(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm_oo, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM cm_oo_&TWOYR. GROUP BY
        oud_cm_oo ;
QUIT;
TITLE;

/* Merge all CM subfiles */
PROC SQL;
    CREATE TABLE cm_merge_&TWOYR. AS SELECT DISTINCT coalesce(ed_hd.ed_hd_ID,
        cm_oo.rawID) AS ID, ed_hd.oud_cm_merge_ed, ed_hd.oud_cm_merge_hd,
        cm_oo.oud_cm_oo FROM (SELECT coalesce(ed.ID, hd.ID) AS ed_hd_ID, ed.*,
        hd.* FROM cm_merge_ed_&TWOYR. AS ed FULL JOIN cm_merge_hd_&TWOYR. AS hd
        on ed.ID=hd.ID ) AS ed_hd FULL JOIN cm_oo_&TWOYR. (RENAME=(ID=rawID)) AS
        cm_oo on ed_hd.ed_hd_ID=cm_oo.rawID ;
QUIT;

/* Mark OUD */
DATA cm_merge_&TWOYR. (KEEP=ID oud_cm);
    SET cm_merge_&TWOYR.;
    IF SUM(oud_cm_merge_ed, oud_cm_merge_hd, oud_cm_oo) > 0 THEN oud_cm=1;
    ELSE oud_cm=0;
    IF oud_cm=0 THEN DELETE;
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE cm_merge_&TWOYR. AS SELECT DISTINCT ID, oud_cm FROM
        cm_merge_&TWOYR. ;
QUIT;

/* Print the total observed counts - CM all merged */
TITLE "CM Crude - oud_cm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <=
        10, -1, COUNT(distinct ID)) AS N_ID_supp FROM cm_merge_&TWOYR. GROUP BY
        oud_cm ;
QUIT;
TITLE;

/* Print the observed counts from merged CM by Race and Sex */
PROC SQL;
    CREATE TABLE cm_sex_race_&TWOYR. AS SELECT DISTINCT cm_merge_&TWOYR..ID,
        cm_merge_&TWOYR..oud_cm, demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE
        FROM cm_merge_&TWOYR. LEFT JOIN demo_race_sex ON cm_merge_&TWOYR..ID=
        demo_race_sex.ID ;
QUIT;

TITLE "CM(by sex, race) - oud_cm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_cm, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        cm_sex_race_&TWOYR. GROUP BY oud_cm, FINAL_SEX, FINAL_RE ;
QUIT;

/* Merge merged CM and APCD (GRACE: INCLUDING PHARMACY) */
PROC SQL;
    CREATE TABLE apcd_cm_&TWOYR. AS
        /*GRACE: DO NOT CHANGE THIS DSN. APCD PHARMACY HAS BEEN ADDED IN THE FROM STMNT*/
        SELECT DISTINCT coalesce(apcd_pharm.rawID, cm_merge.rawID) AS ID,
        apcd_pharm.*, cm_merge.* FROM apcd_pharm_&TWOYR. (RENAME=(ID=rawID)) AS
        apcd_pharm full join cm_merge_&TWOYR. (RENAME=(ID=rawID)) AS cm_merge on
        apcd_pharm.rawID=cm_merge.rawID ;
QUIT;

/* Recode to label 0 */
DATA apcd_cm_&TWOYR.;
    SET apcd_cm_&TWOYR.;
    IF oud_apcd_pharm=. THEN oud_apcd_pharm=0;
    IF oud_cm=. THEN oud_cm=0;
RUN;

/* Before mark either APCD or CM as OUD, check the overlap between APCD and CM */

/* Label the missing cells with ZERO */
DATA merge_apcd_cm_&TWOYR.;
    SET apcd_cm_&TWOYR.;
    ARRAY missing {*} oud_apcd_pharm -- oud_cm;
    Do i=1 TO dim(missing);
        IF missing[i]=. THEN missing[i]=0;
    END;
    DROP i ;
RUN;

/* Remove the non-oud people (labeled with 0) */
DATA merge_apcd_cm_&TWOYR._1;
    SET merge_apcd_cm_&TWOYR.;
    IF SUM(of oud_apcd_pharm -- oud_cm)=0 THEN DELETE;
RUN;

/* Construct Contingency Table */
PROC SUMMARY DATA=merge_apcd_cm_&TWOYR._1 NWAY COMPLETETYPES;
    CLASS oud_apcd_pharm oud_cm /MISSING;
    OUTPUT OUT=Count_apcd_cm_&TWOYR.;
RUN;

DATA Count_apcd_cm_&TWOYR.;
    SET Count_apcd_cm_&TWOYR.;
    raw_n=_FREQ_;
    DROP _TYPE_ _FREQ_;
RUN;

/* remove the rows with all zeros */
DATA Count_apcd_cm_&TWOYR.;
    SET Count_apcd_cm_&TWOYR.;
    IF SUM(of oud_apcd_pharm -- oud_cm)=0 THEN DELETE;
    IF 0 < raw_n <= 10 THEN N_ID_supp=-1;
    ELSE N_ID_supp=raw_n;
    DROP raw_n;
RUN;

/* Print Contingency table of APCD/CM */
TITLE "Contingency Table between APCD vs CaseMix";

PROC SQL;
    SELECT DISTINCT oud_apcd_pharm, oud_cm, N_ID_supp FROM Count_apcd_cm_&TWOYR.
        GROUP BY oud_apcd_pharm, oud_cm ;
QUIT;
TITLE;

/* Calculate number of KNOWN */
TITLE "Number of KNOWN between APCD vs CaseMix";

PROC SQL;
    SELECT DISTINCT IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10, -1,
        COUNT(distinct ID)) AS N_KNOWN_supp FROM merge_apcd_cm_&TWOYR._1 WHERE
        SUM(oud_apcd_pharm, oud_cm)>0 ;
QUIT;
TITLE;

/* Continue to combine APCD and CM by marking OUD */

/* Mark OUD for APCD and CM combined */
DATA apcd_cm_&TWOYR. (KEEP=ID oud_apcd_cm);
    SET apcd_cm_&TWOYR.;
    IF SUM(oud_apcd_pharm, oud_cm) > 0 THEN oud_apcd_cm=1;
    ELSE oud_apcd_cm=0;
    IF oud_apcd_cm=0 THEN DELETE;
RUN;

/* Print APCD/CM by Sex and Race */
PROC SQL;
    CREATE TABLE apcd_cm_sex_race_&TWOYR. AS SELECT DISTINCT apcd_cm_&TWOYR..ID,
        apcd_cm_&TWOYR..oud_apcd_cm, demo_race_sex.FINAL_SEX,
        demo_race_sex.FINAL_RE FROM apcd_cm_&TWOYR. LEFT JOIN demo_race_sex ON
        apcd_cm_&TWOYR..ID=demo_race_sex.ID ;
QUIT;

TITLE "APCD/CM (by sex, race) - oud_apcd_cm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_apcd_cm, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        apcd_cm_sex_race_&TWOYR. GROUP BY oud_apcd_cm, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* BIRTH */
/* Notes:
Use the variable in INFANT dataset but link back to MOM dataset.
 */

/* BIRTH_INFANT */
DATA birth_&TWOYR._0 (KEEP=ID oud_birth_baby BIRTH_LINK_ID);
    SET PHDBIRTH.BIRTH_INFANT (KEEP=ID NAS_BC NAS_BC_NEW YEAR_BIRTH
        BIRTH_LINK_ID WHERE=(YEAR_BIRTH=&fouryr.));
    IF NAS_BC=1 OR NAS_BC_NEW=1 THEN oud_birth_baby=1;
    /*GRACE: ADDED NAS_BC_NEW*/
    ELSE oud_birth_baby=0;
    IF oud_birth_baby=0 THEN DELETE;
RUN;

/* BIRTH_MOM */
PROC SQL;
    CREATE TABLE birth_&TWOYR. AS SELECT DISTINCT ID, 1 AS oud_birth,
        MOTHER_RACE_BIRTH, AGE_BIRTH FROM PHDBIRTH.BIRTH_MOM WHERE BIRTH_LINK_ID
        in (SELECT BIRTH_LINK_ID FROM birth_&TWOYR._0) AND YEAR_BIRTH=&fouryr. ;
QUIT;

DATA birth_&TWOYR. (KEEP=ID oud_birth);
    SET birth_&TWOYR.;
    /* Demography */
    /* Age */
    agenum_birth=AGE_BIRTH;
    IF agenum_birth < 18 OR agenum_birth > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE birth_&TWOYR. AS SELECT DISTINCT ID, oud_birth FROM
        birth_&TWOYR. ;
QUIT;

/* Print the total observed counts - BIRTH */
TITLE "BIRTH Crude - oud_birth(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_birth, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM birth_&TWOYR. GROUP BY
        oud_birth ;
QUIT;
TITLE;

/* Print the observed counts from BIRTH by Race and Sex*/
PROC SQL;
    CREATE TABLE birth_sex_race_&TWOYR. AS SELECT DISTINCT birth_&TWOYR..ID,
        birth_&TWOYR..oud_birth, demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE
        FROM birth_&TWOYR. LEFT JOIN demo_race_sex ON birth_&TWOYR..ID=
        demo_race_sex.ID ;
QUIT;
TITLE "BIRTH (by sex, race) - oud_apcd_cm(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_birth, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        birth_sex_race_&TWOYR. GROUP BY oud_birth, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* Merge BIRTH and APCD/CM */
PROC SQL;
    CREATE TABLE apcd_cm_birth_&TWOYR. AS SELECT coalesce(apcdcm.rawID,
        birth.rawID) AS ID, apcdcm.oud_apcd_cm, birth.oud_birth FROM
        apcd_cm_&TWOYR. (RENAME=(ID=rawID)) AS apcdcm full join birth_&TWOYR.
        (RENAME=(ID=rawID)) AS birth on apcdcm.rawID=birth.rawID ;
QUIT;

/* Recode to label 0 */
DATA apcd_cm_birth_&TWOYR.;
    SET apcd_cm_birth_&TWOYR.;
    IF oud_apcd_cm=. THEN oud_apcd_cm=0;
    IF oud_birth=. THEN oud_birth=0;
RUN;

/* Before mark either APCD or CM as OUD, see overlap between APCD and CM */

/* Correct cells with missing to Zero */
DATA merge_apcd_cm_birth_&TWOYR.;
    SET apcd_cm_birth_&TWOYR.;
    ARRAY missing {*} oud_apcd_cm -- oud_birth;
    Do i=1 TO dim(missing);
        IF missing[i]=. THEN missing[i]=0;
    END;
    DROP i ;
RUN;

/* Remove the non-oud people */
DATA merge_apcd_cm_birth_&TWOYR._1;
    SET merge_apcd_cm_birth_&TWOYR.;
    IF SUM(of oud_apcd_cm -- oud_birth)=0 THEN DELETE;
RUN;

/* Making Contingency Table */
PROC SUMMARY DATA=merge_apcd_cm_birth_&TWOYR._1 NWAY COMPLETETYPES;
    CLASS oud_apcd_cm oud_birth /MISSING;
    OUTPUT OUT=Count_apcd_cm_birth_&TWOYR.;
RUN;

DATA Count_apcd_cm_birth_&TWOYR.;
    SET Count_apcd_cm_birth_&TWOYR.;
    raw_n=_FREQ_;
    DROP _TYPE_ _FREQ_;
RUN;

/* Remove the all zeros row */
DATA Count_apcd_cm_birth_&TWOYR.;
    SET Count_apcd_cm_birth_&TWOYR.;
    IF SUM(of oud_apcd_cm -- oud_birth)=0 THEN DELETE;
    IF 0 < raw_n <= 10 THEN N_ID_supp=-1;
    ELSE N_ID_supp=raw_n;
RUN;
/* Print Contingency table */
TITLE "Contingency Table between APCD/CM vs BIRTH";

PROC SQL;
    SELECT DISTINCT oud_apcd_cm, oud_birth, N_ID_supp FROM
        Count_apcd_cm_birth_&TWOYR. GROUP BY oud_apcd_cm, oud_birth ;
QUIT;
TITLE;

/* Calculate number of KNOWN */
TITLE "Number of KNOWN between APCD/CM vs BIRTH";

PROC SQL;
    SELECT DISTINCT IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10, -1,
        COUNT(distinct ID)) AS N_KNOWN_supp FROM merge_apcd_cm_birth_&TWOYR._1
        WHERE SUM(oud_apcd_cm, oud_birth)>0 ;
QUIT;
TITLE;

/* Continue to combine APCD/CM AND BIRTH by marking OUD */

/* Mark OUD for APCD/CM+BIRTH */
DATA apcd_cm_birth_&TWOYR. (KEEP=ID oud_apcd_cm_birth);
    SET apcd_cm_birth_&TWOYR.;
    oud_apcd_cm_birth=.;
    IF SUM(oud_apcd_cm, oud_birth) > 0 THEN oud_apcd_cm_birth=1;
    ELSE oud_apcd_cm_birth=0;
    IF oud_apcd_cm_birth=0 THEN DELETE;
RUN;

/* Remove duplicated ID */
PROC SQL;
    CREATE TABLE apcd_cm_birth_&TWOYR. AS SELECT DISTINCT ID, oud_apcd_cm_birth
        FROM apcd_cm_birth_&TWOYR. ;
QUIT;

/* Print the total observed counts - APCD/CM/BIRTH */
TITLE "APCD/CM/BIRTH Crude - oud_apcd_cm_birth(&fouryr.)";

PROC SQL;
    SELECT oud_apcd_cm_birth, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID)
        <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM apcd_cm_birth_&TWOYR.
        GROUP BY oud_apcd_cm_birth ;
QUIT;
TITLE;

/* Print the observed counts from APCD/CM/BIRTH by Race and Sex*/
PROC SQL;
    CREATE TABLE apcd_cm_birth_sex_race_&TWOYR. AS SELECT DISTINCT
        apcd_cm_birth_&TWOYR..ID, apcd_cm_birth_&TWOYR..oud_apcd_cm_birth,
        demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE FROM
        apcd_cm_birth_&TWOYR. LEFT JOIN demo_race_sex ON
        apcd_cm_birth_&TWOYR..ID=demo_race_sex.ID ;
QUIT;
TITLE "APCD/CM/BIRTH (by sex, race) - oud_apcd_cm_birth(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_apcd_cm_birth, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct
        ID) > 0 AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS
        N_ID_supp FROM apcd_cm_birth_sex_race_&TWOYR. GROUP BY
        oud_apcd_cm_birth, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* BSAS */
/* GRACE: REMOVE IDS THAT WERE IN JAIL/PRISON EVERYDAY */
%include
    "/sas/data/DPH/OPH/SAP/FOLDERS/GRACE/OUD Estimation/BSAS_HOCDOC/BSAS_HOCDOC_&fouryr..sas";

data bsas&fouryr.;
    set PHDBSAS.BSAS;
    where ENR_YEAR_BSAS=&fouryr.;
run;

proc sort data=bsas&fouryr.;
    by ID;
run;

/* Remove IDs in bsas_hocdoc_&year. from BSAS */
proc sql;
    create table bsas_no_hocdoc_&fouryr. as select a.* from bsas&fouryr. as a
        left join bsas_hocdoc_&year. as b on a.id=b.id where b.id is null;
run;

DATA bsas_&TWOYR. (KEEP=ID oud_bsas);
    SET bsas_no_hocdoc_&fouryr. (KEEP=ID /*CLT_ENR_OVERDOSES_LIFE*/
        CLT_ENR_PRIMARY_DRUG CLT_ENR_SECONDARY_DRUG CLT_ENR_TERTIARY_DRUG
        PDM_PRV_SERV_CAT /*PDM_PRV_SERV_TYPE*/ AGE_BSAS SEX_BSAS RACE_BSAS
        ENR_YEAR_BSAS METHADONE_BSAS RENAME=(SEX_BSAS=SEX_BSAS_RAW RACE_BSAS=
        RACE_BSAS_RAW) WHERE=(ENR_YEAR_BSAS=&fouryr.));
    /* IF (CLT_ENR_OVERDOSES_LIFE > 1 AND CLT_ENR_OVERDOSES_LIFE ^= 999) */
    /*    OR  GRACE SILENCED THIS*/
    IF CLT_ENR_PRIMARY_DRUG in (5,6,7,21,22,23,24,26) OR CLT_ENR_SECONDARY_DRUG
        in (5,6,7,21,22,23,24,26) OR CLT_ENR_TERTIARY_DRUG in
        (5,6,7,21,22,23,24,26) OR METHADONE_BSAS=1 THEN oud_bsas=1;
    ELSE oud_bsas=0;
    IF oud_bsas=0 THEN DELETE;
    /* Can delete because contingency table would refill 0 IF missing after merge */
    /* Demography */
    /* Age */
    agenum_bsas=AGE_BSAS;
    IF agenum_bsas < 18 OR agenum_bsas > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplicated rows */
PROC SQL;
    CREATE TABLE bsas_&TWOYR. AS SELECT DISTINCT ID, oud_bsas FROM bsas_&TWOYR.
        ;
QUIT;

/* Print the total observed count - BSAS */
PROC SQL;
    TITLE "BSAS Crude - oud_bsas(&fouryr.)";
    SELECT oud_bsas, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10,
        -1, COUNT(distinct ID)) AS N_ID_supp FROM bsas_&TWOYR. GROUP BY oud_bsas
        ;
    TITLE;
QUIT;

/* Print the observed counts from BSAS by Race and Sex */
PROC SQL;
    CREATE TABLE bsas_sex_race_&TWOYR. AS SELECT DISTINCT bsas_&TWOYR..ID,
        bsas_&TWOYR..oud_bsas, demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE
        FROM bsas_&TWOYR. LEFT JOIN demo_race_sex ON bsas_&TWOYR..ID=
        demo_race_sex.ID ;
QUIT;

TITLE "BSAS (by sex, race) - oud_bsas(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_bsas, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        bsas_sex_race_&TWOYR. GROUP BY oud_bsas, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* MATRIS */
DATA matris_&TWOYR. (KEEP=ID oud_matris sex_matris_raw INC_DATE_MATRIS);
    SET PHDEMS.MATRIS (KEEP=ID OPIOID_ORI_MATRIS OPIOID_ORISUBCAT_MATRIS
        inc_year_matris AGE_MATRIS RACE_MATRIS SEX_MATRIS INC_DATE_MATRIS
        /* for latest record */ RENAME=(RACE_MATRIS=RACE_MATRIS_RAW SEX_MATRIS=
        SEX_MATRIS_RAW) WHERE=(inc_year_matris=&fouryr.));

    If OPIOID_ORISUBCAT_MATRIS IN (1,2) THEN OUD_MATRIS=1;
    ELSE OUD_MATRIS=0;
    IF OUD_MATRIS=0 THEN DELETE;

    /* Demography */
    /* Age */
    agenum_matris=AGE_MATRIS;
    IF agenum_matris < 18 OR agenum_matris > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplication of ID */
PROC SQL;
    CREATE TABLE matris_&TWOYR. AS SELECT DISTINCT ID, oud_matris,
        INC_DATE_MATRIS, count(*) as totalods FROM matris_&TWOYR. group by ID
        having calculated totalods > 1 ;
QUIT;

/* GRACE: AT LEAST 2 DAYS APART */
data matris2_&TWOYR. (keep=id oud_matris);
    set matris_&TWOYR.;
    by id inc_date_matris;
    retain startdt;
    if first.id=last.id then delete;
    if first.id then startdt=inc_date_matris;
    else if last.id then diff=inc_date_matris-startdt;
    if diff>1 then output;
run;

data matris_&TWOYR.;
    set matris2_&TWOYR.;
run;

/* Print the total observed counts - MATRIS */
TITLE "MATRIS Crude - oud_matris(&fouryr.)";

PROC SQL;
    SELECT oud_matris, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10,
        -1, COUNT(distinct ID)) AS N_ID_supp FROM matris_&TWOYR. GROUP BY
        oud_matris ;
QUIT;
TITLE;

/* Print the observed counts from MATRIS by Race and Sex */
PROC SQL;
    CREATE TABLE matris_sex_race_&TWOYR. AS SELECT DISTINCT matris_&TWOYR..ID,
        matris_&TWOYR..oud_matris, demo_race_sex.FINAL_SEX,
        demo_race_sex.FINAL_RE FROM matris_&TWOYR. LEFT JOIN demo_race_sex ON
        matris_&TWOYR..ID=demo_race_sex.ID ;
QUIT;

TITLE "MATRIS (by sex, race) - oud_matris(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_matris, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        matris_sex_race_&TWOYR. GROUP BY oud_matris, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* DEATH */

/* Notes:
INCLUDE Suicide (MANNER = 4) -> All values in MANNER are included -> Remove MANNER variable
 */
DATA death_&TWOYR. (KEEP=ID oud_death);
    SET PHDDEATH.DEATH (KEEP=ID OPIOID_DEATH YEAR_DEATH /* MANNER */ AGE_DEATH
        RACE_DEATH SEX_DEATH RENAME=(RACE_DEATH=RACE_DEATH_RAW SEX_DEATH=
        SEX_DEATH_RAW) WHERE=(YEAR_DEATH=&fouryr.));
    IF OPIOID_DEATH=1 THEN oud_death=1; /* AND MANNER in (1,2,3,4,5,6,7,8)*/
    ELSE oud_death=0;
    IF oud_death=0 THEN DELETE;

    /* Demography */
    /* Age */
    agenum_death=AGE_DEATH;
    IF agenum_death < 18 OR agenum_death > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplication of ID*/
PROC SQL;
    CREATE TABLE death_&TWOYR. AS SELECT DISTINCT ID, oud_death FROM
        death_&TWOYR. ;
QUIT;

/* Print the total observed counts - DEATH */
TITLE "DEATH Crude - oud_death(&fouryr.)";

PROC SQL;
    SELECT oud_death, IFN(COUNT(distinct ID)>0 AND COUNT(distinct ID) <= 10, -1,
        COUNT(distinct ID)) AS N_ID_supp FROM death_&TWOYR. GROUP BY oud_death ;
QUIT;
TITLE;

/* Print the observed counts from DEATH by Race and Sex*/
PROC SQL;
    CREATE TABLE death_sex_race_&TWOYR. AS SELECT DISTINCT death_&TWOYR..ID,
        death_&TWOYR..oud_death, demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE
        FROM death_&TWOYR. LEFT JOIN demo_race_sex ON death_&TWOYR..ID=
        demo_race_sex.ID ;
QUIT;
TITLE "DEATH (by sex, race) - oud_death(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_death, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        death_sex_race_&TWOYR. GROUP BY oud_death, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* PMP */
DATA pmp_&TWOYR. (KEEP=ID oud_pmp);
    SET PHDPMP.PMP (KEEP=ID BUPRENORPHINE_PMP date_filled_year
        /* SUBOPIOID_PMP */ AGE_PMP SEX_PMP BUP_CAT_PMP RENAME=(SEX_PMP=
        SEX_PMP_RAW) WHERE=(date_filled_year=&fouryr.));

    IF BUP_CAT_PMP=1 THEN OUD_PMP=1;
    ELSE OUD_PMP=0;
    IF OUD_PMP=0 THEN DELETE;
    /* Demography */
    /* Age */
    agenum_pmp=AGE_PMP;
    IF agenum_pmp < 18 OR agenum_pmp > 64 THEN DELETE;
    /* Remove age<18 OR age>64 */
RUN;

/* Remove the duplication of ID*/
PROC SQL;
    CREATE TABLE pmp_&TWOYR. AS SELECT DISTINCT ID, oud_pmp FROM pmp_&TWOYR. ;
QUIT;

/* Print the total observed counts - PMP */
TITLE "PMP Crude - oud_pmp(&fouryr.)";

PROC SQL;
    SELECT oud_pmp, IFN(COUNT(distinct ID)>0 AND COUNT(distinct ID) <= 10, -1,
        COUNT(distinct ID)) AS N_ID_supp FROM pmp_&TWOYR. GROUP BY oud_pmp ;
QUIT;
TITLE;

/* Print the observed counts from PMP by Race and Sex*/
PROC SQL;
    CREATE TABLE pmp_sex_race_&TWOYR. AS SELECT DISTINCT pmp_&TWOYR..ID,
        pmp_&TWOYR..oud_pmp, demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE
        FROM pmp_&TWOYR. LEFT JOIN demo_race_sex ON pmp_&TWOYR..ID=
        demo_race_sex.ID ;
QUIT;
TITLE "PMP (by sex, race) - oud_pmp(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_pmp, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0 AND
        COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        pmp_sex_race_&TWOYR. GROUP BY oud_pmp, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/* JAILS */
/* Purpose: To add people who received MOUD in jail to the OUD definition excluding IDs that were incarcerated every single day of the year */
/* Author: GEN */
%include
    "/sas/data/DPH/OPH/SAP/FOLDERS/GRACE/OUD Estimation/HOCMOUD/HOCMOUD_&FOURYR..sas";
%include
    "/sas/data/DPH/OPH/SAP/FOLDERS/GRACE/OUD Estimation/DOC analyses/DOC_&FOURYR..sas";

/* BRING IN THE HOCMOUD FILE - people who were enrolled in the MOUD program */
data hocmoud_&FOURYR.;
    set PHDBSAS.HOCMOUD;
    if jailentryyear<&FOURYR. & enroll_year <=&FOURYR.;
run;

/* Dedup */
proc sort data=hocmoud_&FOURYR. nodupkey;
    by ID /*admit_date_hoc release_date_hoc*/;
run;

/* REMOVE THOSE WHO WERE IN JAIL/PRISON EVERYDAY */
proc contents data=injail&FOURYR.;
run;

data injail&FOURYR._2 (keep=ID match_flag);
    set injail&FOURYR.;
run;

data inprison&FOURYR._2 (keep=ID match_flag);
    set inprison&FOURYR.;
run;

proc sort data=injail&FOURYR._2 nodupkey;
    by ID;
run;

proc sql;
    create table hocmoud_nohocdoc_&TWOYR. as select distinct a.* from
        hocmoud_&FOURYR. as a left join injail&FOURYR._2 as b on a.id=b.id left
        join inprison&FOURYR._2 as c on a.id=c.id where b.id is null and c.id is
        null;
quit;

data hocmoud_nohocdoc_&TWOYR. (keep=ID oud_hocmoud);
    set hocmoud_nohocdoc_&TWOYR.;
    oud_hocmoud=1;
run;

/* Remove the duplication of ID*/
PROC SQL;
    CREATE TABLE hocmoud2_&TWOYR. AS /*shorten the dsn*/ SELECT DISTINCT ID,
        oud_hocmoud FROM hocmoud_nohocdoc_&TWOYR. ;
QUIT;

/* Print the total observed counts - HOCMOUD */
TITLE "HOCMOUD Crude - oud_hocmoud(&fouryr.)";

PROC SQL;
    SELECT oud_hocmoud, IFN(COUNT(distinct ID)>0 AND COUNT(distinct ID) <= 10,
        -1, COUNT(distinct ID)) AS N_ID_supp FROM hocmoud2_&TWOYR. GROUP BY
        oud_hocmoud ;
QUIT;
TITLE;

/* Print the observed counts from HOCMOUD by Race and Sex*/
PROC SQL;
    CREATE TABLE hocmoud_sex_race_&TWOYR. AS SELECT DISTINCT
        hocmoud2_&TWOYR..ID, hocmoud2_&TWOYR..oud_hocmoud,
        demo_race_sex.FINAL_SEX, demo_race_sex.FINAL_RE FROM hocmoud2_&TWOYR.
        LEFT JOIN demo_race_sex ON hocmoud2_&TWOYR..ID=demo_race_sex.ID ;
QUIT;
TITLE "HOCMOUD (by sex, race) - oud_hocmoud(&fouryr.)";

PROC SQL;
    SELECT DISTINCT oud_hocmoud, FINAL_SEX, FINAL_RE, IFN(COUNT(distinct ID) > 0
        AND COUNT(distinct ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        hocmoud_sex_race_&TWOYR. GROUP BY oud_hocmoud, FINAL_SEX, FINAL_RE ;
QUIT;
TITLE;

/********************************************************/
;
/**************** CRC Log-linear Analysis ***************/
;
/********************** WITH DEATH **********************/
;
/********************************************************/
;
/********************************************************/
;

/* Merge all data sources together */

/* Step 1: Rename ID to rawID for all datasets first */
data apcd_cm_birth_&TWOYR.;
    set apcd_cm_birth_&TWOYR.;
    rename ID=rawID;
run;

data bsas_&TWOYR.;
    set bsas_&TWOYR.;
    rename ID=rawID;
run;

data death_&TWOYR.;
    set death_&TWOYR.;
    rename ID=rawID;
run;

data pmp_&TWOYR.;
    set pmp_&TWOYR.;
    rename ID=rawID;
run;

data matris_&TWOYR.;
    set matris_&TWOYR.;
    rename ID=rawID;
run;

data hocmoud2_&TWOYR.;
    set hocmoud2_&TWOYR.;
    rename ID=rawID;
run;

/* Step 2: Create the merged file */
proc sql;
    create table merged_obs_&TWOYR. as select coalesce(hoc.rawID, matris.rawID,
        pmp.rawID, death.rawID, bsas.rawID, apcd_cm_birth.rawID) as ID,
        apcd_cm_birth.*, bsas.*, death.*, pmp.*, matris.*, hoc.* from
        apcd_cm_birth_&TWOYR. as apcd_cm_birth full join bsas_&TWOYR. as bsas on
        apcd_cm_birth.rawID=bsas.rawID full join death_&TWOYR. as death on
        coalesce(apcd_cm_birth.rawID, bsas.rawID)=death.rawID full join
        pmp_&TWOYR. as pmp on coalesce(apcd_cm_birth.rawID, bsas.rawID,
        death.rawID)=pmp.rawID full join matris_&TWOYR. as matris on
        coalesce(apcd_cm_birth.rawID, bsas.rawID, death.rawID, pmp.rawID)=
        matris.rawID full join hocmoud2_&TWOYR. as hoc on
        coalesce(apcd_cm_birth.rawID, bsas.rawID, death.rawID, pmp.rawID,
        matris.rawID)=hoc.rawID ;
quit;

/* GRACE: MAKE SURE THE VARIABLES ARE LISTED IN THE ORDER THEY APPEAR IN THE DATASET.
RUN PROC CONTENTS AND CHECK THE ORDER IN THE ARRAY */
/* RENAME THE NEW OUD VARIABLES */
/* data merged_obs_&TWOYR. (rename = (dmh_oud=oud_dmh hocmoud_oud=oud_hocmoud hocsurv_oud=oud_hocsurv)) ; */
/* set merged_obs_&TWOYR.; */
/* run; */

/* Label the missing cells with zeros */
DATA merged_obs_&TWOYR.;
    SET merged_obs_&TWOYR.;
    ARRAY missing {*} oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp
        oud_hocmoud;
    DO i=1 TO dim(missing);
        IF missing[i]=. THEN missing[i]=0;
    END;
    DROP i;
RUN;

/* Remove the non-OUD people */
DATA merged_obs_&TWOYR._1;
    SET merged_obs_&TWOYR.;
    IF SUM(of oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp
        oud_hocmoud)=0 THEN
        DELETE;/*GRACE: I TYPED IN THE VARIABLES JUST SO WE DON'T ALWAYS HAVE TO CHECK THEIR ORDER*/
RUN;

/* Merge Sex and Race */
PROC SQL;
    CREATE TABLE merged_obs_&TWOYR._1 AS SELECT DISTINCT merged_obs_&TWOYR._1.*,
        demo_race_sex.FINAL_SEX AS sex_combo, demo_race_sex.FINAL_RE AS
        race_combo FROM merged_obs_&TWOYR._1 LEFT JOIN demo_race_sex ON
        merged_obs_&TWOYR._1.ID=demo_race_sex.ID ;
QUIT;

title "ALL THESE ANALYSES ARE WITH DEATH";

PROC SQL;
    SELECT sex_combo, race_combo, IFN(COUNT(distinct ID) > 0 AND COUNT(distinct
        ID) <= 10, -1, COUNT(distinct ID)) AS N_ID_supp FROM
        merged_obs_&TWOYR._1 GROUP BY sex_combo, race_combo ;
QUIT;
title2;

title2 "(OUD) KNOWN - Yr&fouryr. (with Death)";

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS N_KNOWN_&TWOYR. FROM merged_obs_&TWOYR._1 ;
QUIT;
title2;

proc contents data=merged_obs_&TWOYR._1;
run;

/* Delete the missing demographics or non-MA residents */
;

PROC SQL;
    CREATE TABLE merged_obs_&TWOYR._1 AS SELECT DISTINCT ID, oud_apcd_cm_birth,
        oud_bsas, oud_death, oud_matris, oud_pmp, oud_hocmoud, sex_combo,
        race_combo FROM merged_obs_&TWOYR._1 WHERE race_combo IN (1,2,3,4,5) AND
        sex_combo IN (1,2) ;
QUIT;

/***************************************/
/* Making Contingency Table (sex, race)*/

/* &fouryr. */
PROC SUMMARY DATA=merged_obs_&TWOYR._1 NWAY COMPLETETYPES;
    CLASS oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp oud_hocmoud
        sex_combo race_combo /MISSING;
    OUTPUT OUT=Contingency_&TWOYR.;
RUN;

DATA Contingency_&TWOYR.;
    SET Contingency_&TWOYR.;
    raw_n=_FREQ_;
    DROP _TYPE_ _FREQ_;
RUN;

/* Remove the all zeros row */
DATA Contingency_&TWOYR.;
    SET Contingency_&TWOYR.;
    IF SUM(of oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp
        oud_hocmoud)=0 THEN DELETE;
RUN;

/* Combine two race groups into one */
;

DATA Contingency_&TWOYR. (DROP=race_combo RENAME=(race_combo1=race_combo));
    SET Contingency_&TWOYR.;
    IF race_combo in (3,5) THEN race_combo1=3;
    ELSE race_combo1=race_combo;
RUN;

/* Total number of KNOWN (Rm Missing/Non-MA Residents) (with Death) - &fouryr. */
PROC SQL;
    title2
        "Total number of KNOWN (Rm Missing/Non-MA Residents) (with Death) - &fouryr.";
    SELECT DISTINCT sum(raw_n) AS N_Obs FROM Contingency_&TWOYR. ;
    title2;

    title2
        "WDEATH 1) Total number of KNOWN by race and sex (Rm Missing/Non-MA Residents) (with Death) - YYYY";
    /* THIS TABLE IS SAVED AS 'KNOWN_wDeath_&TWOYR.' */
    title3 "Save this in the CSV called KNOWN_GRP_wDeath_YY_ZZ";
    SELECT DISTINCT &fouryr. AS YEAR, sex_combo, race_combo, sum(raw_n) AS N_Obs
        FROM Contingency_&TWOYR. GROUP BY race_combo, sex_combo ;
    title2;
QUIT;

/* Create no-strat contingency table */
PROC SQL;
    CREATE TABLE Contingency_&TWOYR._noS AS SELECT oud_apcd_cm_birth, oud_bsas,
        oud_death, oud_matris, oud_pmp, oud_hocmoud, SUM(raw_n) AS count FROM
        Contingency_&TWOYR. GROUP BY oud_apcd_cm_birth, oud_bsas, oud_death,
        oud_matris, oud_pmp, oud_hocmoud;
QUIT;
/* Print Contingency table */
title2 "(OUD)Contingency Table - Yr&fouryr. (with Death)";

PROC SQL;
    SELECT * FROM Contingency_&TWOYR._noS ;
QUIT;
title2;

/* Add suppression */
DATA Contingency_&TWOYR._2;
    SET Contingency_&TWOYR.;
    IF raw_n > 0 AND raw_n <= 10 THEN count=-1;
    ELSE count=raw_n;
    DROP raw_n;
RUN;
/* Print Contingency table */
title2 "(OUD)Contingency Table (sex, race(4 grps)) - Yr&fouryr. (with Death)";

PROC SQL;
    SELECT oud_apcd_cm_birth, oud_bsas, oud_death, oud_matris, oud_pmp,
        oud_hocmoud, sex_combo, race_combo, count FROM Contingency_&TWOYR._2 ;
QUIT;
title2;

/* Split the datasets for stratified analysis */
%MACRO splitdt_wDeath_sex_race;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            PROC SQL;
                CREATE TABLE SEX&i._RACE&j._&TWOYR. AS SELECT * FROM
                    Contingency_&TWOYR. WHERE sex_combo=&i. AND race_combo=&j. ;
            QUIT;
        %END;
    %END;
%MEND splitdt_wDeath_sex_race;
%splitdt_wDeath_sex_race;

/* Create data with small sample adjustment (with DEATH) */
;

DATA Contingency_&TWOYR._adj (drop=raw_n);
    SET Contingency_&TWOYR.;
    adj_n=raw_n+(0.5**(5-1)); /* K = 5 */
RUN;

/* Split the datasets for stratified analysis */
%MACRO splitdt_wDeath_sex_race_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            PROC SQL;
                CREATE TABLE Adj_SEX&i._RACE&j._&TWOYR. AS SELECT * FROM
                    Contingency_&TWOYR._adj WHERE sex_combo=&i. AND race_combo=
                    &j. ;
            QUIT;
        %END;
    %END;
%MEND splitdt_wDeath_sex_race_adj;
%splitdt_wDeath_sex_race_adj;

/********************* FINISH DATA MANIPULATION *****************************/
;

/**************************/
;
/* Run no strata analysis */
/**************************/
/* Poisson */
;
ODS SELECT none;
ODS OUTPUT parameterestimates (persist=proc)=est_poi_wDeath_noS_auto_&TWOYR.
    fitstatistics (persist=proc)=AIC_poi_wDeath_noS_auto_&TWOYR.;

PROC HPGENSELECT DATA=Contingency_&TWOYR._noS;
    CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0") oud_death(ref="0")
        oud_matris(ref="0") oud_pmp(ref="0") oud_hocmoud(ref="0") /param=ref;
    MODEL count=oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp
        oud_hocmoud /DIST=Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death
        oud_matris oud_pmp oud_hocmoud) link=Log CL;
RUN;
ODS OUTPUT CLEAR;
ODS SELECT ALL;
/* NB */
;
ODS SELECT none;
ODS OUTPUT parameterestimates (persist=proc)=est_nb_wDeath_noS_auto_&TWOYR.
    fitstatistics (persist=proc)=AIC_nb_wDeath_noS_auto_&TWOYR.;

PROC HPGENSELECT DATA=Contingency_&TWOYR._noS;
    CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0") oud_death(ref="0")
        oud_matris(ref="0") oud_pmp(ref="0") oud_hocmoud(ref="0") /param=ref;
    MODEL count=oud_apcd_cm_birth oud_bsas oud_death oud_matris oud_pmp
        oud_hocmoud /DIST=NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death
        oud_matris oud_pmp oud_hocmoud) link=Log CL;
RUN;
ODS OUTPUT CLEAR;
ODS SELECT ALL;

DATA est0_poi_wDeath_noS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_poi_wDeath_noS_auto_&TWOYR. (WHERE=(Parameter in ("Intercept")));
    Model="Poisson";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="With Death";
    Small_Sample_Adj="No Adj";
RUN;

DATA est0_nb_wDeath_noS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_nb_wDeath_noS_auto_&TWOYR. (WHERE=(Parameter in ("Intercept")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="With Death";
    Small_Sample_Adj="No Adj";
RUN;

data est_nb_poi_wDeath_nS_main_&TWOYR.;
    set est0_poi_wDeath_noS_main_&TWOYR. est0_nb_wDeath_noS_main_&TWOYR.;
run;
title2
    "WDeath 2) Results of Estimates of Models without Stratification (main effect) - &fouryr.";
title3 "Save this in the CSV titled Est0_nb_poi_noStrata_wDeath_YY_ZZ.csv";

proc print data=est_nb_poi_wDeath_nS_main_&TWOYR.;
run;
title2;

DATA disp_nb_wDeath_nS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_nb_wDeath_noS_auto_&TWOYR. (WHERE=(Parameter in ("Dispersion")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="With Death";
    Small_Sample_Adj="No Adj";
RUN;
title2
    "WDeath 3) Results of Estimated Dispersion of NB Models without Stratification (main effect) - &fouryr.";
title3 "Save this in the CSV titled Disp_nb_poi_noStrata_wDeath_YY_ZZ.csv";

proc print data=disp_nb_wDeath_nS_main_&TWOYR.;
run;
title2;

DATA AIC_poi_wDeath_noS_main_&TWOYR. (KEEP=Label Value Model Year Interaction
    Strata W_wo_Death Small_Sample_Adj);
    SET AIC_poi_wDeath_noS_auto_&TWOYR. (WHERE=(Label IN
        ("AIC (smaller is better)")));
    Model="Poisson";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="With Death";
    Small_Sample_Adj="No Adj";
RUN;

DATA AIC_nb_wDeath_noS_main_&TWOYR. (KEEP=Label Value Model Year Interaction
    Strata W_wo_Death Small_Sample_Adj);
    SET AIC_nb_wDeath_noS_auto_&TWOYR. (WHERE=(Label IN
        ("AIC (smaller is better)")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="With Death";
    Small_Sample_Adj="No Adj";
RUN;

data aic_nb_poi_wDeath_nS_main_&TWOYR.;
    set AIC_poi_wDeath_noS_main_&TWOYR. AIC_nb_wDeath_noS_main_&TWOYR.;
run;
title2
    "WDeath 4) Results of AIC without Stratification (main effect) - &fouryr.";
title3 "Save output in CSV titled AIC_nb_poi_noStrata_wDeath_YY_ZZ.csv";

proc print data=aic_nb_poi_wDeath_nS_main_&TWOYR.;
run;
title2;
/* Done with the no-strata analysis */
/* Note:
For the following CRC analyses, we run the primary and all sensitivity analysis together and then combine the results into a single table.
When the estimates are not converged in the primary analysis, we evaluate if it is due to the small sample issue and can use the corresponding results from the small sample adjusted analysis.
We output the final model with Poisson distributional assumption versus NB distributional assumption and run the comparison in the summary code (R code) to decide the final model.
In our OUD analysis, we finally decided to use NB distributional assumption for all the years and strata for consistency reason.
 */
/**************************************************************************************************/
;
/* Primary - Fit automated step-wise selection (AIC + 5% pvalue) up to two-way interaction model */
;
/**************************************************************************************************/
;

%MACRO wDeath_strata_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL raw_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death
                    oud_matris oud_pmp oud_hocmoud) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* If you want to automatically select up to K-1 way interaction term, please remove | and @2 in the MODEL statement.
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL raw_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death oud_matris
                    oud_pmp oud_hocmoud) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND wDeath_strata_auto;
%wDeath_strata_auto;

/* Combine results from stratified model */
%MACRO combine_est_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est0_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA est0_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA disp_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_wDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_wDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_wDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_est_auto;
%combine_est_auto;

%MACRO combine_aic_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA AIC_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex Race
                Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_wDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_wDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_auto;
%combine_aic_auto;

/********************* FINISH AUTOMATED STEP-WISE TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/****************************************************/
;
/* Sensitivity - Fit fixed two-way interaction model */
;
/****************************************************/
;

%MACRO wDeath_strata_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL raw_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death
                    oud_matris oud_pmp oud_hocmoud) link=Log CL;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.
                /*TECH = QUANEW - include that specification for 2015 data if getting an error*/;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL raw_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death oud_matris
                    oud_pmp oud_hocmoud) link=Log CL;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND wDeath_strata_twoway;
%wDeath_strata_twoway;

/* Combine results from stratified model */
%MACRO combine_est_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est0_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA est0_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA disp_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_wDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_wDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_wDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_est_twoway;
%combine_est_twoway;

%MACRO combine_aic_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA AIC_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex Race
                Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="With Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_wDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_wDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_twoway;
%combine_aic_twoway;
/********************* FINISH FIXED TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/**************************************************************************************************************************/
;
/* Sensitivity - Fit Adjusted data using automated step-wise selectrion (AIC + 5% pvalue) up to two-way interaction model */
;
/**************************************************************************************************************************/
;

%MACRO wDeath_strata_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=Adj_SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL adj_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death
                    oud_matris oud_pmp oud_hocmoud) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_wDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_wDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=Adj_SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_death(ref="0") oud_matris(ref="0") oud_pmp(ref="0")
                    oud_hocmoud(ref="0") /param=ref;
                MODEL adj_n=
                    oud_apcd_cm_birth|oud_bsas|oud_death|oud_matris|oud_pmp|oud_hocmoud@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_death oud_matris
                    oud_pmp oud_hocmoud) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND wDeath_strata_auto_adj;
%wDeath_strata_auto_adj;

/* Combine results from stratified model */
%MACRO combine_est_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est0_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA est0_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA disp_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_wDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_wDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est0_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_wDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_est_auto_adj;
%combine_est_auto_adj;

%MACRO combine_aic_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA AIC_nb_wDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex Race
                Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_wDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="With Death";
                Small_Sample_Adj="Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_wDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_wDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_wDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_auto_adj;
%combine_aic_auto_adj;

/********************* FINISH SMALL SAMPLE ADJUSTED AUTOMATED STEP-WISE TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/******************************************************/
;
/************ Combine All Results Together ************/
;
/******************************************************/
;

data est_poi_nb_wDeath_&TWOYR.;
    length Interaction $32;
    set est_poi_wDeath_S_auto_&TWOYR. est_poi_wDeath_S_twoway_&TWOYR.
        est_poi_wDeath_S_auto_adj_&TWOYR. est_nb_wDeath_S_auto_&TWOYR.
        est_nb_wDeath_S_twoway_&TWOYR. est_nb_wDeath_S_auto_adj_&TWOYR.;
run;
title2 "WDeath 5) Results of Estimates for Models with Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled Est0_nb_poi_wDeath_YY.CSV";

proc print data=est_poi_nb_wDeath_&TWOYR.;
run;
title2;

data disp_nb_wDeath_&TWOYR.;
    length Interaction $32;
    set disp_nb_wDeath_S_auto_&TWOYR. disp_nb_wDeath_S_twoway_&TWOYR.
        disp_nb_wDeath_S_auto_adj_&TWOYR.;
run;
title2
    "WDeath 6) Results of Estimated Dispersion for NB Models with Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled Disp_nb_poi_wDeath_YY.CSV";

proc print data=disp_nb_wDeath_&TWOYR.;
run;
title2;

data aic_poi_nb_wDeath_&TWOYR.;
    length Interaction $32;
    set aic_poi_wDeath_S_auto_&TWOYR. aic_poi_wDeath_S_twoway_&TWOYR.
        aic_poi_wDeath_S_auto_adj_&TWOYR. aic_nb_wDeath_S_auto_&TWOYR.
        aic_nb_wDeath_S_twoway_&TWOYR. aic_nb_wDeath_S_auto_adj_&TWOYR.;
run;
title2 "WDeath 7) Results of AIC for Models with Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled AIC_nb_poi_wDeath_YY.csv";

proc print data=aic_poi_nb_wDeath_&TWOYR.;
run;
title2;
/*************** FINISH THE COMBINATION OF RESULTS **************/
;
/************ FINISH THE ANALYSIS OF DATA WITH DEATH ************/
;

/*********************************************************/
;
/*********************************************************/
;
/********************** WITHOUT DEATH ********************/
;
/*********************************************************/
;
/*********************************************************/
;
/* GRACE: THESE ANALYSES HAVE NOT BEEN UPDATED WITH THE HOC DATA */
title "ALL ANALYSES WITHOUT DEATH";

/* Merge DATA Sources Together */
PROC SQL;
    CREATE TABLE merged_obs_woDeath_&TWOYR. (DROP=rawID merge1ID /*merge2ID*/
        merge3ID) AS SELECT COALESCE(merge3.merge3ID, matris.rawID) AS ID, *
        FROM (SELECT COALESCE(merge1.merge1ID, pmp.rawID) AS merge3ID, *
        /*     FROM (SELECT COALESCE(merge1.merge1ID, death.rawID) AS merge2ID, * */
        FROM (SELECT COALESCE(apcd_cm_birth.rawID, bsas.rawID) AS merge1ID, *
        FROM apcd_cm_birth_&TWOYR. (RENAME=(ID=rawID)) AS apcd_cm_birth FULL
        JOIN bsas_&TWOYR. (RENAME=(ID=rawID)) AS bsas ON apcd_cm_birth.rawID=
        bsas.rawID) AS merge1
        /*     FULL JOIN death_&TWOYR. (RENAME=(ID=rawID)) AS death */
        /*        ON merge1.merge1ID = death.rawID) AS merge2 */ FULL JOIN
        pmp_&TWOYR. (RENAME=(ID=rawID)) AS pmp ON merge1.merge1ID=pmp.rawID) AS
        merge3 FULL JOIN matris_&TWOYR. (RENAME=(ID=rawID)) AS matris ON
        merge3.merge3ID=matris.rawID;
QUIT;

proc contents data=merged_obs_woDeath_&TWOYR. varnum;
run;

/* data merged_obs_woDeath_&TWOYR. (DROP = dmh_oud hocmoud_oud hocsurv_oud); */
/* set merged_obs_woDeath_&TWOYR.; */
/* oud_dmh = dmh_oud; */
/* oud_hocmoud = hocmoud_oud; */
/* oud_hocsurv = hocsurv_oud; */
/* run; */

/* Label the missing cells with zeros */
DATA merged_obs_woDeath_&TWOYR.;
    SET merged_obs_woDeath_&TWOYR.;
    ARRAY missing {*} oud_apcd_cm_birth oud_bsas oud_matris oud_pmp;
    DO i=1 TO dim(missing);
        IF missing[i]=. THEN missing[i]=0;
    END;
    DROP i;
RUN;

/* Remove the non-OUD people */
DATA merged_obs_woDeath_&TWOYR._1;
    SET merged_obs_woDeath_&TWOYR.;
    IF SUM(of oud_apcd_cm_birth oud_bsas oud_matris oud_pmp)=0 THEN DELETE;
RUN;

/* Merge Sex and Race */
PROC SQL;
    CREATE TABLE merged_obs_woDeath_&TWOYR._1 AS SELECT DISTINCT
        merged_obs_woDeath_&TWOYR._1.*, demo_race_sex.FINAL_SEX AS sex_combo,
        demo_race_sex.FINAL_RE AS race_combo FROM merged_obs_woDeath_&TWOYR._1
        LEFT JOIN demo_race_sex ON merged_obs_woDeath_&TWOYR._1.ID=
        demo_race_sex.ID ;
QUIT;
TITLE2 "(OUD) KNOWN - Yr&fouryr. (without Death) (sex, race)";

PROC SQL;
    SELECT sex_combo, race_combo, COUNT(distinct ID) AS raw_n,
        IFN(COUNT(distinct ID) > 0 AND COUNT(distinct ID) <= 10, -1,
        COUNT(distinct ID)) AS N_ID_supp FROM merged_obs_woDeath_&TWOYR._1 GROUP
        BY sex_combo, race_combo ;
QUIT;
title2;

/* Delete the missing demographics or non-MA residents */
;

PROC SQL;
    CREATE TABLE merged_obs_woDeath_&TWOYR._1 AS SELECT DISTINCT ID,
        oud_apcd_cm_birth, oud_bsas, oud_matris, oud_pmp, sex_combo, race_combo
        FROM merged_obs_woDeath_&TWOYR._1 WHERE race_combo IN (1,2,3,4,5) AND
        sex_combo IN (1,2) ;
QUIT;

title2 "(OUD) KNOWN - Yr&fouryr. (without Death)(Rm Missing/Multiple Demo)";

PROC SQL;
    SELECT COUNT(DISTINCT ID) AS N_KNOWN_&TWOYR. FROM
        merged_obs_woDeath_&TWOYR._1 ;
QUIT;
title2;

/***************************************/
/* Making Contingency Table (sex, race)*/

/* &fouryr. */
PROC SUMMARY DATA=merged_obs_woDeath_&TWOYR._1 NWAY COMPLETETYPES;
    CLASS oud_apcd_cm_birth oud_bsas oud_matris oud_pmp sex_combo race_combo
        /MISSING;
    OUTPUT OUT=Contingency_woDeath_&TWOYR.;
RUN;

DATA Contingency_woDeath_&TWOYR.;
    SET Contingency_woDeath_&TWOYR.;
    raw_n=_FREQ_;
    DROP _TYPE_ _FREQ_;
RUN;

/* Remove the all zeros row */
DATA Contingency_woDeath_&TWOYR.;
    SET Contingency_woDeath_&TWOYR.;
    IF SUM(of oud_apcd_cm_birth oud_bsas oud_matris oud_pmp)=0 THEN DELETE;
RUN;

/* Combine two race groups into one */
;

DATA Contingency_woDeath_&TWOYR. (DROP=race_combo RENAME=(race_combo1=
    race_combo));
    SET Contingency_woDeath_&TWOYR.;
    IF race_combo in (3,5) THEN race_combo1=3;
    ELSE race_combo1=race_combo;
RUN;

/* Total number of KNOWN (Rm Missing/Non-MA Residents) (without Death) */
PROC SQL;
    title2
        "Total number of KNOWN (Rm Missing/Non-MA Residents) (without Death) - &fouryr. ";
    SELECT DISTINCT sum(raw_n) AS N_Obs FROM Contingency_woDeath_&TWOYR. ;
    title2;
    title2
        "WODeath 1) Total number of KNOWN by race and sex (Rm Missing/Non-MA Residents) (with Death) - &fouryr. ";
    /* THIS TABLE IS SAVED AS 'KNOWN_woDeath_&TWOYR.' */
    title3 "Save this in the CSV called KNOWN_GRP_woDeath_YY_ZZ";
    SELECT DISTINCT &fouryr. AS YEAR, sex_combo, race_combo, sum(raw_n) AS N_Obs
        FROM Contingency_woDeath_&TWOYR. GROUP BY race_combo, sex_combo ;
    title2;
QUIT;

/* Create no-strat contingency table */
PROC SQL;
    CREATE TABLE Contingency_woDeath_&TWOYR._noS AS SELECT oud_apcd_cm_birth,
        oud_bsas, oud_matris, oud_pmp, SUM(raw_n) AS count FROM
        Contingency_woDeath_&TWOYR. GROUP BY oud_apcd_cm_birth, oud_bsas,
        oud_matris, oud_pmp ;
QUIT;
/* Print Contingency table */
title2 "(OUD)Contingency Table - Yr&fouryr. (without Death)";

PROC SQL;
    SELECT * FROM Contingency_woDeath_&TWOYR._noS ;
QUIT;
title2;

/* Add suppression */
DATA Contingency_woDeath_&TWOYR._2;
    SET Contingency_woDeath_&TWOYR.;
    IF raw_n > 0 AND raw_n <= 10 THEN count=-1;
    ELSE count=raw_n;
    DROP raw_n;
RUN;
/* Print Contingency table */
title2
    "(OUD)Contingency Table (sex, race(4 grps)) - Yr&fouryr. (without Death)";

PROC SQL;
    SELECT oud_apcd_cm_birth, oud_bsas, oud_matris, oud_pmp, sex_combo,
        race_combo, count FROM Contingency_woDeath_&TWOYR._2 ;
QUIT;
title2;

/* Split the datasets for stratified analysis */
%MACRO splitdt_woDeath_sex_race;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            PROC SQL;
                CREATE TABLE SEX&i._RACE&j._&TWOYR. AS SELECT * FROM
                    Contingency_woDeath_&TWOYR. WHERE sex_combo=&i. AND
                    race_combo=&j. ;
            QUIT;
        %END;
    %END;
%MEND splitdt_woDeath_sex_race;
%splitdt_woDeath_sex_race;

/* Create data with small sample adjustment (Without Death) */
;

DATA Contingency_woDeath_&TWOYR._adj (drop=raw_n);
    SET Contingency_woDeath_&TWOYR.;
    adj_n=raw_n+(0.5**(5-1)); /* K = 5 */
RUN;

/* Split the datasets for stratified analysis */
%MACRO splitdt_woDeath_sex_race_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            PROC SQL;
                CREATE TABLE Adj_SEX&i._RACE&j._&TWOYR. AS SELECT * FROM
                    Contingency_woDeath_&TWOYR._adj WHERE sex_combo=&i. AND
                    race_combo=&j. ;
            QUIT;
        %END;
    %END;
%MEND splitdt_woDeath_sex_race_adj;
%splitdt_woDeath_sex_race_adj;

/********************* FINISH DATA MANIPULATION *****************************/
;

/**************************/
;
/* Run no strata analysis */
/**************************/
;
/* Poisson */
;
ODS SELECT none;
ODS OUTPUT parameterestimates (persist=proc)=est_poi_woDeath_noS_main_&TWOYR.
    fitstatistics (persist=proc)=AIC_poi_woDeath_noS_main_&TWOYR.;

PROC HPGENSELECT DATA=Contingency_woDeath_&TWOYR._noS;
    CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0") oud_matris(ref="0")
        oud_pmp(ref="0") /param=ref;
    MODEL count=oud_apcd_cm_birth oud_bsas oud_matris oud_pmp /DIST=Poisson
        INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris oud_pmp) link=Log CL;
RUN;

ODS OUTPUT CLEAR;
ODS SELECT ALL;
/* NB */
;
ODS SELECT none;
ODS OUTPUT parameterestimates (persist=proc)=est_nb_woDeath_noS_main_&TWOYR.
    fitstatistics (persist=proc)=AIC_nb_woDeath_noS_main_&TWOYR.;

PROC HPGENSELECT DATA=Contingency_woDeath_&TWOYR._noS;
    CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0") oud_matris(ref="0")
        oud_pmp(ref="0") /param=ref;
    MODEL count=oud_apcd_cm_birth oud_bsas oud_matris oud_pmp /DIST=NB INCLUDE=
        (oud_apcd_cm_birth oud_bsas oud_matris oud_pmp ) link=Log CL;
RUN;
ODS OUTPUT CLEAR;
ODS SELECT ALL;

DATA est0_poi_woDeath_noS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_poi_woDeath_noS_main_&TWOYR. (WHERE=(Parameter in ("Intercept")));
    Model="Poisson";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="Without Death";
    Small_Sample_Adj="No Adj";
RUN;

DATA est0_nb_woDeath_noS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_nb_woDeath_noS_main_&TWOYR. (WHERE=(Parameter in ("Intercept")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="Without Death";
    Small_Sample_Adj="No Adj";
RUN;

data est_nb_poi_woDeath_nS_main_&TWOYR.;
    set est0_poi_woDeath_noS_main_&TWOYR. est0_nb_woDeath_noS_main_&TWOYR.;
run;
title2
    "WODeath 2) Results of Estimates of Models without Stratification (main effect) - &fouryr.";
title3 "Save this in the csv titled Est0_nb_poi_noStrata_woDeath_YY_ZZ.csv";

proc print data=est_nb_poi_woDeath_nS_main_&TWOYR.;
run;
title2;

DATA disp_nb_woDeath_nS_main_&TWOYR. (KEEP=Parameter Estimate StdErr LowerCL
    UpperCL Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
    SET est_nb_woDeath_noS_main_&TWOYR. (WHERE=(Parameter in ("Dispersion")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="Without Death";
    Small_Sample_Adj="No Adj";
RUN;
title2
    "WODeath 3) Results of Estimated Dispersion of NB Models without Stratification (main effect) - &fouryr.";
title3 "Save in the CSV titled Disp_nb_poi_noStrata_woDeath_YY_ZZ.csv";

proc print data=disp_nb_woDeath_nS_main_&TWOYR.;
run;
title2;

DATA AIC_poi_woDeath_noS_main_&TWOYR. (KEEP=Label Value Model Year Interaction
    Strata W_wo_Death Small_Sample_Adj);
    SET AIC_poi_woDeath_noS_main_&TWOYR. (WHERE=(Label IN
        ("AIC (smaller is better)")));
    Model="Poisson";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="Without Death";
    Small_Sample_Adj="No Adj";
RUN;

DATA AIC_nb_woDeath_noS_main_&TWOYR. (KEEP=Label Value Model Year Interaction
    Strata W_wo_Death Small_Sample_Adj);
    SET AIC_nb_woDeath_noS_main_&TWOYR. (WHERE=(Label IN
        ("AIC (smaller is better)")));
    Model="NB";
    Year=&fouryr.;
    Strata="No Strata";
    Interaction="Main Effect";
    W_wo_Death="Without Death";
    Small_Sample_Adj="No Adj";
RUN;

data aic_nb_poi_woDeath_nS_main_&TWOYR.;
    set AIC_poi_woDeath_noS_main_&TWOYR. AIC_nb_woDeath_noS_main_&TWOYR.;
run;
title2
    "WODeath 4) Results of AIC without Stratification (main effect) - &fouryr.";
title3 "Save output in CSV called AIC_nb_poi_noStrata_woDeath_YY_ZZ.csv";

proc print data=aic_nb_poi_woDeath_nS_main_&TWOYR.;
run;
title2;
/* Done with the no-strata analysis */
/**************************************************************************************************/
;
/* Primary - Fit automated step-wise selectrion (AIC + 5% pvalue) up to two-way interaction model */
;
/**************************************************************************************************/
;

%MACRO woDeath_strata_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL raw_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris
                    oud_pmp) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL raw_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris oud_pmp)
                    link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND woDeath_strata_auto;
%woDeath_strata_auto;

/* Combine results from stratified model */
%MACRO combine_est_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA est_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept","Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA disp_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_woDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_woDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_woDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_est_auto;
%combine_est_auto;

%MACRO combine_aic_auto;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA AIC_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_woDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_woDeath_S_auto_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_auto;
%combine_aic_auto;

/********************* FINISH AUTOMATED STEP-WISE TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/******************************************************/
;
/* Sensitivity - Fit fixed two-way interaction model */
;
/******************************************************/
;

%MACRO woDeath_strata_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL raw_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris
                    oud_pmp) link=Log CL;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL raw_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris oud_pmp)
                    link=Log CL;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND woDeath_strata_twoway;
%woDeath_strata_twoway;

/* Combine results from stratified model */
%MACRO combine_est_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA est_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept","Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA disp_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_woDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_woDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_woDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

%MEND combine_est_twoway;
%combine_est_twoway;

%MACRO combine_aic_twoway;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;

            DATA AIC_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Fix Two-Way";
                W_wo_Death="Without Death";
                Small_Sample_Adj="No Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_woDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_woDeath_S_twoway_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_twoway;
%combine_aic_twoway;
/********************* FINISH TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/*************************************************************************************************************************/
;
/* Sensitivity - Fit Adjusted data using automated step-wise selectrion (AIC + 5% pvalue) up to two-way interaction model */
;
/**************************************************************************************************************************/
;

%MACRO woDeath_strata_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            /* Poisson */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_poi_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_poi_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=Adj_SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL adj_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =Poisson INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris
                    oud_pmp) link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
            /* NB */
            ;
            ODS SELECT none;
            ODS OUTPUT parameterestimates (persist=proc)=
                est_nb_woDeath_sex&i._race&j._&TWOYR. fitstatistics
                (persist=proc)=AIC_nb_woDeath_sex&i._race&j._&TWOYR.;

            PROC HPGENSELECT DATA=Adj_SEX&i._RACE&j._&TWOYR.;
                CLASS oud_apcd_cm_birth(ref="0") oud_bsas(ref="0")
                    oud_matris(ref="0") oud_pmp(ref="0") /param=ref;
                MODEL adj_n=oud_apcd_cm_birth|oud_bsas|oud_matris|oud_pmp@2/DIST
                    =NB INCLUDE=(oud_apcd_cm_birth oud_bsas oud_matris oud_pmp)
                    link=Log CL;
                SELECTION METHOD=stepwise(choose=AIC select=SL SLE=0.05
                    SLS=0.05) HIERARCHY=SINGLE;
            RUN;
            ODS OUTPUT CLEAR;
            ODS SELECT ALL;
        %END;
    %END;
%MEND woDeath_strata_auto_adj;
%woDeath_strata_auto_adj;

/* Combine results from stratified model */
%MACRO combine_est_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA est_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA est_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Intercept","Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA disp_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Parameter Estimate
                StdErr LowerCL UpperCL Sex Race Model Year Strata Interaction
                W_wo_Death Small_Sample_Adj);
                SET est_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Parameter in
                    ("Dispersion")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="Adj";
            RUN;
        %END;
    %END;

    DATA est_poi_woDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA est_nb_woDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        est_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA disp_nb_woDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        disp_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_est_auto_adj;
%combine_est_auto_adj;

%MACRO combine_aic_auto_adj;
    %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
            DATA AIC_poi_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_poi_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="Poisson";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="Adj";
            RUN;

            DATA AIC_nb_woDeath_sex&i._race&j._&TWOYR. (KEEP=Label Value Sex
                Race Model Year Strata Interaction W_wo_Death Small_Sample_Adj);
                SET AIC_nb_woDeath_sex&i._race&j._&TWOYR. (WHERE=(Label IN
                    ("AIC (smaller is better)")));
                Sex=&i.;
                Race=&j.;
                Model="NB";
                Year=&fouryr.;
                Strata="Sex Race";
                Interaction="Auto Two-Way (AIC+P-value)";
                W_wo_Death="Without Death";
                Small_Sample_Adj="Adj";
            RUN;
        %END;
    %END;

    DATA aic_poi_woDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_poi_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;

    DATA aic_nb_woDeath_S_auto_adj_&TWOYR.;
        SET %DO i=1 %TO 2; /* sex, 1 = male, 2 = female */
        %DO j=1 %TO 4;
            /* race, 1 = White Non-Hispanic, 2 = Black non-Hispanic, 3 = Asian/PI non-Hispanic/American Indian or Other non-Hispanic, 4 = Hispanic,*/
        AIC_nb_woDeath_sex&i._race&j._&TWOYR. %END;
        %END;
        ;
    RUN;
%MEND combine_aic_auto_adj;
%combine_aic_auto_adj;

/********************* FINISH SMALL SAMPLE ADJUSTED AUTOMATED STEP-WISE TWO-WAY INTERACTION MODEL RUN  *****************************/
;

/******************************************************/
;
/************ Combine All Results Together ************/
;
/******************************************************/
;

data est_poi_nb_woDeath_&TWOYR.;
    length Interaction $32;
    set est_poi_woDeath_S_twoway_&TWOYR. est_poi_woDeath_S_auto_&TWOYR.
        est_poi_woDeath_S_auto_adj_&TWOYR. est_nb_woDeath_S_twoway_&TWOYR.
        est_nb_woDeath_S_auto_&TWOYR. est_nb_woDeath_S_auto_adj_&TWOYR.;
run;
title2 "WODeath 5) Results of Estimates for Models Without Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled Est0_nb_poi_woDeath_YY.CSV";

proc print data=est_poi_nb_woDeath_&TWOYR.;
run;
title2;

data disp_nb_woDeath_&TWOYR.;
    length Interaction $32;
    set disp_nb_woDeath_S_twoway_&TWOYR. disp_nb_woDeath_S_auto_&TWOYR.
        disp_nb_woDeath_S_auto_adj_&TWOYR.;
run;
title2
    "WODeath 6) Results of Estimated Dispersion for NB Models Without Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled Disp_nb_poi_woDeath_YY.CSV";

proc print data=disp_nb_woDeath_&TWOYR.;
run;
title2;

data aic_poi_nb_woDeath_&TWOYR.;
    length Interaction $32;
    set aic_poi_woDeath_S_twoway_&TWOYR. aic_poi_woDeath_S_auto_&TWOYR.
        aic_poi_woDeath_S_auto_adj_&TWOYR. aic_nb_woDeath_S_twoway_&TWOYR.
        aic_nb_woDeath_S_auto_&TWOYR. aic_nb_woDeath_S_auto_adj_&TWOYR.;
run;
title2 "WODeath 7) Results of AIC for Models Without Death - &fouryr.";
/* THIS IS NEEDED FOR SUBSEQUENT ANALYSIS */
title3 "Save this output to the CSV titled AIC_nb_poi_woDeath_YY.csv";

proc print data=aic_poi_nb_woDeath_&TWOYR.;
run;
title2;
/*************** FINISH THE COMBINATION OF RESULTS **************/
;
/************ FINISH THE ANALYSIS OF DATA WITHOUT DEATH ************/
;
