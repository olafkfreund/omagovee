---
status: draft
issue: none
spec: spec/2026-10-15-panel-cards.md
---

# Plan: Card look for the bar panel

## Approved decisions (self-contained)

- **Restyle `plugin/Govee.qml` in place. Only the visuals change.** Keep these unchanged:
  - the tree: `roomList` Repeater → `roomItem` → member Repeater → `devItem`
  - the drag code: the `dragArea` grip with `preventStealing`, the slot Item
    that does not move with the `content` Item inside it that does, the
    `roomDrop` DropArea, and the `Flickable.interactive` guard
  - the `editors` counter, `PanelKeyCatcher.blocked`, the 60 s Timer, and
    every `root.act([...])` argument list
- **Root type stays `BarWidget`.** No CLI change.
- **MIT attribution.** Code copied from eldtechnologies/omarchy-plugin-govee
  `Panel.qml` (v0.3.0) gets the comment
  `// From eldtechnologies/omarchy-plugin-govee Panel.qml (MIT).`
- **Dump shape** (`bin/omarchy-govee` `dump()` / `power_state()`). Each device has:
  - `mac`, `name`, `label`, `kind`, `ip`, `online` (true/false/null)
  - `power` (1/0/null) and `brightness` (number/null)
  - `color`: `{r, g, b}` or null, **not a hex string**
  - `transport`: `"lan"` or `"cloud"`, absent when the read failed
  - `error` (optional)
- **Room switch:** `checked` = any member has `power === 1`. Toggling sends
  `off room:<name>` if any member is on, else `on room:<name>`.
- **Room slider:** shown only when any member is on AND at least one member
  has a numeric brightness. Its value is the average of the numeric readings.
- **Device slider:** inline, shown when `power === 1 && online &&
  typeof brightness === "number"`. `minimum: 0`, `step: 1`, `integer: true`.
- **The "other" bucket** keeps a plain `PanelSectionHeader`, with no room card and no
  switch, because it is not a room.
- **Swatches:** keep our ten named swatches (including `warm`/`cool`), drawn
  as 26 px circles. Add the upstream `HueStrip`.
- **Dropped:** a keyboard-selection accent border, warm/cool slider, per-light
  scene dropdown, theme follow, hide, demo, queue.
- **Esc** collapses an expanded card before it closes the panel.

## Steps

1. `plugin/Govee.qml:18-62` (root properties): add the tokens copied from
   upstream:
   ```qml
   readonly property color foreground: bar ? bar.foreground : Color.foreground
   readonly property color dim: Qt.darker(foreground, 1.55)
   readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
   readonly property color surface: Util.alpha(foreground, 0.05)
   ```
   Then replace every `root.bar ? root.bar.foreground : Color.foreground` with
   `root.foreground`, every `root.bar ? root.bar.fontFamily : Style.font.family`
   with `root.fontFamily`, and the five unguarded `root.bar.foreground` uses
   (current lines 200, 203, 539, 542, 656) with `root.foreground`. Add helpers:
   - `function dotColor(dev)`: returns `"transparent"` unless
     `dev.power === 1 && dev.color`, else
     `Qt.rgba(dev.color.r / 255, dev.color.g / 255, dev.color.b / 255, 1)`.
   - `function onCount()` and a `property int onLights`, recomputed in
     `applyDump`. Simplest: set `root.onLights` in `applyDump` next to `lit`.
   - `function subtitle(dev)`: joins with `" · "`. First part: `"<b>%"` if on
     with a numeric brightness, `"on"` if on without one, `"offline"` if
     `online === false`, else `"off"`. Then `"LAN"`/`"cloud"` from
     `transport` when present.

   → verify by `grep -n 'root.bar' plugin/Govee.qml`: the only hits are
     `bar: root.bar` assignments.
   Traps: `Util` is in `qs.Commons`, which is already imported. Do not touch
   `GoveeMenu.qml`.

2. `plugin/Govee.qml`, new inline components before `BarIconButton`: copy
   upstream `ActionButton` (`Panel.qml:569-582`) and `HueStrip`
   (`Panel.qml:617-658`) verbatim, with the attribution comment. `ActionButton`
   uses `root.foreground`/`root.fontFamily`; `qs.Ui` `Button` emits
   `clicked()`. `HueStrip`'s marker uses `root.foreground`.
   → verify in step 7 (load check).
   Traps: `component` declarations must sit directly inside the root object.

3. Header (`KeyboardPanel` content, current lines 153-183): wrap the
   `Flickable` in a `Column` (spacing `Style.space(10)`). Put a header `Row`
   before it:
   - Left: Text `"GOVEE" + (devices.length ? "  ·  " + onLights + "/" + devices.length + " ON" : "")`,
     bold, `Style.font.subtitle`, elided, with
     `width: parent.width - actions.width - spacing`.
   - Right: `ActionButton`s "All on" / "All off" (`outlined: true`) calling
     `root.act(["on","all"], "")` / `root.act(["off","all"], "")`.

   The Flickable gets `width: parent.width` and
   `height: parent.height - header.height - spacing`. Set
   `contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(10) + column.implicitHeight, Style.space(900))`.
   In `PanelKeyCatcher.onCloseRequested`:
   `if (root.expandedName !== "") root.expandedName = ""; else root.close()`.
   Restyle the scene chips: radius `Style.cornerRadius`, border
   `Util.alpha(root.foreground, 0.35)`, hover fill
   `Util.alpha(root.foreground, 0.09)`.
   → verify in step 7.
   Traps: `PanelKeyCatcher` must still be the `focusTarget` and stay
   `anchors.fill: parent`. Keep `interactive: root.dragName === ""` on the
   Flickable.

