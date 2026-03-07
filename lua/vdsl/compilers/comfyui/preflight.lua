--- ComfyUI Preflight: extract model references, check availability.
-- Compiler-integrated preflight — extract, merge, check, format.

local M = {}

-- ============================================================
-- Node class_type → model input field mapping
-- ============================================================

local MODEL_REFS = {
  CheckpointLoaderSimple      = { field = "ckpt_name",        category = "checkpoints" },
  VAELoader                   = { field = "vae_name",         category = "vaes" },
  LoraLoader                  = { field = "lora_name",        category = "loras" },
  ControlNetLoader            = { field = "control_net_name", category = "controlnets" },
  UpscaleModelLoader          = { field = "model_name",       category = "upscalers" },
  FaceRestoreModelLoader      = { field = "model_name",       category = "upscalers" },
  UltralyticsDetectorProvider = { field = "model_name",       category = "upscalers" },
}

--- All model categories used by this compiler.
M.CATEGORIES = { "checkpoints", "loras", "vaes", "controlnets", "upscalers" }

--- Extract all model references and node types from a compiled ComfyUI prompt table.
-- @param prompt table ComfyUI prompt { node_id = { class_type, inputs } }
-- @return table { checkpoints = {name=true}, ..., node_types = {class_type=true} }
function M.extract(prompt)
  if type(prompt) ~= "table" then
    error("preflight.extract: prompt must be a table, got " .. type(prompt), 2)
  end

  local required = {}
  for _, cat in ipairs(M.CATEGORIES) do
    required[cat] = {}
  end
  required.node_types = {}

  for _, node in pairs(prompt) do
    local ct = node.class_type
    if ct and type(ct) == "string" then
      required.node_types[ct] = true
    end

    local ref = MODEL_REFS[ct]
    if ref then
      local name = node.inputs and node.inputs[ref.field]
      if name and type(name) == "string" and name ~= "" then
        required[ref.category][name] = true
      end
    end
  end

  return required
end

--- Extract and merge model references from multiple compiled prompts.
-- @param prompts table list of compiled prompt tables
-- @return table merged { category = { name = true }, node_types = { class_type = true } }
function M.extract_all(prompts)
  if type(prompts) ~= "table" then
    error("preflight.extract_all: prompts must be a table, got " .. type(prompts), 2)
  end

  local merged = {}
  for _, cat in ipairs(M.CATEGORIES) do
    merged[cat] = {}
  end
  merged.node_types = {}

  for i, prompt in ipairs(prompts) do
    if type(prompt) ~= "table" then
      error(string.format("preflight.extract_all: prompts[%d] must be a table, got %s", i, type(prompt)), 2)
    end
    local req = M.extract(prompt)
    for cat, names in pairs(req) do
      if not merged[cat] then merged[cat] = {} end
      for name in pairs(names) do
        merged[cat][name] = true
      end
    end
  end

  return merged
end

--- Convert required model/node sets to sorted arrays (for JSON serialization).
-- @param required table from extract() or extract_all()
-- @return table { category = { "name1", "name2", ... }, ... }
function M.to_arrays(required)
  local out = {}
  for cat, names in pairs(required) do
    out[cat] = {}
    for name in pairs(names) do
      out[cat][#out[cat] + 1] = name
    end
    table.sort(out[cat])
  end
  return out
end

--- Check extracted model requirements against available models and node types.
-- @param required table from extract()
-- @param available table from server
-- @return table { ok = bool, missing = {...}, missing_nodes = {...}, summary = string }
function M.check(required, available)
  if type(required) ~= "table" then
    error("preflight.check: required must be a table, got " .. type(required), 2)
  end
  if type(available) ~= "table" then
    error("preflight.check: available must be a table, got " .. type(available), 2)
  end

  -- Build lookup sets from available lists
  local avail_sets = {}
  for cat, list in pairs(available) do
    avail_sets[cat] = {}
    if type(list) == "table" then
      for _, name in ipairs(list) do
        avail_sets[cat][name] = true
      end
    end
  end

  -- Check models
  local missing = {}
  for cat, names in pairs(required) do
    if cat ~= "node_types" then
      local avail = avail_sets[cat] or {}
      for name in pairs(names) do
        if not avail[name] then
          missing[#missing + 1] = { name = name, category = cat }
        end
      end
    end
  end

  table.sort(missing, function(a, b)
    if a.category == b.category then return a.name < b.name end
    return a.category < b.category
  end)

  -- Check node types
  local missing_nodes = {}
  if required.node_types and avail_sets.node_types then
    for ct in pairs(required.node_types) do
      if not avail_sets.node_types[ct] then
        missing_nodes[#missing_nodes + 1] = ct
      end
    end
    table.sort(missing_nodes)
  end

  -- Build summary
  local all_ok = #missing == 0 and #missing_nodes == 0
  local lines = {}
  if all_ok then
    lines[1] = "Preflight OK: all models and nodes available."
  else
    if #missing > 0 then
      lines[#lines + 1] = string.format("Preflight FAIL: %d model(s) missing.", #missing)
      for _, m in ipairs(missing) do
        lines[#lines + 1] = string.format("  [%s] %s", m.category, m.name)
      end
    end
    if #missing_nodes > 0 then
      lines[#lines + 1] = string.format("Preflight FAIL: %d custom node(s) missing.", #missing_nodes)
      for _, ct in ipairs(missing_nodes) do
        lines[#lines + 1] = string.format("  [node] %s", ct)
      end
    end
  end

  return {
    ok            = all_ok,
    missing       = missing,
    missing_nodes = missing_nodes,
    summary       = table.concat(lines, "\n"),
  }
end

--- Format required models and node types as a human-readable summary.
-- @param required table from extract() or extract_all()
-- @return string formatted summary
function M.format_required(required)
  local lines = {}
  for _, cat in ipairs(M.CATEGORIES) do
    local names = required[cat]
    if names then
      local sorted = {}
      for name in pairs(names) do sorted[#sorted + 1] = name end
      if #sorted > 0 then
        table.sort(sorted)
        lines[#lines + 1] = string.format("[%s] %s", cat, table.concat(sorted, ", "))
      end
    end
  end
  if required.node_types then
    local sorted = {}
    for ct in pairs(required.node_types) do sorted[#sorted + 1] = ct end
    if #sorted > 0 then
      table.sort(sorted)
      lines[#lines + 1] = string.format("[node_types] %s", table.concat(sorted, ", "))
    end
  end
  if #lines == 0 then return "No model references found." end
  return table.concat(lines, "\n")
end

--- Convenience alias (backward compat for vdsl.preflight.categories()).
function M.categories()
  return M.CATEGORIES
end

return M
