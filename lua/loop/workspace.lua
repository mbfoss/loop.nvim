local M = {}

local logs = require('loop.logs')
local taskmgr = require("loop.task.taskmgr")
local window = require("loop.ui.window")
local wsinfo = require("loop.wsinfo")
local runner = require("loop.task.runner")
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local jsonschema = require('loop.tools.jsonschema')
local filetools = require('loop.tools.file')
local wssaveutil = require('loop.ws.saveutil')
local migration = require('loop.ws.migration')
local floatwin = require('loop.tools.floatwin')
local selector = require('loop.tools.selector')

local _init_done = false
local _init_err_msg = "init() not called"

---@type loop.ws.WorkspaceInfo?
local _workspace_info = nil

local _save_timer = nil

-- New: recent workspaces persistence
local MAX_RECENTS = 50

local function _get_recent_file()
    local data_dir = vim.fn.stdpath('data')
    return vim.fs.joinpath(data_dir, "loop", "recent_workspaces.json")
end

local function _load_recent_workspaces()
    local f = _get_recent_file()
    if not filetools.file_exists(f) then return {} end
    local ok, data_or_err = jsontools.load_from_file(f)
    if not ok or type(data_or_err) ~= "table" then return {} end
    return data_or_err
end

local function _save_recent_workspaces(list)
    local f = _get_recent_file()
    -- ensure parent dir exists
    local dir = vim.fn.fnamemodify(f, ":h")
    vim.fn.mkdir(dir, "p")
    jsontools.save_to_file(f, list)
end

local function _add_recent_workspace(dir)
    if not dir or dir == "" then return end
    dir = vim.fn.fnamemodify(dir, ":p")
    local list = _load_recent_workspaces()
    local seen = {}
    local newlist = { dir }
    seen[dir] = true
    for _, v in ipairs(list) do
        local p = vim.fn.fnamemodify(v, ":p")
        if not seen[p] then
            table.insert(newlist, p)
            seen[p] = true
        end
        if #newlist >= MAX_RECENTS then break end
    end
    _save_recent_workspaces(newlist)
end

---@return loop.ws.WorkspaceInfo?
local function _get_ws_info_or_warn()
    if not _workspace_info then
        vim.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    return _workspace_info
end

local function _get_config_dir(workspace_dir)
    local dir = vim.fs.joinpath(workspace_dir, ".nvimloop")
    return dir
end

local function _save_workspace()
    if not _workspace_info then
        return false
    end
    assert(_init_done, _init_err_msg)
    window.save_settings(_workspace_info.config_dir)
    taskmgr.save_provider_states(_workspace_info)
    return true
end

---@param quiet? boolean
local function _close_workspace(quiet)
    if not _workspace_info then
        return false
    end

    runner.terminate_tasks()

    _save_workspace()

    taskmgr.on_workspace_unload(_workspace_info)

    if not quiet and _workspace_info then
        local label = _workspace_info.name or _workspace_info.root_dir
        logs.user_log("Workspace closed: " .. label, "workspace")
        vim.notify("Workspace closed")
    end
    _workspace_info = nil
    wsinfo.set_ws_info(nil)
end

---@param ws_dir string
---@return boolean
---@return string?
local function _configure_workspace(ws_dir)
    local config_dir = _get_config_dir(ws_dir)
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")
    local bufnr = vim.fn.bufnr(config_file)
    if bufnr ~= -1 then
        winid = uitools.smart_open_buffer(bufnr)
        return true
    end
    if not filetools.file_exists(config_file) then
        local model = require('loop.ws.template')
        model = vim.fn.copy(model)
        model.name = vim.fn.fnamemodify(ws_dir, ":p:h:t")
        jsontools.save_to_file(config_file, model)
    end
    local winid = uitools.smart_open_file(config_file)
    uitools.move_to_first_occurence(winid, '"name": "')
    return true, config_file
end