4. Room card (current lines 249-359). Applies only when
   `roomItem.room.name !== "other"`. For "other", keep today's
   `PanelSectionHeader` and hide the switch.

   Replace the header `Item` with a `Rectangle`: `radius: Style.cornerRadius`,
   `color: root.surface`, 8 px padding. Contents:
   - 14 px dot (`radius: width/2`, border `Util.alpha(root.foreground, 0.2)`),
     coloured with the `dotColor` of the first member that is on.
   - A two-line title: room name (`Style.font.body`), then the subtitle
     `"<n> of <m> on"` + `" · <avg>%"` when there are readings, in `root.dim`
     at `Style.font.caption`, plus `▾`/`▴` for `roomItem.editing`.
   - A `ToggleSwitch` on the right, per the room switch rule above.
   - The inline `PanelSlider`, per the room slider rule above, moved here
     from the expanded section with the same `onReleased`.

   Keep:
   - the grow-during-drag height term (`+ (root.dragName !== "" ? Style.space(14) : 0)`)
   - the name MouseArea toggling `expandedName`. It covers the title only,
     not the switch.

   The expanded section keeps the rename `TextField` and swatches (step 6),
   and gets a `HueStrip` that calls
   `root.act(["color", hex, "room:" + roomItem.room.name], "")`.
   Delete the two `PanelActionButton`s, which the switch replaces.
   → verify in step 7.
   Traps: `DropArea` and the highlight `Rectangle` (current lines 633-657)
   stay outside the Column, anchored to `roomItem`. Do not move them into
   the card.

5. Device card (current lines 373-500). Turn the moving `content` `Item`
   into a `Rectangle`: `radius: Style.cornerRadius`, `color: root.surface`.
   Keep:
   - `opacity: Drag.active ? 0.6 : (devItem.dev.online ? 1 : 0.5)`
   - all `Drag.*` properties, and `devName`/`devRoom`
   - the `dragArea` exactly as it is

   Inside, after the grip, add:
   - a 14 px `dotColor(dev)` dot
   - a title Column: label/name (`Style.font.body`, elided) over
     `subtitle(dev) + (isExpanded ? "  ▴" : "  ▾")` in `root.dim` at
     `Style.font.caption`
   - the existing `ToggleSwitch` (same bindings, plus `cursorRing: false`)

   Delete the `typeIcon` Text and the `(offline)`/`· lan` suffixes; the
   subtitle and opacity replace them. The expand MouseArea anchors
   `left: dragArea.right` and `right: sw.left`.

   The slot `Item` height becomes the card's implicit height, and it must
   still contain the inline slider. So put the slider inside the card
   Rectangle, under the title row (a Column inside the card), not in the
   expanded section.
   → verify in step 7.
   Traps:
   - The slot Item keeps `z: root.dragName === devItem.dev.mac ? 100 : 0`,
     and `content` stays a child of the slot, so the Column does not reflow
     while dragging.
   - `devItem` stays the direct child of `roomCol`.
   - `kindIcon`/`kindIcons` become unused: delete them.

6. Swatches (current lines 336-356 and 605-624): 26 px, `radius: width / 2`.
   The border is `Util.alpha(root.foreground, 0.25)`, or `root.foreground` at
   width 2 on hover, with `cursorShape: Qt.PointingHandCursor`. Keep the
   named `root.swatches` list and its `act` calls. In the device expanded
   section, add a `HueStrip` after the swatches that calls
   `root.act(["color", hex, devItem.dev.mac], devItem.dev.mac)`.
   → verify in step 7.
   Traps: `parse_color` takes `#rrggbb`. `String(Qt.hsva(...))` yields
   `#rrggbb` in Qt 6. Confirm with one hue pick in step 8.

7. Load check:
   - Run `omarchy restart shell`, open the panel, then run
     `journalctl --user -b --since "-2 min" | grep -iE 'govee|qml'`.
   - Expect no `TypeError`, `ReferenceError` or `is not a type` lines.
   - Fix anything found before step 8.
   Traps: the shell does not watch symlinked plugin folders; restart after
   every QML edit.

8. Manual checks in the live panel, each with its expected result:
   - The header count matches `omarchy-govee state`.
   - All on / All off work.
   - The device switch works, and the inline slider shows only while the
     light is on.
   - The dot matches the light after a swatch pick and after a hue pick.
   - A mixed room shows on, and its switch turns the room off.
   - The room slider is hidden when no member reports brightness.
   - Rename, room chips and new room work.
   - Dragging a light to another room works, and the journal shows
     `govee drag start` and `govee drop`.
   - Esc collapses an open card first, then closes the panel.
   - An offline light is at half opacity with an inert switch.
   - **Editors check:** focus a name field, run `omarchy-govee on all` in a
     terminal, click out, then press Esc. The panel must close. If it does
     not, add `Component.onDestruction: if (activeFocus) root.editors -= 1`
     to the three `TextField`s, and record the deviation here.

## Tests

```bash
python3 test_omagovee.py && python3 test_reliability.py && python3 test_mcp.py
python3 test_menu_qml.py
node test_menu_model.js
```

All pass, unchanged: the menu and the CLI are not touched. There is no
automated test for `Govee.qml`. Steps 7 and 8 are the check.

## Rollback

`git revert` the implementation commits on `feat/panel-cards`, then run
`omarchy restart shell`. No state or config files change.

## Execution

Steps 1-6 edit files, so the `coder` agent implements them, one agent with
the steps sent in order. A fresh Opus agent reviews `git diff main` against
this plan. Steps 7-8 need the live desktop and stay with the session.
