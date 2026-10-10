import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Nested detail popup, loaded by BarWidget.qml. Owns the modem data fetch,
// poll timer, and power toggle; BarWidget.qml just reads `icon` for the bar
// button and forwards open/close/toggle lifecycle in and out.
Panel {
  id: root
  moduleName: "senysisu.lte"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  property var info: Model.parseLteStatus("")
  property bool cursorActive: false
  property string actionError: ""

  readonly property bool busy: actionProc.running
  readonly property string icon: Model.lteIcon(info)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool headerHasCursor: cursorActive
  readonly property string toggleHint: info.powerState === "on" ? "Turn modem off" : "Turn modem on"

  function refresh() {
    if (!dataProc.running) dataProc.running = true
  }

  // Toggling via `mmcli -e/-d` directly fights the "telia" NetworkManager
  // connection, which has autoconnect=yes with unlimited retries: NM notices
  // the modem went down and immediately re-enables it, so a manual disable
  // never sticks (shows "enabling" and bounces back on). `nmcli radio wwan`
  // is the layer NM itself respects as explicit user intent, so it doesn't
  // fight itself, and it cascades down to actually power the modem off.
  function toggleModem() {
    if (!info.present || actionProc.running) return
    actionError = ""
    var turnOn = info.powerState !== "on"
    actionProc.command = ["nmcli", "radio", "wwan", turnOn ? "on" : "off"]
    actionProc.running = true
  }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  // Data fetch: ~/.local/bin/omarchy-lte-data prints one JSON object
  // describing the modem (mmcli-based). Polled continuously (not just while
  // the panel is open) so the bar icon reflects live signal.
  Process {
    id: dataProc
    command: ["bash", "-c", "$HOME/.local/bin/omarchy-lte-data"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.info = Model.parseLteStatus(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.actionError = String(actionStderr.text || "").trim() || "mmcli command failed"
      root.refresh()
    }
  }

  Timer {
    id: pollTimer
    interval: 5000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) { root.cursorActive = true }
      onActivateRequested: if (root.cursorActive) root.toggleModem()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: Model.heroTitle(root.info)
          meta: Model.heroMeta(root.info)
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.info.present ? 1.0 : 0.5

          iconComponent: Component {
            Text {
              text: root.icon
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          // Status only — the switch owns toggling, mouse and keyboard alike.
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: root.info.present
              checked: root.info.powerState === "on"
              busy: root.busy
              hasCursor: root.headerHasCursor
              foreground: hero.foreground
              onHovered: function(on) { if (on) root.cursorActive = true }
              onToggled: root.toggleModem()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Text {
          visible: !root.info.present
          width: parent.width
          text: "No LTE modem detected."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.actionError !== ""
          width: parent.width
          text: root.actionError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          visible: root.info.present
          foreground: root.foreground
        }

        GridLayout {
          visible: root.info.present
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { text: "Signal" }
          InfoValue { text: Model.formatSignal(root.info.signal, root.info.present) + "  " + Model.barsDots(root.info.bars) }

          InfoLabel { text: "Technology" }
          InfoValue { text: Model.formatTechnology(root.info.technology) }

          InfoLabel { text: "Network" }
          InfoValue {
            text: Model.roamingLabel(root.info.roaming)
            color: root.info.roaming ? root.urgent : root.foreground
          }

          InfoLabel { text: "State" }
          InfoValue { text: Model.stateLabel(root.info.state) }

          InfoLabel { text: "Ping" }
          InfoValue { text: Model.formatPingLatency(root.info.pingMs) }
        }
      }
    }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    Layout.fillWidth: true
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}
