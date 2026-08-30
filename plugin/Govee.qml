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
  property var roomNames: []     // room keys only, for the assign chips
  property var scenes: []
  property string expandedName: ""
  property bool loading: false
  property bool lit: false
  property string busyName: ""
  // PanelKeyCatcher eats plain keys before descendants see them; while a name
  // field is focused it has to stand down or "a" toggles a light mid-word.
  property int editors: 0
  // Name of the device currently being dragged, "" when none. Three things
  // read it: the Flickable (stops scrolling), the delegates (raise z so the
  // dragged row is not painted under the sections below it), and the room
  // headers (grow into a target you can actually hit).
  property string dragName: ""
  property string dragRoom: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // nf-md glyphs per device kind; `kind` comes from the CLI, which is the one
  // place that knows how to read a Govee SKU.
  readonly property var kindIcons: {
    "bulb":   "󰌵",
    "strip":  "󰟕",
    "string": "󱊺",
    "lamp":   "󰚵"
  }

  function kindIcon(kind) {
    return kindIcons[kind] || kindIcons["bulb"]
  }

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
    root.roomNames = names

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
    // nf-md-lightbulb_on / nf-md-lightbulb_outline. The size is deliberately
    // NOT overridden: BarIconButton defaults to Style.bar.iconFont in the
    // iconSlot, which is what every other icon on the bar is drawn at.
    text: root.lit ? "󰛨" : "󰌶"
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
      blocked: root.editors > 0
      onCloseRequested: root.close()

      Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // A Flickable claims any drag that passes its threshold, so a drag
        // that started on a grip would scroll the list instead of moving the
        // row. It stands down for the duration.
        interactive: root.dragName === ""

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
          // Delegates name their model (`room`, `dev`) instead of walking
          // parent.parent.parent: the chains broke every time the tree gained
          // a level, and silently — a wrong `parent` reads as undefined.
          Repeater {
            model: root.roomList

            delegate: Column {
              id: roomItem
              required property var modelData
              readonly property var room: modelData
              readonly property bool editing: root.expandedName === "room:" + room.name
              width: column.width
              spacing: Style.space(4)
              z: root.dragRoom === room.name ? 100 : 0

              Item {
                width: parent.width
                // Grows during a drag: a one-line header is a miserable thing
                // to aim at.
                implicitHeight: roomHeader.implicitHeight
                  + (root.dragName !== "" ? Style.space(14) : 0)

                DropArea {
                  id: roomDrop
                  anchors.fill: parent
                  keys: ["govee-device"]
                  onDropped: function (drop) {
                    // "other" is not a room, it is the devices in none of them.
                    var target = roomItem.room.name === "other"
                      ? "none" : roomItem.room.name
                    if (drop.source.devRoom !== roomItem.room.name)
                      root.act(["rooms", "assign", target, drop.source.devName], "")
                    drop.accept()
                  }
                }

                Rectangle {
                  anchors.fill: parent
                  z: -1
                  visible: roomDrop.containsDrag
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: 1
                  border.color: Style.selectedFillFor(root.bar.foreground, Color.accent)
                }

                PanelSectionHeader {
                  id: roomHeader
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: roomItem.room.name
                  foreground: root.bar ? root.bar.foreground : Color.foreground

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.expandedName =
                      roomItem.editing ? "" : "room:" + roomItem.room.name
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  PanelActionButton {
                    iconText: "\uf011"
                    tooltipText: "All off"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    onClicked: root.act(["off", "room:" + roomItem.room.name], "")
                  }
                  PanelActionButton {
                    iconText: "\uf0eb"
                    tooltipText: "All on"
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    onClicked: root.act(["on", "room:" + roomItem.room.name], "")
                  }
                }
              }

              // ----- whole-room controls, shown by clicking the room name -----
              Column {
                width: parent.width
                spacing: Style.space(6)
                visible: roomItem.editing
                height: visible ? implicitHeight : 0

                TextField {
                  width: parent.width
                  text: roomItem.room.name
                  placeholderText: "Room name"
                  verticalPadding: Style.space(3)
                  foreground: root.bar ? root.bar.foreground : Color.foreground
                  enabled: roomItem.room.name !== "other"
                  onActiveFocusChanged: root.editors += activeFocus ? 1 : -1
                  onAccepted: {
                    if (text && text !== roomItem.room.name) {
                      root.act(["rooms", "rename", roomItem.room.name, text], "")
                      root.expandedName = ""
                    }
                    focus = false
                  }
                }

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
                              "room:" + roomItem.room.name], "")
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
                      border.width: roomSwatch.containsMouse ? 2 : 1
                      border.color: root.bar ? root.bar.foreground : Color.foreground

                      MouseArea {
                        id: roomSwatch
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.act(["color", parent.modelData.name,
                                             "room:" + roomItem.room.name], "")
                      }
                    }
                  }
                }

                PanelSeparator { width: parent.width }
              }

              Repeater {
                model: roomItem.room.members

                delegate: Column {
                  id: devItem
                  required property var modelData
                  readonly property var dev: modelData
                  readonly property bool isExpanded: root.expandedName === dev.name
                  width: column.width
                  spacing: Style.space(4)

                  // ----- device row -----
                  Item {
                    width: parent.width
                    implicitHeight: Math.max(nameText.implicitHeight, sw.implicitHeight)
                    z: root.dragName === devItem.dev.name ? 100 : 0

                    // Only `content` moves while dragging. The row keeps its
                    // slot in the Column, so the list does not reflow under
                    // the cursor mid-drag and the drop lands where you aimed.
                    Item {
                      id: content
                      width: parent.width
                      height: parent.height
                      opacity: Drag.active ? 0.6 : 1.0

                      // Read back off `drop.source` by the room that catches it.
                      property string devName: devItem.dev.name
                      property string devRoom: roomItem.room.name

                      Drag.active: gripArea.drag.active
                      Drag.source: content
                      Drag.keys: ["govee-device"]
                      Drag.hotSpot.x: width / 2
                      Drag.hotSpot.y: height / 2

                      Text {
                        id: grip
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u2630"
                        color: root.bar ? root.bar.foreground : Color.foreground
                        opacity: gripArea.containsMouse || gripArea.drag.active ? 0.9 : 0.35
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption

                        MouseArea {
                          id: gripArea
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          hoverEnabled: true
                          cursorShape: Qt.OpenHandCursor
                          drag.target: content
                          drag.smoothed: false
                          onPressed: {
                            root.dragName = devItem.dev.name
                            root.dragRoom = roomItem.room.name
                          }
                          onReleased: {
                            content.Drag.drop()
                            content.x = 0
                            content.y = 0
                            root.dragName = ""
                            root.dragRoom = ""
                          }
                        }
                      }

                      Text {
                        id: typeIcon
                        anchors.left: grip.right
                        anchors.leftMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.kindIcon(devItem.dev.kind)
                        color: root.bar ? root.bar.foreground : Color.foreground
                        opacity: devItem.dev.online ? 0.85 : 0.35
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        id: nameText
                        anchors.left: typeIcon.right
                        anchors.leftMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: (devItem.dev.label || devItem.dev.name)
                          + (devItem.dev.online ? "" : "  (offline)")
                          + (devItem.dev.ip ? "  ·  lan" : "")
                        color: root.bar ? root.bar.foreground : Color.foreground
                        opacity: devItem.dev.online ? 1.0 : 0.45
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption

                        MouseArea {
                          anchors.fill: parent
                          onClicked: root.expandedName =
                            devItem.isExpanded ? "" : devItem.dev.name
                        }
                      }

                      ToggleSwitch {
                        id: sw
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: devItem.dev.power === 1
                        interactive: devItem.dev.online
                        busy: root.busyName === devItem.dev.name
                        foreground: root.bar ? root.bar.foreground : Color.foreground
                        onToggled: root.act([checked ? "off" : "on", devItem.dev.name],
                                            devItem.dev.name)
                      }
                    }
                  }

                  // ----- expanded controls -----
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    visible: devItem.isExpanded
                    height: visible ? implicitHeight : 0

                    TextField {
                      width: parent.width
                      text: devItem.dev.label
                      // The device keeps the name Govee knows it by; this only
                      // changes what the panel calls it. Empty clears it.
                      placeholderText: "Friendly name for " + devItem.dev.name
                      verticalPadding: Style.space(3)
                      foreground: root.bar ? root.bar.foreground : Color.foreground
                      onActiveFocusChanged: root.editors += activeFocus ? 1 : -1
                      onAccepted: {
                        root.act(["label", devItem.dev.name].concat(
                          text ? [text] : []), "")
                        focus = false
                      }
                    }

                    Flow {
                      width: parent.width
                      spacing: Style.space(5)

                      Repeater {
                        model: root.roomNames.concat(["none"])
                        delegate: Rectangle {
                          required property string modelData
                          readonly property bool current:
                            modelData === roomItem.room.name
                          radius: Style.cornerRadius
                          color: current || chipMouse.containsMouse
                            ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                            : "transparent"
                          border.width: 1
                          border.color: Style.selectedFillFor(root.bar.foreground,
                                                              Color.accent)
                          implicitWidth: chipLabel.implicitWidth + Style.space(12)
                          implicitHeight: chipLabel.implicitHeight + Style.space(6)

                          Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: root.bar ? root.bar.foreground : Color.foreground
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                          }

                          MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.act(["rooms", "assign",
                                                 parent.modelData, devItem.dev.name], "")
                          }
                        }
                      }
                    }

                    PanelSlider {
                      width: parent.width
                      bar: root.bar
                      minimum: 1
                      maximum: 100
                      step: 1
                      integer: true
                      value: 50
                      onReleased: function (v) {
                        root.act(["brightness", String(Math.round(v)), devItem.dev.name],
                                 devItem.dev.name)
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
                            onClicked: root.act(["color", parent.modelData.name,
                                                 devItem.dev.name], devItem.dev.name)
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
