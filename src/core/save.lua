-- Hand-rolled serializer for save data. Encodes numbers/strings/booleans and
-- (nested) tables to a compact Lua-literal string and parses it back with a
-- small recursive-descent reader — no dependency, no code execution.
local Save = {}

local PATH = "save.dat"

local function esc(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function enc(v, out)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "0"
    elseif v == math.floor(v) and math.abs(v) < 1e15 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.14g", v)
    end
  elseif t == "string" then
    out[#out + 1] = '"' .. esc(v) .. '"'
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      enc(v[i], out)
      out[#out + 1] = ","
    end
    for k, x in pairs(v) do
      local isArray = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
      if not isArray then
        out[#out + 1] = "["
        enc(k, out)
        out[#out + 1] = "]="
        enc(x, out)
        out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  end
end

function Save.encode(v)
  local out = {}
  enc(v, out)
  return table.concat(out)
end

local function decode(s)
  local pos = 1
  local len = #s
  local parseValue

  local function skip()
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == " " or c == "\n" or c == "\t" or c == "\r" then
        pos = pos + 1
      else
        return
      end
    end
  end

  local function parseString()
    pos = pos + 1
    local buf = {}
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(buf)
      elseif c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        if n == "n" then buf[#buf + 1] = "\n"
        elseif n == "r" then buf[#buf + 1] = "\r"
        elseif n == "t" then buf[#buf + 1] = "\t"
        else buf[#buf + 1] = n end
        pos = pos + 2
      else
        buf[#buf + 1] = c
        pos = pos + 1
      end
    end
    error("unterminated string")
  end

  local function parseNumber()
    local start = pos
    while pos <= len and s:sub(pos, pos):match("[%d%.eE%+%-]") do
      pos = pos + 1
    end
    return tonumber(s:sub(start, pos - 1))
  end

  parseValue = function()
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local t = {}
      while true do
        skip()
        c = s:sub(pos, pos)
        if c == "}" or pos > len then
          pos = pos + 1
          break
        end
        if c == "[" then
          pos = pos + 1
          local k = parseValue()
          skip()
          if s:sub(pos, pos) == "]" then pos = pos + 1 end
          skip()
          if s:sub(pos, pos) == "=" then pos = pos + 1 end
          t[k] = parseValue()
        else
          t[#t + 1] = parseValue()
        end
        skip()
        c = s:sub(pos, pos)
        if c == "," or c == ";" then pos = pos + 1 end
      end
      return t
    elseif c == '"' then
      return parseString()
    elseif c == "t" then
      pos = pos + 4
      return true
    elseif c == "f" then
      pos = pos + 5
      return false
    elseif c == "n" then
      pos = pos + 4
      return nil
    else
      return parseNumber()
    end
  end

  return parseValue()
end

function Save.decode(str)
  if not str then return nil end
  local ok, val = pcall(decode, str)
  if not ok then return nil end
  return val
end

function Save.exists()
  return love.filesystem.getInfo(PATH) ~= nil
end

function Save.write(data)
  return love.filesystem.write(PATH, Save.encode(data))
end

function Save.read()
  local s = love.filesystem.read(PATH)
  if not s then return nil end
  return Save.decode(s)
end

function Save.remove()
  love.filesystem.remove(PATH)
end

return Save
