import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Detail popup, loaded by BarWidget.qml. Filesystem figures come from the
// host widget, which polls them for the bar anyway; this panel only samples
// read/write throughput from /proc/diskstats, and only while it is open.
// The `panel` setting picks the layout: mounts (default), activity, combined.
Panel {
  id: root
  moduleName: "senysisu.disk"
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

  readonly property var mounts: hostWidget ? hostWidget.mounts : []
  readonly property var shown: hostWidget ? hostWidget.shown : null
  readonly property real warnAt: hostWidget ? hostWidget.warnAt : Model.DEFAULT_WARN_AT
  readonly property bool warning: hostWidget ? hostWidget.warning : false
  readonly property var disks: Model.disks(mounts)
  readonly property var diskNames: disks.map(function(d) { return d.name }).filter(function(n) { return n !== "" })

  // Throughput, sampled while open: { disk: {read, write} } in bytes/s, and
  // per-disk histories for the activity graph.
  property var lastStats: null
  property real lastTime: 0
  property var rates: ({})
  property var readHistory: ({})
  property var writeHistory: ({})
  readonly property int historyLimit: Math.ceil(Model.ACTIVITY_MS / Model.ACTIVITY_INTERVAL)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (hostWidget) hostWidget.poll()
    sampleActivity()
  }

  function sampleActivity() {
    diskstats.reload()
    var now = Date.now()
    var stats = Model.parseDiskstats(diskstats.text(), diskNames)
    if (lastStats) {
      var r = Model.rates(lastStats, stats, (now - lastTime) / 1000)
      var reads = {}, writes = {}
      for (var name in r) {
        reads[name] = Model.pushHistory(readHistory[name], r[name].read, historyLimit)
        writes[name] = Model.pushHistory(writeHistory[name], r[name].write, historyLimit)
      }
      rates = r
      readHistory = reads
      writeHistory = writes
    }
    lastStats = stats
    lastTime = now
  }

  function openBtop() {
    if (hostWidget) hostWidget.openBtop()
    close()
  }

  function levelColor(percent) {
    return percent >= root.warnAt ? root.urgent : root.foreground
  }

  function rateLine(name) {
    var r = rates[name]
    return "read " + (r ? Model.formatRate(r.read) : "--") + "  ·  write " + (r ? Model.formatRate(r.write) : "--")
  }

  onOpenedChanged: {
    if (opened) {
      lastStats = null
      rates = {}
      refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  FileView { id: diskstats; path: "/proc/diskstats"; blockLoading: true }

  Timer {
    interval: Model.ACTIVITY_INTERVAL
    repeat: true
    running: root.opened && root.layout !== "mounts"
    onTriggered: root.sampleActivity()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
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
          title: root.shown ? Model.formatPercent(root.shown.percent) : "--"
          meta: Model.heroMeta(root.shown)
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: root.hostWidget ? root.hostWidget.icon : Model.ICON
              textFormat: Text.PlainText
              color: root.warning ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---- mounts: every filesystem ----
        Column {
          visible: root.layout === "mounts"
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.layout === "mounts" ? root.mounts : []
            MountRow { required property var modelData; mount: modelData; width: parent.width }
          }
        }

        // ---- activity: main mount, then throughput per disk ----
        Column {
          visible: root.layout === "activity"
          width: parent.width
          spacing: Style.space(10)

          MountRow { visible: root.shown !== null; mount: root.shown; width: parent.width }

          Repeater {
            model: root.layout === "activity" ? root.disks : []

            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(6)
              visible: modelData.name !== ""

              PanelSectionHeader {
                width: parent.width
                text: Model.diskLabel(modelData).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
                elide: Text.ElideRight
              }

              ActivityGraph {
                width: parent.width
                height: Style.space(48)
                diskName: modelData.name
              }

              Text {
                text: root.rateLine(modelData.name)
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- combined: mounts grouped by disk, with throughput ----
        Column {
          visible: root.layout === "combined"
          width: parent.width
          spacing: Style.space(14)

          Repeater {
            model: root.layout === "combined" ? root.disks : []

            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                width: parent.width
                text: Model.diskLabel(modelData).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
                elide: Text.ElideRight
              }

              Text {
                visible: modelData.name !== ""
                text: root.rateLine(modelData.name)
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: modelData.mounts
                MountRow { required property var modelData; mount: modelData; width: parent.width }
              }
            }
          }
        }

        Text {
          visible: root.mounts.length === 0
          width: parent.width
          text: "No filesystems found."
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // One filesystem: mount point, type, used / total, and a meter that turns
  // red at the warning threshold.
  component MountRow: Column {
    property var mount: null
    readonly property real percent: mount ? mount.percent : 0
    spacing: Style.space(4)

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Text {
        Layout.fillWidth: true
        text: mount ? mount.target : ""
        textFormat: Text.PlainText
        color: root.levelColor(percent)
        elide: Text.ElideMiddle
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        text: mount ? mount.fstype + (mount.luks ? " · LUKS" : "") : ""
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        text: mount ? Model.usedOfTotal(mount) : ""
        textFormat: Text.PlainText
        color: root.levelColor(percent)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(5)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, percent / 100))
        height: parent.height
        radius: parent.radius
        color: root.levelColor(percent)
      }
    }
  }

  // Read (filled area) and write (line) throughput over the last minute,
  // scaled to the busiest moment (at least 1 MiB/s).
  component ActivityGraph: Canvas {
    property string diskName: ""
    readonly property var reads: root.readHistory[diskName] || []
    readonly property var writes: root.writeHistory[diskName] || []
    onReadsChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      var fg = root.foreground
      var step = w / Math.max(1, root.historyLimit - 1)
      var max = 1048576
      for (var i = 0; i < reads.length; i++) max = Math.max(max, reads[i], writes[i] || 0)

      ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
      ctx.lineWidth = 1
      ctx.beginPath(); ctx.moveTo(0, h - 0.5); ctx.lineTo(w, h - 0.5); ctx.stroke()

      if (reads.length < 2) return
      var x0 = w - (reads.length - 1) * step

      ctx.beginPath()
      ctx.moveTo(x0, h)
      for (var j = 0; j < reads.length; j++) ctx.lineTo(x0 + j * step, h - reads[j] / max * h)
      ctx.lineTo(w, h)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.25)
      ctx.fill()

      ctx.beginPath()
      for (var k = 0; k < writes.length; k++) {
        var x = x0 + k * step, y = h - writes[k] / max * h
        if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.strokeStyle = fg
      ctx.lineWidth = 1.5
      ctx.stroke()
    }
  }
}
