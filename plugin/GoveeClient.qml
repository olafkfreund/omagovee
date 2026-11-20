pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared CLI boundary for both views, one instance (qmldir): a running command,
// its queue and the last snapshot survive the menu being unloaded.
// No device protocol or optimistic state.
Singleton {
  id: root
  property var snapshot: null
  property string error: ""
  property bool loading: false
  property bool refreshPending: false
  property var queue: []
  property string busyName: ""
  readonly property bool busy: actionProc.running || queue.length > 0
  property string runningOrigin: ""
  // Last menu-origin result not yet shown; a hidden or unloaded menu reads it on open.
  property var menuResult: null
  signal completed(bool success, string message, string origin)

  function refresh() {
    if (dumpProc.running) { refreshPending = true; return }
    loading = true
    dumpProc.running = true
  }

  function act(args, label, origin) {
    queue = queue.concat([{ args: args, label: label || "", origin: origin || "bar" }])
    pump()
  }

  function pump() {
    if (actionProc.running || !queue.length) return
    var job = queue[0]
    queue = queue.slice(1)
    busyName = job.label
    runningOrigin = job.origin
    actionProc.command = ["omarchy-govee"].concat(job.args)
    actionProc.running = true
  }

  Process {
    id: dumpProc
    command: ["omarchy-govee", "dump"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (!Array.isArray(parsed.devices) || !parsed.rooms || !Array.isArray(parsed.scenes))
            throw new Error("Invalid device data")
          root.error = parsed.devices.some(function (d) { return !!d.error })
            ? "Some devices could not be refreshed" : ""
          root.snapshot = parsed
        } catch (e) { root.error = "Could not refresh lights; displayed state is stale" }
      }
    }
    stderr: StdioCollector { id: dumpErr; waitForEnd: true }
    onExited: function (code) {
      root.loading = false
      if (code !== 0) root.error = dumpErr.text.trim() || "Could not refresh lights"
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (code) {
      var text = actionErr.text.trim() || actionOut.text.trim()
      if (root.runningOrigin === "menu") root.menuResult = { success: code === 0, message: text }
      root.completed(code === 0, text, root.runningOrigin)
      root.busyName = ""
      Qt.callLater(function () {
        root.pump()
        if (!root.busy) root.refresh()
      })
    }
  }
}
