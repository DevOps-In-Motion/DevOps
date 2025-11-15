public class QueueableCMSImport implements Database.AllowsCallouts, Queueable {
  // --------------------------------------------------------------------
  // CONFIGURATION
  // --------------------------------------------------------------------
  // Fetch 1000 records per batch to stay under 6MB limit
  private static final String BASE_ENDPOINT = 
      'https://data.cms.gov/provider-data/api/1/datastore/sql?show_db_columns=true';
  private static final Integer RECORDS_PER_BATCH = 1000;
  private static final Integer BATCH_SIZE = 200;
  
  // Instance variable to track pagination
  private Integer offset;
  private Integer totalProcessed;
  
  // Mapping of API column header → Salesforce field API name
  private static final Map<String,String> API_TO_SF = new Map<String,String>{
    'record_number' => 'AccountNumber',
    'abuse_icon' => 'Abuse_Icon__c',
    'adjusted_lpn_staffing_hours_per_resident_per_day' => 'Adjusted_LPN_Hours__c',
    'adjusted_nurse_aide_staffing_hours_per_resident_per_day' => 'Adjusted_Nurse_Aide_Hours__c',
    'adjusted_rn_staffing_hours_per_resident_per_day' => 'Adjusted_RN_Hours__c',
    'adjusted_total_nurse_staffing_hours_per_resident_per_day' => 'Adjusted_Total_Nurse_Hours__c',
    'adjusted_weekend_total_nurse_staffing_hours_per_resident_per_day' => 'Adjusted_Weekend_Total_Hours__c',
    'administrator_turnover_footnote' => 'Administrator_Turnover_Footnote__c',
    'automatic_sprinkler_systems_in_all_required_areas' => 'Automatic_Sprinkler_Systems__c',
    'average_number_of_residents_per_day' => 'Average_Number_of_Residents_per_Day__c',
    'average_number_of_residents_per_day_footnote' => 'Avg_Residents_per_Day_Footnote__c',
    'casemix_lpn_staffing_hours_per_resident_per_day' => 'Case_Mix_LPN_Hours__c',
    'casemix_nurse_aide_staffing_hours_per_resident_per_day' => 'Case_Mix_Nurse_Aide_Hours__c',
    'casemix_rn_staffing_hours_per_resident_per_day' => 'Case_Mix_RN_Hours__c',
    'casemix_total_nurse_staffing_hours_per_resident_per_day' => 'Case_Mix_Total_Nurse_Hours__c',
    'casemix_weekend_total_nurse_staffing_hours_per_resident_per_day' => 'Case_Mix_Weekend_Total_Hours__c',
    'chain_average_health_inspection_rating' => 'Chain_Avg_Health_Inspection_Rating__c',
    'chain_average_overall_5star_rating' => 'Chain_Avg_Overall_5_star_Rating__c',
    'chain_average_qm_rating' => 'Chain_Avg_QM_Rating__c',
    'chain_average_staffing_rating' => 'Chain_Avg_Staffing_Rating__c',
    'chain_id' => 'Chain_ID__c',
    'chain_name' => 'Chain_Name__c',
    'number_of_citations_from_infection_control_inspections' => 'Citations_from_Infection_Control__c',
    'citytown' => 'City_Town__c',
    'cms_certification_number_ccn' => 'CMS_Certification_Number__c',
    'continuing_care_retirement_community' => 'Continuing_Care_Retirement_Community__c',
    'countyparish' => 'County_Parish__c',
    'rating_cycle_1_number_of_complaint_health_deficiencies' => 'Cycle_1_Complaint_Health_Deficiencies__c',
    'rating_cycle_1_health_deficiency_score' => 'Cycle_1_Health_Deficiency_Score__c',
    'rating_cycle_1_health_revisit_score' => 'Cycle_1_Health_Revisit_Score__c',
    'rating_cycle_1_number_of_health_revisits' => 'Cycle_1_Number_of_Health_Revisits__c',
    'rating_cycle_1_number_of_standard_health_deficiencies' => 'Cycle_1_Standard_Health_Deficiencies__c',
    'rating_cycle_1_standard_survey_health_date' => 'Cycle_1_Standard_Survey_Health_Date__c',
    'rating_cycle_1_total_number_of_health_deficiencies' => 'Cycle_1_Total_Health_Deficiencies__c',
    'rating_cycle_1_total_health_score' => 'Cycle_1_Total_Health_Score__c',
    'rating_cycle_23_number_of_complaint_health_deficiencies' => 'Cycle_2_3_Complaint_Health_Defic__c',
    'rating_cycle_23_health_deficiency_score' => 'Cycle_2_3_Health_Deficiency_Score__c',
    'rating_cycle_23_health_revisit_score' => 'Cycle_2_3_Health_Revisit_Score__c',
    'rating_cycle_23_number_of_health_revisits' => 'Cycle_2_3_Number_of_Health_Revisits__c',
    'rating_cycle_23_total_number_of_health_deficiencies' => 'Cycle_2_3_Total_Health_Deficiencies__c',
    'rating_cycle_23_total_health_score' => 'Cycle_2_3_Total_Health_Score__c',
    'rating_cycle_2_number_of_standard_health_deficiencies' => 'Cycle_2_Standard_Health_Deficiencies__c',
    'rating_cycle_2_standard_health_survey_date' => 'Cycle_2_Standard_Health_Survey_Date__c',
    'date_first_approved_to_provide_medicare_and_medicaid_services' => 'Date_First_Approved__c',
    'geocoding_footnote' => 'Geocoding_Footnote__c',
    'health_inspection_rating' => 'Health_Inspection_Rating__c',
    'health_inspection_rating_footnote' => 'Health_Inspection_Rating_Footnote__c',
    'latitude' => 'Latitude__c',
    'legal_business_name' => 'Legal_Business_Name__c',
    'location' => 'Location__c',
    'longstay_qm_rating' => 'Long_Stay_QM_Rating__c',
    'longstay_qm_rating_footnote' => 'Long_Stay_QM_Rating_Footnote__c',
    'longitude' => 'Longitude__c',
    'number_of_administrators_who_have_left_the_nursing_home' => 'Number_of_Administrators_Left__c',
    'number_of_certified_beds' => 'Number_of_Certified_Beds__c',
    'number_of_facilities_in_chain' => 'Number_of_Facilities_in_Chain__c',
    'number_of_facility_reported_incidents' => 'Number_of_Facility_Reported_Incidents__c',
    'number_of_fines' => 'Number_of_Fines__c',
    'number_of_payment_denials' => 'Number_of_Payment_Denials__c',
    'number_of_substantiated_complaints' => 'Number_of_Substantiated_Complaints__c',
    'nursing_casemix_index' => 'Nursing_Case_Mix_Index__c',
    'nursing_casemix_index_ratio' => 'Nursing_Case_Mix_Index_Ratio__c',
    'overall_rating' => 'Overall_Rating__c',
    'overall_rating_footnote' => 'Overall_Rating_Footnote__c',
    'provider_changed_ownership_in_last_12_months' => 'Ownership_Changed_Last_12_Months__c',
    'ownership_type' => 'Ownership_Type__c',
    'physical_therapist_staffing_footnote' => 'Physical_Therapist_Staffing_Footnote__c',
    'processing_date' => 'Processing_Date__c',
    'provider_address' => 'Provider_Address__c',
    'provider_name' => 'Provider_Name__c',
    'provider_resides_in_hospital' => 'Provider_Resides_in_Hospital__c',
    'provider_ssa_county_code' => 'Provider_SSA_County_Code__c',
    'provider_type' => 'Provider_Type__c',
    'qm_rating' => 'QM_Rating__c',
    'qm_rating_footnote' => 'QM_Rating_Footnote__c',
    'most_recent_health_inspection_more_than_2_years_ago' => 'Recent_Inspection_More_Than_2_Years__c',
    'reported_licensed_staffing_hours_per_resident_per_day' => 'Reported_Licensed_Staffing_Hours__c',
    'reported_lpn_staffing_hours_per_resident_per_day' => 'Reported_LPN_Hours__c',
    'reported_nurse_aide_staffing_hours_per_resident_per_day' => 'Reported_Nurse_Aide_Hours__c',
    'reported_physical_therapist_staffing_hours_per_resident_per_day' => 'Reported_PT_Staffing_Hours__c',
    'reported_rn_staffing_hours_per_resident_per_day' => 'Reported_RN_Hours__c',
    'reported_staffing_footnote' => 'Reported_Staffing_Footnote__c',
    'reported_total_nurse_staffing_hours_per_resident_per_day' => 'Reported_Total_Nurse_Staffing_Hours__c',
    'registered_nurse_hours_per_resident_per_day_on_the_weekend' => 'RN_Hours_Weekend__c',
    'registered_nurse_turnover' => 'RN_Turnover__c',
    'registered_nurse_turnover_footnote' => 'RN_Turnover_Footnote__c',
    'shortstay_qm_rating' => 'Short_Stay_QM_Rating__c',
    'shortstay_qm_rating_footnote' => 'Short_Stay_QM_Rating_Footnote__c',
    'special_focus_status' => 'Special_Focus_Status__c',
    'staffing_rating' => 'Staffing_Rating__c',
    'staffing_rating_footnote' => 'Staffing_Rating_Footnote__c',
    'state' => 'State__c',
    'telephone_number' => 'Telephone_Number__c',
    'total_amount_of_fines_in_dollars' => 'Total_Amount_of_Fines__c',
    'total_number_of_penalties' => 'Total_Number_of_Penalties__c',
    'total_number_of_nurse_staff_hours_per_resident_per_day_on_t_4a14' => 'Total_Nurse_Hours_Weekend__c',
    'total_nursing_staff_turnover' => 'Total_Nursing_Staff_Turnover__c',
    'total_nursing_staff_turnover_footnote' => 'Total_Nursing_Staff_Turnover_Footnote__c',
    'total_weighted_health_survey_score' => 'Total_Weighted_Health_Survey_Score__c',
    'with_a_resident_and_family_council' => 'With_Resident_and_Family_Council__c',
    'zip_code' => 'ZIP_Code__c'
  };
  
  // Constructor for initial run
  public QueueableCMSImport() {
      this.offset = 0;
      this.totalProcessed = 0;
  }
  
  // Constructor for chained runs
  public QueueableCMSImport(Integer offset, Integer totalProcessed) {
      this.offset = offset;
      this.totalProcessed = totalProcessed;
  }
  
  // --------------------------------------------------------------------
  // ENTRY POINT
  // --------------------------------------------------------------------
  public void execute(QueueableContext ctx) {
      System.debug('=== Starting batch at offset: ' + offset + ' ===');
      
      // 1️⃣ Callout with pagination
      HttpResponse resp = doCallout();
      if (resp == null || resp.getStatusCode() != 200) {
          logError('Callout failed – status: ' + (resp==null?'null':resp.getStatus()));
          return;
      }
      
      // 2️⃣ Parse JSON
      List<Account> newAccounts = parseAndBuildAccounts(resp.getBody());
      System.debug('Parsed ' + newAccounts.size() + ' accounts from API');
      
      // 3️⃣ Insert in chunks
      Integer inserted = insertInChunks(newAccounts);
      totalProcessed += inserted;
      
      System.debug('Total processed so far: ' + totalProcessed);
      
      // 4️⃣ Chain next batch if we got a full batch
      if (newAccounts.size() >= RECORDS_PER_BATCH) {
          System.debug('Chaining next batch...');
          System.enqueueJob(new QueueableCMSImport(offset + RECORDS_PER_BATCH, totalProcessed));
      } else {
          System.debug('=== Import complete! Total: ' + totalProcessed + ' ===');
      }
  }
  
  // --------------------------------------------------------------------
  // CALLOUT WITH PAGINATION
  // --------------------------------------------------------------------
  private HttpResponse doCallout() {
      Http http = new Http();
      HttpRequest req = new HttpRequest();
      
      // Build SQL query with LIMIT and OFFSET
      String query = '[SELECT * FROM 0ae91eb2-22da-5fe3-9dce-9811cdd6f1a8][LIMIT ' + 
                     RECORDS_PER_BATCH + '][OFFSET ' + offset + ']';
      String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
      String endpoint = BASE_ENDPOINT + '&query=' + encodedQuery;
      
      System.debug('Endpoint: ' + endpoint);
      
      req.setEndpoint(endpoint);
      req.setMethod('GET');
      req.setHeader('Content-Type', 'application/json');
      req.setTimeout(120000);
      
      try {
          return http.send(req);
      } catch (Exception e) {
          logError('HTTP exception: ' + e.getMessage());
          return null;
      }
  }
  
  // --------------------------------------------------------------------
  // PARSE & BUILD ACCOUNTS
  // --------------------------------------------------------------------
  private List<Account> parseAndBuildAccounts(String jsonBody) {
      Set<String> existingAccountNumbers = fetchExistingAccountNumbers();
      List<Account> accountsToInsert = new List<Account>();
      
      JSONParser parser = JSON.createParser(jsonBody);
      Boolean inResultsArray = false;
      
      while (parser.nextToken() != null) {
          if (parser.getCurrentToken() == JSONToken.FIELD_NAME &&
              parser.getText() == 'results') {
              parser.nextToken();
              inResultsArray = true;
              continue;
          }
          
          if (inResultsArray && parser.getCurrentToken() == JSONToken.START_OBJECT) {
              Map<String,Object> row = new Map<String,Object>();
              while (parser.nextToken() != JSONToken.END_OBJECT) {
                  String col = parser.getText();
                  parser.nextToken();
                  
                  Object val = null;
                  JSONToken currentToken = parser.getCurrentToken();
                  if (currentToken == JSONToken.VALUE_STRING) {
                      val = parser.getText();
                  } else if (currentToken == JSONToken.VALUE_NUMBER_INT) {
                      val = parser.getIntegerValue();
                  } else if (currentToken == JSONToken.VALUE_NUMBER_FLOAT) {
                      val = parser.getDoubleValue();
                  } else if (currentToken == JSONToken.VALUE_TRUE) {
                      val = true;
                  } else if (currentToken == JSONToken.VALUE_FALSE) {
                      val = false;
                  } else if (currentToken == JSONToken.VALUE_NULL) {
                      val = null;
                  }
                  
                  row.put(col, val);
              }
              
              // Build Account
              String accountNumber = (String)row.get('record_number');
              if (String.isBlank(accountNumber) || existingAccountNumbers.contains(accountNumber)) {
                  continue;
              }
              
              Account acc = new Account();
              acc.AccountNumber = accountNumber;
              
              String providerName = (String)row.get('provider_name');
              if (String.isNotBlank(providerName)) {
                  acc.Name = providerName;
              } else {
                  acc.Name = 'Provider ' + accountNumber;
              }
              
              // Populate fields
              for (String apiHeader : row.keySet()) {
                  Object rawVal = row.get(apiHeader);
                  if (rawVal == null) continue;
                  if (apiHeader == 'record_number' || apiHeader == 'provider_name') continue;
                  
                  String sfField = API_TO_SF.containsKey(apiHeader)
                      ? API_TO_SF.get(apiHeader)
                      : convertHeaderToApiName(apiHeader);
                  
                  Schema.SObjectField sField = Account.SObjectType.getDescribe().fields.getMap().get(sfField);
                  if (sField == null) continue;
                  
                  Schema.DisplayType dType = sField.getDescribe().getType();
                  try {
                      if (dType == Schema.DisplayType.String ||
                          dType == Schema.DisplayType.TextArea ||
                          dType == Schema.DisplayType.Email ||
                          dType == Schema.DisplayType.Url ||
                          dType == Schema.DisplayType.Phone) {
                          String strVal = String.valueOf(rawVal);
                          if (strVal.length() > 255) {
                              strVal = strVal.substring(0, 255);
                          }
                          acc.put(sfField, strVal);
                      } else if (dType == Schema.DisplayType.Boolean) {
                          acc.put(sfField, parseBoolean(rawVal));
                      } else if (dType == Schema.DisplayType.Date) {
                          acc.put(sfField, parseDate(rawVal));
                      } else if (dType == Schema.DisplayType.Double ||
                                 dType == Schema.DisplayType.Currency ||
                                 dType == Schema.DisplayType.Integer ||
                                 dType == Schema.DisplayType.Percent) {
                          acc.put(sfField, parseDecimal(rawVal));
                      } else {
                          acc.put(sfField, String.valueOf(rawVal));
                      }
                  } catch (Exception ex) {
                      logError('Failed to cast field '+sfField+': '+ex.getMessage());
                  }
              }
              
              accountsToInsert.add(acc);
          }
          
          if (inResultsArray && parser.getCurrentToken() == JSONToken.END_ARRAY) {
              break;
          }
      }
      
      return accountsToInsert;
  }
  
  // --------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------
  private Set<String> fetchExistingAccountNumbers() {
      Set<String> accountNumbers = new Set<String>();
      for (Account a : [SELECT AccountNumber FROM Account WHERE AccountNumber != null]) {
          accountNumbers.add(a.AccountNumber);
      }
      return accountNumbers;
  }
  
  private static Boolean parseBoolean(Object val) {
      if (val == null) return null;
      String s = String.valueOf(val).toLowerCase();
      return (s == 'y' || s == 'yes' || s == 'true' || s == '1');
  }
  
  private static Date parseDate(Object val) {
      if (val == null) return null;
      try {
          return Date.valueOf(String.valueOf(val));
      } catch (Exception e) {
          return null;
      }
  }
  
  private static Decimal parseDecimal(Object val) {
      if (val == null) return null;
      try {
          return Decimal.valueOf(String.valueOf(val));
      } catch (Exception e) {
          return null;
      }
  }
  
  private static String convertHeaderToApiName(String header) {
      String cleaned = header.replaceAll('[^A-Za-z0-9]', '_');
      cleaned = cleaned.replaceAll('_+', '_');
      cleaned = cleaned.replaceAll('^_|_$', '');
      if (!cleaned.endsWith('__c')) cleaned += '__c';
      return cleaned;
  }
  
  // --------------------------------------------------------------------
  // DML CHUNKING - Returns number of successfully inserted records
  // --------------------------------------------------------------------
  private Integer insertInChunks(List<Account> accounts) {
      Integer total = accounts.size();
      Integer successCount = 0;
      
      if (total == 0) {
          System.debug('No new accounts to insert.');
          return 0;
      }
      
      for (Integer i = 0; i < total; i += BATCH_SIZE) {
          List<Account> slice = new List<Account>();
          for (Integer j = i; j < Math.min(i + BATCH_SIZE, total); j++) {
              slice.add(accounts[j]);
          }
          
          try {
              insert slice;
              successCount += slice.size();
              System.debug('Inserted '+slice.size()+' accounts');
          } catch (DmlException dmle) {
              for (Integer j = 0; j < slice.size(); j++) {
                  try {
                      insert slice[j];
                      successCount++;
                  } catch (DmlException innerEx) {
                      logError('Failed to insert: '+innerEx.getMessage());
                  }
              }
          }
      }
      
      return successCount;
  }
  
  private void logError(String msg) {
      System.debug(LoggingLevel.ERROR, msg);
  }
}