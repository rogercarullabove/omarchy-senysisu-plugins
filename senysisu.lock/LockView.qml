import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool showPassword: false
  property date now: new Date()
  property string weatherText: ""
  property string weatherCondition: ""   // wttr.in condition text, e.g. "Light rain"
  property string sunrise: ""            // "HH:mm:ss", location local time
  property string sunset: ""

  // Settings from settings.lua next to this file, converted to JSON by
  // settings-loader.lua. Watched, so saved edits apply live. Any missing,
  // nil or wrongly typed value falls back to the default passed to opt().
  property var settings: ({})
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))

  function opt(section, key, fallback) {
    var group = settings ? settings[section] : null
    var value = group ? group[key] : undefined
    return (value === undefined || value === null || typeof value !== typeof fallback) ? fallback : value
  }

  function optColor(section, key, fallback) {
    var value = opt(section, key, "")
    return value.length > 0 ? value : fallback
  }

  FileView {
    path: root.pluginDir + "settings.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: settingsProc.running = true
    onLoadFailed: root.settings = ({})
  }

  Process {
    id: settingsProc
    command: ["lua", root.pluginDir + "settings-loader.lua", root.pluginDir + "settings.lua"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim().length === 0) return
        try {
          root.settings = JSON.parse(text)
        } catch (e) {
          console.warn("senysisu.lock: could not parse settings: " + e)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim().length > 0) console.warn("senysisu.lock: settings.lua error, using defaults: " + text.trim())
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.settings = ({}) }
  }

  readonly property string clockFont: opt("clock", "font", "Adwaita Sans")
  readonly property bool revealEnabled: opt("password", "reveal_toggle", true)
  readonly property bool weatherEnabled: opt("weather", "enabled", true)
  readonly property string weatherLocation: opt("weather", "location", "")

  // ---- Weather effects: off, auto (from the fetched condition) or manual.
  readonly property var effectKinds: ["sunny", "cloudy", "rain", "storm", "snow", "snowstorm"]
  readonly property string effectMode: opt("effects", "mode", "auto")
  readonly property string effectKind: {
    if (effectMode === "manual") {
      var manual = opt("effects", "weather", "rain")
      return effectKinds.indexOf(manual) !== -1 ? manual : ""
    }
    return effectMode === "auto" ? conditionToKind(weatherCondition) : ""
  }
  readonly property bool effectNight: {
    var forced = settings && settings.effects ? settings.effects.night : undefined
    if (typeof forced === "boolean") return forced
    var t = Qt.formatDateTime(now, "HH:mm:ss")
    if (sunrise.length > 0 && sunset.length > 0) return t < sunrise || t >= sunset
    var hour = now.getHours()
    return hour < 7 || hour >= 19
  }
  // Weather is fetched for the top line and/or for automatic effects/night.
  readonly property bool weatherNeeded: weatherEnabled || effectMode === "auto"
    || (effectMode === "manual" && !(settings && settings.effects && typeof settings.effects.night === "boolean"))

  // Color grade applied to the blurred wallpaper itself (not an overlay):
  // [saturation, brightness, tint color, tint amount] per weather. Night
  // makes any weather cooler, less saturated and darker.
  readonly property var grade: {
    var g = ({
      sunny:     [ 0.05,  0.02, "#ffa040", 0.20],
      cloudy:    [-0.30, -0.02, "#ffffff", 0.00],
      rain:      [-0.35, -0.06, "#ffffff", 0.00],
      storm:     [-0.45, -0.16, "#ffffff", 0.00],
      snow:      [-0.25,  0.02, "#a8c4ff", 0.08],
      snowstorm: [-0.35,  0.00, "#a8c4ff", 0.12]
    })[effectNight && effectKind === "sunny" ? "" : effectKind] || [0, 0, "#ffffff", 0]  // sunny at night = clear night: no sun grading
    var result = { saturation: g[0], brightness: g[1], tint: g[2], amount: g[3] }
    if (effectKind !== "" && effectNight) {
      result.saturation -= 0.20
      result.brightness -= 0.15
      result.tint = "#4a6cff"
      result.amount = Math.max(result.amount, 0.16)
    }
    return result
  }

  function conditionToKind(text) {
    var t = String(text || "").toLowerCase()
    if (t.length === 0) return ""
    if (/thunder/.test(t)) return "storm"
    if (/blizzard|blowing snow|heavy snow/.test(t)) return "snowstorm"
    if (/snow|sleet|ice pellets/.test(t)) return "snow"
    if (/rain|drizzle|shower/.test(t)) return "rain"
    if (/cloud|overcast|fog|mist|haze/.test(t)) return "cloudy"
    if (/sun|clear/.test(t)) return "sunny"
    return ""
  }
  readonly property int infoFontSize: Math.max(11, Math.round(Style.font.heading * 0.7))
  readonly property var battery: UPower.displayDevice
  readonly property bool batteryPresent: !!(battery && battery.isPresent)
  readonly property bool batteryCharging: batteryPresent
    && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)
  readonly property int batteryPercent: batteryPresent ? Math.round(battery.percentage * 100) : 0
  readonly property string batteryIcon: batteryCharging ? "󰂄"
    : ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][Math.min(10, Math.floor(batteryPercent / 10))]

  // Network state straight from NetworkManager via Quickshell, like the bar's
  // network widget, so the indicator updates without polling.
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wifiNetwork: {
    var networks = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].connected) return networks[i]
    return null
  }
  readonly property int wifiSignal: wifiNetwork ? Math.round((wifiNetwork.signalStrength || 0) * 100) : -1
  readonly property string wifiIcon: {
    if (wiredDevice && wiredDevice.connected) return "󰈀"
    if (!Networking.wifiEnabled) return "󰤭"
    if (!wifiNetwork) return "󰤮"
    return ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][Math.max(0, Math.min(4, Math.ceil(wifiSignal / 20) - 1))]
  }
  readonly property string wifiLabel: wiredDevice && wiredDevice.connected ? "Ethernet"
    : (wifiNetwork ? (wifiNetwork.name || "") : "")

  function findDevice(type) {
    var fallback = null
    for (var i = 0; i < networkDevices.length; i++) {
      var device = networkDevices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  // Indicators listed for a corner in settings.lua, in display order (left to
  // right). Accepts a list or a single name; an empty Lua table arrives as {}.
  readonly property var defaultCorners: ({ bottom_right: ["wifi", "battery"] })
  function cornerItems(corner) {
    var corners = settings && settings.corners && typeof settings.corners === "object" ? settings.corners : defaultCorners
    var value = corners[corner]
    if (typeof value === "string") return [value]
    if (!Array.isArray(value)) return []
    return value.filter(function(name) {
      var known = name === "battery" || name === "wifi"
      if (!known) console.warn("senysisu.lock: unknown corner indicator '" + name + "' (use \"battery\" or \"wifi\")")
      return known
    })
  }

  readonly property string placeholderText: opt("password", "placeholder", "Enter Password")
  readonly property int fieldWidth: Math.round(opt("password", "width", 340))
  readonly property int fieldHeight: Math.round(opt("password", "height", 56))
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // The reveal toggle sits inside the field's left edge; reserve the larger of
  // the two icons on both sides so the centered text stays symmetric.
  readonly property real revealReserve: revealEnabled ? Math.round(revealIcon.implicitWidth + 12) : 0
  readonly property real sideReserve: Math.max(fingerprintReserve, revealReserve)
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  // Location + current conditions from wttr.in. Location comes from
  // settings.lua, else the bar weather's weather.json, else IP auto-detect.
  // Formatted as "IN, Delhi ☀️  Clear +12°C"; hidden until a fetch succeeds.
  Process {
    id: weatherProc
    command: ["bash", "-c",
      "q=\"$1\"; f=\"$HOME/.local/state/omarchy/settings/weather.json\"; "
      + "[[ -n $q ]] || q=$(jq -r 'if (.latitude and .longitude) then \"\\(.latitude),\\(.longitude)\" else (.name // \"\") end' \"$f\" 2>/dev/null); "
      + "curl -fsS --max-time 8 \"https://wttr.in/${q// /+}?format=%l|%c|%C|%t|%S|%s\"",
      "weather", root.weatherLocation]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("|")
        if (parts.length < 4 || parts[0].indexOf("Unknown") !== -1) return
        var place = parts[0].split(",").map(function(p) { return p.trim() })
        var label = place.length > 1 ? place[place.length - 1] + ", " + place[0] : place[0]
        root.weatherText = label + " " + parts[1].trim() + "   " + parts[2].trim() + " " + parts[3].trim()
        root.weatherCondition = parts[2].trim()
        root.sunrise = parts.length > 5 ? parts[4].trim() : ""
        root.sunset = parts.length > 5 ? parts[5].trim() : ""
      }
    }
  }

  Timer {
    id: weatherTimer
    interval: Math.max(1, opt("weather", "refresh_minutes", 15)) * 60 * 1000
    running: root.weatherNeeded
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!weatherProc.running) weatherProc.running = true
  }

  onWeatherLocationChanged: {
    root.weatherText = ""
    root.weatherCondition = ""
    if (weatherNeeded) weatherTimer.restart()
  }

  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready && blur > 0
      blur: Math.max(0, Math.min(1, root.opt("background", "blur", 1.0)))
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
      saturation: root.grade.saturation
      brightness: root.grade.brightness
      colorizationColor: root.grade.tint
      colorization: root.grade.amount
      Behavior on saturation { NumberAnimation { duration: 1500 } }
      Behavior on brightness { NumberAnimation { duration: 1500 } }
      Behavior on colorization { NumberAnimation { duration: 1500 } }
      Behavior on colorizationColor { ColorAnimation { duration: 1500 } }
    }

    WeatherBackdrop {
      id: weatherBack
      anchors.fill: parent
      kind: root.effectKind
      night: root.effectNight
      intensity: root.opt("effects", "intensity", 1.0)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // Overlay text gets a soft shadow so it stays readable on any wallpaper.
    Item {
      id: overlay
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Color.background
        shadowBlur: 0.8
        shadowOpacity: 0.6
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(parent.height * 0.055)
        visible: root.weatherEnabled && root.weatherText.length > 0
        textFormat: Text.PlainText
        text: root.weatherText
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: root.infoFontSize
        font.bold: true
      }

      // Hours stacked over minutes, like a poster clock.
      Column {
        id: clockBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Math.round(parent.height * root.opt("clock", "position", 0.16))
        // Font line boxes carry generous padding; pull the date up under the digits.
        spacing: Math.round(clockHours.font.pixelSize * root.opt("date", "gap", -0.16))

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Math.round(clockHours.font.pixelSize * root.opt("clock", "line_gap", -0.45))

          Text {
            id: clockHours
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Qt.formatDateTime(root.now, root.opt("clock", "hour_format", "HH"))
            color: root.optColor("clock", "color", Color.lock.text)
            font.family: root.clockFont
            font.weight: Font.Black
            font.pixelSize: Math.round(overlay.height * root.opt("clock", "size", 0.19))
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Qt.formatDateTime(root.now, root.opt("clock", "minute_format", "mm"))
            color: root.optColor("clock", "color", Color.lock.text)
            font.family: root.clockFont
            font.weight: Font.Black
            font.pixelSize: clockHours.font.pixelSize
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          visible: root.opt("date", "enabled", true)
          text: Qt.formatDateTime(root.now, root.opt("date", "format", "d MMM dddd"))
          color: root.optColor("date", "color", Color.lock.text)
          font.family: Style.font.family
          font.pixelSize: root.fieldFontSize
          font.bold: true
        }
      }

      Component {
        id: batteryIndicator
        Text {
          textFormat: Text.PlainText
          text: (root.opt("battery", "show_percent", true) ? root.batteryPercent + "% " : "") + root.batteryIcon
          color: root.batteryPercent <= root.opt("battery", "low", 15) && !root.batteryCharging ? Color.lock.textError : Color.lock.text
          font.family: Style.font.family
          font.pixelSize: root.infoFontSize
          font.bold: true
        }
      }

      Component {
        id: wifiIndicator
        Text {
          textFormat: Text.PlainText
          text: (root.opt("wifi", "show_name", false) && root.wifiLabel.length > 0 ? root.wifiLabel + " " : "") + root.wifiIcon
          color: Color.lock.text
          font.family: Style.font.family
          font.pixelSize: root.infoFontSize
          font.bold: true
        }
      }

      Repeater {
        model: ["top_left", "top_right", "bottom_left", "bottom_right"]

        Row {
          required property string modelData
          readonly property int margin: Math.round(Style.font.heading * 1.2)
          x: modelData.indexOf("left") !== -1 ? margin : overlay.width - width - margin
          y: modelData.indexOf("top") !== -1 ? margin : overlay.height - height - margin
          spacing: Math.round(Style.font.heading * root.opt("indicators", "spacing", 1.0))

          Repeater {
            model: root.cornerItems(parent.modelData)

            Loader {
              required property string modelData
              sourceComponent: modelData === "battery" ? batteryIndicator : wifiIndicator
              // Hide (and let Row skip) the battery on machines without one.
              visible: modelData !== "battery" || root.batteryPresent
            }
          }
        }
      }
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      // overlay fills the screen at (0,0), so clockBlock's y is in our coordinates.
      y: clockBlock.y + clockBlock.height + Math.round(parent.height * root.opt("password", "gap", 0.13))
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: height / 2
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.sideReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.sideReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 && !root.showPassword ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 && !root.showPassword ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.showPassword = false
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          } else if (root.revealEnabled && event.modifiers & Qt.ControlModifier && event.key === Qt.Key_R) {
            root.showPassword = !root.showPassword
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Show/hide password toggle pinned inside the field's left edge.
      // Click it or press Ctrl+R; it resets to hidden after each submit.
      Text {
        id: revealIcon
        anchors.left: parent.left
        anchors.leftMargin: inputField.borderLeft + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.revealEnabled
        text: root.showPassword ? "󰈉" : "󰈈"
        color: revealMouse.containsMouse ? Color.lock.text : Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        MouseArea {
          id: revealMouse
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.showPassword = !root.showPassword
            root.wakeRequested()
            root.forcePasswordFocus()
          }
        }
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    // Nearest rain/snow, drawn over the clock and password box. Follows the
    // back layer's wind; takes no input (WeatherBackdrop sets enabled: false).
    WeatherBackdrop {
      anchors.fill: parent
      front: true
      driver: weatherBack
      kind: root.effectKind
      night: root.effectNight
      intensity: root.opt("effects", "intensity", 1.0)
    }
  }
}
