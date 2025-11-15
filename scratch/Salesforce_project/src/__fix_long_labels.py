#!/usr/bin/env python3
"""
Script to fix field labels that exceed Salesforce's 40 character limit
"""

import os
import re
from pathlib import Path

# Directory containing the field files
fields_dir = "/Users/deon/githubRepos/DevOps-In-Motion/scratch/deployment/force-app/main/default/objects/Account/fields"

# Label abbreviations to shorten common long phrases
abbreviations = {
    'Staffing Hours per Resident per Day': 'Hours/Resident/Day',
    'per Resident per Day': '/Resident/Day',
    'Number of': 'Num',
    'Average': 'Avg',
    'Rating Cycle': 'Cycle',
    'Standard Health': 'Std Health',
    'Deficiencies': 'Defic',
    'Registered Nurse': 'RN',
    'Physical Therapist': 'PT',
    'Licensed Practical Nurse': 'LPN',
    'Case-Mix': 'CaseMix',
    'Adjusted': 'Adj',
    'Reported': 'Rpt',
    'Total Number of Health': 'Total Health',
    'Health Inspection': 'Health Insp',
    'Most Recent Health Inspection More Than 2 Years Ago': 'Recent Insp >2 Years',
    'Provider Changed Ownership in Last 12 Months': 'Ownership Changed (12mo)',
    'With a Resident and Family Council': 'Resident/Family Council',
    'Automatic Sprinkler Systems in All Required Areas': 'Auto Sprinklers (All Areas)',
    'Average Number of Residents per Day Footnote': 'Avg Residents/Day Footnote',
    'Date First Approved to Provide Medicare and Medicaid Services': 'Medicare/Medicaid Approval Date',
    'Number of administrators who have left the nursing home': 'Num Admins Left',
    'hours per resident per day on the weekend': 'Hours/Resident Weekend',
    'Number of Citations from Infection Control Inspections': 'Infection Control Citations',
    'Continuing Care Retirement Community': 'CCRC',
}

def shorten_label(label):
    """Shorten a label to 40 characters or less"""
    # Apply abbreviations
    for long_form, short_form in abbreviations.items():
        label = label.replace(long_form, short_form)
    
    # If still too long, truncate intelligently
    if len(label) > 40:
        # Try removing parenthetical content first
        label = re.sub(r'\s*\([^)]*\)', '', label)
    
    # If still too long, truncate with ellipsis
    if len(label) > 40:
        label = label[:37] + '...'
    
    return label

# Process each field file
count = 0
fixed = 0

for filename in os.listdir(fields_dir):
    if not filename.endswith('.field-meta.xml'):
        continue
    
    filepath = os.path.join(fields_dir, filename)
    count += 1
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find the label
    label_match = re.search(r'<label>(.*?)</label>', content)
    if not label_match:
        continue
    
    original_label = label_match.group(1)
    
    # Check if label is too long
    if len(original_label) <= 40:
        continue
    
    # Shorten the label
    new_label = shorten_label(original_label)
    
    # Replace in content
    new_content = content.replace(
        f'<label>{original_label}</label>',
        f'<label>{new_label}</label>'
    )
    
    # Write back
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    fixed += 1
    print(f"Fixed: {filename}")
    print(f"  Old ({len(original_label)}): {original_label}")
    print(f"  New ({len(new_label)}): {new_label}")
    print()

print(f"\nProcessed {count} files, fixed {fixed} labels")
print("\nNow deploy with:")
print("sf project deploy start --source-dir force-app/main/default/objects/Account/fields")