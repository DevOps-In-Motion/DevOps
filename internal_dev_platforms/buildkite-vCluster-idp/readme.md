

This repo is a store for the basic information for a CI/CD build pipeline with
buildkite and octopus deploy.



## Buildkite information
### Buildkite File locations

-    Configuration: ~/.buildkite-agent/buildkite-agent.cfg
-    Agent Hooks: ~/.buildkite-agent/hooks
-    Builds: ~/.buildkite-agent/builds
-    SSH keys: ~/.ssh
-    Logs, depending on your system:
        journalctl -f -u buildkite-agent (when started with systemd)
        logs only go to stdout and do not persist (when started with buildkite-agent start)



## resources
https://buildkite.com/docs/agent/v3/installation