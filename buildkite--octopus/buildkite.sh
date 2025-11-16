# https://buildkite.com/docs/agent/v3/installation

TOKEN="INSERT-YOUR-AGENT-TOKEN-HERE" bash -c "`curl -sL https://raw.githubusercontent.com/buildkite/agent/main/install.sh`"
~/.buildkite-agent/bin/buildkite-agent start
mkdir -p ~/.ssh && cd ~/.ssh
ssh-keygen -t rsa -b 4096 -C "build@myorg.com"


# https://buildkite.com/docs/agent/v3/configuration
