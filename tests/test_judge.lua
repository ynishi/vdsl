--- test_judge.lua: Verify VLM judge module
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_judge.lua

local judge = require("vdsl.judge")
local json  = require("vdsl.util.json")
local T     = require("harness")

-- ============================================================
-- Base64 encoding
-- ============================================================

local tmp = os.tmpname()
local f = io.open(tmp, "wb")
f:write("Hello")
f:close()

local b64 = judge._read_base64(tmp)
T.eq("base64: Hello", b64, "SGVsbG8=")
os.remove(tmp)

-- Multi-byte: 1 byte (padding ==)
tmp = os.tmpname()
f = io.open(tmp, "wb")
f:write("A")
f:close()
T.eq("base64: single byte", judge._read_base64(tmp), "QQ==")
os.remove(tmp)

-- 2 bytes (padding =)
tmp = os.tmpname()
f = io.open(tmp, "wb")
f:write("AB")
f:close()
T.eq("base64: two bytes", judge._read_base64(tmp), "QUI=")
os.remove(tmp)

-- 3 bytes (no padding)
tmp = os.tmpname()
f = io.open(tmp, "wb")
f:write("ABC")
f:close()
T.eq("base64: three bytes", judge._read_base64(tmp), "QUJD")
os.remove(tmp)

-- Error cases
tmp = os.tmpname()
f = io.open(tmp, "wb")
f:write("")
f:close()
T.err("base64: empty file errors", function() judge._read_base64(tmp) end)
os.remove(tmp)

T.err("base64: missing file errors", function() judge._read_base64("/nonexistent/path.png") end)
T.err("base64: nil path errors", function() judge._read_base64(nil) end)
T.err("base64: empty string errors", function() judge._read_base64("") end)

-- ============================================================
-- Prompt building
-- ============================================================

local test_candidates = {
  { suffix = "d055", sweep = { denoise = 0.55 }, key = "a__d055" },
  { suffix = "d060", sweep = { denoise = 0.60 }, key = "a__d060" },
  { suffix = "d065", sweep = { denoise = 0.65 }, key = "a__d065" },
}

local prompt = judge._build_prompt(test_candidates, {
  criteria = { "顔が破綻していないか", "衣装が反映されているか" },
  prune = { "B01", "B04" },
  top_k = 2,
})

T.ok("prompt: contains candidate count", prompt:find("3 AI%-generated") ~= nil)
T.ok("prompt: contains d055", prompt:find("d055") ~= nil)
T.ok("prompt: contains d060", prompt:find("d060") ~= nil)
T.ok("prompt: contains d065", prompt:find("d065") ~= nil)
T.ok("prompt: contains sweep info", prompt:find("denoise=") ~= nil)
T.ok("prompt: contains criteria 1", prompt:find("顔が破綻していないか") ~= nil)
T.ok("prompt: contains criteria 2", prompt:find("衣装が反映されているか") ~= nil)
T.ok("prompt: contains prune B01", prompt:find("B01") ~= nil)
T.ok("prompt: contains B01 desc", prompt:find("face distortion") ~= nil)
T.ok("prompt: contains prune B04", prompt:find("B04") ~= nil)
T.ok("prompt: contains top_k", prompt:find("top 2 candidates") ~= nil)
T.ok("prompt: contains JSON format", prompt:find('"survivors"') ~= nil)

-- Without prune/criteria
local prompt_minimal = judge._build_prompt(test_candidates, { top_k = 2 })
T.ok("prompt minimal: no prune header", prompt_minimal:find("%[Breakdown Detection%]") == nil)
T.ok("prompt minimal: no criteria header", prompt_minimal:find("%[Evaluation Criteria%]") == nil)
T.ok("prompt minimal: still has format", prompt_minimal:find('"survivors"') ~= nil)

-- ============================================================
-- Content building
-- ============================================================

local img1 = os.tmpname()
local img2 = os.tmpname()
f = io.open(img1, "wb"); f:write("PNG1"); f:close()
f = io.open(img2, "wb"); f:write("PNG2"); f:close()

local content_cands = {
  { suffix = "d055", sweep = { denoise = 0.55 }, output_path = img1 },
  { suffix = "d060", sweep = { denoise = 0.60 }, output_path = img2 },
}

