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

# opencode CLI, pinned to 1.14.17 (the last build on Bun 1.3.11) behind a
# version-reporting wrapper.
#
# Root cause of "OpenCode did not finish starting on this machine": every
# OpenCode release embedding Bun >= 1.3.12 dies on the Zeabur S2 host (kernel
# 7.0.0-34-generic). JSC cannot suspend its threads (SIGPWR handshake), so the
# binary prints "embedder failed to suspend thread 0x... for TLC 0x..." and
# dies of SIGTRAP (exit 133) about 2s in -- before emitting a single
# `--format json` event. raft-computer's readiness gate therefore never sees a
# runtime event and reports the startup timeout after 120s.
#
# Measured on this host: 1.14.17 streams step_start / text / step_finish and
# exits 0 in ~8s; 1.14.30, 1.15.0, 1.17.20, 1.18.35 and 1.19.3 (newest as of
# 2026-10-17) all crash. Turning off BUN_JSC_useConcurrentJIT, useJITCage,
# useDFGJIT/useFTLJIT/useOMGJIT/useBBQJIT, useSamplingProfiler/useProfiler and
# useConcurrentGC/useBarrierGC -- individually and all together -- changes
# nothing, and the container has no CPU/memory quota, so it is not starvation.
#
# raft-computer 1.0.47 hard-codes MIN_SUPPORTED_OPENCODE_VERSION = "1.14.30" and
# refuses to spawn an older CLI, so no release both passes the gate and runs
# here. The wrapper below answers --version with the gate version and executes
# the pinned working binary for everything else.
#
# TODO(operate): when an OpenCode release ships a Bun that starts on kernel 7.0,
# bump OPENCODE_VERSION to it and delete RAFT_OPENCODE_REPORTED_VERSION + the
# wrapper (point /usr/local/bin/opencode straight at the binary again).
ENV OPENCODE_VERSION=1.14.17
ENV RAFT_OPENCODE_REPORTED_VERSION=1.14.30
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
 && OC_BIN=$(find /usr/local/lib/node_modules -type f -path "*/opencode-linux-x64/bin/opencode" | head -1) \
 && test -n "$OC_BIN" \
 && ln -sf "$OC_BIN" /usr/local/bin/opencode.real \
 && printf '#!/bin/sh\n# Compat wrapper: Raft requires opencode >=1.14.30, but every\n# release at or above it embeds a Bun that crashes on this host kernel.\n# Report the minimum accepted version, run the pinned working binary.\nif [ "$1" = "--version" ] || [ "$1" = "-v" ] || [ "$1" = "version" ]; then\n  printf "%s\\n"\n  exit 0\nfi\nexec /usr/local/bin/opencode.real "$@"\n' "$RAFT_OPENCODE_REPORTED_VERSION" > /usr/local/bin/opencode \
 && chmod 755 /usr/local/bin/opencode \
 && [ "$(opencode --version)" = "$RAFT_OPENCODE_REPORTED_VERSION" ] \
 && [ "$(/usr/local/bin/opencode.real --version | tail -1)" = "$OPENCODE_VERSION" ]

# grok CLI (xAI official npm package)
RUN npm install -g @xai-official/grok

# Cursor agent CLI (installed as `agent`). Headless auth via CURSOR_API_KEY,
# injected at runtime, never baked into the image.
RUN curl -fsSL https://cursor.com/install | bash \
 && ln -sf /root/.local/bin/agent /usr/local/bin/agent \
 && ln -sf /root/.local/bin/agent /usr/local/bin/cursor-agent

# Kimi Code CLI. Raft looks for ~/.kimi-code/bin/kimi and launches `kimi acp`.
# Garza Auto is wired at boot from GARZA_AUTO_API_KEY, never baked.
RUN curl -fsSL https://code.kimi.com/kimi-code/install.sh | KIMI_NO_MODIFY_PATH=1 bash \
 && ln -sf /root/.kimi-code/bin/kimi /usr/local/bin/kimi \
 && kimi --version \
 && kimi acp --help >/dev/null

# Placeholder opencode config; start.sh replaces the API key at boot.
RUN mkdir -p /root/.config/opencode && printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > /root/.config/opencode/opencode.jsonc

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Agent CLIs that read standard env vars route through Manifest at runtime
ENV OPENAI_BASE_URL=https://app.manifest.build/v1 \
    ANTHROPIC_BASE_URL=https://app.manifest.build \
    PATH=/root/.local/bin:/usr/local/bin:$PATH

# Secrets (MANIFEST_API_KEY, RAFT_SESSION_B64) are injected via runtime env, never baked in.
CMD ["/bin/sh", "/app/start.sh"]