---@param config_dir string
---@return loop.WorkspaceConfig?,string[]?
local function _load_workspace_config(config_dir)
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")
    if not filetools.file_exists(config_file) then
        return nil, { "workspace.json not found" }
    end
    local loaded, data_or_err = jsontools.load_from_file(config_file)
    if not loaded then
        ---@cast data_or_err string
        return nil, { data_or_err }
    end
    local config = data_or_err
    local schema = require('loop.ws.schema')

    -- Check if migration is needed
    local needs_migrate, current_ver = migration.needs_migration(config)
    if needs_migrate then
        local migrated_config, migrate_err = migration.migrate_config(config)
        if migrate_err then
            return nil, { "Migration failed: " .. migrate_err }
        end
        config = migrated_config
        -- Save migrated config back to file
        local config_file = vim.fs.joinpath(config_dir, "workspace.json")
        local save_ok = jsontools.save_to_file(config_file, config)
        if not save_ok then
            vim.notify("Migrated workspace config but failed to save. Please save manually.",
                vim.log.levels.WARN)
        else
            vim.notify("Migrated workspace config from version " .. current_ver .. " to " .. config.version,
                vim.log.levels.INFO)
        end
    end

    local errors = jsonschema.validate(schema, config)
    if errors then
        return nil, errors
    end
    return config
end

---@param dir string
---@return boolean
---@return string|nil
local function _load_workspace(dir)
    assert(_init_done, _init_err_msg)
    assert(type(dir) == 'string')

    dir = vim.fn.fnamemodify(dir, ":p")

    local config_dir = _get_config_dir(dir)
    if not filetools.dir_exists(config_dir) then
        return false, "No workspace in " .. dir
    end

    local ws_config, config_errors = _load_workspace_config(config_dir)
    if not ws_config then
        logs.log(config_errors or "", vim.log.levels.ERROR)
        return false, "Failed to load workspace configuration (:Loop logs for details)"
    end

    local loopconfig = require('loop.config')
    ---@type loop.ws.WorkspaceInfo
    _workspace_info = {
        name = ws_config.name,
        root_dir = dir,
        config_dir = config_dir,
        config = ws_config,
    }
    if not _workspace_info.name or _workspace_info.name == "" then
        _workspace_info.name = vim.fn.fnamemodify(dir, ":p:h:t")
    end

    wsinfo.set_ws_info(vim.deepcopy(_workspace_info)) --copy for safety

    window.load_settings(config_dir)

    taskmgr.on_workspace_load(_workspace_info)

    if not _save_timer then
        local config = require('loop.config')
        local save_interval = (config.current.autosave_interval or 5) * 60 * 1000

        if save_interval > 0 then
            -- Create and start the repeating timer
            ---@diagnostic disable-next-line: undefined-field
            _save_timer = vim.loop.new_timer()
            _save_timer:start(
                save_interval, -- initial delay
                save_interval, -- frequency
                vim.schedule_wrap(_save_workspace)
            )
        end
    end

    return true, nil
end

function _show_workspace_info_floatwin()
    if not _workspace_info then
        vim.notify("No active workspace")
        return
    end
    local info = _workspace_info
    local save_config = vim.fn.copy(info.config.save)
    ---@diagnostic disable-next-line: inject-field
    save_config.__order = { "include", "exclude" }
    local str = ("Name: %s\nDirectory: %s\nFiles:\n%s"):format(info.name, info.root_dir,
        jsontools.to_string(save_config))
    floatwin.show_floatwin(str, { title = "Workspace" })
end

---@param dir string?
function M.create_workspace(dir)
    assert(_init_done, _init_err_msg)

    dir = dir or vim.fn.getcwd()
    local config_dir = _get_config_dir(dir)

    assert(type(dir) == 'string')
    assert(type(config_dir) == 'string')
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")

    if filetools.dir_exists(config_dir) and filetools.file_exists(config_file) then
        vim.notify("A workspace already exists in " .. dir, vim.log.levels.ERROR)
        return
    end

    -- Ask user to confirm creation and show the target directory
    local msg = "Create workspace in:\n" .. tostring(dir) .. "\n\nProceed?"
    local choice = vim.fn.confirm(msg, "&Yes\n&No", 2)
    if choice ~= 1 then
        vim.notify("Workspace creation cancelled")
        return false
    end

    -- important check because the user may pass garbage data
    if not filetools.dir_exists(dir) then
        vim.notify("Invalid directory " .. tostring(dir), vim.log.levels.ERROR)
        return
    end

    vim.fn.mkdir(config_dir, "p")

    if not _configure_workspace(dir) then
        vim.notify("Failed to setup configuration file")
    else
        local ws_name = vim.fn.fnamemodify(dir, ":p:h:t")
        logs.user_log("Workspace created: " .. ws_name, "workspace")
    end
