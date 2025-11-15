I need this to handle at least 20000 rows at a time. I also want to get rid of the future method (Switch to **Queueable Apex). Change the timeoout to 10 mins. Also the actual endpoint is** https://data.cms.gov/provider-data/api/1/datastore/sql?query=%5BSELECT%20%2A%20FROM%201ee2fea0-00a3-58f4-8717-89b3cd62e442%5D%5BLIMIT%2020000%5D&show_db_columns=true. This is the one that returns all the data I need. 


I need this json to create records on the account object but only if they exist. The other issue is that I changed the mapping of the data to the mapping below. Please think about all the issues before attempting an implementation. The columns below are the only cols that had their headers changed. The pattern == (original | formatted for salesforce). The remaining columns for the original dataset remain.



## formatted columns

Abuse_Icon__c|Abuse Icon
Adjusted_LPN_Hours__c|Adj LPN Hours/Resident/Day
Adjusted_Nurse_Aide_Hours__c|Adj Nurse Aide Hours/Resident/Day
Adjusted_RN_Hours__c|Adj RN Hours/Resident/Day
Adjusted_Total_Nurse_Hours__c|Adj Total Nurse Hours/Resident/Day
Adjusted_Weekend_Total_Hours__c|Adj Weekend Total Nurse Hours/Residen...
Administrator_Turnover_Footnote__c|Administrator turnover footnote
Automatic_Sprinkler_Systems__c|Auto Sprinklers (All Areas)
Average_Number_of_Residents_per_Day__c|Average Number of Residents per Day
Avg_Residents_per_Day_Footnote__c|Avg Num Residents per Day Footnote
Case_Mix_LPN_Hours__c|CaseMix LPN Hours/Resident/Day
Case_Mix_Nurse_Aide_Hours__c|CaseMix Nurse Aide Hours/Resident/Day
Case_Mix_RN_Hours__c|CaseMix RN Hours/Resident/Day
Case_Mix_Total_Nurse_Hours__c|CaseMix Total Nurse Hours/Resident/Day
Case_Mix_Weekend_Total_Hours__c|CaseMix Weekend Total Nurse Hours/Res...
Chain_Avg_Health_Inspection_Rating__c|Chain Average Health Inspection Rating
Chain_Avg_Overall_5_star_Rating__c|Chain Average Overall 5-star Rating
Chain_Avg_QM_Rating__c|Chain Average QM Rating
Chain_Avg_Staffing_Rating__c|Chain Average Staffing Rating
Chain_ID__c|Chain ID
Chain_Name__c|Chain Name
Citations_from_Infection_Control__c|Num Citations from Infection Control ...
City_Town__c|City/Town
CMS_Certification_Number__c|CMS Certification Number (CCN)
Continuing_Care_Retirement_Community__c|Continuing Care Retirement Community
County_Parish__c|County/Parish
Cycle_1_Complaint_Health_Deficiencies__c|Cycle 1 Num Complaint Health Defic
Cycle_1_Health_Deficiency_Score__c|Rating Cycle 1 Health Deficiency Score
Cycle_1_Health_Revisit_Score__c|Rating Cycle 1 Health Revisit Score
Cycle_1_Number_of_Health_Revisits__c|Rating Cycle 1 Number of Health Revisits

## sample query return from postman

[
    {
        "record_number": "1",
        "facility_name": "SPECTRUM FAMILY EYE CENTER OPTOMETRIC PA",
        "org_pac_id": "0042268971",
        "aco_id_1": "",
        "aco_nm_1": "",
        "aco_id_2": "",
        "aco_nm_2": "",
        "measure_cd": "IA_GRP_AHE_1",
        "measure_title": "Enhance Engagement of Medicaid and Other Underserved Populations",
        "invs_msr": "N",
        "attestation_value": "Y",
        "prf_rate": "",
        "patient_count": "",
        "star_value": "",
        "five_star_benchmark": "",
        "collection_type": "",
        "ccxp_ind": "Y"
    },
    {
        "record_number": "6",
        "facility_name": "MOBILE MBS INC",
        "org_pac_id": "0042357527",
        "aco_id_1": "",
        "aco_nm_1": "",
        "aco_id_2": "",
        "aco_nm_2": "",
        "measure_cd": "IA_GRP_AHE_1",
        "measure_title": "Enhance Engagement of Medicaid and Other Underserved Populations",
        "invs_msr": "N",
        "attestation_value": "Y",
        "prf_rate": "",
        "patient_count": "",
        "star_value": "",
        "five_star_benchmark": "",
        "collection_type": "",
        "ccxp_ind": "Y"
    }
]