--- Test harness: unified assertion utilities for all VDSL tests.
-- Usage:
--   local T = require("tests.harness")
--   T.eq("name", got, expected)
--   T.ok("name", condition)
--   T.err("name", function() ... end)
--   T.summary()

local M = {}

local pass_count = 0
local fail_count = 0

function M.eq(name, got, expected)
  if got == expected then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    io.stderr:write("FAIL: " .. name .. "\n")
    io.stderr:write("  expected: " .. tostring(expected) .. "\n")
    io.stderr:write("  got:      " .. tostring(got) .. "\n")
  end
end

function M.ok(name, cond)
  M.eq(name, cond, true)
end

function M.err(name, fn)
  local ok = pcall(fn)
  if not ok then
    pass_count = pass_count + 1
  else
    fail_count = fail_count + 1
    io.stderr:write("FAIL: " .. name .. " (expected error, got success)\n")
  end
end

function M.summary()
  print(string.format("\n%d passed, %d failed", pass_count, fail_count))
  if fail_count > 0 then
    os.exit(1)
  end
end

function M.counts()
  return pass_count, fail_count
end

return M
