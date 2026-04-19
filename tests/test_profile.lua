--- test_profile.lua — Profile DSL normalize + manifest hash stability
-- Run:
--   lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_profile.lua

local vdsl    = require("vdsl")
local Profile = require("vdsl.runtime.profile")
local json    = require("vdsl.util.json")
local T       = require("harness")

-- ============================================================
-- 1. Minimal profile requires name + comfyui
-- ============================================================
T.err("profile: rejects missing name", function()
  vdsl.profile { comfyui = { ref = "master" } }
end)

T.err("profile: rejects missing comfyui", function()
  vdsl.profile { name = "x" }
end)

-- ============================================================
-- 2. Minimal profile: defaults fill in
-- ============================================================
local p = vdsl.profile {
  name = "min",
  comfyui = { ref = "v0.3.26" },
}
T.eq("profile: name", p.name, "min")
T.eq("profile: version default", p.version, 1)
T.eq("profile: comfyui.repo default", p.comfyui.repo, "comfyanonymous/ComfyUI")
T.eq("profile: comfyui.ref", p.comfyui.ref, "v0.3.26")
T.eq("profile: comfyui.port default", p.comfyui.port, 8188)
T.eq("profile: python.version default", p.python.version, "3.12")
T.eq("profile: schema tag", p.schema, "vdsl.profile/1")

-- ============================================================
-- 3. Kind mapping → subdir
-- ============================================================
local p2 = vdsl.profile {
  name = "kinds",
  comfyui = { ref = "master" },
  models = {
    { kind = "checkpoint",      dst = "a.safetensors", src = "b2://v/checkpoints/a.safetensors" },
    { kind = "lora",            dst = "b.safetensors", src = "b2://v/loras/b.safetensors" },
    { kind = "vae",             dst = "c.safetensors", src = "file:///workspace/staged/c.safetensors" },
    -- Z-Image / Flux layout: diffusion_models/ + text_encoders/
    { kind = "diffusion_model", dst = "z_image_turbo_fp16.safetensors",
      src  = "b2://v/diffusion_models/z_image_turbo_fp16.safetensors" },
    { kind = "text_encoder",    dst = "qwen_3_4b_bf16.safetensors",
      src  = "b2://v/text_encoders/qwen_3_4b_bf16.safetensors" },
  },
}
T.eq("models[1].subdir",           p2.models[1].subdir, "checkpoints")
T.eq("models[2].subdir",           p2.models[2].subdir, "loras")
T.eq("models[3].subdir",           p2.models[3].subdir, "vae")
T.eq("models[4].subdir diffusion", p2.models[4].subdir, "diffusion_models")
T.eq("models[5].subdir text_enc",  p2.models[5].subdir, "text_encoders")

T.err("profile: rejects unknown kind", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    models = { { kind = "nope", dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects unsupported scheme (ftp)", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    models = { { kind = "lora", dst = "x", src = "ftp://a/b" } },
  }
end)

-- HF / Civitai / direct HTTP(S) are out of scope — stage into B2 first.
T.err("profile: rejects hf:// scheme", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    models = { { kind = "lora", dst = "x", src = "hf://a/b/c" } },
  }
end)

T.err("profile: rejects https:// scheme", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    models = { { kind = "lora", dst = "x", src = "https://example.com/x.safetensors" } },
  }
end)

-- Extended kinds (ComfyUI master folder_paths.py coverage)
local p_ext = vdsl.profile {
  name = "ext_kinds",
  comfyui = { ref = "master" },
  models = {
    { kind = "audio_encoder",  dst = "a.safetensors", src = "b2://v/audio_encoders/a.safetensors" },
    { kind = "model_patch",    dst = "b.safetensors", src = "b2://v/model_patches/b.safetensors" },
    { kind = "photomaker",     dst = "c.safetensors", src = "b2://v/photomaker/c.safetensors" },
    { kind = "vae_approx",     dst = "d.safetensors", src = "b2://v/vae_approx/d.safetensors" },
    { kind = "latent_upscale", dst = "e.safetensors", src = "b2://v/latent_upscale_models/e.safetensors" },
    { kind = "classifier",     dst = "f.safetensors", src = "b2://v/classifiers/f.safetensors" },
    { kind = "config",         dst = "g.yaml",        src = "b2://v/configs/g.yaml" },
  },
}
T.eq("ext: audio_encoder",  p_ext.models[1].subdir, "audio_encoders")
T.eq("ext: model_patch",    p_ext.models[2].subdir, "model_patches")
T.eq("ext: photomaker",     p_ext.models[3].subdir, "photomaker")
T.eq("ext: vae_approx",     p_ext.models[4].subdir, "vae_approx")
T.eq("ext: latent_upscale", p_ext.models[5].subdir, "latent_upscale_models")
T.eq("ext: classifier",     p_ext.models[6].subdir, "classifiers")
T.eq("ext: config",         p_ext.models[7].subdir, "configs")

-- Custom-node kinds (Impact Pack detectors, facerestore_cf)
local p_cn = vdsl.profile {
  name = "custom_node_kinds",
  comfyui = { ref = "master" },
  models = {
    { kind = "face_restore",  dst = "gfpgan.pth",      src = "b2://v/facerestore_models/gfpgan.pth" },
    { kind = "detector_bbox", dst = "face_yolov8m.pt", src = "b2://v/ultralytics/bbox/face_yolov8m.pt" },
    { kind = "detector_segm", dst = "person_yolov8m-seg.pt",
      src  = "b2://v/ultralytics/segm/person_yolov8m-seg.pt" },
  },
}
T.eq("cn: face_restore",  p_cn.models[1].subdir, "facerestore_models")
T.eq("cn: detector_bbox", p_cn.models[2].subdir, "ultralytics/bbox")
T.eq("cn: detector_segm", p_cn.models[3].subdir, "ultralytics/segm")

