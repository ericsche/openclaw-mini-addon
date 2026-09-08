#!/usr/bin/env bash
# OpenClaw Mini add-on entrypoint and gateway supervisor.
set -euo pipefail

# shellcheck source=oc-common.sh
. /usr/local/lib/oc-common.sh

OPTIONS_FILE=/data/options.json

log() { echo "[openclaw-mini] $*"; }

opt() {
  if [ -f "$OPTIONS_FILE" ]; then
    jq -r "$1 // empty" "$OPTIONS_FILE" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------- options ---
TIMEZONE="$(opt '.timezone')";              TIMEZONE="${TIMEZONE:-Europe/Paris}"
GW_PORT="$(opt '.gateway_port')";           GW_PORT="${GW_PORT:-18789}"
GW_BIND="$(opt '.gateway_bind_mode')";      GW_BIND="${GW_BIND:-lan}"
GW_TOKEN="$(opt '.gateway_token')"
AUTO_UPDATE="$(opt '.auto_update')";        AUTO_UPDATE="${AUTO_UPDATE:-false}"

if [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  echo "$TIMEZONE" > /etc/timezone
  export TZ="$TIMEZONE"
fi

oc_export_env
mkdir -p "$OC_STATE_DIR" "$OC_WORKSPACE" "$OC_NODE_GLOBAL"

# Global npm installs land in /config so `oc-maint update` survives rebuilds.
npm config set prefix "$OC_NODE_GLOBAL" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- updates ---
# Updating here is safe: the gateway is not running yet, so nothing owns the
# state lock. This is why `openclaw update` must never be run by hand later.
if [ "$AUTO_UPDATE" = "true" ]; then
  log "auto_update enabled; installing openclaw@latest"
  npm install -g openclaw@latest || log "WARN: update failed; keeping the current version"
fi

# ----------------------------------------------------------------- config ---
if [ ! -f "$OC_CONFIG" ]; then
  log "Bootstrapping $OC_CONFIG"
  echo '{}' > "$OC_CONFIG"
fi

EXISTING_TOKEN="$(jq -r '.gateway.auth.token // empty' "$OC_CONFIG" 2>/dev/null || true)"
if [ -z "$GW_TOKEN" ]; then
  GW_TOKEN="$EXISTING_TOKEN"
fi

# The gateway refuses to bind beyond loopback without auth, so guarantee a token.
if [ "$GW_BIND" != "loopback" ] && [ -z "$GW_TOKEN" ]; then
  GW_TOKEN="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
  log "No gateway token set; generated one. Retrieve it later with: oc-maint token"
  log "Gateway token: $GW_TOKEN"
fi

CONFIG_TMP="$(mktemp)"
jq \
  --argjson port "$GW_PORT" \
  --arg bind "$GW_BIND" \
  --arg token "$GW_TOKEN" '
  .gateway = ((.gateway // {})
    | .mode = "local"
    | .port = $port
    | .bind = $bind
    | if $token == "" then .
      else .auth = ((.auth // {}) | .mode = "token" | .token = $token)
      end)
' "$OC_CONFIG" > "$CONFIG_TMP"
mv "$CONFIG_TMP" "$OC_CONFIG"

log "OpenClaw $(openclaw --version 2>/dev/null || echo unknown) | port=$GW_PORT bind=$GW_BIND"
log "Operator commands: oc-maint status|stop|start|restart|doctor|update|token"

# ------------------------------------------------------------- supervisor ---
GW_WRAPPER=""
SHUTTING_DOWN=false

# Interruptible sleep: a bare `sleep` would delay SIGTERM handling.
nap() { sleep "$1" & wait $! 2>/dev/null || true; }

stop_gateway() {
  local pid
  pid="$(oc_gateway_pid "$GW_PORT" || true)"
  if [ -z "$pid" ]; then
    return 0
  fi
  log "Stopping gateway (PID $pid)"
  kill "$pid" 2>/dev/null || true
  local i
  for i in $(seq 1 20); do
    if ! oc_listening "$GW_PORT"; then
      return 0
    fi
    sleep 1
  done
  kill -9 "$pid" 2>/dev/null || true
}

on_term() {
  SHUTTING_DOWN=true
  log "Shutdown requested"
  stop_gateway
  exit 0
}
trap on_term TERM INT

start_gateway() {
  log "Starting gateway on :$GW_PORT"
  openclaw gateway run < /dev/null &
  GW_WRAPPER=$!

  local i rc
  for i in $(seq 1 90); do
    if [ "$SHUTTING_DOWN" = true ]; then
      return 1
    fi
    if [ -f "$OC_MAINT_FLAG" ]; then
      return 1
    fi
    if oc_listening "$GW_PORT"; then
      log "Gateway is listening on :$GW_PORT"
      return 0
    fi
    # A zero exit means the wrapper forked the real daemon, so keep waiting for
    # the port. A non-zero exit is a hard failure worth reporting immediately.
    if [ -n "$GW_WRAPPER" ] && ! kill -0 "$GW_WRAPPER" 2>/dev/null; then
      rc=0
      wait "$GW_WRAPPER" 2>/dev/null || rc=$?
      GW_WRAPPER=""
      if [ "$rc" -ne 0 ]; then
        log "Gateway exited with code $rc before binding :$GW_PORT"
        return 1
      fi
    fi
    nap 1
  done
  log "Gateway did not bind :$GW_PORT within 90s"
  return 1
}

# Reap the wrapper once it exits, without ever blocking the supervisor.
reap_wrapper() {
  if [ -n "$GW_WRAPPER" ] && ! kill -0 "$GW_WRAPPER" 2>/dev/null; then
    wait "$GW_WRAPPER" 2>/dev/null || true
    GW_WRAPPER=""
  fi
}

FAIL_STREAK=0

while true; do
  reap_wrapper

  # Maintenance mode: oc-maint owns the gateway, do not fight it.
  if [ -f "$OC_MAINT_FLAG" ]; then
    nap 2
    continue
  fi

  if oc_listening "$GW_PORT"; then
    FAIL_STREAK=0
    nap 5
    continue
  fi

  if [ "$FAIL_STREAK" -gt 0 ]; then
    BACKOFF=$(( FAIL_STREAK * 5 ))
    if [ "$BACKOFF" -gt 60 ]; then
      BACKOFF=60
    fi
    log "Gateway is down (failure #$FAIL_STREAK); retrying in ${BACKOFF}s"
    nap "$BACKOFF"
    if [ -f "$OC_MAINT_FLAG" ]; then
      continue
    fi
  fi

  if start_gateway; then
    FAIL_STREAK=0
  else
    FAIL_STREAK=$(( FAIL_STREAK + 1 ))
    if [ "$FAIL_STREAK" -eq 2 ]; then
      log "Gateway will not start. Open the add-on terminal and run: oc-maint doctor"
    fi
  fi
done
