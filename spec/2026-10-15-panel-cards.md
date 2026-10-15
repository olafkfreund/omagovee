---
status: draft
issue: none
intent: intent/2026-10-15-panel-cards.md
---

# Spec: Card look for the bar panel

## Design

Restyle `plugin/Govee.qml` in place. Keep the existing tree
(`roomList` Repeater → `roomItem` → member Repeater → `devItem`), the drag
scaffolding (`dragArea` grip with `preventStealing`, the non-moving slot Item
with the moving `content` inside, `roomDrop` DropArea, `Flickable.interactive`
guard), the `editors` guard, and every `root.act([...])` call. Only the
chrome changes. No CLI change.

Code copied from eldtechnologies/omarchy-plugin-govee `Panel.qml` (MIT,
v0.3.0) gets a one-line attribution comment where it lands.

### 1. Tokens (copied from upstream `Panel.qml:525-529`)

On `root`: `foreground` (`bar ? bar.foreground : Color.foreground`),
`dim` (`Qt.darker(foreground, 1.55)`), `fontFamily`, `surface`
(`Util.alpha(foreground, 0.05)`). Replace every
`root.bar ? root.bar.foreground : Color.foreground` with `root.foreground`.
This also fixes the five unguarded `root.bar.foreground` reads
(`Govee.qml:200, 203, 539, 542, 656`), which throw when `bar` is null.

### 2. Colour dot

`dump` returns `color` as `{r, g, b}` or null (`bin/omarchy-govee:73`, `:717`,
`:738`), not a hex string. Add `function dotColor(dev)`: transparent when
`power !== 1` or color is null, else
`Qt.rgba(c.r / 255, c.g / 255, c.b / 255, 1)`. Rooms: the colour of the
first member that is on, else transparent.

### 3. Header

Above the scenes, outside the `Flickable` so it never scrolls away:
`GOVEE · <on>/<total> ON` (bold, `Style.font.subtitle`), with outlined
**All on** / **All off** buttons (`ActionButton` copied from upstream
`Panel.qml:569-582`, on `qs.Ui` `Button`) running `act(["on","all"])` /
`act(["off","all"])`. `contentHeight` becomes header + spacing + capped
flickable content.

### 4. Device card

The moving `content` Item becomes a `Rectangle`: `radius: Style.cornerRadius`,
`color: root.surface`, 8 px padding, `opacity: online ? 1 : 0.5`. Inside,
left to right: drag grip (unchanged), 14 px colour dot, a two-line title
(name in `Style.font.body`; subtitle in `root.dim`, `Style.font.caption`:
`<brightness>%` or `off`, then `LAN`/`cloud` from the dump's `transport`
field, not from `ip`, then `▾`/`▴`), and the power switch (unchanged
bindings: `checked: power === 1`, `interactive: online`, `busy`).

The click-to-expand MouseArea starts at the grip's right edge, so the grip
and expand never overlap.

The brightness `PanelSlider` moves out of the expanded section and shows
inline under the title while `power === 1 && online && typeof brightness === "number"`.
It keeps `minimum: 0`, `step: 1` and `onReleased` as today.

The expanded section keeps name field, room chips, and new-room field, and
gets the restyled swatches and the hue strip (below).

### 5. Room card

The room header becomes a card on `root.surface`: dot (§2), room name,
subtitle `<n> of <m> on · <avg>%`, and a power switch replacing the two
icon buttons. Switch rule for a mixed room: `checked` when any member is
on; toggling sends `off room:<name>` if any is on, else `on room:<name>`.
The inline slider shows when any member is on and at least one has a
numeric brightness. With no readings it is hidden, which fixes today's
behaviour of showing 0 and sending it.

The "other" bucket stays a plain section label (it is not a room and has no
room actions). Clicking the room name still opens the rename field and
room swatches. The drop highlight rectangle and the grow-during-drag rule
stay.

### 6. Swatches and hue strip

Swatches become 26 px circles with upstream's hover border
(`Util.alpha(foreground, 0.25)` → `foreground`). Keep our ten named
swatches, including `warm` and `cool`: we have no white slider to replace
them. `HueStrip` is copied from upstream `Panel.qml:617-658`; `picked(hex)`
calls `act(["color", hex, target], ...)`. `parse_color` accepts `#rrggbb`
(`bin/omarchy-govee:62-68`). Both appear in device and room expanded sections.

### 7. Scenes

Unchanged chips, restyled to match `ActionButton` outlines.

## Dropped from the intent

- **Accent border on the keyboard-selected card.** The panel has no
  keyboard selection today; `PanelKeyCatcher` only handles close. Adding
  arrow/Enter navigation is a feature, and `GoveeMenu.qml` already gives
  full keyboard control. Drop it. Esc collapses an open card before closing
  the panel (one line in `onCloseRequested`), as upstream does.

## Alternatives rejected

- **Copy upstream `LightRow`/`LookControls` as components.** `LightRow`
  owns its own MouseArea from `parent.left` and assumes boolean power,
  `supports` flags and its own `setPower`/`expand`. Wrapping it around our
  drag scaffolding fights `drag.target: content` and the slot/z layering.
  Both reviewers recommended restyling in place instead.
- **Switch to upstream's `Panel` root and `state.json` watching.** The
  `Panel` root fails to load for a third-party plugin (`Govee.qml:15`), and
  `dump` is our single source of truth.
- **Change `dump` to emit hex colours.** Converting in QML is one function
  and keeps the CLI contract and its test (`test_reliability.py:193`).

## Risks

- **Drag z-order.** The dragged card must paint over later sibling cards. The
  slot Item already raises `z` for the dragged device (`Govee.qml:376`) and
  the room raises `z` (`:242`). Cards add no new nesting level above
  `content`, so this holds. Still check by hand.
- **Taller panel.** Cards with inline sliders are about 3× taller than today's rows.
  The header sits outside the Flickable, and the content is capped and scrolls.
  Dragging to a room that is out of view needs a scroll first. That is
  true today and is out of scope.
- **`editors` counter can stick (unverified).** agy flagged that a focused
  name field destroyed by a `roomList` reassignment may never decrement
  `editors`, leaving keys blocked and refresh paused. The 60 s refresh is
  already skipped while editing, so only a command-triggered refresh could
  do it. Not changed here; see Verification.
- Only the owner's Omarchy shell is affected.

## Verification

1. `python3 -m unittest test_omagovee test_reliability test_mcp` and
   `python3 test_menu_qml.py` and `node test_menu_model.js` still pass. The
   menu is untouched.
2. Load check: `qmllint` is not available for the shell's private modules,
   so restart the shell (`omarchy restart shell`) and confirm no errors for
   `olafkfreund.govee` in `journalctl --user -b | grep -i govee`.
3. Manual checks in the live panel: header count matches; All on/All off;
   device switch and inline slider; colour dot matches the light after a
   swatch and a hue pick; room switch with a mixed room; room slider hidden
   when no readings; rename, room chips, new room; drag a light to another
   room (the `govee drag start` / `govee drop` journal lines appear); Esc
   collapses then closes; an offline light is dimmed and its switch inert.
4. Editors check: focus a name field, run `omarchy-govee on all` in a
   terminal, then confirm Esc still closes the panel after unfocusing.
   If they do not, fix the counter in this task.
