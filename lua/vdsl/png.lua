--- PNG: Pure Lua reader/writer for PNG tEXt metadata chunks.
-- Read and inject text chunks (keyword → value) without C dependencies.
-- ComfyUI embeds "prompt" and "workflow" as tEXt chunks.
-- vdsl adds a "vdsl" chunk for semantic recipe preservation.
--
-- Usage:
--   local png = require("vdsl.png")
--   local chunks, err = png.read_text("output.png")
--   if chunks then print(chunks["prompt"]) end
--   png.inject_text("output.png", { vdsl = recipe_json })

local M = {}

-- ============================================================
-- Binary helpers
-- ============================================================

--- Read a big-endian uint32 from a string at a given offset (1-based).
-- @param data string binary data
-- @param offset integer 1-based position
-- @return integer
local function read_uint32_be(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  return b1 * 0x1000000 + b2 * 0x10000 + b3 * 0x100 + b4
end

--- Write a big-endian uint32 as a 4-byte string.
local function write_uint32_be(n)
  return string.char(
    math.floor(n / 0x1000000) % 256,
    math.floor(n / 0x10000) % 256,
    math.floor(n / 0x100) % 256,
    n % 256
  )
end

--- PNG signature (8 bytes).
local PNG_SIG = "\137PNG\r\n\26\n"

-- ============================================================
-- CRC32 (PNG uses ISO 3309 / ITU-T V.42)
-- ============================================================

-- Portable XOR: Lua 5.2 (bit32), LuaJIT (bit), Lua 5.3+ (native ~)
-- All variants return unsigned 32-bit (0..0xFFFFFFFF).
-- LuaJIT's bit.bxor returns signed 32-bit; normalize with % 2^32.
local bxor
if bit32 then
  bxor = bit32.bxor
else
  local ok, bit_mod = pcall(require, "bit")
  if ok then
    local raw = bit_mod.bxor
    bxor = function(a, b) return raw(a, b) % 0x100000000 end
  else
    bxor = load("return function(a,b) return a ~ b end")()
  end
end

local crc_table = nil

local function build_crc_table()
  crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then
        c = bxor(math.floor(c / 2), 0xEDB88320)
      else
        c = math.floor(c / 2)
      end
    end
    crc_table[i] = c
  end
end

--- Compute CRC32 over a string.
-- @param data string
-- @return integer CRC32 value
local function crc32(data)
  if not crc_table then build_crc_table() end
  local crc = 0xFFFFFFFF
  for i = 1, #data do
    local byte = data:byte(i)
    local idx = bxor(crc, byte) % 256
    crc = bxor(crc_table[idx], math.floor(crc / 256))
  end
  return bxor(crc, 0xFFFFFFFF) % 0x100000000
end

--- Build a complete PNG chunk (length + type + data + crc).
-- @param chunk_type string 4-char chunk type (e.g. "tEXt")
-- @param chunk_data string raw chunk data
-- @return string complete chunk bytes
local function make_chunk(chunk_type, chunk_data)
  local type_and_data = chunk_type .. chunk_data
  local c = crc32(type_and_data)
  return write_uint32_be(#chunk_data) .. type_and_data .. write_uint32_be(c)
end

--- Build a tEXt chunk from keyword and text.
-- @param keyword string chunk keyword (1-79 chars)
-- @param text string chunk text
-- @return string complete tEXt chunk bytes
local function make_text_chunk(keyword, text)
  return make_chunk("tEXt", keyword .. "\0" .. text)
end

-- Expose for testing
M._crc32 = crc32

--- Extract all tEXt chunks from a PNG file.
-- Design note: No CRC verification on read and no file size limit.
-- This is user-managed data; corrupted PNGs are caught by other tooling.
-- OOM on extreme files is handled by OS/runtime, not by artificial limits.
-- @param filepath string path to PNG file
-- @return table|nil chunks { keyword = text, ... } or nil on error
-- @return string|nil error message
function M.read_text(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    return nil, "png.read_text: filepath is required"
  end

  local f, err = io.open(filepath, "rb")
  if not f then
    return nil, "png.read_text: " .. (err or "cannot open file")
  end

  local content = f:read("*a")
  f:close()

  if not content or #content < 8 then
    return nil, "png.read_text: file too small"
  end

  if content:sub(1, 8) ~= PNG_SIG then
    return nil, "png.read_text: not a valid PNG file"
  end

  local chunks = {}
  local pos = 9  -- after 8-byte signature

  while pos + 7 <= #content do
    local length = read_uint32_be(content, pos)
    local chunk_type = content:sub(pos + 4, pos + 7)
    local data_start = pos + 8
    local data_end = data_start + length - 1

    if data_end > #content then
      break  -- truncated chunk
    end

    if chunk_type == "tEXt" then
      local chunk_data = content:sub(data_start, data_end)
      local null_pos = chunk_data:find("\0", 1, true)
      if null_pos then
        local keyword = chunk_data:sub(1, null_pos - 1)
        local text = chunk_data:sub(null_pos + 1)
        chunks[keyword] = text
      end
    elseif chunk_type == "IEND" then
      break
    end

    -- Advance: length(4) + type(4) + data(length) + crc(4)
    pos = pos + 12 + length
  end

  return chunks
end

--- Extract and JSON-decode ComfyUI metadata from a PNG file.
-- @param filepath string path to PNG file
-- @param json_mod table|nil JSON module (default: require("vdsl.json"))
-- @return table|nil { prompt = table|nil, workflow = table|nil }
-- @return string|nil error message
function M.read_comfy(filepath, json_mod)
  local chunks, err = M.read_text(filepath)
  if not chunks then
    return nil, err
  end

  json_mod = json_mod or require("vdsl.json")

  local result = {}

  if chunks["prompt"] then
    local ok, decoded = pcall(json_mod.decode, chunks["prompt"])
    if ok then
      result.prompt = decoded
    end
  end

  if chunks["workflow"] then
    local ok, decoded = pcall(json_mod.decode, chunks["workflow"])
    if ok then
      result.workflow = decoded
    end
  end

  return result
end

-- ============================================================
-- Writer: inject tEXt chunks into existing PNG
-- ============================================================

--- Inject tEXt chunks into an existing PNG file.
-- Inserts new chunks just before IEND. Overwrites existing chunks with same keyword.
-- @param filepath string path to PNG file (modified in-place)
-- @param text_chunks table { keyword = text, ... }
-- @return boolean success
-- @return string|nil error message
function M.inject_text(filepath, text_chunks)
  if type(filepath) ~= "string" or filepath == "" then
    return false, "png.inject_text: filepath is required"
  end
  if type(text_chunks) ~= "table" then
    return false, "png.inject_text: text_chunks must be a table"
  end

  local f, err = io.open(filepath, "rb")
  if not f then
    return false, "png.inject_text: " .. (err or "cannot open file")
  end
  local content = f:read("*a")
  f:close()

  if not content or #content < 8 then
    return false, "png.inject_text: file too small"
  end
  if content:sub(1, 8) ~= PNG_SIG then
    return false, "png.inject_text: not a valid PNG file"
  end

  -- Collect keywords to inject (for duplicate removal)
  local inject_keys = {}
  for k in pairs(text_chunks) do
    inject_keys[k] = true
  end

  -- Walk existing chunks, rebuild without conflicting tEXt keys
  local parts = { PNG_SIG }
  local pos = 9

  while pos + 7 <= #content do
    local length = read_uint32_be(content, pos)
    local chunk_type = content:sub(pos + 4, pos + 7)
    local chunk_end = pos + 12 + length - 1  -- last byte of chunk (incl crc)

    if chunk_end > #content then break end

    if chunk_type == "IEND" then
      -- Before IEND: inject our tEXt chunks
      -- Sort keys for deterministic output
      local keys = {}
      for k in pairs(text_chunks) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do
        parts[#parts + 1] = make_text_chunk(k, text_chunks[k])
      end
      -- Append IEND
      parts[#parts + 1] = content:sub(pos, chunk_end)
      break
    elseif chunk_type == "tEXt" then
      -- Check if this chunk's keyword conflicts
      local data_start = pos + 8
      local data_end = data_start + length - 1
      local chunk_data = content:sub(data_start, data_end)
      local null_pos = chunk_data:find("\0", 1, true)
      local keyword = null_pos and chunk_data:sub(1, null_pos - 1) or ""
      if inject_keys[keyword] then
        -- Skip: will be replaced by our version
      else
        parts[#parts + 1] = content:sub(pos, chunk_end)
      end
    else
      parts[#parts + 1] = content:sub(pos, chunk_end)
    end

    pos = pos + 12 + length
  end

  local output = table.concat(parts)

  local wf, werr = io.open(filepath, "wb")
  if not wf then
    return false, "png.inject_text: " .. (werr or "cannot write file")
  end
  wf:write(output)
  wf:close()

  return true
end

--- Inject tEXt chunks and write to a new file (non-destructive).
-- @param src_path string source PNG
-- @param dst_path string destination PNG
-- @param text_chunks table { keyword = text, ... }
-- @return boolean success
-- @return string|nil error message
function M.inject_text_to(src_path, dst_path, text_chunks)
  if type(src_path) ~= "string" or src_path == "" then
    return false, "png.inject_text_to: src_path is required"
  end
  if type(dst_path) ~= "string" or dst_path == "" then
    return false, "png.inject_text_to: dst_path is required"
  end

  -- Copy src to dst first
  local sf, serr = io.open(src_path, "rb")
  if not sf then
    return false, "png.inject_text_to: " .. (serr or "cannot open source")
  end
  local data = sf:read("*a")
  sf:close()

  local df, derr = io.open(dst_path, "wb")
  if not df then
    return false, "png.inject_text_to: " .. (derr or "cannot open dest")
  end
  df:write(data)
  df:close()

  return M.inject_text(dst_path, text_chunks)
end

return M
