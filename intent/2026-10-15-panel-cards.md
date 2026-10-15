---
status: draft
issue: none  # repo convention so far; add the issue number if one is opened
author: olafkfreund
---

# Intent: Give the bar panel the card look of eldtechnologies/omarchy-plugin-govee

## Problem

The dropdown in `plugin/Govee.qml` is a flat list: section headers, small
text rows, and controls hidden until you click a name. You cannot see a
light's colour or brightness without opening it, and there is no "how many
are on" summary. The ELD Technologies plugin
(https://github.com/eldtechnologies/omarchy-plugin-govee, MIT, v0.3.0) shows
the same data far more legibly, and the owner wants that look.

What it does that we do not:

- Header: `GOVEE · 3/5 ON` with outlined **All on** / **All off** buttons.
- Each light and each room is a rounded card on a faint surface
  (`alpha(foreground, 0.05)`), with a dot in its current colour, a name, a
  dim subtitle (`70% · LAN ▾`), a power switch, and a brightness slider
  shown inline while it is on.
- Opening a card shows larger (26 px) round swatches and a click-to-pick
  rainbow hue strip.
- Offline lights are dimmed to half opacity; the keyboard-selected card gets
  an accent border.

It is all built from the same `qs.Ui` primitives we already use
(`KeyboardPanel`, `PanelKeyCatcher`, `ToggleSwitch`, `PanelSlider`,
`Button`), so this is a QML restyle, not new infrastructure.

## Proposed outcome

Opening the bar dropdown shows the card layout above, for our data: rooms
as group cards (with their lights beneath), unassigned lights after, our
global scenes kept. Every action the panel offers today still works: power,
brightness, colour, rename, room assign, new room, drag to a room, scenes,
and the keyboard menu (`GoveeMenu.qml`) is untouched.

## Affected users and systems

- `plugin/Govee.qml` (the panel). Possibly `bin/omarchy-govee dump` only if
  a field the cards need is missing (it already returns `power`,
  `brightness`, `color`, `online`, `ip`).
- `test_menu_qml.py` if it asserts on panel structure.
- The owner's Omarchy shell; no other hosts.

## Constraints

- Copy code with MIT attribution (a header comment naming the source).
- No new CLI transport, daemon or dependency.
- Keep the root type `BarWidget` (see the comment at `Govee.qml:15`; the
  upstream `Panel` root does not load for a third-party plugin here).
- Keep drag-to-room and the editors/PanelKeyCatcher guard working.

## Not taken from upstream (pushback, decide in open questions)

These need CLI or data work the look itself does not:

- Warm/cool white slider: our CLI has no colour-temperature command.
- Per-light scene dropdown: our scenes are local and global, not Govee's.
- Follow Omarchy theme hook, Hide/Forget, demo mode, first-run setup,
  request queue with coalescing, `state.json` file watching.

## Open questions

1. Rooms: show each room as one group card (aggregate switch + slider) with
   its lights as cards beneath it, or keep a plain room heading over light
   cards?
2. Do you want any of the "not taken" features as separate follow-up tasks
   (warm/cool white is the one most visible in their screenshots)?
3. Keep scenes as chips at the top, or move them into a dropdown?
