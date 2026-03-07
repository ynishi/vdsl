--- sdscripts_base: Shared config builder for kohya sd-scripts family.
--
-- kohya, lycoriss, ti all use sd-scripts and share:
--   - TOML config structure ([general], [model], [dataset], [optimizer], [training])
--   - Default parameter resolution
--   - `accelerate launch` command pattern
--
-- Each method provides only its unique section (network / embedding).

local M = {}

-- ============================================================
-- Default parameter resolution
-- ============================================================

--- Resolve common training parameters from user opts.
-- @param opts table raw user options
-- @return table resolved parameters (all non-nil)
function M.resolve(opts)
  if not opts.checkpoint then
    error("config: 'checkpoint' is required", 3)
  end
  if not opts.data_dir then
    error("config: 'data_dir' is required", 3)
  end

  local rank       = opts.rank or 8
  local alpha      = opts.alpha or math.floor(rank / 2)
  local steps      = opts.steps or 300
  local lr         = opts.lr or 0.0003
  local resolution = opts.resolution or 1024
  local optimizer  = opts.optimizer or "AdamW8bit"
  local scheduler  = opts.scheduler or "cosine"
  local precision  = opts.precision or "fp16"
  local output_dir = opts.output_dir or (opts.data_dir .. "/output")

  local trigger = ""
  if opts.archetype then
    trigger = opts.archetype.trigger or opts.archetype.name or ""
  end
  local output_name = opts.output_name or trigger

  return {
    checkpoint  = opts.checkpoint,
    data_dir    = opts.data_dir,
    rank        = rank,
    alpha       = alpha,
    steps       = steps,
    lr          = lr,
    resolution  = resolution,
    optimizer   = optimizer,
    scheduler   = scheduler,
    precision   = precision,
    output_dir  = output_dir,
    output_name = output_name,
    trigger     = trigger,
  }
end

-- ============================================================
-- TOML section builders
-- ============================================================

--- Build the shared TOML config: header + [general] + [model] + [dataset].
-- @param p table resolved parameters
-- @param header_comment string comment lines (may include \n for multi-line)
-- @return string TOML text (no trailing newline — caller appends middle section)
function M.config_top(p, header_comment)
  return string.format(
[[# %s

[general]
enable_bucket = true
bucket_no_upscale = true

[model]
pretrained_model_name_or_path = "%s"

[dataset]
train_data_dir = "%s"
resolution = "%d,%d"
caption_extension = ".txt"]],
    header_comment,
    p.checkpoint,
    p.data_dir, p.resolution, p.resolution
  )
end

--- Build the shared TOML tail: [optimizer] + [training].
-- @param p table resolved parameters
-- @return string TOML text
function M.config_bottom(p)
  return string.format(
[[[optimizer]
optimizer_type = "%s"
learning_rate = %g
lr_scheduler = "%s"

[training]
output_dir = "%s"
output_name = "%s"
save_model_as = "safetensors"
save_precision = "fp16"
max_train_steps = %d
train_batch_size = 1
mixed_precision = "%s"
gradient_checkpointing = true
cache_latents = true
cache_text_encoder_outputs = true
sdpa = true
max_data_loader_n_workers = 0
seed = 42
]],
    p.optimizer, p.lr, p.scheduler,
    p.output_dir, p.output_name, p.steps, p.precision
  )
end

--- Assemble a full TOML config: top + middle + bottom.
-- @param opts table raw user options
-- @param header_comment string
-- @param middle_fn function(p) -> string  method-specific TOML section
-- @return string complete TOML config
function M.config(opts, header_comment, middle_fn)
  local p = M.resolve(opts)
  local top    = M.config_top(p, header_comment)
  local middle = middle_fn(p)
  local bottom = M.config_bottom(p)
  return top .. "\n\n" .. middle .. "\n\n" .. bottom
end

-- ============================================================
-- Command builder
-- ============================================================

--- Generate an `accelerate launch` command for sd-scripts.
-- @param opts table { config_path, repo_dir?, script? }
-- @return string shell command
function M.command(opts)
  if not opts.config_path then
    error("command: 'config_path' is required", 3)
  end
  local repo   = opts.repo_dir or "/workspace/sd-scripts"
  local script = opts.script or "sdxl_train_network.py"
  return string.format(
    "cd %s && accelerate launch %s --config_file=%s",
    repo, script, opts.config_path
  )
end

return M
