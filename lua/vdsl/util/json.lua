--- Pure Lua JSON encoder/decoder for ComfyUI prompt format.
-- Handles: string, number, boolean, nil, table (array/object).

local M = {}

--- Sentinel metatable: tables with this metatable encode as JSON arrays.
-- Needed to distinguish empty arrays [] from empty objects {}.
local ARRAY_MT = {}

--- Mark a table as a JSON array (required for empty arrays to encode as []).
-- Non-empty sequential tables are auto-detected; this is only needed for
-- empty tables or to force array encoding.
-- @param t table|nil optional table to mark (defaults to {})
-- @return table the marked table
function M.array(t)
  return setmetatable(t or {}, ARRAY_MT)
end

local function is_array(t)
  if type(t) ~= "table" then return false end
  if getmetatable(t) == ARRAY_MT then return true end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  if count == 0 then return false end
  for i = 1, count do
    if t[i] == nil then return false end
  end
  return true
end

local encode_value

local function encode_string(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return '"' .. s .. '"'
end

local function encode_number(n)
  if n ~= n then return '"NaN"' end
  if n == math.huge then return '1e999' end
  if n == -math.huge then return '-1e999' end
  if n == math.floor(n) and math.abs(n) < 2^53 then
    return string.format("%d", n)
  end
  return string.format("%.17g", n)
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function encode_array(t, indent, level)
  local items = {}
  for i = 1, #t do
    items[i] = encode_value(t[i], indent, level + 1)
  end
  if indent then
    local pad = string.rep(indent, level + 1)
    local pad_close = string.rep(indent, level)
    return "[\n" .. pad .. table.concat(items, ",\n" .. pad) .. "\n" .. pad_close .. "]"
  end
  return "[" .. table.concat(items, ",") .. "]"
end

local function encode_object(t, indent, level)
  local keys = sorted_keys(t)
  if #keys == 0 then return "{}" end
  local items = {}
  for _, k in ipairs(keys) do
    local key_str = encode_string(tostring(k))
    local val_str = encode_value(t[k], indent, level + 1)
    items[#items + 1] = key_str .. ":" .. (indent and " " or "") .. val_str
  end
  if indent then
    local pad = string.rep(indent, level + 1)
    local pad_close = string.rep(indent, level)
    return "{\n" .. pad .. table.concat(items, ",\n" .. pad) .. "\n" .. pad_close .. "}"
  end
  return "{" .. table.concat(items, ",") .. "}"
end

encode_value = function(v, indent, level)
  level = level or 0
  local vtype = type(v)
  if v == nil then
    return "null"
  elseif vtype == "boolean" then
    return v and "true" or "false"
  elseif vtype == "number" then
    return encode_number(v)
  elseif vtype == "string" then
    return encode_string(v)
  elseif vtype == "table" then
    if is_array(v) then
      return encode_array(v, indent, level)
    else
      return encode_object(v, indent, level)
    end
  else
    error("json: unsupported type: " .. vtype)
  end
end

function M.encode(value, pretty)
  local indent = pretty and "  " or nil
  return encode_value(value, indent, 0)
end

-- ============================================================
-- Decoder
-- ============================================================

function M.decode(str)
  if type(str) ~= "string" then
    error("json.decode: expected string, got " .. type(str), 2)
  end

  local pos = 1
  local len = #str

  local function skip_ws()
    while pos <= len do
      local b = str:byte(pos)
      if b == 32 or b == 9 or b == 10 or b == 13 then
        pos = pos + 1
      else
        break
      end
    end
  end

  local function expect(ch)
    skip_ws()
    if str:byte(pos) ~= ch then
      error(string.format(
        "json.decode: expected '%s' at position %d, got '%s'",
        string.char(ch), pos, str:sub(pos, pos)
      ), 3)
    end
    pos = pos + 1
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local segments = {}
    local seg_start = pos
    while pos <= len do
      local b = str:byte(pos)
      if b == 34 then
        segments[#segments + 1] = str:sub(seg_start, pos - 1)
        pos = pos + 1
        return table.concat(segments)
      elseif b == 92 then
        segments[#segments + 1] = str:sub(seg_start, pos - 1)
        pos = pos + 1
        local esc = str:byte(pos)
        if     esc == 34  then segments[#segments + 1] = '"'
        elseif esc == 92  then segments[#segments + 1] = '\\'
        elseif esc == 47  then segments[#segments + 1] = '/'
        elseif esc == 110 then segments[#segments + 1] = '\n'
        elseif esc == 116 then segments[#segments + 1] = '\t'
        elseif esc == 114 then segments[#segments + 1] = '\r'
        elseif esc == 98  then segments[#segments + 1] = '\b'
        elseif esc == 102 then segments[#segments + 1] = '\f'
        elseif esc == 117 then
          local hex = str:sub(pos + 1, pos + 4)
          local code = tonumber(hex, 16)
          pos = pos + 4
          if code then
            -- UTF-16 surrogate pair handling
            if code >= 0xD800 and code <= 0xDBFF then
              -- High surrogate: expect \uXXXX low surrogate
              if str:byte(pos + 1) == 92 and str:byte(pos + 2) == 117 then
                local hex2 = str:sub(pos + 3, pos + 6)
                local low = tonumber(hex2, 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                  code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                  pos = pos + 6
                else
                  code = 0xFFFD  -- unpaired high surrogate
                end
              else
                code = 0xFFFD  -- unpaired high surrogate
              end
            elseif code >= 0xDC00 and code <= 0xDFFF then
              code = 0xFFFD  -- lone low surrogate
            end
            -- Encode codepoint to UTF-8
            if code < 0x80 then
              segments[#segments + 1] = string.char(code)
            elseif code < 0x800 then
              segments[#segments + 1] = string.char(
                0xC0 + math.floor(code / 64),
                0x80 + (code % 64)
              )
            elseif code < 0x10000 then
              segments[#segments + 1] = string.char(
                0xE0 + math.floor(code / 4096),
                0x80 + math.floor((code % 4096) / 64),
                0x80 + (code % 64)
              )
            else
              segments[#segments + 1] = string.char(
                0xF0 + math.floor(code / 262144),
                0x80 + math.floor((code % 262144) / 4096),
                0x80 + math.floor((code % 4096) / 64),
                0x80 + (code % 64)
              )
            end
          end
        end
        pos = pos + 1
        seg_start = pos
      else
        pos = pos + 1
      end
    end
    error("json.decode: unterminated string", 3)
  end

  local function parse_number()
    local start = pos
    if str:byte(pos) == 45 then pos = pos + 1 end
    while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
      pos = pos + 1
    end
    if pos <= len and str:byte(pos) == 46 then
      pos = pos + 1
      while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
        pos = pos + 1
      end
    end
    if pos <= len and (str:byte(pos) == 101 or str:byte(pos) == 69) then
      pos = pos + 1
      if pos <= len and (str:byte(pos) == 43 or str:byte(pos) == 45) then
        pos = pos + 1
      end
      while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
        pos = pos + 1
      end
    end
    local n = tonumber(str:sub(start, pos - 1))
    if not n then
      error("json.decode: invalid number at position " .. start, 3)
    end
    return n
  end

  local function parse_array()
    pos = pos + 1
    local arr = {}
    skip_ws()
    if str:byte(pos) == 93 then
      pos = pos + 1
      return setmetatable(arr, ARRAY_MT)
    end
    while true do
      arr[#arr + 1] = parse_value()
      skip_ws()
      local b = str:byte(pos)
      if b == 93 then
        pos = pos + 1
        return arr
      elseif b == 44 then
        pos = pos + 1
      else
        error("json.decode: expected ',' or ']' at position " .. pos, 3)
      end
    end
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if str:byte(pos) == 125 then
      pos = pos + 1
      return obj
    end
    while true do
      skip_ws()
      if str:byte(pos) ~= 34 then
        error("json.decode: expected string key at position " .. pos, 3)
      end
      local key = parse_string()
      expect(58)
      obj[key] = parse_value()
      skip_ws()
      local b = str:byte(pos)
      if b == 125 then
        pos = pos + 1
        return obj
      elseif b == 44 then
        pos = pos + 1
      else
        error("json.decode: expected ',' or '}' at position " .. pos, 3)
      end
    end
  end

  parse_value = function()
    skip_ws()
    local b = str:byte(pos)
    if b == 34 then       return parse_string()
    elseif b == 123 then  return parse_object()
    elseif b == 91 then   return parse_array()
    elseif b == 116 then
      if str:sub(pos, pos + 3) ~= "true" then
        error("json.decode: invalid literal at position " .. pos, 3)
      end
      pos = pos + 4; return true
    elseif b == 102 then
      if str:sub(pos, pos + 4) ~= "false" then
        error("json.decode: invalid literal at position " .. pos, 3)
      end
      pos = pos + 5; return false
    elseif b == 110 then
      if str:sub(pos, pos + 3) ~= "null" then
        error("json.decode: invalid literal at position " .. pos, 3)
      end
      pos = pos + 4; return nil
    elseif b == 45 or (b >= 48 and b <= 57) then
      return parse_number()
    else
      error("json.decode: unexpected character at position " .. pos, 3)
    end
  end

  return parse_value()
end

return M
