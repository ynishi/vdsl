--- Transport backend: curl (command-line).
-- Default HTTP backend using system curl via io.popen / os.execute.
-- Implements the backend interface: { get, post_json, download }.

local json = require("vdsl.json")

local M = {}

local function shell_quote(s)
  s = s:gsub("%z", "")  -- strip NUL bytes
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Check os.execute success (portable across Lua versions).
-- Lua 5.2+: returns true on success, nil on failure.
-- Lua 5.1/LuaJIT: returns exit code number (0 = success).
local function shell_ok(result)
  return result == true or result == 0
end

--- Read popen output and check exit status (portable).
-- Returns body and success flag.
-- Lua 5.1 close() returns nil (unknowable) -> rely on body content.
local function popen_read(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil, false end
  local body = handle:read("*a")
  local result = handle:close()
  -- Lua 5.1: result is nil (can't determine exit status)
  -- LuaJIT: result is exit code (0 = success)
  -- Lua 5.2+: result is true/nil
  local ok = (result == nil) or (result == true) or (result == 0)
  return body, ok
end

--- Build curl header flags from a headers table.
-- @param headers table|nil { ["Authorization"] = "Bearer ...", ... }
-- @return string curl -H flags
local function curl_headers(headers)
  if not headers then return "" end
  local parts = {}
  for k, v in pairs(headers) do
    parts[#parts + 1] = string.format('-H %s', shell_quote(k .. ": " .. v))
  end
  return table.concat(parts, " ")
end

--- Default curl timeout flags.
local CURL_TIMEOUT = "--connect-timeout 10 --max-time 300"

--- HTTP GET request.
-- @param url string
-- @param headers table|nil optional HTTP headers
-- @return string response body
function M.get(url, headers)
  local h = curl_headers(headers)
  local cmd = "curl -sf " .. CURL_TIMEOUT .. " " .. h .. " " .. shell_quote(url)
  local body, ok = popen_read(cmd)
  if ok and body and #body > 0 then
    return body
  end
  error("failed to connect (is ComfyUI running?)", 2)
end

--- HTTP POST with JSON body.
-- @param url string
-- @param data table Lua table to encode as JSON
-- @param headers table|nil optional HTTP headers
-- @return table parsed JSON response
function M.post_json(url, data, headers)
  local body = json.encode(data)

  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if not f then error("cannot create temp file", 2) end
  f:write(body)
  f:close()

  local h = curl_headers(headers)
  local cmd = string.format(
    'curl -sf %s -X POST -H "Content-Type: application/json" %s -d @%s %s',
    CURL_TIMEOUT, h, shell_quote(tmp), shell_quote(url)
  )
  local resp_body, ok = popen_read(cmd)
  os.remove(tmp)

  if ok and resp_body and #resp_body > 0 then
    return json.decode(resp_body)
  end
  error("failed to POST", 2)
end

--- Download binary content to a file.
-- @param url string
-- @param filepath string local path to save
-- @param headers table|nil optional HTTP headers
-- @return boolean success
function M.download(url, filepath, headers)
  local h = curl_headers(headers)
  local cmd = string.format("curl -sf %s %s -o %s %s",
    CURL_TIMEOUT, h, shell_quote(filepath), shell_quote(url))
  if shell_ok(os.execute(cmd)) then return true end
  error("failed to download", 2)
end

return M