end

---@param dir string?
---@param at_startup boolean
function M.open_workspace(dir, at_startup)
    assert(_init_done, _init_err_msg)

    -- If no dir provided, present recent workspaces via selector
    if not dir or dir == "" then
        local cwd = vim.fn.getcwd()
        local candidates = _load_recent_workspaces()

        -- If cwd is a workspace, ensure it's first
        local cwd_config_dir = _get_config_dir(cwd)
        if filetools.dir_exists(cwd_config_dir) then
            table.insert(candidates, 1, cwd)
        end

        -- Deduplicate and normalize
        local seen = {}
        local uniq = {}
        for _, p in ipairs(candidates) do
            if p and p ~= "" then
                local np = vim.fn.fnamemodify(p, ":p")
                if not seen[np] then
                    seen[np] = true
                    table.insert(uniq, np)
                end
            end
        end

        if #uniq == 0 then
            vim.notify("No recent workspaces found")
            return
        end

        local items = {}
        for _, path in ipairs(uniq) do
            local label = vim.fn.fnamemodify(path, ":t") .. " — " .. path
            table.insert(items, { label = label, data = path })
        end

        selector.select("Open workspace", items, nil, function(choice)
            if choice then
                -- async open of selected workspace
                M.open_workspace(choice, false)
            end
        end)
        return
    end

    dir = dir or vim.fn.getcwd()
    local ok, err_msg = _load_workspace(dir)
    if ok and _workspace_info then
        -- add to recent list (MRU)
        _add_recent_workspace(dir)

        local label = _workspace_info.name
        if not label or label == "" then label = _workspace_info.root_dir end
        logs.user_log("Workspace opened: " .. label, "workspace")
        if not at_startup then
            vim.notify("Workspace opened: " .. label)
        end
    else
        if not at_startup and err_msg then
            vim.notify(err_msg, vim.log.levels.ERROR)
        end
        errors = errors or {}
        logs.user_log("Workspace not loaded\n" .. table.concat(errors, '\n'), "workspace")
    end
end

function M.configure_workspace()
    if not _workspace_info then
        vim.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    local ok, configfile = _configure_workspace(_workspace_info.root_dir)
    if not ok or not configfile then
        vim.notify("Failed to setup configuration file")
        return
    end
    local read_ok, data_or_err = uitools.smart_read_file(configfile)
    if not read_ok then
        vim.notify("Workspace configuration error - " .. tostring(data_or_err))
        return
    end
    local config_ok, config_or_err = jsontools.from_string(data_or_err)
    if not config_ok then
        vim.notify("Workspace configuration is not a valid JSON - " .. tostring(config_or_err))
        return
    end
    local config = config_or_err
    local schema = require('loop.ws.schema')
    local errors = jsonschema.validate(schema, config)
    if errors then
        vim.notify("Workspace configuration error\n" .. table.concat(errors, '\n'))
    end
end

---@param args string[]
---@return string[]
function M.workspace_subcommands(args)
    if #args == 0 then
        return { "info", "create", "open", "configure", "save" }
    end
    return {}
end

---@param command string|nil
function M.workspace_cmmand(command)
    if not command or command == "" or command == "info" then
        _show_workspace_info_floatwin()
        return
    end
    if command == "create" then
        M.create_workspace()
        return
    end
    if command == "open" then
        M.open_workspace(nil, false)
        return
    end
    if command == "configure" then
        M.configure_workspace()
        return
    end
    if command == "save" then
        M.save_workspace_buffers()
        return
    end
    vim.notify("Invalid command: " .. command)
end

---@param args string[]
---@return string[]
function M.task_subcommands(args)
    if #args == 0 then
        return { "run", "repeat", "add", "configure", "terminate" }
    elseif #args == 1 then
        if args[1] == 'add' then
            return taskmgr.task_types()
        elseif args[1] == 'configure' then
            return taskmgr.configurable_task_types()
        end
    end
    return {}
