--- UUID v4 generator for VDSL ID management.
-- Used across all layers: Workspace, Run, Generation.

local M = {}

local random = math.random

-- Seed with best available entropy
math.randomseed(os.time() + (os.clock() * 1000000))

--- Generate a UUID v4 string (RFC 4122).
-- @return string "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
function M.uuid()
  local b = {}
  for i = 1, 16 do b[i] = random(0, 255) end
  -- version 4: bits 48-51 = 0100
  b[7] = (b[7] & 0x0f) | 0x40
  -- variant 1: bits 64-65 = 10
  b[9] = (b[9] & 0x3f) | 0x80
  return string.format(
    "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    b[1], b[2], b[3], b[4],
    b[5], b[6], b[7], b[8],
    b[9], b[10], b[11], b[12],
    b[13], b[14], b[15], b[16])
end

--- Short form of UUID (first 8 chars).
-- @param uuid string full UUID
-- @return string 8-char prefix
function M.short(uuid)
  return uuid:sub(1, 8)
end

return M
