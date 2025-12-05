local config            = require('loop.config')
local signs             = require('loop.signs')
local selector          = require("loop.selector")
local window            = require('loop.window')
local breakpoints       = require('loop.dap.breakpoints')
local Page              = require('loop.pages.Page')
local OutputPage        = require('loop.pages.OutputPage')
local ItemListPage      = require('loop.pages.ItemListPage')
local ItemTreePage      = require('loop.pages.ItemTreePage')
local StackTracePage    = require('loop.pages.StackTracePage')
local uitools           = require('loop.tools.uitools')
local Trackers          = require('loop.tools.Trackers')

local M                 = {}

local _setup_done       = false
local _last_node_id     = 0

---@class loop.debugui.TrackerCallbacks
---@field on_bp_added fun(bp:loop.dap.SourceBreakpoint, verified:boolean)|nil
---@field on_bp_removed fun(bp:loop.dap.SourceBreakpoint)|nil
---@field on_all_bp_removed fun(bpts:loop.dap.SourceBreakpoint[])|nil
---@field on_bp_state_update fun(bp:loop.dap.SourceBreakpoint, verified:boolean)

---@type loop.tools.Trackers<loop.debugui.TrackerCallbacks>
local _trackers         = Trackers:new()

---@class loop.debug_ui.Breakpointata
---@field breakpoint loop.dap.SourceBreakpoint
---@field states table<number,boolean>|nil

---@type table<number,loop.debug_ui.Breakpointata>
local _breakpoints_data = {}

---@param bp loop.dap.SourceBreakpoint
---@param verified boolean
---@return loop.signs.SignName
local function _get_breakpoint_sign(bp, verified)
    -- Determine the sign type based on breakpoint fields
    local sign
    if bp.logMessage then
        sign = verified and "logpoint" or "logpoint_inactive"
    elseif bp.condition or bp.hitCondition then
        sign = verified and "conditional_breakpoint" or "conditional_breakpoint_inactive"
    else
        sign = verified and "active_breakpoint" or "inactive_breakpoint"
    end
    return sign
end

---@param data loop.debug_ui.Breakpointata
---@@return boolean
local function _get_breakpoint_state(data)
    local verified = nil
    if data.states then
        for _, state in ipairs(data.states) do
            verified = verified or state
        end
    end
    if verified == nil then verified = true end
    return verified
end

---@param data loop.debug_ui.Breakpointata
local function _refresh_breakpoint_sign(data)
    local verified = _get_breakpoint_state(data)
    local sign = _get_breakpoint_sign(data.breakpoint, verified)
    signs.place_file_sign(data.breakpoint.file, data.breakpoint.line, "breakpoints", sign)
    _trackers:invoke("on_bp_state_update", data.breakpoint, verified)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_breakpoint_added(bp)
    _breakpoints_data[bp.id] = {
        breakpoint = bp,
    }
    local sign = _get_breakpoint_sign(bp, true)
    signs.place_file_sign(bp.file, bp.line, "breakpoints", sign)
    _trackers:invoke("on_bp_added", bp, true)
end

---@param bp loop.dap.SourceBreakpoint
local function _on_breakpoint_removed(bp)
    _breakpoints_data[bp.id] = nil
    signs.remove_file_sign(bp.file, bp.line, "breakpoints")
    _trackers:invoke("on_bp_removed", bp)
end

---@param removed loop.dap.SourceBreakpoint[]
local function _on_all_breakpoints_removed(removed)
    _breakpoints_data = {}
    local files = {}
    for _, bp in ipairs(removed) do
        files[bp.file] = true
    end
    for file, _ in pairs(files) do
        signs.remove_file_signs(file, "breakpoints")
    end
    _trackers:invoke("on_all_bp_removed", removed)
end

---@param sess_id number
---@param sess_name string
---@param parent_id number|nil
---@param task_page loop.pages.ItemListPage
local function _on_session_added(sess_id, sess_name, parent_id, task_page)
    task_page:upsert_item({
        id = sess_id,
        data = {
            name = sess_name,
            state = 'starting'
        }
    })

    for _, data in pairs(_breakpoints_data) do
        data.states = data.states or {}
        data.states[sess_id] = false
        _refresh_breakpoint_sign(data)
    end
end

---@param sess_id number
---@param sess_name string
---@param task_page loop.pages.ItemListPage
local function _on_session_removed(sess_id, sess_name, task_page)
    task_page:remove_item(sess_id)
    for _, data in pairs(_breakpoints_data) do
        if data.states then
            data.states[sess_id] = nil
            _refresh_breakpoint_sign(data)
        end
    end
end

