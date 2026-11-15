---
status: draft
issue: none  # repo convention so far; add the issue number if one is opened
spec: spec/2026-11-15-qml-commons-color.md
coders:
  1: agy     # mechanical rename across 24 sites in two files, checked by diff against the installed copy
  2: codex   # small, tricky helper: multi-line statement stripping with its own guard
  3: coder   # new QML test stages and output filters; plain harness work
reviewers:
  - codex    # independent read of the test logic it did not write in full
  - agy      # independent check that the rename matches the live copy and nothing else moved
---

# Plan: Make the repo plugin and its tests run clean on the current shell

## Approved decisions (from the spec)

- Plugin fix = the installed hand-patch exactly: add
  `import qs.Commons as Commons` directly after `import qs.Commons`, and change
  every bare `Color.` to `Commons.Color.` (5 in `plugin/Govee.qml`: lines 50,
  161, 793, 797, 903; 19 in `plugin/GoveeMenu.qml`, 17 lines, 151–314). Keep
  the unqualified import, so `Style` and `Util` are unchanged. No other edits.
- `test_menu_qml.py` copies `$OMARCHY_PATH/shell/Ui` (not a symlink) and
  strips `WlrLayershell.` statements from it and from `GoveeMenu.qml` with one
  helper. A statement is the `WlrLayershell.` line plus following lines whose
  stripped text starts with `?` or `:`.
- The test loads `plugin/Govee.qml` too and drives it over separate ticks:
  open, wait for data, expand a room, then a device. It fails on
  `Loader.Error`, on any `WARN`/`ERROR` output line except the exact Hyprland
  line, on any `Error:` line, and on any bare `Color.` in `plugin/*.qml`.
- `test_mcp.py` is unchanged. Run it as `uv run --with mcp==1.29.0 test_mcp.py`.
- Rejected: qualifying `Style`/`Util`, a Wayland compositor in tests, a PEP
  723 header, asserting rendered colour values, matching only `scene:` lines.

## Steps

1. `plugin/Govee.qml`, `plugin/GoveeMenu.qml`: apply the rename and the import.
   → verify:
   `diff plugin/Govee.qml ~/.config/omarchy/plugins/olafkfreund.govee/Govee.qml && diff plugin/GoveeMenu.qml ~/.config/omarchy/plugins/olafkfreund.govee/GoveeMenu.qml`
   prints nothing, and
   `grep -nP '(?<![\w.])Color\.' plugin/*.qml` prints nothing.
   Traps: `Commons.Color.` must not become `Commons.Commons.Color.`. Don't
   touch lowercase `color:` properties or names that end in `Color`. File mode
   stays 0600.

2. `test_menu_qml.py:20–26`: replace the inline `GoveeMenu.qml` strip
   (lines 22–24) and the `Ui` symlink (line 26) with one helper,
   `strip_layershell(path)`, applied to `tmp/plugin/GoveeMenu.qml` and to
   every `*.qml` in a `shutil.copytree` of `omarchy/'shell/Ui'` into `tmp/'Ui'`.
   The copied files come from the Nix store and are read-only, so `chmod`
   them to 0644 before writing. Guard right after stripping: assert no copied
   `Ui/*.qml` contains `WlrLayershell.`. Also assert that in `Ui/KeyboardPanel.qml`
   the line before the stripped `keyboardFocus` block and the line after it
   are still present and unchanged (compare against the source file).
   `Commons` stays a symlink.
   → verify: `python3 test_menu_qml.py` (with `OMARCHY_PATH` set) still
   prints `QML runtime: … passed` with the menu-only test as it stands.
   Traps: leave the existing Wayland comment at lines 20–21 in place,
   reworded to cover `Ui/`.

3. `test_menu_qml.py`, QML string and the asserts after the run:
   - Line 68: add `Loader { id: barLoader; source: "plugin/Govee.qml" }`.
     Add `property var bar: barLoader.item`. Both loaders: on
     `status === Loader.Error`, `console.error("GOVEE_QML_FAIL: load " + source)`
     and `Qt.quit()`.
   - Lines 133–134: replace `GOVEE_QML_PASS` / `Qt.quit()` with
     `test.stage++; return`, then add stages, one per tick:
     3: `bar.open()`, check `bar.opened`;
     4: return until `bar.devices.length === 1 && bar.roomList.length >= 1`;
     5: `bar.expandedName = "room:Office"`, check it;
     6: `bar.expandedName = "AA:01"`, check it, then `GOVEE_QML_PASS`, `Qt.quit()`.
   - Line 139: raise the timeout from 8000 to 15000 ms. The extra stages and
     the bar's own `dump` take longer, and `subprocess.run(... timeout=20)`
     stays above it.
   - After line 167: add an output check. For each line, fail if it matches
     `\b(WARN|ERROR)\b` or contains `Error:`, unless it equals (after stripping)
     `WARN: $HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.`.
     Print the bad lines in the assertion message.
   - Add a static check: `re.search(r'(?<![\w.])Color\.', text)` over
     `ROOT/'plugin'/*.qml` must find nothing. Name file and line on failure.
   - Update the last print to say the bar panel was covered too.
   → verify: passes on the fixed repo. Then check that the test catches the
   bug: `git stash` only the step 1 files (or `git show HEAD~:plugin/…` into
   place), confirm the test fails on the bare-`Color` check and on QColor/
   `TypeError` warnings, and restore.
   Traps: the existing CLI assertion at lines 168–170 must stay exact. The
   bar sends only `dump`, which is already filtered. Don't send any action
   from the bar stages. Note `qs` prints `DEBUG qml:` lines for
   `console.log`, which are not `WARN`.

## Tests

```bash
export OMARCHY_PATH=/nix/store/q4l3pkaqwircaclc877pqxgy4l967mj8-nixarchy-omarchy-tree
python3 test_menu_qml.py
python3 test_omagovee.py
python3 test_reliability.py
node test_menu_model.js
uv run --with mcp==1.29.0 test_mcp.py
omarchy plugin validate plugin
diff -r plugin ~/.config/omarchy/plugins/olafkfreund.govee
```

All pass, and the `diff -r` prints nothing. Live: summon over IPC returns
`ok` and the shell log gets no new lines. The owner opens the bar panel,
expands a room and a device, checks the chips show the accent colour, and the
log stays quiet.

## Rollback

`git revert` the implementation commits. The installed copy is unaffected
until it is reinstalled. Host config: `~/.config/omarchy/shell.json.bak-govee`
restores the pre-fix `plugins[]`.
