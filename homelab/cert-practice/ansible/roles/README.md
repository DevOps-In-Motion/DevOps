# Overview

An Ansible Role has a defined directory structure with eight main standard directories. Each directory must contain a main.yml file, which contains the relevant content. Here's a brief overview of each directory:

    tasks - contains the main list of tasks to be executed by the role.
    handlers - contains handlers, which may be used by this role or outside of this role.
    defaults - default variables for the role.
    vars - other variables for the role.
    files - contains files which can be deployed via this role.
    templates - contains templates which can be deployed via this role.
    meta - defines some meta data for this role.
    tests - contains tests for the role.
