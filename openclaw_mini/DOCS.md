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

### `allowed_origins`

Comma-separated list of browser origins allowed to open the Control UI, for example:

```
http://192.168.1.50:18789
```

OpenClaw rejects any origin that is not listed, with:

```
origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)
```

Use the exact scheme, host and port shown in your browser's address bar, with no
trailing slash. These are always allowed without configuration:
`http://127.0.0.1:<port>`, `http://localhost:<port>`, `http://homeassistant:<port>`
and `http://homeassistant.local:<port>`.

> The add-on owns `gateway.controlUi.allowedOrigins` and rewrites it on every start.
> Add origins here, not with `openclaw config set`, or they will be lost on restart.

### `enable_terminal`

Serves a web terminal on the **OpenClaw** entry in the Home Assistant sidebar, through
Ingress. Enabled by default. This is how you reach `oc-maint`.

Turning it off removes the only built-in way to administer the add-on. Do that only if
you have Docker access, or if you also enable `auto_approve_devices`.

### `auto_approve_devices`

Approves Control UI browser pairing requests automatically, so you never need a shell.

**Why this exists:** it lets you pair a browser without opening a shell. It is the
fallback when `enable_terminal` is off and you have no Docker access — for example
with Home Assistant's official *Terminal & SSH* add-on, which cannot `docker exec`.

⚠️ **Security:** with this on, any browser that reaches the port and presents the
gateway token is granted operator access without confirmation. Only enable it on a
trusted network. Leave it off if you can reach a shell.

Approved request IDs are remembered for the lifetime of the container, so repeated
upgrade requests are not resubmitted in a loop.

### `auto_update`

When `true`, `openclaw@latest` is installed on every start, before the gateway boots.
This is the only safe moment to update: nothing owns the state lock yet.

Leave it `false` if you prefer to update deliberately with `oc-maint update`.

## Maintenance

Some OpenClaw commands require the gateway to be stopped. This add-on can actually do
that — its supervisor honours a maintenance flag instead of restarting the gateway
behind your back.

### Getting a shell

Click **OpenClaw** in the Home Assistant sidebar. The add-on serves a web terminal
through Ingress, so it inherits Home Assistant authentication, needs no exposed port,
and requires neither an SSH add-on nor Docker access.

The session runs in `tmux`, so closing the tab does not kill a long-running command.
Reopening the terminal reattaches to it.

If you would rather use Docker:

```bash
docker exec -it $(docker ps --format '{{.Names}}' | grep openclaw_mini) bash
```

Note that Home Assistant's official *Terminal & SSH* add-on has **no Docker access**;
only the community *Advanced SSH & Web Terminal* with protection mode disabled does.

The container sets `HOME=/config` and puts `/config/.node_global/bin` on `PATH`, so
`openclaw` and `oc-maint` target the live state without extra environment variables.

### Commands

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
| `oc-maint devices` | List pending and paired Control UI devices |
| `oc-maint approve <id>` | Approve a pending device pairing request |

`oc-maint doctor` and `oc-maint update` always resume the supervisor, even if the
command fails or you press Ctrl+C.

## Pairing your browser

The first time you open the Control UI from anything other than loopback, OpenClaw
asks for a one-time approval and shows a request ID. This is a security feature and
cannot be disabled.

```bash
oc-maint devices                                     # find the pending request
oc-maint approve 77e3e1c6-3c2a-4096-a1c1-fbff57f77f8c
```

Each browser profile gets its own device ID, so clearing browser data means pairing
again.

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

**"origin not allowed" when opening the dashboard.**
Add the URL you use to the `allowed_origins` option, scheme and port included, for
example `http://192.168.1.50:18789`, then restart the add-on.

**Connection refused right after starting.**
The gateway can take 20-30 seconds to initialise. The supervisor waits up to 90
seconds before declaring a failure.
