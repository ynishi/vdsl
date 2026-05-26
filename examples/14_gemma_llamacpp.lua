-- examples/14_gemma_llamacpp.lua
-- llama.cpp profile example: Gemma 4 E4B-IT GGUF (Q4_K_M) on RTX 4090.
--
-- This is the **operational primary route** for Gemma 4 as of 2026-05.
-- See `examples/13_gemma_vllm.lua` for the vLLM-based sibling — that path
-- is currently frozen because RunPod ephemeral pods carry NVIDIA driver
-- 550-570, while vllm 0.20+ cu130 wheels (the version range that
-- supports Gemma 4) demand driver 575+. llama.cpp + GGUF runs cleanly
-- on driver 550 with the standard `runpod/pytorch:2.4.0-cuda12.4.1`
-- base, so it is the gacha-free way to serve Gemma 4 today.
--
-- Throughput trade-off: roughly 30-60% of vLLM at the same GPU
-- (~170 tok/sec on 4090 / Q4_K_M, batch=1 measured). Acceptable for
-- agent-loop usage where latency, not throughput, is the main axis.
--
-- This file is a *reference* Profile, kept self-contained for readability.
-- For production / parameterized use (variant, GPU class, port, quant
-- override), wrap this file with a factory of your own under
-- `projects/<your-app>/` instead of editing this file directly.
--
-- Why E4B on 4090 as the reference:
--   - E4B Q4_K_M (~5 GB) fits comfortably on a 24GB 4090 with 32K ctx
--     headroom for tool loops.
--   - Multimodal (text + image + audio) is preserved by Unsloth's GGUF
--     conversion of the E* family.
--   - 26B-A4B / 31B GGUFs need >=48GB VRAM (A40+) at Q4_K_M; 4090 cannot
--     host them.
--
-- Why /workspace/ for install paths (model + llama.cpp build artifacts):
--   RunPod pods have a 3-tier storage model (docs.runpod.io/pods/storage/types):
--     * Container disk (/, /root, /tmp, /var ...) — cleared on Pod stop
--     * Volume disk (/workspace)                  — persists across stop/start,
--                                                   deleted only on terminate
--     * Network Volume (mounted at /workspace)    — persists across terminate
--   Installing the GGUF model under `/root/models/` and llama.cpp build
--   output under `/root/llama.cpp/build/` means a Pod stop wipes the
--   build artifacts (multiple small files) and forces a ~10 min cmake
--   rebuild on resume. Placing both under `/workspace/` makes resume
--   skip both the model download and the rebuild, so `vdsl_pod_start`
--   alone (+ a profile_apply re-run that no-ops every hook) is enough
--   to bring the service back.
--
-- Pipeline:
--   - hooks.post_install pulls the single Q4_K_M GGUF file from the
--     Unsloth HF mirror (avoids the 50-70 GB full-repo pull) and builds
--     llama.cpp with CUDA (sm_80/86/89/90 fat-binary for portability).
--     Both steps are idempotent and skipped when the artifacts already
--     exist under /workspace/.
--   - services[] launches `llama-server` with Gemma 4 chat template
--     (Jinja-rendered by `--jinja`) on port 8188.
--
-- Reference: https://github.com/ggerganov/llama.cpp
--            https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF
-- Caveat: Unsloth GGUF guide warns CUDA 13.2 runtime degrades quality.
--   This base is CUDA 12.4 so the caveat does not apply.

local vdsl = require("vdsl")

local repo            = "unsloth/gemma-4-E4B-it-GGUF"
local dst_dir         = "/workspace/models/gemma-4-E4B-gguf"
local gguf_filename   = "gemma-4-E4B-it-Q4_K_M.gguf"
local gguf_path       = dst_dir .. "/" .. gguf_filename
local llama_repo      = "https://github.com/ggerganov/llama.cpp"
local llama_dir       = "/workspace/llama.cpp"
local binary_path     = llama_dir .. "/build/bin/llama-server"

