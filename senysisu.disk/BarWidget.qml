import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Manifest entry point: the disk icon + ring/percent in the bar, and host for
// Panel.qml (the detail popup). Owns the filesystem poll (omarchy-disk-data,
// every `interval`), because the bar needs it whether or not the panel was
// ever opened; the panel reads `mounts` and `shown` off this widget through
// `hostWidget`. Structure follows the documented BarWidget.qml + nested
// Panel.qml contract, like senysisu.lte.
BarWidget {
  id: root
  moduleName: "senysisu.disk"

  // ---- Settings (inline on this widget's shell.json layout entry) ----
  readonly property string style: Model.pick(setting("style", ""), Model.STYLES, Model.STYLES[0])
  readonly property bool showIcon: setting("showIcon", true) !== false
  readonly property string icon: String(setting("icon", "")) || Model.ICON
  readonly property real warnAt: Model.clampNumber(setting("warnAt", Model.DEFAULT_WARN_AT), 1, 100, Model.DEFAULT_WARN_AT)
  readonly property int interval: Model.clampNumber(setting("interval", Model.DEFAULT_INTERVAL), 1000, 3600000, Model.DEFAULT_INTERVAL)
  readonly property var watch: Model.watchList(setting("mounts", null))

  // ---- Live values ----
  property var mounts: []
  property bool warning: false

  readonly property var watched: Model.watchedMounts(mounts, watch)
  // The bar shows the fullest watched mount; that is also the one that
  // decides the warning.
  readonly property var shown: Model.fullest(watched)
  readonly property real percent: shown ? shown.percent : 0

  // Vertical bars are 28 px wide: there is no room for a number beside the ring.
  readonly property bool showRing: style !== "percent"
  readonly property bool showPercent: style === "percent" || (style === "ring+percent" && !vertical)
  readonly property color tint: warning ? (bar ? bar.urgent : Color.urgent) : (bar ? bar.barForeground : Color.foreground)

  onPercentChanged: warning = Model.isWarning(warning, percent, warnAt)
  onWarnAtChanged: warning = Model.isWarning(false, percent, warnAt)

  function poll() {
    if (!dataProc.running) dataProc.running = true
  }

  function refresh() {
    poll()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function openBtop() {
    if (bar) bar.run("omarchy-launch-or-focus-tui btop")
  }

  // ---- Panel lifecycle, forwarded to Panel.qml (shape contract for
  //      shell.summon/hide/toggle routing) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: poll()

  Process {
    id: dataProc
    command: ["bash", "-c", "$HOME/.local/bin/omarchy-disk-data"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mounts = Model.parseMounts(text)
    }
  }

  Timer {
    interval: root.interval
    repeat: true
    running: true
    onTriggered: root.poll()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "senysisu.disk"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.shown
      ? "Disk " + root.shown.target + " " + Model.formatPercent(root.percent) + " · " + Model.formatBytes(root.shown.avail) + " free"
      : "Disk"
    fixedWidth: root.vertical ? -1 : content.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? content.implicitHeight + scaledVerticalPadding * 2 : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else if (buttonCode === Qt.RightButton) root.openBtop()
      else root.toggle()
    }

    Grid {
      id: content
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 3
      rowSpacing: Style.space(3)
      columnSpacing: Style.space(5)
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Text {
        visible: root.showIcon
        text: root.icon
        textFormat: Text.PlainText
        color: root.tint
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
      }

      Gauge {
        visible: root.showRing
        value: root.percent
        color: root.tint
        size: Style.bar.iconCanvas - 2
      }

      Text {
        id: percentText
        visible: root.showPercent
        // Sized for "100%" so the widget doesn't change width as the number does.
        width: Math.ceil(percentMetrics.advanceWidth)
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        text: root.vertical ? String(Math.round(root.percent)) : Model.formatPercent(root.percent)
        textFormat: Text.PlainText
        color: root.tint
        font.family: button.fontFamily
        font.pixelSize: root.vertical ? Style.font.caption : Style.font.bodySmall
      }
    }

    TextMetrics {
      id: percentMetrics
      font: percentText.font
      text: root.vertical ? "100" : "100%"
    }
  }
}
