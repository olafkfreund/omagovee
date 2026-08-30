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
  primary doc that renders without JavaScript. Verified working against H615A.
  If a model ignores a LAN command, delete its entry from
  `~/.cache/omagovee/lan.json` to force the cloud path.
- **LAN writes are read back.** UDP is unacknowledged, and a dropped `turn` was
  observed reporting success while the light stayed off. Every power/brightness
  command is confirmed with a `devStatus` (~20ms) and resent once before the
  command is allowed to claim it worked.
- **Cloud state lags LAN commands.** After a LAN write the cloud keeps serving
  the old value for a few seconds, which is why state is read over LAN first
  whenever an ip is known.

## Bluetooth

Every Govee device here also advertises BLE at `wifi_mac + 2`, named e.g.
`GBK_H615A_6E1D` or `GVH600C7C56`, and exposes Govee's control service
`00010203-0405-0607-0809-0a0b0c0d1910`, characteristic `…2b11`
(`write-without-response`). Twenty-byte packets: `0x33`, command
(`01` power, `04` brightness, `05` colour), payload, zero padding, XOR checksum
of the first 19 bytes.

Confirmed working on the H615A strips — but **not implemented here**, on
purpose. BLE only reaches one device at a time, needs a live connection BlueZ
keeps dropping when idle, and is a reverse-engineered protocol rather than a
published API. Once a device is on Wi-Fi the LAN path is faster and more
reliable. Worth revisiting only for a device that can never join Wi-Fi.
- The widget draws from `~/.cache/omagovee/state.json`, written after each
  action — an optimistic value, not a live query. Changing a light from the
  phone will not update the bar until the next command from here. Deliberate:
  the cloud state endpoint allows 30 req/min/device and a redraw poll would eat
  that in seconds.
- Device list is cached 24h (`~/.cache/omagovee/devices.json`); delete it after
  adding a lamp.
