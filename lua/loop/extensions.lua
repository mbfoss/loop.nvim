-- IMPORTANT: keep this module light for lazy loading
local M = {}

---@type table<string,string>
local _ext_registry = {}

---@type table<string,string>
local _cmd_providers = {}
local _reserved_cmd_providers = {
    workspace = true,
    ui = true,
    page = true,
    logs = true,
    help = true,
    task = true,
    var = true
}

---@type table<string,string>
local _task_providers = {}
local _reserved_task_types = {
    composite = true, build = true, run = true, vimcmd = true
}

-- Cache for sorted keys to avoid redundant table operations
local _cache = {
    leads = nil,
    types = nil
}

---@return string[]
function M.ext_names()
    return vim.tbl_keys(_ext_registry)
end

---@return string[]
function M.cmd_leads()
    if not _cache.leads then
        _cache.leads = vim.fn.sort(vim.tbl_keys(_cmd_providers))
    end
    return _cache.leads
end

---@return string[]
function M.task_types()
    if not _cache.types then
        _cache.types = vim.fn.sort(vim.tbl_keys(_task_providers))
    end
    return _cache.types
end

---@class loop.ExtensionOpts
---@field name string
---@field module string
---@field is_cmd_provider? boolean
---@field cmd_lead? string
---@field is_task_provider? boolean
---@field task_type? string

---@param opts loop.ExtensionOpts
function M.register_extension(opts)
    assert(type(opts.module) == 'string' and opts.module:match("^[%w_.-][%w_.-]*$") ~= nil,
        "Invalid extension module: " .. tostring(opts.module))

    assert(type(opts.name) == 'string' and opts.name:match("[_%a][_%w]*") ~= nil,
        "Invalid extension name: " .. tostring(opts.name))
    assert(#opts.name >= 2, "ext name too short: " .. opts.name)
    assert(not _ext_registry[opts.name], "extension name already registered: " .. opts.name)

    _ext_registry[opts.name] = opts.module

    if opts.is_cmd_provider then
        local cmd_lead = opts.cmd_lead or opts.name
        assert(type(cmd_lead) == 'string' and cmd_lead:match("[_%a][_%w]*") ~= nil,
            "Invalid cmd lead: " .. tostring(cmd_lead))
        assert(not _reserved_cmd_providers[cmd_lead], "cmd lead is reserved: " .. cmd_lead)
        assert(#cmd_lead >= 2, "cmd lead too short: " .. cmd_lead)
        _cmd_providers[cmd_lead] = opts.module
        _cache.leads = nil -- invalidate cache
    end

    if opts.is_task_provider then
        local task_type = opts.task_type or opts.name
        assert(type(task_type) == 'string' and task_type:match("[_%a][_%w]*") ~= nil,
            "Invalid task type: " .. tostring(task_type))
        assert(not _reserved_task_types[task_type], "task type is reserved: " .. task_type)
        assert(#task_type >= 2, "ext task type too short: " .. task_type)
        _task_providers[task_type] = opts.module
        _cache.types = nil -- invalidate cache
    end
end

---@param modname string
---@return loop.Extension|nil
local function _get_extension(modname)
    local m = package.loaded[modname]
    if m then return m end

    -- Do not attempt to load modules during shutdown
    if vim.v.exiting ~= vim.NIL then return nil end

    local ok, res = pcall(require, modname)
    if not ok then
        vim.notify(string.format("[loop] Failed to load extension: %s\n%s", modname, res), vim.log.levels.ERROR)
        return nil
    end
    return res
end

---@param name string
---@return loop.Extension|nil
function M.get_extension(name)
    local modname = _ext_registry[name]
    return modname and _get_extension(modname) or nil
end

---@param name string
---@return loop.UserCommandProvider|nil
function M.get_cmd_provider(name)
    local modname = _cmd_providers[name]
    if not modname then return nil end

    local ex = _get_extension(modname)
    if ex and ex.get_cmd_provider then
        return ex.get_cmd_provider()
    end

    error("Extension for '" .. name .. "' (" .. modname .. ") is missing 'get_cmd_provider'")
end

---@param name string
---@return loop.TaskProvider|nil
function M.get_task_provider(name)
    local modname = _task_providers[name]
    if not modname then return nil end

    local ex = _get_extension(modname)
    if ex and ex.get_task_provider then
        return ex.get_task_provider()
    end

    error("Extension for '" .. name .. "' (" .. modname .. ") is missing 'get_task_provider'")
end

return M
