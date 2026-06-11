/*==============================*/
/* Project: RESPOND    			*/
/* Author: Ryan O'Dea  			*/
/* Source: RESPOND.sas (DOC)    */
/*==============================*/
/* Distribution of time spent in a correctional facility, used to      */
/* estimate how many people may not yet appear in the data (records     */
/* only land after release). PROC FREQ tabulates length-of-stay overall */
/* and crossed by race, sex, and age band; counts under 10 are then     */
/* suppressed to -1 in a DATA step.                                     */

PROC FREQ DATA=doc_frq_tmp;
	TABLES n_days / OUT=doc_length;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES FINAL_RE*n_days / OUT=doc_length_race;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES FINAL_SEX*n_days / OUT=doc_length_sex;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES age_grp_twenty*n_days / OUT=doc_length_twenty;
RUN;

PROC FREQ DATA=doc_frq_tmp;
	TABLES age_grp_five*n_days / OUT=doc_length_five;
RUN;

DATA doc_length_twenty(KEEP=n_days COUNT); SET doc_length_twenty; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_five(KEEP=n_days COUNT); SET doc_length_five; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_sex(KEEP=n_days COUNT); SET doc_length_sex; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length_race(KEEP=n_days COUNT); SET doc_length_race; IF COUNT < 10 THEN COUNT = -1; RUN;
DATA doc_length(KEEP=n_days COUNT); SET doc_length; IF COUNT < 10 THEN COUNT = -1; RUN;

PROC PRINT DATA= doc_length; TITLE "Length-of-stay distribution (suppressed counts)"; RUN;
PROC PRINT DATA= doc_length_race; TITLE "Length-of-stay by race (suppressed counts)"; RUN;

PROC EXPORT
	DATA= doc_length
	OUTFILE= "./output/IncarcerationsLength.csv"
	DBMS= csv REPLACE;
RUN;
