--- repo.lua: CLI for VDSL generation database.
-- Usage: lua -e "package.path='lua/?.lua;lua/?/init.lua;'..package.path" scripts/repo.lua <command> [args...]
--
-- Commands:
--   find <gen_id>                        Find a generation by ID
--   run <run_id>                         List generations in a run
--   workspace <name>                     List runs in a workspace
--   workspaces                           List all workspaces
--   query [--model X] [--script Y]       Filtered search
--         [--workspace W] [--limit N]
--   search <dot.path> <value>            Search recipe JSON
--   stats <model|script|workspace|date>  Aggregate statistics
--   reindex [path]                       Rebuild DB from PNG files

local json = require("vdsl.util.json")
local repo = require("vdsl").repo

local function print_json(data)
  print(json.encode(data, true))
end

local function usage()
  io.stderr:write([[
Usage: repo.lua <command> [args...]

Commands:
  find <gen_id>                       Find generation by ID
  run <run_id>                        List generations in a run
  workspace <name>                    List runs in workspace
  workspaces                          List all workspaces
  query [--model X] [--script Y]      Filtered search
        [--workspace W] [--limit N]
  search <dot.path> <value>           Search recipe JSON
  stats <model|script|workspace|date> Statistics
]])
  os.exit(1)
end

local cmd = arg[1]
if not cmd then usage() end

if cmd == "find" then
  local gen_id = arg[2]
  if not gen_id then
    io.stderr:write("find: gen_id required\n")
    os.exit(1)
  end
  local result = repo:find(gen_id)
  if result then
    print_json(result)
  else
    io.stderr:write("not found: " .. gen_id .. "\n")
    os.exit(1)
  end

elseif cmd == "run" then
  local run_id = arg[2]
  if not run_id then
    io.stderr:write("run: run_id required\n")
    os.exit(1)
  end
  print_json(repo:find_by_run(run_id))

elseif cmd == "workspace" then
  local name = arg[2]
  if not name then
    io.stderr:write("workspace: name required\n")
    os.exit(1)
  end
  local ws = repo:ensure_workspace(name)
  local runs = repo:find_by_workspace(ws.id)
  print_json({ workspace = ws, runs = runs })

elseif cmd == "workspaces" then
  print_json(repo:list_workspaces())

elseif cmd == "query" then
  local filter, opts = {}, {}
  local i = 2
  while i <= #arg do
    if arg[i] == "--model" then
      filter.model = arg[i + 1]; i = i + 2
    elseif arg[i] == "--script" then
      filter.script = arg[i + 1]; i = i + 2
    elseif arg[i] == "--workspace" then
      filter.workspace = arg[i + 1]; i = i + 2
    elseif arg[i] == "--limit" then
      opts.limit = tonumber(arg[i + 1]); i = i + 2
    elseif arg[i] == "--from" then
      filter.date_from = arg[i + 1]; i = i + 2
    elseif arg[i] == "--to" then
      filter.date_to = arg[i + 1]; i = i + 2
    else
      io.stderr:write("unknown option: " .. arg[i] .. "\n")
      os.exit(1)
    end
  end
  print_json(repo:query(filter, opts))

elseif cmd == "search" then
  local dot_path = arg[2]
  local value = arg[3]
  if not dot_path or not value then
    io.stderr:write("search: <dot.path> <value> required\n")
    os.exit(1)
  end
  -- Try numeric conversion
  local num = tonumber(value)
  print_json(repo:search(dot_path, num or value))

elseif cmd == "stats" then
  local group_by = arg[2]
  if not group_by then
    io.stderr:write("stats: group_by required (model|script|workspace|date)\n")
    os.exit(1)
  end
  print_json(repo:stats(group_by))

elseif cmd == "reindex" then
  local path = arg[2] or "output/"
  local verbose = arg[3] == "-v" or arg[3] == "--verbose"
  local result = repo:reindex(path, { verbose = verbose })
  print_json(result)

else
  io.stderr:write("unknown command: " .. cmd .. "\n")
  usage()
end
