# ping all in the inventory file
ansible -i inventory -m ping all
# ping the group under webservers
### -i == inventory file
ansible -i inventory -m ping webservers