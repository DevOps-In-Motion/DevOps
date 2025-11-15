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

  // Mapping of API column header → Salesforce field API name (see map above)
  private static final Map<String,String> API_TO_SF = new Map<String,String>{
    // ---- renamed columns (your list) ----
    'Abuse Icon'                                 => 'Abuse_Icon__c',
    'Adj LPN Hours/Resident/Day'                 => 'Adjusted_LPN_Hours__c',
    'Adj Nurse Aide Hours/Resident/Day'          => 'Adjusted_Nurse_Aide_Hours__c',
    'Adj RN Hours/Resident/Day'                  => 'Adjusted_RN_Hours__c',
    'Adj Total Nurse Hours/Resident/Day'         => 'Adjusted_Total_Nurse_Hours__c',
    'Adj Weekend Total Nurse Hours/Residen...'    => 'Adjusted_Weekend_Total_Hours__c',
    'Administrator turnover footnote'            => 'Administrator_Turnover_Footnote__c',
    'Auto Sprinklers (All Areas)'                => 'Automatic_Sprinkler_Systems__c',
    'Average Number of Residents per Day'        => 'Average_Number_of_Residents_per_Day__c',
    'Avg Num Residents per Day Footnote'         => 'Avg_Residents_per_Day_Footnote__c',
    'CaseMix LPN Hours/Resident/Day'             => 'Case_Mix_LPN_Hours__c',
    'CaseMix Nurse Aide Hours/Resident/Day'      => 'Case_Mix_Nurse_Aide_Hours__c',
    'CaseMix RN Hours/Resident/Day'              => 'Case_Mix_RN_Hours__c',
    'CaseMix Total Nurse Hours/Resident/Day'     => 'Case_Mix_Total_Nurse_Hours__c',
    'CaseMix Weekend Total Nurse Hours/Res...'    => 'Case_Mix_Weekend_Total_Hours__c',
    'Chain Average Health Inspection Rating'     => 'Chain_Avg_Health_Inspection_Rating__c',
    'Chain Average Overall 5-star Rating'       => 'Chain_Avg_Overall_5_star_Rating__c',
    'Chain Average QM Rating'                    => 'Chain_Avg_QM_Rating__c',
    'Chain Average Staffing Rating'              => 'Chain_Avg_Staffing_Rating__c',
    'Chain ID'                                   => 'Chain_ID__c',
    'Chain Name'                                 => 'Chain_Name__c',
    'Num Citations from Infection Control ...'  => 'Citations_from_Infection_Control__c',
    'City/Town'                                  => 'City_Town__c',
    'CMS Certification Number (CCN)'            => 'CMS_Certification_Number__c',
    'Continuing Care Retirement Community'      => 'Continuing_Care_Retirement_Community__c',
    'County/Parish'                              => 'County_Parish__c',
    'Cycle 1 Num Complaint Health Defic'         => 'Cycle_1_Complaint_Health_Deficiencies__c',
    'Rating Cycle 1 Health Deficiency Score'     => 'Cycle_1_Health_Deficiency_Score__c',
    'Rating Cycle 1 Health Revisit Score'        => 'Cycle_1_Health_Revisit_Score__c',
    'Rating Cycle 1 Number of Health Revisits'   => 'Cycle_1_Number_of_Health_Revisits__c'
    // …add any other renamed columns here…
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
      // 1️⃣ Get existing CCNs once (set for fast lookup)
      Set<String> existingCCNs = fetchExistingCCNs();

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
              // Build Account if CCN not already present
              // -------------------------------------------------
              String ccn = (String)row.get('CMS Certification Number (CCN)');
              if (String.isBlank(ccn) || existingCCNs.contains(ccn)) {
                  // Skip – either no CCN or already exists
                  continue;
              }

              Account acc = new Account();
              acc.CMS_Certification_Number__c = ccn; // always present

              // Populate every field using the mapping table
              for (String apiHeader : row.keySet()) {
                  Object rawVal = row.get(apiHeader);
                  if (rawVal == null) continue;

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
  // HELPERS – EXISTING CCNs
  // --------------------------------------------------------------------
  private Set<String> fetchExistingCCNs() {
      Set<String> ccns = new Set<String>();
      for (Account a : [
          SELECT CMS_Certification_Number__c
          FROM Account
          WHERE CMS_Certification_Number__c != null
      ]) {
          ccns.add(a.CMS_Certification_Number__c);
      }
      return ccns;
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