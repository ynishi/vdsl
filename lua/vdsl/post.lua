--- Post: composable post-processing pipeline.
-- Domain-general image/video operations. Compiler maps to ComfyUI nodes.
-- Chainable with + operator (like Trait).
--
-- Usage:
--   local p = vdsl.post("upscale", { model = "4x-UltraSharp", scale = 2 })
--           + vdsl.post("face", { strength = 0.5 })
--   vdsl.render { ..., post = p }

local Entity = require("vdsl.entity")

local Post = Entity.define("post")

--- Create a single post-processing operation.
-- @param op_type string operation type (e.g. "upscale", "hires", "face")
-- @param params table|nil operation parameters
-- @return Post
function Post.new(op_type, params)
  if type(op_type) ~= "string" or op_type == "" then
    error("Post: operation type is required", 2)
  end
  local self = setmetatable({}, Post)
  self._ops = { { type = op_type, params = params or {} } }
  return self
end

--- Flatten ops into target list.
local function flatten_into(target, post)
  for _, op in ipairs(post._ops) do
    target[#target + 1] = op
  end
end

--- Chain two Post pipelines with + operator.
-- @return Post combined pipeline
function Post.__add(a, b)
  local chain = setmetatable({}, Post)
  chain._ops = {}
  flatten_into(chain._ops, a)
  flatten_into(chain._ops, b)
  return chain
end

--- Append an operation or Post pipeline.
-- @param op_or_post string|Post operation type or Post entity
-- @param params table|nil parameters (when op_or_post is string)
-- @return Post
function Post:then_do(op_or_post, params)
  if Entity.is(op_or_post, "post") then
    return self + op_or_post
  end
  return self + Post.new(op_or_post, params)
end

--- Get the operation list (for compiler).
-- @return table list of { type, params }
function Post:ops()
  return self._ops
end

return Post
