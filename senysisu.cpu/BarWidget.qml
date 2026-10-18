import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Manifest entry point: the CPU icon + gauge in the bar, and host for
// Panel.qml (the detail popup). Owns the usage sampling, because the bar
// needs it whether or not the panel was ever opened; the panel reads
// `cores`, `total` and `history` off this widget through `hostWidget`.
// Structure follows the documented BarWidget.qml + nested Panel.qml contract,
// like senysisu.lte.
BarWidget {
  id: root
  moduleName: "senysisu.cpu"

  // ---- Settings (inline on this widget's shell.json layout entry) ----
  readonly property string style: Model.pick(setting("style", ""), Model.STYLES, Model.STYLES[0])
  readonly property bool showIcon: setting("showIcon", true) !== false
  readonly property string icon: String(setting("icon", "")) || Model.ICON
  readonly property real warnAt: Model.clampNumber(setting("warnAt", Model.DEFAULT_WARN_AT), 1, 100, Model.DEFAULT_WARN_AT)
  readonly property int interval: Model.clampNumber(setting("interval", Model.DEFAULT_INTERVAL), 500, 60000, Model.DEFAULT_INTERVAL)
  readonly property int maxColumns: Model.clampNumber(setting("maxColumns", Model.DEFAULT_MAX_COLUMNS), 1, 64, Model.DEFAULT_MAX_COLUMNS)

  // ---- Live values ----
  property var lastSample: null
  property real total: 0
  property var cores: []
  property var history: []
  property bool warning: false

  readonly property int threads: cores.length
  readonly property int historyLimit: Math.max(2, Math.ceil(Model.HISTORY_MS / interval))
  readonly property var columns: Model.groupCores(cores, maxColumns)

  // Vertical bars are 28 px wide: columns don't fit, and neither does a
  // number beside the ring.
  readonly property string gaugeMode: {
    if (style === "percent") return ""
    if (style === "columns" || style === "sparkline") return vertical ? "ring" : style
    return "ring"
  }
  readonly property bool showPercent: style === "percent" || (style === "ring+percent" && !vertical)
  readonly property color tint: warning ? (bar ? bar.urgent : Color.urgent) : (bar ? bar.barForeground : Color.foreground)

  function sample() {
    stat.reload()
    var current = Model.parseStat(stat.text())
    if (!current.total) return
    if (lastSample) {
      var u = Model.usage(lastSample, current)
      total = u.total
      cores = u.cores
      history = Model.pushHistory(history, u.total, historyLimit)
      warning = Model.isWarning(warning, Model.average(history, Model.WARN_SAMPLES), warnAt)
    } else {
      // Usage needs two samples; until then draw one empty column per core
      // so the widget doesn't change width on the second one.
      cores = current.cores.map(function() { return 0 })
    }
    lastSample = current
  }

  function refresh() {
    sample()
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
  onHistoryLimitChanged: history = history.slice(Math.max(0, history.length - historyLimit))
  Component.onCompleted: sample()

  FileView {
    id: stat
    path: "/proc/stat"
    blockLoading: true
  }

  Timer {
    interval: root.interval
    repeat: true
    running: true
    onTriggered: root.sample()
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
    target: "senysisu.cpu"

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
    tooltipText: "CPU " + Model.formatPercent(root.total) + (root.threads > 0 ? " · " + root.threads + " threads" : "")
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
        visible: root.gaugeMode !== ""
        mode: root.gaugeMode
        values: root.columns
        value: root.total
        color: root.tint
        size: Style.bar.iconCanvas - 2
      }

      Text {
        id: percentText
        visible: root.showPercent
        // Sized for "100%" so the widget doesn't change width as the number does.
        width: Math.ceil(percentMetrics.advanceWidth)
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        text: root.vertical ? String(Math.round(root.total)) : Model.formatPercent(root.total)
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
