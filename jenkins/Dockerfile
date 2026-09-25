FROM jenkins/jenkins:lts-jdk17

USER root

# Docker CLI + buildx (builds use the host's Docker via the mounted socket)
RUN apt-get update && apt-get install -y ca-certificates curl gnupg unzip && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli docker-buildx-plugin && \
    rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# kubectl (matches cluster version 1.31)
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v1.31.0/bin/linux/$(dpkg --print-architecture)/kubectl" && \
    chmod +x /usr/local/bin/kubectl

# Helm 3
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Runs as root so the container can use the host Docker socket (local dev setup)
