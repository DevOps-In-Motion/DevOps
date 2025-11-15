#!/bin/bash
# get the error report if needed
# sf project deploy report --job-id 0Afbm00000MwyC1CAJ --target-org allen.saunders@toptal.com
sf project deploy start --metadata-dir /Users/deon/githubRepos/DevOps-In-Motion/scratch/deployment/force-app/main/default/objects/Account/fields/all-fields.field-meta.xml \

sf project deploy start --source-dir /Users/deon/githubRepos/DevOps-In-Motion/scratch/deployment/force-app/main/default/objects/Account/fields \
  --target-org allen.saunders@toptal.com


sf project deploy report --target-org allen.saunders@toptal.com



# Check if any of our custom fields exist
sf sobject describe --sobject Account --target-org allen.saunders@toptal.com | grep -i "CMS_Certification"
sf sobject describe --sobject Account --target-org allen.saunders@toptal.com | grep -i "Provider_Name"
sf sobject describe --sobject Account --target-org allen.saunders@toptal.com | grep -i "Nursing"


ls -1 *.field-meta.xml | wc -l



curl -X 'GET' \
  'https://data.cms.gov/provider-data/api/1/datastore/sql?query=%5BSELECT%20%2A%20FROM%200ae91eb2-22da-5fe3-9dce-9811cdd6f1a8%5D%5BLIMIT%202%5D&show_db_columns=true' \
  -H 'accept: application/json'