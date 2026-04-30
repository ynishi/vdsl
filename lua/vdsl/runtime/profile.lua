--- Profile: declarative ComfyUI-on-pod configuration.
--
-- A Profile describes everything needed to recreate a ComfyUI environment
-- on a RunPod (or compatible) instance: ComfyUI version, Python deps,
-- custom nodes, models, env, B2 sync routes, hooks.
--
-- A normalized profile serializes to a canonical JSON manifest. The
-- manifest is consumed client-side by the MCP tool vdsl_profile_apply,
-- which expands it into a sequence of existing MCP tool calls
-- (pod_exec_script, sync, sync_route, comfy_api) via vdsl_batch_tools.
-- There is no pod-side convergence script; the pod stays dumb.
--
-- See docs/profile-and-orchestration.md for the full design.
--
-- Source schemes are intentionally limited to b2:// and file://. Stage
-- assets into Backblaze B2 (or onto the pod filesystem) before
-- referencing them; HuggingFace / Civitai / direct HTTP(S) are out of
-- scope.
--
-- ---------------------------------------------------------------
-- SECRETS: user profiles MUST NOT declare them.
-- ---------------------------------------------------------------
-- The whole point of MCP-side profile evaluation is that MCP already
-- knows which credentials each expanded phase needs and injects them
-- into the corresponding batch step's env at apply time:
--   - B2 pull / push steps    → VDSL_B2_KEY_ID, VDSL_B2_KEY
--   - (future auth integrations add their own here)
-- None of these appear in the Profile written by the user. They are
-- added by vdsl-mcp's profile_service during manifest → BatchPlan
-- expansion.
--
-- Consequently `env` in a user Profile is for non-secret runtime
-- configuration only (COMFYUI_PORT-like values). Secret-shaped keys
-- (KEY / SECRET / TOKEN / PASSWORD / PWD / AUTH / CRED / APIKEY,
-- case-insensitive) are rejected at normalization. `vdsl.secret()`
-- has been removed entirely — there is no sentinel path for secrets
-- in user-authored profiles.
--
-- Also reading secrets off the host filesystem (e.g. sourcing a local
-- `.env`) and pasting them inline into a pod command is forbidden —
-- always go through MCP's injection path, never around it.
--
-- ---------------------------------------------------------------
-- NO DSL-BYPASS: pod file ops go through Profile evaluation only.
-- ---------------------------------------------------------------
-- Structurally the same rule as SECRETS above, one layer out:
-- every pod-side file operation that is part of apply / setup /
-- staging must be expressible in this DSL and happen via
-- `expand_phases` in vdsl-mcp/crates/vdsl-mcp/src/application/
-- profile_service.rs. Hand-rolled `mv` / `cp` / `ln` via
-- `vdsl_exec`, direct `rclone` / `wget` / `curl` on the pod, and
-- piggybacking on `vdsl_storage_push` by pre-mv'ing files into
-- its 8 `MODEL_DIRS` categories are all prohibited.
--
-- If you hit an operation this DSL cannot express, the fix is to
-- add a new block here (and a matching expansion in
-- `profile_service.rs`), NOT to reach around the DSL. See
-- docs/profile-and-orchestration.md §2.5 for the rationale and
-- concrete patterns (e.g. staging.push, non-preset subdirs, new
-- source schemes).
--
-- Minimal example:
--   local vdsl = require("vdsl")
--   local p = vdsl.profile {
--     name = "fantasy",
--     comfyui = { ref = "v0.3.26" },
--     models = {
--       { kind = "checkpoint",
--         dst  = "sd_xl_base_1.0.safetensors",
--         src  = "b2://vdsl-assets/checkpoints/sd_xl_base_1.0.safetensors" },
--     },
--   }
--   p:write_manifest("/tmp/manifest.json")
--   print(p:hash_source())   -- canonical JSON used for hashing

local json = require("vdsl.util.json")

local M = {}

-- ============================================================
-- Schema constants
-- ============================================================