-- subdir escape hatch for custom / unlisted directories
local p_sub = vdsl.profile {
  name = "custom_subdir",
  comfyui = { ref = "master" },
  models = {
    { subdir = "custom_weird_dir", dst = "x.safetensors",
      src    = "b2://v/custom_weird_dir/x.safetensors" },
    { subdir = "nested/deeper",    dst = "y.safetensors",
      src    = "b2://v/nested/y.safetensors" },
  },
}
T.eq("subdir: custom dir preserved", p_sub.models[1].subdir, "custom_weird_dir")
T.eq("subdir: custom kind tag",      p_sub.models[1].kind,   "custom")
T.eq("subdir: nested path allowed",  p_sub.models[2].subdir, "nested/deeper")

T.err("profile: rejects kind+subdir both set", function()
  vdsl.profile {
    name = "bad", comfyui = { ref = "master" },
    models = { { kind = "lora", subdir = "loras", dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects neither kind nor subdir", function()
  vdsl.profile {
    name = "bad", comfyui = { ref = "master" },
    models = { { dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects absolute subdir", function()
  vdsl.profile {
    name = "bad", comfyui = { ref = "master" },
    models = { { subdir = "/abs/path", dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects subdir with ..", function()
  vdsl.profile {
    name = "bad", comfyui = { ref = "master" },
    models = { { subdir = "../escape", dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects empty subdir", function()
  vdsl.profile {
    name = "bad", comfyui = { ref = "master" },
    models = { { subdir = "", dst = "x", src = "b2://a/b" } },
  }
end)

T.err("profile: rejects duplicate model dst", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    models = {
      { kind = "lora", dst = "x.safetensors", src = "b2://a/b" },
      { kind = "lora", dst = "x.safetensors", src = "b2://a/c" },
    },
  }
end)

-- ============================================================
-- 4. Sync route parsing (string shorthand + table form)
-- ============================================================
local p3 = vdsl.profile {
  name = "sync",
  comfyui = { ref = "master" },
  sync = {
    pull = { "b2://v/models/ → /workspace/ComfyUI/models/" },
    push = { { src = "/workspace/ComfyUI/output/", dst = "b2://out/{pod_id}/" } },
  },
}
T.eq("sync.pull.src", p3.sync.pull[1].src, "b2://v/models/")
T.eq("sync.pull.dst", p3.sync.pull[1].dst, "/workspace/ComfyUI/models/")
T.eq("sync.push.src", p3.sync.push[1].src, "/workspace/ComfyUI/output/")

T.err("profile: rejects malformed sync route string", function()
  vdsl.profile {
    name = "bad",
    comfyui = { ref = "master" },
    sync   = { pull = { "just a string with no arrow" } },
  }
end)

-- ============================================================
-- 5. Secret sentinel round-trips through env
-- ============================================================
local p4 = vdsl.profile {
  name = "secrets",
  comfyui = { ref = "master" },
  env = { HF_TOKEN = vdsl.secret("HF_TOKEN"), DEBUG = "1" },
}
T.eq("env.HF_TOKEN preserved as secret", p4.env.HF_TOKEN.__secret, "HF_TOKEN")
T.eq("env.DEBUG literal", p4.env.DEBUG, "1")

-- The rendered manifest must mark secrets explicitly so vdsl_profile_apply
-- can resolve them on the orchestrator side without baking values into the
-- manifest itself.
local mj = p4:manifest_json(false)
T.ok("manifest marks secret via __secret key", mj:find('"__secret":"HF_TOKEN"', 1, true) ~= nil)
T.ok("manifest does NOT include a raw HF_TOKEN value", mj:find("HF_TOKEN_VALUE", 1, true) == nil)

-- ============================================================
-- 6. hash_source is deterministic across runs + key orders
-- ============================================================
local a = vdsl.profile {
  name = "det",
  comfyui = { ref = "master", args = { "--listen", "0.0.0.0" } },
  python  = { deps = { "torch==2.4", "xformers==0.0.27" } },
  models  = {
    { kind = "lora", dst = "x.safetensors", src = "b2://a/b/x.safetensors" },
  },
  env = { B = "2", A = "1" },
}
local b = vdsl.profile {
  -- Same profile, different *spec* authoring order:
  comfyui = { args = { "--listen", "0.0.0.0" }, ref = "master" },
  env = { A = "1", B = "2" },
  models = {
    { src = "b2://a/b/x.safetensors", kind = "lora", dst = "x.safetensors" },
  },
  python = { deps = { "torch==2.4", "xformers==0.0.27" } },
  name = "det",
}
T.eq("hash_source stable across spec key order", a:hash_source(), b:hash_source())

-- ============================================================
-- 7. write_manifest produces parseable JSON
-- ============================================================
local tmp = os.tmpname()
p2:write_manifest(tmp)
local f = io.open(tmp, "r")
local text = f:read("*a"); f:close()
os.remove(tmp)
local ok, decoded = pcall(json.decode, text)
T.ok("manifest file parses as JSON", ok)
T.eq("manifest round-trips name", decoded.name, "kinds")
T.eq("manifest round-trips schema tag", decoded.schema, "vdsl.profile/1")

T.summary()
