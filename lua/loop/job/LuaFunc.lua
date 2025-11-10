local Job      = require('loop.job.Job')
local class    = require('loop.tools.class')
local buftools = require('loop.tools.buffer')


---@class loop.job.LuaFunc : loop.job.Job
---@field new fun(self: loop.job.LuaFunc) : loop.job.LuaFunc
local LuaFunc = class(Job)

---@diagnostic disable-next-line: undefined-field
local main_thread_id = vim.loop.thread_self() -- capture at startup
local function assert_main_thread()
    ---@diagnostic disable-next-line: undefined-field
    assert(vim.loop.thread_self() == main_thread_id, "Not in main thread!")
end

---Initializes the LuaFunc instance.
function LuaFunc:init()
end

---@return boolean
function LuaFunc:is_running()
    return false
end

function LuaFunc:kill()
end

---Kills the running terminal job, if any.
function LuaFunc:kill_and_wait()
end

---@class loop.LuaFunc.StartArgs
---@field command string|string[]
---@field on_exit_handler fun(code : number)

---Starts a new terminal job.
---@param args loop.LuaFunc.StartArgs
---@return boolean, string|nil
function LuaFunc:start(args)
    local arr = type(args.command) == 'string' and { args.command } or args.command
    if type(arr) ~= "table" or #arr < 1 then
        return false, "Invalid command"
    end

    local full_name = arr[1]
    if type(full_name) ~= "string" then
        return false, "Invalid function name format"
    end

    -- separate module path and function name
    local module_path, fn_name = full_name:match("^(.-)%.([^%.]+)$")
    if not module_path or not fn_name then
        return false, ("invalid function name format: %q (expected module.submodule.function)"):format(full_name)
    end

    -- require the module
    local require_ok, mod = pcall(require, module_path)
    if not require_ok then
        return false, ("could not require module %q: %s"):format(module_path, mod)
    end
    if type(mod) ~= "table" then
        return false, ("module %q did not return a table"):format(module_path)
    end

    local fn = mod[fn_name]
    if type(fn) ~= "function" then
        return false, ("module %q does not have function %q"):format(module_path, fn_name)
    end

    local call_args = {}
    for i = 2, #arr do
        if type(arr[i]) ~= "string" then
            return false, ("argument #%d is not a string (value: %s)"):format(i, tostring(arr[i]))
        end
        call_args[#call_args + 1] = arr[i]
    end

    local fncall_ok, out1, out2 = pcall(fn, call_args)
    if not fncall_ok then
        return false, "lua call failed, " .. out1
    end
    if type(out1) ~= 'boolean' then
        return false, "lua call did not return a boolean"        
    end
    if not out1 then 
        return false, out2 or "Unkown error"
    end
    if args.on_exit_handler then
        vim.schedule(function ()
            args.on_exit_handler(0)
        end)
    end
    return true, nil
end

return LuaFunc
