#!/usr/bin/env bash
# Config persistence harness: user-owned settings must survive restarts, the
# add-on must only enforce what it needs, and it must not rewrite the file when
# nothing changed.
set -uo pipefail

SRC="$1"
SB=/tmp/ocmini-persist
export SBROOT="$SB"
CFG="$SB/config/.openclaw/openclaw.json"

rm -rf "$SB"; mkdir -p "$SB/config" "$SB/data" "$SB/bin" "$SB/lib"

cat > "$SB/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "run" ]; then
  echo $$ > "$SBROOT/listener"
  trap 'rm -f "$SBROOT/listener"; exit 0' TERM INT
  while true; do sleep 0.3; done
fi
case "${1:-}" in --version) echo "2026.9.2-test" ;; esac
exit 0
EOF
cat > "$SB/bin/ss" <<'EOF'
#!/usr/bin/env bash
[ -f "$SBROOT/listener" ] && echo "LISTEN 0 511 0.0.0.0:18789 0.0.0.0:* users:((\"node\",pid=$(cat "$SBROOT/listener"),fd=20))"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 1\n'  > "$SB/bin/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/npm"
chmod +x "$SB"/bin/*
cp "$(dirname "$0")/jq.exe" "$SB/bin/jq.exe" 2>/dev/null || true

printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"lan","gateway_token":"","allowed_origins":"http://192.168.1.50:18789","enable_terminal":false,"auto_update":false}\n' > "$SB/data/options.json"

sandbox() {
  sed -e "s#/usr/local/lib/oc-common.sh#$SB/lib/oc-common.sh#g" \
      -e "s#/data/options.json#$SB/data/options.json#g" \
      -e "s#/config#$SB/config#g" "$1" > "$2"
  chmod +x "$2"
}
sandbox "$SRC/oc-common.sh" "$SB/lib/oc-common.sh"
sandbox "$SRC/run.sh"       "$SB/bin/run.sh"
export PATH="$SB/bin:$PATH"

PASS=0; FAIL=0
check() {
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
  else echo "  FAIL  $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi
}
boot() {
  "$SB/bin/run.sh" > "$SB/run$1.log" 2>&1 &
  local pid=$!
  local i; for i in $(seq 1 25); do [ -f "$SB/listener" ] && break; sleep 1; done
  echo "$pid"
}
halt() { kill -TERM "$1" 2>/dev/null; sleep 3; }

echo "== first boot =="
P1="$(boot 1)"
check "config created"        "$([ -f "$CFG" ] && echo yes || echo no)" "yes"
check "option origin present" "$(jq -r '[.gateway.controlUi.allowedOrigins[]] | index("http://192.168.1.50:18789") != null' "$CFG")" "true"
halt "$P1"

echo "== user edits the config by hand =="
TMP="$(mktemp)"
jq '.agents = {"defaults": {"model": {"primary": "anthropic/claude-opus-4-6"}}}
    | .channels = {"telegram": {"enabled": true, "botToken": "keepme"}}
    | .gateway.controlUi.allowedOrigins += ["https://manual.example.com"]
    | .gateway.controlUi.basePath = "/openclaw"' "$CFG" > "$TMP"
mv "$TMP" "$CFG"

P2="$(boot 2)"
check "agents preserved"           "$(jq -r '.agents.defaults.model.primary' "$CFG")" "anthropic/claude-opus-4-6"
check "channels preserved"         "$(jq -r '.channels.telegram.botToken' "$CFG")" "keepme"
check "manual origin preserved"    "$(jq -r '[.gateway.controlUi.allowedOrigins[]] | index("https://manual.example.com") != null' "$CFG")" "true"
check "other controlUi key kept"   "$(jq -r '.gateway.controlUi.basePath' "$CFG")" "/openclaw"
check "enforced mode still local"  "$(jq -r '.gateway.mode' "$CFG")" "local"
check "enforced bind still lan"    "$(jq -r '.gateway.bind' "$CFG")" "lan"
check "generated token kept"       "$(jq -r '.gateway.auth.token | length > 0' "$CFG")" "true"
halt "$P2"

echo "== idempotent boot =="
BEFORE="$(md5sum "$CFG" | cut -d' ' -f1)"
rm -f "$CFG.addon.bak"
P3="$(boot 3)"
AFTER="$(md5sum "$CFG" | cut -d' ' -f1)"
check "config byte-identical"      "$AFTER" "$BEFORE"
check "no needless backup written" "$([ -f "$CFG.addon.bak" ] && echo yes || echo no)" "no"
check "logged as untouched"        "$(grep -c 'left untouched' "$SB/run3.log")" "1"
halt "$P3"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
