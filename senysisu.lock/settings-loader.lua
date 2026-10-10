-- Evaluates settings.lua and prints it as JSON for LockView.qml to read.
-- Exits non-zero (and prints nothing) if the settings file has an error.

local ok, settings = pcall(dofile, arg[1])
if not ok then
  io.stderr:write(tostring(settings), "\n")
  os.exit(1)
end
if type(settings) ~= "table" then
  io.stderr:write("settings.lua must return a table\n")
  os.exit(1)
end

local function encode(value)
  local kind = type(value)
  if kind == "table" then
    local parts = {}
    if #value > 0 then
      for _, item in ipairs(value) do parts[#parts + 1] = encode(item) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, item in pairs(value) do
      parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif kind == "string" then
    return '"' .. value:gsub('[%c"\\]', function(c)
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif kind == "number" then
    return value == value and value ~= math.huge and value ~= -math.huge and tostring(value) or "null"
  elseif kind == "boolean" then
    return tostring(value)
  end
  return "null"
end

io.write(encode(settings), "\n")
