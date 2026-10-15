import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Govee lights: a bar button that opens a dropdown of scenes, rooms and
// per-device controls.
//
// All state comes from `omarchy-govee dump` (one JSON document, states fetched
// with concurrent cloud reads) and every action shells back out to the
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
  readonly property bool loading: client.loading
  readonly property string refreshError: client.error
  property bool lit: false
  readonly property string busyName: client.busyName
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

  // Tokens from eldtechnologies/omarchy-plugin-govee Panel.qml (MIT).
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color surface: Util.alpha(foreground, 0.05)
  property int onLights: 0

  // Swatch colour of a light; transparent when it is off or has no reading.
  function dotColor(dev) {
    if (dev.power !== 1 || !dev.color) return "transparent"
    return Qt.rgba(dev.color.r / 255, dev.color.g / 255, dev.color.b / 255, 1)
  }

  // "60% · LAN": state first, then the transport when the read reported one.
  function subtitle(dev) {
    var parts = []
    if (dev.power === 1)
      parts.push(typeof dev.brightness === "number" ? dev.brightness + "%" : "on")
    else
      parts.push(dev.online === false ? "offline" : "off")
    if (dev.transport) parts.push(dev.transport === "lan" ? "LAN" : "cloud")
    return parts.join(" · ")
  }

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

  function refresh() { client.refresh() }
  function act(args, label) { client.act(args, label) }

  GoveeClient {
    id: client
    onSnapshotChanged: if (snapshot) root.applyDump(JSON.stringify(snapshot))
    onCompleted: function (success, message) {
      if (!success)
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Omarchy",
                                 "Govee failed", message || "Command failed"])
    }
  }

  function applyDump(text) {
    var data = JSON.parse(text)
    if (!data.devices || !data.rooms || !data.scenes) throw new Error("Invalid dump")
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
        if ((data.rooms[names[i]] || []).indexOf(data.devices[j].mac) >= 0
            || (data.rooms[names[i]] || []).indexOf(data.devices[j].name) >= 0) {
          members.push(data.devices[j])
          assigned[data.devices[j].mac] = true
        }
      }
      if (members.length > 0) list.push({ name: names[i], members: members })
    }
    var rest = []
    for (var k = 0; k < data.devices.length; k++)
      if (!assigned[data.devices[k].mac]) rest.push(data.devices[k])
    if (rest.length > 0) list.push({ name: "other", members: rest })
    root.roomList = list
    root.roomNames = names

    var onCount = 0
    for (var m = 0; m < root.devices.length; m++)
      if (root.devices[m].power === 1) onCount++
    root.lit = onCount > 0
    root.onLights = onCount
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
    onTriggered: if (root.editors === 0 && !root.dragName) root.refresh()
  }

  // From eldtechnologies/omarchy-plugin-govee Panel.qml (MIT).
  component ActionButton: Button {
    property string label: ""
    property bool outlined: false
    signal triggered()

    text: label
    bordered: outlined
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    opacity: enabled ? 1 : 0.4
    onClicked: if (enabled) triggered()
  }

  // From eldtechnologies/omarchy-plugin-govee Panel.qml (MIT).
  // A rainbow strip: click or drag to pick a saturated colour.
  component HueStrip: Item {
    id: strip
    signal picked(string hex)
    implicitHeight: Style.space(20)

    function colorAt(x) {
      return String(Qt.hsva(Math.max(0, Math.min(0.999, x / width)), 1, 1, 1))
    }

    Rectangle {
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, height / 2)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#ff0000" }
        GradientStop { position: 0.17; color: "#ffff00" }
        GradientStop { position: 0.33; color: "#00ff00" }
        GradientStop { position: 0.5; color: "#00ffff" }
        GradientStop { position: 0.67; color: "#0000ff" }
        GradientStop { position: 0.83; color: "#ff00ff" }
        GradientStop { position: 1.0; color: "#ff0000" }
      }
    }

    Rectangle {
      id: marker
      visible: hueMouse.pressed
      width: Style.space(4)
      height: parent.height + Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(parent.width - width, hueMouse.mouseX - width / 2))
      color: root.foreground
      radius: width / 2
    }

    MouseArea {
      id: hueMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onReleased: function(mouse) { strip.picked(strip.colorAt(mouse.x)) }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-lightbulb_on / nf-md-lightbulb_outline. The size is deliberately
    // NOT overridden: BarIconButton defaults to Style.bar.iconFont in the
    // iconSlot, which is what every other icon on the bar is drawn at.
    text: root.refreshError ? "!" : (root.lit ? "󰛨" : "󰌶")
    tooltipText: root.refreshError || "Lights"
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
    contentHeight: panel.fittedContentHeight(
      header.implicitHeight + Style.space(10) + column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editors > 0
      onCloseRequested: {
        if (root.expandedName !== "") root.expandedName = ""
        else root.close()
      }

      // Pinned above the scroll area. Not wrapped in a Column with the
      // Flickable: that would re-indent the whole list for no behaviour change.
      Row {
        id: header
        width: parent.width
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          width: parent.width - actions.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "GOVEE" + (root.devices.length
                           ? "  ·  " + root.onLights + "/" + root.devices.length + " ON" : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Row {
          id: actions
          spacing: Style.space(6)

          ActionButton {
            label: "All on"
            outlined: true
            onTriggered: root.act(["on", "all"], "")
          }
          ActionButton {
            label: "All off"
            outlined: true
            onTriggered: root.act(["off", "all"], "")
          }
        }
      }

      Flickable {
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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
            foreground: root.foreground
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
                  ? Util.alpha(root.foreground, 0.09)
                  : "transparent"
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.35)
                implicitWidth: sceneLabel.implicitWidth + Style.space(16)
                implicitHeight: sceneLabel.implicitHeight + Style.space(8)

                Text {
                  id: sceneLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: root.foreground
                  font.family: root.fontFamily
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

            delegate: Item {
              id: roomItem
              required property var modelData
              readonly property var room: modelData
              readonly property bool editing: root.expandedName === "room:" + room.name
              readonly property bool isOther: room.name === "other"
              readonly property var lit: room.members.filter(function (d) { return d.power === 1 })
              readonly property int onMembers: lit.length
              readonly property var firstOn: lit.length ? lit[0] : null
              readonly property var levels: room.members.map(function (d) { return d.brightness })
                .filter(function (v) { return typeof v === "number" })
              readonly property int avg: levels.length
                ? Math.round(levels.reduce(function (a, b) { return a + b }, 0) / levels.length) : 0
              width: column.width
              implicitHeight: roomCol.implicitHeight
              z: root.dragRoom === room.name ? 100 : 0

              Column {
                id: roomCol
                width: parent.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  // Grows during a drag: a one-line header is a miserable thing
                  // to aim at.
                  implicitHeight: (roomItem.isOther
                      ? roomHeader.implicitHeight : cardCol.implicitHeight + Style.space(16))
                    + (root.dragName !== "" ? Style.space(14) : 0)

                  // "other" is not a room: plain heading, no card, no switch.
                  PanelSectionHeader {
                    id: roomHeader
                    visible: roomItem.isOther
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: roomItem.room.name
                    foreground: root.foreground

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.expandedName =
                        roomItem.editing ? "" : "room:" + roomItem.room.name
                    }
                  }

                  Rectangle {
                    visible: !roomItem.isOther
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: root.surface

                    Column {
                      id: cardCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.space(8)
                      spacing: Style.space(6)

                      Item {
                        width: parent.width
                        implicitHeight: Math.max(titleCol.implicitHeight, roomSw.implicitHeight)

                        Rectangle {
                          id: roomDot
                          width: Style.space(14)
                          height: width
                          radius: width / 2
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          color: roomItem.firstOn ? root.dotColor(roomItem.firstOn) : "transparent"
                          border.width: 1
                          border.color: Util.alpha(root.foreground, 0.2)
                        }

                        Column {
                          id: titleCol
                          anchors.left: roomDot.right
                          anchors.leftMargin: Style.space(8)
                          anchors.right: roomSw.left
                          anchors.rightMargin: Style.space(8)
                          anchors.verticalCenter: parent.verticalCenter

                          Text {
                            width: parent.width
                            text: roomItem.room.name
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                          }
                          Text {
                            width: parent.width
                            text: roomItem.onMembers + " of " + roomItem.room.members.length + " on"
                              + (roomItem.levels.length ? " · " + roomItem.avg + "%" : "")
                              + (roomItem.editing ? "  ▴" : "  ▾")
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                          }
                        }

                        // Covers the title only, not the switch.
                        MouseArea {
                          anchors.left: parent.left
                          anchors.right: roomSw.left
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.expandedName =
                            roomItem.editing ? "" : "room:" + roomItem.room.name
                        }

                        ToggleSwitch {
                          id: roomSw
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          checked: roomItem.onMembers > 0
                          foreground: root.foreground
                          cursorRing: false
                          onToggled: root.act([checked ? "off" : "on", "room:" + roomItem.room.name], "")
                        }
                      }

                      PanelSlider {
                        visible: roomItem.onMembers > 0 && roomItem.levels.length > 0
                        width: parent.width
                        bar: root.bar
                        minimum: 0
                        maximum: 100
                        step: 1
                        integer: true
                        value: roomItem.avg
                        onReleased: function (v) {
                          root.act(["brightness", String(Math.round(v)),
                                    "room:" + roomItem.room.name], "")
                        }
                      }
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
                    foreground: root.foreground
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
                        border.color: root.foreground

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

                  HueStrip {
                    width: parent.width
                    onPicked: function (hex) {
                      root.act(["color", hex, "room:" + roomItem.room.name], "")
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
                    readonly property bool isExpanded: root.expandedName === dev.mac
                    width: column.width
                    spacing: Style.space(4)

                    // ----- device row -----
                    Item {
                      width: parent.width
                      implicitHeight: Math.max(nameText.implicitHeight, sw.implicitHeight)
                      z: root.dragName === devItem.dev.mac ? 100 : 0

                      // Only `content` moves while dragging. The row keeps its
                      // slot in the Column, so the list does not reflow under
                      // the cursor mid-drag and the drop lands where you aimed.
                      Item {
                        id: content
                        width: parent.width
                        height: parent.height
                        opacity: Drag.active ? 0.6 : 1.0

                        // Read back off `drop.source` by the room that catches it.
                        property string devName: devItem.dev.mac
                        property string devRoom: roomItem.room.name

                        Drag.active: dragArea.drag.active
                        Drag.source: content
                        Drag.keys: ["govee-device"]
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        // Dragging and scrolling are the same gesture, so they
                        // get different territory: this handle column drags, the
                        // rest of the row still flicks the list.
                        //
                        // preventStealing is the load-bearing line. A Flickable
                        // filters its children's mouse events and takes the grab
                        // the moment the pointer passes its own threshold, so
                        // without it the drag never starts and the panel scrolls
                        // instead — which is exactly what it did.
                        MouseArea {
                          id: dragArea
                          anchors.left: parent.left
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          width: Style.space(24)
                          hoverEnabled: true
                          preventStealing: true
                          cursorShape: drag.active ? Qt.ClosedHandCursor
                                                   : Qt.OpenHandCursor
                          drag.target: content
                          drag.smoothed: false
                          drag.threshold: 4

                          // Announced once the drag is real, not on press: a
                          // stray click should not make every room heading jump.
                          onPositionChanged: {
                            if (drag.active && root.dragName === "") {
                              root.dragName = devItem.dev.mac
                              root.dragRoom = roomItem.room.name
                              // Left in deliberately: this gesture cannot be
                              // tested from a shell, so the journal is the only
                              // evidence of where it broke.
                              console.log("govee drag start", root.dragName,
                                          "from", root.dragRoom)
                            }
                          }
                          onReleased: {
                            if (drag.active) content.Drag.drop()
                            content.x = 0
                            content.y = 0
                            root.dragName = ""
                            root.dragRoom = ""
                          }
                          onCanceled: {
                            content.x = 0
                            content.y = 0
                            root.dragName = ""
                            root.dragRoom = ""
                          }

                          Text {
                            anchors.centerIn: parent
                            text: "\u2630"
                            color: root.foreground
                            opacity: dragArea.containsMouse || dragArea.drag.active
                              ? 0.9 : 0.3
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        Text {
                          id: typeIcon
                          anchors.left: dragArea.right
                          anchors.leftMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          text: root.kindIcon(devItem.dev.kind)
                          color: root.foreground
                          opacity: devItem.dev.online ? 0.85 : 0.35
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          id: nameText
                          anchors.left: typeIcon.right
                          anchors.leftMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          text: (devItem.dev.label || devItem.dev.name)
                            + (devItem.dev.online === true ? "" : devItem.dev.online === false ? "  (offline)" : "  (unknown)")
                            + (devItem.dev.ip ? "  ·  lan" : "")
                          color: root.foreground
                          opacity: devItem.dev.online ? 1.0 : 0.45
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption

                          MouseArea {
                            anchors.fill: parent
                            onClicked: root.expandedName =
                              devItem.isExpanded ? "" : devItem.dev.mac
                          }
                        }

                        ToggleSwitch {
                          id: sw
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          checked: devItem.dev.power === 1
                          interactive: devItem.dev.online
                          busy: root.busyName === devItem.dev.mac
                          foreground: root.foreground
                          onToggled: root.act([checked ? "off" : "on", devItem.dev.mac],
                                              devItem.dev.mac)
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
                        foreground: root.foreground
                        onActiveFocusChanged: root.editors += activeFocus ? 1 : -1
                        onAccepted: {
                          root.act(["label", devItem.dev.mac].concat(
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
                              ? Style.selectedFillFor(root.foreground, Color.accent)
                              : "transparent"
                            border.width: 1
                            border.color: Style.selectedFillFor(root.foreground,
                                                                Color.accent)
                            implicitWidth: chipLabel.implicitWidth + Style.space(12)
                            implicitHeight: chipLabel.implicitHeight + Style.space(6)

                            Text {
                              id: chipLabel
                              anchors.centerIn: parent
                              text: parent.modelData
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }

                            MouseArea {
                              id: chipMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              onClicked: root.act(["rooms", "assign",
                                                   parent.modelData, devItem.dev.mac], "")
                            }
                          }
                        }
                      }

                      // A room is born with its first light: there are no empty
                      // rooms, so creating one means naming it while putting a
                      // light in it. The CLI refuses reserved names.
                      TextField {
                        width: parent.width
                        placeholderText: "New room…"
                        verticalPadding: Style.space(3)
                        foreground: root.foreground
                        onActiveFocusChanged: root.editors += activeFocus ? 1 : -1
                        onAccepted: {
                          var name = text.trim()
                          if (name)
                            root.act(["rooms", "assign", name, devItem.dev.mac], "")
                          text = ""
                          focus = false
                        }
                      }

                      PanelSlider {
                        width: parent.width
                        bar: root.bar
                        minimum: 0
                        maximum: 100
                        step: 1
                        integer: true
                        value: devItem.dev.brightness === null || devItem.dev.brightness === undefined
                          ? 0 : devItem.dev.brightness
                        enabled: typeof devItem.dev.brightness === "number"
                        onReleased: function (v) {
                          root.act(["brightness", String(Math.round(v)), devItem.dev.mac],
                                   devItem.dev.mac)
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
                            border.color: root.foreground

                            MouseArea {
                              id: swatchMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              onClicked: root.act(["color", parent.modelData.name,
                                                   devItem.dev.mac], devItem.dev.mac)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // The whole room takes a drop, not just its one-line heading.
              // Outside the Column because a Column refuses anchored children.
              DropArea {
                id: roomDrop
                anchors.fill: parent
                keys: ["govee-device"]
                onDropped: function (drop) {
                  // "other" is not a room, it is the devices in none of them.
                  var target = roomItem.room.name === "other"
                    ? "none" : roomItem.room.name
                  console.log("govee drop", drop.source.devName,
                              "->", target)
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
                border.color: Style.selectedFillFor(root.foreground, Color.accent)
              }
            }
          }
        }
      }
    }
  }
}
