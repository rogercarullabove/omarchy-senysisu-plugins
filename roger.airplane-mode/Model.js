// omarchy-airplane-mode-data prints one JSON object describing current
// radio states, e.g.:
//   {"wifi": "enabled", "wwan": "enabled", "bluetooth": "enabled", "airplaneOn": false}
function parseRadioStatus(raw) {
  var parsed = null
  try {
    parsed = JSON.parse(String(raw || "").trim())
  } catch (error) {
    parsed = null
  }

  var value = parsed && typeof parsed === "object" ? parsed : {}

  return {
    wifi: String(value.wifi || "unknown"),
    wwan: String(value.wwan || "unknown"),
    bluetooth: String(value.bluetooth || "unknown"),
    airplaneOn: !!value.airplaneOn
  }
}

// Codepoint cross-checked against nerd-fonts' glyphnames.json and rendered
// with the installed font to confirm the shape (md-airplane, U+F001D). One
// glyph covers both states; ON/OFF is communicated by color via
// BarIconButton's "active" state, matching how omarchy's
// NightLight/StayAwake bar indicators reuse one glyph both ways.
var ICON_AIRPLANE = "󰀝"

function airplaneIcon(info) {
  return ICON_AIRPLANE
}

function radioLabel(state) {
  if (state === "enabled") return "on"
  if (state === "disabled") return "off"
  return "unknown"
}

function tooltipText(info) {
  var status = info || {}
  if (status.airplaneOn) return "Airplane Mode: ON"
  return "Airplane Mode: OFF  (WiFi " + radioLabel(status.wifi)
    + ", Bluetooth " + radioLabel(status.bluetooth)
    + ", LTE " + radioLabel(status.wwan) + ")"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseRadioStatus: parseRadioStatus,
    airplaneIcon: airplaneIcon,
    radioLabel: radioLabel,
    tooltipText: tooltipText
  }
}
