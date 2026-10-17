#!/bin/sh
export PATH="$PATH:/root/.local/bin:/usr/local/bin"

# Belt and braces for Bun/JSC. Note: this does NOT fix the 7.0-kernel thread
# suspension crash (oven-sh/bun#31832) — that is why the image pins opencode to
# the last Bun 1.3.11 build. See the Dockerfile comment.
export BUN_JSC_useConcurrentGC="${BUN_JSC_useConcurrentGC:-0}"

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

  # opencode needs the manifest provider configured or every turn fails
  # ("Unexpected server error") for agents using model manifest/auto.
  mkdir -p /root/.config/opencode
  cat > /root/.config/opencode/opencode.json <<OCJSON
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "manifest/auto",
  "provider": {
    "manifest": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Manifest Gateway",
      "options": {
        "baseURL": "https://app.manifest.build/v1",
        "apiKey": "$MANIFEST_API_KEY",
        "stream": true
      },
      "models": {
        "auto": {
          "name": "Manifest Auto",
          "limit": { "context": 200000, "output": 128000 },
          "options": { "stream": true }
        }
      }
    }
  },
  "permission": { "*": "allow" }
}
OCJSON
fi

# Garza Auto is an OpenAI-compatible gateway. Add it beside Manifest when the
# key is present so pi and opencode can select provider garza, model garza-auto.
if [ -n "$GARZA_AUTO_API_KEY" ]; then
  mkdir -p /root/.pi/agent /root/.config/opencode
  node -e '
    const fs = require("fs");
    const key = process.env.GARZA_AUTO_API_KEY;
    const model = {
      id: "garza-auto", name: "Garza Auto", reasoning: true, input: ["text"],
      cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0},
      contextWindow: 200000, maxTokens: 64000,
      compat: {supportsDeveloperRole: true, maxTokensField: "max_completion_tokens"},
    };
    let pi = {providers: {}};
    try { pi = JSON.parse(fs.readFileSync("/root/.pi/agent/models.json", "utf8")); } catch {}
    pi.providers = pi.providers || {};
    pi.providers.garza = {name: "Garza Auto", baseUrl: "https://llm.garzahub.app/v1", api: "openai-completions", apiKey: key, authHeader: true, models: [model]};
    fs.writeFileSync("/root/.pi/agent/models.json", JSON.stringify(pi, null, 2));
    let oc = {"$schema": "https://opencode.ai/config.json", provider: {}};
    try { oc = JSON.parse(fs.readFileSync("/root/.config/opencode/opencode.json", "utf8")); } catch {}
    oc.provider = oc.provider || {};
    oc.provider.garza = {npm: "@ai-sdk/openai-compatible", name: "Garza Auto", options: {baseURL: "https://llm.garzahub.app/v1", apiKey: key, stream: true}, models: {"garza-auto": {name: "Garza Auto", limit: {context: 200000, output: 128000}, options: {stream: true}}}};
    fs.writeFileSync("/root/.config/opencode/opencode.json", JSON.stringify(oc, null, 2));
    console.log("[garza] garza-auto provider configured");
  ' || true

  # Kimi Code does not inherit the daemon environment, and api_key_env is not
  # visible to the ACP child it spawns. Write the key into config at boot so
  # the image stays secret-free. default_model lands a new agent on Garza Auto.
  mkdir -p /root/.kimi-code
  umask 077
  cat > /root/.kimi-code/config.toml <<KIMI
default_model = "garza/garza-auto"
default_permission_mode = "yolo"
telemetry = false

[providers.garza]
type = "openai"
base_url = "https://llm.garzahub.app/v1"
api_key = "$GARZA_AUTO_API_KEY"

[models."garza/garza-auto"]
provider = "garza"
model = "garza-auto"
max_context_size = 200000
capabilities = ["thinking", "tool_use"]
display_name = "Garza Auto"
KIMI
  chmod 600 /root/.kimi-code/config.toml
  echo "[garza] kimi garza-auto config written"

  # Grok CLI: override built-in models with Garza Auto so Cindy, Cody, Travel,
  # and Teacher never lose auth to 6-hour OAuth expiration.
  mkdir -p /root/.grok
  cat > /root/.grok/config.toml <<GROK
