FROM python:3.11-slim

LABEL maintainer="rehanfazal47"
LABEL description="Ansible runner for Nephio BYOH cluster provisioning"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    curl \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    ansible \
    kubernetes \
    jinja2 \
    pyyaml

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/v1.32.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Create working directory
WORKDIR /ansible

# Copy Ansible playbooks and templates
COPY site.yaml /ansible/
COPY templates/ /ansible/templates/

# Configure SSH
RUN mkdir -p /root/.ssh && \
    echo "Host *" >> /root/.ssh/config && \
    echo "  StrictHostKeyChecking no" >> /root/.ssh/config && \
    echo "  UserKnownHostsFile /dev/null" >> /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Default entrypoint
ENTRYPOINT ["ansible-playbook"]
CMD ["site.yaml", "-e", "@/config/input.json"]
