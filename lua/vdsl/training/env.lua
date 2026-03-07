--- env: Declarative training environment specification.
--
-- Captures known-good package versions, patches, and setup steps
-- so that Pod environment setup is reproducible and 1-command.
--
-- Design: catalog of known pitfalls and tested workarounds.
--   Each training method carries an env_spec of tested combinations.
--   env_spec:setup_script() emits a single bash script that:
--     1. Installs pinned packages (with correct index URLs)
--     2. Removes conflicting packages
--     3. Applies source patches to training repos
--     4. Runs verification imports
--
-- Usage:
--   local env = require("vdsl.training.env")
--
--   local spec = env.new {
--     name = "sliders_rtx4090",
--     pip = {
--       install = {
--         { "diffusers", "0.32.2" },
--         { "transformers", "4.47.1" },
--         { "accelerate" },
--         { "peft" },
--         { "wandb" },
--         { "torchvision", "0.21.0+cu124", index = "https://download.pytorch.org/whl/cu124" },
--       },
--       uninstall = { "xformers", "flash-attn" },
--     },
--     repos = {
--       { url = "https://github.com/rohitgandikota/sliders.git",
--         dir = "/workspace/sliders",
--         patches = { ... } },
--     },
--     verify = { "torch", "diffusers", "transformers", "accelerate" },
--   }
--
--   print(spec:setup_script())   -- bash script
--   print(spec:verify_script())  -- import check script

local M = {}
local EnvSpec = {}
EnvSpec.__index = EnvSpec

--- Create a new EnvSpec.
-- @param opts table environment specification
-- @return EnvSpec
function M.new(opts)
  if type(opts) ~= "table" then
    error("training.env: expected a table", 2)
  end

  local self = setmetatable({}, EnvSpec)
  self._name      = opts.name or "unnamed"
  self._pip       = opts.pip or {}
  self._repos     = opts.repos or {}
  self._verify    = opts.verify or {}
  self._pre_cmds  = opts.pre_cmds or {}
  self._post_cmds = opts.post_cmds or {}
  self._notes     = opts.notes or {}
  return self
end

