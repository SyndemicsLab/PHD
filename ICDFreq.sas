/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/ 
/* Created: 01/18/2023 			*/
/* Updated: 01/19/2023 			*/
/*==============================*/
%LET year = 2020;
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

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

/*=========APCD DATA=============*/
DATA apcd_wide (DROP= DROP= MED_FROM_DATE_YEAR);
    SET PHDAPCD.MEDICAL (KEEP= ID MED_ECODE MED_ADM_DIAGNOSIS
                                MED_ICD_PROC1-MED_ICD_PROC7
                                MED_ICD1-MED_ICD25
                                MED_FROM_DATE_YEAR
                                MED_DIS_DIAGNOSIS
                        WHERE=(MED_FROM_DATE_YEAR = &year));
RUN;

PROC SURVEYSELECT 
    DATA = apcd_wide
    OUT = samp_apcd_wide
    SAMPRATE = .2;
RUN;

/*======CASEMIX DATA==========*/
/* ED */
DATA ed_wide (DROP= ED_ADMIT_YEAR);
    SET PHDCM.ED (KEEP= ID ED_DIAG1 ED_PRINCIPLE_ECODE ED_ADMIT_YEAR ED_ID
                  WHERE=(ED_ADMIT_YEAR = &year));
RUN;

DATA ed_diag_wide;
    SET PHDCM.ED_DIAG (KEEP= ED_ID ED_DIAG);
RUN;

DATA ed_proc_wide;
    SET PHDCM.ED_PROC (KEEP= ED_ID ED_PROC);
RUN;

/* CASEMIX ED MERGE */
PROC SQL;
    CREATE TABLE ed_wide AS
    SELECT * FROM ed_wide
    LEFT JOIN ed_diag_wide ON ed_wide.ED_ID = ed_diag_wide.ED_ID
    LEFT JOIN ed_proc_wide ON ed_diag_wide.ED_ID = ed_proc_wide.ED_ID;
QUIT;

/* HD */
DATA hd_raw_wide(DROP=HD_ADMIT_YEAR);
    SET PHDCM.HD (KEEP= ID HD_DIAG1 HD_PROC1 HD_ADMIT_YEAR HD_ID
                    WHERE=(HD_ADMIT_YEAR = &year));
RUN;

/* HD DIAG */
DATA hd_diag_wide;
    SET PHDCM.HD_DIAG (KEEP= HD_ID HD_DIAG);
RUN;

/* HD MERGE */
PROC SQL;
    CREATE TABLE hd_wide AS
    SELECT * 
    FROM hd_raw_wide
    LEFT JOIN hd_diag_wide ON hd_raw_wide.HD_ID = hd_diag_wide.HD_ID;
QUIT;

/* OO */
DATA oo_wide;
    SET PHDCM.OO (KEEP= ID OO_DIAG1-OO_DIAG16 OO_PROC1-OO_PROC4 OO_ADMIT_YEAR
                    WHERE=(OO_ADMIT_YEAR = &year));
RUN;

/*FULL CASEMIX MERGE */
PROC SQL;
    CREATE TABLE cm_wide AS
    SELECT * FROM ed_wide
    FULL JOIN hd_wide ON ed_wide.ID = hd_wide.ID
    FULL JOIN oo_wide ON hd_wide.ID = oo_wide.ID;
QUIT;

PROC SURVEYSELECT 
    DATA = cm_wide
    OUT = samp_cm_wide
    SAMPRATE = .2;
RUN;

/* CASEMIX FREQUENCY */
PROC TRANSPOSE DATA=samp_cm_wide OUT=casemix(RENAME=(COL1= ICD_Code)) LET;
	BY NOTSORTED ID;
	VAR _all_;
RUN;

PROC FREQ DATA = casemix(WHERE=(ICD_Code IN &ICD));
	TABLES ICD_Code/OUT=casemix_freq(KEEP=ICD_Code Count);
RUN;

/* APCD FREQUENCY*/
PROC TRANSPOSE DATA=samp_apcd_wide OUT=apcd(RENAME=(COL1=ICD_Code)) LET;
	BY NOTSORTED ID;
	VAR _all_;
RUN;

PROC FREQ DATA = apcd(WHERE=(ICD_Code IN &ICD));
	TABLES ICD_Code/OUT=apcd_freq(KEEP=ICD_Code Count);
RUN;

/* MERGE FREQ TABLES */
DATA freq;
	SET apcd_freq casemix_freq;
RUN;

PROC SQL;
	CREATE TABLE icd_freq AS
	SELECT ICD_Code, 
	IFN(SUM(Count) < 10 AND SUM(Count) > 0, -1, SUM(Count)) AS Freq
	FROM freq
	GROUP BY ICD_Code;
QUIT;

/* FREQUENCY TABLE PRINT */
PROC EXPORT
	DATA= icd_freq
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/ICDFreq_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;