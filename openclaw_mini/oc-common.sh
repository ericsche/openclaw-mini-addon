# shellcheck shell=bash
# Shared helpers for run.sh (supervisor) and oc-maint (operator CLI).

OC_STATE_DIR=/config/.openclaw
OC_CONFIG="$OC_STATE_DIR/openclaw.json"
OC_WORKSPACE=/config/clawd
OC_NODE_GLOBAL=/config/.node_global
OC_MAINT_FLAG=/tmp/openclaw.maintenance

# OpenClaw derives its canonical state directory from the account home.
# Set HOME only. Exporting OPENCLAW_STATE_DIR / OPENCLAW_CONFIG_PATH / OPENCLAW_HOME
# makes OpenClaw classify the tree as "isolated state" and silently disable
# service management, doctor repairs and self-update.
oc_export_env() {
  export HOME=/config
  export XDG_CONFIG_HOME=/config
  export PATH="$OC_NODE_GLOBAL/bin:$PATH"
  unset OPENCLAW_HOME OPENCLAW_STATE_DIR OPENCLAW_CONFIG_PATH OPENCLAW_WORKSPACE_DIR
}

oc_port() {
  local port=""
  if [ -f "$OC_CONFIG" ]; then
    port="$(jq -r '.gateway.port // empty' "$OC_CONFIG" 2>/dev/null || true)"
  fi
  echo "${port:-18789}"
}

oc_listening() {
  ss -tln 2>/dev/null | grep -q ":${1} "
}

# Resolve the live gateway PID. The port owner is authoritative because
# `openclaw gateway run` is a wrapper that may fork the real daemon.
oc_gateway_pid() {
  local port="$1" pid=""

  pid="$(ss -tlnp 2>/dev/null | grep ":${port} " | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)"
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  pid="$(pgrep -f 'openclaw-gateway' 2>/dev/null | head -1 || true)"
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  pid="$(pgrep -f 'openclaw gateway run' 2>/dev/null | head -1 || true)"
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  return 1
}
