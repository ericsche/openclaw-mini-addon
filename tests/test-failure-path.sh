#!/usr/bin/env bash
# Failure-path harness: gateway refuses to start, then recovers.
# Guards against `set -e` killing the supervisor inside the backoff branch.
set -uo pipefail

SRC="$1"
SB=/tmp/ocmini-fail
export SBROOT="$SB"

rm -rf "$SB"; mkdir -p "$SB/config" "$SB/data" "$SB/bin" "$SB/lib"

cat > "$SB/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "run" ]; then
  if [ -f "$SBROOT/boom" ]; then exit 1; fi
  echo $$ > "$SBROOT/listener"
  trap 'rm -f "$SBROOT/listener"; exit 0' TERM INT
  while true; do sleep 0.3; done
fi
case "${1:-}" in
  --version) echo "2026.9.2-test" ;;
  doctor)    echo "stub doctor"; exit 0 ;;
esac
exit 0
EOF
cat > "$SB/bin/ss" <<'EOF'
#!/usr/bin/env bash
if [ -f "$SBROOT/listener" ]; then
  echo "LISTEN 0 511 0.0.0.0:18789 0.0.0.0:* users:((\"node\",pid=$(cat "$SBROOT/listener"),fd=20))"
fi
EOF
printf '#!/usr/bin/env bash\nexit 1\n'    > "$SB/bin/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n'   > "$SB/bin/npm"
chmod +x "$SB"/bin/*
cp "$(dirname "$0")/jq.exe" "$SB/bin/jq.exe" 2>/dev/null || true
printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"loopback","gateway_token":"","enable_terminal":false,"auto_update":false}\n' > "$SB/data/options.json"

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

touch "$SB/boom"
"$SB/bin/run.sh" > "$SB/run.log" 2>&1 &
SUP=$!

# 90s startup budget per attempt would be too slow to observe, so we only need
# to prove the supervisor is still alive and looping while the gateway fails.
sleep 20
check "supervisor survives a failing gateway" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"
check "no listener yet" "$([ -f "$SB/listener" ] && echo yes || echo no)" "no"

# No token was generated because bind=loopback -> auth stays untouched.
check "loopback bind writes no token" "$(jq -r '.gateway.auth.token // "none"' "$SB/config/.openclaw/openclaw.json")" "none"
check "bind persisted" "$(jq -r '.gateway.bind' "$SB/config/.openclaw/openclaw.json")" "loopback"

rm -f "$SB/boom"
for i in $(seq 1 120); do [ -f "$SB/listener" ] && break; sleep 1; done
check "recovers once the gateway can start" "$([ -f "$SB/listener" ] && echo yes || echo no)" "yes"
check "supervisor still alive after recovery" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "yes"

kill -TERM $SUP 2>/dev/null; sleep 3
check "clean shutdown" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "no"

echo
echo "--- supervisor log ---"
cat "$SB/run.log"
echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
