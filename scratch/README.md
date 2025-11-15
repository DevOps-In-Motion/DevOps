Ah! You need to add the Remote Site Setting. Here's how:

## Fix: Add Remote Site Setting

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

## Then run the sync again:

```apex
CMSProviderAPIService.syncProviderData();
```

The Remote Site Setting tells Salesforce that it's safe to make HTTP callouts to that external URL. Without it, Salesforce blocks all outbound API calls for security reasons.

Once you add it, the integration should work! Let me know what you see in the debug log after adding the remote site setting. 🚀