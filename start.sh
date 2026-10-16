#!/bin/sh
export PATH="$PATH:/root/.local/bin:/usr/local/bin"

# Generate pi config from env at boot (no secrets baked into the image)
if [ -n "$MANIFEST_API_KEY" ]; then
  mkdir -p /root/.pi/agent
  cat > /root/.pi/agent/models.json <<EOF
{
  "providers": {
    "manifest": {
      "name": "Manifest",
      "baseUrl": "https://app.manifest.build/v1",
      "api": "openai-completions",
      "apiKey": "$MANIFEST_API_KEY",
      "authHeader": true,
      "models": [
        {"id": "auto", "name": "Manifest Auto", "reasoning": true, "input": ["text","image"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "contextWindow": 200000, "maxTokens": 64000, "compat": {"supportsDeveloperRole": true, "supportsReasoningEffort": true, "maxTokensField": "max_completion_tokens", "thinkingFormat": "openai"}},
        {"id": "anthropic/claude-sonnet-5-5-subscription", "name": "Manifest Claude Sonnet 5.5", "reasoning": true, "input": ["text","image"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "contextWindow": 200000, "maxTokens": 64000, "compat": {"supportsDeveloperRole": true, "maxTokensField": "max_completion_tokens"}},
        {"id": "zai/glm-5.3-subscription", "name": "Manifest GLM 5.3", "reasoning": true, "input": ["text","image"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0}, "contextWindow": 200000, "maxTokens": 64000, "compat": {"supportsDeveloperRole": true, "maxTokensField": "max_completion_tokens"}}
      ]
    }
  }
}
EOF
  printf '{\n  "defaultProvider": "manifest",\n  "defaultModel": "auto",\n  "theme": "dark"\n}\n' > /root/.pi/agent/settings.json
fi

# Optional: pre-seed a Raft session (base64 JSON) for headless attach
if [ -n "$RAFT_SESSION_B64" ] && [ ! -f /root/.raft/computer/user-session.json ]; then
  mkdir -p /root/.raft/computer
  echo "$RAFT_SESSION_B64" | base64 -d > /root/.raft/computer/user-session.json
fi

echo "[garza] starting raft-computer (reconnect loop)..."
while true; do
  raft-computer start --foreground 2>&1 || true
  echo "[garza] raft-computer exited; retrying in 10s"
  sleep 10
done
