# Tests

Stubbed integration tests for the supervisor and the maintenance mode. They replace
`openclaw`, `ss`, `pgrep` and `npm` with fakes, then run the real `run.sh` and
`oc-maint` against a sandboxed `/config`. No container and no OpenClaw install needed.

```bash
./tests/run-all.sh ./openclaw_mini      # everything
./tests/test-supervisor.sh ./openclaw_mini   # or one at a time
```

Requires `bash`, `jq`, `sed`, `grep` and `seq`. Each script exits non-zero on failure.

| Script | Covers |
|---|---|
| `test-supervisor.sh` | Boot, config merge, token generation, crash recovery, `oc-maint stop/start/doctor/status`, SIGTERM shutdown |
| `test-failure-path.sh` | Gateway refusing to start: fast-fail on non-zero exit, backoff, no `set -e` death, recovery, loopback bind writing no token |
| `test-terminal.sh` | Ingress terminal start, crash recovery, staying up while the gateway is down, shutdown, and `enable_terminal: false` |
| `test-auto-approve.sh` | Control UI pairing: approving pending requests, ignoring approved ones, no duplicate approvals |
| `test-config-persistence.sh` | User settings surviving restarts, allowed-origin merging, idempotent boots leaving the file untouched |

The `cp jq.exe` line in each script is a no-op on Linux; it exists so the suite can
also run under Git Bash on Windows with a local `jq.exe`.
