public class QueueableCMSImport implements Database.AllowsCallouts, Queueable {

  // --------------------------------------------------------------------
  // CONFIGURATION
  // --------------------------------------------------------------------
  // Endpoint that returns exactly 20 000 rows
  private static final String ENDPOINT =
      'https://data.cms.gov/provider-data/api/1/datastore/sql?' +
      'query=%5BSELECT%20%2A%20FROM%200ae91eb2-22da-5fe3-9dce-9811cdd6f1a8%5D%5BLIMIT%2020000%5D&show_db_columns=true';

  // Max number of records we insert per DML statement (Governor limit = 200)
  private static final Integer BATCH_SIZE = 200;

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
  // --------------------------------------------------------------------
  // ENTRY POINT
  // --------------------------------------------------------------------
  public void execute(QueueableContext ctx) {
      // 1️⃣ Callout
      HttpResponse resp = doCallout();
      if (resp == null || resp.getStatusCode() != 200) {
          logError('Callout failed – status: ' + (resp==null?'null':resp.getStatus()));
          return;
      }

      // 2️⃣ Parse JSON streaming (avoid full deserialization)
      List<Account> newAccounts = parseAndBuildAccounts(resp.getBody());

      // 3️⃣ Insert in safe chunks
      insertInChunks(newAccounts);
  }

  // --------------------------------------------------------------------
  // CALLOUT
  // --------------------------------------------------------------------
  private HttpResponse doCallout() {
      Http http = new Http();
      HttpRequest req = new HttpRequest();
      req.setEndpoint(ENDPOINT);
      req.setMethod('GET');
      req.setHeader('Content-Type', 'application/json');
      // Salesforce max timeout is 120 seconds
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
      // 1️⃣ Get existing Account Numbers once (set for fast lookup)
      Set<String> existingAccountNumbers = fetchExistingAccountNumbers();

      // 2️⃣ Stream‑parse the JSON
      List<Account> accountsToInsert = new List<Account>();
      JSONParser parser = JSON.createParser(jsonBody);

      // Expected shape:
      // { "results": [ { "column1": "...", "column2": "...", ... }, ... ] }
      Boolean inResultsArray = false;
      while (parser.nextToken() != null) {
          if (parser.getCurrentToken() == JSONToken.FIELD_NAME &&
              parser.getText() == 'results') {
              parser.nextToken(); // move to START_ARRAY
              inResultsArray = true;
              continue;
          }

          if (inResultsArray && parser.getCurrentToken() == JSONToken.START_OBJECT) {
              // Parse a single row into a map
              Map<String,Object> row = new Map<String,Object>();
              while (parser.nextToken() != JSONToken.END_OBJECT) {
                  String col = parser.getText();          // field name
                  parser.nextToken();                     // move to value
                  
                  // Handle different token types
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

              // -------------------------------------------------
              // Build Account if Account Number not already present
              // -------------------------------------------------
              String accountNumber = (String)row.get('record_number');
              if (String.isBlank(accountNumber) || existingAccountNumbers.contains(accountNumber)) {
                  // Skip – either no Account Number or already exists
                  continue;
              }

              Account acc = new Account();
              acc.AccountNumber = accountNumber; // always set this first
              
              // Also grab provider name for the Name field (required)
              String providerName = (String)row.get('provider_name');
              if (String.isNotBlank(providerName)) {
                  acc.Name = providerName;
              } else {
                  acc.Name = 'Provider ' + accountNumber; // fallback name
              }

              // Populate every field using the mapping table
              for (String apiHeader : row.keySet()) {
                  Object rawVal = row.get(apiHeader);
                  if (rawVal == null) continue;
                  
                  // Skip record_number and provider_name since we already handled them
                  if (apiHeader == 'record_number' || apiHeader == 'provider_name') continue;

                  // Resolve the SF field name
                  String sfField = API_TO_SF.containsKey(apiHeader)
                      ? API_TO_SF.get(apiHeader)
                      : convertHeaderToApiName(apiHeader); // fallback

                  // Cast based on field type (simple heuristic)
                  Schema.SObjectField sField = Account.SObjectType.getDescribe().fields.getMap().get(sfField);
                  if (sField == null) continue; // unknown field – ignore

                  Schema.DisplayType dType = sField.getDescribe().getType();
                  try {
                      if (dType == Schema.DisplayType.String ||
                          dType == Schema.DisplayType.TextArea ||
                          dType == Schema.DisplayType.Email ||
                          dType == Schema.DisplayType.Url ||
                          dType == Schema.DisplayType.Phone) {
                          acc.put(sfField, String.valueOf(rawVal));
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
                          // fallback to string
                          acc.put(sfField, String.valueOf(rawVal));
                      }
                  } catch (Exception ex) {
                      // Log but keep going – a bad value on one field shouldn't stop the row
                      logError('Failed to cast field '+sfField+' value '+rawVal+': '+ex.getMessage());
                  }
              }

              accountsToInsert.add(acc);
          }

          // End of results array?
          if (inResultsArray && parser.getCurrentToken() == JSONToken.END_ARRAY) {
              break;
          }
      }

      return accountsToInsert;
  }

  // --------------------------------------------------------------------
  // HELPERS – EXISTING ACCOUNT NUMBERS
  // --------------------------------------------------------------------
  private Set<String> fetchExistingAccountNumbers() {
      Set<String> accountNumbers = new Set<String>();
      for (Account a : [
          SELECT AccountNumber
          FROM Account
          WHERE AccountNumber != null
      ]) {
          accountNumbers.add(a.AccountNumber);
      }
      return accountNumbers;
  }

  // --------------------------------------------------------------------
  // HELPERS – TYPE CONVERSIONS
  // --------------------------------------------------------------------
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

  // Fallback conversion: replace spaces & slashes with underscores, strip extra chars
  private static String convertHeaderToApiName(String header) {
      String cleaned = header.replaceAll('[^A-Za-z0-9]', '_');
      // Collapse multiple underscores
      cleaned = cleaned.replaceAll('_+', '_');
      // Trim leading/trailing underscores
      cleaned = cleaned.replaceAll('^_|_$', '');
      // Ensure it ends with __c if it looks like a custom field (most of yours do)
      if (!cleaned.endsWith('__c')) cleaned += '__c';
      return cleaned;
  }

  // --------------------------------------------------------------------
  // DML CHUNKING
  // --------------------------------------------------------------------
  private void insertInChunks(List<Account> accounts) {
      Integer total = accounts.size();
      if (total == 0) {
          System.debug('No new accounts to insert.');
          return;
      }

      for (Integer i = 0; i < total; i += BATCH_SIZE) {
          List<Account> slice = new List<Account>();
          for (Integer j = i; j < Math.min(i + BATCH_SIZE, total); j++) {
              slice.add(accounts[j]);
          }
          try {
              insert slice;
              System.debug('Inserted '+slice.size()+' accounts (records '+(i+1)+'–'+(i+slice.size())+')');
          } catch (DmlException dmle) {
              // Log each failed row individually for later re‑try
              for (Integer j = 0; j < slice.size(); j++) {
                  try {
                      insert slice[j];
                  } catch (DmlException innerEx) {
                      logError('Failed to insert Account with CCN '+slice[j].CMS_Certification_Number__c+
                               ': '+innerEx.getMessage());
                  }
              }
          }
      }
  }

  // --------------------------------------------------------------------
  // SIMPLE LOGGING (you can replace with a custom object or Platform Event)
  // --------------------------------------------------------------------
  private void logError(String msg) {
      System.debug(LoggingLevel.ERROR, msg);
      // In production you'd probably insert into a custom Error_Log__c object
  }
}