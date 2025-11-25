local M = {}

require("loop.config")
local taskmgr = require("loop.taskmgr")
local window = require("loop.window")
local uitools = require('loop.tools.uitools')
local vartools = require('loop.tools.vars')
local breakpoints = require('loop.breakpoints')
local extensions = require('loop.ext.extensions')

local _setup_done = false
local _project_dir = nil
local _save_timer = nil

local function _get_proj_dir_or_warn()
    if not _project_dir then
        vim.notify("Loop.nvim: No active project")
        return
    end
    return _project_dir
end

local function _get_config_dir(project_dir)
    local dir = vim.fs.joinpath(project_dir, ".nvimloop")
    return dir
end

local function _is_project_dir(dir)
    local config_dir = _get_config_dir(dir)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(config_dir)
    return stat and stat.type == "directory"
end

local function _save_project()
    if not _project_dir then
        return false
    end
    assert(_setup_done)
    local config_dir = _get_config_dir(_project_dir)
    vim.fn.mkdir(config_dir, "p")
    window.save_settings(config_dir)
    breakpoints.save_breakpoints(config_dir)
end

local function _close_project()
    if not _project_dir then
        return
    end
    _save_project()

    local have_breakpoints = breakpoints.have_breakpoints()
    if have_breakpoints then
        breakpoints.clear_all_breakpoints()
    end

    window.add_events({ "Project closed" })
    _project_dir = nil
end

---@param dir string
---@return boolean
---@return string[]|nil
local function _load_project(dir)
    assert(_setup_done)
    dir = dir or vim.fn.getcwd()
    if not _is_project_dir(dir) then
        return false, { "No project in " .. dir }
    end

    _close_project()

    local proj_dir = vim.fn.fnamemodify(dir, ":p")
    _project_dir = proj_dir

    vartools.set_context(proj_dir)
    local config_dir = _get_config_dir(proj_dir)

    window.load_settings(config_dir)
    breakpoints.load_breakpoints(config_dir)

    if not _save_timer then
        -- Create and start the repeating timer
        ---@diagnostic disable-next-line: undefined-field
        _save_timer = vim.loop.new_timer()
        local save_frequency = 5 * 60 * 1000 -- every 5 minutes (in ms)
        _save_timer:start(
            save_frequency,                  -- initial delay
            save_frequency,                  -- frequency
            vim.schedule_wrap(_save_project)
        )
    end

    return true, nil
end

function M.create_project(dir)
    assert(_setup_done)
    if _project_dir then
        return false
    end

    dir = dir or vim.fn.getcwd()
    assert(type(dir) == 'string')
    if _is_project_dir(dir) then
        vim.notify("A project already exists in " .. dir)
        return
    end

    local config_dir = _get_config_dir(dir)
    vim.fn.mkdir(config_dir, "p")

    _load_project(dir)
    if _project_dir then
        window.add_events({ "Project created in " .. _project_dir })
        window.show_events()
    end
end

function M.open_project(dir)
    assert(_setup_done)
    dir = dir or vim.fn.getcwd()
    local ok, errors = _load_project(dir)
    if ok and _project_dir then
        window.add_events({ "Project loaded " .. _project_dir })
    else
        errors = errors or {}
        table.insert(errors, 1, "Failed to load project")
        window.add_events(errors, "error")
        window.show_events()
    end
end

function M.close_project()
    assert(_setup_done)
    _close_project()
end

---@param args string[]
---@return string[]
function M.task_subcommands(args)
    if #args == 0 then
        return { "select", "run", "repeat", "add", "import", "configure" }
    elseif #args == 1 and args[1] == 'import' then
        return extensions.ext_names()
    end
    return {}
end

---@param command string|nil
---@param arg1 string|nil
function M.task_command(command, arg1)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end

    command = command and command:match("^%s*(.-)%s*$") or ""
    command = command ~= "" and command or "select"

    local config_dir = _get_config_dir(proj_dir)
    if command == "add" then
        taskmgr.add_task(config_dir)
    elseif command == "import" then
        taskmgr.import_task(config_dir, arg1 or "")
    elseif command == "configure" then
        taskmgr.open_task_config(config_dir)
    elseif command == "select" then
        taskmgr.run_task(proj_dir, config_dir, "task")
    elseif command == "run" then
        taskmgr.run_task(proj_dir, config_dir, "task")
    elseif command == "repeat" then
        taskmgr.run_task(proj_dir, config_dir, "repeat")
    else
        vim.notify('loop.nvim: Invalid task command: ' .. command)
    end
end

---@param args string[]
---@return string[]
function M.extension_subcommands(args)
    if #args == 0 then
        return extensions.ext_names()
    elseif #args == 1 then
        return { "configure", "task" }
    end
    return {}
end

---@param extname string|nil
---@param extcommand string|nil
function M.extension_command(extname, extcommand)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    
    local name = extname and extname:match("^%s*(.-)%s*$") or ""
    local cmd = extcommand and extcommand:match("^%s*(.-)%s*$") or ""

    local config_dir = _get_config_dir(proj_dir)
    if cmd == "" or cmd == "task" then
        taskmgr.run_extension_task(config_dir, name)
    elseif cmd == "configure" then
        taskmgr.create_extension_config(config_dir, name)
    else
        vim.notify('loop.nvim: Invalid extension command: ' .. extname .. ' ' .. cmd)
    end
end

---@param args string[]
---@return string[]
function M.breakpoints_subcommands(args)
    if #args == 0 then
        return { "toggle", "clear_file", "clear_all" }
    end
    return {}
end

---@param command nil|"toggle"|"clear_file"|"clear_all"
function M.breakpoints_command(command)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" or command == "toggle" then
        breakpoints.toggle_breakpoint()
    elseif command == "clear_file" then
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local full_path = vim.api.nvim_buf_get_name(bufnr)
            if full_path and full_path ~= "" then
                uitools.confirm_action("Clear breakpoints in file", false, function(accepted)
                    if accepted == true then
                        breakpoints.clear_file_breakpoints(full_path)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all breakpoints", false, function(accepted)
            if accepted == true then
                breakpoints.clear_all_breakpoints()
            end
        end)
    else
        vim.notify('loop.nvim: Invalid breakpoints subcommand: ' .. tostring(command))
    end
end


---@param args string[]
---@return string[]
function M.debug_subcommands(args)
    if #args == 0 then
        return { "continue", "step_in", "step_out", "step_over", "terminate" }
    end
    return {}
end

---@param command loop.job.DebugJob.Command|nil
function M.debug_command(command)
    taskmgr.debug_task_command(command)
end

function M.show_window()
    assert(_setup_done)
    window.show_window()
end

function M.hide_window()
    assert(_setup_done)
    window.hide_window()
end

function M.toggle_window()
    assert(_setup_done)
    window.toggle_window()
end

function M.winbar_click(id, clicks, button, mods)
    assert(_setup_done)
    window.winbar_click(id, clicks, button, mods)
end

---@param config loop.Config
function M.setup(config)
    assert(not _setup_done, "Setup alreay done")
    _setup_done = true

    require('loop.signs').setup()
    breakpoints.setup()

    window.setup({})

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            local args = vim.fn.argv()
            local has_dir = #args > 0 and vim.fn.isdirectory(args[1]) == 1
            local dir = has_dir and args[1] or vim.fn.getcwd()
            if _is_project_dir(dir) then
                vim.schedule(function()
                    M.open_project(dir)
                end
                )
            end
        end
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            -- Stop the timer if it's still running
            if _save_timer and _save_timer:is_active() then
                _save_timer:stop()
                _save_timer:close()
            end
            _save_project()
        end,
    })
end

return M