[cli]
installer = "npm"
auto_update = false

[models]
default = "grok-4.7"

[model."grok-4.7"]
model = "garza-auto"
base_url = "https://llm.garzahub.app/v1"
name = "Garza Auto (Grok 4.7)"
api_key = "$GARZA_AUTO_API_KEY"
api_backend = "chat_completions"
context_window = 200000

[model."grok-4.5"]
model = "garza-auto"
base_url = "https://llm.garzahub.app/v1"
name = "Garza Auto (Grok 4.5)"
api_key = "$GARZA_AUTO_API_KEY"
api_backend = "chat_completions"
context_window = 200000

[model."grok-4.6"]
model = "garza-auto"
base_url = "https://llm.garzahub.app/v1"
name = "Garza Auto (Grok 4.6)"
api_key = "$GARZA_AUTO_API_KEY"
api_backend = "chat_completions"
context_window = 200000
GROK
  chmod 600 /root/.grok/config.toml
  rm -f /root/.grok/auth.json
  echo "[garza] grok garza-auto config written (permanent key auth)"
fi

# Optional: pre-seed a Raft session (base64 JSON) for headless attach
if [ -n "$RAFT_SESSION_B64" ] && [ ! -f /root/.raft/computer/user-session.json ]; then
  mkdir -p /root/.raft/computer
  echo "$RAFT_SESSION_B64" | base64 -d > /root/.raft/computer/user-session.json
fi

# Optional: pre-seed the machine attachment (base64 of
# ~/.raft/computer/servers/<serverId>/runner.state.json) so pod restarts
# reattach as the SAME machine row instead of registering a new one.
if [ -n "$RAFT_RUNNER_STATE_B64" ]; then
  mkdir -p /root/.raft/computer/servers/garza
  # decode; find serverId inside to pick the dir name
  tmp=/tmp/raft-runner-state.json
  echo "$RAFT_RUNNER_STATE_B64" | base64 -d > "$tmp"
  sid=$(sed -n 's/.*"serverId": *"\([^"]*\)".*/\1/p' "$tmp" | head -1)
  if [ -n "$sid" ] && [ ! -f "/root/.raft/computer/servers/$sid/runner.state.json" ]; then
    mkdir -p "/root/.raft/computer/servers/$sid"
    cp "$tmp" "/root/.raft/computer/servers/$sid/runner.state.json"
    chmod 600 "/root/.raft/computer/servers/$sid/runner.state.json"
  fi
  rm -f "$tmp"
fi

# Optional: pre-seed grok CLI auth (base64 of ~/.grok/auth.json) so it survives redeploys
if [ -n "$GROK_AUTH_B64" ] && [ ! -f /root/.grok/auth.json ]; then
  mkdir -p /root/.grok
  echo "$GROK_AUTH_B64" | base64 -d > /root/.grok/auth.json
  chmod 600 /root/.grok/auth.json
fi

# Cursor agent authenticates from CURSOR_API_KEY when set. Confirm it without
# printing the value so boot logs prove headless auth is available.
if [ -n "$CURSOR_API_KEY" ]; then
  echo "[garza] cursor-agent key present (len ${#CURSOR_API_KEY})"
fi

