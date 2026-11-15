---
status: draft
issue: none  # repo convention so far; add the issue number if one is opened
spec: spec/2026-11-15-qml-commons-color.md
coders:
  1: agy     # mechanical rename across 24 sites in two files, checked by diff against the installed copy
  2: coder   # test harness helper; same agent as step 3 so line shifts in one file stay with one author
  3: coder   # new QML test stages and output filters, same file as step 2
reviewers:
  - codex    # wrote nothing here, so it reviews the whole diff independently
  - agy      # reviews steps 2–3 (it did not write them); its own step 1 is checked mechanically by diff, not by its review
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
  wait for the first data, open, expand a room, then a device. It fails on
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
   The copy comes from the Nix store and is read-only: `chmod` every copied
   directory to 0755 and every file to 0644 before writing, and walk with
   `rglob('*.qml')` (Ui/ may have subdirectories).
   Guard right after stripping, in Python:
   - no copied `Ui/**/*.qml` contains `WlrLayershell.`;
   - in the copied `KeyboardPanel.qml`, none of the three source lines 157–159
     remain (157 `WlrLayershell.keyboardFocus: open && !yielding`, 158
     `? (focusPrimed ? WlrKeyboardFocus.OnDemand : …`, 159
     `: WlrKeyboardFocus.None`), so no line contains `WlrKeyboardFocus.`
     outside a removed statement. Check by content, not line number;
   - the bindings next to it survive: `onBackingWindowVisibleChanged:
     beginFocusPrime()` (source line 161) is still present, and every source
     line that is not part of a stripped statement is still in the copy, in
     order (so only stripped statements were removed).
   `Commons` stays a symlink.
   → verify: `python3 test_menu_qml.py` (with `OMARCHY_PATH` set) still
   prints `QML runtime: … passed` with the menu-only test as it stands.
   Traps: leave the existing Wayland comment at lines 20–21 in place,
   reworded to cover `Ui/`.

3. `test_menu_qml.py`, QML string and the asserts after the run:
   - Line 68: add
     `Loader { id: barLoader; source: "plugin/Govee.qml"; asynchronous: true }`,
     the same as the menu loader. Add `property var bar: barLoader.item`.
     Don't quit on `Loader.Error` inside the loader. Instead, at the top of the
     timer handler, if either loader's `status === Loader.Error`, call
     `test.check(false, "load failed: " + source)`. That way it fails through
     the existing catch, after the event loop is running.
   - Lines 133–134: replace `GOVEE_QML_PASS` / `Qt.quit()` with
     `test.stage++; return`. Then add stages, each ending in `test.stage++; return`
     so there is exactly one stage per tick:
     3: `return` while `!bar`; then return until
        `bar.devices.length === 1 && bar.roomList.length >= 1 && !bar.loading`
        (first `dump`, started by `Component.onCompleted: refresh()`, Govee.qml:143);
     4: `bar.open()`, check `bar.opened`; the refresh that `open()` starts
        (Govee.qml:88) only sends `dump`;
     5: return while `bar.loading`; then `bar.expandedName = "room:Office"`,
        check it;
     6: `bar.expandedName = "AA:01"`, check it, then `GOVEE_QML_PASS`, `Qt.quit()`.
   - Line 139: raise the QML timeout from 8000 to 15000 ms, and the
     `subprocess.run(..., timeout=20)` at line 157 to 25, so a QML timeout
     reports instead of being killed.
   - After line 167: add an output check. For each line, fail if it matches
     `\b(WARN|ERROR)\b` or contains `Error:`, unless it equals (after stripping)
     `WARN: $HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.`.
     Print the bad lines in the assertion message.
   - Add a static check: `re.search(r'(?<![\w.])Color\.', text)` over
     `ROOT/'plugin'/*.qml` must find nothing. Name file and line on failure.
   - Update the last print to say the bar panel was covered too.
   → verify: passes on the fixed repo.
   The negative check is done by the lead, not the coder, and never with git
   in the worktree. Copy the repo to a scratch dir, put the pre-fix files in
   place there with `git show a8de62d:plugin/Govee.qml` and
   `git show a8de62d:plugin/GoveeMenu.qml`, and run the test twice:
   (a) as is: it must fail on the bare-`Color` check;
   (b) with the bare-`Color` check temporarily disabled in the scratch copy:
   it must fail on `QColor`/`TypeError` warnings.
   Each check is proven to fire on its own.
   Traps: the existing CLI assertion at lines 168–170 must stay exact. The
   bar sends only `dump`, which is already filtered. Don't send any action
   from the bar stages. Note `qs` prints `DEBUG qml:` lines for
   `console.log`, which are not `WARN`.

## Tests

Coders: never stage, commit, stash, switch or push. The lead commits each step.

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

All pass, and the `diff -r` prints nothing.

Live, run by the lead after reinstalling from the repo:

```bash
cp plugin/* ~/.config/omarchy/plugins/olafkfreund.govee/
omarchy restart shell
L=$(ls -td /run/user/1000/quickshell/by-id/*/ | head -1)log.log; n=$(wc -l < "$L")
omarchy-shell shell summon olafkfreund.govee '{}'   # expect: ok
omarchy-shell shell hide olafkfreund.govee
tail -n +$((n+1)) "$L"                               # expect: no govee/WARN lines
```

The owner then opens the bar panel, expands a room and a device, and checks
that the chips show the accent colour. The lead re-reads the log tail, which
should still be quiet.

## Rollback

`git revert` the implementation commits. The installed copy is unaffected
until it is reinstalled. Host config: `~/.config/omarchy/shell.json.bak-govee`
restores the pre-fix `plugins[]`.
