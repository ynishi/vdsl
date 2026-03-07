--- test_preflight.lua: Tests for Preflight (CompilerCheck UseCase)
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_preflight.lua

local T          = require("harness")
local preflight  = require("vdsl.compilers.comfyui.preflight")

print("=== Preflight Tests ===")

-- ============================================================
-- categories()
-- ============================================================

print("\n--- categories ---")

local cats = preflight.categories()
T.ok("categories: returns table", type(cats) == "table")
T.ok("categories: has checkpoints", cats[1] == "checkpoints" or cats[2] == "checkpoints"
  or cats[3] == "checkpoints" or cats[4] == "checkpoints" or cats[5] == "checkpoints")

-- ============================================================
-- extract(): validation
-- ============================================================

print("\n--- extract: validation ---")

T.err("extract: nil input", function()
  preflight.extract(nil)
end)

T.err("extract: string input", function()
  preflight.extract("not a table")
end)

T.err("extract: number input", function()
  preflight.extract(42)
end)

-- ============================================================
-- extract(): ComfyUI prompt
-- ============================================================

print("\n--- extract: ComfyUI prompt ---")

local prompt = {
  ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "model.safetensors" } },
  ["2"] = { class_type = "LoraLoader", inputs = { lora_name = "detail.safetensors" } },
  ["3"] = { class_type = "CLIPTextEncode", inputs = { text = "hello" } },
  ["4"] = { class_type = "VAELoader", inputs = { vae_name = "sdxl_vae.safetensors" } },
}

local req = preflight.extract(prompt)
T.ok("extract: checkpoints found", req.checkpoints["model.safetensors"])
T.ok("extract: loras found", req.loras["detail.safetensors"])
T.ok("extract: vaes found", req.vaes["sdxl_vae.safetensors"])

-- Empty prompt
local req_empty = preflight.extract({})
T.ok("extract: empty prompt returns table", type(req_empty) == "table")

-- ============================================================
-- extract_all(): validation
-- ============================================================

print("\n--- extract_all: validation ---")

T.err("extract_all: nil input", function()
  preflight.extract_all(nil)
end)

T.err("extract_all: string input", function()
  preflight.extract_all("bad")
end)

T.err("extract_all: bad element", function()
  preflight.extract_all({ "not a table" })
end)

-- ============================================================
-- extract_all(): merge
-- ============================================================

print("\n--- extract_all: merge ---")

local prompt_a = {
  ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "modelA.safetensors" } },
  ["2"] = { class_type = "LoraLoader", inputs = { lora_name = "loraA.safetensors" } },
}

local prompt_b = {
  ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "modelB.safetensors" } },
  ["2"] = { class_type = "LoraLoader", inputs = { lora_name = "loraA.safetensors" } },  -- duplicate
  ["3"] = { class_type = "LoraLoader", inputs = { lora_name = "loraB.safetensors" } },
}

local merged = preflight.extract_all({ prompt_a, prompt_b })
T.ok("extract_all: modelA", merged.checkpoints["modelA.safetensors"])
T.ok("extract_all: modelB", merged.checkpoints["modelB.safetensors"])
T.ok("extract_all: loraA (deduped)", merged.loras["loraA.safetensors"])
T.ok("extract_all: loraB", merged.loras["loraB.safetensors"])

-- Empty list
local merged_empty = preflight.extract_all({})
T.ok("extract_all: empty list returns table", type(merged_empty) == "table")
T.ok("extract_all: empty list has categories", type(merged_empty.checkpoints) == "table")

-- ============================================================
-- to_arrays()
-- ============================================================

print("\n--- to_arrays ---")

