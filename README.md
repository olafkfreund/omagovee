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
| `plugin/` | Omarchy bar widget + dropdown panel: scenes, rooms, per-device toggle/brightness/colour |
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
omarchy-govee state

# groups: a device name, room:<name>, or all
omarchy-govee rooms --auto          # infer rooms from the name prefixes
omarchy-govee rooms office shelf1 shelf2
omarchy-govee off room:hall
omarchy-govee color red all

# scenes live in ~/.config/omagovee/scenes.json and are yours to edit
omarchy-govee scene                 # list
omarchy-govee scene meeting         # all lights red at 60%
```

### Scenes

`scenes.json` is a list of steps per scene; each step names a target and any of
`power`, `brightness`, `color`:

```json
{ "meeting": [ { "target": "room:office", "power": 1, "color": "red", "brightness": 60 } ] }
```

Power is applied before colour and brightness — setting a colour on a dark lamp
is invisible otherwise.

Nothing here runs a scene for you. To make "red while in a meeting" automatic,
hang it off the calendar you already have via `gog`:

```bash
gog events today --json | jq -e '.[] | select(.now)' >/dev/null \
  && omarchy-govee scene meeting || omarchy-govee scene evening
```

in a user timer. A daemon that watches for you is deliberately not built yet.

### Panel

The bar icon left-clicks to open a dropdown: scene buttons, one section per
room with all-on/all-off, and a row per device with a toggle. Clicking a device
name expands a brightness slider and colour swatches. Right-clicking the bar
icon toggles the default device without opening anything.

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
- The panel and the bar icon both read `omarchy-govee dump`, which fetches all
  device states concurrently (~1.2s for 15 devices; serially it would be five).
  It refreshes at startup, when the panel opens, after every action, and once a
  minute while closed. An earlier design cached state in a file the widget
  watched with inotify — that broke silently, because the CLI's atomic writes
  swap the inode out from under the watch, and a second copy of the state is a
  second thing that can be wrong.
- **The plugin's QML entry file must be named `Govee.qml`.** Naming it
  `Panel.qml` or `GoveePanel.qml` makes Quickshell fail the widget with "File
  name case mismatch". Relatedly, the `Panel` base type from `qs.Ui` resolves
  only inside the shell's own module path, so a third-party plugin has to build
  its popup on `BarWidget` + `KeyboardPanel` instead.
- Device list is cached 24h (`~/.cache/omagovee/devices.json`); delete it after
  adding a lamp.


## Friendly names and rooms

`label` gives a device a name for the panel only — the device keeps the name
Govee knows it by, so rooms, scenes and every existing command keep working
when the label changes. A label is also accepted anywhere a device name is:

    omarchy-govee label shelf1 "Desk Shelf"
    omarchy-govee on "Desk Shelf"
    omarchy-govee label shelf1              # clears it

Rooms hold each device exactly once — `rooms assign` removes it from whatever
room it was in, because a device in two rooms fires twice for one `room:`
command. `rooms rename` renames the key, so `room:` targets and any scene
referring to the old name must be updated with it.

In the panel: click a **device** name to open its label field, room chips,
brightness and colours; click a **room** name to rename the room and set
brightness or colour for everything in it at once.


## Dragging devices between rooms

Grab the ☰ handle on a device row and drop it on a room heading. Room headings
grow while a drag is in flight, and the list stops scrolling for the duration —
a Flickable otherwise claims the drag the moment it passes its threshold and
you scroll the panel instead of moving the row. Dropping on **other** takes the
device out of every room.

The clickable room chips in a device's expansion do the same thing without the
aim, and both call `rooms assign`.

## Device icons

Govee reports every light as `devices.types.light` with the same capability
list whether it is a bulb, a strip or a floor lamp, and publishes no SKU-to-
product table. The form factor is therefore read from the model number by the
prefix table in `KINDS` (longest prefix wins, unknown models draw as a bulb).
To correct one without touching the code:

    echo '{"H6072": "lamp"}' > ~/.config/omagovee/icons.json

Known kinds: `bulb`, `strip`, `string`, `lamp`.
