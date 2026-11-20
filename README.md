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
| `bin/omarchy-menu-lights` | Quickshell keyboard menu launcher for keybindings |
| `bin/omarchy-cmd-lights` | `gum` picker: device → action → value; for the menu row and the widget |
| `bin/omagovee-mcp` | Optional stdio MCP server for AI agents |
| `plugin/` | Omarchy bar widget + dropdown panel: scenes, rooms, per-device toggle/brightness/colour |
| `test_omagovee.py` | `python3 test_omagovee.py` — payload, colour and room logic |

The controller uses only the Python standard library. The optional MCP adapter
uses the official `mcp` SDK, pinned in its script metadata; widget clicks do
not import it.

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

Every scene is validated and all targets resolved before the first command.
Power is applied before brightness and colour. Runtime failures are reported
per device/action; successful changes are not rolled back. If `scenes.json` is
missing, built-in scenes are used in memory. Reads never create or replace it.
Malformed files produce an error and are preserved.

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
  If a model ignores a LAN command, the controller retries once and falls back
  to cloud when read-back cannot confirm the requested value.
- **LAN writes are read back.** Power, brightness and colour are checked with
  `devStatus`, with one retry. Exact matching read-back is `confirmed`; a cloud
  acknowledgement is `unverified`. A cloud rejection is `failed`. Some lamps
  adjust RGB values, so colours may fall back to cloud even after a LAN write.
- **LAN replies share UDP port 4002.** Exchanges are serialized across threads
  and processes using a per-user file lock. Cloud reads remain concurrent.
  Run updated copies of the CLI everywhere; older versions do not take the lock.
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
  cloud states concurrently and LAN states one at a time.
  It refreshes at startup, when the panel opens, after every action, and once a
  minute unless editing or dragging. A pending refresh runs after an in-flight
  fetch. Refresh errors show `!` in the bar with an explanatory tooltip.
  Device sliders use reported brightness (disabled if unknown); room sliders
  show the mean of known brightness values. An earlier design cached state in a file the widget
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

Rooms hold each device exactly once — `rooms assign` (and its shorthand
`rooms <room> <dev>...`) removes it from whatever room it was in, because a
device in two rooms fires twice for one `room:` command. A `rooms.json` that
already lists a device twice is read as if only its first room counted; the
file is corrected the next time a room changes.

    omarchy-govee rooms assign office shelf1 shelf2   # creates office if new
    omarchy-govee rooms office lvrt1                  # same thing
    omarchy-govee rooms assign none shelf2            # out of every room

There are no empty rooms: a room exists while it has a light, and is created
by assigning its first one. `none`, `other` and `all` cannot be room names —
they already mean "no room", the panel's unassigned heading and every device.

`rooms rename` renames the key, so `room:` targets and any scene referring to
the old name must be updated with it. Renaming onto a room that already
exists is refused rather than silently dropping that room's lights.

A MAC takes precedence. Exact names and labels must identify one device;
otherwise a partial name is accepted only when it matches a single device,
so `lvrt` is refused when there are `lvrt1` and `lvrt10` instead of moving
whichever came first.

In the panel: click a **device** name to open its label field, room chips, a
**New room…** field, brightness and colours; click a **room** name to rename
the room and set brightness or colour for everything in it at once. Type a
name into **New room…** and press Enter to create that room with this light
in it. Any command the panel runs that fails — a reserved room name, an
offline light — raises a notification with the reason.


## Dragging devices between rooms

Grab the ☰ handle at the left of a device row and drop it anywhere on a
room — its heading or its list of lights. Room headings grow while a drag is
in flight. Dropping on **other** takes the device out of every room. To drag
into a room that does not exist yet, create it first with **New room…**.

Dragging and scrolling are the same gesture, so they get different territory:
the 24px handle column drags, the rest of the row still flicks the list. The
handle sets `preventStealing`, without which a Flickable takes the grab the
moment the pointer passes its own threshold and the panel scrolls instead of
the row moving — this is why the first attempt did nothing.

The drag logs `govee drag start` and `govee drop` to the journal
(`journalctl --user -f | grep govee`); it cannot be exercised from a shell, so
that is the only evidence of where it broke if it ever does again.

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


