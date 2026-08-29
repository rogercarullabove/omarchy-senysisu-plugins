import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "roger.airplane-mode"
  ipcTarget: "roger.airplane-mode"

  property var info: Model.parseRadioStatus("")

  readonly property bool busy: actionProc.running
  readonly property string icon: Model.airplaneIcon(info)
  readonly property string hintText: Model.tooltipText(info)

  function refresh() {
    if (!dataProc.running) dataProc.running = true
  }

  // A one-time action, not an enforced lock: this only runs on click. The
  // helper script itself decides engage-vs-restore from current radio
  // state, so nothing here fights a WiFi/Bluetooth/LTE change made from
  // those panels directly between clicks.
  function toggleAirplaneMode() {
    if (actionProc.running) return
    actionProc.command = ["bash", "-c", "$HOME/.local/bin/omarchy-airplane-mode-toggle"]
    actionProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Data fetch: ~/.local/bin/omarchy-airplane-mode-data prints one JSON
  // object with the current WiFi/WWAN/Bluetooth state. Polled continuously
  // (not just while a panel is open, since this widget has none) so the
  // icon reflects live radio state even when changed from elsewhere.
  Process {
    id: dataProc
    command: ["bash", "-c", "$HOME/.local/bin/omarchy-airplane-mode-data"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.info = Model.parseRadioStatus(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.info.airplaneOn
    tooltipText: root.hintText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggleAirplaneMode()
    }
  }
}
