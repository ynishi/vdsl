-- examples/13_gemma_vllm.lua
-- vLLM profile example: Gemma 4 E4B-IT on RunPod (A40 reference).
--
-- This is a *reference* Profile, kept self-contained for readability.
-- For production / parameterized use (variant, GPU class, port,
-- multimodal mode override), wrap this file with a factory of your own
-- under `projects/<your-app>/` instead of editing this file directly.
--
-- Why E4B on A40 as the reference:
--   - 26B-A4B / 31B require 80GB GPUs (A100-80 / H100); A40 cannot host
--     them in BF16. AWQ-INT4 release of Gemma 4 is not yet announced.
--   - E4B is multimodal (text + image + audio) and runs comfortably
--     on a single A40 with full 64K context, making it a practical
--     reference for vision/audio-aware tool loops.
--
-- Pipeline:
--   - llm_models[] pulls weights from HuggingFace (Phase 7b)
--   - services[] launches vllm with Gemma 4 reasoning + tool-call
--     parsers (Phase 11). No free-form cmd string; `kind = "vllm"`
--     selects the typed platform schema.
--
-- Reference: https://recipes.vllm.ai/  Google / Gemma 4 Usage Guide
-- Caveat: Unsloth GGUF guide warns CUDA 13.2 runtime degrades quality.
--   The vllm/vllm-openai cu129 image path is the validated route.

local vdsl = require("vdsl")

local profile = vdsl.profile {
  name = "gemma-4-E4B-vllm",

  python = {
    -- Gemma 4 サポートを含む vllm を install。base image (torch 2.4) との
    -- 依存衝突を避けるため force_reinstall。
    deps            = { "vllm", "huggingface_hub" },
    force_reinstall = true,
  },

  system = {
    apt = { "curl", "iproute2" },
  },

  env = {
    FLASHINFER_DISABLE_VERSION_CHECK = "1",
  },

  llm_models = {
    {
      src     = "hf://google/gemma-4-E4B-it",
      dst_dir = "/root/models/gemma-4-E4B",
    },
  },

  services = {
    {
      name                 = "vllm",
      kind                 = "vllm",
      model                = "/root/models/gemma-4-E4B",
      port                 = 8188,  -- vdsl_pod_create の default expose port
      dtype                = "auto",
      tensor_parallel_size = 1,
      extra_args = {
        "--max-model-len 65536",
        "--gpu-memory-utilization 0.92",
        "--kv-cache-dtype fp8",
        "--async-scheduling",
        -- Gemma 4 専用 parser & chat template (vllm 同梱)
        "--enable-auto-tool-choice",
        "--tool-call-parser gemma4",
        "--reasoning-parser gemma4",
        -- vllm 0.20.1 には `examples/tool_chat_template_gemma4.jinja` が
        -- 同梱されていないので、Google が model dir に同梱している
        -- `chat_template.jinja` を絶対パスで参照する。
        "--chat-template /root/models/gemma-4-E4B/chat_template.jinja",
        -- Thinking mode は client 側で per-request 指定:
        --   extra_body = { chat_template_kwargs = { enable_thinking = true } }
        -- server-side `--default-chat-template-kwargs '{"enable_thinking":true}'`
        -- は extra_args injection-guard が JSON brace を unsafe と判定するため使わない。
        -- `--limit-mm-per-prompt` は意図的に省略。vllm 1.x はこの flag
        -- の値を json.loads で parse する仕様 (例: `{"image":4,"audio":1}`)
        -- に変わったが、vdsl-mcp injection-guard が JSON brace/quote を
        -- 含むトークンを reject するため、Profile DSL 経由では渡せない。
        -- 省略時の default は無制限なので multimodal 動作には支障なし。
        -- 副作用: E*/E4B では audio encoder が常時 load され ~数百 MB
        -- VRAM を消費する。text-only 用途では memory 節約余地あり。
        "--served-model-name gemma",
      },
      ready_check = {
        http        = "http://localhost:8188/v1/models",
        timeout_sec = 900,
      },
    },
  },
}

vdsl.profile_emit(profile)
return profile
