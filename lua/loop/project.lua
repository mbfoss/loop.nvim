local M = {}

require("loop.config")
local log = require('loop.tools.Logger').create_logger("project")
local taskmgr = require("loop.taskmgr")
local window = require("loop.window")
local uitools = require('loop.tools.uitools')
local vartools = require('loop.tools.vars')
local dap = require('loop.dap')
local breakpoints = require('loop.breakpoints')


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

function M.add_task()
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    local config_dir = _get_config_dir(proj_dir)
    taskmgr.add_task(config_dir)
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
        window.update_breakpoints(breakpoints.get_breakpoints(), _project_dir)
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
    if breakpoints.have_breakpoints() then
        window.update_breakpoints(breakpoints.get_breakpoints(), proj_dir)
    end

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
        vim.notify("Loop.nvim: another project is already active", vim.log.levels.ERROR)
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

---@param name string|nil
function M.run_task(name)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    local config_dir = _get_config_dir(proj_dir)
    taskmgr.run_task(proj_dir, config_dir, "task", nil, name)
end

function M.repeat_task()
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    local config_dir = _get_config_dir(proj_dir)
    taskmgr.run_task(proj_dir, config_dir, "repeat")
end

---@param ext_name string
---@param task_name string|nil
function M.extension_task(ext_name, task_name)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    local config_dir = _get_config_dir(proj_dir)
    taskmgr.run_task(proj_dir, config_dir, "extension", ext_name, task_name)
end

---@param ext_name string
function M.extension_config(ext_name)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    local config_dir = _get_config_dir(proj_dir)
    taskmgr.create_extension_config(config_dir, ext_name)
end

---@return string[]
function M.tab_names()
    assert(_setup_done)
    return window.tab_names()
end

---@param tabname string
function M.show_window(tabname)
    assert(_setup_done)
    window.show_window(tabname)
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

---@param command nil|"toggle"|"clear_file"|"clear_all"
function M.update_breakpoints(command)
    assert(_setup_done)
    local proj_dir = _get_proj_dir_or_warn()
    if not proj_dir then
        return
    end
    if command == nil or command == "toggle" then
        breakpoints.toggle_breakpoint()
        window.update_breakpoints(breakpoints.get_breakpoints(), proj_dir)
    elseif command == "clear_file" then
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local full_path = vim.api.nvim_buf_get_name(bufnr)
            if full_path and full_path ~= "" then
                uitools.confirm_action("Clear breakpoints in file", false, function(accepted)
                    if accepted == true then
                        breakpoints.clear_file_breakpoints(full_path)
                        window.update_breakpoints(breakpoints.get_breakpoints(), proj_dir)
                    end
                end)
            end
        end
    elseif command == "clear_all" then
        uitools.confirm_action("Clear all breakpoints", false, function(accepted)
            if accepted == true then
                breakpoints.clear_all_breakpoints()
                window.update_breakpoints(breakpoints.get_breakpoints(), proj_dir)
            end
        end)
    else
        vim.notify('loop.nvim: Invalid breakpoints subcommand: ' .. command)
    end
end

---@param command string|nil
function M.debug_command(command)
    vim.notify('loop.nvim: Invalid debug subcommand: ' .. tostring(command))
end

---@param config loop.Config
function M.setup(config)
    assert(not _setup_done, "Setup alreay done")
    _setup_done = true

    log:log('setup')

    dap.setup(config)

    breakpoints.setup()

    window.setup({})

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            local args = vim.fn.argv()
            local has_file = #args > 0 and vim.fn.isdirectory(args[1]) == 0
            if not has_file then
                local dir = #args > 0 and args[1] or vim.fn.getcwd()
                if _is_project_dir(dir) then
                    vim.schedule(function()
                        M.open_project(dir)
                    end
                    )
                end
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