---@param sess_id number
---@param sess_name string
---@param data loop.dap.session.notify.StateData
---@param task_page loop.pages.ItemListPage
---@param stacktrace_page loop.pages.StackTracePage|nil
local function _on_session_state_update(sess_id, sess_name, data, task_page, stacktrace_page)
    local item = task_page:get_item(sess_id)
    if item then
        item.data.state = data.state
        task_page:refresh_content()
    end
    if data.state == "ended" then
        signs.remove_signs("currentframe")
        if stacktrace_page then
            stacktrace_page:clear_content()
        end
    end
end

---@param sess_id number
---@param session loop.dap.Session
---@param event loop.dap.session.notify.BreakpointsEvent
local function _on_session_breakpoints_event(sess_id, session, event)
    for _, state in ipairs(event) do
        local bp = _breakpoints_data[state.breakpoint_id]
        if bp then
            bp.states = bp.states or {}
            bp.states[sess_id] = state.verified
            local data = _breakpoints_data[state.breakpoint_id]
            if data then
                _refresh_breakpoint_sign(data)
            end
        end
    end
end

local function _make_node_id()
    local id = _last_node_id + 1
    _last_node_id = id
    return id
end

---@param scopes loop.dap.proto.Scope[]
---@param thread_data loop.dap.session.notify.ThreadData
---@param variables_page loop.pages.ItemTreePage
local function _load_scopes(scopes, thread_data, variables_page)
    ---@param ref number
    ---@param parent_id number
    ---@param callback fun(items:loop.pages.ItemTreePage.Item[])
    local function load_variables(ref, parent_id, callback)
        thread_data.variables_provider({ variablesReference = ref },
            function(_, vars_data)
                local children = {}
                if vars_data then
                    for var_idx, var in ipairs(vars_data.variables) do
                        ---@type loop.pages.ItemTreePage.Item
                        local var_item = {
                            id = _make_node_id(),
                            parent = parent_id,
                            expanded = true,
                            data = { variable = var },
                        }
                        if var.variablesReference and var.variablesReference > 0 then
                            var_item.expanded = false
                            var_item.children_callback = function(cb)
                                load_variables(var.variablesReference, var_item.id, cb)
                            end
                        end
                        table.insert(children, var_item)
                    end
                end
                callback(children)
            end)
    end

    for scope_idx, scope in ipairs(scopes) do
        local suffix = scope.expensive and " ⏱" or ""
        ---@type loop.pages.ItemTreePage.Item
        local scope_item = {
            id = _make_node_id(),
            expanded = false,
            data = { text = scope.name .. suffix }
        }
        if not scope.expensive
            and scope.presentationHint ~= "globals"
            and scope.name ~= "Globals"
            and scope.presentationHint ~= "registers"
        then
            scope_item.expanded = true
        end
        scope_item.children_callback = function(cb)
            load_variables(scope.variablesReference, scope_item.id, cb)
        end
        variables_page:insert_item(scope_item)
    end
end

---@param sess_id number
---@param sess_name string
---@param event_data loop.dap.session.notify.ThreadData
---@param variables_page loop.pages.ItemTreePage
---@param stacktrace_page loop.pages.StackTracePage
local function _on_thread_pause(sess_id, sess_name, event_data, variables_page, stacktrace_page)
    if not event_data.thread_id then return end
    local curframe
    -- handle current frame
    event_data.stack_provider({ threadId = event_data.thread_id, levels = 1 }, function(err, data)
        ---@type loop.dap.proto.StackFrame
        curframe = data and data.stackFrames[1] or nil
        if curframe and curframe.source and curframe.source.path then
            signs.place_file_sign(curframe.source.path, curframe.line, "currentframe", "currentframe")
            uitools.smart_open_file(curframe.source.path, curframe.line, curframe.column)
        end
        -- handle scopes/variable
        if curframe then
            event_data.scopes_provider({ frameId = curframe.id }, function(_, scopes_data)
                if scopes_data and scopes_data.scopes then
                    _load_scopes(scopes_data.scopes, event_data, variables_page)
                end
            end)
        end
    end)
    -- handle stack trace page
    do
        stacktrace_page:set_content(event_data)
    end
end

---@param sess_id number
---@param sess_name string
---@param variables_page loop.pages.ItemTreePage|nil
---@param stacktrace_page loop.pages.StackTracePage|nil
local function _on_thread_continue(sess_id, sess_name, variables_page, stacktrace_page)
    signs.remove_signs("currentframe")
    if variables_page then
        variables_page:set_items({})
    end
    if stacktrace_page then
        stacktrace_page:clear_content()
    end
end

