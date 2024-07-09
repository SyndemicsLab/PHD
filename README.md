# PHD
## About the PHD
[Pulled from PHDW Documentation](https://www.mass.gov/public-health-data-warehouse-phd)
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
# The PHD-RESPOND Project
The purpose of MA DPH's PHDW integration with the RESPOND model is the provide raw data for use in estimation of model parameters, and parameter tuning through providing outcome targets. This documentation and the RESPOND project are kept up through [Boston Medical Center's Syndemics Lab](https://www.syndemicslab.org/)
RESPOND relies primarily on four unique scripts, and uses information derived from a fifth:
1. *RESPOND*: Develops the Opioid Use Disorder (OUD) cohort by looking through APCD, Casemix, Death, Matris, PMP, and BSAS. This script forms the basis for other scripts when involving the 'OUD Cohort.' The second part of the script Utilizes the PHD created MOUD Spine dataset to determine how many people are starting, or in, either methadone, buprenorphine, or naltrexone treatments.
2. *Overdose*: Draws fatal and nonfatal overdoses from the Overdose spine.
3. *DeathCount*: Creates counts of fatal overdoses and aids in output parameter tuning of RESPOND
4. *ICDFreq*: While not a necesary script, this allows us to gather information about what ICD codes are 'hit' given their frequencies respective to our question of gathering people with OUD.
5. *Incarcerations*: Creates the count of Incarcerated people with OUD - Because incarceration status indicates non-existence elsewhere in the data, if someone is tagged as 'OUD' prior to their incarceration duration, the 'OUD' status is forwarded through incarceration period and counted as such. This has been out of date sine ~Q3 2023
# In the Repo
Within this Repo there are scripts that have been approved through the PHD by their internal Data Brief process. Output naming conventions for data are *_Ten* or *_Five* indicate age bins, *Monthly* indicates that the counting method is by month rather than year. These scripts output:
1. *RESPOND*: Age, Sex, Race stratifications *x* Monthly, Yearly *x* OUDCount, MOUDCount, MOUDStart, MOUDEnds, OUDOrigin
2. *Overdose*: Age, Sex, Race stratifications *x* Monthly, Yearly *x* Overdose
3. *DeathCount*: DeathCount_Ten; DeathCount_Five; DeathCountMonthly
4. *ICDFreq*: ICDFreq
5. *Incarcerations* (Outdated): IncarcerationsMonthly; Incarcerations_Ten; Incarcerations_Five

# Attribution and Lineage
Jianing (Jenny) Wang - Original creation of code under Chapter55 \
Ryan O'Dea - Development/Overhaul to PHD Standards \
Sarah Munroe - Development of the PreVenT branch  \
Amy Bettano - Development and day-to-day oversight of the Public Health Data Warehouse \
Devon Dunn - Massachusetts DPH PHD Liaison
