# create role dir and example role
mkdir -p roles/example_role
cd roles/example_role
# create the basic structure for roles
mkdir {tasks,handlers,defaults,vars,files,templates,meta}
# create task
nano tasks/main.yml