---@param item loop.pages.ItemListPage.Item
function _debug_session_item_formatter(item)
    return item.data.name .. ' - ' .. item.data.state
end

---@param item loop.pages.ItemListPage.Item
---@return string
function _variable_node_formatter(item)
    if item.data.text then
        return item.data.text
    end
    ---@type loop.dap.proto.Variable
    local var = item.data.variable
    return tostring(var.name) .. ": " .. tostring(var.value)
end

---@param item loop.pages.ItemListPage.Item
---@return loop.pages.ItemTreePage.Highlight[]|nil
function _variable_node_highlighter(item)
    if item.data.text then
        return nil
    end
    -----@type loop.dap.proto.Variable
    --local var = item.data.variable
    return {}
end

---@param task_name string -- task name
---@return loop.job.debugjob.Tracker
function M.track_new_debugjob(task_name)
    assert(_setup_done)
    assert(type(task_name) == "string")

    ---@type loop.pages.ItemListPage
    local task_page = ItemListPage:new(task_name, {
        formatter = _debug_session_item_formatter
    })
    window.add_page("task", task_page)

    created = true

    local output_pages = {}
    local stacktrace_pages = {}
    local variable_pages = {}

    ---@type loop.job.debugjob.Tracker
    local tracker = {
        on_sess_added = function(id, name, parent_id)
            _on_session_added(id, name, parent_id, task_page)
        end,
        on_sess_removed = function(id, name)
            _on_session_removed(id, name, task_page)
        end,
        on_sess_state = function(sess_id, name, data)
            local stacktrace_page = stacktrace_pages[sess_id]
            _on_session_state_update(sess_id, name, data, task_page, stacktrace_page)
        end,
        on_output = function(sess_id, sess_name, category, output)
            ---@type loop.pages.OutputPage|nil
            ---@diagnostic disable-next-line: assign-type-mismatch
            local page = output_pages[sess_id]
            if not page then
                page = OutputPage:new(sess_name)
                window.add_page("debugoutput", page)
                output_pages[sess_id] = page
            end
            local level = category == "stderr" and "error" or nil
            page:add_line(output, level)
        end,
        on_new_term = function(name, bufnr)
            local page = Page:new("term", name)
            page:assign_buf(bufnr)
            window.add_page("debugoutput", page)
        end,
        on_thread_pause = function(sess_id, sess_name, thread_data)
            ---@type loop.pages.ItemTreePage|nil
            local variable_page = variable_pages[sess_id]
            ---@type loop.pages.StackTracePage|nil
            local stacktrace_page = stacktrace_pages[sess_id]

            if not variable_page then
                variable_page = ItemTreePage:new(sess_name, {
                    formatter = _variable_node_formatter,
                    highlighter = _variable_node_highlighter,
                })
                window.add_page("variables", variable_page)
                variable_pages[sess_id] = variable_page
            end

            if not stacktrace_page then
                stacktrace_page = StackTracePage:new(sess_name)
                window.add_page("stacktrace", stacktrace_page)
                stacktrace_pages[sess_id] = stacktrace_page
            end

            _on_thread_pause(sess_id, sess_name, thread_data, variable_page, stacktrace_page)
        end,
        on_thread_continue = function(sess_id, sess_name)
            ---@type loop.pages.ItemTreePage|nil
            local variables_page = variable_pages[sess_id]
            ---@type loop.pages.StackTracePage|nil
            local stacktrace_page = stacktrace_pages[sess_id]
            _on_thread_continue(sess_id, sess_name, variables_page, stacktrace_page)
        end,

        on_breakpoint_event = _on_session_breakpoints_event,
        on_exit = function(code)

        end
    }
    return tracker
end

---@param callbacks loop.debugui.TrackerCallbacks
---@return number
function M.add_tracker(callbacks)
    local tracker_id = _trackers:add_tracker(callbacks)
    --initial snapshot
    if callbacks.on_bp_added then
        for _, data in pairs(_breakpoints_data) do
            local verified = _get_breakpoint_state(data)
            callbacks.on_bp_added(data.breakpoint, verified)
        end
    end
    return tracker_id
end

---@param id number
---@return boolean
function M.remove_tracker(id)
    return _trackers:remove_tracker(id)
end

--- Setup the breakpoint sign system and autocommands.
---@param _? table Optional setup options (currently unused)
function M.setup(_)
    assert(not _setup_done, "setup already done")
    _setup_done = true

    require('loop.dap.breakpoints').add_tracker({
        on_added = _on_breakpoint_added,
        on_removed = _on_breakpoint_removed,
        on_all_removed = _on_all_breakpoints_removed
    })
end

return M
