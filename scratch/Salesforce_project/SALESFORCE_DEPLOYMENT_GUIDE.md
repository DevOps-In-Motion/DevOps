# Salesforce CLI Deployment Guide for CMS Fields

## Prerequisites

1. **Install Salesforce CLI**
   ```bash
   npm install -g @salesforce/cli
   ```

2. **Authenticate to your Salesforce org**
   ```bash
   # For production org
   sf org login web --alias myorg
   
   # For sandbox org
   sf org login web --alias mysandbox --instance-url https://test.salesforce.com
   ```

## Method 1: Using the Automated Script

Run the deployment script I created:

```bash
cd /Users/deon/githubRepos/DevOps-In-Motion/scratch
./deploy-cms-fields.sh
```

# Summary: Automating Salesforce Field Creation

## Big Picture Process:

1. **Started with CSV columns** - You provided a list of field names from a CSV

2. **Generated XML metadata** - Created a single XML file with all 106 fields in Salesforce metadata format

3. **Split into individual files** - Salesforce requires one XML file per field, so created a Python script to split the combined XML into 106 separate `.field-meta.xml` files

4. **Fixed label length issues** - Salesforce has a 40-character limit on field labels, so created another Python script to automatically shorten long labels using abbreviations

5. **Deployed via Salesforce CLI** - Used `sf project deploy start` to push all fields to the Account object

## Key Takeaway:
For bulk field creation, the pattern is: **Generate metadata files → Split into proper structure → Fix validation issues → Deploy with CLI**

This approach is repeatable and can be templated/scripted for future bulk field additions.



## Apex API integration script

### Add Remote Site Setting

1. **Go to Setup** (gear icon in top right)
2. In Quick Find box, type: **Remote Site Settings**
3. Click **Remote Site Settings**
4. Click **New Remote Site**
5. Fill in:
   - **Remote Site Name:** `CMS_Provider_API`
   - **Remote Site URL:** `https://data.cms.gov`
   - **Description:** `CMS Provider Data API`
   - **Active:** ✓ (checked)
6. Click **Save**

### Add script to the apex developer 

### Run the script in the apex developer via a test

```apex
CMSProviderAPIService.syncProviderData();
```

The Remote Site Setting tells Salesforce that it's safe to make HTTP callouts to that external URL. Without it, Salesforce blocks all outbound API calls for security reasons.

Once you add it, the integration should work! Let me know what you see in the debug log after adding the remote site setting. 🚀