--- Kind → ComfyUI models subdirectory.
-- Keep lowercase. Unknown kinds are rejected during normalization.
-- For directories not listed here, models[].subdir = "…" is the escape
-- hatch (see normalize_models). Keep this table in sync with
-- docs/profile-and-orchestration.md §2.2.
local KIND_TO_DIR = {
  checkpoint      = "checkpoints",
  lora            = "loras",
  vae             = "vae",
  controlnet      = "controlnet",
  clip            = "clip",
  clip_vision     = "clip_vision",
  upscale         = "upscale_models",
  embedding       = "embeddings",
  unet            = "unet",
  diffusion_model = "diffusion_models",
  text_encoder    = "text_encoders",
  gligen          = "gligen",
  hypernetwork    = "hypernetworks",
  style           = "style_models",
  diffusers       = "diffusers",
  ipadapter       = "ipadapter",
  -- Extended kinds (ComfyUI master folder_paths.py):
  audio_encoder   = "audio_encoders",
  model_patch     = "model_patches",
  photomaker      = "photomaker",
  vae_approx      = "vae_approx",
  latent_upscale  = "latent_upscale_models",
  classifier      = "classifiers",
  config          = "configs",
  -- Custom-node registered trees (Impact Pack, facerestore_cf):
  face_restore    = "facerestore_models",
  detector_bbox   = "ultralytics/bbox",
  detector_segm   = "ultralytics/segm",
}

--- Allowed src schemes for ComfyUI `models[]` entries.
-- Only B2 (object storage) and file:// (already on the pod) are supported
-- for ComfyUI models. `hf://` belongs in `llm_models[]` (raw LLM weight
-- staging for non-ComfyUI workloads); models[] rejects it explicitly.
local ALLOWED_SCHEMES = {
  ["b2://"]   = true,
  ["file://"] = true,
}

local PROFILE_MT = { __index = {} }

-- ============================================================
-- Helpers
-- ============================================================

local function assert_type(v, t, path)
  if type(v) ~= t then
    error(("profile: %s must be %s, got %s"):format(path, t, type(v)), 3)
  end
end

local function optional_type(v, t, path)
  if v == nil then return end
  assert_type(v, t, path)
end

local function scheme_of(src)
  local s = src:match("^[%w_]+://") or src:match("^[%w_]+:")
  return s
end

