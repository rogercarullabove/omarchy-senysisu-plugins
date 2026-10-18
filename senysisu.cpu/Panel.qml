import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Detail popup, loaded by BarWidget.qml. Usage figures (total, per core,
// history) come from the host widget, which samples them for the bar
// anyway; this panel only fetches the extras (load, clocks, temperature,
// top processes) through omarchy-cpu-data, and only while it is open.
// The `panel` setting picks the layout: overview (default), cores, minimal.
Panel {
  id: root
  moduleName: "senysisu.cpu"
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

  readonly property real total: hostWidget ? hostWidget.total : 0
  readonly property var cores: hostWidget ? hostWidget.cores : []
  readonly property var history: hostWidget ? hostWidget.history : []
  readonly property real warnAt: hostWidget ? hostWidget.warnAt : Model.DEFAULT_WARN_AT
  readonly property bool warning: hostWidget ? hostWidget.warning : false
  readonly property int threads: cores.length > 0 ? cores.length : details.threads

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (!detailsProc.running) detailsProc.running = true
  }

  function openBtop() {
    if (hostWidget) hostWidget.openBtop()
    close()
  }

  function levelColor(value) {
    return value >= root.warnAt ? root.urgent : root.foreground
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Process {
    id: detailsProc
    command: ["bash", "-c", "$HOME/.local/bin/omarchy-cpu-data"]
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
    contentWidth: panel.fittedContentWidth(Style.space(root.layout === "cores" ? 380 : 340))
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
          id: hero
          width: parent.width
          title: Model.formatPercent(root.total)
          meta: Model.heroMeta(root.threads, root.details)
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: root.hostWidget ? root.hostWidget.icon : Model.ICON
              textFormat: Text.PlainText
              color: root.levelColor(root.warning ? 100 : 0)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          visible: root.layout === "overview" && root.details.model !== ""
          width: parent.width
          text: root.details.model
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        PanelSeparator { foreground: root.foreground }

        // ---- overview: 60-second usage graph ----
        HistoryGraph {
          visible: root.layout === "overview"
          width: parent.width
          height: Style.space(56)
        }

        // ---- cores: one bar per thread ----
        GridLayout {
          visible: root.layout === "cores"
          width: parent.width
          columns: 2
          columnSpacing: Style.space(18)
          rowSpacing: Style.space(6)

          Repeater {
            model: root.layout === "cores" ? root.cores.length : 0

            CoreRow {
              required property int index
              Layout.fillWidth: true
              coreIndex: index
            }
          }
        }

        // ---- overview / minimal: key figures ----
        GridLayout {
          visible: root.layout !== "cores"
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { visible: root.layout === "minimal"; text: "Usage" }
          InfoValue {
            visible: root.layout === "minimal"
            text: Model.formatPercent(root.total)
            color: root.levelColor(root.warning ? 100 : 0)
          }

          InfoLabel { text: "Load avg" }
          InfoValue { text: Model.formatLoad(root.details.load) }

          InfoLabel { text: "Frequency" }
          InfoValue {
            text: Model.formatGHz(Model.averageFreq(root.details.freqMhz))
              + (root.details.maxFreqMhz !== null && root.layout === "overview" ? " (max " + Model.formatGHz(root.details.maxFreqMhz) + ")" : "")
          }

          InfoLabel { text: "Temperature" }
          InfoValue { text: Model.formatTemp(root.details.tempC) }

          InfoLabel { visible: root.layout === "overview"; text: "Uptime" }
          InfoValue { visible: root.layout === "overview"; text: Model.formatUptime(root.details.uptime) }
        }

        // ---- overview / cores: top processes ----
        PanelSeparator {
          visible: root.layout !== "minimal" && root.details.top.length > 0
          foreground: root.foreground
        }

        PanelSectionHeader {
          visible: root.layout !== "minimal" && root.details.top.length > 0
          text: "TOP PROCESSES"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        GridLayout {
          visible: root.layout !== "minimal"
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          Repeater {
            model: root.layout === "minimal" ? 0 : Math.min(root.details.top.length, root.layout === "cores" ? 3 : 5) * 2

            Text {
              required property int index
              readonly property var proc: root.details.top[Math.floor(index / 2)]
              readonly property bool isName: index % 2 === 0
              Layout.fillWidth: isName
              text: isName ? proc.name : Model.formatPercent(Model.processShare(proc.cpu, root.threads))
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

  // Usage over the last minute: filled area, line, and a dashed line at the
  // warning threshold.
  component HistoryGraph: Canvas {
    id: graph
    readonly property var points: root.history
    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()

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
      ctx.beginPath()
      ctx.moveTo(x0, h)
      for (var i = 0; i < points.length; i++) ctx.lineTo(x0 + i * step, h - points[i] / 100 * h)
      ctx.lineTo(w, h)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
      ctx.fill()

      ctx.beginPath()
      for (var j = 0; j < points.length; j++) {
        var x = x0 + j * step, y = h - points[j] / 100 * h
        if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = root.warning ? root.urgent : fg
      ctx.lineWidth = 1.5
      ctx.stroke()
    }
  }

  component CoreRow: RowLayout {
    property int coreIndex: 0
    readonly property real usage: root.cores[coreIndex] || 0
    readonly property real mhz: root.details.freqMhz[coreIndex] || 0
    spacing: Style.space(8)

    Text {
      text: String(coreIndex)
      textFormat: Text.PlainText
      Layout.preferredWidth: Style.space(16)
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(5)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, usage / 100))
        height: parent.height
        radius: parent.radius
        color: root.levelColor(usage)
      }
    }

    Text {
      text: Model.formatPercent(usage)
      textFormat: Text.PlainText
      Layout.preferredWidth: Style.space(30)
      horizontalAlignment: Text.AlignRight
      color: root.levelColor(usage)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      text: mhz > 0 ? (mhz / 1000).toFixed(1) : "--"
      textFormat: Text.PlainText
      Layout.preferredWidth: Style.space(22)
      horizontalAlignment: Text.AlignRight
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
