import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "GoveeMenuModel.js" as Model

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string view: "targets"
  property var target: null
  property string form: ""
  property string message: ""
  property bool failed: false
  property int selected: 0
  readonly property var rows: Model.filter(Model.rows(view, GoveeClient.snapshot, target), search.text)
  readonly property string heading: form ? ({ brightness: "Brightness (0–100)", color: "Custom RGB colour",
      label: "Friendly name (empty clears)", newroom: "New room", rename: "Rename room" })[form]
    : view === "targets" ? "Govee lights" : view === "scenes" ? "Scenes"
    : (target ? target.label : "Lights") + (view === "colors" ? " · Colour" : view === "rooms" ? " · Move to room" : "")

  function open(payloadJson) {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    panel.screen = screens.find(function (s) { return monitor && s.name === monitor.name }) || screens[0] || null
    view = "targets"
    target = null
    form = ""
    search.text = ""
    message = ""
    failed = false
    selected = 0
    opened = true
    showResult()
    GoveeClient.refresh()
    focusInput()
  }

  function showResult() {
    var r = GoveeClient.menuResult
    if (!r) return
    failed = !r.success
    message = Model.resultMessage(r.success, r.message)
    if (opened) GoveeClient.menuResult = null
  }

  function close() { opened = false }
  function dismiss() { close() }
  function focusInput() {
    Qt.callLater(function () {
      if (root.opened) (root.form ? editor : search).forceActiveFocus()
    })
  }
  function navigate(next) {
    view = next
    form = ""
    search.text = ""
    selected = 0
    focusInput()
  }
  function back() {
    if (form) { form = ""; focusInput() }
    else if (search.text) search.text = ""
    else if (view === "targets") dismiss()
    else navigate(view === "colors" || view === "rooms" ? "actions" : "targets")
  }
  function move(delta) {
    if (!rows.length) return
    selected = (selected + delta + rows.length) % rows.length
    list.positionViewAtIndex(selected, ListView.Contain)
  }
  function activate() {
    var row = rows[selected]
    if (!row) return
    if (row.target) { target = row; navigate("actions") }
    else if (row.form) {
      form = row.form
      editor.text = form === "brightness" && target.device && typeof target.device.brightness === "number"
        ? String(target.device.brightness) : form === "label" ? target.device.label || ""
        : form === "rename" ? target.label : ""
      message = ""
      focusInput()
    } else if (row.view) navigate(row.view)
    else if (row.args) send(row.args)
  }
  function send(args) {
    message = "Queued…"
    failed = false
    GoveeClient.act(args, target ? target.target : "scene", "menu")
  }
  function submit() {
    try {
      var args = Model.formCommand(form, editor.text, target)
      if (form === "rename") {
        // Return to the target list: the old room ID no longer resolves.
        navigate("targets")
        target = null
      } else { form = ""; focusInput() }
      send(args)
    } catch (e) { failed = true; message = e.message }
  }
  function forward() {
    var row = rows[selected]
    // Arrow navigation enters views/forms; only Enter executes device commands.
    if (row && (row.target || row.view || row.form)) activate()
  }
  function handleKey(event) {
    if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier))) back()
    else if (event.key === Qt.Key_F5 || (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) GoveeClient.refresh()
    else if (!form && event.key === Qt.Key_Right && ((event.modifiers & Qt.AltModifier) || !search.text)) forward()
    else if (!form && event.key === Qt.Key_Left && !search.text) back()
    else if (!form && event.key === Qt.Key_Down) move(1)
    else if (!form && event.key === Qt.Key_Up) move(-1)
    else if (!form && event.key === Qt.Key_Backspace && !search.text) back()
    else return
    event.accepted = true
  }
  onRowsChanged: selected = Math.max(0, Math.min(selected, rows.length - 1))

  Connections {
    target: GoveeClient
    function onCompleted(success, output, origin) {
      if (origin === "menu") root.showResult()
    }
    function onSnapshotChanged() {
      // Refresh state without changing the selected device identity.
      if (root.target && root.target.kind === "device") {
        var updated = Model.targets(GoveeClient.snapshot).find(function (r) { return r.id === root.target.id })
        if (updated) root.target = updated
      }
    }
  }
  Timer {
    interval: 60000
    running: root.opened && !root.form && !GoveeClient.busy
    repeat: true
    onTriggered: GoveeClient.refresh()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omagovee-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onBackingWindowVisibleChanged: if (backingWindowVisible) root.focusInput()

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(580), panel.height - Style.gapsOut * 2)
      color: Commons.Color.menu.background
      border.color: Commons.Color.menu.border
      border.width: 1
      radius: Style.space(4)
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: root.heading
            color: Commons.Color.menu.text
            font.family: "sans-serif"
            font.pixelSize: Math.max(22, Style.font.title)
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        Controls.TextField {
          id: search
          objectName: "search"
          Layout.fillWidth: true
          visible: !root.form
          placeholderText: "Type to filter…"
          color: Commons.Color.menu.text
          font.family: "sans-serif"
          font.pixelSize: Math.max(18, Style.font.body * 1.2)
          Accessible.name: "Filter lights and actions"
          background: Item {}
          placeholderTextColor: Commons.Color.menu.text
          leftPadding: 0
          rightPadding: 0
          onTextChanged: root.selected = 0
          onAccepted: root.activate()
          Keys.onPressed: function (event) { root.handleKey(event) }
        }
        Controls.TextField {
          id: editor
          objectName: "editor"
          Layout.fillWidth: true
          visible: !!root.form
          color: Commons.Color.menu.text
          font.family: "sans-serif"
          font.pixelSize: Math.max(18, Style.font.body * 1.2)
          Accessible.name: root.heading
          background: Item {}
          placeholderTextColor: Commons.Color.menu.text
          leftPadding: 0
          rightPadding: 0
          onAccepted: root.submit()
          Keys.onPressed: function (event) { root.handleKey(event) }
        }

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: !root.form
          clip: true
          model: root.rows
          currentIndex: root.selected
          spacing: Style.space(4)
          Controls.ScrollBar.vertical: Controls.ScrollBar {}
          delegate: Item {
            required property var modelData
            required property int index
            width: list.width
            height: Math.max(64, Style.space(60))
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.label + " " + (modelData.detail || "")
            Accessible.selected: root.selected === index
            Accessible.onPressAction: { root.selected = index; root.activate() }
            Text {
              text: root.selected === index ? "›" : ""
              color: Commons.Color.menu.text
              font.pixelSize: Math.max(18, Style.font.body * 1.2)
              anchors.top: parent.top
              anchors.topMargin: Style.space(8)
            }
            Text {
              text: Model.icon(modelData, root.view)
              color: modelData.device
                ? (modelData.device.online === false ? Commons.Color.urgent
                  : modelData.device.online === true && modelData.device.power === 1 ? Commons.Color.accent : Commons.Color.muted)
                : Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Math.max(18, Style.font.body * 1.2)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(18)
              anchors.top: parent.top
              anchors.topMargin: Style.space(8)
              Accessible.ignored: true
            }
            Column {
              anchors.fill: parent
              anchors.topMargin: Style.space(8)
              anchors.leftMargin: Style.space(44)
              spacing: Style.space(3)
              Text {
                width: parent.width
                text: modelData.label
                font.weight: root.selected === index ? Font.Bold : Font.DemiBold
                opacity: root.selected === index ? 1 : 0.85
                color: root.selected === index ? Commons.Color.accent : Commons.Color.menu.text
                font.family: "sans-serif"
                font.pixelSize: Math.max(18, Style.font.body * 1.2)
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: modelData.detail || ""
                color: Commons.Color.menu.text
                opacity: 0.9
                font.family: "sans-serif"
                font.pixelSize: Math.max(15, Style.font.caption * 1.2)
                font.weight: Font.Medium
                elide: Text.ElideRight
              }
            }
            MouseArea {
              anchors.fill: parent
              onClicked: { root.selected = parent.index; root.activate(); root.focusInput() }
            }
          }
          Text {
            anchors.centerIn: parent
            visible: !root.rows.length
            text: GoveeClient.loading ? "Loading lights…" : "No matches"
            color: Commons.Color.menu.text
            font.family: "sans-serif"
          }
        }
        Item { Layout.fillHeight: true; visible: !!root.form }
        Text {
          Layout.fillWidth: true
          visible: !!text
          text: GoveeClient.error || root.message || (GoveeClient.loading ? "Refreshing…" : "")
          color: Commons.Color.menu.text
          font.family: "sans-serif"
          font.pixelSize: Math.max(15, Style.font.caption * 1.2)
          font.weight: root.failed || GoveeClient.error ? Font.Bold : Font.Medium
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: (GoveeClient.busy ? "Working… · " : "") + (root.form ? "Enter save · Esc cancel"
            : "↑↓ select · ← back · → open · Enter apply · Esc back/close · F5 reload")
          color: Commons.Color.menu.text
          opacity: 0.9
          font.family: "sans-serif"
          font.pixelSize: Math.max(15, Style.font.caption * 1.2)
          font.weight: Font.Medium
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
