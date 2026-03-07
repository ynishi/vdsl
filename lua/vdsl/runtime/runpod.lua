--- DEPRECATED: RunPod Pod lifecycle management via runpod-cli.
-- This module is deprecated. Use MCP tools (vdsl_pod_*) instead.
-- No VDSL core modules depend on this file as of 2026-03-06.
-- Retained for reference only; will be removed in a future release.
--
-- Original description:
-- Wraps runpod-cli commands for create/delete/start/stop/status/wait.
-- Integrates with Registry for seamless vdsl.connect().
--
-- Usage (existing pod):
--   local runpod = require("vdsl.runpod")
--   local pod = runpod.pod("pod_abc123")
--   pod:start()
--   local reg = pod:connect()   -- waits until proxy ready
--   -- ... use reg:run() ...
--   pod:stop()
--
-- Usage (disposable pod with Network Volume):
--   local pod = runpod.create_pod({
--     name             = "comfyui-vdsl",
--     templateId       = "cw3nka7d08",
--     networkVolumeId  = "gxfrdzimaa",
--     gpuTypeIds       = { "NVIDIA A40" },
--     containerDiskInGb = 30,
--     ports            = { "8188/http", "22/tcp" },
--   }, { token = "mytoken" })
--   local reg = pod:connect()
--   -- ... use reg:run() ...
--   pod:delete()

local json = require("vdsl.util.json")

local M = {}

-- ============================================================
-- ComfyUI on RunPod defaults
-- ============================================================

--- Default spec for ComfyUI pods on RunPod.
-- Override individual fields via opts in comfy_pod().
M.COMFY_DEFAULTS = {
  templateId        = "cw3nka7d08",
  containerDiskInGb = 30,
  ports             = { "8188/http", "22/tcp" },
  name              = "comfyui-vdsl",
}

-- ============================================================
-- Shell helpers
-- ============================================================

local shell_quote = require("vdsl.util.shell").quote

--- Run runpod-cli and return parsed JSON output.
-- @param args string CLI arguments
-- @param api_key string RUNPOD_API_KEY
-- @return table parsed JSON response
local function cli(args, api_key)
  local cmd = string.format(
    "RUNPOD_API_KEY=%s runpod-cli -o json %s 2>&1",
    shell_quote(api_key), args
  )
  local handle = io.popen(cmd)
  if not handle then
    error("runpod: failed to execute runpod-cli", 2)
  end
  local raw = handle:read("*a")
  local ok, status_or_msg, code = handle:close()

  -- Lua 5.1 returns just boolean; 5.2+ returns (bool, "exit", code)
  local exit_code = code or (ok and 0 or 1)

  if exit_code ~= 0 then
    error("runpod-cli failed (exit " .. tostring(exit_code) .. "): " .. raw, 2)
  end

  if raw == "" then return {} end

  local ok2, result = pcall(json.decode, raw)
  if not ok2 then
    error("runpod: failed to parse CLI output: " .. raw, 2)
  end
  return result
end

-- ============================================================
-- Sleep (shared with registry.lua pattern)
-- ============================================================

local function sleep(seconds)
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.sleep then
    socket.sleep(seconds)
    return
  end
  os.execute("sleep " .. string.format("%.1f", seconds))
end

-- ============================================================
-- Pod object
-- ============================================================

local DEFAULT_SSH_KEY = "~/.ssh/id_ed25519_runpod"

local Pod = {}
Pod.__index = Pod

--- Get pod status.
-- @return table full pod info from RunPod API
function Pod:status()
  return cli("pods get-pod " .. shell_quote(self.id), self._api_key)
end

--- Start (or resume) the pod.
-- @return table API response
function Pod:start()
  return cli("pods start-pod " .. shell_quote(self.id), self._api_key)
end

--- Stop the pod.
-- @return table API response
function Pod:stop()
  return cli("pods stop-pod " .. shell_quote(self.id), self._api_key)
end

--- Delete the pod permanently.
-- @return table API response
function Pod:delete()
  return cli("pods delete-pod " .. shell_quote(self.id), self._api_key)
end

-- ============================================================
-- Remote execution (via runpod-cli exec)
-- ============================================================

