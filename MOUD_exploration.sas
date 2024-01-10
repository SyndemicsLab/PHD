/* MOUD Dataset Exploration/Testing Script */
%let today = %sysfunc(today(), date9.);
%let formatted_date = %sysfunc(translate(&today, %str(_), %str(/)));

DATA moud;
    SET PHDSPINE.MOUD;
RUN;

PROC SORT data=moud;
    by ID DATE_START_MOUD;
RUN;

DATA treatment_length;
    SET MOUD;
    tx_length = DATE_END_MOUD - DATE_START_MOUD;
RUN;

PROC FREQ data=treatment_length;
    tables tx_length/out=freq_treatment_length(KEEP=tx_length Count);
RUN;

PROC FREQ data=treatment_length;
    tables ID/out=temp(KEEP= rename=(Count=N_Tx));
RUN;

PROC FREQ data=temp;
    tables N_Tx/out=num_treatments(keep=N_Tx Count);
RUN;

DATA mim;
    SET moud;
    BY ID;

    diff = DATE_START_MOUD - lag(DATE_END_MOUD);
    IF DATE_END_MOUD > lag(DATE_END_MOUD) then temp_flag = 1;
    else temp_flag = 0;

    IF first.ID THEN flag_mim = 0;
    else if diff < 0 AND temp_flag = 1 THEN flag_mim = 1;
    else flag_mim = 0;

    IF flag_mim = 0 THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE tx_len_out AS 
    SELECT tx_length,
           IFN(COUNT IN (1:10), -1, COUNT) AS N
    FROM freq_treatment_length;

    CREATE TABLE num_tx_out AS
    SELECT N_Tx,
    IFN(COUNT IN (1:10), -1, COUNT) AS N
    FROM num_treatments;

    CREATE TABLE mim_out AS
    SELECT TYPE_MOUD AS MOUD,
    IFN(COUNT(DISTINCT(ID)) IN (1:10), -1, COUNT(DISTINCT(ID))) AS N_ID
    FROM mim
    GROUP BY TYPE_MOUD;
QUIT;

PROC EXPORT
	DATA= tx_len_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TxLengths_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= num_tx_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/TxNumbers_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;

PROC EXPORT
	DATA= mim_out
	OUTFILE= "/sas/data/DPH/OPH/PHD/FOLDERS/SUBSTANCE_USE_CODE/RESPOND/RESPOND UPDATE/MiM_&formatted_date..csv"
	DBMS= csv REPLACE;
RUN;