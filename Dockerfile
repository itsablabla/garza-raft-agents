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

# Agent CLIs that read standard env vars route through Manifest at runtime
ENV OPENAI_BASE_URL=https://app.manifest.build/v1 \
    ANTHROPIC_BASE_URL=https://app.manifest.build \
    PATH=/root/.local/bin:/usr/local/bin:$PATH

# Secrets (MANIFEST_API_KEY, RAFT_SESSION_B64) are injected via runtime env, never baked in.
CMD ["/bin/sh", "/app/start.sh"]
