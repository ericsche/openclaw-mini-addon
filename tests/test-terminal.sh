#!/usr/bin/env bash
# Terminal harness: the ingress web terminal must start, survive a crash, stay
# up while the gateway is broken, and stop on shutdown. Also checks that
# enable_terminal=false really disables it.
set -uo pipefail

SRC="$1"
SB=/tmp/ocmini-term
export SBROOT="$SB"

setup() {
  rm -rf "$SB"; mkdir -p "$SB/config" "$SB/data" "$SB/bin" "$SB/lib"

  cat > "$SB/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "run" ]; then
  if [ -f "$SBROOT/boom" ]; then exit 1; fi
  echo $$ > "$SBROOT/listener"
  trap 'rm -f "$SBROOT/listener"; exit 0' TERM INT
  while true; do sleep 0.3; done
fi
case "${1:-}" in --version) echo "2026.9.2-test" ;; esac
exit 0
EOF

  # Stands in for the real ttyd: marks the port as bound while alive.
  cat > "$SB/bin/ttyd" <<'EOF'
#!/usr/bin/env bash
echo $$ > "$SBROOT/ttyd"
trap 'rm -f "$SBROOT/ttyd"; exit 0' TERM INT
while true; do sleep 0.3; done
EOF

  # Reports both ports, so oc_listening can distinguish gateway from terminal.
  cat > "$SB/bin/ss" <<'EOF'
#!/usr/bin/env bash
[ -f "$SBROOT/listener" ] && echo "LISTEN 0 511 0.0.0.0:18789 0.0.0.0:* users:((\"node\",pid=$(cat "$SBROOT/listener"),fd=20))"
[ -f "$SBROOT/ttyd" ]     && echo "LISTEN 0 511 0.0.0.0:8099 0.0.0.0:* users:((\"ttyd\",pid=$(cat "$SBROOT/ttyd"),fd=7))"
exit 0
EOF

  printf '#!/usr/bin/env bash\nexit 1\n'  > "$SB/bin/pgrep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/npm"
  chmod +x "$SB"/bin/*
  cp "$(dirname "$0")/jq.exe" "$SB/bin/jq.exe" 2>/dev/null || true

  sandbox "$SRC/oc-common.sh" "$SB/lib/oc-common.sh"
  sandbox "$SRC/run.sh"       "$SB/bin/run.sh"
}

sandbox() {
  sed -e "s#/usr/local/lib/oc-common.sh#$SB/lib/oc-common.sh#g" \
      -e "s#/data/options.json#$SB/data/options.json#g" \
      -e "s#/config#$SB/config#g" "$1" > "$2"
  chmod +x "$2"
}

PASS=0; FAIL=0
check() {
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
  else echo "  FAIL  $1 (expected '$3', got '$2')"; FAIL=$((FAIL+1)); fi
}
term_up() { [ -f "$SB/ttyd" ] && echo yes || echo no; }
wait_term() { local i; for i in $(seq 1 "$2"); do [ "$(term_up)" = "$1" ] && return 0; sleep 1; done; return 1; }

echo "== enabled =="
setup
printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"lan","enable_terminal":true,"auto_update":false}\n' > "$SB/data/options.json"
export PATH="$SB/bin:$PATH"
"$SB/bin/run.sh" > "$SB/run.log" 2>&1 &
SUP=$!
wait_term yes 25
check "terminal started" "$(term_up)" "yes"

echo "== crash recovery =="
kill "$(cat "$SB/ttyd")" 2>/dev/null
wait_term no 5
wait_term yes 25
check "terminal restarted after crash" "$(term_up)" "yes"

echo "== stays up while the gateway is broken =="
touch "$SB/boom"
kill "$(cat "$SB/listener")" 2>/dev/null
sleep 12
check "terminal still up with gateway down" "$(term_up)" "yes"
check "gateway really down" "$([ -f "$SB/listener" ] && echo yes || echo no)" "no"

echo "== shutdown =="
kill -TERM $SUP 2>/dev/null
sleep 4
check "terminal stopped on SIGTERM" "$(term_up)" "no"
check "supervisor exited" "$(kill -0 $SUP 2>/dev/null && echo yes || echo no)" "no"

echo "== disabled =="
setup
printf '{"timezone":"Europe/Paris","gateway_port":18789,"gateway_bind_mode":"lan","enable_terminal":false,"auto_update":false}\n' > "$SB/data/options.json"
"$SB/bin/run.sh" > "$SB/run2.log" 2>&1 &
SUP2=$!
sleep 15
check "terminal not started when disabled" "$(term_up)" "no"
kill -TERM $SUP2 2>/dev/null; sleep 3

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
