# omagovee

Govee light control from the Omarchy desktop — a command, an interactive
picker, and a bar widget. Sibling of [omagog](../omagog).

Govee publishes two open APIs and this uses both, per device:

| Transport | Needs | Why |
|---|---|---|
| LAN (UDP) | "LAN Control" enabled per device in the Govee Home app | Instant, no rate limit, works with the internet down |
| Cloud (`openapi.api.govee.com`) | An API key | Every model, and the only way to enumerate devices |

`scan` writes the LAN cache; anything it found is driven over UDP, everything
else falls back to the cloud. No account of ours, no broker, no MQTT.

## Parts

| Path | What |
|---|---|
| `bin/omarchy-govee` | The whole client — scan, list, on/off/toggle, brightness, colour |
| `bin/omarchy-cmd-lights` | `gum` picker: device → action → value; for the menu row and the widget |
| `plugin/` | Omarchy bar widget: left-click toggles, right-click opens the picker |
| `test_omagovee.py` | `python3 test_omagovee.py` — payload and colour logic |

Python stdlib only. No `jq`, no `curl`, no pip install — a bar-widget click has
to start fast.

## Setup

Govee Home app → Profile → ⚙️ Settings → **Apply for API Key**. It arrives by
email. One key per account: re-applying invalidates the old one.

```bash
mkdir -p ~/.config/omagovee
echo 'YOUR-KEY' > ~/.config/omagovee/api-key   # or export GOVEE_API_KEY
chmod 600 ~/.config/omagovee/api-key

omarchy-govee scan          # find LAN-enabled devices (optional but faster)
omarchy-govee list
omarchy-govee default desk  # which device bare commands hit
```

## Use

```bash
omarchy-govee toggle
omarchy-govee brightness 40
omarchy-govee color warm
omarchy-govee color ff8800 "Living room"
omarchy-govee state
```

## Install (NixOS / Nixarchy)

Same shape as omagog: the scripts go in `home/shell/`, the menu row in
`programs.nixarchy.menu.extraEntries`, the key in an agenix secret exposed as
`GOVEE_API_KEY`. The widget is a plain user plugin:

```bash
cp -r plugin ~/.config/omarchy/plugins/olafkfreund.govee
omarchy plugin enable olafkfreund.govee
omarchy restart shell
```

## Notes

- **A scan that finds nothing is usually the network, not the lamp.** Multicast
  gets dropped by consumer routers, so `scan` also sweeps the /24 by unicast,
  and binds explicitly to the route-selected interface — on a machine with
  docker bridges an unbound multicast send leaves the wrong NIC and finds zero
  devices with no error. UDP 4001/4003 outbound, 4002 inbound.
- Models without a "LAN Control" toggle in the app are cloud-only. That is a
  firmware limit, not a bug here — they still work, just over the internet.
- The LAN command names (`turn`, `brightness`, `colorwc`, `devStatus`) come
  from Govee's WLAN guide as reproduced by community integrations, not from a
  primary doc that renders without JavaScript. If a model ignores a LAN command,
  delete its entry from `~/.cache/omagovee/lan.json` to force the cloud path.
- The widget draws from `~/.cache/omagovee/state.json`, written after each
  action — an optimistic value, not a live query. Changing a light from the
  phone will not update the bar until the next command from here. Deliberate:
  the cloud state endpoint allows 30 req/min/device and a redraw poll would eat
  that in seconds.
- Device list is cached 24h (`~/.cache/omagovee/devices.json`); delete it after
  adding a lamp.
