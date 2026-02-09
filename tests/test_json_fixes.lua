--- test_json_fixes.lua: Tests for json.lua fixes (empty array, literal validation, surrogate pairs).
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_json_fixes.lua

local json = require("vdsl.json")
local T    = require("harness")

print("=== JSON Fixes Tests ===")

-- ============================================================
-- Fix 3: is_array empty table handling + ARRAY_MT marker
-- ============================================================

print("\n--- Empty array marker ---")

-- Decode: [] round-trips as []
T.eq("decode [] → encode []",
  json.encode(json.decode("[]")),
  "[]")

-- Decode: {} round-trips as {}
T.eq("decode {} → encode {}",
  json.encode(json.decode("{}")),
  "{}")

-- json.array() creates a marked empty table
T.eq("json.array() encodes as []",
  json.encode(json.array()),
  "[]")

-- json.array with content still works
T.eq("json.array({1,2}) encodes as [1,2]",
  json.encode(json.array({1, 2})),
  "[1,2]")

-- Unmarked empty table → object {}
T.eq("plain {} encodes as {}",
  json.encode({}),
  "{}")

-- Non-empty sequential table auto-detected as array
T.eq("non-empty array auto-detected",
  json.encode({1, 2, 3}),
  "[1,2,3]")

-- Nested: object with empty array value
T.eq("nested empty array",
  json.encode({ items = json.array() }),
  '{"items":[]}')

-- Decode nested empty array round-trips
local nested_json = '{"items":[],"name":"test"}'
T.eq("nested [] round-trip",
  json.encode(json.decode(nested_json)),
  nested_json)

-- ComfyUI pattern: object_info with empty COMBO lists
local comfy_info = '{"node":{"input":{"required":{"field":[[]]}}}}'
local decoded = json.decode(comfy_info)
local re_encoded = json.encode(decoded)
T.eq("ComfyUI empty COMBO round-trip", re_encoded, comfy_info)

-- ============================================================
-- Fix 4: Literal validation (true/false/null)
-- ============================================================

print("\n--- Literal validation ---")

-- Valid literals
T.eq("decode true",  json.decode("true"), true)
T.eq("decode false", json.decode("false"), false)
T.eq("decode null",  json.decode("null"), nil)

