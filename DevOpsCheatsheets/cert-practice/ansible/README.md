# Ansible Notes

These are ansible playbooks that are examples for reference to the api




## Ansible Modules Cheatsheet

## Overview
Ansible modules are discrete units of code that perform specific tasks on target systems. They are the building blocks of Ansible playbooks and ad-hoc commands.


## Ansible CLI tools

The most commonly used tools in daily work are:

 - `ansible-playbook` - Running your automation
 - `ansible` - Quick ad-hoc tasks
 - `ansible-vault` - Managing secrets
 - `ansible-galaxy` - Installing roles/collections
 - `ansible-doc` - Looking up module documentation
 - `ansible-pull` - Pull playbook from a repository


---

## File & Directory Management

### `copy`
Copies files from local/remote to remote locations.
```yaml
- copy:
    src: /local/file.txt
    dest: /remote/file.txt
    mode: '0644'
```

### `file`
Manages file and directory properties (create, delete, permissions, ownership).
```yaml
- file:
    path: /path/to/file
    state: directory
    mode: '0755'
```

### `template`
Processes Jinja2 templates and copies them to remote systems.
```yaml
- template:
    src: config.j2
    dest: /etc/app/config.conf
```

### `lineinfile`
Ensures a particular line is in a file, or replaces an existing line.
```yaml
- lineinfile:
    path: /etc/hosts
    line: '192.168.1.100 server.local'
```

### `blockinfile`
Inserts/updates/removes a block of lines in a file.
```yaml
- blockinfile:
    path: /etc/config
    block: |
      setting1=value1
      setting2=value2
```

### `fetch`
Fetches files from remote nodes to the local system.
```yaml
- fetch:
    src: /remote/file.log
    dest: /local/logs/
```

---

## Package Management

### `apt`
Manages packages on Debian/Ubuntu systems.
```yaml
- apt:
    name: nginx
    state: present
    update_cache: yes
```

### `yum`
Manages packages on RHEL/CentOS systems.
```yaml
- yum:
    name: httpd
    state: latest
```

### `dnf`
Manages packages on Fedora/RHEL 8+ systems.
```yaml
- dnf:
    name: python3
    state: present
```

### `package`
Generic package manager (auto-detects system package manager).
```yaml
- package:
    name: git
    state: present
```

### `pip`
Manages Python packages via pip.
```yaml
- pip:
    name: flask
    version: 2.0.1
```

---

## Service Management

### `service`
Manages system services (start, stop, restart, enable).
```yaml
- service:
    name: nginx
    state: started
    enabled: yes
```

### `systemd`
Manages systemd services with additional systemd-specific features.
```yaml
- systemd:
    name: docker
    state: restarted
    daemon_reload: yes
```

---

## User & Group Management

### `user`
Manages user accounts.
```yaml
- user:
    name: john
    state: present
    groups: sudo
    shell: /bin/bash
```

### `group`
Manages groups.
```yaml
- group:
    name: developers
    state: present
    gid: 5000
```

### `authorized_key`
Manages SSH authorized keys.
```yaml
- authorized_key:
    user: john
    key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
```

---

## Command Execution

### `command`
Executes commands on remote nodes (does not use shell).
```yaml
- command: /usr/bin/make install
  args:
    chdir: /source/dir
```

### `shell`
Executes commands through a shell (supports pipes, redirects).
```yaml
- shell: echo $HOME | grep /home
```

### `script`
Runs a local script on remote nodes.
```yaml
- script: /local/scripts/setup.sh
```

### `raw`
Executes raw commands without requiring Python on target.
```yaml
- raw: apt-get install -y python3
```

---

## System Information

### `setup`
Gathers facts about remote systems (automatically run by playbooks).
```yaml
- setup:
    gather_subset:
      - hardware
      - network
```

### `stat`
Retrieves file or directory status.
```yaml
- stat:
    path: /etc/config.conf
  register: file_stat
```

### `find`
Searches for files matching criteria.
```yaml
- find:
    paths: /var/log
    patterns: "*.log"
    age: 7d
```

---

## Archive & Compression

### `archive`
Creates compressed archives.
```yaml
- archive:
    path: /data/files
    dest: /backup/files.tar.gz
    format: gz
```

### `unarchive`
Extracts archives on remote systems.
```yaml
- unarchive:
    src: /tmp/archive.tar.gz
    dest: /opt/app
    remote_src: yes
```

---

## Network & Connectivity

### `get_url`
Downloads files from HTTP, HTTPS, or FTP.
```yaml
- get_url:
    url: https://example.com/file.zip
    dest: /tmp/file.zip
```

### `uri`
Interacts with web services (REST API calls).
```yaml
- uri:
    url: https://api.example.com/status
    method: GET
    return_content: yes
```

### `wait_for`
Waits for a condition (port, file, connection).
```yaml
- wait_for:
    port: 8080
    delay: 10
    timeout: 300
```

---

## Database Management

### `mysql_db`
Manages MySQL databases.
```yaml
- mysql_db:
    name: myapp
    state: present
```

### `mysql_user`
Manages MySQL users and privileges.
```yaml
- mysql_user:
    name: appuser
    password: secret
    priv: 'myapp.*:ALL'
```

### `postgresql_db`
Manages PostgreSQL databases.
```yaml
- postgresql_db:
    name: mydb
    state: present
```

---

## Cloud Modules

### `ec2_instance`
Manages AWS EC2 instances.
```yaml
- ec2_instance:
    name: web-server
    instance_type: t2.micro
    state: present
```

### `azure_rm_virtualmachine`
Manages Azure virtual machines.

### `gcp_compute_instance`
Manages Google Cloud Compute instances.

### `docker_container`
Manages Docker containers.
```yaml
- docker_container:
    name: nginx
    image: nginx:latest
    state: started
```

---

## Version Control

### `git`
Manages git repositories.
```yaml
- git:
    repo: https://github.com/user/repo.git
    dest: /opt/app
    version: main
```

---

## Debugging & Testing

### `debug`
Prints variables or messages during execution.
```yaml
- debug:
    msg: "The value is {{ my_variable }}"
```

### `assert`
Validates conditions and fails if false.
```yaml
- assert:
    that:
      - ansible_distribution == "Ubuntu"
    fail_msg: "This playbook requires Ubuntu"
```

### `fail`
Fails the playbook with a custom message.
```yaml
- fail:
    msg: "Critical error occurred"
  when: error_condition
```

---

## Flow Control

### `include_tasks`
Dynamically includes task files.
```yaml
- include_tasks: deploy.yml
```

### `import_tasks`
Statically imports task files.
```yaml
- import_tasks: setup.yml
```

### `meta`
Executes special Ansible actions (flush handlers, refresh inventory).
```yaml
- meta: flush_handlers
```

---

## Tips
- Use `ansible-doc <module_name>` to view detailed module documentation
- Most modules support `check_mode` for dry runs
- Use `-v`, `-vv`, or `-vvv` flags for increased verbosity
- Common module parameters: `when`, `register`, `become`, `tags`