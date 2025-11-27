# Update 
sudo apt update
# 
sudo apt install ansible
ansible --version

## Configure SSH for node
# generate key
ssh-keygen -t rsa -b 4096 -C "labex@example.com"
# copy key to device
ssh-copy-id labex@localhost
# ssh into node
ssh user@node

## Create Ansible Configuration
sudo mkdir -p /etc/ansible
sudo nano /etc/ansible/hosts