local function has_prefix(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, vv in pairs(v) do
    out[k] = deepcopy(vv)
  end
  return out
end

-- ============================================================
-- Normalization
-- ============================================================

local function normalize_comfyui(c)
  -- `comfyui` is OPTIONAL. A profile with no `comfyui` block means
  -- "don't install/restart/health-check ComfyUI on this apply" — useful
  -- for volume evacuation / staging-only / archival profiles where the
  -- pod does not even need a ComfyUI install. Phase 2 / 9 / 10 are
  -- skipped by `profile_service::expand_phases` when this returns nil.
  if c == nil then
    return nil
  end
  assert_type(c, "table", "comfyui")
  local ref = c.ref
  if ref == nil then ref = "master" end
  assert_type(ref, "string", "comfyui.ref")

  local args = c.args or {}
  assert_type(args, "table", "comfyui.args")
  for i, a in ipairs(args) do
    assert_type(a, "string", "comfyui.args[" .. i .. "]")
  end

  local repo = c.repo or "comfyanonymous/ComfyUI"
  assert_type(repo, "string", "comfyui.repo")

  local port = c.port or 8188
  assert_type(port, "number", "comfyui.port")

  return {
    repo = repo,
    ref  = ref,
    port = port,
    args = #args == 0 and json.array({}) or args,
  }
end

local function normalize_python(p)
  if p == nil then
    return { version = "3.12", deps = json.array({}) }
  end
  assert_type(p, "table", "python")
  local version = p.version or "3.12"
  assert_type(version, "string", "python.version")
  local deps = p.deps or {}
  assert_type(deps, "table", "python.deps")
  local out = {}
  for i, d in ipairs(deps) do
    assert_type(d, "string", "python.deps[" .. i .. "]")
    out[i] = d
  end
  local result = {
    version = version,
    deps    = #out == 0 and json.array({}) or out,
  }
  if p.force_reinstall ~= nil then
    assert_type(p.force_reinstall, "boolean", "python.force_reinstall")
    result.force_reinstall = p.force_reinstall
  end
  return result
end

local function normalize_system(s)
  if s == nil then
    return { apt = json.array({}) }
  end
  assert_type(s, "table", "system")
  local apt = s.apt or {}
  assert_type(apt, "table", "system.apt")
  local out = {}
  for i, pkg in ipairs(apt) do
    assert_type(pkg, "string", "system.apt[" .. i .. "]")
    out[i] = pkg
  end
  return {
    apt = #out == 0 and json.array({}) or out,
  }
end

local function normalize_custom_nodes(list)
  if list == nil then return json.array({}) end
  assert_type(list, "table", "custom_nodes")
  local out = {}
  for i, n in ipairs(list) do
    local path = "custom_nodes[" .. i .. "]"
    assert_type(n, "table", path)
    assert_type(n.repo, "string", path .. ".repo")
    optional_type(n.ref, "string", path .. ".ref")
    optional_type(n.pip, "boolean", path .. ".pip")
    optional_type(n.post, "string", path .. ".post")
    optional_type(n.name, "string", path .. ".name")

    local derived_name = n.name
    if not derived_name then
      derived_name = n.repo:match("([^/]+)$") or n.repo
    end

    out[i] = {
      repo = n.repo,
      ref  = n.ref,  -- nil → omitted from JSON, mcp clones default branch
      pip  = n.pip == true,
      post = n.post,
      name = derived_name,
    }
  end
  return #out == 0 and json.array({}) or out
end

local function normalize_models(list)
  if list == nil then return json.array({}) end
  assert_type(list, "table", "models")
  local out = {}
  local seen = {}
  for i, m in ipairs(list) do
    local path = "models[" .. i .. "]"
    assert_type(m, "table", path)

    -- kind (preset) XOR subdir (escape hatch). Exactly one is required.
    -- subdir lets Profile target directories not in KIND_TO_DIR (new ComfyUI
    -- folders, third-party custom-node trees under models/, etc.) without
    -- DSL changes.
    local has_kind   = m.kind   ~= nil
    local has_subdir = m.subdir ~= nil
    if has_kind and has_subdir then
      error(("profile: %s set both kind and subdir; pick one"):format(path), 3)
    elseif not has_kind and not has_subdir then
      error(("profile: %s requires kind or subdir"):format(path), 3)
    end

    local kind, subdir
    if has_kind then
      assert_type(m.kind, "string", path .. ".kind")
      subdir = KIND_TO_DIR[m.kind]
      if not subdir then
        error(("profile: %s.kind unknown: %q (use subdir=\"…\" for custom dirs)")
          :format(path, m.kind), 3)
      end
      kind = m.kind
    else
      assert_type(m.subdir, "string", path .. ".subdir")
      if m.subdir == "" or m.subdir:match("^/") or m.subdir:find("%.%.")
         or m.subdir:find("\\") then
        error(("profile: %s.subdir %q must be a non-empty relative path without '..' or backslashes")
          :format(path, m.subdir), 3)
      end
      subdir = m.subdir
      kind = "custom"
    end

    if m.base_dir ~= nil then
      error(("profile: %s.base_dir is no longer supported on models[]; "
        .. "for non-ComfyUI weight staging use llm_models[] instead")
        :format(path), 3)
    end

    assert_type(m.dst, "string", path .. ".dst")
    assert_type(m.src, "string", path .. ".src")

    local scheme = scheme_of(m.src)
    if scheme == "hf://" then
      error(("profile: %s.src uses hf:// — ComfyUI models[] supports b2:// or file:// only; "
        .. "use llm_models[] for HuggingFace weight pulls")
        :format(path), 3)
    end
    if not scheme or not ALLOWED_SCHEMES[scheme] then
      error(("profile: %s.src has unsupported scheme (%s); allowed: b2:// file://")
        :format(path, tostring(scheme)), 3)
    end

    -- Duplicate detection on (subdir, dst) to catch accidental overwrites.
    local key = subdir .. "/" .. m.dst
    if seen[key] then
      error(("profile: duplicate model destination %s (see %s)"):format(key, seen[key]), 3)
    end
    seen[key] = path

    out[i] = {
      kind   = kind,
      subdir = subdir,
      dst    = m.dst,
      src    = m.src,
    }
  end
  return #out == 0 and json.array({}) or out
end

-- Keys that look secret-shaped. Rejected unconditionally.
-- Profile.env is for non-secret runtime config only; MCP auto-injects
-- real credentials during manifest → BatchPlan expansion.
local SECRET_KEY_SUBSTRINGS = {
  "KEY", "SECRET", "TOKEN", "PASSWORD", "PWD",
  "AUTH", "CRED", "APIKEY",
}

local function looks_secret(key)
  local u = key:upper()
  for _, needle in ipairs(SECRET_KEY_SUBSTRINGS) do
    if u:find(needle, 1, true) then
      return needle
    end
  end
  return nil
end

local function normalize_env(e)
  if e == nil then return {} end
  assert_type(e, "table", "env")
  local out = {}
  for k, v in pairs(e) do
    assert_type(k, "string", "env key")
    local hit = looks_secret(k)
    if hit then
      error(("profile: env[%s] has a secret-shaped key (contains %q); "
        .. "Profile.env is for non-secret runtime config only. "
        .. "Credentials are MCP-owned and auto-injected during profile apply.")
        :format(k, hit), 3)
    end
    if type(v) == "string" then
      out[k] = v
    elseif type(v) == "number" or type(v) == "boolean" then
      out[k] = tostring(v)
    else
      error(("profile: env[%s] must be string|number|boolean, got %s")
        :format(k, type(v)), 3)
    end
  end
  return out
end

local function normalize_sync_routes(routes, path_name)
  if routes == nil then return json.array({}) end
  assert_type(routes, "table", path_name)
  local out = {}
  for i, r in ipairs(routes) do
    local p = path_name .. "[" .. i .. "]"
    if type(r) == "string" then
      -- "src → dst" shorthand. Accept "→" (UTF-8 \xE2\x86\x92), "->", or "=>".
      -- Lua patterns are byte-oriented, so match the arrow bytes literally.
      local separators = { "\xE2\x86\x92", "->", "=>" }
      local src, dst
      for _, sep in ipairs(separators) do
        local a, b = r:match("^%s*(.-)%s*" .. sep:gsub("([^%w])", "%%%1") .. "%s*(.-)%s*$")
        if a and a ~= "" and b and b ~= "" then
          src, dst = a, b
          break
        end
      end
      if not src then
        error(("profile: %s route string must be 'src → dst', got %q"):format(p, r), 3)
      end
      out[i] = { src = src, dst = dst }
    elseif type(r) == "table" then
      assert_type(r.src, "string", p .. ".src")
      assert_type(r.dst, "string", p .. ".dst")
      out[i] = { src = r.src, dst = r.dst }
    else
      error(("profile: %s must be string|table, got %s"):format(p, type(r)), 3)
    end
  end
  return #out == 0 and json.array({}) or out
end

local function normalize_sync(s)
  if s == nil then
    return { pull = json.array({}), push = json.array({}) }
  end
  assert_type(s, "table", "sync")
  return {
    pull = normalize_sync_routes(s.pull, "sync.pull"),
    push = normalize_sync_routes(s.push, "sync.push"),
  }
end

-- Normalize the optional `staging` block. Currently exposes only
-- `staging.push`: eager pod → B2 one-shot upload routes executed
-- during Phase 5 of apply. Distinct from `sync.push` (marker-only,
-- consumed by later generation flows); see
-- docs/profile-and-orchestration.md §2.3 / §2.5.
--
-- Validation:
--   - src must be an absolute pod path ("/workspace/...").
--   - dst must use the b2:// scheme. {pod_id} placeholder allowed
--     (resolved during MCP expansion).
-- Reuse normalize_sync_routes for arrow / table shape, then enforce
-- the scheme constraints here so the error path stays local.
local function validate_staging_push_route(r, p)
  if not r.src:match("^/") then
    error(("profile: %s.src must be an absolute pod path (got %q)"):format(p, r.src), 3)
  end
  if r.src:find("..", 1, true) then
    error(("profile: %s.src must not contain '..' segments (got %q)"):format(p, r.src), 3)
  end
  if not r.dst:match("^b2://") then
    error(("profile: %s.dst must be a b2:// URI (got %q)"):format(p, r.dst), 3)
  end
end

local function normalize_staging(s)
  if s == nil then
    return { push = json.array({}) }
  end
  assert_type(s, "table", "staging")
  local push = normalize_sync_routes(s.push, "staging.push")
  for i, r in ipairs(push) do
    validate_staging_push_route(r, "staging.push[" .. i .. "]")
  end
  return { push = (#push == 0) and json.array({}) or push }
end

local function normalize_hooks(h)
  if h == nil then return {} end
  assert_type(h, "table", "hooks")
  local allowed = {
    pre_install = true, post_install = true,
    pre_start = true,   post_start = true,
  }
  local out = {}
  for k, v in pairs(h) do
    if not allowed[k] then
      error(("profile: hooks.%s is not a known hook (allowed: pre_install, post_install, pre_start, post_start)"):format(k), 3)
    end
    assert_type(v, "string", "hooks." .. k)
    out[k] = v
  end
  return out
end

--- Raw LLM weight staging for non-ComfyUI workloads (vLLM / Ollama / etc).
-- Independent of `models[]` — `models[]` is ComfyUI-only.
-- Currently only `hf://<org>/<repo>` is supported. `dst_dir` must be an
-- absolute pod path; the repo is materialized there via `huggingface-cli
-- download --local-dir`.
local function normalize_llm_models(list)
  if list == nil then return json.array({}) end
  assert_type(list, "table", "llm_models")
  local out = {}
  local seen = {}
  for i, m in ipairs(list) do
    local path = "llm_models[" .. i .. "]"
    assert_type(m, "table", path)
    assert_type(m.src, "string", path .. ".src")
    assert_type(m.dst_dir, "string", path .. ".dst_dir")
    optional_type(m.revision, "string", path .. ".revision")

    local scheme = scheme_of(m.src)
    if scheme ~= "hf://" then
      error(("profile: %s.src must use hf:// scheme (got %s)")
        :format(path, tostring(scheme)), 3)
    end
    if not m.dst_dir:match("^/") or m.dst_dir:find("%.%.") then
      error(("profile: %s.dst_dir %q must be an absolute pod path without '..'")
        :format(path, m.dst_dir), 3)
    end
    if seen[m.dst_dir] then
      error(("profile: duplicate llm_models dst_dir %s (see %s)"):format(m.dst_dir, seen[m.dst_dir]), 3)
    end
    seen[m.dst_dir] = path

    out[i] = {
      src      = m.src,
      dst_dir  = m.dst_dir,
      revision = m.revision,
    }
  end
  return #out == 0 and json.array({}) or out
end

-- Closed set of supported service platforms. Mirrors the Rust
-- `ServicePlatform` enum in vdsl-mcp; new platforms require a code
-- change in both repos (intentional — no free-form cmd escape hatch).
local SERVICE_KIND_NORMALIZERS = {
  vllm = function(s, path)
    assert_type(s.model, "string", path .. ".model")
    assert_type(s.port, "number", path .. ".port")
    optional_type(s.dtype, "string", path .. ".dtype")
    optional_type(s.tensor_parallel_size, "number", path .. ".tensor_parallel_size")
    local extra = s.extra_args or {}
    assert_type(extra, "table", path .. ".extra_args")
    for j, a in ipairs(extra) do
      assert_type(a, "string", path .. ".extra_args[" .. j .. "]")
    end
    return {
      kind                  = "vllm",
      model                 = s.model,
      port                  = s.port,
      dtype                 = s.dtype,
      tensor_parallel_size  = s.tensor_parallel_size,
      extra_args            = #extra == 0 and json.array({}) or extra,
    }
  end,
  ollama = function(s, path)
    assert_type(s.port, "number", path .. ".port")
    local models = s.models or {}
    assert_type(models, "table", path .. ".models")
    for j, mname in ipairs(models) do
      assert_type(mname, "string", path .. ".models[" .. j .. "]")
    end
    return {
      kind   = "ollama",
      port   = s.port,
      models = #models == 0 and json.array({}) or models,
    }
  end,
}

local function normalize_services(list)
  if list == nil then return json.array({}) end
  assert_type(list, "table", "services")
  local out = {}
  local seen_names = {}
  for i, s in ipairs(list) do
    local path = "services[" .. i .. "]"
    assert_type(s, "table", path)
    assert_type(s.name, "string", path .. ".name")
    if s.cmd ~= nil then
      error(("profile: %s.cmd is no longer supported; "
        .. "use kind=\"vllm\"|\"ollama\" with platform-specific fields")
        :format(path), 3)
    end
    if seen_names[s.name] then
      error(("profile: duplicate services[].name %q"):format(s.name), 3)
    end
    seen_names[s.name] = true

    assert_type(s.kind, "string", path .. ".kind")
    local norm = SERVICE_KIND_NORMALIZERS[s.kind]
    if not norm then
      error(("profile: %s.kind %q unsupported; allowed: vllm, ollama")
        :format(path, s.kind), 3)
    end
    local platform = norm(s, path)

    local ready_check = nil
    if s.ready_check then
      assert_type(s.ready_check, "table", path .. ".ready_check")
      assert_type(s.ready_check.http, "string", path .. ".ready_check.http")
      optional_type(s.ready_check.timeout_sec, "number", path .. ".ready_check.timeout_sec")
      ready_check = {
        http        = s.ready_check.http,
        timeout_sec = s.ready_check.timeout_sec,
      }
    end

    -- Flatten platform fields into the service entry so the JSON shape
    -- matches Rust `ServiceConfig { name, #[serde(flatten)] platform, ready_check }`.
    local entry = { name = s.name, ready_check = ready_check }
    for k, v in pairs(platform) do
      entry[k] = v
    end
    out[i] = entry
  end
  return #out == 0 and json.array({}) or out
end

-- ============================================================
-- Public constructor
-- ============================================================

--- Construct a normalized Profile.
-- @param spec table user-facing spec (see module docstring).
-- @return Profile
function M.new(spec)
  assert_type(spec, "table", "spec")
  assert_type(spec.name, "string", "name")
  if spec.name == "" then
    error("profile: name must be non-empty", 2)
  end

  local version = spec.version
  if version == nil then version = 1 end
  assert_type(version, "number", "version")

  local p = {
    schema        = "vdsl.profile/1",
    name          = spec.name,
    version       = version,
    comfyui       = normalize_comfyui(spec.comfyui),
    python        = normalize_python(spec.python),
    system        = normalize_system(spec.system),
    custom_nodes  = normalize_custom_nodes(spec.custom_nodes),
    models        = normalize_models(spec.models),
    llm_models    = normalize_llm_models(spec.llm_models),
    env           = normalize_env(spec.env),
    sync          = normalize_sync(spec.sync),
    staging       = normalize_staging(spec.staging),
    hooks         = normalize_hooks(spec.hooks),
    services      = normalize_services(spec.services),
  }

  return setmetatable(p, PROFILE_MT)
end

-- ============================================================
-- Profile methods
-- ============================================================

--- Canonical manifest JSON (deterministic: sorted keys, stable array order).
-- Used both for persistence and as the input to hash_source().
function PROFILE_MT.__index:manifest_json(pretty)
  return json.encode(self, pretty)
end

--- Canonical string used to compute profile_hash.
-- Identical to manifest_json(false). Exposed as a named method so callers
-- do not depend on a particular serialization style for hashing.
function PROFILE_MT.__index:hash_source()
  return json.encode(self, false)
end

--- Write the pretty-printed manifest to a file.
-- Returns true on success; raises on IO error.
function PROFILE_MT.__index:write_manifest(path)
  assert_type(path, "string", "write_manifest: path")
  local f, err = io.open(path, "w")
  if not f then
    error("profile: cannot open " .. path .. " for write: " .. tostring(err), 2)
  end
  f:write(self:manifest_json(true))
  f:write("\n")
  f:close()
  return true
end

--- Return a shallow table-view of the profile (for inspection/tests).
function PROFILE_MT.__index:to_table()
  return deepcopy(self)
end

-- ============================================================
-- Module exports
-- ============================================================

--- Kind → subdir mapping (read-only view).
function M.kinds()
  local out = {}
  for k, v in pairs(KIND_TO_DIR) do out[k] = v end
  return out
end

return M
