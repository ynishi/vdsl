--- Shell utilities: safe command interpolation.

local M = {}

--- Shell-quote a string for safe interpolation into shell commands.
-- Prevents command injection when paths contain single quotes or special chars.
-- @param s string|any value to quote (tostring applied)
-- @return string safely quoted string
function M.quote(s)
  s = tostring(s):gsub("%z", "")  -- strip NUL bytes
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

return M