## Stable IDs and existing configuration

New defaults and labels use device MACs. Room edits convert their members to
MACs, and the widget and picker send MACs rather than display names. Legacy
name-based files remain readable. Before renaming devices in Govee Home,
convert existing rooms, labels, defaults and scene device targets:

```bash
omarchy-govee migrate-ids
```

Migration validates all references first and saves existing files as
`*.before-ids` before replacing them. Ambiguous or missing device names must be
corrected first. Existing backups are preserved on repeat runs. Replacement is
atomic per file, not across the whole set; after an I/O failure, fix the cause
and rerun. No lights are changed by migration. Room renames still require
updating scene `room:` targets.

`room:other` selects unassigned devices. `none` remains the room assignment
command for removing a light from all rooms.

## AI automation via MCP

Run the server from this checkout (keep both scripts together):

```bash
uv run --script /absolute/path/to/omagovee/bin/omagovee-mcp
```

`uv` reads the adapter's inline dependency pin, creates an isolated script
environment and starts the stdio server. If your Python already has
`mcp==1.29.0`, `python3 bin/omagovee-mcp` also works. The adapter uses the
[official Python SDK's v1 API](https://py.sdk.modelcontextprotocol.io/v1/).

Configure an MCP host with this server command and arguments; for hosts using
`mcpServers` JSON:

```json
{
  "mcpServers": {
    "omagovee": {
      "command": "uv",
      "args": ["run", "--script", "/absolute/path/to/omagovee/bin/omagovee-mcp"]
    }
  }
}
```

The server inherits `GOVEE_API_KEY`, or reads the existing
`~/.config/omagovee/api-key`. It also respects `OMAGOVEE_CONFIG`,
`OMAGOVEE_CACHE` and `OMAGOVEE_IFACE_IP`. Keep credentials out of tool arguments.
A host launches the server on demand; no listener, service or firewall change
is needed. Registration in a particular agent app is a separate host setting.

| Tool | Arguments | Result |
|---|---|---|
| `list_devices` | none | MACs, names, capabilities, rooms and labels; no state polling |
| `get_state` | `target` | Power, brightness, RGB colour, reachability, transport and read errors |
| `set_power` | `target`, `on` boolean | Per-device confirmation status |
| `set_brightness` | `target`, `percent` integer 0–100 | Per-device confirmation status |
| `set_color` | `target`, `color` | RRGGBB, #RRGGBB or a named colour |
| `list_scenes` | none | Scene definitions including targets and requested values |
| `run_scene` | `name` | Per-action results, including partial failures |

Use MACs returned by `list_devices`, `room:<name>`, or explicitly `all`.
Names/labels remain accepted but must resolve unambiguously. Power, brightness
and colour commands set explicit values, making retries safer than `toggle`.
Brightness/colour do not implicitly turn lights on. There is no toggle tool.

Example agent request: “List my lights, then set room:office to 40% brightness.”
The agent calls `list_devices`, then `set_brightness` with
`{"target":"room:office","percent":40}`.

Results distinguish `confirmed` LAN read-back, `unverified` cloud acceptance,
and `failed`. Group failures return MCP `isError` **and** structured per-device
results, so successful changes remain visible. Each CLI subprocess has a
120-second deadline. A timeout stops further commands, but previous writes may
have reached lamps: read state before deciding whether to retry. Cloud state
may lag LAN writes; an API acknowledgement is not physical confirmation.

The same machine-readable interface is available without MCP:

```bash
omarchy-govee --json list
omarchy-govee --json state room:office
omarchy-govee --json brightness 40 room:office
omarchy-govee --json scenes
omarchy-govee --json scene evening
```

JSON commands return exit status 1 on failure, including partial failures, and
keep diagnostic information in the JSON result.

## Verification

```bash
python3 test_omagovee.py
python3 test_reliability.py
python3 test_mcp.py  # requires the adapter's mcp version
# Or use the same isolated SDK dependency:
uv run --with mcp==1.29.0 test_mcp.py
```

Tests use temporary configuration, loopback fake lamps and a fake cloud. The
MCP check performs a real stdio handshake and exercises all seven tools,
validation errors and partial failures. No real lamps are controlled.

Manual desktop check after installing the updated CLI and widget: open the
panel, check reported brightness, move a device between rooms, rename its label,
and confirm refresh failures are visible. Live Govee firmware behaviour and
these desktop gestures require a real-device check.

## Keyboard pop-out menu

The plugin includes a separate, searchable Quickshell menu alongside the bar
panel. It runs in the existing Omarchy shell and also works when its bar widget
is not placed in the bar. Enable the plugin and install `bin/omarchy-menu-lights`
with the other CLI scripts. Keep all files from `plugin/` together when updating.

```bash
omarchy-menu-lights          # toggle keyboard menu
omarchy-menu-lights summon   # always open
omarchy-menu-lights close
# Equivalent direct shell route:
omarchy-shell shell toggle olafkfreund.govee '{}'
```

The direct shell route can also be used in keybindings without installing the
launcher script. If new QML files fail to load after updating, restart the shell
with `omarchy restart shell` and allow its plugins to finish loading.

The IPC route now opens the keyboard menu; clicking the bar icon still opens
the existing mouse panel. No second Quickshell process is started.

Suggested Hyprland Lua binding in `~/.config/hypr/bindings.lua` (check that this
combination is free before adding it):

```lua
o.bind("SUPER + CTRL + ALT + G", "Govee lights", "omarchy-menu-lights")
```

For older Hyprland configurations using `.conf`:

```ini
bindd = SUPER CTRL ALT, G, Govee lights, exec, omarchy-menu-lights
```

Reload and check the configuration with `hyprctl reload` and
`hyprctl configerrors`. The repository does not change your live keybindings.

The menu uses flat, unboxed rows with larger sans-serif text, heavier labels,
and Nerd Font icons. Back and reload controls are keyboard shortcuts. Device icons follow the active
Omarchy theme: accent for on, muted for off/unknown, and urgent for offline.
State text remains visible so colour is not the only indicator.

### Keyboard controls

| Key | Action |
|---|---|
| Left / Right (empty filter) | Back / open selected submenu or editor |
| Alt+Right | Open selected submenu or editor with a filter |
| Ctrl+R | Reload device state |
| Type | Filter the current list by name, ID or detail |
| Up / Down | Select a row, wrapping at the ends |
| Enter | Open the selected target/action, or save a form |
| Escape | Cancel a form, clear the filter, go back, then close at the top |
| Alt+Left | Same back action |
| Backspace with an empty filter | Go back |
| F5 | Refresh device state |

Select **All devices**, a room, **Unassigned devices**, or an individual light.
Each target offers explicit on/off, brightness from 0–100, named colours and
custom six-digit RGB. **Scenes** lists existing scenes. Individual lights also
have friendly-name editing and room assignment, including **No room** and
**New room**. Room actions include rename. Renaming a room still requires
updating scenes that use its old name.

State, busy messages, validation errors and partial command failures are shown
in the menu. Cloud acceptance is identified as unverified. Actions queue in
order and continue if the menu is dismissed; opening it again refreshes state.
The menu can be unloaded while a command runs: `GoveeClient.qml` is a singleton
(listed in `plugin/qmldir`) shared by the bar widget and the menu, so the running
command, its queue and the latest state stay in it. Esc and a click away only hide
the menu. The menu does not poll in the background.

### Menu development checks

The research and implementation plan is in
[plan/2026-09-16-keyboard-menu.md](plan/2026-09-16-keyboard-menu.md).
It follows the [Omarchy plugin guide](https://plugins.omarchy.org/develop.html)
and the installed shell's combined menu/bar-widget lifecycle.

```bash
omarchy plugin validate ./plugin
node test_menu_model.js
python3 test_menu_qml.py
```

The model test uses Node's standard library. The QML test requires the installed
Omarchy shell (`OMARCHY_PATH`), Quickshell and Xvfb; it opens an isolated virtual
display and substitutes a fake CLI. The test copy omits Wayland-only surface
hints, which X11 cannot instantiate; application logic is unchanged. It does
not change real lights or load a
second shell on your desktop. Wayland focus, monitor placement, outside-click
dismissal, keybinding activation and shell plugin reload still need a manual
check in the actual desktop after installation.
