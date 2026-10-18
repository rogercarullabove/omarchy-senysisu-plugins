// Bar styles the widget can draw, first one is the default.
var STYLES = ["sparkline", "columns", "ring", "percent", "ring+percent"]
var PANELS = ["overview", "cores", "minimal"]

// Codepoint validated against the installed JetBrainsMono Nerd Font and
// nerd-fonts' glyphnames.json (md-cpu_64_bit).
var ICON = "󰻠"

var DEFAULT_WARN_AT = 90
var DEFAULT_INTERVAL = 2000
var DEFAULT_MAX_COLUMNS = 8
// The warning only clears this many points below warnAt, so a value hovering
// at the threshold doesn't flicker between colors.
var HYSTERESIS = 5
// The warning compares the average of this many samples (~10 s at the
// default interval), so a short spike doesn't turn the bar red.
var WARN_SAMPLES = 5
// How much history the overview graph keeps.
var HISTORY_MS = 60000

function pick(value, allowed, fallback) {
  var v = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(v) >= 0 ? v : fallback
}

function clampNumber(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// /proc/stat lines "cpu  user nice system idle iowait irq softirq steal ..."
// for the total and "cpuN ..." per core. Returns cumulative jiffies:
//   { total: {busy, all}, cores: [{busy, all}, ...] }
function parseStat(text) {
  var lines = String(text || "").split("\n")
  var out = { total: null, cores: [] }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("cpu") !== 0) continue
    var parts = line.trim().split(/\s+/)
    var nums = []
    // guest/guest_nice (fields 9-10) are already counted in user/nice.
    for (var j = 1; j < parts.length && j <= 8; j++) nums.push(parseInt(parts[j], 10) || 0)
    var idle = (nums[3] || 0) + (nums[4] || 0)
    var all = 0
    for (var k = 0; k < nums.length; k++) all += nums[k]
    var sample = { busy: all - idle, all: all }
    if (parts[0] === "cpu") out.total = sample
    else out.cores.push(sample)
  }
  return out
}

function percentBetween(prev, cur) {
  if (!prev || !cur) return 0
  var dAll = cur.all - prev.all
  if (dAll <= 0) return 0
  return Math.max(0, Math.min(100, (cur.busy - prev.busy) / dAll * 100))
}

// Usage percent between two parseStat() samples: { total, cores: [...] }.
function usage(prev, cur) {
  var result = { total: 0, cores: [] }
  if (!prev || !cur || !cur.total) return result
  result.total = percentBetween(prev.total, cur.total)
  for (var i = 0; i < cur.cores.length; i++) result.cores.push(percentBetween(prev.cores[i], cur.cores[i]))
  return result
}

// Average neighbouring cores so at most maxColumns columns are drawn.
function groupCores(values, maxColumns) {
  var list = values || []
  var max = Math.max(1, Math.floor(maxColumns) || DEFAULT_MAX_COLUMNS)
  if (list.length <= max) return list.slice()
  var size = Math.ceil(list.length / max)
  var out = []
  for (var i = 0; i < list.length; i += size) {
    var sum = 0, n = 0
    for (var j = i; j < Math.min(list.length, i + size); j++) { sum += list[j]; n++ }
    out.push(n > 0 ? sum / n : 0)
  }
  return out
}

function pushHistory(history, value, limit) {
  var next = (history || []).slice()
  next.push(value)
  while (next.length > limit) next.shift()
  return next
}

function average(values, count) {
  var list = values || []
  var from = Math.max(0, list.length - count)
  var sum = 0, n = 0
  for (var i = from; i < list.length; i++) { sum += list[i]; n++ }
  return n > 0 ? sum / n : 0
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

// omarchy-cpu-data prints one JSON object with the panel-only details:
//   {"model": "...", "threads": 12, "load": [0.8, 0.9, 1.1], "uptime": 12345,
//    "freqMhz": [1100, ...], "maxFreqMhz": 4400, "tempC": 46,
//    "top": [{"name": "firefox", "cpu": 7.9}, ...]}
// "cpu" in top is top(1)'s per-process figure (100 = one full thread).
function parseDetails(raw) {
  var value = null
  try { value = JSON.parse(String(raw || "").trim()) } catch (error) { value = null }
  value = value && typeof value === "object" ? value : {}
  var num = function(v) { var n = parseFloat(v); return isFinite(n) ? n : null }
  var list = function(v) { return Array.isArray(v) ? v : [] }
  return {
    model: String(value.model || ""),
    threads: parseInt(value.threads, 10) || 0,
    load: list(value.load).map(num),
    uptime: num(value.uptime),
    freqMhz: list(value.freqMhz).map(num),
    maxFreqMhz: num(value.maxFreqMhz),
    tempC: num(value.tempC),
    top: list(value.top).map(function(p) { return { name: String(p && p.name || "?"), cpu: num(p && p.cpu) || 0 } })
  }
}

function averageFreq(freqs) {
  var sum = 0, n = 0
  for (var i = 0; i < (freqs || []).length; i++) if (freqs[i] !== null) { sum += freqs[i]; n++ }
  return n > 0 ? sum / n : null
}

function formatGHz(mhz) {
  if (mhz === null || mhz === undefined || !isFinite(mhz)) return "--"
  return (mhz / 1000).toFixed(1) + " GHz"
}

function formatTemp(c) {
  if (c === null || c === undefined || !isFinite(c)) return "--"
  return Math.round(c) + " °C"
}

function formatLoad(load) {
  if (!load || load.length < 3) return "--"
  return load.slice(0, 3).map(function(v) { return v === null ? "--" : v.toFixed(2) }).join("  ")
}

function formatUptime(seconds) {
  if (seconds === null || seconds === undefined || !isFinite(seconds)) return "--"
  var s = Math.floor(seconds)
  var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
  if (d > 0) return d + " d " + h + " h"
  if (h > 0) return h + " h " + m + " min"
  return m + " min"
}

// top(1) reports 100% per fully busy thread; the bar shows share of the
// whole CPU, so scale process figures the same way.
function processShare(cpu, threads) {
  var t = threads > 0 ? threads : 1
  return cpu / t
}

function heroMeta(threads, details) {
  var parts = []
  if (threads > 0) parts.push(threads + (threads === 1 ? " thread" : " threads"))
  var f = averageFreq(details.freqMhz)
  if (f !== null) parts.push(formatGHz(f))
  if (details.tempC !== null) parts.push(formatTemp(details.tempC))
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLES: STYLES, PANELS: PANELS, HYSTERESIS: HYSTERESIS,
    pick: pick, clampNumber: clampNumber, parseStat: parseStat, usage: usage,
    groupCores: groupCores, pushHistory: pushHistory, average: average,
    isWarning: isWarning, formatPercent: formatPercent, parseDetails: parseDetails,
    averageFreq: averageFreq, formatGHz: formatGHz, formatTemp: formatTemp,
    formatLoad: formatLoad, formatUptime: formatUptime, processShare: processShare,
    heroMeta: heroMeta
  }
}