--- Merge two EnvSpecs (e.g. base + method-specific).
-- @param other EnvSpec
-- @return EnvSpec new merged spec
function EnvSpec:merge(other)
  local merged = M.new {
    name = self._name .. "+" .. other._name,
  }

  -- pip: combine install lists, deduplicate by package name (other wins)
  local install_map = {}
  local install_order = {}
  for _, list in ipairs({ self._pip.install or {}, other._pip.install or {} }) do
    for _, pkg in ipairs(list) do
      local name = pkg[1]
      if not install_map[name] then
        install_order[#install_order + 1] = name
      end
      install_map[name] = pkg
    end
  end
  merged._pip.install = {}
  for _, name in ipairs(install_order) do
    merged._pip.install[#merged._pip.install + 1] = install_map[name]
  end

  -- pip: combine uninstall lists, deduplicate
  local unseen = {}
  merged._pip.uninstall = {}
  for _, list in ipairs({ self._pip.uninstall or {}, other._pip.uninstall or {} }) do
    for _, pkg in ipairs(list) do
      if not unseen[pkg] then
        unseen[pkg] = true
        merged._pip.uninstall[#merged._pip.uninstall + 1] = pkg
      end
    end
  end

  -- repos: concatenate
  merged._repos = {}
  for _, r in ipairs(self._repos) do merged._repos[#merged._repos + 1] = r end
  for _, r in ipairs(other._repos) do merged._repos[#merged._repos + 1] = r end

  -- verify: concatenate, deduplicate
  local vseen = {}
  merged._verify = {}
  for _, list in ipairs({ self._verify, other._verify }) do
    for _, v in ipairs(list) do
      if not vseen[v] then
        vseen[v] = true
        merged._verify[#merged._verify + 1] = v
      end
    end
  end

  -- pre/post cmds: concatenate
  merged._pre_cmds = {}
  for _, c in ipairs(self._pre_cmds) do merged._pre_cmds[#merged._pre_cmds + 1] = c end
  for _, c in ipairs(other._pre_cmds) do merged._pre_cmds[#merged._pre_cmds + 1] = c end
  merged._post_cmds = {}
  for _, c in ipairs(self._post_cmds) do merged._post_cmds[#merged._post_cmds + 1] = c end
  for _, c in ipairs(other._post_cmds) do merged._post_cmds[#merged._post_cmds + 1] = c end

  -- notes: concatenate
  merged._notes = {}
  for _, n in ipairs(self._notes) do merged._notes[#merged._notes + 1] = n end
  for _, n in ipairs(other._notes) do merged._notes[#merged._notes + 1] = n end

  return merged
end

--- Generate setup bash script.
-- @return string bash script content
function EnvSpec:setup_script()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  add("#!/bin/bash")
  add("set -e")
  add(string.format("# VDSL Training Env Setup: %s", self._name))
  add(string.format("# Generated: %s", os.date("%Y-%m-%d %H:%M:%S")))

  -- Notes (as comments)
  if #self._notes > 0 then
    add("#")
    add("# Known issues resolved by this spec:")
    for _, note in ipairs(self._notes) do
      add("#   - " .. note)
    end
  end
  add("")

  -- Pre-commands
  if #self._pre_cmds > 0 then
    add("# === Pre-setup commands ===")
    for _, cmd in ipairs(self._pre_cmds) do
      add(cmd)
    end
    add("")
  end

  -- Uninstall conflicting packages
  local uninstall = self._pip.uninstall or {}
  if #uninstall > 0 then
    add("# === Remove conflicting packages ===")
    add("pip uninstall -y " .. table.concat(uninstall, " ") .. " 2>/dev/null || true")
    add("")
  end

  -- Install packages
  local install = self._pip.install or {}
  if #install > 0 then
    -- Group by index URL
    local default_pkgs = {}
    local indexed = {}  -- { [url] = { pkgs } }

    for _, pkg in ipairs(install) do
      local name = pkg[1]
      local version = pkg[2]
      local index = pkg.index or pkg[3]
      local spec = version and (name .. "==" .. version) or name

      if index then
        indexed[index] = indexed[index] or {}
        indexed[index][#indexed[index] + 1] = spec
      else
        default_pkgs[#default_pkgs + 1] = spec
      end
    end

    add("# === Install packages ===")
    if #default_pkgs > 0 then
      add("pip install " .. table.concat(default_pkgs, " "))
    end
    for idx_url, pkgs in pairs(indexed) do
      add("pip install " .. table.concat(pkgs, " ") .. " --index-url " .. idx_url)
    end
    add("")
  end

  -- Clone repos
  if #self._repos > 0 then
    add("# === Setup training repos ===")
    for _, repo in ipairs(self._repos) do
      local dir = repo.dir or ("/workspace/" .. repo.url:match("([^/]+)%.git$"))
      add(string.format("if [ ! -d '%s' ]; then", dir))
      add(string.format("  git clone %s '%s'", repo.url, dir))
      add("fi")

      -- Apply patches
      if repo.patches then
        for _, patch in ipairs(repo.patches) do
          add(string.format("# Patch: %s", patch.description or patch.file))
          if patch.type == "replace" then
            -- Python-based replacement (handles multiline safely)
            local py_lines = {
              "python3 << 'PATCH_EOF'",
              "with open('" .. dir .. "/" .. patch.file .. "', 'r') as f:",
              "    content = f.read()",
              "content = content.replace(",
              "    '''" .. patch.search .. "''',",
              "    '''" .. patch.replace .. "''')",
              "with open('" .. dir .. "/" .. patch.file .. "', 'w') as f:",
              "    f.write(content)",
              "print('patched: " .. patch.file .. "')",
              "PATCH_EOF",
            }
            for _, pl in ipairs(py_lines) do add(pl) end
          elseif patch.type == "line_replace" then
            -- Simple sed for single-line replacements
            local escaped_search = patch.search:gsub("/", "\\/")
            local escaped_replace = patch.replace:gsub("/", "\\/")
            add(string.format(
              "sed -i 's/%s/%s/' '%s/%s'",
              escaped_search, escaped_replace, dir, patch.file
            ))
          end
        end
      end
      add("")
    end
  end

  -- Post-commands
  if #self._post_cmds > 0 then
    add("# === Post-setup commands ===")
    for _, cmd in ipairs(self._post_cmds) do
      add(cmd)
    end
    add("")
  end

  -- Verify
  if #self._verify > 0 then
    add("# === Verify imports ===")
    add(self:verify_script())
    add("")
  end

  add("echo '=== VDSL env setup complete: " .. self._name .. " ==='")

  return table.concat(lines, "\n")
end

--- Generate Python import verification script.
-- @return string python3 one-liner
function EnvSpec:verify_script()
  if #self._verify == 0 then return "echo 'no verify targets'" end

  local imports = {}
  for _, mod in ipairs(self._verify) do
    imports[#imports + 1] = string.format(
      "import %s; print(f'  %s: {%s.__version__}')",
      mod, mod, mod
    )
  end

  return "python3 -c \"\n" .. table.concat(imports, "\n") .. "\nprint('all imports OK')\n\""
end

--- Get human-readable summary of the spec.
-- @return string
function EnvSpec:summary()
  local parts = {}
  parts[#parts + 1] = string.format("EnvSpec: %s", self._name)

  local install = self._pip.install or {}
  if #install > 0 then
    parts[#parts + 1] = string.format("  pip install: %d packages", #install)
    for _, pkg in ipairs(install) do
      local s = pkg[2] and (pkg[1] .. "==" .. pkg[2]) or pkg[1]
      if pkg.index or pkg[3] then
        s = s .. " (custom index)"
      end
      parts[#parts + 1] = "    " .. s
    end
  end

  local uninstall = self._pip.uninstall or {}
  if #uninstall > 0 then
    parts[#parts + 1] = "  pip uninstall: " .. table.concat(uninstall, ", ")
  end

  if #self._repos > 0 then
    parts[#parts + 1] = string.format("  repos: %d", #self._repos)
    for _, r in ipairs(self._repos) do
      local patches_count = r.patches and #r.patches or 0
      parts[#parts + 1] = string.format("    %s (%d patches)", r.url, patches_count)
    end
  end

  if #self._notes > 0 then
    parts[#parts + 1] = "  notes:"
    for _, n in ipairs(self._notes) do
      parts[#parts + 1] = "    - " .. n
    end
  end

  return table.concat(parts, "\n")
end

-- ============================================================
-- Pre-built env specs (known-good combinations)
-- ============================================================

--- Base SDXL training environment (torch 2.6 + cu124).
M.base_sdxl_cu124 = M.new {
  name = "base_sdxl_cu124",
  pip = {
    install = {
      { "diffusers", "0.32.2" },
      { "transformers", "4.47.1" },
      { "accelerate" },
      { "peft" },
      { "safetensors" },
      { "wandb" },
      { "torchvision", "0.21.0+cu124", index = "https://download.pytorch.org/whl/cu124" },
    },
    uninstall = { "xformers", "flash-attn" },
  },
  verify = { "torch", "diffusers", "transformers", "accelerate", "peft" },
  notes = {
    "xformers 0.0.35 conflicts with torch 2.6 (flash attention schema mismatch)",
    "torchvision must match torch 2.6 cu124 (PyTorch index required)",
    "diffusers 0.32.2 + transformers 4.47.1 is tested compatible pair",
    "diffusers >= 0.36 breaks randn_tensor import path",
  },
}

return M
