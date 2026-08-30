import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Govee light control.
//
// The icon reflects the state file that omarchy-govee writes after every
// action, not a live query: a bar widget must never block on the network, and
// the cloud state endpoint allows only 30 req/min/device — a redraw-driven
// poll would burn that in seconds.
BarWidget {
  id: root
  moduleName: "olafkfreund.govee"

  property bool lit: false
  property string label: ""

  function run(cmd) {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + cmd)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Toggling needs no terminal, so it skips the floating window entirely.
  Process {
    id: toggle
    command: ["omarchy-govee", "toggle"]
  }

  FileView {
    id: stateFile
    path: (Quickshell.env("HOME") || "") + "/.cache/omagovee/state.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var state = JSON.parse(text())
        var newest = null
        for (var mac in state)
          if (!newest || (state[mac].at || 0) > (newest.at || 0)) newest = state[mac]
        root.lit = newest ? newest.power === 1 : false
        root.label = newest ? (newest.name || "") : ""
      } catch (e) {
        root.lit = false
      }
    }
    onLoadFailed: root.lit = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-lightbulb_o when lit, nf-fa-power_off when not.
    text: root.lit ? "\uf0eb" : "\uf011"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: (root.label ? root.label + " · " : "")
      + (root.lit ? "on" : "off")
      + " · left: toggle, right: pick"

    onPressed: function (b) {
      if (b === Qt.RightButton) root.run("omarchy-cmd-lights")
      else toggle.running = true
    }
  }
}
