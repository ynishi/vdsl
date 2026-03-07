--- sliders: Concept Sliders (ECCV 2024) training target.
-- Generates YAML config for rohitgandikota/sliders image-pair LoRA training.
--
-- Impl module: HOW to train concept slider LoRAs.
--
-- Includes env_spec: tested package combinations and source patches
-- for reproducible Pod setup (1-command via setup_script).

local env_mod = require("vdsl.training.env")

local M = {}

-- ============================================================
-- Environment specification (known-good for RTX 4090 + torch 2.6)
-- ============================================================

M.env = env_mod.base_sdxl_cu124:merge(env_mod.new {
  name = "sliders",
  repos = {
    {
      url = "https://github.com/rohitgandikota/sliders.git",
      dir = "/workspace/sliders",
      patches = {
        {
          description = "diffusers >= 0.29: randn_tensor moved to torch_utils",
          file = "trainscripts/imagesliders/train_util.py",
          type = "line_replace",
          search = "from diffusers.utils import randn_tensor",
          replace = "try:\\n    from diffusers.utils.torch_utils import randn_tensor\\nexcept ImportError:\\n    from diffusers.utils import randn_tensor",
        },
        {
          description = "diffusers >= 0.32: from_single_file rejects local .safetensors paths",
          file = "trainscripts/imagesliders/model_util.py",
          type = "replace",
          search = [[    pipe = StableDiffusionXLPipeline.from_single_file(
        checkpoint_path,
        torch_dtype=weight_dtype,
        cache_dir=DIFFUSERS_CACHE_DIR,
    )]],
          replace = [[    import os
    extra_kwargs = {}
    if os.path.isfile(checkpoint_path):
        extra_kwargs['local_files_only'] = True
    pipe = StableDiffusionXLPipeline.from_single_file(
        checkpoint_path,
        torch_dtype=weight_dtype,
        cache_dir=DIFFUSERS_CACHE_DIR,
        **extra_kwargs,
    )]],
        },
      },
    },
  },
  post_cmds = {
    "mkdir -p /workspace/sliders/models",
  },
  notes = {
    "python → python3 on RunPod (no python symlink)",
    "--scales='-1,1' needs = syntax to avoid argparse treating -1 as flag",
    "use_xformers: false required when xformers is removed",
    "wandb is imported unconditionally by sliders even with use_wandb: false",
  },
})

-- ============================================================
-- Config generation
-- ============================================================

--- Generate Concept Sliders YAML config for image-pair training.
-- @param opts table {
--   checkpoint    string   pretrained model path on Pod
--   prompts       table    { target, positive, unconditional, neutral, action, guidance_scale }
--   rank?         number   LoRA rank (default 4)
--   alpha?        number   LoRA alpha (default 1.0)
--   iterations?   number   training iterations (default 500)
--   lr?           number   learning rate (default 0.0002)
--   method?       string   training method (default "noxattn")
--   save_path?    string   model save directory (default "/workspace/sliders/models")
--   save_name?    string   output model name
--   save_per?     number   save checkpoint every N steps (default 250)
--   archetype     table    concept archetype (must have kind="concept")
-- }
-- @return string YAML config text
function M.config(opts)
  if not opts.checkpoint then
    error("sliders.config: 'checkpoint' is required", 2)
  end
  if not opts.archetype or opts.archetype.kind ~= "concept" then
    error("sliders.config: concept archetype is required", 2)
  end

  local name       = opts.archetype.name
  local rank       = opts.rank or 4
  local alpha      = opts.alpha or 1.0
  local iterations = opts.iterations or 500
  local lr         = opts.lr or 0.0002
  local method     = opts.method or "noxattn"
  local save_path  = opts.save_path or "/workspace/sliders/models"
  local save_name  = opts.save_name or name
  local save_per   = opts.save_per or 250

  -- Prompts section (for prompts YAML file)
  local prompts = opts.prompts

  -- Main config YAML
  local config = string.format(
[[prompts_file: "trainscripts/imagesliders/data/prompts-%s.yaml"
pretrained_model:
  name_or_path: "%s"
  v2: false
  v_pred: false
network:
  type: "c3lier"
  rank: %d
  alpha: %g
  training_method: "%s"
train:
  precision: "bfloat16"
  noise_scheduler: "ddim"
  iterations: %d
  lr: %g
  optimizer: "AdamW"
  lr_scheduler: "constant"
  max_denoising_steps: 50
save:
  name: "%s"
  path: "%s"
  per_steps: %d
  precision: "bfloat16"
logging:
  use_wandb: false
  verbose: false
other:
  use_xformers: false
]],
    name, opts.checkpoint,
    rank, alpha, method,
    iterations, lr,
    save_name, save_path, save_per
  )

  return config
end

--- Generate prompts YAML for concept sliders.
-- @param opts table {
--   target         string   base concept (e.g. "1girl")
--   positive       string   enhanced concept
--   unconditional  string   opposite concept
--   neutral?       string   neutral prompt (default = target)
--   action?        string   "enhance" or "suppress" (default "enhance")
--   guidance_scale? number  (default 4)
--   resolution?    number   (default 1024)
-- }
-- @return string YAML content
function M.prompts(opts)
  if not opts.target then
    error("sliders.prompts: 'target' is required", 2)
  end
  if not opts.positive then
    error("sliders.prompts: 'positive' is required", 2)
  end
  if not opts.unconditional then
    error("sliders.prompts: 'unconditional' is required", 2)
  end

  return string.format(
[[- target: "%s"
  positive: "%s"
  unconditional: "%s"
  neutral: "%s"
  action: "%s"
  guidance_scale: %g
  resolution: %d
  dynamic_resolution: false
  batch_size: 1
]],
    opts.target,
    opts.positive,
    opts.unconditional,
    opts.neutral or opts.target,
    opts.action or "enhance",
    opts.guidance_scale or 4,
    opts.resolution or 1024
  )
end

--- Generate the training execution command.
-- @param opts table {
--   config_path  string   path to config YAML on Pod
--   name         string   output model name
--   dataset_dir  string   path to dataset (with before/after subdirs)
--   rank?        number   LoRA rank (default 4)
--   alpha?       number   LoRA alpha (default 1.0)
--   repo_dir?    string   sliders repo directory (default /workspace/sliders)
--   folders?     string   folder names (default "before,after")
--   scales?      string   scale values (default "-1,1")
-- }
-- @return string shell command
function M.command(opts)
  if not opts.config_path then
    error("sliders.command: 'config_path' is required", 2)
  end

  local name    = opts.name or "slider"
  local repo    = opts.repo_dir or "/workspace/sliders"
  local rank    = opts.rank or 4
  local alpha   = opts.alpha or 1.0
  local folders = opts.folders or "before,after"
  local scales  = opts.scales or "-1,1"

  -- Use python3 (RunPod has no python symlink)
  local python = "python3"

  local parts = {
    "cd " .. repo,
    string.format(
      "%s trainscripts/imagesliders/train_lora-scale-xl.py"
      .. " --config_file %s"
      .. " --alpha %g --rank %d --name %s",
      python, opts.config_path, alpha, rank, name
    ),
  }

  -- Dataset dir + folders/scales (use = syntax to avoid argparse -1 flag issue)
  if opts.dataset_dir then
    parts[2] = parts[2]
      .. " --folder_main " .. opts.dataset_dir
      .. string.format(' --folders="%s" --scales="%s"', folders, scales)
  end

  return table.concat(parts, " && ")
end

return M
