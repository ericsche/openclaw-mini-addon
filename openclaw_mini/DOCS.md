# OpenClaw Mini

Runs the OpenClaw gateway inside Home Assistant, with a working maintenance mode.

## First start

1. Set your `timezone`.
2. Leave `gateway_bind_mode` on `lan` so you can reach the dashboard from your network.
3. Start the add-on and open the **Log** tab.
4. Copy the generated `Gateway token:` line — you need it to connect.
5. Open `http://<home-assistant-ip>:18789/`.

Lost the token later? Run `oc-maint token` in the add-on shell.

## Options

### `timezone`

Container timezone, e.g. `Europe/Paris`.

### `gateway_port`

Port for the gateway WebSocket and the dashboard. Also the host port. Default `18789`.

### `gateway_bind_mode`

- `lan` — reachable from your network. Requires a token (generated if you leave one empty).
- `loopback` — only reachable from inside the container. The mapped port will **not** work.

### `gateway_token`

Shared auth token. Leave empty to have one generated on first start and stored in
`/config/.openclaw/openclaw.json`.

### `auto_update`

When `true`, `openclaw@latest` is installed on every start, before the gateway boots.
This is the only safe moment to update: nothing owns the state lock yet.

Leave it `false` if you prefer to update deliberately with `oc-maint update`.

## Maintenance

Some OpenClaw commands require the gateway to be stopped. This add-on can actually do
that — its supervisor honours a maintenance flag instead of restarting the gateway
behind your back.

From a shell in the add-on container:

| Command | Effect |
|---|---|
| `oc-maint status` | Port, PID, listener state, maintenance state, version |
| `oc-maint stop` | Stop the gateway and pause the supervisor |
| `oc-maint start` | Resume the supervisor and wait for the gateway |
| `oc-maint restart` | `stop` then `start` |
| `oc-maint doctor` | Stop, run `openclaw doctor --fix`, restart |
| `oc-maint update` | Stop, install `openclaw@latest`, repair, restart |
| `oc-maint token` | Print the gateway auth token |

`oc-maint doctor` and `oc-maint update` always resume the supervisor, even if the
command fails or you press Ctrl+C.

## Commands to avoid

- `openclaw update` — it drives service management and a post-update doctor that
  cannot succeed in a container. It ends in `triage`. Use `oc-maint update`.
- `openclaw gateway stop` / `openclaw gateway restart` — there is no systemd in this
  container, so OpenClaw's service commands do not apply. Use `oc-maint`.
- Exporting `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH` or `OPENCLAW_HOME` — OpenClaw
  then treats the state tree as isolated and silently disables doctor repairs.
  `HOME=/config` is set for you and is all that is needed.

## Persistent data

Everything under `/config` survives add-on updates and rebuilds:

- `/config/.openclaw` — configuration, credentials, sessions, agents
- `/config/clawd` — the agent workspace
- `/config/.node_global` — npm globals, so `oc-maint update` sticks

`.node_global`, `.npm` and `.cache` are excluded from Home Assistant backups because
they are regenerable.

## Troubleshooting

**The add-on log repeats "Gateway is down (failure #N)".**
The gateway cannot start. Run `oc-maint doctor` from the add-on shell; it stops the
gateway properly first, which is exactly what `doctor` needs.

**"Maintenance : ON" in `oc-maint status`.**
A previous `oc-maint stop` was never resumed. Run `oc-maint start`.

**Cannot reach the dashboard from another machine.**
Check that `gateway_bind_mode` is `lan`, not `loopback`, then restart the add-on.

**Connection refused right after starting.**
The gateway can take 20-30 seconds to initialise. The supervisor waits up to 90
seconds before declaring a failure.
