#!/bin/bash

# generate keys for node connection to use ansible
ssh-keygen -t rsa -b 4096 -C "labex@example.com"
# mkdir
sudo mkdir -p /etc/ansible
# create hosts file

ssh-copy-id labex@localhost
ssh labex@localhost


# --- ansible [pattern] -m [module] -a "[module options]" --- #
# check the 
ansible all -i /home/labex/project/inventory -m command -a "df -h"
ansible webservers -i /home/labex/project/inventory -m command -a "uptime"
ansible dbservers -i /home/labex/project/inventory -a "free -m"

## copy module - used to copy files from the local machine to the remote hosts. 
ansible all -i /home/labex/project/inventory -m copy -a "src=/home/labex/project/hello.txt dest=/tmp/hello.txt"
## file module - This module is used to manage files and directories. 
# create dir on all webservers
ansible webservers -i /home/labex/project/inventory -m file -a "path=/tmp/test_dir state=directory mode=0755"
## setup module - This module is used to gather facts about the remote hosts. It's automatically run at the beginning of playbooks, but can also be used in ad-hoc commands:
ansible dbservers -i /home/labex/project/inventory -m setup -a "filter=ansible_distribution*"


# ping all nodes
ansible all -m ping
# Now, let's test our inventory using Ansible's ping module. 
# The ping module doesn't actually use the ICMP ping protocol; 
# instead, it verifies that Ansible can connect to the host and execute code.
ansible -i inventory -m ping all
ansible all -a "uptime"

# config
cat /etc/ansible/ansible.cfg
# Now, let's look at Ansible's default configuration values. We can do this by running:
ansible-config dump
# start project inventory file
echo "localhost ansible_connection=local" > /home/labex/project/inventory
# verify changes
ansible-config dump --only-changed

# ansible-playbook -i <config-file-name> <playbook-file>
ansible-playbook -i inventory show_http_port.yml
# pass a variable to a module
ansible-playbook script-module-playbook.yaml -e "message=Hello,Ansible"


### --- python interpreter --- ###



### --- Secrets --- ###
ansible-vault create secrets.yml
# create user based on vault
ansible-playbook --ask-vault-pass create_user.yml
# verify that everything is working
id myappuser

