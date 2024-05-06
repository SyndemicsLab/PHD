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

%LET codes = ('30400', '30401', '30402', '30403', '30470', '30471', '30472', 
	'30473', '30550', '30551', '30552', '30553', 'F1110', 'F1111', 'F11120', 
	'F11121', 'F11122', 'F11129', 'F1113', 'F1114', 'F11150', 'F11151', 'F11159', 
	'F11181', 'F11182', 'F11188', 'F1119', 'F1120', 'F1121', 'F11220', 'F11221', 
	'F11222', 'F11229', 'F1123', 'F1124', 'F11250', 'F11251', 'F11259', 'F11281', 
	'F11282', 'F11288', 'F1129', 'F1193', 'F1199', '9701', '96500', '96501', 
	'96502', '96509', 'E8500', 'E8501', 'E8502', 'T400X1A', 'T400X2A', 'T400X3A', 
	'T400X4A', 'T400X1D', 'T400X2D', 'T400X3D', 'T400X4D', 'T401X1A', 'T401X2A', 
	'T401X3A', 'T401X4A', 'T401X1D', 'T401X2D', 'T401X3D', 'T401X4D', 'T402X1A', 
	'T402X2A', 'T402X3A', 'T402X4A', 'T402X1D', 'T402X2D', 'T402X3D', 'T402X4D', 
	'T403X1A', 'T403X2A', 'T403X3A', 'T403X4A', 'T403X1D', 'T403X2D', 'T403X3D', 
	'T403X4D', 'T404X1A', 'T404X2A', 'T404X3A', 'T404X4A', 'T404X1D', 'T404X2D', 
	'T404X3D', 'T404X4D', 'T40601A', 'T40601D', 'T40602A', 'T40602D', 'T40603A', 
	'T40603D', 'T40604A', 'T40604D', 'T40691A', 'T40692A', 'T40693A', 'T40694A', 
	'T40691D', 'T40692D', 'T40693D', 'T40694D', 'T40411A','T40411D','T40412A','T40412D', 
    'T40413A','T40413D','T40414A','T40414D', 'T40421A','T40421D','T40422A','T40422D', 
    'T40423A','T40423D','T40424A','T40424D', 'G2067', 'G2068', 'G2069', 
	'G2070', 'G2071', 'G2072', 'G2073', 'G2074', 'G2075', 'G2076', 'G2077', 'G2078', 
	'G2079', 'G2080', 'G2081', 'H0020', 'HZ81ZZZ', 'HZ84ZZZ', 'HZ91ZZZ', 'HZ94ZZZ', 'J0570', 
	'J0571', 'J0572', 'J0573', 'J0574', 'J0575', 'J0592', 'J2315', 'Q9991', 'Q9992', 
	'S0109', 'G2215', 'G2216', 'G1028', 'G0472', '86803', '86804', 
	'80074', '87520', '87521', '87522', '87902', '3266F', '7051', '7054', '707', 
	'7041', '7044', '7071', 'B1710', 'B182', 'B1920', 'B1711', 'B1921', 
	'00003021301', '00003021501', '61958220101', '61958180101', '61958180301', 
	'61958180401', '61958180501', '61958150101', '61958150401', '61958150501', 
	'72626260101', '00074262501', '00074262528', '00074262556', '00074262580', 
	'00074262584', '00074260028', '72626270101', '00074308228', '00074006301', 
	'00074006328', '00074309301', '00074309328', '61958240101', '61958220301', 
	'61958220401', '61958220501', '00006307402', '51167010001', '51167010003', 
	'59676022507', '59676022528', '00085031402', '3642', '9884', '11281', '11504', 
	'11514', '11594', '421', '4211', '4219', 'A382', 'B376', 'I011', 
	'I059', 'I079', 'I080', 'I083', 'I089', 'I330', 'I339', 'I358', 'I378', 'I38', 
	'T826', 'I39', '681', '6811', '6819', '682', '6821', '6822', '6823', '6824', 
	'6825', '6826', '6827', '6828', '6829', 'L030', 'L031', 'L032', 'L033', 
	'L038', 'L039', 'M000', 'M001', 'M002', 'M008', 'M009', '711', '7114', '7115', 
	'7116', '7118', '7119', 'I800', 'I801', 'I802', 'I803', 'I808', 'I809', '451', 
	'4512', '4518', '4519', '2910', '2911', '2912', '2913', '2914', '2915', 
	'2918', '29181', '29182', '29189', '2919', '30300', '30301', '30302', '30390', 
	'30391', '30392', '30500', '30501', '30502', '76071', '9800', '3575', '4255', 
	'53530', '53531', '5710', '5711', '5712', '5713', 'F101', 'F1010', 'F1012', 
	'F10120', 'F10121', 'F10129', 'F1013', 'F10130', 'F10131', 'F10132', 'F10139', 
	'F1014', 'F1015', 'F10150', 'F10151', 'F10159', 'F1018', 'F10180', 'F10181', 
	'F10182', 'F10188', 'F1019', 'F102', 'F1020', 'F1022', 'F10220', 'F10221', 
	'F10229', 'F1023', 'F10230', 'F10231', 'F10232', 'F10239', 'F1024', 'F1025', 
	'F10250', 'F10251', 'F10259', 'F1026', 'F1027', 'F1028', 'F10280', 'F10281', 
	'F10282', 'F10288', 'F1029', 'F109', 'F1090', 'F1092', 'F10920', 'F10921', 
	'F10929', 'F1093', 'F10930', 'F10931', 'F10932', 'F10939', 'F1094', 'F1095', 
	'F10950', 'F10951', 'F10959', 'F1096', 'F1097', 'F1098', 'F10980', 'F10981', 
	'F10982', 'F10988', 'F1099', 'T405X4A', '30421', '30422', '3056', '30561', 
	'30562', '3044', '30441', '30442', '9697', '96972', '96973', '96979', 'F14', 
	'F141', 'F1410', 'F1412', 'F14120', 'F14121', 'F14122', 'F14129', 'F1413', 
	'F1414', 'F1415', 'F14150', 'F14151', 'F14159', 'F1418', 'F14180', 'F14181', 
	'F14182', 'F14188', 'F1419', 'F142', 'F1420', 'F1421', 'F1422', 'F14220', 
	'F14221', 'F14222', 'F14229', 'F1423', 'F1424', 'F1425', 'F14250', 'F14251', 
	'F14259', 'F1428', 'F14280', 'F14281', 'F14282', 'F14288', 'F1429', 'F149', 
	'F1490', 'F1491', 'F1492', 'F14920', 'F14921', 'F14922', 'F14929', 'F1493', 
	'F1494', 'F1495', 'F14950', 'F14951', 'F14959', 'F1498', 'F14980', 'F14981', 
	'F14982', 'F14988', 'F1499', 'F15', 'F151', 'F1510', 'F1512', 'F15120', 
	'F15121', 'F15122', 'F15129', 'F1513', 'F1514', 'F1515', 'F15150', 'F15151', 
	'F15159', 'F1518', 'F15180', 'F15181', 'F15182', 'F15188', 'F1519', 'F152', 
	'F1520', 'F1522', 'F15220', 'F15221', 'F15222', 'F15229', 'F1523', 'F1524', 
	'F1525', 'F15250', 'F15251', 'F15259', 'F1528', 'F15280', 'F15281', 'F15282', 
	'F15288', 'F1529', 'F159', 'F1590', 'F1592', 'F15920', 'F15921', 'F15922', 
	'F15929', 'F1593', 'F1594', 'F1595', 'F15950', 'F15951', 'F15959', 'F1598', 
	'F15980', 'F15981', 'F15982', 'F15988', 'F1599', 'T405', 'T436', 'T405XIA', 
	'T43601A', 'T43602A', 'T43604A', 'T43611A', 'T43621A', 'T43624A', 'T43631A', 
	'T43634A', 'T43641A', 'T43644A', '96970', '97081', '97089', 'E8542', 'E8543', 
	'E8552', 'T43691A', 'T43694A', 'Z00129', 'Z00121', 'V202', 'V700', 'V703', 
	'V705', 'V706', 'V708', 'V709', '99381', '99391', '99381', '99391', '99381', 
    '99391', '99382', '99392');


