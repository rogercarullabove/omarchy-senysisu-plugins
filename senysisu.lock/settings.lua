-- Lock screen settings for roger.lock.
-- Saved changes apply live; no shell restart needed. Preview without locking:
--   omarchy-shell lock preview
-- Any setting you delete (or set to nil) falls back to its default. If this
-- file has an error, the lock screen uses the defaults and logs a warning
-- (journalctl --user -g roger.lock).
--
-- Sizes and positions given as fractions are relative to the screen height,
-- so 0.10 means 10% of the screen. Colors are "#rrggbb" hex, or nil to follow
-- the current Omarchy theme.

return {
  clock = {
    font = "Adwaita Sans",
    size = 0.25,            -- digit height
    position = 0.16,        -- how far the clock sits above the screen center
    line_gap = -0.45,       -- gap between hours and minutes (fraction of digit size; negative pulls together)
    hour_format = "HH",     -- "HH" = 24-hour, "hh" = 12-hour
    minute_format = "mm",
    color = nil,
  },

  date = {
    enabled = true,
    format = "d MMM dddd",  -- Qt date format, e.g. "dddd, d MMMM" or "yyyy-MM-dd"
    gap = -0.16,            -- gap below the minutes (fraction of digit size)
    color = nil,
  },

  weather = {
    enabled = true,
    location = nil,         -- e.g. "Helsinki"; nil = same as the bar's weather widget
    refresh_minutes = 15,
  },

  -- Corner indicators. List the indicators for each corner; within a corner
  -- they are shown left to right in the order listed. Leave an indicator out
  -- of every list to hide it.
  -- Available: "battery", "wifi"
  corners = {
    top_left = {},
    top_right = {},
    bottom_left = {},
    bottom_right = { "wifi", "battery" },
  },

  indicators = {
    spacing = 1.0,          -- gap between indicators in the same corner (in font heights)
  },

  battery = {
    show_percent = true,
    low = 15,               -- percentage at which the text turns red
  },

  wifi = {
    show_name = false,      -- show the network name (or "Ethernet") before the icon
  },

  password = {
    width = 340,            -- pixels
    height = 56,            -- pixels
    gap = 0.13,             -- space between the date and the password field
    placeholder = "Enter Password",
    reveal_toggle = true,   -- eye icon + Ctrl+R to show the password
  },

  -- Weather effects on the lock screen.
  effects = {
    mode = "auto",          -- "off", "auto" (follow the current weather) or "manual"
    weather = "rain",       -- manual mode: "sunny", "cloudy", "rain", "storm", "snow" or "snowstorm"
    night = "auto",         -- "auto" (from sunrise/sunset), true or false (no quotes)
    intensity = 1.0,        -- 0.1 to 2.0; scales how much rain/snow falls
  },

  background = {
    blur = 0.50,             -- 0.0 = sharp wallpaper, 1.0 = fully blurred
  },
}
