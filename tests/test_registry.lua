--- test_registry.lua: Registry, Matcher, Transport tests (no live server)
-- Run: lua -e "package.path='lua/?.lua;lua/?/init.lua;tests/?.lua;'..package.path" tests/test_registry.lua

local vdsl    = require("vdsl")
local json    = require("vdsl.json")
local matcher = require("vdsl.matcher")
local T       = require("harness")

-- ============================================================
-- Mock ComfyUI /object_info data
-- ============================================================
local mock_object_info = {
  CheckpointLoaderSimple = {
    input = {
      required = {
        ckpt_name = {{
          "sd_xl_base_1.0.safetensors",
          "v1-5-pruned-emaonly.safetensors",
          "dreamshaper_8.safetensors",
          "realisticVisionV51_v51VAE.safetensors",
        }},
      },
    },
  },
  VAELoader = {
    input = {
      required = {
        vae_name = {{
          "sdxl_vae.safetensors",
          "vae-ft-mse-840000-ema-pruned.safetensors",
        }},
      },
    },
  },
  LoraLoader = {
    input = {
      required = {
        lora_name = {{
          "add_detail.safetensors",
          "lcm_lora_sdxl.safetensors",
          "sd_xl_offset_example-lora_1.0.safetensors",
        }},
      },
    },
  },
  ControlNetLoader = {
    input = {
      required = {
        control_net_name = {{
          "control_v11f1p_sd15_depth.pth",
          "control_v11p_sd15_canny.pth",
          "control_v11p_sd15_openpose.pth",
        }},
      },
    },
  },
}

-- ============================================================
-- Registry from mock data
-- ============================================================
local server = vdsl.from_object_info(mock_object_info)

T.eq("registry: checkpoints", #server.checkpoints, 4)
T.eq("registry: loras",       #server.loras,       3)
T.eq("registry: vaes",        #server.vaes,        2)
T.eq("registry: controlnets", #server.controlnets, 3)

-- ============================================================
-- Fuzzy match: checkpoints
-- ============================================================
T.eq("match: exact stem",
  server:checkpoint("sd_xl_base_1.0"),
  "sd_xl_base_1.0.safetensors")

T.eq("match: exact full",
  server:checkpoint("sd_xl_base_1.0.safetensors"),
  "sd_xl_base_1.0.safetensors")

T.eq("match: starts with",
  server:checkpoint("dreamshaper"),
  "dreamshaper_8.safetensors")

T.eq("match: contains",
  server:checkpoint("realistic"),
  "realisticVisionV51_v51VAE.safetensors")

T.eq("match: case insensitive",
  server:checkpoint("SDXL_BASE"),
  "sd_xl_base_1.0.safetensors")

-- ============================================================
-- Fuzzy match: LoRAs
-- ============================================================
local lora = server:lora("detail", 0.7)
T.eq("lora: name",   lora.name,   "add_detail.safetensors")
T.eq("lora: weight", lora.weight, 0.7)

local lora2 = server:lora("lcm")
T.eq("lora: lcm",      lora2.name,   "lcm_lora_sdxl.safetensors")
T.eq("lora: default",  lora2.weight, 1.0)

-- ============================================================
-- Fuzzy match: VAE
-- ============================================================
T.eq("vae: sdxl", server:vae("sdxl"), "sdxl_vae.safetensors")
T.eq("vae: mse",  server:vae("mse"),  "vae-ft-mse-840000-ema-pruned.safetensors")

-- ============================================================
-- Fuzzy match: ControlNet
-- ============================================================
T.eq("cn: depth",    server:controlnet("depth"),    "control_v11f1p_sd15_depth.pth")
T.eq("cn: canny",    server:controlnet("canny"),    "control_v11p_sd15_canny.pth")
T.eq("cn: openpose", server:controlnet("openpose"), "control_v11p_sd15_openpose.pth")

-- ============================================================
-- No match -> error
-- ============================================================
T.err("match: no match", function()
  server:checkpoint("nonexistent_model_xyz")
end)

-- ============================================================
-- Integration: registry + entity + render
-- ============================================================
local w = vdsl.world {
  model     = server:checkpoint("sdxl_base"),
  vae       = server:vae("sdxl"),
  clip_skip = 2,
}
T.eq("int: world model", w.model, "sd_xl_base_1.0.safetensors")

local hero = vdsl.cast {
  subject  = vdsl.subject("warrior woman"):with("silver armor"),
  negative = vdsl.trait("blurry, ugly"),
  lora     = { server:lora("detail", 0.6) },
}
T.eq("int: cast lora", hero.lora[1].name, "add_detail.safetensors")

local stage = vdsl.stage {
  controlnet = {
    { type = server:controlnet("depth"), image = "depth.png", strength = 0.8 },
  },
}
T.eq("int: stage cn", stage.controlnet[1].type, "control_v11f1p_sd15_depth.pth")

local result = vdsl.render {
  world = w,
  cast  = { hero },
  stage = stage,
  seed  = 42,
  steps = 30,
}
T.ok("int: json output", #result.json > 100)

T.ok("int: model in json",  result.json:find("sd_xl_base_1.0.safetensors") ~= nil)
T.ok("int: vae in json",    result.json:find("sdxl_vae.safetensors") ~= nil)
T.ok("int: lora in json",   result.json:find("add_detail.safetensors") ~= nil)
T.ok("int: cn in json",     result.json:find("control_v11f1p_sd15_depth.pth") ~= nil)

-- ============================================================
-- JSON roundtrip with registry data
-- ============================================================
local info_json = json.encode(mock_object_info)
local info_parsed = json.decode(info_json)
local server2 = vdsl.from_object_info(info_parsed)
T.eq("json rt: checkpoints", #server2.checkpoints, 4)
T.eq("json rt: match works",
  server2:checkpoint("dreamshaper"),
  "dreamshaper_8.safetensors")

-- ============================================================
-- from_object_info: url and headers propagation
-- ============================================================
local server3 = vdsl.from_object_info(mock_object_info, "http://localhost:8188", {
  Authorization = "Bearer test-token-123",
  ["X-Custom"] = "value",
})
T.eq("from_info: url stored",    server3._url,     "http://localhost:8188")
T.eq("from_info: auth header",   server3._headers.Authorization, "Bearer test-token-123")
T.eq("from_info: custom header", server3._headers["X-Custom"],   "value")
T.eq("from_info: resources ok",  #server3.checkpoints, 4)

-- Without headers (nil): backward-compatible
local server4 = vdsl.from_object_info(mock_object_info, "http://localhost:8188")
T.eq("from_info: nil headers ok", server4._headers, nil)
T.eq("from_info: url ok",         server4._url, "http://localhost:8188")

-- Without url and headers: minimal usage
local server5 = vdsl.from_object_info(mock_object_info)
T.eq("from_info: nil url",     server5._url, nil)
T.eq("from_info: nil headers", server5._headers, nil)

-- ============================================================
-- Custom matcher injection
-- ============================================================
vdsl.set_matcher(function(query, name)
  if name:lower():sub(1, #query) == query:lower() then
    return 100
  end
  return 0
end)

T.eq("custom: prefix match",
  server:checkpoint("sd_xl"),
  "sd_xl_base_1.0.safetensors")

T.err("custom: no prefix", function()
  server:checkpoint("vision")
end)

-- Restore default
vdsl.set_matcher(nil)

T.eq("restored: contains",
  server:checkpoint("realistic"),
  "realisticVisionV51_v51VAE.safetensors")

-- Matcher module API
T.ok("matcher: default is func", type(matcher.get_default()) == "function")

T.summary()