local profile = vdsl.profile {
  name = "gemma-4-E4B-llamacpp-4090",

  system = {
    -- llama.cpp build chain. cmake / build-essential are not in the
    -- default pytorch base. CUDA toolkit (nvcc) ships with the image.
    apt = { "cmake", "build-essential", "git", "curl", "ca-certificates" },
  },

  python = {
    -- HF cli for the single-file GGUF download.
    deps = { "huggingface_hub" },
  },

  env = {
    -- nvcc lives under /usr/local/cuda/bin in the runpod/pytorch image.
    PATH = "/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  },

  -- `llm_models[]` is not used here: the framework's HF download
  -- primitive pulls a whole repo, which would fetch the 50-70 GB
  -- Unsloth GGUF mirror in full. We need just one Q4_K_M quant, so
  -- the file fetch is done in `hooks.post_install` with `hf download`
  -- targeting a single filename.

  hooks = {
    -- (1) Download the single Q4_K_M GGUF (idempotent: skipped if the
    --     file already exists with non-zero size).
    -- (2) Build llama.cpp with CUDA enabled for sm_80/86/89/90 so the
    --     same binary is portable across A100 / A40 / 4090 / H100.
    --     Idempotent: skipped if the server binary is already present
    --     and executable under /workspace/.
    --
    -- HF_TOKEN is not required: the Unsloth GGUF repo is public.
    post_install = string.format([[
set -e
export PATH=/usr/local/cuda/bin:$PATH

mkdir -p %s
if [ ! -s %s ]; then
  python3 -c 'import huggingface_hub' 2>/dev/null || pip install -q huggingface_hub
  hf download "%s" "%s" --local-dir "%s"
fi
ls -la "%s"

if [ ! -x %s ]; then
  if [ ! -d %s ]; then
    git clone --depth 1 %s %s
  fi
  cd %s
  cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="80;86;89;90" -DLLAMA_CURL=ON
  cmake --build build --config Release -j --target llama-server llama-cli
fi
ls -la %s %s

# Write a self-contained startup script to /workspace so that pod
# resume (stop → start) can bring the service back with a single
# `bash /workspace/.vdsl/start_llamacpp.sh` — no profile_apply needed.
# /workspace persists across stop/start; /etc and apt packages do not.
mkdir -p /workspace/.vdsl
cat > /workspace/.vdsl/start_llamacpp.sh <<'STARTUP'
#!/usr/bin/env bash
set -e
BINARY="%s"
MODEL="%s"
PORT=8188
LOGFILE=/workspace/.vdsl/service_llamacpp.log
PIDFILE=/workspace/.vdsl/service_llamacpp.pid

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "llamacpp already running (pid $(cat "$PIDFILE"))"
  exit 0
fi

nohup "$BINARY" -m "$MODEL" --host 0.0.0.0 --port "$PORT" \
  --alias gemma -ngl 999 --jinja -c 32768 -np 1 \
  > "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
echo "llamacpp started (pid $!, log $LOGFILE)"
STARTUP
chmod +x /workspace/.vdsl/start_llamacpp.sh
]],
      dst_dir,
      gguf_path,
      repo,
      gguf_filename,
      dst_dir,
      gguf_path,
      binary_path,
      llama_dir,
      llama_repo,
      llama_dir,
      llama_dir,
      binary_path,
      llama_dir .. "/build/bin/llama-cli",
      binary_path,
      gguf_path
    ),
  },

  services = {
    {
      name   = "llamacpp",
      kind   = "llamacpp",
      model  = gguf_path,
      port   = 8188,  -- vdsl_pod_create default expose port
      binary = binary_path,
      alias  = "gemma",
      -- llama-server flags:
      --   -ngl 999  : offload all transformer layers to GPU
      --   --jinja   : honour Gemma 4 chat_template (reasoning_content
      --               / content split for tool-call routing)
      --   -c 32768  : context (4090 preset; A40+ can carry 65536)
      --   -np 1     : single concurrent slot — agent loops call
      --               sequentially, parallelism is wasted KV cache.
      extra_args = {
        "-ngl 999",
        "--jinja",
        "-c 32768",
        "-np 1",
      },
      ready_check = {
        http        = "http://localhost:8188/v1/models",
        timeout_sec = 120,
      },
    },
  },
}

vdsl.profile_emit(profile)
return profile