local content = judge._build_content(content_cands, { top_k = 1 })
-- 2 images × (image + label) + 1 prompt = 5 blocks
T.eq("content: block count", #content, 5)
T.eq("content: block 1 is image", content[1].type, "image")
T.eq("content: block 1 media type", content[1].source.media_type, "image/png")
T.ok("content: block 1 has base64 data", #content[1].source.data > 0)
T.eq("content: block 2 is text label", content[2].type, "text")
T.ok("content: block 2 has suffix", content[2].text:find("d055") ~= nil)
T.eq("content: block 3 is image", content[3].type, "image")
T.eq("content: block 4 is text label", content[4].type, "text")
T.ok("content: block 4 has suffix", content[4].text:find("d060") ~= nil)
T.eq("content: block 5 is prompt", content[5].type, "text")
T.ok("content: prompt has format", content[5].text:find('"survivors"') ~= nil)

os.remove(img1)
os.remove(img2)

-- ============================================================
-- JSON extraction from VLM response
-- ============================================================

-- Clean JSON
local parsed = judge._extract_json('{"survivors":["d060","d065"],"pruned":["d055"],"scores":{"d055":3.0,"d060":8.5,"d065":7.0}}')
T.ok("extract: clean JSON", parsed ~= nil)
T.eq("extract: clean survivors count", #parsed.survivors, 2)
T.eq("extract: clean survivors[1]", parsed.survivors[1], "d060")

-- JSON in markdown block
parsed = judge._extract_json([[
Here is my evaluation:

```json
{"survivors":["d060"],"pruned":["d055","d065"],"scores":{"d060":9.0}}
```

The winner is d060.
]])
T.ok("extract: markdown block", parsed ~= nil)
T.eq("extract: markdown survivors[1]", parsed.survivors[1], "d060")

-- JSON in bare code block
parsed = judge._extract_json([[
```
{"survivors":["d065"]}
```
]])
T.ok("extract: bare code block", parsed ~= nil)
T.eq("extract: bare block survivors[1]", parsed.survivors[1], "d065")

-- JSON embedded in prose
parsed = judge._extract_json([[
My evaluation result is {"survivors":["d060","d065"],"pruned":["d055"]} and that's it.
]])
T.ok("extract: embedded JSON", parsed ~= nil)
T.eq("extract: embedded survivors count", #parsed.survivors, 2)

-- Garbage → nil
T.eq("extract: garbage → nil", judge._extract_json("I cannot evaluate."), nil)
T.eq("extract: empty → nil", judge._extract_json(""), nil)
T.eq("extract: nil → nil", judge._extract_json(nil), nil)

-- ============================================================
-- Response normalization
-- ============================================================

local cands = {
  { suffix = "d055" },
  { suffix = "d060" },
  { suffix = "d065" },
  { suffix = "d070" },
}

-- Normal case
local norm = judge._normalize_response({
  survivors = { "d060", "d065" },
  pruned = { "d055", "d070" },
  scores = { d055 = 3.0, d060 = 8.5, d065 = 7.0, d070 = 2.0 },
}, cands, 2)

T.ok("normalize: returns table", norm ~= nil)
T.eq("normalize: survivors count", #norm.survivors, 2)
T.eq("normalize: survivors[1]", norm.survivors[1], "d060")
T.eq("normalize: survivors[2]", norm.survivors[2], "d065")
T.eq("normalize: pruned count", #norm.pruned, 2)
T.eq("normalize: scores d060", norm.scores.d060, 8.5)
T.eq("normalize: scores d070", norm.scores.d070, 2.0)

-- Too many survivors → capped at top_k
norm = judge._normalize_response({
  survivors = { "d060", "d065", "d070" },
}, cands, 2)
T.eq("normalize: cap at top_k", #norm.survivors, 2)

-- Invalid suffix filtered
norm = judge._normalize_response({
  survivors = { "d060", "INVALID", "d065" },
}, cands, 2)
T.eq("normalize: invalid filtered count", #norm.survivors, 2)
T.eq("normalize: valid remain[1]", norm.survivors[1], "d060")
T.eq("normalize: valid remain[2]", norm.survivors[2], "d065")

-- Empty survivors → fallback
norm = judge._normalize_response({ survivors = {} }, cands, 2)
T.eq("normalize: fallback[1]", norm.survivors[1], "d055")
T.eq("normalize: fallback[2]", norm.survivors[2], "d060")

-- All invalid → fallback
norm = judge._normalize_response({ survivors = { "X", "Y" } }, cands, 1)
T.eq("normalize: all invalid fallback", norm.survivors[1], "d055")

-- No scores → nil
norm = judge._normalize_response({ survivors = { "d060" } }, cands, 1)
T.eq("normalize: no scores", norm.scores, nil)

-- Invalid scores filtered
norm = judge._normalize_response({
  survivors = { "d060" },
  scores = { d060 = 9.0, INVALID = 5.0, d065 = "not a number" },
}, cands, 1)
T.ok("normalize: scores filtered", norm.scores ~= nil)
T.eq("normalize: valid score kept", norm.scores.d060, 9.0)
T.eq("normalize: invalid key removed", norm.scores.INVALID, nil)
T.eq("normalize: non-number removed", norm.scores.d065, nil)

-- Pruned auto-computed from survivors
norm = judge._normalize_response({
  survivors = { "d060" },
}, cands, 1)
T.ok("normalize: pruned auto-computed", norm.pruned ~= nil)
T.eq("normalize: pruned count", #norm.pruned, 3)

-- nil parsed → nil
T.eq("normalize: nil → nil", judge._normalize_response(nil, cands, 2), nil)

-- Missing survivors key → nil
T.eq("normalize: no survivors key", judge._normalize_response({ ranking = { "d060" } }, cands, 2), nil)

-- ============================================================
-- Breakdown catalog
-- ============================================================

T.eq("breakdowns: B01 severity", judge.breakdowns.B01.severity, "critical")
T.eq("breakdowns: B05 severity", judge.breakdowns.B05.severity, "major")
T.eq("breakdowns: B09 severity", judge.breakdowns.B09.severity, "minor")
T.eq("breakdowns: B14 severity", judge.breakdowns.B14.severity, "info")

local bd_count = 0
for _ in pairs(judge.breakdowns) do bd_count = bd_count + 1 end
T.eq("breakdowns: 16 entries", bd_count, 16)

-- ============================================================
-- vlm() factory validation
-- ============================================================

T.err("vlm: unsupported api", function() judge.vlm({ api = "openai" }) end)

local eval_fn = judge.vlm({ top_k = 2, api_key = "test-key" })
T.eq("vlm: returns function", type(eval_fn), "function")

-- Returns nil when not all images exist
local result = eval_fn({
  { suffix = "d060", exists = false, output_path = "/tmp/nope.png" },
  { suffix = "d065", exists = true,  output_path = "/tmp/nope2.png" },
}, {})
T.eq("vlm: nil when not all exist", result, nil)

-- Returns nil when no images exist
result = eval_fn({
  { suffix = "d060", exists = false },
  { suffix = "d065", exists = false },
}, {})
T.eq("vlm: nil when none exist", result, nil)

-- ============================================================
-- vlm() end-to-end with call_vlm mock
-- ============================================================

-- Create mock images
local mock_img1 = os.tmpname()
local mock_img2 = os.tmpname()
local mock_img3 = os.tmpname()
f = io.open(mock_img1, "wb"); f:write("FAKE_PNG_1"); f:close()
f = io.open(mock_img2, "wb"); f:write("FAKE_PNG_2"); f:close()
f = io.open(mock_img3, "wb"); f:write("FAKE_PNG_3"); f:close()

-- Save original and install mock
local orig_call_vlm = judge.call_vlm
local captured_content = nil
local captured_model = nil
local captured_api_key = nil

judge.call_vlm = function(content, model, api_key)
  captured_content = content
  captured_model = model
  captured_api_key = api_key
  return '```json\n{"survivors":["d060","d065"],"pruned":["d055"],"scores":{"d055":2.0,"d060":9.0,"d065":7.5},"reasons":{"d055":"顔歪み","d060":"最良","d065":"良好"}}\n```'
end

local mock_eval = judge.vlm({
  top_k    = 2,
  criteria = { "顔の品質", "衣装反映度" },
  prune    = { "B01", "B04" },
  api_key  = "sk-test-mock-key",
})

local mock_candidates = {
  { suffix = "d055", key = "a__d055", sweep = { denoise = 0.55 },
    exists = true, output_path = mock_img1 },
  { suffix = "d060", key = "a__d060", sweep = { denoise = 0.60 },
    exists = true, output_path = mock_img2 },
  { suffix = "d065", key = "a__d065", sweep = { denoise = 0.65 },
    exists = true, output_path = mock_img3 },
}

local mock_result = mock_eval(mock_candidates, { key = "a" })

-- call_vlm received correct args
T.eq("mock: model", captured_model, "claude-sonnet-4-5-20250514")
T.eq("mock: api_key", captured_api_key, "sk-test-mock-key")

-- Content structure: 3 images × (image + label) + 1 prompt = 7 blocks
T.eq("mock: content blocks", #captured_content, 7)
T.eq("mock: block 1 type", captured_content[1].type, "image")
T.eq("mock: block 1 media", captured_content[1].source.media_type, "image/png")
T.ok("mock: block 1 b64 data", #captured_content[1].source.data > 0)
T.eq("mock: block 2 type", captured_content[2].type, "text")
T.ok("mock: block 2 label", captured_content[2].text:find("d055") ~= nil)
T.eq("mock: last block is prompt", captured_content[7].type, "text")
T.ok("mock: prompt has criteria", captured_content[7].text:find("顔の品質") ~= nil)
T.ok("mock: prompt has prune B01", captured_content[7].text:find("B01") ~= nil)

-- Result structure
T.ok("mock: result not nil", mock_result ~= nil)
T.eq("mock: survivors count", #mock_result.survivors, 2)
T.eq("mock: survivors[1]", mock_result.survivors[1], "d060")
T.eq("mock: survivors[2]", mock_result.survivors[2], "d065")
T.ok("mock: pruned exists", mock_result.pruned ~= nil)
T.eq("mock: pruned[1]", mock_result.pruned[1], "d055")
T.eq("mock: score d060", mock_result.scores.d060, 9.0)
T.eq("mock: score d065", mock_result.scores.d065, 7.5)
T.eq("mock: score d055", mock_result.scores.d055, 2.0)

-- ============================================================
-- vlm() fallback when call_vlm returns garbage
-- ============================================================

judge.call_vlm = function(content, model, api_key)
  return "I cannot evaluate these images properly."
end

local fallback_eval = judge.vlm({ top_k = 1, api_key = "sk-test" })
local fallback_result = fallback_eval({
  { suffix = "d055", exists = true, output_path = mock_img1 },
  { suffix = "d060", exists = true, output_path = mock_img2 },
}, {})

T.ok("fallback: returns result", fallback_result ~= nil)
T.eq("fallback: survivors count", #fallback_result.survivors, 1)
T.eq("fallback: falls back to first", fallback_result.survivors[1], "d055")

-- ============================================================
-- vlm() fallback when call_vlm returns nil
-- ============================================================

judge.call_vlm = function() return nil end

local nil_eval = judge.vlm({ top_k = 2, api_key = "sk-test" })
local nil_result = nil_eval({
  { suffix = "d055", exists = true, output_path = mock_img1 },
  { suffix = "d060", exists = true, output_path = mock_img2 },
}, {})

T.ok("nil resp: returns result", nil_result ~= nil)
T.eq("nil resp: fallback count", #nil_result.survivors, 2)
T.eq("nil resp: fallback[1]", nil_result.survivors[1], "d055")
T.eq("nil resp: fallback[2]", nil_result.survivors[2], "d060")

-- ============================================================
-- vlm() with partial JSON (survivors only, no scores)
-- ============================================================

judge.call_vlm = function()
  return '{"survivors":["d060"]}'
end

local partial_eval = judge.vlm({ top_k = 1, api_key = "sk-test" })
local partial_result = partial_eval({
  { suffix = "d055", exists = true, output_path = mock_img1 },
  { suffix = "d060", exists = true, output_path = mock_img2 },
}, {})

T.eq("partial: survivors[1]", partial_result.survivors[1], "d060")
T.ok("partial: pruned has d055", partial_result.pruned ~= nil)
T.eq("partial: pruned[1]", partial_result.pruned[1], "d055")
T.eq("partial: no scores", partial_result.scores, nil)

-- ============================================================
-- vlm() errors when no API key
-- ============================================================

judge.call_vlm = orig_call_vlm  -- restore

-- Unset environment for this test
local saved_env = os.getenv("ANTHROPIC_API_KEY")
local no_key_eval = judge.vlm({ top_k = 1 })  -- no api_key, no env
-- Only errors when images exist (past the gate)
if not saved_env then
  T.err("vlm: no api key error", function()
    no_key_eval({
      { suffix = "d055", exists = true, output_path = mock_img1 },
    }, {})
  end)
else
  -- If env is set, we can't test this cleanly — skip
  T.ok("vlm: api key from env (skip no-key test)", true)
end

-- ============================================================
-- judge.external() factory
-- ============================================================

-- Validation: pass option required
T.err("external: pass required", function() judge.external({}) end)
T.err("external: pass required (nil)", function() judge.external({ pass = nil }) end)
T.err("external: pass required (empty)", function() judge.external({ pass = "" }) end)

-- Returns function
local ext_fn = judge.external({ pass = "p2", top_k = 2 })
T.eq("external: returns function", type(ext_fn), "function")

-- Without VDSL_JUDGE_RESULT → nil (pending)
-- Note: os.setenv is not standard Lua. We test by ensuring env is not set.
-- The test runner should not have VDSL_JUDGE_RESULT set.
if not os.getenv("VDSL_JUDGE_RESULT") then
  local ext_result = ext_fn({
    { suffix = "d055" }, { suffix = "d060" }, { suffix = "d065" },
  }, {})
  T.eq("external: nil when no env", ext_result, nil)
else
  T.ok("external: env set, skip pending test", true)
end

-- ============================================================
-- judge.external() with mock environment (via _extract_json reuse)
-- ============================================================

-- Since we can't set env vars in standard Lua, we test the internal
-- logic by temporarily overriding os.getenv.
local orig_getenv = os.getenv

-- Test: valid result for matching pass
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then
    return '{"p2":{"survivors":["d060","d065"],"scores":{"d055":3.0,"d060":9.0,"d065":7.5,"d070":2.0}}}'
  end
  return orig_getenv(key)
end

local ext_eval = judge.external({ pass = "p2", top_k = 2 })
local ext_candidates = {
  { suffix = "d055" }, { suffix = "d060" },
  { suffix = "d065" }, { suffix = "d070" },
}
local ext_res = ext_eval(ext_candidates, {})

T.ok("external: result not nil", ext_res ~= nil)
T.eq("external: survivors count", #ext_res.survivors, 2)
T.eq("external: survivors[1]", ext_res.survivors[1], "d060")
T.eq("external: survivors[2]", ext_res.survivors[2], "d065")
T.ok("external: pruned exists", ext_res.pruned ~= nil)
T.eq("external: pruned count", #ext_res.pruned, 2)
T.eq("external: score d060", ext_res.scores.d060, 9.0)
T.eq("external: score d065", ext_res.scores.d065, 7.5)

-- Test: wrong pass name → nil
local ext_wrong = judge.external({ pass = "p3", top_k = 2 })
T.eq("external: wrong pass → nil", ext_wrong(ext_candidates, {}), nil)

-- Test: top_k caps survivors
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then
    return '{"p2":{"survivors":["d055","d060","d065"]}}'
  end
  return orig_getenv(key)
end

local ext_capped = judge.external({ pass = "p2", top_k = 1 })
local capped_res = ext_capped(ext_candidates, {})
T.eq("external: top_k caps", #capped_res.survivors, 1)
T.eq("external: capped survivor", capped_res.survivors[1], "d055")

-- Test: invalid suffix filtered
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then
    return '{"p2":{"survivors":["d060","INVALID","d065"]}}'
  end
  return orig_getenv(key)
end

local ext_filtered = judge.external({ pass = "p2", top_k = 2 })
local filtered_res = ext_filtered(ext_candidates, {})
T.eq("external: invalid filtered count", #filtered_res.survivors, 2)
T.eq("external: filtered[1]", filtered_res.survivors[1], "d060")
T.eq("external: filtered[2]", filtered_res.survivors[2], "d065")

-- Test: all invalid → nil (pending)
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then
    return '{"p2":{"survivors":["INVALID1","INVALID2"]}}'
  end
  return orig_getenv(key)
end

local ext_all_invalid = judge.external({ pass = "p2", top_k = 2 })
T.eq("external: all invalid → nil", ext_all_invalid(ext_candidates, {}), nil)

-- Test: malformed JSON → nil
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then return "NOT_JSON" end
  return orig_getenv(key)
end

local ext_bad_json = judge.external({ pass = "p2" })
T.eq("external: bad JSON → nil", ext_bad_json(ext_candidates, {}), nil)

-- Test: empty string → nil
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then return "" end
  return orig_getenv(key)
end

local ext_empty = judge.external({ pass = "p2" })
T.eq("external: empty env → nil", ext_empty(ext_candidates, {}), nil)

-- Test: no scores in result
os.getenv = function(key)
  if key == "VDSL_JUDGE_RESULT" then
    return '{"p2":{"survivors":["d060"]}}'
  end
  return orig_getenv(key)
end

local ext_no_scores = judge.external({ pass = "p2", top_k = 1 })
local no_scores_res = ext_no_scores(ext_candidates, {})
T.eq("external: no scores → nil", no_scores_res.scores, nil)
T.eq("external: no scores survivor", no_scores_res.survivors[1], "d060")

-- Restore os.getenv
os.getenv = orig_getenv

-- ============================================================
-- Cleanup
-- ============================================================

judge.call_vlm = orig_call_vlm
os.remove(mock_img1)
os.remove(mock_img2)
os.remove(mock_img3)

T.summary()
