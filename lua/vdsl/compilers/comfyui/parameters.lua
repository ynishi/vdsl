--- ComfyUI-specific parameter presets.
-- Node class_type mappings, model filenames, and default values
-- that are tied to the ComfyUI node ecosystem.
--
-- These are NOT domain knowledge (that lives in catalogs/).
-- These are target-specific wiring: which ComfyUI node to use,
-- which model file to load, which parameter names the node expects.
--
-- Defaults (widely available community models):
--   upscale_model  = "4x-UltraSharp.pth"        -- 4x upscaler
--   face_model     = "codeformer-v0.1.0.pth"     -- face restore
--   detectors.face   = "bbox/face_yolov8m.pt"    -- face detection (ultralytics)
--   detectors.hand   = "bbox/hand_yolov8s.pt"    -- hand detection
--   detectors.person = "segm/person_yolov8m-seg.pt" -- person segmentation
--   preprocessors.depth.ckpt_name = "depth_anything_vitl14.pth"
--
-- Override via .vdsl/config.lua (or workspaces/config.lua):
--   return {
--     upscale_model = "4x-AnimeSharp.pth",
--     face_model    = "GFPGANv1.4.pth",
--     detectors     = { face = "bbox/face_yolov8s.pt" },
--     preprocessors = { depth = { ckpt_name = "depth_anything_v2_vitl.pth" } },
--   }

local config = require("vdsl.config")

local M = {}

-- ============================================================
-- ControlNet preprocessor node mappings
-- Maps user-facing short names → ComfyUI node types (comfyui_controlnet_aux).
-- ============================================================

local PREPROCESSOR_DEFAULTS = {
  canny    = { node = "CannyEdgePreprocessor",    params = { low_threshold = 100, high_threshold = 200 } },
  depth    = { node = "DepthAnythingPreprocessor", params = { ckpt_name = "depth_anything_vitl14.pth" } },
  lineart  = { node = "LineArtPreprocessor",       params = { coarse = "disable" } },
  scribble = { node = "ScribblePreprocessor",      params = {} },
  openpose = { node = "OpenposePreprocessor",      params = { detect_hand = "enable", detect_body = "enable", detect_face = "enable" } },
  dwpose   = { node = "DWPreprocessor",            params = { detect_hand = "enable", detect_body = "enable", detect_face = "enable" } },
}

-- Apply config overrides for preprocessor params (e.g. ckpt_name)
M.preprocessors = PREPROCESSOR_DEFAULTS
local cfg_pre = config.get("preprocessors")
if type(cfg_pre) == "table" then
  for name, overrides in pairs(cfg_pre) do
    if PREPROCESSOR_DEFAULTS[name] then
      for k, v in pairs(overrides) do
        PREPROCESSOR_DEFAULTS[name].params[k] = v
      end
    end
  end
end

-- ============================================================
-- FaceDetailer detector model mappings
-- Keys are user-facing short names, values are model filenames
-- installed in ComfyUI's ultralytics/ directory.
-- ============================================================

local DETECTOR_DEFAULTS = {
  face   = "bbox/face_yolov8m.pt",
  hand   = "bbox/hand_yolov8s.pt",
  person = "segm/person_yolov8m-seg.pt",
}

M.detectors = DETECTOR_DEFAULTS
local cfg_det = config.get("detectors")
if type(cfg_det) == "table" then
  for name, path in pairs(cfg_det) do
    DETECTOR_DEFAULTS[name] = path
  end
end

-- ============================================================
-- Default model filenames
-- ============================================================

M.upscale_model  = config.get("upscale_model") or "4x-UltraSharp.pth"
M.face_model     = config.get("face_model")    or "codeformer-v0.1.0.pth"

return M