local arrays = preflight.to_arrays(merged)
T.ok("to_arrays: checkpoints is array", type(arrays.checkpoints) == "table")
T.eq("to_arrays: checkpoints count", #arrays.checkpoints, 2)
-- Sorted order
T.eq("to_arrays: checkpoints[1]", arrays.checkpoints[1], "modelA.safetensors")
T.eq("to_arrays: checkpoints[2]", arrays.checkpoints[2], "modelB.safetensors")
T.eq("to_arrays: loras count", #arrays.loras, 2)

-- ============================================================
-- check(): validation
-- ============================================================

print("\n--- check: validation ---")

T.err("check: nil required", function()
  preflight.check(nil, {})
end)

T.err("check: nil available", function()
  preflight.check({}, nil)
end)

-- ============================================================
-- check(): all available
-- ============================================================

print("\n--- check: all available ---")

local required_ok = {
  checkpoints = { ["model.safetensors"] = true },
  loras       = { ["lora.safetensors"] = true },
}
local available_ok = {
  checkpoints = { "model.safetensors", "other.safetensors" },
  loras       = { "lora.safetensors" },
}
local report_ok = preflight.check(required_ok, available_ok)
T.ok("check: ok = true", report_ok.ok)
T.eq("check: no missing", #report_ok.missing, 0)
T.ok("check: summary contains OK", report_ok.summary:find("OK") ~= nil)

-- ============================================================
-- check(): missing models
-- ============================================================

print("\n--- check: missing models ---")

local required_miss = {
  checkpoints = { ["model.safetensors"] = true },
  loras       = { ["missing_lora.safetensors"] = true },
}
local available_miss = {
  checkpoints = { "model.safetensors" },
  loras       = {},
}
local report_miss = preflight.check(required_miss, available_miss)
T.ok("check: ok = false", not report_miss.ok)
T.eq("check: 1 missing", #report_miss.missing, 1)
T.eq("check: missing name", report_miss.missing[1].name, "missing_lora.safetensors")
T.eq("check: missing category", report_miss.missing[1].category, "loras")
T.ok("check: summary contains FAIL", report_miss.summary:find("FAIL") ~= nil)

-- ============================================================
-- check(): unknown category in available (no crash)
-- ============================================================

print("\n--- check: unknown category ---")

local report_extra = preflight.check(
  { checkpoints = {} },
  { checkpoints = {}, unknown_cat = { "something" } }
)
T.ok("check: extra category ok", report_extra.ok)

-- ============================================================
-- format_required()
-- ============================================================

print("\n--- format_required ---")

local fmt = preflight.format_required({
  checkpoints = { ["model.safetensors"] = true },
  loras       = { ["a.safetensors"] = true, ["b.safetensors"] = true },
  vaes        = {},
})
T.ok("format: contains checkpoints", fmt:find("%[checkpoints%]") ~= nil)
T.ok("format: contains loras", fmt:find("%[loras%]") ~= nil)
T.ok("format: loras sorted", fmt:find("a.safetensors, b.safetensors") ~= nil)
-- Empty vaes should not appear
T.ok("format: no empty vaes", fmt:find("%[vaes%]") == nil)

-- Empty required
local fmt_empty = preflight.format_required({})
T.eq("format: empty", fmt_empty, "No model references found.")

-- format with node_types
local fmt_nodes = preflight.format_required({
  checkpoints = { ["model.safetensors"] = true },
  node_types  = { ["KSampler"] = true, ["CLIPTextEncode"] = true },
})
T.ok("format: has node_types", fmt_nodes:find("%[node_types%]") ~= nil)
T.ok("format: nodes sorted", fmt_nodes:find("CLIPTextEncode, KSampler") ~= nil)

-- ============================================================
-- extract(): node_types collection
-- ============================================================

print("\n--- extract: node_types ---")

local prompt_nt = {
  ["1"] = { class_type = "CheckpointLoaderSimple", inputs = { ckpt_name = "m.safetensors" } },
  ["2"] = { class_type = "KSampler", inputs = {} },
  ["3"] = { class_type = "CLIPTextEncode", inputs = { text = "hi" } },
  ["4"] = { class_type = "ColorCorrect", inputs = {} },
}

local req_nt = preflight.extract(prompt_nt)
T.ok("extract: node_types exists",       type(req_nt.node_types) == "table")
T.ok("extract: has KSampler",            req_nt.node_types["KSampler"])
T.ok("extract: has CLIPTextEncode",      req_nt.node_types["CLIPTextEncode"])
T.ok("extract: has ColorCorrect",        req_nt.node_types["ColorCorrect"])
T.ok("extract: has CheckpointLoader",    req_nt.node_types["CheckpointLoaderSimple"])

-- extract_all merges node_types
local prompt_nt2 = {
  ["1"] = { class_type = "UltralyticsDetectorProvider", inputs = { model_name = "face.pt" } },
}
local merged_nt = preflight.extract_all({ prompt_nt, prompt_nt2 })
T.ok("extract_all: merged KSampler",                merged_nt.node_types["KSampler"])
T.ok("extract_all: merged UltralyticsDetector",      merged_nt.node_types["UltralyticsDetectorProvider"])

-- to_arrays includes node_types
local arrays_nt = preflight.to_arrays(merged_nt)
T.ok("to_arrays: node_types is array", type(arrays_nt.node_types) == "table")
T.ok("to_arrays: node_types count > 0", #arrays_nt.node_types > 0)

-- ============================================================
-- check(): missing node types
-- ============================================================

print("\n--- check: missing nodes ---")

local required_nodes = {
  checkpoints = { ["model.safetensors"] = true },
  node_types  = {
    ["KSampler"] = true,
    ["CLIPTextEncode"] = true,
    ["ColorCorrect"] = true,
    ["UltralyticsDetectorProvider"] = true,
  },
}
local available_nodes = {
  checkpoints = { "model.safetensors" },
  node_types  = { "KSampler", "CLIPTextEncode", "VAEDecode" },
}
local report_nodes = preflight.check(required_nodes, available_nodes)
T.ok("check nodes: ok = false",           not report_nodes.ok)
T.eq("check nodes: missing models = 0",   #report_nodes.missing, 0)
T.eq("check nodes: missing_nodes = 2",    #report_nodes.missing_nodes, 2)
T.eq("check nodes: missing[1]",           report_nodes.missing_nodes[1], "ColorCorrect")
T.eq("check nodes: missing[2]",           report_nodes.missing_nodes[2], "UltralyticsDetectorProvider")
T.ok("check nodes: summary has node",     report_nodes.summary:find("custom node") ~= nil)

-- check: all nodes available
local report_nodes_ok = preflight.check(
  { checkpoints = {}, node_types = { ["KSampler"] = true } },
  { checkpoints = {}, node_types = { "KSampler", "VAEDecode" } }
)
T.ok("check nodes ok: ok = true",       report_nodes_ok.ok)
T.eq("check nodes ok: no missing",      #report_nodes_ok.missing_nodes, 0)

-- check: no node_types in available (MCP hasn't sent them yet) — skip silently
local report_no_avail = preflight.check(
  { checkpoints = {}, node_types = { ["KSampler"] = true } },
  { checkpoints = {} }
)
T.ok("check no avail nodes: ok = true", report_no_avail.ok)
T.eq("check no avail nodes: skip",      #report_no_avail.missing_nodes, 0)

-- ============================================================
-- Summary
-- ============================================================

T.summary()
