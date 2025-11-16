---@alias loop.TaskType "lua"|"tool"|"app"|"debug"

---@class loop.task.DebugConfig
---@field adapter string
---@field run_in_terminal boolean
---@field stop_on_entry boolean

---@class loop.Task
---@field name string # non-empty task name (supports ${VAR} templates)
---@field type loop.TaskType # task category
---@field command string[]|string # non-empty executable command (supports templates)
---@field cwd string? # optional working directory (supports templates)
---@field env table<string,string>? # optional environment variables
---@field quickfix_matcher string|nil
---@field debug loop.task.DebugConfig|nil
---@field depends_on string[]? # optional list of dependent task names
