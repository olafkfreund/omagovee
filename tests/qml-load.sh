#!/usr/bin/env bash
# Compiles every plugin QML file headless against the installed Omarchy shell's qs.* modules.
# GoveeMenu.qml (PanelWindow) and Govee.qml (KeyboardPanel) need a live Wayland shell; only those two errors are allowed.
set -euo pipefail
here=$(cd "$(dirname "$0")/../plugin" && pwd)
shell=$(dirname "$(readlink -f "$(command -v omarchy-shell)")")/../shell
[[ -f $shell/shell.qml ]] || { echo "SKIP: no omarchy shell found"; exit 0; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for d in "$shell"/*/; do ln -s "$d" "$tmp/$(basename "$d")"; done
cp "$here"/* "$tmp/" 2>/dev/null || true
cat > "$tmp/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  Timer {
    interval: 100; running: true
    onTriggered: {
      var files = ["GoveeClient.qml", "Govee.qml", "GoveeMenu.qml"]
      for (var i = 0; i < files.length; i++) {
        var c = Qt.createComponent("file://" + Quickshell.env("PLUGDIR") + "/" + files[i], Component.PreferSynchronous)
        console.log("LOAD " + files[i] + " " + (c.status === Component.Ready ? "READY" : "ERROR " + c.errorString()))
      }
      Qt.quit()
    }
  }
}
QML
out=$(cd "$tmp" && PLUGDIR=$tmp QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$tmp/shell.qml" 2>&1 | grep -o 'LOAD .*' || true)
printf '%s\n' "$out"
fail=0
while IFS= read -r line; do
  case $line in
    *READY) ;;
    "LOAD GoveeMenu.qml ERROR"*"No PanelWindow backend loaded"*) ;;
    "LOAD Govee.qml ERROR"*"Type KeyboardPanel unavailable"*) ;;
    *) fail=1 ;;
  esac
done <<< "$out"
[[ $(grep -c '^LOAD ' <<< "$out") -eq 3 ]] || fail=1
(( fail == 0 )) || { echo "FAIL: plugin QML does not compile"; exit 1; }
echo "PASS: plugin QML compiles"
