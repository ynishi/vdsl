--- Judge: VLM-based image evaluation for Pipeline judge gates.
--
-- Returns evaluator functions compatible with pipe:judge(eval_fn).
-- The evaluator reads candidate images, sends them to a VLM API
-- (Claude Vision), and returns a ranked { survivors, pruned, scores }.
--
-- Architecture:
--   build_content()  → image base64 + labels + prompt
--   call_vlm()       → external API call (mock seam)
--   extract_json()   → parse VLM text response
--   normalize_response() → validate & cap to pipeline format
--
-- Usage:
--   local judge = require("vdsl.judge")
--
--   pipe:judge(judge.vlm({
--     top_k    = 2,
--     criteria = { "costume reflected accurately", "face not distorted" },
--     prune    = { "B01", "B04" },
--   }))
--
--   -- Mock for testing:
--   judge.call_vlm = function(content, model, api_key)
--     return '{"survivors":["d060"]}'
--   end

local transport = require("vdsl.runtime.transport")
local json      = require("vdsl.util.json")
local fs        = require("vdsl.runtime.fs")

local M = {}

-- ============================================================
-- Base64 encoding (pure Lua, no system command dependency)
-- ============================================================

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- Read a file and return base64-encoded string.
-- @param filepath string path to image file
-- @return string base64 data (no whitespace)
local function read_base64(filepath)
  if type(filepath) ~= "string" or filepath == "" then
    error("judge: filepath must be a non-empty string", 2)
  end
  local bytes = fs.read_binary(filepath)
  if not bytes or #bytes == 0 then
    error("judge: empty image file: " .. filepath, 2)
  end
  local out = {}
  for i = 1, #bytes, 3 do
    local b1 = bytes:byte(i)
    local b2 = bytes:byte(i + 1) or 0
    local b3 = bytes:byte(i + 2) or 0
    local n = b1 * 65536 + b2 * 256 + b3
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64_CHARS:sub(c1 + 1, c1 + 1)
    out[#out + 1] = B64_CHARS:sub(c2 + 1, c2 + 1)
    local remaining = #bytes - i + 1
    out[#out + 1] = remaining >= 2 and B64_CHARS:sub(c3 + 1, c3 + 1) or "="
    out[#out + 1] = remaining >= 3 and B64_CHARS:sub(c4 + 1, c4 + 1) or "="
  end
  return table.concat(out)
end

M._read_base64 = read_base64

-- ============================================================
-- Breakdown catalog (from picker-design.md §3)
-- ============================================================

local BREAKDOWNS = {
  B01 = { severity = "critical", desc = "face distortion / asymmetry" },
  B02 = { severity = "critical", desc = "wrong finger count (extra/missing)" },
  B03 = { severity = "critical", desc = "proportion collapse in lying poses" },
  B04 = { severity = "critical", desc = "iris/pupil deformation" },
  B05 = { severity = "major",    desc = "plastic skin (body_oil overdose)" },
  B06 = { severity = "major",    desc = "ADetailer over-processing (shine/color drift)" },
  B07 = { severity = "major",    desc = "uncanny valley (denoise 0.45-0.55)" },
  B08 = { severity = "major",    desc = "cloth floating (matte material lighting mismatch)" },
  B09 = { severity = "minor",    desc = "butterfly lighting leaks butterfly pattern onto clothes" },
  B10 = { severity = "minor",    desc = "neon lighting leaks cyberpunk motifs" },
  B11 = { severity = "minor",    desc = "multi-LoRA unintended feature bleed" },
  B12 = { severity = "minor",    desc = "FaceDetailer person pass over-smoothing" },
  B13 = { severity = "minor",    desc = "frontal composition fails to convey subtle emotion" },
  B14 = { severity = "info",     desc = "petite tag non-responsive" },
  B15 = { severity = "info",     desc = "silky hair non-responsive on curly long hair" },
  B16 = { severity = "info",     desc = "hip_thrust pose ambiguous" },
}

M.breakdowns = BREAKDOWNS

-- ============================================================
-- Prompt building
-- ============================================================

--- Build evaluation prompt for VLM.
-- @param candidates table cand_info from pipeline
-- @param opts table { criteria, prune, top_k }
-- @return string prompt text
local function build_prompt(candidates, opts)
  local parts = {}

  parts[#parts + 1] = string.format(
    "Compare the following %d AI-generated images.\n" ..
    "All are sweep variations from the same prompt.\n",
    #candidates
  )

  -- Candidate labels
  parts[#parts + 1] = "Candidates:"
  for _, c in ipairs(candidates) do
    local info = c.suffix
    if c.sweep then
      local sweep_parts = {}
      for k, v in pairs(c.sweep) do
        sweep_parts[#sweep_parts + 1] = k .. "=" .. tostring(v)
      end
      if #sweep_parts > 0 then
        info = info .. " (" .. table.concat(sweep_parts, ", ") .. ")"
      end
    end
    parts[#parts + 1] = "  - " .. info
  end
  parts[#parts + 1] = ""

  -- Prune checks (breakdown catalog)
  if opts.prune and #opts.prune > 0 then
    parts[#parts + 1] = "[Breakdown Detection] Prune immediately if any of the following are found:"
    for _, bid in ipairs(opts.prune) do
      local b = BREAKDOWNS[bid]
      if b then
        parts[#parts + 1] = string.format("  - %s: %s (%s)", bid, b.desc, b.severity)
      end
    end
    parts[#parts + 1] = ""
  end

  -- Criteria
  if opts.criteria and #opts.criteria > 0 then
    parts[#parts + 1] = "[Evaluation Criteria]"
    for i, c in ipairs(opts.criteria) do
      parts[#parts + 1] = string.format("  %d. %s", i, c)
    end
    parts[#parts + 1] = ""
  end

  -- Output format
  parts[#parts + 1] = string.format(
    "[Instructions]\n" ..
    "Select the top %d candidates.\n" ..
    "Respond ONLY with the following JSON format (no explanation):\n" ..
    "```json\n" ..
    "{\n" ..
    '  "survivors": ["suffix1", "suffix2"],\n' ..
    '  "pruned": ["suffix3"],\n' ..
    '  "scores": {"suffix1": 8.5, "suffix2": 7.0, "suffix3": 2.0},\n' ..
    '  "reasons": {"suffix1": "reason", "suffix2": "reason", "suffix3": "breakdown reason"}\n' ..
    "}\n" ..
    "```\n" ..
    "survivors: array of top %d suffixes ranked best-first\n" ..
    "pruned: array of pruned suffixes (breakdown detected or insufficient quality)\n" ..
    "scores: 0-10 score for each suffix\n" ..
    "reasons: brief justification for each suffix",
    opts.top_k, opts.top_k
  )

  return table.concat(parts, "\n")
end

M._build_prompt = build_prompt

-- ============================================================
-- Content building (image base64 + labels + prompt)
-- ============================================================

--- Build Claude Messages API content array from candidates.
-- Interleaves base64 images with text labels, appends evaluation prompt.
-- @param candidates table cand_info from pipeline (must all have exists=true)
-- @param prompt_opts table { criteria, prune, top_k }
-- @return table content array for messages[].content
local function build_content(candidates, prompt_opts)
  local content = {}
  for _, c in ipairs(candidates) do
    local b64 = read_base64(c.output_path)
    content[#content + 1] = {
      type = "image",
      source = {
        type = "base64",
        media_type = "image/png",
        data = b64,
      },
    }
    content[#content + 1] = {
      type = "text",
      text = string.format("Candidate: %s", c.suffix),
    }
  end

  local prompt_text = build_prompt(candidates, prompt_opts)
  content[#content + 1] = { type = "text", text = prompt_text }

  return content
end

M._build_content = build_content

-- ============================================================
-- Response parsing
-- ============================================================

--- Extract JSON from VLM response text (handles markdown code blocks).
-- @param text string raw response text
-- @return table|nil parsed JSON
local function extract_json(text)
  if not text or text == "" then return nil end

  -- Try extracting from ```json ... ``` block
  local json_block = text:match("```json%s*\n?(.-)\n?```")
  if json_block then
    local ok, parsed = pcall(json.decode, json_block)
    if ok then return parsed end
  end

  -- Try extracting from ``` ... ``` block
  json_block = text:match("```%s*\n?(.-)\n?```")
  if json_block then
    local ok, parsed = pcall(json.decode, json_block)
    if ok then return parsed end
  end

  -- Try parsing the entire text as JSON
  -- Find first { and last }
  local start = text:find("{")
  local finish = text:reverse():find("}")
  if start and finish then
    finish = #text - finish + 1
    local ok, parsed = pcall(json.decode, text:sub(start, finish))
    if ok then return parsed end
  end

  return nil
end

M._extract_json = extract_json

--- Validate and normalize VLM response into pipeline-compatible format.
-- @param parsed table parsed JSON response
-- @param candidates table cand_info from pipeline
-- @param top_k number desired survivor count
-- @return table { survivors, pruned, scores }
local function normalize_response(parsed, candidates, top_k)
  if not parsed or type(parsed) ~= "table" then
    return nil
  end
  if not parsed.survivors or type(parsed.survivors) ~= "table" then
    return nil
  end

  -- Build suffix lookup
  local valid_suffixes = {}
  for _, c in ipairs(candidates) do
    valid_suffixes[c.suffix] = true
  end

  -- Validate survivors
  local survivors = {}
  for _, s in ipairs(parsed.survivors) do
    if valid_suffixes[s] then
      survivors[#survivors + 1] = s
    end
  end

  -- Cap at top_k
  while #survivors > top_k do
    table.remove(survivors)
  end

  -- If no valid survivors, fall back to first top_k candidates
  if #survivors == 0 then
    for i = 1, math.min(top_k, #candidates) do
      survivors[#survivors + 1] = candidates[i].suffix
    end
  end

  -- Pruned: everything not in survivors
  local survivor_set = {}
  for _, s in ipairs(survivors) do survivor_set[s] = true end
  local pruned = {}
  for _, c in ipairs(candidates) do
    if not survivor_set[c.suffix] then
      pruned[#pruned + 1] = c.suffix
    end
  end

  -- Scores (optional, pass through if valid)
  local scores = nil
  if parsed.scores and type(parsed.scores) == "table" then
    scores = {}
    for k, v in pairs(parsed.scores) do
      if valid_suffixes[k] and type(v) == "number" then
        scores[k] = v
      end
    end
  end

  return {
    survivors = survivors,
    pruned    = #pruned > 0 and pruned or nil,
    scores    = scores,
  }
end

M._normalize_response = normalize_response

-- ============================================================
-- call_vlm: external API call seam (mockable)
-- ============================================================

--- Default VLM model selection.
local DEFAULT_MODELS = {
  claude = "claude-sonnet-4-5-20250514",
}

--- Call VLM API and return the response text.
-- This is the only function that performs external I/O.
-- Replace M.call_vlm to mock in tests.
--
-- @param content table  Messages API content array (images + text)
-- @param model   string model identifier
-- @param api_key string API key
-- @return string response text from VLM
function M.call_vlm(content, model, api_key)
  local resp = transport.post_json(
    "https://api.anthropic.com/v1/messages",
    {
      model      = model,
      max_tokens = 2048,
      messages   = {
        { role = "user", content = content },
      },
    },
    {
      ["x-api-key"]         = api_key,
      ["anthropic-version"] = "2023-06-01",
      ["content-type"]      = "application/json",
    }
  )

  -- Extract first text block from response
  if resp and resp.content then
    for _, block in ipairs(resp.content) do
      if block.type == "text" then
        return block.text
      end
    end
  end
  return nil
end

-- ============================================================
-- VLM evaluator factory
-- ============================================================

--- Create a VLM-based judge evaluator for pipe:judge().
--
-- @param opts table configuration:
--   api       string  "claude" (default). Future: "gemini"
--   model     string  model name (default: auto-select)
--   criteria  table   evaluation criteria strings
--   prune     table   breakdown IDs to detect (e.g. {"B01", "B04"})
--   top_k     number  survivors to keep (default: 2)
--   api_key   string  API key (default: env ANTHROPIC_API_KEY)
--   verbose   boolean print debug info (default: false)
-- @return function judge evaluator compatible with pipe:judge()
function M.vlm(opts)
  opts = opts or {}
  local api     = opts.api or "claude"
  local model   = opts.model or DEFAULT_MODELS[api]
  local top_k   = opts.top_k or 2
  local verbose = opts.verbose or false

  if api ~= "claude" then
    error("judge.vlm: unsupported api '" .. tostring(api) .. "' (supported: claude)", 2)
  end
  if not model then
    error("judge.vlm: no model specified and no default for api '" .. api .. "'", 2)
  end

  local api_key = opts.api_key or os.getenv("ANTHROPIC_API_KEY")

  return function(candidates, base_var)
    -- Gate: all images must exist before evaluation
    for _, c in ipairs(candidates) do
      if not c.exists then
        if verbose then
          print(string.format("  judge: waiting for %s (not yet generated)", c.suffix))
        end
        return nil  -- unresolved — compile again after execution
      end
    end

    if not api_key then
      error("judge.vlm: ANTHROPIC_API_KEY not set", 2)
    end

    -- 1. Build content (images + labels + prompt)
    local prompt_opts = {
      criteria = opts.criteria,
      prune    = opts.prune,
      top_k    = top_k,
    }
    local content = build_content(candidates, prompt_opts)

    if verbose then
      print(string.format("  judge: sending %d images to %s (%s)",
        #candidates, api, model))
    end

    -- 2. Call VLM (mockable seam)
    local resp_text = M.call_vlm(content, model, api_key)

    if verbose and resp_text then
      print("  judge: VLM response:")
      print("  " .. resp_text:sub(1, 200))
    end

    -- 3. Parse and normalize
    local parsed = extract_json(resp_text)
    local result = normalize_response(parsed, candidates, top_k)

    if not result then
      if verbose then
        print("  judge: failed to parse VLM response, falling back to first " .. top_k)
      end
      local fallback_survivors = {}
      for i = 1, math.min(top_k, #candidates) do
        fallback_survivors[#fallback_survivors + 1] = candidates[i].suffix
      end
      result = { survivors = fallback_survivors }
    end

    if verbose then
      print(string.format("  judge: survivors = {%s}",
        table.concat(result.survivors, ", ")))
      if result.pruned then
        print(string.format("  judge: pruned = {%s}",
          table.concat(result.pruned, ", ")))
      end
    end

    return result
  end
end

-- ============================================================
-- External evaluator factory (MCP-driven judge gate)
-- ============================================================

--- Create an external judge evaluator for pipe:judge().
-- Reads judge results from VDSL_JUDGE_RESULT environment variable,
-- injected by the MCP vdsl_run tool's judge_result parameter.
--
-- When VDSL_JUDGE_RESULT is not set, returns nil (pending) so the
-- pipeline pauses and the MCP layer can download candidate images
-- for Human or Agent evaluation.
--
-- @param opts table configuration:
--   pass    string  pass name to look up in VDSL_JUDGE_RESULT (required)
--   top_k   number  max survivors to keep (default: 2)
--   verbose boolean print debug info (default: false)
-- @return function judge evaluator compatible with pipe:judge()
--
-- Usage:
--   pipe:judge(judge.external({ pass = "p2", top_k = 2 }))
--
--   -- Resume via MCP:
--   -- vdsl_run(script=..., judge_result={"p2": {"survivors": ["d060","d065"]}})
function M.external(opts)
  opts = opts or {}
  local pass_name = opts.pass
  local top_k     = opts.top_k or 2
  local verbose   = opts.verbose or false

  if type(pass_name) ~= "string" or pass_name == "" then
    error("judge.external: 'pass' option is required (pass name string)", 2)
  end

  return function(candidates, base_var)
    local env = os.getenv("VDSL_JUDGE_RESULT")
    if not env or env == "" then
      if verbose then
        print(string.format(
          "  judge.external: VDSL_JUDGE_RESULT not set, pending (pass=%s)", pass_name))
      end
      return nil  -- pending — MCP will execute passes and return candidate images
    end

    -- Parse JSON from environment variable
    local ok, data = pcall(json.decode, env)
    if not ok or type(data) ~= "table" then
      if verbose then
        print("  judge.external: failed to parse VDSL_JUDGE_RESULT, pending")
      end
      return nil
    end

    -- Look up result for this pass
    local result = data[pass_name]
    if not result or type(result) ~= "table" or not result.survivors then
      if verbose then
        print(string.format(
          "  judge.external: no result for pass '%s' in VDSL_JUDGE_RESULT, pending",
          pass_name))
      end
      return nil
    end

    -- Build valid suffix set from candidates
    local valid_suffixes = {}
    for _, c in ipairs(candidates) do
      valid_suffixes[c.suffix] = true
    end

    -- Filter survivors to valid suffixes only
    local survivors = {}
    for _, s in ipairs(result.survivors) do
      if valid_suffixes[s] then
        survivors[#survivors + 1] = s
      end
    end

    -- Cap at top_k
    while #survivors > top_k do
      table.remove(survivors)
    end

    if #survivors == 0 then
      if verbose then
        print(string.format(
          "  judge.external: no valid survivors for pass '%s', pending", pass_name))
      end
      return nil
    end

    -- Compute pruned set
    local survivor_set = {}
    for _, s in ipairs(survivors) do survivor_set[s] = true end
    local pruned = {}
    for _, c in ipairs(candidates) do
      if not survivor_set[c.suffix] then
        pruned[#pruned + 1] = c.suffix
      end
    end

    -- Pass through scores if provided
    local scores = nil
    if result.scores and type(result.scores) == "table" then
      scores = {}
      for k, v in pairs(result.scores) do
        if valid_suffixes[k] and type(v) == "number" then
          scores[k] = v
        end
      end
    end

    if verbose then
      print(string.format("  judge.external: pass=%s survivors={%s}",
        pass_name, table.concat(survivors, ", ")))
    end

    return {
      survivors = survivors,
      pruned    = #pruned > 0 and pruned or nil,
      scores    = scores,
    }
  end
end

return M
