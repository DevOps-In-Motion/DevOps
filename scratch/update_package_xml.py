#!/usr/bin/env python3
"""
Generate package.xml with all field names
"""

import os

# Get all field files
field_files = [f for f in os.listdir('force-app/main/default/objects/Account/fields') if f.endswith('.field-meta.xml')]

# Create package.xml
package_xml = """<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.salesforce.com/2006/04/metadata">
    <types>
"""

for field_file in field_files:
    field_name = field_file.replace('.field-meta.xml', '')
    package_xml += f"        <members>Account.{field_name}</members>\n"

package_xml += """        <name>CustomField</name>
    </types>
    <version>58.0</version>
</Package>"""

with open('manifest/package.xml', 'w') as f:
    f.write(package_xml)

print(f"Created manifest/package.xml with {len(field_files)} fields")
