import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Detail popup, loaded by BarWidget.qml. Memory figures and histories come
// from the host widget, which samples them for the bar anyway; this panel
// only reads the extras (swap devices, memory pressure, top processes), and
// only while it is open. The `panel` setting picks the layout: breakdown
// (default), history, minimal.
Panel {
  id: root
  moduleName: "senysisu.ram"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by has to be that
  // widget (see senysisu.lte/Panel.qml).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  readonly property string layout: Model.pick(setting("panel", ""), Model.PANELS, Model.PANELS[0])
  property var details: Model.parseDetails("")
  property var swaps: []
  property var pressure: null

  readonly property var mem: hostWidget ? hostWidget.mem : Model.memory({}, false)
  readonly property bool warning: hostWidget ? hostWidget.warning : false
  readonly property real warnAt: hostWidget ? hostWidget.warnAt : Model.DEFAULT_WARN_AT

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color usedColor: warning ? urgent : foreground

  function refresh() {
    swapsFile.reload()
    pressureFile.reload()
    swaps = Model.parseSwaps(swapsFile.text())
    pressure = Model.parsePressure(pressureFile.text())
    if (!detailsProc.running) detailsProc.running = true
  }

  function openBtop() {
    if (hostWidget) hostWidget.openBtop()
    close()
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  FileView { id: swapsFile; path: "/proc/swaps"; blockLoading: true }
  FileView { id: pressureFile; path: "/proc/pressure/memory"; blockLoading: true }

  Process {
    id: detailsProc
    command: ["bash", "-c", "$HOME/.local/bin/omarchy-ram-data"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.details = Model.parseDetails(text)
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onActivateRequested: root.openBtop()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "b" || t === "B") root.openBtop()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: Model.formatPercent(root.mem.percent)
          meta: Model.usedOfTotal(root.mem.usedKb, root.mem.totalKb)
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: root.hostWidget ? root.hostWidget.icon : Model.ICON
              textFormat: Text.PlainText
              color: root.usedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- breakdown: used / cache / free bar ----
        Column {
          visible: root.layout === "breakdown"
          width: parent.width
          spacing: Style.space(6)

          Row {
            width: parent.width
            height: Style.space(10)

            Rectangle {
              width: parent.width * (root.mem.totalKb > 0 ? root.mem.usedKb / root.mem.totalKb : 0)
              height: parent.height
              color: root.usedColor
            }
            Rectangle {
              width: parent.width * (root.mem.totalKb > 0 ? root.mem.cacheKb / root.mem.totalKb : 0)
              height: parent.height
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
            }
            Rectangle {
              width: parent.width * (root.mem.totalKb > 0 ? root.mem.freeKb / root.mem.totalKb : 0)
              height: parent.height
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
            }
          }

          Row {
            spacing: Style.space(14)
            LegendItem { swatch: root.usedColor; label: "used " + Model.formatSize(root.mem.usedKb) }
            LegendItem { swatch: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45); label: "cache " + Model.formatSize(root.mem.cacheKb) }
            LegendItem { swatch: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14); label: "free " + Model.formatSize(root.mem.freeKb) }
          }
        }

        // ---- history: last 5 minutes ----
        Column {
          visible: root.layout === "history"
          width: parent.width
          spacing: Style.space(6)

          HistoryGraph {
            width: parent.width
            height: Style.space(64)
          }

          Row {
            spacing: Style.space(14)
            LegendItem { swatch: root.usedColor; label: "memory" }
            LegendItem { swatch: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45); label: "swap" }
            LegendItem { swatch: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.6); label: "warn " + Math.round(root.warnAt) + "%" }
          }
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { visible: root.layout !== "breakdown"; text: "Used" }
          InfoValue { visible: root.layout !== "breakdown"; text: Model.formatKb(root.mem.usedKb) }

          InfoLabel { text: "Available" }
          InfoValue { text: Model.formatKb(root.mem.availableKb) }

          InfoLabel { visible: root.layout === "breakdown"; text: "Cache/buffers" }
          InfoValue { visible: root.layout === "breakdown"; text: Model.formatKb(root.mem.cacheKb) }

          InfoLabel { text: "Swap" + (root.swaps.length > 0 ? " (" + Model.swapSummary(root.swaps) + ")" : "") }
          InfoValue { text: root.mem.swapTotalKb > 0 ? Model.usedOfTotal(root.mem.swapUsedKb, root.mem.swapTotalKb) : "none" }

          InfoLabel { visible: root.layout === "breakdown"; text: "Pressure" }
          InfoValue {
            visible: root.layout === "breakdown"
            text: Model.formatPressure(root.pressure)
            color: root.pressure !== null && root.pressure >= 10 ? root.urgent : root.foreground
          }
        }

        // ---- breakdown: top processes ----
        PanelSeparator {
          visible: root.layout === "breakdown" && root.details.top.length > 0
          foreground: root.foreground
        }

        PanelSectionHeader {
          visible: root.layout === "breakdown" && root.details.top.length > 0
          text: "TOP PROCESSES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        GridLayout {
          visible: root.layout === "breakdown"
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          Repeater {
            model: root.layout === "breakdown" ? Math.min(root.details.top.length, 5) * 2 : 0

            Text {
              required property int index
              readonly property var proc: root.details.top[Math.floor(index / 2)]
              readonly property bool isName: index % 2 === 0
              Layout.fillWidth: isName
              text: isName ? proc.name : Model.formatKb(proc.rssKb)
              textFormat: Text.PlainText
              color: root.foreground
              opacity: isName ? 0.6 : 1
              horizontalAlignment: isName ? Text.AlignLeft : Text.AlignRight
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---- minimal: hand off to btop ----
        Button {
          visible: root.layout === "minimal"
          width: parent.width
          text: "Open btop"
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.openBtop()
        }
      }
    }
  }

  // Memory (filled area + line) and swap (line) over the last 5 minutes,
  // with a dashed line at the warning threshold.
  component HistoryGraph: Canvas {
    readonly property var points: root.hostWidget ? root.hostWidget.history : []
    readonly property var swapPoints: root.hostWidget ? root.hostWidget.swapHistory : []
    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()

    function trace(ctx, values, x0, step, h) {
      ctx.beginPath()
      for (var i = 0; i < values.length; i++) {
        var x = x0 + i * step, y = h - values[i] / 100 * h
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      var limit = root.hostWidget ? root.hostWidget.historyLimit : points.length
      var step = w / Math.max(1, limit - 1)
      var fg = root.foreground

      ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
      ctx.lineWidth = 1
      ctx.beginPath(); ctx.moveTo(0, Math.round(h / 2) + 0.5); ctx.lineTo(w, Math.round(h / 2) + 0.5); ctx.stroke()

      var warnY = Math.round(h - root.warnAt / 100 * h) + 0.5
      ctx.strokeStyle = Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.6)
      ctx.setLineDash([3, 3])
      ctx.beginPath(); ctx.moveTo(0, warnY); ctx.lineTo(w, warnY); ctx.stroke()
      ctx.setLineDash([])

      if (points.length < 2) return
      var x0 = w - (points.length - 1) * step

      trace(ctx, points, x0, step, h)
      ctx.lineTo(w, h); ctx.lineTo(x0, h); ctx.closePath()
      ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
      ctx.fill()

      trace(ctx, points, x0, step, h)
      ctx.strokeStyle = root.usedColor
      ctx.lineWidth = 1.5
      ctx.stroke()

      if (swapPoints.length >= 2) {
        trace(ctx, swapPoints, w - (swapPoints.length - 1) * step, step, h)
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.45)
        ctx.lineWidth = 1
        ctx.stroke()
      }
    }
  }

  component LegendItem: Row {
    property color swatch: "white"
    property string label: ""
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8); height: Style.space(8); radius: 2
      color: parent.swatch
    }
    Text {
      text: parent.label
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    Layout.fillWidth: true
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}
