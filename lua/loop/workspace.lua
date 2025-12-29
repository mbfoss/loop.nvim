local M = {}

require("loop.config")
local notifications = require('loop.notifications')
local taskmgr = require("loop.task.taskmgr")
local window = require("loop.ui.window")
local wsinfo = require("loop.wsinfo")
local runner = require("loop.task.runner")
local uitools = require('loop.tools.uitools')
local jsontools = require('loop.tools.json')
local jsonschema = require('loop.tools.jsonschema')
local strtools = require('loop.tools.strtools')
local filetools = require('loop.tools.file')
local persistence = require('loop.persistence')

local _init_done = false
local _init_err_msg = "init() not called"

---@type loop.ws.WorkspaceInfo?
local _workspace_info = nil

local _save_timer = nil

---@return loop.ws.WorkspaceInfo?
local function _get_ws_info_or_warn()
    if not _workspace_info then
        notifications.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    return _workspace_info
end

local function _get_config_dir(workspace_dir)
    local dir = vim.fs.joinpath(workspace_dir, ".nvimloop")
    return dir
end

local function _is_workspace_dir(dir)
    local config_dir = _get_config_dir(dir)
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.loop.fs_stat(config_dir)
    return stat and stat.type == "directory"
end

local function _save_workspace()
    if not _workspace_info then
        return false
    end
    assert(_init_done, _init_err_msg)
    window.save_settings(_workspace_info.config_dir)
    taskmgr.save_provider_states(_workspace_info)
end

---@param quiet? boolean
local function _close_workspace(quiet)
    if not _workspace_info then
        return false
    end

    assert(vim.v.exiting ~= vim.NIL, "can only close ws when vim is exiting")

    runner.terminate_tasks()

    _save_workspace()

    persistence.close()

    taskmgr.on_workspace_close(_workspace_info)

    if not quiet then notifications.notify("Workspace closed") end
    _workspace_info = nil
    wsinfo.set_ws_info(nil)
end

---@param config_dir any
---@return boolean
---@return string?
local function _init_or_open_ws_config(config_dir)
    local config_file = vim.fs.joinpath(config_dir, "workspace.json")
    if not filetools.file_exists(config_file) then
        jsontools.save_to_file(config_file, require('loop.wsconfig.template'))
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
        local default_config = vim.deepcopy(require('loop.wsconfig.template'))
        return default_config
    end
    local loaded, data_or_err = jsontools.load_from_file(config_file)
    if not loaded then
        ---@cast data_or_err string
        return nil, { data_or_err }
    end
    local config = data_or_err
    local schema = require('loop.wsconfig.schema')
    local errors = jsonschema.validate(schema, config)
    if errors then
        return nil, errors
    end
    return config
end

---@param dir string
---@param quiet? boolean
---@return boolean
---@return string[]|nil
---@return boolean? --- is config error
---@return string? -- config_dir where the error is
local function _load_workspace(dir, quiet)
    assert(_init_done, _init_err_msg)

    dir = dir or vim.fn.getcwd()
    dir = vim.fn.fnamemodify(dir, ":p")

    if _workspace_info and dir == _workspace_info.root_dir then
        if not quiet then
            notifications.notify("Workspace is already open")
            return true
        end
        return true
    end

    if _workspace_info and dir ~= _workspace_info.root_dir then
        return false, { "Another workspace is already open" }
    end

    if not _is_workspace_dir(dir) then
        return false, { "No workspace in " .. dir }
    end

    local config_dir = _get_config_dir(dir)
    local ws_config, config_errors = _load_workspace_config(config_dir)
    if not ws_config then
        return false, config_errors, true, config_dir
    end

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

    persistence.open(config_dir, ws_config.persistence)

    window.load_settings(config_dir)

    taskmgr.on_workspace_open(_workspace_info)

    if not _save_timer then
        -- Create and start the repeating timer
        ---@diagnostic disable-next-line: undefined-field
        _save_timer = vim.loop.new_timer()
        local save_frequency = 5 * 60 * 1000 -- every 5 minutes (in ms)
        _save_timer:start(
            save_frequency,                  -- initial delay
            save_frequency,                  -- frequency
            vim.schedule_wrap(_save_workspace)
        )
    end

    return true, nil
end

