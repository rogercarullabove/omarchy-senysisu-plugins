// omarchy-lte-data prints one JSON object describing modem state, e.g.:
//   {"present": false}
// or
//   {"present": true, "modemIndex": 0, "state": "connected", "powerState": "on",
//    "signal": 72, "bars": 3, "operator": "Vodafone", "technology": "lte",
//    "roaming": false, "connected": true, "pingMs": 42.1}
function parseLteStatus(raw) {
  var parsed = null
  try {
    parsed = JSON.parse(String(raw || "").trim())
  } catch (error) {
    parsed = null
  }

  var value = parsed && typeof parsed === "object" ? parsed : {}

  return {
    present: !!value.present,
    modemIndex: value.modemIndex !== undefined && value.modemIndex !== null ? String(value.modemIndex) : "",
    state: String(value.state || "unknown"),
    powerState: String(value.powerState || "unknown"),
    signal: typeof value.signal === "number" ? value.signal : parseInt(value.signal, 10) || 0,
    bars: typeof value.bars === "number" ? value.bars : parseInt(value.bars, 10) || 0,
    operator: String(value.operator || ""),
    technology: String(value.technology || ""),
    roaming: !!value.roaming,
    connected: !!value.connected,
    pingMs: (value.pingMs === null || value.pingMs === undefined) ? null : parseFloat(value.pingMs)
  }
}

// Codepoints validated against the installed Nerd Font's cmap (Material
// Design Icons subset): signal-cellular-{outline,1,2,3}, signal-off. MDI has
// no 4-bar cellular glyph, so a full-strength (3-4 bar) reading tops out on
// the same "3 bars" icon as a 3-bar reading.
var ICON_OFF = "󰞃"                // signal-off: no modem, or radio powered down
var ICON_CELLULAR_OUTLINE = "󰢿"   // 0 bars
var ICON_CELLULAR_1 = "󰢼"
var ICON_CELLULAR_2 = "󰢽"
var ICON_CELLULAR_3 = "󰢾"

function lteIcon(info) {
  var status = info || {}
  if (!status.present || status.powerState === "off") return ICON_OFF
  var bars = Math.max(0, Math.min(4, status.bars || 0))
  if (bars <= 0) return ICON_CELLULAR_OUTLINE
  if (bars === 1) return ICON_CELLULAR_1
  if (bars === 2) return ICON_CELLULAR_2
  return ICON_CELLULAR_3
}

// Dot-row rendering of the 0-4 bar bucket, independent of icon-font glyphs.
function barsDots(bars) {
  var level = Math.max(0, Math.min(4, parseInt(bars, 10) || 0))
  var dots = ""
  for (var i = 0; i < 4; i++) dots += i < level ? "●" : "○"
  return dots
}

function formatSignal(signal, present) {
  if (!present) return "--"
  var value = parseInt(signal, 10)
  if (!isFinite(value) || value < 0) return "--"
  return value + "%"
}

// mmcli reports access-technologies as a comma-separated lowercase list
// (e.g. "lte", "lte, umts"). Upper-case each token for display.
function formatTechnology(technology) {
  var raw = String(technology || "").trim()
  if (raw === "" || raw.toLowerCase() === "unknown") return "--"
  var parts = raw.split(",")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var token = parts[i].trim()
    if (token !== "") out.push(token.toUpperCase())
  }
  return out.length > 0 ? out.join(", ") : "--"
}

function formatPingLatency(ms) {
  if (ms === null || ms === undefined) return "--"
  var value = parseFloat(ms)
  if (!isFinite(value) || value < 0) return "Timeout"
  return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms"
}

// modem.generic.state values: failed, unknown, initializing, locked,
// disabled, disabling, enabling, enabled, searching, registered,
// disconnecting, connecting, connected.
function stateLabel(state) {
  var raw = String(state || "unknown")
  if (raw === "") return "Unknown"
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function roamingLabel(roaming) {
  return roaming ? "Roaming" : "Home network"
}

function heroTitle(info) {
  var status = info || {}
  if (!status.present) return "No Modem"
  return status.operator !== "" ? status.operator : "LTE Modem"
}

function heroMeta(info) {
  var status = info || {}
  if (!status.present) return "NOT DETECTED"
  if (status.connected) return "CONNECTED"
  return stateLabel(status.state).toUpperCase()
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLteStatus: parseLteStatus,
    lteIcon: lteIcon,
    barsDots: barsDots,
    formatSignal: formatSignal,
    formatTechnology: formatTechnology,
    formatPingLatency: formatPingLatency,
    stateLabel: stateLabel,
    roamingLabel: roamingLabel,
    heroTitle: heroTitle,
    heroMeta: heroMeta
  }
}
