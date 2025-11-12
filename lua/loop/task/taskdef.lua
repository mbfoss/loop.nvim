---@class loop.task.CustomProblemMatcher
---@field regexp string # non-empty regex pattern for error parsing
---@field file number # 1-based index in match groups for file path
---@field line number # 1-based index for line number
---@field column number # 1-based index for column number
---@field type_group number # 1-based index for severity (error/warning/info)
---@field message number # 1-based index for diagnostic message

---@alias loop.task.KnownProblemMatcher
---| "$gcc"
---| "$tsc-watch"
---| "$eslint-stylish"
---| "$msCompile"
---| "$lessCompile"

---@alias loop.task.ProblemMatcher loop.task.KnownProblemMatcher | loop.task.CustomProblemMatcher

---@alias loop.TaskType "lua"|"tool"|"app"|"debug"|"attach"

---@class loop.Task
---@field name string # non-empty task name (supports ${VAR} templates)
---@field type loop.TaskType # task category
---@field command string[]|string # non-empty executable command (supports templates)
---@field cwd string? # optional working directory (supports templates)
---@field env table<string,string>? # optional environment variables
---@field problem_matcher loop.task.ProblemMatcher | loop.task.ProblemMatcher[]? # optional error parser(s)
---@field depends_on string[]? # optional list of dependent task names
