/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 4/10/2023 			*/
/* Updated:          			*/
/*==============================*/

/*==============================*/
/*  	GLOBAL VARIABLES   		*/
/*==============================*/

%LET year = (2015:2020);
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

PROC FORMAT;
	VALUE age_grps
		low-9 = '1'
        10-19 = '2'
        20-29 = '3'
        30-39 = '4'
        40-49 = '5'
        50-59 = '6'
        60-69 = '7'
        70-79 = '8'
        80-89 = '9'
        90-99 = '10'
        99-high = '11';

/*========ICD CODES=============*/
%LET ICD = ('30400', '30401', '30402', '30403',
            '30470', '30471', '30472', '30473',
            '30550', '30551', '30552', '30553',
            'E8500', 'E8501', 'E8502', '96500',
            '96501', '96502', '96509', '9701', /* ICD9 */
            'F1120', 'F1121', 'F1110', 'F11120',
            'F11121', 'F11122', 'F11129', 'F1114',
            'F11150', 'F11151', 'F11159', 'F11181',
            'F11182', 'F11188', 'F1119',
            'F11220', 'F11221', 'F11222', 'F11229',
            'F1123', 'F1124', 'F11250', 'F11251',
            'F11259', 'F11281', 'F11282', 'F11288',
            'F1129', 'F1190', 'F11920', 'F11921',
            'F11922', 'F11929','F1193', 'F1194', 
			'F11950', 'F11951', 'F11959', 'F11981', 
			'F11982', 'F1199', 'F1110', 'F1111', /* Additional for HCS */
            'F1113', 'J0592', 'G2068',
            'G2069', 'G2070', 'G2071', 'G2072',
            'G2073', 'G2079', 'J0570', 'J0571',
            'J0572', 'J0573', 'J0574', 'J0575', /* Additional for Bup */
            'H0020', 'G2067', 'G2078', 'S0109',
            'J1230', 'HZ91ZZZ', 'HZ81ZZZ', '9464', /* Additional for Methedone */
            'T400X1A', 'T400X2A', 'T400X3A', 'T400X4A',
            'T400X1D', 'T400X2D', 'T400X3D', 'T400X4D',
            'T401X1A', 'T401X2A', 'T401X3A', 'T401X4A',
            'T401X1D', 'T401X2D', 'T401X3D', 'T401X4D',
            'T402X1A', 'T402X2A', 'T402X3A', 'T402X4A',
            'T402X1D', 'T402X2D', 'T402X3D', 'T402X4D', 
			'T403X1A', 'T403X2A', 'T403X3A', 'T403X4A', 
			'T403X1D', 'T403X2D', 'T403X3D', 'T403X4D', 
			'T404X1A', 'T404X2A', 'T404X3A', 'T404X4A', 
			'T404X1D', 'T404X2D', 'T404X3D', 'T404X4D',
			'T40601A', 'T40601D', 'T40602A', 'T40602D', 
			'T40603A', 'T40603D', 'T40604A', 'T40604D', 
			'T40691A', 'T40692A', 'T40693A', 'T40694A', 
			'T40691D', 'T40692D', 'T40693D', 'T40694D', /* T codes */
			'E8500', 'E8501', 'E8502', /* Principle Encodes */
			'G2067', 'G2068', 'G2069', 'G2070', 
			'G2071', 'G2072', 'G2073', 'G2074', 
			'G2075', /* MAT Opioid */
			'G2076', 'G2077', 'G2078', 'G2079', 
			'G2080', 'G2081', /*Opioid Trt */
 			'J0570', 'J0571', 'J0572', 'J0573', 
 			'J0574', 'J0575', 'J0592', 'S0109', 
            'G2215', 'G2216', 'G1028', /* Naloxone */
			'H0047' /* DEBATED CODE */);
PROC SQL;
    CREATE TABLE demographics AS
    SELECT DISTINCT ID, FINAL_RE, FINAL_SEX
    FROM PHDSPINE.DEMO;
QUIT;

/*======CASEMIX DATA==========*/
/* ED */
DATA casemix_ed (KEEP= ID oud_cm_ed ED_ID year age);
	SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_AGE ED_ID
				  WHERE= (ED_ADMIT_YEAR IN &year));
	IF ED_DIAG1 in &ICD OR ED_PRINCIPLE_ECODE IN &ICD THEN oud_cm_ed = 1;
	ELSE oud_cm_ed = 0;
	
	age = ED_AGE;
	year = ED_ADMIT_YEAR;
RUN;

PROC SQL;
	CREATE TABLE casemix_ed AS
	SELECT DISTINCT *
	FROM casemix_ed;
QUIT;

/* ED_DIAG */
DATA casemix_ed_diag (KEEP= oud_cm_ed_diag ED_ID);
	SET PHDCM.ED_DIAG (KEEP= ED_ID ED_DIAG);
	IF ED_DIAG in &ICD THEN oud_cm_ed_diag = 1;
	ELSE oud_cm_ed_diag = 0;
RUN;

PROC SQL;
	CREATE TABLE casemix_ed_diag AS
	SELECT DISTINCT *
	FROM casemix_ed_diag;
QUIT;

/* ED_PROC */
DATA casemix_ed_proc (KEEP= oud_cm_ed_proc ED_ID);
	SET PHDCM.ED_PROC (KEEP= ED_ID ED_PROC);
	IF ED_PROC in &ICD THEN oud_cm_ed_proc = 1;
	ELSE oud_cm_ed_proc = 0;
RUN;

PROC SQL;
	CREATE TABLE casemix_ed_proc AS
	SELECT DISTINCT *
	FROM casemix_ed_proc;
QUIT;

/* CASEMIX ED MERGE */
PROC SQL;
	CREATE TABLE casemix AS 
	SELECT *
	FROM casemix_ed
	LEFT JOIN casemix_ed_diag ON casemix_ed.ED_ID = casemix_ed_diag.ED_ID
	LEFT JOIN casemix_ed_proc ON casemix_ed_diag.ED_ID = casemix_ed_proc.ED_ID;
QUIT;

DATA casemix (KEEP= ID oud year agegrp);
	SET casemix;

	IF SUM(oud_cm_ed_proc, oud_cm_ed_diag, oud_cm_ed) > 0 THEN oud = 1;
	ELSE oud = 0;

    agegrp = put(age, age_grps.);
	
	IF oud = 0 THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE oud_stratified AS
    SELECT DISTINCT agegrp, FINAL_RE, FINAL_SEX, year, 
    IFN(COUNT(DISTINCT ID) IN (1:10), -1, COUNT(DISTINCT ID)) AS N_ID
    FROM (
        SELECT DISTINCT * FROM casemix
        LEFT JOIN demographics ON demographics.ID = casemix.ID
    ) AS oud
    GROUP BY agegrp, FINAL_RE, FINAL_SEX, year;
QUIT;

PROC EXPORT
	DATA= oud_stratified
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/EDVisits_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;
