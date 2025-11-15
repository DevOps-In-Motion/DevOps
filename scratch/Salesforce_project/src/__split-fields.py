#!/usr/bin/env python3
"""
Script to split a multi-field CustomObject XML into individual CustomField files
"""

import os
import re

# Input and output paths
input_file = "/Users/deon/githubRepos/DevOps-In-Motion/scratch/deployment/force-app/main/default/objects/Account/fields/all-fields.field-meta.xml"
output_dir = "/Users/deon/githubRepos/DevOps-In-Motion/scratch/deployment/force-app/main/default/objects/Account/fields"

# Read the entire file
with open(input_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Find all <fields>...</fields> blocks
field_pattern = r'<fields>(.*?)</fields>'
fields = re.findall(field_pattern, content, re.DOTALL)

print(f"Found {len(fields)} fields to split")

# Process each field
for field_content in fields:
    # Extract the field name
    name_match = re.search(r'<fullName>(.*?)</fullName>', field_content)
    if not name_match:
        print("Warning: Field without fullName found, skipping")
        continue
    
    field_name = name_match.group(1)
    
    # Create the new CustomField XML
    new_xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
{field_content.strip()}
</CustomField>
'''
    
    # Write to individual file
    output_file = os.path.join(output_dir, f"{field_name}.field-meta.xml")
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(new_xml)
    
    print(f"Created: {field_name}.field-meta.xml")

print(f"\nSuccessfully created {len(fields)} field files!")
print(f"\nNext steps:")
print(f"1. Delete the original file:")
print(f"   rm {input_file}")
print(f"2. Deploy the fields:")
print(f"   sf project deploy start --source-dir force-app/main/default/objects/Account/fields")