--- Execute a command on the pod via runpod-cli exec.
-- runpod-cli auto-detects public IP, SSH port, and key.
-- @param cmd string shell command to execute
-- @param opts table|nil { ssh_key, timeout = 30 }
-- @return string command output (stdout + stderr), number exit_code
function Pod:exec(cmd, opts)
  opts = opts or {}
  local ssh_key = opts.ssh_key or self._ssh_key or DEFAULT_SSH_KEY
  local timeout = opts.timeout or 30

  local parts = {
    "RUNPOD_API_KEY=" .. shell_quote(self._api_key),
    "runpod-cli exec",
    "-i " .. shell_quote(ssh_key),
  }
  parts[#parts + 1] = "-t " .. tostring(timeout)
  parts[#parts + 1] = shell_quote(self.id)
  -- Pass as "sh -c 'cmd'" so runpod-cli's shell_join produces
  -- correct quoting on the remote side (3 separate args).
  parts[#parts + 1] = "-- sh -c"
  parts[#parts + 1] = shell_quote(cmd)
  parts[#parts + 1] = "2>&1"

  local exec_cmd = table.concat(parts, " ")

  local handle = io.popen(exec_cmd)
  if not handle then
    error("runpod: failed to execute runpod-cli exec", 2)
  end
  local output = handle:read("*a")
  local ok, _, code = handle:close()

  -- Lua 5.1 returns just boolean; 5.2+ returns (bool, "exit", code)
  local exit_code = code or (ok and 0 or 1)
  return output, exit_code
end

-- ============================================================
-- Background download (via runpod-cli download)
-- ============================================================

--- Queue a background download on the pod.
-- Uses runpod-cli download add (nohup wget, survives SSH disconnect).
-- @param url string URL to download
-- @param dest string|nil destination path on the pod (default: /workspace/<filename>)
-- @param opts table|nil { ssh_key }
-- @return table { id, url, output } or { id, state = "already_running", ... }
function Pod:download_add(url, dest, opts)
  opts = opts or {}
  local parts = { "download add" }
  local ssh_key = opts.ssh_key or self._ssh_key or DEFAULT_SSH_KEY
  parts[#parts + 1] = "-i " .. shell_quote(ssh_key)
  parts[#parts + 1] = shell_quote(self.id)
  parts[#parts + 1] = shell_quote(url)
  if dest then
    parts[#parts + 1] = "-d " .. shell_quote(dest)
  end
  return cli(table.concat(parts, " "), self._api_key)
end

--- Check download progress.
-- @param job_id string download job ID (returned by download_add as .id)
-- @param opts table|nil { ssh_key }
-- @return table { id, state, pid, url, output, exit_code, file_size, log }
function Pod:download_status(job_id, opts)
  opts = opts or {}
  local parts = { "download status" }
  local ssh_key = opts.ssh_key or self._ssh_key or DEFAULT_SSH_KEY
  parts[#parts + 1] = "-i " .. shell_quote(ssh_key)
  parts[#parts + 1] = shell_quote(self.id)
  parts[#parts + 1] = shell_quote(job_id)
  return cli(table.concat(parts, " "), self._api_key)
end

--- List all downloads on the pod.
-- @param opts table|nil { ssh_key }
-- @return table array of download job info
function Pod:download_list(opts)
  opts = opts or {}
  local parts = { "download list" }
  local ssh_key = opts.ssh_key or self._ssh_key or DEFAULT_SSH_KEY
  parts[#parts + 1] = "-i " .. shell_quote(ssh_key)
  parts[#parts + 1] = shell_quote(self.id)
  return cli(table.concat(parts, " "), self._api_key)
end

--- Wait for a download to complete.
-- Polls download_status until state == "done" or timeout.
-- @param job_id string download job ID
-- @param opts table|nil { timeout = 600, interval = 3, ssh_key }
-- @return table final status
function Pod:download_wait(job_id, opts)
  opts = opts or {}
  local timeout  = opts.timeout or 600
  local interval = opts.interval or 3
  local elapsed  = 0

  while elapsed < timeout do
    local status = self:download_status(job_id, { ssh_key = opts.ssh_key })

    if status.state == "done" then
      if status.exit_code ~= "0" then
        error(string.format(
          "runpod: download failed (exit %s): %s",
          status.exit_code, status.log or ""), 2)
      end
      return status
    end

    sleep(interval)
    elapsed = elapsed + interval
  end

  error("runpod: download timeout after " .. timeout .. "s for job " .. job_id, 2)
end

-- ============================================================
-- Model installation
-- ============================================================

-- ComfyUI model directory mapping (relative to models base dir).
-- Base path is auto-detected on first exec via Pod:models_base().
local MODEL_DIRS = {
  checkpoints  = "checkpoints",
  loras        = "loras",
  controlnet   = "controlnet",
  vae          = "vae",
  upscale      = "upscale_models",
  embeddings   = "embeddings",
  clip         = "clip",
  unet         = "unet",
  custom_nodes = "../custom_nodes",
}

--- Detect the ComfyUI models base directory on the pod.
-- Caches the result for subsequent calls.
-- @return string absolute path (e.g. "/workspace/comfyui/models")
function Pod:models_base()
  if self._models_base then return self._models_base end
  -- Try common paths
  local candidates = {
    "/workspace/runpod-slim/ComfyUI/models",
    "/workspace/comfyui/models",
    "/workspace/ComfyUI/models",
    "/opt/ComfyUI/models",
  }
  local check_cmd = "for d in " .. table.concat(candidates, " ")
    .. '; do [ -d "$d" ] && echo "$d" && exit 0; done; echo NOT_FOUND'
  local result = self:exec(check_cmd):match("^%s*(.-)%s*$")
  if result == "NOT_FOUND" then
    error("runpod: ComfyUI models directory not found on pod", 2)
  end
  self._models_base = result
  return result
end

--- Market resolvers: parse source string into download URL and filename.
-- Each resolver returns { url, filename }.
local MARKETS = {}

--- HuggingFace resolver.
-- Formats: "hf:user/repo/file.safetensors", or bare "user/repo/file"
-- @param source string source identifier (without "hf:" prefix)
-- @param opts table|nil { file = specific filename }
-- @return table { url, filename }
MARKETS.hf = function(source, opts)
  opts = opts or {}

  -- Parse: "user/repo/path/to/file.ext" or "user/repo" + opts.file
  local repo, filepath = source:match("^([^/]+/[^/]+)/(.+)$")
  if not repo then
    repo = source
    filepath = opts.file
  end

  if not filepath then
    error("runpod: HuggingFace source requires a file path (e.g. 'user/repo/model.safetensors')", 3)
  end

  return {
    url = string.format("https://huggingface.co/%s/resolve/main/%s", repo, filepath),
    filename = filepath:match("([^/]+)$"),
  }
end

--- Direct URL resolver.
-- @param source string full URL
-- @return table { url, filename }
MARKETS.url = function(source)
  -- Strip query string and fragment, then extract last path component
  local path = source:match("^([^?#]+)") or source
  local filename = path:match("([^/]+)$") or "download"
  return {
    url = source,
    filename = filename,
  }
end

--- Parse a source string into market + identifier.
-- "hf:user/repo" → "hf", "user/repo"
-- "https://..." → "url", "https://..."
-- "user/repo" → "hf", "user/repo" (default)
-- @return string market, string identifier
local function parse_source(source)
  local prefix, rest = source:match("^(%w+):(.+)$")
  if prefix and MARKETS[prefix] then
    return prefix, rest
  end
  if source:match("^https?://") then
    return "url", source
  end
  -- Default: HuggingFace
  return "hf", source
end

--- Install a model to the pod's ComfyUI models directory.
-- Uses runpod-cli download add for reliable background download.
-- @param source string model source (e.g. "hf:user/repo/file", "https://...")
-- @param target string model category ("controlnet", "checkpoints", "loras", etc.)
-- @param opts table|nil { file, ssh_key, timeout = 600, interval = 3 }
-- @return table download status { id, state, file_size, ... }
function Pod:install_model(source, target, opts)
  opts = opts or {}

  local dir_name = MODEL_DIRS[target]
  if not dir_name then
    local valid = {}
    for k in pairs(MODEL_DIRS) do valid[#valid + 1] = k end
    table.sort(valid)
    error("runpod: unknown target '" .. target .. "'. Valid: " .. table.concat(valid, ", "), 2)
  end

  local dest_dir = self:models_base() .. "/" .. dir_name
  local market, identifier = parse_source(source)
  local resolver = MARKETS[market]
  if not resolver then
    error("runpod: unknown market '" .. market .. "'", 2)
  end

  local dl_info = resolver(identifier, opts)
  if opts.filename then dl_info.filename = opts.filename end
  local dest = dest_dir .. "/" .. dl_info.filename

  io.write(string.format("  downloading %s → %s/%s ...\n", source, target, dl_info.filename))

  local resp = self:download_add(dl_info.url, dest, { ssh_key = opts.ssh_key })

  if resp.state == "already_running" then
    io.write(string.format("  already in progress (pid %s), waiting ...\n", resp.pid or "?"))
  end

  local status = self:download_wait(resp.id, {
    timeout  = opts.timeout or 600,
    interval = opts.interval or 3,
    ssh_key  = opts.ssh_key,
  })

  io.write(string.format("  done (%s bytes)\n", status.file_size or "0"))
  return status
end

--- Extract the proxy URL from pod status.
-- RunPod pods expose ComfyUI via https://{pod_id}-{port}.proxy.runpod.net
-- @param info table pod status (from :status())
-- @param port number|nil ComfyUI port (default 8188)
-- @return string|nil proxy URL, nil if pod not running
local function extract_proxy_url(info, port)
  port = port or 8188
  local pod_id = info.id
  if not pod_id then return nil end

  -- Pod must be running
  local status = info.desiredStatus or info.status
  if status ~= "RUNNING" then return nil end

  return string.format("https://%s-%d.proxy.runpod.net", pod_id, port)
end

--- Wait until the pod is running and the proxy URL is reachable.
-- @param opts table|nil { timeout = 300, interval = 5, port = 8188 }
-- @return string proxy URL
function Pod:wait_ready(opts)
  opts = opts or {}
  local timeout  = opts.timeout or 300
  local interval = opts.interval or 5
  local port     = opts.port or 8188

  local elapsed = 0
  while elapsed < timeout do
    local ok, info = pcall(self.status, self)
    if ok and info then
      local url = extract_proxy_url(info, port)
      if url then
        -- Probe the proxy to confirm ComfyUI is responding
        local transport = require("vdsl.runtime.transport")
        local probe_ok = pcall(transport.get, url .. "/system_stats", self._headers)
        if probe_ok then
          return url
        end
      end
    end

    sleep(interval)
    elapsed = elapsed + interval
  end

  error("runpod: pod " .. self.id .. " not ready after " .. timeout .. "s", 2)
end

--- Wait until ready, then return a connected Registry.
-- @param opts table|nil { timeout, interval, port, token }
-- @return Registry connected registry
function Pod:connect(opts)
  opts = opts or {}
  local url = self:wait_ready(opts)

  local Registry = require("vdsl.runtime.registry")
  return Registry.connect(url, {
    token   = opts.token or self._token,
    headers = self._headers,
  })
end

--- Full convenience: start → wait → connect → run → stop.
-- @param render_opts table vdsl render options
-- @param run_opts table|nil { save, save_dir, timeout, interval, auto_stop }
-- @return table run result
function Pod:run(render_opts, run_opts)
  run_opts = run_opts or {}
  local auto_stop   = run_opts.auto_stop ~= false
  local auto_delete = run_opts.auto_delete or false

  self:start()
  local reg = self:connect(run_opts)

  local ok, result = pcall(reg.run, reg, render_opts, run_opts)

  if auto_delete then
    pcall(self.delete, self)
  elseif auto_stop then
    pcall(self.stop, self)
  end

  if not ok then error(result, 2) end
  return result
end

-- ============================================================
-- Module-level functions
-- ============================================================

--- Create a Pod handle.
-- @param id string RunPod pod ID
-- @param opts table|nil { api_key, token, port, ssh_key, headers }
-- @return Pod
function M.pod(id, opts)
  if type(id) ~= "string" or id == "" then
    error("runpod.pod: id is required", 2)
  end
  opts = opts or {}

  local api_key = opts.api_key or os.getenv("RUNPOD_API_KEY")
  if not api_key or api_key == "" then
    error("runpod.pod: RUNPOD_API_KEY is required (env or opts.api_key)", 2)
  end

  local headers = opts.headers
  local token = opts.token
  if token then
    headers = headers or {}
    headers["Authorization"] = "Bearer " .. token
  end

  local self = setmetatable({}, Pod)
  self.id       = id
  self._api_key = api_key
  self._token   = token
  self._headers = headers
  self._port    = opts.port or 8188
  self._ssh_key = opts.ssh_key
  return self
end

--- Create a new pod.
-- @param spec table pod specification { name, templateId, networkVolumeId, gpuTypeIds, containerDiskInGb, ports, ... }
-- @param opts table|nil { api_key, token, port }
-- @return Pod
function M.create_pod(spec, opts)
  opts = opts or {}
  local api_key = opts.api_key or os.getenv("RUNPOD_API_KEY")
  if not api_key or api_key == "" then
    error("runpod.create_pod: RUNPOD_API_KEY is required", 2)
  end
  if not spec or not spec.name then
    error("runpod.create_pod: spec.name is required", 2)
  end

  local body = json.encode(spec)
  local result = cli("pods create-pod -j " .. shell_quote(body), api_key)

  local pod_id = result.id
  if not pod_id then
    error("runpod.create_pod: API did not return pod id: " .. json.encode(result), 2)
  end

  io.write(string.format("  pod created: %s (%s)\n", pod_id, spec.name))

  return M.pod(pod_id, {
    api_key = api_key,
    token   = opts.token,
    port    = opts.port,
  })
end

--- Create a ComfyUI pod with sensible defaults.
-- Applies COMFY_DEFAULTS, then overlays user opts.
-- @param opts table|nil { name, gpu, volume, template, disk, ports }
-- @param api_opts table|nil { api_key, token, port }
-- @return Pod
function M.comfy_pod(opts, api_opts)
  opts = opts or {}
  api_opts = api_opts or {}

  local defaults = M.COMFY_DEFAULTS
  local spec = {
    name              = opts.name or defaults.name,
    templateId        = opts.template or defaults.templateId,
    containerDiskInGb = opts.disk or defaults.containerDiskInGb,
    ports             = opts.ports or defaults.ports,
  }

  if opts.gpu then
    spec.gpuTypeIds = type(opts.gpu) == "table" and opts.gpu or { opts.gpu }
  end

  if opts.volume then
    spec.networkVolumeId = opts.volume
  end

  if opts.datacenter then
    spec.dataCenterIds = type(opts.datacenter) == "table" and opts.datacenter or { opts.datacenter }
  end

  return M.create_pod(spec, {
    api_key = api_opts.api_key or opts.api_key,
    token   = api_opts.token or opts.token,
    port    = api_opts.port or opts.port,
  })
end

--- List all pods.
-- @param opts table|nil { api_key }
-- @return table array of pod info
function M.pods(opts)
  opts = opts or {}
  local api_key = opts.api_key or os.getenv("RUNPOD_API_KEY")
  if not api_key or api_key == "" then
    error("runpod.pods: RUNPOD_API_KEY is required", 2)
  end
  return cli("pods list-pods", api_key)
end

--- Find an existing pod by name.
-- Searches pods list for an exact name match.
-- @param name string pod name to search for (e.g. "comfyui-vdsl")
-- @param opts table|nil { api_key, token, port, ssh_key }
-- @return Pod|nil Pod handle if found, nil otherwise
function M.find_pod(name, opts)
  opts = opts or {}
  local api_key = opts.api_key or os.getenv("RUNPOD_API_KEY")
  if not api_key or api_key == "" then
    error("runpod.find_pod: RUNPOD_API_KEY is required", 2)
  end

  local pods = cli("pods list-pods", api_key)
  for _, info in ipairs(pods) do
    if info.name == name then
      return M.pod(info.id, {
        api_key = api_key,
        token   = opts.token,
        port    = opts.port,
        ssh_key = opts.ssh_key,
      })
    end
  end

  return nil
end

--- List network volumes.
-- @param opts table|nil { api_key }
-- @return table array of volume info
function M.volumes(opts)
  opts = opts or {}
  local api_key = opts.api_key or os.getenv("RUNPOD_API_KEY")
  if not api_key or api_key == "" then
    error("runpod.volumes: RUNPOD_API_KEY is required", 2)
  end
  return cli("network-volumes list-network-volumes", api_key)
end

return M
