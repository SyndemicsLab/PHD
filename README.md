# PHD
The Public Health Data Warehouse (PHDW) provided by the Massachusetts Department of Public Health (MDPH) and operationalized by the Office of Population Health (OPH) is an individually linked database across state government agencies with the goal to address and improve upon public health issues, with an initial focus of improving health outcomes to those impacted by the opioid epidemic.  
The PHD has three primary goals:  
1. To link data from within DPH across other state agencies to effectively create a population health database to inform policies aimed at reducing morbidity and mortality.
2. To establish a goverance structure which enables fair, secure, and appropriate access to the PHD to study and address public health priorities.
3. To coordinate multi-disciplinary teams comprised of DPH and external staff to design and conduct studies to provide actionable recommendations to address DPH priorities.  
The PHD has four structural cornerstones to support itself:  
1. *Governance:* Ensuring a sustainable inter-agency data warehouse by establishing guiding principles, organizational structure for decision making, and stakeholder access and roles.
2. *Legal:* Establishing accountability for a secure data envinronment and the collaborative framework in which data contributors and users operate.  
3. *Technical:* Provides expertise for defining the technical architecture, linkage algorithms, data configuration, and the overall analytics principles for the environment, and develops a roadmap for PHD future expansion to account for new computing environments
4. *Operations:* Oversees the funding and implementation strategy for program sustainability, and provides ongoing support for the management of daily PHD functions.
## Utilizing the PHD
The PHD has several evolving tools to aid researchings in their collaboration and exploration of the database. This involves the PHD Technical Documentation, including attribution to data set sources, brief descriptions of their available datasets, and data dictionaries for exploring column level specifics of each data set. Also included are the PHD Synthetic Datasets: [PHD Techincal Documentation](https://www.mass.gov/info-details/public-health-data-warehouse-phd-technical-documentation)
On a weekly basis, the PHD will also send out updates to variable changes or database additions.
# The PHD-PreVenT Project
The purpose of MA DPH's PHDW integration with the PreVenT model is asses disparities in race/ethnicity and age the OUD care cascade for women of reproductive age in Massachusetts
PreVenT relies primarily on these scripts:
1. *RESPOND*: Develops the Opioid Use Disorder (OUD) cohort by looking through APCD, Casemix, Death, Matris, PMP, and BSAS. This script forms the basis for other scripts when involving the 'OUD Cohort.' The second part of the script Utilizes the PHD created MOUD Spine dataset to determine how many people are starting, or in, either methadone, buprenorphine, and/or naltrexone treatments. Up until this point, the script is the same as the RESPOND model scripts. The final portion of the script differs from the RESPOND model (or, rather, is in addition to) and uses APCD medical and pharmacy records to pull HCV testing and linkage data to define the cascade of care.
2. *PHD_Infant_cascade*: Characterizes the HCV care cascade of infants born to mothers seropositive for HCV by looking through HCV, BIRTH_MOM, and BIRTH_INFANT datasets
# More Documentation
For full documentation on processes and logic within these scripts, please see either https://ryan-odea.shinyapps.io/PHD-Documentation/, which is the hosted version of https://github.com/SyndemicsLab/PHD-Documentation. 