-- In arrays/objects
T.eq("true in array", json.decode("[true]")[1], true)
T.eq("false in array", json.decode("[false]")[1], false)
-- null in array → nil (Lua limitation: arr[#arr+1] = nil is no-op)
-- json.decode("[null,1]") produces {1} because nil can't be stored in arrays
T.eq("null in array (Lua nil limitation)", json.decode("[null,1]")[1], 1)

-- Invalid literals should error
T.err("trumpet not valid", function()
  json.decode('{"key":trumpet}')
end)

T.err("tru not valid", function()
  json.decode("tru")
end)

T.err("falsy not valid", function()
  json.decode("falsy")
end)

T.err("nul not valid", function()
  json.decode("nul")
end)

T.err("nullify not valid (object value)", function()
  json.decode('{"key":nullify}')
end)

T.err("trueish not valid (array element)", function()
  json.decode("[trueish]")
end)

-- Edge: literal at end of string (truncated)
T.err("truncated true", function()
  json.decode("tru")
end)

T.err("truncated false", function()
  json.decode("fals")
end)

T.err("truncated null", function()
  json.decode("nul")
end)

-- ============================================================
-- Fix 5: Unicode surrogate pair handling
-- ============================================================

print("\n--- Surrogate pair handling ---")

-- Grinning face U+1F600 = \uD83D\uDE00
local grin = json.decode('"\\uD83D\\uDE00"')
-- U+1F600 in UTF-8: 0xF0 0x9F 0x98 0x80
T.eq("surrogate pair: grinning face byte 1", grin:byte(1), 0xF0)
T.eq("surrogate pair: grinning face byte 2", grin:byte(2), 0x9F)
T.eq("surrogate pair: grinning face byte 3", grin:byte(3), 0x98)
T.eq("surrogate pair: grinning face byte 4", grin:byte(4), 0x80)
T.eq("surrogate pair: grinning face length", #grin, 4)

-- Pile of poo U+1F4A9 = \uD83D\uDCA9
local poo = json.decode('"\\uD83D\\uDCA9"')
T.eq("surrogate pair: poo byte 1", poo:byte(1), 0xF0)
T.eq("surrogate pair: poo byte 2", poo:byte(2), 0x9F)
T.eq("surrogate pair: poo byte 3", poo:byte(3), 0x92)
T.eq("surrogate pair: poo byte 4", poo:byte(4), 0xA9)

-- Mixed: ASCII + surrogate pair + ASCII
local mixed = json.decode('"hello\\uD83D\\uDE00world"')
T.eq("mixed: starts with hello", mixed:sub(1, 5), "hello")
T.eq("mixed: ends with world", mixed:sub(10, 14), "world")
T.eq("mixed: total length", #mixed, 14)

-- Lone high surrogate → U+FFFD (0xEF 0xBF 0xBD)
local lone_high = json.decode('"\\uD83D"')
T.eq("lone high surrogate → FFFD byte 1", lone_high:byte(1), 0xEF)
T.eq("lone high surrogate → FFFD byte 2", lone_high:byte(2), 0xBF)
T.eq("lone high surrogate → FFFD byte 3", lone_high:byte(3), 0xBD)
T.eq("lone high surrogate length", #lone_high, 3)

-- Lone low surrogate → U+FFFD
local lone_low = json.decode('"\\uDC00"')
T.eq("lone low surrogate → FFFD byte 1", lone_low:byte(1), 0xEF)
T.eq("lone low surrogate → FFFD byte 2", lone_low:byte(2), 0xBF)
T.eq("lone low surrogate → FFFD byte 3", lone_low:byte(3), 0xBD)

-- High surrogate followed by non-surrogate \uXXXX → FFFD + normal char
local bad_pair = json.decode('"\\uD83D\\u0041"')
-- Should produce: U+FFFD (3 bytes) + 'A' (1 byte)
T.eq("bad pair: FFFD byte 1", bad_pair:byte(1), 0xEF)
T.eq("bad pair: FFFD byte 2", bad_pair:byte(2), 0xBF)
T.eq("bad pair: FFFD byte 3", bad_pair:byte(3), 0xBD)
T.eq("bad pair: A after FFFD", bad_pair:byte(4), 0x41)
T.eq("bad pair: length", #bad_pair, 4)

-- BMP characters still work (not surrogates)
T.eq("BMP: \\u0041 = A", json.decode('"\\u0041"'), "A")
T.eq("BMP: \\u00E9 = e-acute",
  json.decode('"\\u00E9"'),
  string.char(0xC3, 0xA9))

-- CJK character U+4E16 (世)
local sekai = json.decode('"\\u4E16"')
T.eq("CJK U+4E16 byte 1", sekai:byte(1), 0xE4)
T.eq("CJK U+4E16 byte 2", sekai:byte(2), 0xB8)
T.eq("CJK U+4E16 byte 3", sekai:byte(3), 0x96)

-- ============================================================
-- Regression: existing decode behavior preserved
-- ============================================================

print("\n--- Regression: existing behavior ---")

T.eq("string roundtrip", json.decode(json.encode("hello")), "hello")
T.eq("number roundtrip", json.decode(json.encode(42)), 42)
T.eq("float roundtrip",  json.decode(json.encode(3.14)), 3.14)
T.eq("bool true roundtrip",  json.decode(json.encode(true)), true)
T.eq("bool false roundtrip", json.decode(json.encode(false)), false)
T.eq("array roundtrip", json.encode(json.decode("[1,2,3]")), "[1,2,3]")
T.eq("object roundtrip", json.encode(json.decode('{"a":1}')), '{"a":1}')

-- Nested structure (null in array is lost due to Lua nil limitation)
local complex = '{"arr":[1,true,"hi"],"obj":{"nested":false}}'
T.eq("complex roundtrip", json.encode(json.decode(complex)), complex)

T.summary()
