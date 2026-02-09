--- Graph: ComfyUI node graph builder.
-- Manages node allocation, wiring, and serialization to prompt format.

local M = {}
M.__index = M

--- Create a new empty graph.
-- @return Graph
function M.new()
  local self = setmetatable({}, M)
  self._nodes = {}
  self._next_id = 1
  return self
end

--- Add a node to the graph.
-- @param class_type string ComfyUI node class name
-- @param inputs table|nil input connections and values
-- @return function(slot) returns an output reference {node_id, slot}
function M:add(class_type, inputs)
  local id = tostring(self._next_id)
  self._next_id = self._next_id + 1
  self._nodes[id] = {
    class_type = class_type,
    inputs = inputs or {},
  }
  return function(slot)
    return { id, slot or 0 }
  end
end

--- Convert the graph to ComfyUI prompt table.
-- @return table prompt in ComfyUI API format
function M:to_prompt()
  local prompt = {}
  for id, node in pairs(self._nodes) do
    prompt[id] = {
      class_type = node.class_type,
      inputs = {},
    }
    for k, v in pairs(node.inputs) do
      prompt[id].inputs[k] = v
    end
  end
  return prompt
end

--- Get the number of nodes in the graph.
-- @return integer
function M:size()
  local count = 0
  for _ in pairs(self._nodes) do count = count + 1 end
  return count
end

return M
