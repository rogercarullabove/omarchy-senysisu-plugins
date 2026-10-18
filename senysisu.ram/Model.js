// Bar styles the widget can draw, first one is the default.
var STYLES = ["ring+percent", "ring", "percent"]
var PANELS = ["breakdown", "history", "minimal"]

// Codepoint validated against the installed JetBrainsMono Nerd Font and
// nerd-fonts' glyphnames.json (fa-memory, a RAM stick). md-memory (U+F035B)
// renders as a chip, too close to senysisu.cpu's icon.
var ICON = ""

var DEFAULT_WARN_AT = 90
var DEFAULT_INTERVAL = 3000
// The warning only clears this many points below warnAt, so a value hovering
// at the threshold doesn't flicker between colors.
var HYSTERESIS = 5
// How much history the history panel keeps.
var HISTORY_MS = 5 * 60 * 1000

function pick(value, allowed, fallback) {
  var v = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(v) >= 0 ? v : fallback
}

function clampNumber(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// /proc/meminfo "Key:   12345 kB" lines -> { Key: kB, ... }
function parseMeminfo(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(\w+(?:\(\w+\))?):\s+(\d+)/.exec(lines[i])
    if (m) out[m[1]] = parseInt(m[2], 10)
  }
  return out
}

// Used is MemTotal − MemAvailable: MemFree alone counts reclaimable cache as
// used, which would turn the widget red on a healthy machine.
//   { totalKb, usedKb, cacheKb, freeKb, availableKb, swapTotalKb, swapUsedKb,
//     percent, swapPercent }
function memory(info, includeSwap) {
  var m = info || {}
  var total = m.MemTotal || 0
  var available = m.MemAvailable !== undefined ? m.MemAvailable : (m.MemFree || 0)
  var used = Math.max(0, total - available)
  var cache = Math.max(0, (m.Buffers || 0) + (m.Cached || 0) + (m.SReclaimable || 0) - (m.Shmem || 0))
  cache = Math.min(cache, Math.max(0, total - used))
  var swapTotal = m.SwapTotal || 0
  var swapUsed = Math.max(0, swapTotal - (m.SwapFree || 0))
  var percent = total > 0 ? used / total * 100 : 0
  if (includeSwap && total + swapTotal > 0) percent = (used + swapUsed) / (total + swapTotal) * 100
  return {
    totalKb: total,
    usedKb: used,
    cacheKb: cache,
    freeKb: Math.max(0, total - used - cache),
    availableKb: available,
    swapTotalKb: swapTotal,
    swapUsedKb: swapUsed,
    percent: Math.max(0, Math.min(100, percent)),
    swapPercent: swapTotal > 0 ? swapUsed / swapTotal * 100 : 0
  }
}

// /proc/swaps, minus its header -> [{ name, type, sizeKb, usedKb, zram }]
function parseSwaps(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 1; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 4) continue
    out.push({
      name: parts[0],
      type: parts[1],
      sizeKb: parseInt(parts[2], 10) || 0,
      usedKb: parseInt(parts[3], 10) || 0,
      zram: parts[0].indexOf("/dev/zram") === 0
    })
  }
  return out
}

// /proc/pressure/memory "some avg10=0.00 avg60=..." -> avg10 of "some", or null.
function parsePressure(text) {
  var m = /^some\s+avg10=([\d.]+)/m.exec(String(text || ""))
  return m ? parseFloat(m[1]) : null
}

function pushHistory(history, value, limit) {
  var next = (history || []).slice()
  next.push(value)
  while (next.length > limit) next.shift()
  return next
}

function isWarning(wasWarning, value, warnAt) {
  if (value >= warnAt) return true
  if (wasWarning && value >= warnAt - HYSTERESIS) return true
  return false
}

function formatPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return "--"
  return Math.round(n) + "%"
}

function formatKb(kb) {
  var n = Number(kb)
  if (!isFinite(n) || n < 0) return "--"
  var gib = n / 1048576
  if (gib >= 1) return gib.toFixed(1) + " GiB"
  return Math.round(n / 1024) + " MiB"
}

function formatSize(kb) {
  var n = Number(kb)
  if (!isFinite(n) || n < 0) return "--"
  var gib = n / 1048576
  if (gib >= 10) return Math.round(gib) + "G"
  if (gib >= 1) return gib.toFixed(1) + "G"
  return Math.round(n / 1024) + "M"
}

function usedOfTotal(usedKb, totalKb) {
  return formatKb(usedKb).replace(" GiB", "") + " / " + formatKb(totalKb)
}

function swapSummary(swaps) {
  var list = swaps || []
  if (list.length === 0) return "none"
  var kinds = []
  var hasZram = list.some(function(s) { return s.zram })
  var hasOther = list.some(function(s) { return !s.zram })
  if (hasZram) kinds.push("zram")
  if (hasOther) kinds.push(list.some(function(s) { return !s.zram && s.type === "file" }) ? "file" : "partition")
  return kinds.join(" + ")
}

function formatPressure(avg10) {
  if (avg10 === null || avg10 === undefined || !isFinite(avg10)) return "--"
  return avg10.toFixed(1) + " % (10 s)"
}

// omarchy-ram-data prints the panel-only details as JSON:
//   {"top": [{"name": "firefox", "rssKb": 2100000}, ...]}
// rssKb is summed over every process with that name.
function parseDetails(raw) {
  var value = null
  try { value = JSON.parse(String(raw || "").trim()) } catch (error) { value = null }
  value = value && typeof value === "object" ? value : {}
  var top = Array.isArray(value.top) ? value.top : []
  return {
    top: top.map(function(p) { return { name: String(p && p.name || "?"), rssKb: parseInt(p && p.rssKb, 10) || 0 } })
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLES: STYLES, PANELS: PANELS, HYSTERESIS: HYSTERESIS,
    pick: pick, clampNumber: clampNumber, parseMeminfo: parseMeminfo, memory: memory,
    parseSwaps: parseSwaps, parsePressure: parsePressure, pushHistory: pushHistory,
    isWarning: isWarning, formatPercent: formatPercent, formatKb: formatKb,
    formatSize: formatSize, usedOfTotal: usedOfTotal, swapSummary: swapSummary,
    formatPressure: formatPressure, parseDetails: parseDetails
  }
}
