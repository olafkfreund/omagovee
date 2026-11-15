---
status: draft
issue: none  # repo convention so far; add the issue number if one is opened
intent: intent/2026-11-15-qml-commons-color.md
---

# Spec: Make the repo plugin and its tests run clean on the current shell

## Design

### 1. Reach the colour singleton through a qualified import

In `plugin/Govee.qml` and `plugin/GoveeMenu.qml`, add
`import qs.Commons as Commons` directly after the existing `import qs.Commons`.
Change each bare `Color.` to `Commons.Color.`: 5 sites in `Govee.qml` (lines 50,
161, 793, 797, 903) and 15 in `GoveeMenu.qml` (151–314). Keep the unqualified
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
  properties. A binding can span several lines (`KeyboardPanel.qml:157–159`
  continues with lines that start with `?` and `:`), so the whole statement
  goes, including its continuation lines. Stripping only the first line would
  attach the ternary to the binding above it.
  Use the same helper for `GoveeMenu.qml`.
- **Load the bar view.** Add a second `Loader` for `plugin/Govee.qml` next to
  the menu loader. In a new stage, once its first `dump` has loaded (1 device,
  1 room): open it, set `expandedName` to `"room:Office"`, then to `"AA:01"`,
  so the room-chip and drop-border delegates are built. Check
  `devices.length === 1` and `roomList.length >= 1`. Send no actions, so the
  existing exact assertion on the CLI calls still holds (`dump` calls are
  already filtered out).
- **Warnings fail the test.** After the run, fail if any output line contains
  `WARN scene:`, `ERROR scene:`, `TypeError` or `ReferenceError`. No allowlist:
  the patched plugin produces none of these.
  `WARN: $HYPRLAND_INSTANCE_SIGNATURE is unset` has no `scene:` and doesn't
  match.

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
- **Allowlist of tolerated warnings**: none are needed today. An allowlist
  would hide new ones.

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
- Live: the shell log shows no new lines after the panel and the menu are
  opened (`omarchy-shell shell summon olafkfreund.govee '{}'` returns `ok`).
