public with sharing class CMSNursingHomeAPIService {
    
  // Fetch data for a specific nursing home by CMS Certification Number
  @future(callout=true)
  public static void fetchNursingHomeData(String ccnNumber, Id accountId) {
      try {
          // CMS API endpoint with filter for specific CCN
          String queryEndpoint = 'https://data.cms.gov/provider-data/api/1/datastore/sql?query=%5BSELECT%20%2A%20FROM%201ee2fea0-00a3-58f4-8717-89b3cd62e442%5D%5BLIMIT%2020000%5D&show_db_columns=true';
          String endpoint = 'https://data.cms.gov/provider-data/api/1/datastore/query/4pq5-n9py/0?conditions[0][property]=cms_certification_number_ccn&conditions[0][value]=' + ccnNumber;
          
          Http http = new Http();
          HttpRequest request = new HttpRequest();
          request.setEndpoint(endpoint);
          request.setMethod('GET');
          request.setHeader('Content-Type', 'application/json');
          request.setTimeout(120000); // 2 minute timeout

          HttpResponse response = http.send(request);
          
          if (response.getStatusCode() == 200) {
              Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
              List<Object> results = (List<Object>) responseBody.get('results');
              
              if (results != null && !results.isEmpty()) {
                  Map<String, Object> data = (Map<String, Object>) results[0];
                  
                  // Update Account record with nursing home data
                  Account acc = new Account(Id = accountId);
                  populateAccountFields(acc, data);
                  
                  update acc;
                  System.debug('Successfully updated Account with CMS data');
              } else {
                  System.debug('No nursing home found with CCN: ' + ccnNumber);
              }
          } else {
              System.debug('Error in API call: ' + response.getStatus() + ' - ' + response.getBody());
          }
      } catch (Exception e) {
          System.debug('Exception during API call: ' + e.getMessage() + '\n' + e.getStackTraceString());
      }
  }
  
  // Batch fetch all nursing homes - only creates records that don't exist
  @future(callout=true)
  public static void fetchAllNursingHomes(Integer offset) {
      try {
          // Fetch data from CMS API with pagination
          String endpoint = 'https://data.cms.gov/provider-data/api/1/datastore/query/4pq5-n9py/0?limit=100&offset=' + offset;
          
          Http http = new Http();
          HttpRequest request = new HttpRequest();
          request.setEndpoint(endpoint);
          request.setMethod('GET');
          request.setHeader('Content-Type', 'application/json');
          request.setTimeout(120000);

          HttpResponse response = http.send(request);
          
          if (response.getStatusCode() == 200) {
              Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
              List<Object> results = (List<Object>) responseBody.get('results');
              
              if (results == null || results.isEmpty()) {
                  System.debug('No more records to fetch at offset: ' + offset);
                  return;
              }
              
              // Extract all CCN numbers from the API response
              Set<String> ccnNumbers = new Set<String>();
              Map<String, Map<String, Object>> ccnToDataMap = new Map<String, Map<String, Object>>();
              
              for (Object result : results) {
                  Map<String, Object> data = (Map<String, Object>) result;
                  String ccn = getString(data, 'cms_certification_number_ccn');
                  if (ccn != null) {
                      ccnNumbers.add(ccn);
                      ccnToDataMap.put(ccn, data);
                  }
              }
              
              // Check which CCNs already exist in Salesforce
              Set<String> existingCCNs = new Set<String>();
              for (Account existingAcc : [SELECT CMS_Certification_Number__c 
                                          FROM Account 
                                          WHERE CMS_Certification_Number__c IN :ccnNumbers]) {
                  existingCCNs.add(existingAcc.CMS_Certification_Number__c);
              }
              
              // Create list of new accounts to insert
              List<Account> accountsToInsert = new List<Account>();
              
              for (String ccn : ccnNumbers) {
                  // Only create if it doesn't exist
                  if (!existingCCNs.contains(ccn)) {
                      Map<String, Object> data = ccnToDataMap.get(ccn);
                      Account acc = new Account();
                      populateAccountFields(acc, data);
                      accountsToInsert.add(acc);
                  }
              }
              
              if (!accountsToInsert.isEmpty()) {
                  insert accountsToInsert;
                  System.debug('Successfully inserted ' + accountsToInsert.size() + ' new nursing homes');
              } else {
                  System.debug('All ' + ccnNumbers.size() + ' records already exist in Salesforce');
              }
              
          } else {
              System.debug('Error in API call: ' + response.getStatus() + ' - ' + response.getBody());
          }
      } catch (Exception e) {
          System.debug('Exception during batch fetch: ' + e.getMessage() + '\n' + e.getStackTraceString());
      }
  }
  
  // Wrapper method to start the batch process
  public static void startBatchImport() {
      // Start with offset 0
      fetchAllNursingHomes(0);
  }
  
  // Method to continue importing with next offset (call manually for next batch)
  public static void continueImport(Integer currentOffset) {
      Integer nextOffset = currentOffset + 100;
      fetchAllNursingHomes(nextOffset);
  }
  
  // Helper method to populate all account fields from API data
  private static void populateAccountFields(Account acc, Map<String, Object> data) {
      // Basic Information
      acc.CMS_Certification_Number__c = getString(data, 'cms_certification_number_ccn');
      acc.Name = getString(data, 'provider_name');
      acc.Provider_Address__c = getString(data, 'provider_address');
      acc.City_Town__c = getString(data, 'city_town');
      acc.State__c = getString(data, 'state');
      acc.ZIP_Code__c = getString(data, 'zip_code');
      acc.Phone = getString(data, 'telephone_number');
      acc.County_Parish__c = getString(data, 'county_parish');
      acc.Ownership_Type__c = getString(data, 'ownership_type');
      acc.Provider_SSA_County_Code__c = getString(data, 'provider_ssa_county_code');
      
      // Facility Details
      acc.Number_of_Certified_Beds__c = getDecimal(data, 'number_of_certified_beds');
      acc.Average_Number_of_Residents_per_Day__c = getDecimal(data, 'average_number_of_residents_per_day');
      acc.Avg_Residents_per_Day_Footnote__c = getString(data, 'average_number_of_residents_per_day_footnote');
      acc.Provider_Type__c = getString(data, 'provider_type');
      acc.Legal_Business_Name__c = getString(data, 'legal_business_name');
      acc.Date_First_Approved__c = getDate(data, 'date_first_approved_to_provide_medicare_and_medicaid_services');
      
      // Chain Information
      acc.Chain_Name__c = getString(data, 'chain_name');
      acc.Chain_ID__c = getString(data, 'chain_id');
      acc.Number_of_Facilities_in_Chain__c = getDecimal(data, 'number_of_facilities_in_chain');
      acc.Chain_Avg_Overall_5_star_Rating__c = getDecimal(data, 'chain_average_overall_5_star_rating');
      acc.Chain_Avg_Health_Inspection_Rating__c = getDecimal(data, 'chain_average_health_inspection_rating');
      acc.Chain_Avg_Staffing_Rating__c = getDecimal(data, 'chain_average_staffing_rating');
      acc.Chain_Avg_QM_Rating__c = getDecimal(data, 'chain_average_qm_rating');
      
      // Ratings
      acc.Overall_Rating__c = getDecimal(data, 'overall_rating');
      acc.Overall_Rating_Footnote__c = getString(data, 'overall_rating_footnote');
      acc.Health_Inspection_Rating__c = getDecimal(data, 'health_inspection_rating');
      acc.Health_Inspection_Rating_Footnote__c = getString(data, 'health_inspection_rating_footnote');
      acc.QM_Rating__c = getDecimal(data, 'qm_rating');
      acc.QM_Rating_Footnote__c = getString(data, 'qm_rating_footnote');
      acc.Long_Stay_QM_Rating__c = getDecimal(data, 'long_stay_qm_rating');
      acc.Long_Stay_QM_Rating_Footnote__c = getString(data, 'long_stay_qm_rating_footnote');
      acc.Short_Stay_QM_Rating__c = getDecimal(data, 'short_stay_qm_rating');
      acc.Short_Stay_QM_Rating_Footnote__c = getString(data, 'short_stay_qm_rating_footnote');
      acc.Staffing_Rating__c = getDecimal(data, 'staffing_rating');
      acc.Staffing_Rating_Footnote__c = getString(data, 'staffing_rating_footnote');
      
      // Staffing Hours - Reported
      acc.Reported_Staffing_Footnote__c = getString(data, 'reported_staffing_footnote');
      acc.Reported_Nurse_Aide_Hours__c = getDecimal(data, 'reported_nurse_aide_staffing_hours_per_resident_per_day');
      acc.Reported_LPN_Hours__c = getDecimal(data, 'reported_lpn_staffing_hours_per_resident_per_day');
      acc.Reported_RN_Hours__c = getDecimal(data, 'reported_rn_staffing_hours_per_resident_per_day');
      acc.Reported_Licensed_Staffing_Hours__c = getDecimal(data, 'reported_licensed_staffing_hours_per_resident_per_day');
      acc.Reported_Total_Nurse_Staffing_Hours__c = getDecimal(data, 'reported_total_nurse_staffing_hours_per_resident_per_day');
      acc.Total_Nurse_Hours_Weekend__c = getDecimal(data, 'total_number_of_nurse_staff_hours_per_resident_per_day_on_the_weekend');
      acc.RN_Hours_Weekend__c = getDecimal(data, 'registered_nurse_hours_per_resident_per_day_on_the_weekend');
      acc.Reported_PT_Staffing_Hours__c = getDecimal(data, 'reported_physical_therapist_staffing_hours_per_resident_per_day');
      acc.Physical_Therapist_Staffing_Footnote__c = getString(data, 'physical_therapist_staffing_footnote');
      
      // Turnover
      acc.Total_Nursing_Staff_Turnover__c = getDecimal(data, 'total_nursing_staff_turnover');
      acc.Total_Nursing_Staff_Turnover_Footnote__c = getString(data, 'total_nursing_staff_turnover_footnote');
      acc.RN_Turnover__c = getDecimal(data, 'registered_nurse_turnover');
      acc.RN_Turnover_Footnote__c = getString(data, 'registered_nurse_turnover_footnote');
      acc.Number_of_Administrators_Left__c = getDecimal(data, 'number_of_administrators_who_have_left_the_nursing_home');
      acc.Administrator_Turnover_Footnote__c = getString(data, 'administrator_turnover_footnote');
      
      // Case Mix
      acc.Nursing_Case_Mix_Index__c = getDecimal(data, 'nursing_case_mix_index');
      acc.Nursing_Case_Mix_Index_Ratio__c = getDecimal(data, 'nursing_case_mix_index_ratio');
      acc.Case_Mix_Nurse_Aide_Hours__c = getDecimal(data, 'case_mix_nurse_aide_staffing_hours_per_resident_per_day');
      acc.Case_Mix_LPN_Hours__c = getDecimal(data, 'case_mix_lpn_staffing_hours_per_resident_per_day');
      acc.Case_Mix_RN_Hours__c = getDecimal(data, 'case_mix_rn_staffing_hours_per_resident_per_day');
      acc.Case_Mix_Total_Nurse_Hours__c = getDecimal(data, 'case_mix_total_nurse_staffing_hours_per_resident_per_day');
      acc.Case_Mix_Weekend_Total_Hours__c = getDecimal(data, 'case_mix_weekend_total_nurse_staffing_hours_per_resident_per_day');
      
      // Adjusted
      acc.Adjusted_Nurse_Aide_Hours__c = getDecimal(data, 'adjusted_nurse_aide_staffing_hours_per_resident_per_day');
      acc.Adjusted_LPN_Hours__c = getDecimal(data, 'adjusted_lpn_staffing_hours_per_resident_per_day');
      acc.Adjusted_RN_Hours__c = getDecimal(data, 'adjusted_rn_staffing_hours_per_resident_per_day');
      acc.Adjusted_Total_Nurse_Hours__c = getDecimal(data, 'adjusted_total_nurse_staffing_hours_per_resident_per_day');
      acc.Adjusted_Weekend_Total_Hours__c = getDecimal(data, 'adjusted_weekend_total_nurse_staffing_hours_per_resident_per_day');
      
      // Health Inspection Cycles
      acc.Cycle_1_Standard_Survey_Health_Date__c = getDate(data, 'rating_cycle_1_standard_survey_health_date');
      acc.Cycle_1_Total_Health_Deficiencies__c = getDecimal(data, 'rating_cycle_1_total_number_of_health_deficiencies');
      acc.Cycle_1_Standard_Health_Deficiencies__c = getDecimal(data, 'rating_cycle_1_number_of_standard_health_deficiencies');
      acc.Cycle_1_Complaint_Health_Deficiencies__c = getDecimal(data, 'rating_cycle_1_number_of_complaint_health_deficiencies');
      acc.Cycle_1_Health_Deficiency_Score__c = getDecimal(data, 'rating_cycle_1_health_deficiency_score');
      acc.Cycle_1_Number_of_Health_Revisits__c = getDecimal(data, 'rating_cycle_1_number_of_health_revisits');
      acc.Cycle_1_Health_Revisit_Score__c = getDecimal(data, 'rating_cycle_1_health_revisit_score');
      acc.Cycle_1_Total_Health_Score__c = getDecimal(data, 'rating_cycle_1_total_health_score');
      
      acc.Cycle_2_Standard_Health_Survey_Date__c = getDate(data, 'rating_cycle_2_standard_health_survey_date');
      acc.Cycle_2_3_Total_Health_Deficiencies__c = getDecimal(data, 'rating_cycle_2_3_total_number_of_health_deficiencies');
      acc.Cycle_2_Standard_Health_Deficiencies__c = getDecimal(data, 'rating_cycle_2_number_of_standard_health_deficiencies');
      acc.Cycle_2_3_Complaint_Health_Defic__c = getDecimal(data, 'rating_cycle_2_3_number_of_complaint_health_deficiencies');
      acc.Cycle_2_3_Health_Deficiency_Score__c = getDecimal(data, 'rating_cycle_2_3_health_deficiency_score');
      acc.Cycle_2_3_Number_of_Health_Revisits__c = getDecimal(data, 'rating_cycle_2_3_number_of_health_revisits');
      acc.Cycle_2_3_Health_Revisit_Score__c = getDecimal(data, 'rating_cycle_2_3_health_revisit_score');
      acc.Cycle_2_3_Total_Health_Score__c = getDecimal(data, 'rating_cycle_2_3_total_health_score');
      acc.Total_Weighted_Health_Survey_Score__c = getDecimal(data, 'total_weighted_health_survey_score');
      
      // Compliance
      acc.Number_of_Facility_Reported_Incidents__c = getDecimal(data, 'number_of_facility_reported_incidents');
      acc.Number_of_Substantiated_Complaints__c = getDecimal(data, 'number_of_substantiated_complaints');
      acc.Citations_from_Infection_Control__c = getDecimal(data, 'number_of_citations_from_infection_control_inspections');
      acc.Number_of_Fines__c = getDecimal(data, 'number_of_fines');
      acc.Total_Amount_of_Fines__c = getDecimal(data, 'total_amount_of_fines_in_dollars');
      acc.Number_of_Payment_Denials__c = getDecimal(data, 'number_of_payment_denials');
      acc.Total_Number_of_Penalties__c = getDecimal(data, 'total_number_of_penalties');
      
      // Location
      acc.Latitude__c = getDecimal(data, 'latitude');
      acc.Longitude__c = getDecimal(data, 'longitude');
      acc.Geocoding_Footnote__c = getString(data, 'geocoding_footnote');
      
      // Boolean/Status fields
      acc.Provider_Resides_in_Hospital__c = getBoolean(data, 'provider_resides_in_hospital');
      acc.Continuing_Care_Retirement_Community__c = getBoolean(data, 'continuing_care_retirement_community');
      acc.Special_Focus_Status__c = getString(data, 'special_focus_status');
      acc.Abuse_Icon__c = getString(data, 'abuse_icon');
      acc.Recent_Inspection_More_Than_2_Years__c = getBoolean(data, 'most_recent_health_inspection_more_than_2_years_ago');
      acc.Ownership_Changed_Last_12_Months__c = getBoolean(data, 'provider_changed_ownership_in_last_12_months');
      acc.With_Resident_and_Family_Council__c = getBoolean(data, 'with_a_resident_and_family_council');
      acc.Automatic_Sprinkler_Systems__c = getBoolean(data, 'automatic_sprinkler_systems_in_all_required_areas');
      
      // Processing Date
      acc.Processing_Date__c = getDate(data, 'processing_date');
  }
  
  // Helper methods
  private static String getString(Map<String, Object> data, String key) {
      Object value = data.get(key);
      return value != null ? String.valueOf(value) : null;
  }
  
  private static Decimal getDecimal(Map<String, Object> data, String key) {
      Object value = data.get(key);
      if (value == null) return null;
      try {
          return Decimal.valueOf(String.valueOf(value));
      } catch (Exception e) {
          return null;
      }
  }
  
  private static Boolean getBoolean(Map<String, Object> data, String key) {
      Object value = data.get(key);
      if (value == null) return false;
      String strValue = String.valueOf(value).toLowerCase();
      return strValue == 'y' || strValue == 'yes' || strValue == 'true' || strValue == '1';
  }
  
  private static Date getDate(Map<String, Object> data, String key) {
      Object value = data.get(key);
      if (value == null) return null;
      try {
          return Date.valueOf(String.valueOf(value));
      } catch (Exception e) {
          return null;
      }
  }
}