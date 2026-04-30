-- examples/12_vllm_profile.lua
-- vLLM profile for Qwen 3.6-27B on RunPod.
--
-- Sets up a vLLM OpenAI-compatible server. Weights are pulled from
-- HuggingFace into /root/models/qwen-awq via llm_models[], and the
-- daemon is launched via services[] using the typed `vllm` platform.

local vdsl = require("vdsl")

local profile = vdsl.profile {
  name = "qwen3.6-vllm",

  -- No comfyui block needed — non-ComfyUI workload.

  python = {
    deps = { "vllm==0.18.1", "huggingface_hub" },
    -- vllm 0.18.1 requires torch 2.10 / flashinfer; the runpod/pytorch
    -- base image ships torch 2.4. Without --force-reinstall, pip's
    -- resolver keeps the existing wheel and the import path breaks.
    -- See workspace/qwen3.6-vllm-runpod-setup.md §Step 3.
    force_reinstall = true,
  },

  system = {
    apt = { "curl", "iproute2" },
  },

  env = {
    FLASHINFER_DISABLE_VERSION_CHECK = "1",
  },

  -- Raw LLM weight staging (non-ComfyUI). hf:// only.
  llm_models = {
    {
      src     = "hf://cyankiwi/Qwen3.6-27B-AWQ-INT4",
      dst_dir = "/root/models/qwen-awq",
    },
  },

  -- Typed daemon launch. `kind` selects the platform; fields are
  -- platform-specific. No free-form cmd string.
  services = {
    {
      name                 = "vllm",
      kind                 = "vllm",
      model                = "/root/models/qwen-awq",
      port                 = 8188,
      dtype                = "auto",
      tensor_parallel_size = 1,
      extra_args = {
        "--max-model-len 16384",
        "--gpu-memory-utilization 0.92",
        "--enforce-eager",
        "--enable-auto-tool-choice",
        "--tool-call-parser qwen3_xml",
        "--reasoning-parser qwen3",
        "--served-model-name qwen",
      },
      ready_check = {
        http        = "http://localhost:8188/v1/models",
        timeout_sec = 600,
      },
    },
  },
}

vdsl.profile_emit(profile)
return profile
