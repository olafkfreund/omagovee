---
status: approved
issue: none  # repo convention so far; add the issue number if one is opened
intent: intent/2026-11-15-qml-commons-color.md
---

# Spec: Make the repo plugin and its tests run clean on the current shell

## Design

### 1. Reach the colour singleton through a qualified import

In `plugin/Govee.qml` and `plugin/GoveeMenu.qml`, add
`import qs.Commons as Commons` directly after the existing `import qs.Commons`.
Change each bare `Color.` to `Commons.Color.`: 5 sites in `Govee.qml` (lines 50,
161, 793, 797, 903) and 19 in `GoveeMenu.qml` (17 lines, 151–314). Keep the unqualified
import so `Style` and `Util` stay as they are.

That is exactly the hand-patch already installed in
`~/.config/omarchy/plugins/olafkfreund.govee`. Applying
`s/\bColor\./Commons.Color./` to HEAD gives the installed files, apart from one
import line each (checked with `diff`). The shell's own components use the
same pattern (`shell/Ui/TextField.qml:22`: `Commons.Color.foreground`). We
don't need to know which type hides the bare `Color` for this to work.

### 2. Make `test_menu_qml.py` cover `Govee.qml` and fail on QML warnings

- **Test copy of `Ui/`.** Copy `$OMARCHY_PATH/shell/Ui` instead of symlinking
  it. Strip every `WlrLayershell.` binding from the copy, as the test already
  does for `GoveeMenu.qml`, because X11 cannot create Wayland attached
  properties. One helper does both. A stripped statement is the
  `WlrLayershell.` line plus any following lines whose text starts with `?` or
  `:`. Today that matters only for `KeyboardPanel.qml:157–159`; every other
  `Ui/` binding (`OverlayWindow.qml`, `SpeedTestOverlay.qml`) is one line.
  Stripping only the first line would attach the ternary to the binding above
  it. A focused check guards the helper: after stripping, no copied file
  contains `WlrLayershell.`, and in `KeyboardPanel.qml` the bindings around
  lines 157–159 are unchanged.
- **Load the bar view.** Add a second `Loader` for `plugin/Govee.qml` next to
  the menu loader. The test fails if either loader reaches `Loader.Error`.
  Add new stages after the existing menu stages, each on its own timer tick so
  layout runs between them:
  1. wait until `devices.length === 1` and `roomList.length >= 1` (first
     `dump`);
  2. `open()`, check `opened`;
  3. set `expandedName = "room:Office"` and check it;
  4. set `expandedName = "AA:01"` and check it.

  The existing `GOVEE_QML_PASS` / `Qt.quit()` moves after the last of these.
  Send no actions, so the existing exact assertion on the CLI calls still
  holds: `open()` only triggers `dump` (Govee.qml:88), which is already filtered
  out.
- **Warnings fail the test.** After the run, fail on any output line with a
  `WARN` or `ERROR` log level, or containing `Error:`. The one exception is
  exactly `WARN: $HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to
  hyprland.`, which Xvfb causes (the test removes that variable on purpose).
  The patched plugin produces nothing else.
- **No bare `Color.` in the plugin.** Some bad colours fail silently:
  `Style.selectedFillFor(fg, undefined)` (Commons/Style.qml:158) logs no
  warning, so a regression on room chips (Govee.qml:793, 797) or the drop
  border (903) would pass a warning check. The test therefore also fails if
  `plugin/*.qml` contains `Color.` not preceded by `Commons.` (regex
  `(?<![\w.])Color\.`). Cheap, and it names the exact regression.

A scratch probe proved this. With the patched files, `Govee.qml` loaded,
opened and expanded with 0 warnings (`devices=1 rooms=1 opened=true`). The repo
files gave `Govee.qml: Unable to assign [undefined] to QColor` ×3, and
`GoveeMenu.qml` gave the known `TypeError`s.

### 3. `test_mcp.py`: no change

It already passes with the command documented in `README.md:341`:
`uv run --with mcp==1.29.0 test_mcp.py` ("MCP handshake, all seven tools,
validation and partial-failure checks passed", exit 0). The earlier failure
came from running it with plain `python3`. Verification runs it the
documented way.

## Alternatives rejected

- **Qualify `Style` and `Util` too and drop the unqualified import** (agy's
  suggestion): a bigger diff with no failure behind it, and it moves away from
  the patch that is proven on the live shell.
- **Find and work around whatever shadows `Color`**: not needed for the fix,
  and both reviewers couldn't pin it down without reading Qt's type
  registrations.
- **Run the QML test under a headless Wayland compositor** instead of Xvfb:
  more realistic, but a new test dependency and a rewrite of the harness. The
  strip-on-copy approach already exists in this test.
- **PEP 723 header in `test_mcp.py`**: works, but the README already gives a
  command that passes, so it fixes nothing.
- **Matching only `scene:` warnings**: misses `console.warn`/`console.error`
  (`WARN qml:`) and loader errors. Failing on every level, with one exact
  exception, is stricter and still simple.
- **Asserting rendered chip/border colour values**: needs `objectName`s added
  to production delegates and colour maths in the test. The static `Color.`
  check catches the same regression with no production change.

## Risks

- The `WlrLayershell` strip only touches the test copy. It can hide a
  layer-shell bug, as it already does for `GoveeMenu.qml`. The live check
  covers that.
- A future shell update that adds new `WARN scene:` noise in `Ui/` will fail
  this test even though the plugin is fine. That is the intended trade-off;
  the failure names the file.
- Host p620 only: the installed copy already has this patch, so reinstalling
  from the repo changes nothing visible.

## Verification

- `OMARCHY_PATH=<running tree> python3 test_menu_qml.py` passes on the fixed
  repo, and fails with `QColor`/`TypeError` warnings when step 1 is reverted
  (check the test against the old code once).
- `python3 test_omagovee.py`, `python3 test_reliability.py`,
  `node test_menu_model.js`, `uv run --with mcp==1.29.0 test_mcp.py` all pass.
- `diff -r plugin ~/.config/omarchy/plugins/olafkfreund.govee` is empty after
  the fix, so the repo matches the live, known-good copy.
- `omarchy plugin validate plugin` passes.
- Live, after reinstalling from the repo: the shell log shows no new lines
  after (a) the keyboard menu opens (`omarchy-shell shell summon
  olafkfreund.govee '{}'` returns `ok`) and (b) the bar panel is clicked open
  and a room and a device are expanded by hand. In (b) the room chips show the
  accent colour. (b) needs the owner at the desktop.
