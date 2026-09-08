#!/usr/bin/env bash
# Auto-approve harness: proves the opt-in Control UI pairing loop approves a
# pending request exactly once and ignores already-approved entries.
set -uo pipefail

SRC="$1"
SB=/tmp/ocmini-approve
export SBROOT="$SB"

rm -rf "$SB"; mkdir -p "$SB/config" "$SB/data" "$SB/bin" "$SB/lib"
rm -f /tmp/openclaw-approved-devices

cat > "$SB/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "run" ]; then
  echo $$ > "$SBROOT/listener"
  trap 'rm -f "$SBROOT/listener"; exit 0' TERM INT
  while true; do sleep 0.3; done
fi
if [ "${1:-}" = "devices" ] && [ "${2:-}" = "list" ]; then
  # Nested shape on purpose: the extraction must not assume a flat payload.
  cat <<'JSON'
{ "pending": [ { "requestId": "aaaa-1111", "status": "pending" } ],
  "devices": [ { "requestId": "bbbb-2222", "status": "approved" } ] }
JSON
  exit 0
fi
if [ "${1:-}" = "devices" ] && [ "${2:-}" = "approve" ]; then
  echo "${3:-}" >> "$SBROOT/approved"
  exit 0
fi
case "${1:-}" in
  --version) echo "2026.9.2-test" ;;
esac
exit 0
EOF
cat > "$SB/bin/ss" <<'EOF'
#!/usr/bin/env bash
if [ -f "$SBROOT/listener" ]; then
  echo "LISTEN 0 511 0.0.0.0:18789 0.0.0.0:* users:((\"node\",pid=$(cat "$SBROOT/listener"),fd=20))"
fi
EOF
printf '#!/usr/bin/env bash\nexit 1\n'  > "$SB/bin/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/npm"
chmod +x "$SB"/bin/*
cp "$(dirname "$0")/jq.exe" "$SB/bin/jq.exe" 2>/dev/null || true

printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"lan","gateway_token":"T","allowed_origins":"","auto_approve_devices":true,"auto_update":false}\n' > "$SB/data/options.json"

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

# grep -c prints 0 AND exits 1 on no match, so `|| echo 0` would double the value.
count() {
  if [ -f "$SB/approved" ]; then
    grep -c "$1" "$SB/approved" 2>/dev/null | head -1
  else
    echo 0
  fi
}

"$SB/bin/run.sh" > "$SB/run.log" 2>&1 &
SUP=$!
for i in $(seq 1 30); do [ -f "$SB/approved" ] && break; sleep 1; done

check "pending request approved"        "$(count 'aaaa-1111')" "1"
check "approved entry NOT re-approved"  "$(count 'bbbb-2222')" "0"

# Two more poll cycles must not re-approve the same id.
sleep 35
check "no duplicate approvals"          "$(count 'aaaa-1111')" "1"
check "supervisor still alive"          "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"

kill -TERM $SUP 2>/dev/null; sleep 3
echo
echo "--- log ---"; grep -i approv "$SB/run.log" || true
echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
