-- examples/12_vllm_profile.lua
-- vLLM profile example: Qwen3.6-27B-AWQ-INT4 on RunPod (4090 reference).
--
-- This is a *reference* Profile, kept self-contained for readability.
-- For production / parameterized use (GPU class, model_len, port,
-- model_repo override), use a Profile factory under projects/ instead
-- of editing this file.
--
-- Pipeline:
--   - llm_models[] pulls weights from HuggingFace (Phase 7b)
--   - services[] launches the vllm daemon and waits on ready_check
--     (Phase 11). No free-form cmd string; `kind = "vllm"` selects
--     the typed platform schema.
--
-- Cold construction: ~10 min on RunPod 4090 ephemeral
--   (HF pull ~1 min + vllm install ~5 min + cold start ~3 min).
-- Reference: workspace/qwen3.6-vllm-runpod-setup.md

local vdsl = require("vdsl")

local profile = vdsl.profile {
  name = "qwen3.6-vllm",

  python = {
    deps = { "vllm==0.18.1", "huggingface_hub" },
    -- vllm 0.18.1 requires torch 2.10 / flashinfer; the runpod/pytorch
    -- base image ships torch 2.4. Without --force-reinstall, pip's
    -- resolver keeps the existing wheel and the import path breaks.
    force_reinstall = true,
  },

  system = {
    apt = { "curl", "iproute2" },
  },

  env = {
    FLASHINFER_DISABLE_VERSION_CHECK = "1",
  },

  -- Raw LLM weight staging (non-ComfyUI). hf:// scheme only.
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
        -- 4090 22.5 GiB usable. max_model_len 16384 OOMs because vllm
        -- 0.18.1's Qwen3-Next Triton/FLA GDN prefill workspace
        -- pushes KV cache memory negative. 8192 + fp8 KV fits.
        -- For A40 (48 GiB) bump to 16384 with utilization 0.92.
        "--max-model-len 8192",
        "--gpu-memory-utilization 0.97",
        "--kv-cache-dtype fp8",
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