# Raft pins each opencode agent to an opencode session id, but opencode.db is
# wiped on every pod restart. Seed the pinned session rows (space-separated
# "<agent-dir>:<session-id>" pairs in RAFT_OPENCODE_SESSIONS) so restarts don't
# fail with "Session not found".
if [ -n "$RAFT_OPENCODE_SESSIONS" ]; then
  # opencode's sqlite schema is version-specific and NOT forward/backward
  # compatible: an older binary on a store written by a newer one dies with
  # "Failed to run the query CREATE TABLE `project`" during migrations. Reset
  # the store whenever the pinned binary version changes (history is rebuilt by
  # the seeding below, and Raft keeps its own transcript copy).
  # Real binary version, not the wrapper's answer: /usr/local/bin/opencode
  # reports Raft's gate version (1.14.30) so raft-computer will spawn it, while
  # the actual store schema belongs to opencode.real (1.14.17).
  export OC_VERSION=$( { /usr/local/bin/opencode.real --version 2>/dev/null || opencode --version; } | tail -1)
  OC_STORE=/root/.local/share/opencode
  if [ -n "$OC_VERSION" ] && [ -f "$OC_STORE/opencode.db" ] \
     && [ "$(cat "$OC_STORE/.version" 2>/dev/null)" != "$OC_VERSION" ]; then
    echo "[garza] opencode store built by $(cat "$OC_STORE/.version" 2>/dev/null || echo 'unknown'), resetting for $OC_VERSION"
    rm -rf "$OC_STORE"
  fi
  mkdir -p "$OC_STORE"
  [ -n "$OC_VERSION" ] && echo "$OC_VERSION" > "$OC_STORE/.version"
  if [ ! -f "$OC_STORE/opencode.db" ]; then
    opencode run "boot" >/dev/null 2>&1 || true
  fi
  for pair in $RAFT_OPENCODE_SESSIONS; do
    sid="${pair##*:}"
    # Schema differs by opencode version. Insert with whichever column set
    # the db actually has, so a version bump doesn't silently drop the seed.
    node -e "
      const {DatabaseSync} = require('node:sqlite');
      const db = new DatabaseSync('/root/.local/share/opencode/opencode.db');
      const cols = db.prepare('PRAGMA table_info(session)').all().map(c => c.name);
      const pid = (db.prepare('SELECT id FROM project LIMIT 1').get() || {}).id;
      const have = db.prepare('SELECT id FROM session WHERE id=?').get(process.argv[1]);
      const pick = (names) => names.filter(n => cols.includes(n));
      if (pid && !have) {
        const now = Date.now();
        const data = {
          id: process.argv[1],
          project_id: pid,
          workspace_id: null,
          parent_id: null,
          slug: 'raft-' + process.argv[1].slice(0, 8),
          directory: '/tmp',
          path: '/tmp',
          title: 'raft session',
          version: process.env.OC_VERSION || '1.14.17',
          time_created: now,
          time_updated: now,
        };
        const names = pick(Object.keys(data));
        const qs = names.map(() => '?').join(',');
        db.prepare('INSERT INTO session (' + names.join(',') + ') VALUES (' + qs + ')')
          .run(...names.map(n => data[n]));
        console.log('seeded session ' + process.argv[1] + ' cols=' + names.length);
      }
    " "$sid" || true
  done
fi

echo "[garza] starting raft-computer (reconnect loop)..."
# Forward daemon/runner/opencode logs to stdout so Zeabur runtime logs show why
# agents fail to start (they write to files, not stdout). Re-scan every 30s to
# pick up files created after boot (per-agent logs, opencode's own logs).
(
  sleep 15
  tailed=""
  while true; do
    new=$(find /root/.raft /root/.local/share/opencode/log -name "*.log" -type f 2>/dev/null)
    for f in $new; do
      case " $tailed " in *" $f "*) ;; *)
        tailed="$tailed $f"
        echo "[garza:tail] $f"
        tail -n 0 -F "$f" 2>/dev/null &
        ;;
      esac
    done
    # process snapshot catches spawned runtimes that never log
    ps -eo pid,ppid,etime,args 2>/dev/null | grep -E "opencode|pi " | grep -v grep | sed 's/^/[garza:ps] /' &
    wait_pid=$!
    sleep 30
    kill $wait_pid 2>/dev/null
  done
) &
while true; do
  raft-computer start --foreground 2>&1 || true
  echo "[garza] raft-computer exited; retrying in 10s"
  sleep 10
done