---@param dir string?
function M.create_workspace(dir)
    assert(_init_done, _init_err_msg)
    if _workspace_info then
        if dir == _workspace_info.root_dir then
            notifications.notify("Workspace already exists")
        else
            notifications.notify("Another workspace is already open")
        end
        return false
    end

    dir = dir or vim.fn.getcwd()
    assert(type(dir) == 'string')
    if _is_workspace_dir(dir) then
        notifications.notify("A workspace already exists in " .. dir, vim.log.levels.ERROR)
        return
    end

    -- important check because the user may pass garbage data
    if not filetools.dir_exists(dir) then
        notifications.notify("Invalid directory " .. tostring(dir), vim.log.levels.ERROR)
        return
    end

    local config_dir = _get_config_dir(dir)
    vim.fn.mkdir(config_dir, "p")

    _load_workspace(dir)
    if not _workspace_info then
        notifications.notify("Failed to create workspace")
        return
    end

    if not _init_or_open_ws_config(config_dir) then
        notifications.notify("Failed to setup configuration file")
    end
end

---@param dir string?
---@param at_startup boolean
function M.open_workspace(dir, at_startup)
    assert(_init_done, _init_err_msg)
    dir = dir or vim.fn.getcwd()
    local ok, errors, config_err, config_dir = _load_workspace(dir, at_startup)
    if ok and _workspace_info then
        local label = _workspace_info.name
        if not label or label == "" then label = _workspace_info.root_dir end
        notifications.log("Workspace loaded: " .. label)
    elseif not at_startup then
        errors = errors or {}
        table.insert(errors, 1, "Failed to load workspace")
        notifications.notify(errors, vim.log.levels.ERROR)
        if config_err then
            _init_or_open_ws_config(config_dir)
        end
    end
end

function M.configure_workspace()
    if not _workspace_info then
        notifications.notify("No active workspace", vim.log.levels.WARN)
        return
    end
    local ok, configfile = _init_or_open_ws_config(_workspace_info.config_dir)
    if not ok or not configfile then
        notifications.notify("Failed to setup configuration file")
        return
    end
    local read_ok, data_or_err = uitools.smart_read_file(configfile)
    if not read_ok then
        notifications.notify("Workspace configuration error - " .. tostring(data_or_err))
        return
    end
    local config_ok, config_or_err = jsontools.from_string(data_or_err)
    if not config_ok then
        notifications.notify("Workspace configuration is not a valid JSON - " .. tostring(config_or_err))
        return
    end
    local config = config_or_err
    local schema = require('loop.wsconfig.schema')
    local errors = jsonschema.validate(schema, config)
    if errors then
        notifications.notify("Workspace configuration error\n" .. table.concat(errors, '\n'))
    end
end

--[[
function M.save_session()
    local session_path = vim.fs.joinpath(config_dir, "session.vim")

    if filetools.file_exists(session_path) then
        vim.cmd("silent! source " .. vim.fn.fnameescape(session_path))
    end
end

function M.load_session()
    -- === Save Session with completely safe options ===
    if _state.flags.session then
        local session_path = vim.fs.joinpath(_state.config_dir, "session.vim")

        -- Temporarily set safe sessionoptions
        local old_sessionoptions = vim.o.sessionoptions
        vim.o.sessionoptions = SAFE_SESSIONOPTIONS

        vim.cmd("mksession! " .. vim.fn.fnameescape(session_path))

        -- Restore user's original sessionoptions
        vim.o.sessionoptions = old_sessionoptions
    end
end
]]

---@param args string[]
---@return string[]
function M.workspace_subcommands(args)
    if #args == 0 then
        return { "info", "open", "create", "configure", "save" }
    end
    return {}
end

---@param command string|nil
function M.workspace_cmmand(command)
    if not command or command == "" or command == "info" then
        if _workspace_info then
            vim.notify(("Name: %s\nDirectory: %s"):format(_workspace_info.name, _workspace_info.root_dir))
        else
            vim.notify("No active workspace")
        end
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
    notifications.notify("Invalid command: " .. command)
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
        notifications.notify('Invalid task command: ' .. command)
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
        local group = args[1]
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
        notifications.notify("Invalid command: " .. command)
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
---@param page_pabel string|nil
function M.open_page(group_label, page_pabel)
    assert(_init_done, _init_err_msg)
    window.open_page(vim.api.nvim_get_current_win(), group_label, page_pabel)
end