/*==============================*/
/*  PART 2: APCD.Medical Subset	*/
/*==============================*/

DATA apcd_medical_filtered;
    SET PHDAPCD.MEDICAL (
        KEEP=ID MED_ECODE MED_ADM_DIAGNOSIS MED_AGE MED_DIS_DIAGNOSIS
             MED_ICD_PROC1-MED_ICD_PROC7 MED_ICD1-MED_ICD25 MED_PROC_CODE
             MED_FROM_DATE_year MED_INSURANCE_TYPE MED_MEDICAID MED_FROM_DATE
             MED_FROM_DATE_MONTH MED_SEX MED_FROM_DATE MED_ADM_TYPE
        WHERE=(MED_FROM_DATE_YEAR IN &years)
    );

    cnt_flags = 0;
    ARRAY vars{*} MED_ECODE MED_ADM_DIAGNOSIS MED_ICD_PROC1-MED_ICD_PROC7
        MED_ICD1-MED_ICD25 MED_DIS_DIAGNOSIS MED_PROC_CODE;

    DO i = 1 TO dim(vars);
        IF vars[i] IN &codes THEN
            cnt_flags = cnt_flags + 1;
    END;
    DROP i;

    IF substr(MED_ADM_DIAGNOSIS, 1, 4) = '4249' or
       substr(MED_ICD1, 1, 4) = '4249' or
       substr(MED_ICD2, 1, 4) = '4249' or
       substr(MED_ICD3, 1, 4) = '4249' or
       substr(MED_ICD4, 1, 4) = '4249' or
       substr(MED_ICD5, 1, 4) = '4249' or
       substr(MED_ICD6, 1, 4) = '4249' or
       substr(MED_ICD7, 1, 4) = '4249' or
       substr(MED_ICD8, 1, 4) = '4249' or
       substr(MED_ICD9, 1, 4) = '4249' or
       substr(MED_ICD10, 1, 4) = '4249' or
       substr(MED_ICD11, 1, 4) = '4249' or
       substr(MED_ICD12, 1, 4) = '4249' or
       substr(MED_ICD13, 1, 4) = '4249' or
       substr(MED_ICD14, 1, 4) = '4249' or
       substr(MED_ICD15, 1, 4) = '4249' or
       substr(MED_ICD16, 1, 4) = '4249' or
       substr(MED_ICD17, 1, 4) = '4249' or
       substr(MED_ICD18, 1, 4) = '4249' or
       substr(MED_ICD19, 1, 4) = '4249' or
       substr(MED_ICD20, 1, 4) = '4249' or
       substr(MED_ICD21, 1, 4) = '4249' or
       substr(MED_ICD22, 1, 4) = '4249' or
       substr(MED_ICD23, 1, 4) = '4249' or
       substr(MED_ICD24, 1, 4) = '4249' or
       substr(MED_ICD25, 1, 4) = '4249' or
       substr(MED_DIS_DIAGNOSIS, 1, 4) = '4249' or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ECODE) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ADM_DIAGNOSIS) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD1) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD2) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD3) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD4) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD5) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD6) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD7) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD8) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD9) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD10) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD11) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD12) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD13) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD14) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD15) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD16) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD17) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD18) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD19) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD20) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD21) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD22) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD23) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD24) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_ICD25) > 0 or
       prxmatch('/^F(20|21|22|23|24|25|28|29|30|31|32|33|34|39)/', MED_DIS_DIAGNOSIS) > 0 or
       substr(MED_ECODE, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ADM_DIAGNOSIS, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD1, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD2, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD3, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD4, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD5, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD6, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD7, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD8, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD9, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD10, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD11, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD12, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD13, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD14, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD15, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD16, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD17, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD18, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD19, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD20, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD21, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD22, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD23, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD24, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_ICD25, 1, 3) in ('295', '296', '297', '298', '300', '311') or
       substr(MED_DIS_DIAGNOSIS, 1, 3) in ('295', '296', '297', '298', '300', '311')
       THEN
            cnt_flags = cnt_flags + 1;
       
    IF cnt_flags = 0 THEN DELETE;
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
