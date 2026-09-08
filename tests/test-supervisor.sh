#!/usr/bin/env bash
# Harness: runs run.sh + oc-maint against stubbed ss/pgrep/openclaw/npm.
# Verifies supervision, maintenance mode and resume, with no real container.
set -uo pipefail

SRC="$1"
SB=/tmp/ocmini-test
export SBROOT="$SB"

rm -rf "$SB"
mkdir -p "$SB/config" "$SB/data" "$SB/bin" "$SB/lib"

# --- stubs -------------------------------------------------------------------
cat > "$SB/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "run" ]; then
  if [ -f "$SBROOT/boom" ]; then exit 1; fi
  sleep 2                      # simulate slow startup
  echo $$ > "$SBROOT/listener"
  trap 'rm -f "$SBROOT/listener"; exit 0' TERM INT
  while true; do sleep 0.3; done
fi
case "${1:-}" in
  --version) echo "2026.9.2-test" ;;
  doctor)    echo "stub doctor: repaired"; exit 0 ;;
esac
exit 0
EOF

cat > "$SB/bin/ss" <<'EOF'
#!/usr/bin/env bash
if [ -f "$SBROOT/listener" ]; then
  echo "LISTEN 0 511 0.0.0.0:18789 0.0.0.0:* users:((\"node\",pid=$(cat "$SBROOT/listener"),fd=20))"
fi
EOF

printf '#!/usr/bin/env bash\nexit 1\n'                > "$SB/bin/pgrep"
printf '#!/usr/bin/env bash\necho "npm $*"\nexit 0\n' > "$SB/bin/npm"
chmod +x "$SB"/bin/*
cp "$(dirname "$0")/jq.exe" "$SB/bin/jq.exe" 2>/dev/null || true

printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"lan","gateway_token":"","auto_update":false}\n' > "$SB/data/options.json"

# --- sandboxed copies of the real scripts ------------------------------------
sandbox() {
  sed -e "s#/usr/local/lib/oc-common.sh#$SB/lib/oc-common.sh#g" \
      -e "s#/data/options.json#$SB/data/options.json#g" \
      -e "s#/config#$SB/config#g" "$1" > "$2"
  chmod +x "$2"
}
sandbox "$SRC/oc-common.sh" "$SB/lib/oc-common.sh"
sandbox "$SRC/run.sh"       "$SB/bin/run.sh"
sandbox "$SRC/oc-maint"     "$SB/bin/oc-maint"

export PATH="$SB/bin:$PATH"

PASS=0; FAIL=0
check() {
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
  else echo "  FAIL  $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi
}
listening() { [ -f "$SB/listener" ] && echo yes || echo no; }
wait_for() { local i; for i in $(seq 1 "$2"); do [ "$(listening)" = "$1" ] && return 0; sleep 1; done; return 1; }

echo "== boot =="
"$SB/bin/run.sh" > "$SB/run.log" 2>&1 &
SUP=$!
wait_for yes 25
check "gateway came up" "$(listening)" "yes"
check "supervisor alive" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"
check "gateway.mode written" "$(jq -r '.gateway.mode' "$SB/config/.openclaw/openclaw.json")" "local"
check "token generated for lan bind" "$(jq -r '.gateway.auth.token | length > 0' "$SB/config/.openclaw/openclaw.json")" "true"

echo "== crash recovery =="
kill "$(cat "$SB/listener")" 2>/dev/null
wait_for no 5
wait_for yes 25
check "auto-restarted after crash" "$(listening)" "yes"
check "supervisor still alive" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"

echo "== maintenance =="
"$SB/bin/oc-maint" stop > "$SB/stop.log" 2>&1
check "stop exit code" "$?" "0"
check "gateway down" "$(listening)" "no"
sleep 8
check "supervisor did NOT resurrect it" "$(listening)" "no"
check "supervisor still alive during maintenance" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"

echo "== doctor (stop -> fix -> resume) =="
"$SB/bin/oc-maint" start > "$SB/start.log" 2>&1
check "resumed" "$(listening)" "yes"
"$SB/bin/oc-maint" doctor > "$SB/doctor.log" 2>&1
check "doctor exit code" "$?" "0"
check "doctor ran" "$(grep -c 'stub doctor: repaired' "$SB/doctor.log")" "1"
check "gateway back after doctor" "$(listening)" "yes"
check "maintenance flag cleared" "$([ -f /tmp/openclaw.maintenance ] && echo yes || echo no)" "no"

echo "== status =="
"$SB/bin/oc-maint" status > "$SB/status.log" 2>&1
check "status exit code" "$?" "0"
check "status reports active listener" "$(grep -c 'Listener      : active' "$SB/status.log")" "1"

echo "== shutdown =="
kill -TERM $SUP 2>/dev/null
sleep 4
check "supervisor exited on SIGTERM" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "no"
check "gateway stopped on shutdown" "$(listening)" "no"

pkill -f "$SB/bin" 2>/dev/null
echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
