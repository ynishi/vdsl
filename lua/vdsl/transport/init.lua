--- Transport: HTTP client abstraction.
-- Backend-agnostic layer. Default backend: curl.
-- Custom backends can be injected via set_backend().
--
-- Backend interface (table with 3 functions):
--   get(url, headers) -> string          HTTP GET, returns body
--   post_json(url, data, headers) -> table  HTTP POST JSON, returns decoded table
--   download(url, filepath, headers) -> boolean  Download file
--
-- All methods accept an optional `headers` table for auth etc.

local M = {}

local _backend = nil

--- Validate a URL string.
local function check_url(url, caller)
  if type(url) ~= "string" or url == "" then
    error(caller .. ": url must be a non-empty string", 3)
  end
end

--- Set a custom HTTP backend.
-- @param backend table { get, post_json, download } or nil to reset
function M.set_backend(backend)
  if backend ~= nil then
    if type(backend) ~= "table" then
      error("set_backend: backend must be a table with get/post_json/download", 2)
    end
    if type(backend.get) ~= "function" then
      error("set_backend: backend.get must be a function", 2)
    end
    if type(backend.post_json) ~= "function" then
      error("set_backend: backend.post_json must be a function", 2)
    end
    if type(backend.download) ~= "function" then
      error("set_backend: backend.download must be a function", 2)
    end
  end
  _backend = backend
end

--- Get the active backend (lazy: defaults to curl).
local function get_backend()
  if _backend then return _backend end
  _backend = require("vdsl.transport.curl")
  return _backend
end

--- HTTP GET request.
-- @param url string
-- @param headers table|nil optional HTTP headers
-- @return string response body
function M.get(url, headers)
  check_url(url, "transport.get")
  return get_backend().get(url, headers)
end

--- HTTP POST with JSON body.
-- @param url string
-- @param data table Lua table to encode as JSON
-- @param headers table|nil optional HTTP headers
-- @return table parsed JSON response
function M.post_json(url, data, headers)
  check_url(url, "transport.post_json")
  return get_backend().post_json(url, data, headers)
end

--- Download binary content to a file.
-- @param url string
-- @param filepath string local path to save
-- @param headers table|nil optional HTTP headers
-- @return boolean success
function M.download(url, filepath, headers)
  check_url(url, "transport.download")
  if type(filepath) ~= "string" or filepath == "" then
    error("transport.download: filepath must be a non-empty string", 2)
  end
  if filepath:find("%z") then
    error("transport.download: filepath contains NUL byte", 2)
  end
  return get_backend().download(url, filepath, headers)
end

return M
