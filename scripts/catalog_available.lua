--- catalog_available.lua: Dump all available catalog keys.
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;scripts/?.lua;'..package.path" scripts/catalog_available.lua
--
-- Outputs a structured list of every catalog and its entries,
-- including user catalogs registered via vdsl.use_catalogs().
--
-- To include user catalogs, set VDSL_CATALOGS env var:
--   VDSL_CATALOGS=./my_catalogs lua ... examples/catalog_available.lua

local vdsl     = require("vdsl")
local Entity   = require("vdsl.entity")
local catalogs = vdsl.catalogs

-- Register user catalog dir from env if present
local user_dir = os.getenv("VDSL_CATALOGS")
if user_dir and user_dir ~= "" then
  vdsl.use_catalogs(user_dir)
end

-- Known built-in names (ensures these are loaded even with lazy __index)
local builtin_top   = { "quality", "style", "camera", "lighting", "effect", "material", "atmosphere" }
local builtin_packs = { "figure", "environment", "color" }

--- Collect sorted keys from a table.
local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

--- Check if a table looks like a pack (values are sub-tables, not Traits).
local function is_pack(t)
  for _, v in pairs(t) do
    if type(v) == "table" and not Entity.is(v, "trait") then
      return true
    end
    return false  -- check first entry only
  end
  return false
end

--- Print a catalog's keys on one line.
local function print_catalog(prefix, cat)
  local keys = sorted_keys(cat)
  print(string.format("  %-24s (%d) %s", prefix, #keys, table.concat(keys, ", ")))
end

-- Force-load all known built-ins
for _, name in ipairs(builtin_top) do catalogs[name] = catalogs[name] end
for _, name in ipairs(builtin_packs) do catalogs[name] = catalogs[name] end

local shell_quote = require("vdsl.util.shell").quote

-- Also scan user dirs for catalog files not yet loaded
for _, dir in ipairs(vdsl.catalog_dirs()) do
  local handle = io.popen("ls " .. shell_quote(dir) .. "/*.lua 2>/dev/null")
  if handle then
    for line in handle:lines() do
      local name = line:match("([^/]+)%.lua$")
      if name then
        catalogs[name] = catalogs[name]  -- trigger lazy-load + merge
      end
    end
    handle:close()
  end
end

-- Separate into top-level catalogs and packs
local top_names = {}
local pack_names = {}
local seen = {}

for k, v in pairs(catalogs) do
  if type(v) == "table" then
    seen[k] = true
    if is_pack(v) then
      pack_names[#pack_names + 1] = k
    else
      top_names[#top_names + 1] = k
    end
  end
end
table.sort(top_names)
table.sort(pack_names)

-- Count totals
local total_entries = 0

print("=== Top-level catalogs ===")
for _, name in ipairs(top_names) do
  local cat = catalogs[name]
  if cat then
    print_catalog(name, cat)
    for _ in pairs(cat) do total_entries = total_entries + 1 end
  end
end

print("\n=== Packs ===")
for _, pack_name in ipairs(pack_names) do
  local pack = catalogs[pack_name]
  if pack then
    for _, sub_name in ipairs(sorted_keys(pack)) do
      local sub = pack[sub_name]
      if type(sub) == "table" then
        print_catalog(pack_name .. "." .. sub_name, sub)
        for _ in pairs(sub) do total_entries = total_entries + 1 end
      end
    end
  end
end

-- User catalog dirs info
local dirs = vdsl.catalog_dirs()
if #dirs > 0 then
  print("\n=== User catalog dirs ===")
  for _, d in ipairs(dirs) do
    print("  " .. d)
  end
end

print(string.format("\n--- Total: %d catalogs, %d entries ---",
  #top_names + #pack_names, total_entries))
