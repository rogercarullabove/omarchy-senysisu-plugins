// Bar styles the widget can draw, first one is the default.
var STYLES = ["ring+percent", "ring", "percent"]
var PANELS = ["mounts", "activity", "combined"]

// Codepoint validated against the installed JetBrainsMono Nerd Font and
// nerd-fonts' glyphnames.json (md-harddisk).
var ICON = "󰋊"

var DEFAULT_WARN_AT = 90
var DEFAULT_INTERVAL = 30000
var DEFAULT_MOUNTS = ["/"]
// The warning only clears this many points below warnAt, so a value hovering
// at the threshold doesn't flicker between colors.
var HYSTERESIS = 5
// Throughput is sampled this often while the panel is open, and the activity
// graph keeps this much of it.
var ACTIVITY_INTERVAL = 2000
var ACTIVITY_MS = 60000
// /proc/diskstats counts 512-byte sectors regardless of the device's own
// sector size.
var SECTOR_BYTES = 512

function pick(value, allowed, fallback) {
  var v = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(v) >= 0 ? v : fallback
}

function clampNumber(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// `mounts` setting: "auto" (every filesystem), a list of mount points, or a
// single mount point. Returns null for "auto".
function watchList(value) {
  if (value === "auto") return null
  if (typeof value === "string" && value !== "") return [value]
  if (Array.isArray(value)) {
    var list = value.filter(function(v) { return typeof v === "string" && v !== "" })
    if (list.length > 0) return list
  }
  return DEFAULT_MOUNTS.slice()
}

// Like df's Use%: used / (used + avail), so blocks reserved for root count
// as unavailable rather than free.
function usePercent(mount) {
  var denom = (mount.used || 0) + (mount.avail || 0)
  return denom > 0 ? Math.max(0, Math.min(100, mount.used / denom * 100)) : 0
}

// omarchy-disk-data JSON -> [{target, source, fstype, size, used, avail,
// luks, disk, model, percent}]
function parseMounts(raw) {
  var value = null
  try { value = JSON.parse(String(raw || "").trim()) } catch (error) { value = null }
  var list = value && Array.isArray(value.mounts) ? value.mounts : []
  return list.map(function(m) {
    var mount = {
      target: String(m.target || ""),
      source: String(m.source || ""),
      fstype: String(m.fstype || ""),
      size: Number(m.size) || 0,
      used: Number(m.used) || 0,
      avail: Number(m.avail) || 0,
      luks: !!m.luks,
      disk: String(m.disk || ""),
      model: String(m.model || "")
    }
    mount.percent = usePercent(mount)
    return mount
  })
}

// Watched mounts that exist right now. A watched path that isn't a mount
// point of its own (e.g. /home on a btrfs subvolume, listed once as /) falls
// back to the mount that contains it.
function watchedMounts(mounts, watch) {
  if (watch === null) return mounts.slice()
  var out = []
  for (var i = 0; i < watch.length; i++) {
    var best = null
    for (var j = 0; j < mounts.length; j++) {
      var t = mounts[j].target
      var contains = watch[i] === t || t === "/" || watch[i].indexOf(t + "/") === 0
      if (contains && (!best || t.length > best.target.length)) best = mounts[j]
    }
    if (best && out.indexOf(best) < 0) out.push(best)
  }
  return out
}

// The mount the bar shows: the fullest watched one.
function fullest(mounts) {
  var best = null
  for (var i = 0; i < (mounts || []).length; i++)
    if (!best || mounts[i].percent > best.percent) best = mounts[i]
  return best
}

function isWarning(wasWarning, value, warnAt) {
  if (value >= warnAt) return true
  if (wasWarning && value >= warnAt - HYSTERESIS) return true
  return false
}

// /proc/diskstats -> { name: {readBytes, writeBytes} } for the given disks.
function parseDiskstats(text, names) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var p = lines[i].trim().split(/\s+/)
    if (p.length < 10 || names.indexOf(p[2]) < 0) continue
    out[p[2]] = {
      readBytes: (parseInt(p[5], 10) || 0) * SECTOR_BYTES,
      writeBytes: (parseInt(p[9], 10) || 0) * SECTOR_BYTES
    }
  }
  return out
}

// Bytes per second per disk between two parseDiskstats() samples.
function rates(prev, cur, seconds) {
  var out = {}
  if (!prev || !cur || seconds <= 0) return out
  for (var name in cur) {
    if (!prev[name]) continue
    out[name] = {
      read: Math.max(0, (cur[name].readBytes - prev[name].readBytes) / seconds),
      write: Math.max(0, (cur[name].writeBytes - prev[name].writeBytes) / seconds)
    }
  }
  return out
}

// Physical disks backing the mounts, in mount order:
// [{name, model, mounts: [...]}]
function disks(mounts) {
  var out = []
  var byName = {}
  for (var i = 0; i < (mounts || []).length; i++) {
    var m = mounts[i]
    var key = m.disk || ""
    if (!byName[key]) {
      byName[key] = { name: key, model: m.model, mounts: [] }
      out.push(byName[key])
    }
    byName[key].mounts.push(m)
  }
  return out
}

function pushHistory(history, value, limit) {
  var next = (history || []).slice()
  next.push(value)
  while (next.length > limit) next.shift()
  return next
}

function formatPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return "--"
  return Math.round(n) + "%"
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) return "--"
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

function usedOfTotal(mount) {
  var used = formatBytes(mount.used), total = formatBytes(mount.size)
  var u = used.split(" "), t = total.split(" ")
  return u[1] === t[1] ? u[0] + " / " + total : used + " / " + total
}

function formatRate(bytesPerSecond) {
  var n = Number(bytesPerSecond)
  if (!isFinite(n) || n < 0) return "--"
  if (n < 1024) return "0 KiB/s"
  return formatBytes(n) + "/s"
}

function diskLabel(disk) {
  if (disk.model !== "") return disk.model
  return disk.name !== "" ? disk.name : "Other"
}

function heroMeta(mount) {
  if (!mount) return "no filesystem"
  var parts = [mount.target, mount.fstype]
  if (mount.luks) parts.push("LUKS")
  parts.push(formatBytes(mount.avail) + " free")
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLES: STYLES, PANELS: PANELS, HYSTERESIS: HYSTERESIS,
    pick: pick, clampNumber: clampNumber, watchList: watchList,
    usePercent: usePercent, parseMounts: parseMounts, watchedMounts: watchedMounts,
    fullest: fullest, isWarning: isWarning, parseDiskstats: parseDiskstats,
    rates: rates, disks: disks, pushHistory: pushHistory,
    formatPercent: formatPercent, formatBytes: formatBytes, usedOfTotal: usedOfTotal,
    formatRate: formatRate, diskLabel: diskLabel, heroMeta: heroMeta
  }
}