end

---@return string[]
function M.configurable_task_types()
    return taskmgr.configurable_task_types()
end

---@param command string|nil
---@param arg1 string
---@param arg2? string|nil
function M.task_command(command, arg1, arg2)
    assert(_init_done, _init_err_msg)
    local ws_info = _get_ws_info_or_warn()
    if not ws_info then
        return
    end


    command = command and command:match("^%s*(.-)%s*$") or ""
    command = command ~= "" and command or "run"

    local config_dir = ws_info.config_dir
    if command == "run" then
        runner.run_task(config_dir, window.page_manger_factory(), "task", arg1)
    elseif command == "repeat" then
        runner.run_task(config_dir, window.page_manger_factory(), "repeat")
    elseif command == "add" then
        taskmgr.add_task(config_dir, arg1)
    elseif command == "configure" then
        taskmgr.configure(config_dir, arg1)
    elseif command == "terminate" then
        runner.terminate_tasks()
    else
        vim.notify('Invalid task command: ' .. command)
    end
end

---@param args string[]
---@return string[]
function M.var_subcommands(args)
    if #args == 0 then
        return { "add", "configure" }
    end
    return {}
end

---@param command string|nil
function M.var_command(command)
    assert(_init_done, _init_err_msg)
    local ws_info = _get_ws_info_or_warn()
    if not ws_info then
        return
    end

    command = command and command:match("^%s*(.-)%s*$") or ""
    if command == "" then
        command = "add"
    end

    local config_dir = ws_info.config_dir
    if command == "add" then
        taskmgr.add_variable(config_dir)
    elseif command == "configure" then
        taskmgr.configure_variables(config_dir)
    else
        vim.notify('Invalid var command: ' .. command)
    end
end

function M.page_subcommands(args)
    if #args == 0 then
        return { "switch", "open" }
    end
    if #args == 1 and (args[1] == "open") then
        local names = window.get_pagegroup_names()
        return vim.tbl_map(vim.fn.fnameescape, names)
    end
    if #args == 2 and (args[1] == "open") then
        local group = args[2]
        local names = window.get_page_names(group)
        return vim.tbl_map(vim.fn.fnameescape, names)
    end
    return {}
end

function M.page_command(command, arg1, arg2)
    if not command or command == "" or command == "switch" then
        M.switch_page()
    elseif command == "open" then
        M.open_page(arg1, arg2)
    else
        vim.notify("Invalid command: " .. command)
    end
end

function M.show_window()
    assert(_init_done, _init_err_msg)
    window.show_window()
end

function M.hide_window()
    assert(_init_done, _init_err_msg)
    window.hide_window()
end

function M.toggle_window()
    assert(_init_done, _init_err_msg)
    window.toggle_window()
end

function M.switch_page()
    assert(_init_done, _init_err_msg)
    window.switch_page()
end

---@param group_label string|nil
---@param page_label string|nil
function M.open_page(group_label, page_label)
    assert(_init_done, _init_err_msg)
    window.open_page(vim.api.nvim_get_current_win(), group_label, page_label)
end

function M.logs_command()
    assert(_init_done, _init_err_msg)
    logs.show_logs()
end

function M.save_workspace_buffers()
    local ws_info = _get_ws_info_or_warn()
    if not ws_info then return 0 end
    return wssaveutil.save_workspace_buffers(ws_info)
end

function M.winbar_click(id, clicks, button, mods)
    assert(_init_done, _init_err_msg)
    window.winbar_click(id, clicks, button, mods)
end

function M.init()
    assert(not _init_done, "init already done")
    _init_done = true

    window.init()

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            -- Stop the timer if it's still running
            if _save_timer and _save_timer:is_active() then
                _save_timer:stop()
                _save_timer:close()
            end

            if runner.have_running_task() then
                runner.terminate_tasks()
                local max_waits = 100 -- 10 seconds max
                while max_waits > 0 and runner.have_running_task() do
                    max_waits = max_waits - 1
                    vim.wait(100)
                end
            end

            _close_workspace(true)
        end,
    })
end

return M