---Generates and displays a notification for the save operation.
---@param saved_count number Total files saved.
---@param excluded_count number Total modified files skipped.
---@param saved_paths string[] List of relative paths that were saved.
local function report_save_results(saved_count, excluded_count, saved_paths)
    if saved_count == 0 and excluded_count == 0 then return end

    local lines = {}
    if saved_count > 0 then
        table.insert(lines, ("󰄵 Saved %d file%s:"):format(saved_count, saved_count == 1 and "" or "s"))
        for i = 1, math.min(saved_count, 5) do
            table.insert(lines, ("  • %s"):format(saved_paths[i]))
        end
        if saved_count > 5 then
            table.insert(lines, ("  … and %d more"):format(saved_count - 5))
        end
    end

    if excluded_count > 0 then
        table.insert(lines, ("✖ Excluded %d modified file%s via filter"):format(
            excluded_count, excluded_count == 1 and "" or "s"
        ))
    end

    local level = saved_count > 0 and vim.log.levels.INFO or vim.log.levels.WARN
    notifications.notify(lines, level)
end

function M.save_workspace_buffers()
    local ws_info = _get_ws_info_or_warn()
    if not ws_info then return 0 end

    local filter = ws_info.config.save
    -- Resolve the physical project root
    local root_path = vim.fs.normalize(ws_info.root_dir)
    local real_root = vim.uv.fs_realpath(root_path)
    if not real_root then return 0 end

    local saved, excluded, saved_paths = 0, 0, {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not uitools.is_regular_buffer(bufnr) or not vim.bo[bufnr].modified then
            goto continue
        end

        local bname = vim.api.nvim_buf_get_name(bufnr)
        if bname == "" then goto continue end

        local norm_path = vim.fs.normalize(bname)
        local real_file_path = vim.uv.fs_realpath(norm_path)
        if not real_file_path then goto continue end

        -- 1. PURE FS HIDDEN CHECK
        -- We walk up from the file to the root. If ANY parent (or the file itself)
        -- has a basename starting with a dot, it is hidden.
        local is_hidden = false
        -- Check the file itself first
        if vim.fs.basename(norm_path):sub(1, 1) == "." then
            is_hidden = true
        else
            -- Check all parents up to the root
            for parent in vim.fs.parents(norm_path) do
                if vim.fs.basename(parent):sub(1, 1) == "." then
                    is_hidden = true
                    break
                end
                if parent == root_path then break end
            end
        end

        if is_hidden then
            excluded = excluded + 1
            goto continue
        end

        -- 2. PURE FS BOUNDARY CHECK
        -- Verify real_root is an ancestor of real_file_path
        local is_inside = false
        if real_file_path == real_root then
            is_inside = true
        else
            for parent in vim.fs.parents(real_file_path) do
                if parent == real_root then
                    is_inside = true
                    break
                end
            end
        end

        if not is_inside then
            excluded = excluded + 1
            goto continue
        end

        -- 3. SYMLINK CHECK
        -- If follow_symlinks is false, we ensure the paths are identical
        -- after normalization (handles case-sensitivity/slash differences)
        if not filter.follow_symlinks and (norm_path ~= vim.fs.normalize(real_file_path)) then
            excluded = excluded + 1
            goto continue
        end

        -- 4. GLOB FILTERS (Only string part remaining, required by glob logic)
        local inc = #filter.include > 0 and strtools.matches_any(norm_path, filter.include)
        local exc = #filter.exclude > 0 and strtools.matches_any(norm_path, filter.exclude)

        if (#filter.include > 0 and not inc) or exc then
            excluded = excluded + 1
            goto continue
        end

        -- 5. SAVE
        if pcall(function() vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end) end) then
            saved = saved + 1
            table.insert(saved_paths, vim.fs.basename(norm_path))
        else
            excluded = excluded + 1
        end

        ::continue::
    end

    report_save_results(saved, excluded, saved_paths)
    return saved
end

function M.winbar_click(id, clicks, button, mods)
    assert(_init_done, _init_err_msg)
    window.winbar_click(id, clicks, button, mods)
end

function M.init()
    assert(not _init_done, "init alreay done")
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
                local max_waits = 100 -- 5 seconds max
                while max_waits > 0 and runner.have_running_task() do
                    max_waits = max_waits - 1
                    vim.wait(50)
                end
            end

            _close_workspace(true)
        end,
    })
end

return M
