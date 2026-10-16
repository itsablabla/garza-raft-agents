FROM node:22-slim

# Base tools for raft-computer and agents
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git ripgrep sudo procps && rm -rf /var/lib/apt/lists/*

# raft-computer
RUN curl -fsSL https://cdn.raft.build/computer/install.sh | sh

# pi runtime (Raft's agent runtime), pinned to the version working on the Mac
ENV PI_VERSION=0.87.1
RUN mkdir -p /root/.pi/agent/bin /root/.pi/agent/install/releases/$PI_VERSION \
 && cd /root/.pi/agent/install/releases/$PI_VERSION \
 && npm init -y >/dev/null 2>&1 \
 && npm install --no-audit --no-fund @earendil-works/pi-coding-agent@$PI_VERSION >/dev/null 2>&1 \
 && echo $PI_VERSION > /root/.pi/agent/install/current-version \
 && ln -sf /root/.pi/agent/install/releases/$PI_VERSION/node_modules/.bin/pi /root/.pi/agent/bin/pi \
 && ln -sf /root/.pi/agent/bin/pi /usr/local/bin/pi

# opencode CLI
RUN npm install -g opencode-ai

# grok CLI (xAI official npm package)
RUN npm install -g @xai-official/grok

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Manifest provider config for pi (model routing)
RUN mkdir -p /root/.pi/agent
COPY models.json /root/.pi/agent/models.json
COPY settings.json /root/.pi/agent/settings.json

# Shell env so any CLI reading OPENAI_/ANTHROPIC_ vars uses Manifest
ENV OPENAI_API_KEY=mnfst_4wgFwEZlQdPjccWhRZaiSNUjNdB-17PkaaLQvIUuJNU \
    OPENAI_BASE_URL=https://app.manifest.build/v1 \
    ANTHROPIC_AUTH_TOKEN=mnfst_4wgFwEZlQdPjccWhRZaiSNUjNdB-17PkaaLQvIUuJNU \
    ANTHROPIC_BASE_URL=https://app.manifest.build \
    PATH=/root/.local/bin:/usr/local/bin:$PATH

CMD ["/bin/sh", "/app/start.sh"]
