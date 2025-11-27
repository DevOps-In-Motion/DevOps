


This directory stores all the information for Terraform and Ansible.

## Terraform
### Buildkite File locations

-    Configuration: ~/.buildkite-agent/buildkite-agent.cfg
-    Agent Hooks: ~/.buildkite-agent/hooks
-    Builds: ~/.buildkite-agent/builds
-    SSH keys: ~/.ssh
-    Logs, depending on your system:
        journalctl -f -u buildkite-agent (when started with systemd)
        logs only go to stdout and do not persist (when started with buildkite-agent start)



## resources
