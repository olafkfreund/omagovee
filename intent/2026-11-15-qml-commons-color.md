---
status: draft
issue: none  # repo convention so far; add the issue number if one is opened
author: olafkfreund
---

# Intent: Make the repo plugin load without QML errors on the current shell

## Problem

On the current shell (Quickshell 0.3.2, Qt 6.12, nixarchy-omarchy-tree
`q4l3pkaq…`), the bare name `Color` in `plugin/GoveeMenu.qml` and
`plugin/Govee.qml` no longer resolves to the shell's `qs.Commons` `Color`
singleton. Running the repo plugin through `test_menu_qml.py` prints dozens of
`TypeError: Cannot read property 'text' of undefined` and
`Unable to assign [undefined] to QColor` (GoveeMenu.qml lines 236–273), so the
keyboard menu draws with no colours.

The installed copy in `~/.config/omarchy/plugins/olafkfreund.govee` was fixed
by hand on 2026-10-20 (`import qs.Commons as Commons`, `Commons.Color.…`). The
fix was never committed, so the next `cp -r plugin …` reinstall would bring the
errors back.

The QML test still reports a pass with those errors, because it only checks
the exit code and its own pass marker. It never loads `Govee.qml` either. So
this regression went unnoticed.

`test_mcp.py` cannot run with a bare `python3`
(`ModuleNotFoundError: No module named 'mcp'`).

## Proposed outcome

- A fresh install from the repo shows no QML warnings from either view on the
  current shell, live and in the offscreen test.
- `test_menu_qml.py` fails when either view logs a QML warning or error, and
  it loads `Govee.qml` as well as `GoveeMenu.qml`.
- `test_mcp.py` has a documented command that runs it.

## Affected users and systems

- `plugin/Govee.qml`, `plugin/GoveeMenu.qml`, `test_menu_qml.py`,
  `test_mcp.py` (or README).
- Host p620, where the plugin is installed. Out of scope: the host-side
  `shell.json` `plugins[]` entry, which was a one-line config change and is
  already applied and verified (summon returns `ok`, no log lines).

## Constraints

- Must match the installed, known-good patch and the shell's own convention
  (`Ui/TextField.qml` uses `import qs.Commons as Commons` / `Commons.Color`).
- Must not change behaviour, layout or the CLI.
- No new dependencies for the plugin. Test-only tooling is fine.

## Open questions

- Fix `test_mcp.py` with a PEP 723 header run by `uv run`, or only document
  the command in the README? (Leaning toward the header.)
