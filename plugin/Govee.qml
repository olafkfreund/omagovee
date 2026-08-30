import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Govee lights: a bar button that opens a dropdown of scenes, rooms and
// per-device controls.
//
// All state comes from `omarchy-govee dump` (one JSON document, states fetched
// concurrently ~1.2s for 15 devices) and every action shells back out to the
// same CLI. The panel deliberately holds no protocol knowledge: LAN vs cloud,
// retries and read-back verification all live in the command, so the GUI and
// the terminal can never disagree about what a light is doing.
// Root type is BarWidget, not Ui.Panel: the Panel base resolves only inside
// the shell's own module path, and a third-party plugin using it fails to load
// with "File name case mismatch". Open/close state is held here instead.
BarWidget {
  id: root
  moduleName: "olafkfreund.govee"

  property bool opened: false
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  property var devices: []
  property var roomList: []      // [{ name, members: [device] }]
  property var scenes: []
  property string expandedName: ""
  property bool loading: false
  property bool lit: false
  property string busyName: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var swatches: [
    { name: "warm",   rgb: "#ff9329" },
    { name: "cool",   rgb: "#cce0ff" },
    { name: "white",  rgb: "#ffffff" },
    { name: "red",    rgb: "#ff0000" },
    { name: "orange", rgb: "#ff8800" },
    { name: "yellow", rgb: "#ffdd00" },
    { name: "green",  rgb: "#00ff00" },
    { name: "blue",   rgb: "#0000ff" },
    { name: "purple", rgb: "#8000ff" },
    { name: "pink",   rgb: "#ff40a0" }
  ]

  onOpenedChanged: if (opened) refresh()

  function refresh() {
    if (dumpProc.running) return
    loading = true
    dumpProc.running = true
  }

  // One Process can run one command. Clicking three rows quickly would
  // otherwise overwrite the in-flight command and silently drop two of them,
  // so actions queue and run in order.
  property var queue: []

  function act(args, label) {
    queue.push({ args: args, label: label || "" })
    pump()
  }

  function pump() {
    if (actionProc.running || queue.length === 0) return
    var job = queue.shift()
    root.busyName = job.label
    actionProc.command = ["omarchy-govee"].concat(job.args)
    actionProc.running = true
  }

  function deviceByName(name) {
    for (var i = 0; i < devices.length; i++)
      if (devices[i].name === name) return devices[i]
    return null
  }

  function applyDump(text) {
    var data = JSON.parse(text)
    root.devices = data.devices || []
    root.scenes = data.scenes || []

    // Flatten rooms into draw order, with everything unassigned last, so the
    // list is stable between refreshes rather than reordering under the cursor.
    var assigned = {}
    var list = []
    var names = Object.keys(data.rooms || {}).sort()
    for (var i = 0; i < names.length; i++) {
      var members = []
      for (var j = 0; j < data.devices.length; j++) {
        if ((data.rooms[names[i]] || []).indexOf(data.devices[j].name) >= 0) {
          members.push(data.devices[j])
          assigned[data.devices[j].name] = true
        }
      }
      if (members.length > 0) list.push({ name: names[i], members: members })
    }
    var rest = []
    for (var k = 0; k < data.devices.length; k++)
      if (!assigned[data.devices[k].name]) rest.push(data.devices[k])
    if (rest.length > 0) list.push({ name: "other", members: rest })
    root.roomList = list

    var anyOn = false
    for (var m = 0; m < root.devices.length; m++)
      if (root.devices[m].power === 1) anyOn = true
    root.lit = anyOn
  }

  Process {
    id: dumpProc
    command: ["omarchy-govee", "dump"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.applyDump(text) } catch (e) { }
        root.loading = false
      }
    }
    onExited: root.loading = false
  }

  Process {
    id: actionProc
    onExited: {
      root.busyName = ""
      root.pump()
      // Re-read rather than assume: a command can fail (offline device, a
      // dropped LAN packet the CLI could not recover) and the panel must show
      // what happened, not what was asked for.
      if (root.queue.length === 0 && root.opened) root.refresh()
    }
  }

  // One source of truth: the same dump the panel draws from also decides the
  // bar icon. A file-watch cache used to do this, but inotify does not survive
  // the CLI replacing the file, and a second copy of the state is a second
  // thing that can be wrong.
  Component.onCompleted: refresh()

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: if (!root.opened) root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-fa-lightbulb_o when anything is lit, nf-fa-power_off when not.
    text: root.lit ? "\uf0eb" : "\uf011"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Lights"
    onPressed: function (b) {
      if (b === Qt.RightButton) root.act(["toggle"], "")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: parent.width
          spacing: Style.space(10)

          // ---------- scenes ----------
          PanelSectionHeader {
            text: root.loading ? "Scenes · refreshing…" : "Scenes"
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.scenes
              delegate: Rectangle {
                required property string modelData
                radius: Style.cornerRadius
                color: sceneMouse.containsMouse
                  ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                  : "transparent"
                border.width: 1
                border.color: Style.selectedFillFor(root.bar.foreground, Color.accent)
                implicitWidth: sceneLabel.implicitWidth + Style.space(16)
                implicitHeight: sceneLabel.implicitHeight + Style.space(8)

                Text {
                  id: sceneLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: sceneMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.act(["scene", parent.modelData], parent.modelData)
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---------- rooms and devices ----------
          Repeater {
            model: root.roomList

            delegate: Column {
              required property var modelData
              width: column.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: roomHeader.implicitHeight

                PanelSectionHeader {
                  id: roomHeader
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.parent.modelData.name
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  PanelActionButton {
                    iconText: "\uf011"
                    tooltipText: "All off"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    onClicked: root.act(["off", "room:" + parent.parent.parent.modelData.name], "")
                  }
                  PanelActionButton {
                    iconText: "\uf0eb"
                    tooltipText: "All on"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    onClicked: root.act(["on", "room:" + parent.parent.parent.modelData.name], "")
                  }
                }
              }

              Repeater {
                model: parent.modelData.members

                delegate: Column {
                  required property var modelData
                  width: column.width
                  spacing: Style.space(4)

                  readonly property bool isExpanded: root.expandedName === modelData.name

                  // ----- device row -----
                  Item {
                    width: parent.width
                    implicitHeight: Math.max(nameText.implicitHeight, sw.implicitHeight)

                    Text {
                      id: nameText
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: parent.parent.modelData.name
                        + (parent.parent.modelData.online ? "" : "  (offline)")
                        + (parent.parent.modelData.ip ? "  ·  lan" : "")
                      color: root.bar ? root.bar.foreground : Color.foreground
                      opacity: parent.parent.modelData.online ? 1.0 : 0.45
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption

                      MouseArea {
                        anchors.fill: parent
                        onClicked: root.expandedName =
                          root.expandedName === nameText.parent.parent.modelData.name
                            ? "" : nameText.parent.parent.modelData.name
                      }
                    }

                    ToggleSwitch {
                      id: sw
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      checked: parent.parent.modelData.power === 1
                      interactive: parent.parent.modelData.online
                      busy: root.busyName === parent.parent.modelData.name
                      foreground: root.bar ? root.bar.foreground : Color.foreground
                      onToggled: root.act(
                        [checked ? "off" : "on", sw.parent.parent.modelData.name],
                        sw.parent.parent.modelData.name)
                    }
                  }

                  // ----- expanded controls -----
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: parent.isExpanded
                    height: visible ? implicitHeight : 0

                    PanelSlider {
                      width: parent.width
                      bar: root.bar
                      minimum: 1
                      maximum: 100
                      step: 1
                      integer: true
                      value: 50
                      onReleased: function (v) {
                        root.act(["brightness", String(Math.round(v)),
                                  parent.parent.modelData.name],
                                 parent.parent.modelData.name)
                      }
                    }

                    Flow {
                      width: parent.width
                      spacing: Style.space(5)

                      Repeater {
                        model: root.swatches
                        delegate: Rectangle {
                          required property var modelData
                          width: Style.space(20)
                          height: Style.space(20)
                          radius: Style.cornerRadius > 0 ? width / 2 : 0
                          color: modelData.rgb
                          border.width: swatchMouse.containsMouse ? 2 : 1
                          border.color: root.bar ? root.bar.foreground : Color.foreground

                          MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.act(
                              ["color", parent.modelData.name,
                               parent.parent.parent.parent.modelData.name],
                              parent.parent.parent.parent.modelData.name)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
