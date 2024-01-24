/*==============================*/
/* Project: Create a small version of the APCD as a new permanent dataset to make code more efficient when querying APCD */
/* Author: Rachel Epstein/Sarah Schumacher  			*/
/* Created: 08/16/2023 			*/
/* Updated: 08/17/2023  w input from AB      */
/*==============================*/

/*==============================*/
/*      PROCESS DESCRIPTION     */
/*==============================*/

/*General description: this dataset grabs variables listed in the KEEP statement from APCD Medical,
uses an array to search each of the variables that has OUD, HCV, or MOUD codes for each of the
global / macro OUD, HCV, or MOUD codes collections (ie &ICD for the all the OUD + MOUD codes).
For all lines that contain one of the codes in one of the chosen/searched variables, cnt_flags will be >0.
The last line keeps all lines that have any of these codes. */

/*  PART 1: Create Macro variables 	*/
/*  PART 2: Create mini APCD medical 	*/
/*  PART 2: Create mini APCD pharmacy 	*/

/* ONLINE DOCUMENTATION: https://www.mass.gov/info-details/public-health-data-warehouse-phd-technical-documentation. */

/* CLEAR WORKING DIRECTORY/TEMP FILES  */
proc datasets library=WORK kill;
	run;
quit;

/*==============================*/
/*  PART 1: GLOBAL VARIABLES	*/
/*==============================*/

%LET years = (2014:2021);
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

/*==============================*/
/*     BUP Codes Creation	*/
/*==============================*/
PROC SQL;
	CREATE TABLE bupndc AS SELECT DISTINCT NDC FROM PHDPMP.PMP WHERE BUP_CAT_PMP=1;
QUIT;

PROC SQL noprint;
	SELECT quote(trim(NDC), "'") INTO :bup_codes separated by ',' FROM bupndc;
QUIT;

%LET codes = ('G0472', '86803', '86804', '80074', /*HCV AB_CPT*/
              	'87520', '87521', '87522', /*HCV RNA_CPT*/
              	'87902', '3266F', /*HCV GENO_CPT*/
              	'7051', '7054', '707', '7041', '7044', '7071', 
				'B1710', 'B182', 'B1920', 'B1711', 'B1921', /*HCV_ICD*/
				'00003021301', '00003021501', '61958220101', '61958180101', '61958180301', 
				'61958180401', '61958180501', '61958150101', '61958150401', '61958150501', 
				'72626260101', '00074262501', '00074262528', '00074262556', '00074262580', 
				'00074262584', '00074260028', '72626270101', '00074308228', '00074006301', 
				'00074006328', '00074309301', '00074309328', '61958240101', '61958220101', 
				'61958220301', '61958220301', '61958220501', '00006307402', '51167010001', 
				'51167010003', '59676022507', '59676022528', '00085031402', /*DAA Codes */
              	'30400', '30401', '30402', '30403', '30470', 
				'30471', '30472', '30473', '30550', '30551', '30552', '30553', /*ICD9*/
              	'F1110', 'F1111', 'F11120', 'F11121', 'F11122', 
				'F11129', 'F1113', 'F1114', 'F11150', 'F11151', 'F11159', 'F11181', 'F11182', 
				'F11188', 'F1119', 'F1120', 'F1121', 'F11220', 'F11221', 'F11222', 'F11229', 
				'F1123', 'F1124', 'F11250', 'F11251', 'F11259', 'F11281', 'F11282', 'F11288', 
				'F1129', /* ICD10 */
           		'9701', '96500', '96501', '96502', '96509', 'E8500', 
				'E8501', 'E8502', 'T400X1A', 'T400X2A', 'T400X3A', 'T400X4A', 'T400X1D', 
				'T400X2D', 'T400X3D', 'T400X4D', 'T401X1A', 'T401X2A', 'T401X3A', 'T401X4A', 
				'T401X1D', 'T401X2D', 'T401X3D', 'T401X4D', 'T402X1A', 'T402X2A', 'T402X3A', 
				'T402X4A', 'T402X1D', 'T402X2D', 'T402X3D', 'T402X4D', 'T403X1A', 'T403X2A', 
				'T403X3A', 'T403X4A', 'T403X1D', 'T403X2D', 'T403X3D', 'T403X4D', 'T404X1A', 
				'T404X2A', 'T404X3A', 'T404X4A', 'T404X1D', 'T404X2D', 'T404X3D', 'T404X4D', 
				'T40601A', 'T40601D', 'T40602A', 'T40602D', 'T40603A', 'T40603D', 'T40604A', 
				'T40604D', 'T40691A', 'T40692A', 'T40693A', 'T40694A', 'T40691D', 'T40692D', 
				'T40693D', 'T40694D', /* Overdose Codes */
              	'G2067', 'G2068', 'G2069', 'J0592', 'G2070', 'G2073',
				'G2071', 'G2072', 'G2074', 'G2075', 'G2076', 'G2077', 'G2078', 'G2079', 
				'G2080', 'Q9991', 'Q9992', 'H0020', 'HZ91ZZZ', 'HZ81ZZZ', 'J0570', 'J0571', 
				'J0572', 'J0573', 'J0574', 'J0575', 'J0592', 'S0109', 'H0020', 'HZ94ZZZ', 'HZ84ZZZ',
				/* MOUD */ '65757030001', '63459030042', 'J2315', 
				'54868557400', '54569913900', '54569672000', '50090307600', '50090286600', 
				'16729008101', '16729008110', '52152010502', '52152010530', '53217026130', 
				'68084029111', '68084029121', '52152010504', '42291063230', '63629104701', 
				'63629104601', '68115068030', '65694010010', '65694010003', '00904703604', 
				'43063059115', '76519116005', '68094085359', '68094085362', '00185003930', 
				'00185003901', '00406117001', '00406117003', '47335032688', '47335032683', 
				'51224020650', '51224020630', '00555090201', '00555090202', '50436010501', 
				'00056001170', '00056001130', '00056007950', '00056001122', '51285027502', 
				'51285027501', '00056008050', '65757030001', '63459030042' /*Nalt Codes*/);

