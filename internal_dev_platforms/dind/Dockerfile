# Docker image that creates a k3d cluster and installs the wiki Helm chart (all components).
# Run with the host Docker socket so k3d can create the cluster on the host:
#   docker build -t wiki-k3d .
#   docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d
#
# Then access (all on port 8080): http://localhost:8080/users, http://localhost:8080/posts, http://localhost:8080/grafana

FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    docker-cli-compose \
    git \
    ca-certificates

# kubectl
ARG KUBECTL_VERSION=1.30.2
RUN curl -sSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -sSL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz | tar xz -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64

# k3d (official install script)
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

WORKDIR /app

# Chart and values (copied so image is self-contained)
COPY wiki-chart /app/wiki-chart
COPY k3d /app/k3d
RUN chmod +x /app/k3d/entrypoint.sh

ENTRYPOINT ["/app/k3d/entrypoint.sh"]
