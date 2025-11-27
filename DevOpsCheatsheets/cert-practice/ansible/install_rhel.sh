sudo dnf install ansible-core -y
ansible localhost -m ping


ansible localhost -m setup -a "filter=ansible_distribution*"
# get the list of modules
ansible-doc -l | head -20