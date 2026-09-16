# Keyboard Govee menu

## Request and review

Add a Quickshell pop-out, launched from a keybinding, with keyboard access to
all device controls currently offered by the bar panel. Keep the mouse panel.
No terminal, second shell process, new daemon, or Govee transport implementation.

## Research

- https://plugins.omarchy.org/develop.html documents `menu` entry points and
  `omarchy-shell shell summon/toggle/hide` lifecycle calls.
- The installed `$OMARCHY_PATH/shell/shell.qml` supports combined `menu` and
  `bar-widget` plugins. IPC uses the menu loader; bar clicks remain local.
- `$OMARCHY_PATH/shell/plugins/menu/Menu.qml` provides the reference for a
  centered, themed layer-shell window, keyboard focus and dismissal.
- `$OMARCHY_PATH/shell/Ui/PanelKeyCatcher.qml` consumes h/j/k/l and text keys;
  searchable controls need a focused text input with explicit navigation keys.
- A keep-loaded menu retains pending CLI actions after dismissal, without
  creating another process or polling when closed.

## Implementation

1. Extract CLI processes, refresh coalescing and ordered actions into a small
   `GoveeClient.qml`, used by both views. Preserve the existing bar behaviour.
2. Add `GoveeMenu.qml` as the plugin's `menu` entry point; keep `Govee.qml` as
   the `barWidget` entry point. Add `keepLoaded` and bump the plugin version.
3. Add a pure JS row model for searchable targets and actions, keeping MACs
   separate from labels. Include all devices, rooms/unassigned, and scenes.
4. Keyboard: Up/Down select, Enter activates, typing filters, Escape clears a
   filter/goes back/closes, Alt+Left goes back. Forms accept Enter and cancel
   with Escape. Show shortcut hints, selected state, busy state and errors.
5. Actions: explicit on/off; brightness 0–100; named/custom RGB; scenes;
   device labels; room assignment/unassignment/new room; room rename.
   Validate input before queueing and let the CLI enforce shared rules.
6. Add `omarchy-menu-lights` as a thin IPC launcher, with summon/toggle/close.
   Document a Hyprland Lua keybinding and legacy .conf equivalent. Do not
   modify live desktop configuration as part of repository implementation.

## Verification

- Pure model checks: duplicate display names, stable IDs, filtering, empty
  inventory, room and scene targets, input validation and command arguments.
- QML syntax and manifest validation against the installed shell.
- Virtual-display QML checks (Xvfb, Wayland surface hints omitted): navigation, forms, command queuing,
  menu lifecycle. Use fake command processes; never change real lights.
- Existing controller and MCP regression suites remain green.
- Real compositor focus, placement on multiple monitors and desktop binding
  remain manual acceptance checks after installing the plugin.

## Result

Implemented in `plugin/GoveeMenu.qml`, `plugin/GoveeMenuModel.js` and
`bin/omarchy-menu-lights`. Both UI entry points use `GoveeClient.qml` for
refreshes, queued actions and command errors. The combined manifest is version
3.0.0; IPC now routes to the menu while bar clicks retain the mouse panel.

Validation completed:

- Installed `omarchy plugin validate` accepts the manifest and layout.
- Qt's QML parser accepts the menu, client and existing bar entry point.
- `node test_menu_model.js` checks IDs, filtering, commands and validation.
- `python3 test_menu_qml.py` runs the menu through an asynchronous Loader on
  Xvfb with a fake CLI. It checks launcher arguments, input validation, keyboard
  handlers, form save/cancel, ordered commands after dismissal, and reopening.
  Only Wayland attached surface hints are omitted in the temporary X11 copy.
- The 22 existing controller/reliability checks pass; MCP integration passes.
- qmllint reports incomplete external metadata for Quickshell's dynamic
  PanelWindow backend and shell theme objects, so it is not claimed as clean.
  Runtime loading supplements syntax validation.

Live follow-up completed on 2026-09-16:

- Backed up the installed plugin and Hyprland bindings, then installed all five
  plugin files under `~/.config/omarchy/plugins/olafkfreund.govee/`.
- Added Super+Ctrl+Alt+G using direct shell IPC. Super+Ctrl+G was already assigned
  to recovering windows from disconnected monitors, so it was preserved.
- `hyprctl reload` succeeded and `hyprctl configerrors` was empty; the compositor
  lists the new binding with modifier mask 76.
- Restarted the shell after its existing QML engine reported a file-name case
  mismatch for the newly introduced menu file. After startup, summon succeeded
  and the compositor reported the `omagovee-menu` overlay on DP-2 (2560×1440).
  Closed the menu through IPC afterwards.
- The existing `omarchy-govee` command already links to this repository.
  No package installation or system rebuild was needed.

Real lamp writes, physical keyboard acceptance and moving the menu between
monitors remain untested. Automated navigation and action tests use a fake CLI.