/*==============================*/
/*  PART 2: APCD.Medical Subset	*/
/*==============================*/

DATA apcd_medical_filtered;
	SET PHDAPCD.MEDICAL (KEEP=ID MED_ECODE MED_ADM_DIAGNOSIS MED_AGE 
		MED_DIS_DIAGNOSIS MED_ICD_PROC1-MED_ICD_PROC7 MED_ICD1-MED_ICD25 
		MED_PROC_CODE MED_FROM_DATE_year MED_INSURANCE_TYPE MED_MEDICAID 
		MED_FROM_DATE_MONTH MED_SEX MED_FROM_DATE MED_ADM_TYPE
		
		WHERE=(MED_FROM_DATE_YEAR IN &years));
		
	cnt_flags=0;
	ARRAY vars{*} MED_ECODE MED_ADM_DIAGNOSIS MED_ICD_PROC1-MED_ICD_PROC7 
		MED_ICD1-MED_ICD25 MED_DIS_DIAGNOSIS MED_PROC_CODE;

	DO i=1 TO dim(vars);

		IF vars[i] IN &codes THEN
			cnt_flags=cnt_flags + 1;

		
	END;
	DROP=i;

	IF cnt_flags=0 THEN
		DELETE;
RUN;

/*==============================*/
/*   PART 3: APCD.Pharm Subset	*/
/*==============================*/

DATA apcd_pharm_filtered;
	SET PHDAPCD.PHARMACY (KEEP=PHARM_NDC PHARM_AGE PHARM_ICD ID PHARM_FILL_DATE 
		PHARM_FILL_DATE_MONTH PHARM_FILL_DATE_YEAR PHARM_ICD PHARM_FORMULARY 
		PHARM_INSURANCE_TYPE PHARM_MEDICAID PHARM_PRESCRIBER_ZIP PHARM_PRESCRIBER_NPI 
		PHARM_PRESCRIBER_LINKID PHARM_REFILL RES_ZIP_APCD_PHARM
		
		WHERE=(PHARM_FILL_DATE_YEAR IN &years));
		
	cnt_flags=0;
	ARRAY vars{*} PHARM_NDC PHARM_ICD;

	DO i=1 TO dim(vars);

		IF vars[i] IN &codes THEN
			cnt_flags=cnt_flags +1;

		IF vars[i] IN (&bup_codes) THEN
			cnt_flags=cnt_flags + 1;
	END;
	DROP=i;

	IF cnt_flags=0 THEN
		DELETE;
RUN;

/*NEED to change name/location of the dataset being created to whatever is needed for permanent dataset*/
