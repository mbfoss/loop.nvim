--[[
local class = require('loop.tools.class')
local ItemListPage = require('loop.pages.ItemListPage')
local uitools = require('loop.tools.uitools')

local function _breakpoint_sign(entry)
    if entry.enabled == false then
        return " " -- disabled → no sign
    end
    if entry.logMessage and entry.logMessage ~= "" then
        return "▶" -- logpoint
    end
    if entry.condition and entry.condition ~= "" then
        return "◆" -- conditional
    end
    if entry.hitCondition and entry.hitCondition ~= "" then
        return "▲" -- hit-condition
    end
    return "●" -- plain breakpoint
end
local function _format_entry(entry)
    local parts = {}
    table.insert(parts, ":")
    table.insert(parts, tostring(entry.line))
    -- 3. Optional qualifiers
    if entry.condition and entry.condition ~= "" then
        table.insert(parts, " if " .. entry.condition)
    end
    if entry.hitCondition and entry.hitCondition ~= "" then
        table.insert(parts, " hits=" .. entry.hitCondition)
    end
    if entry.logMessage and entry.logMessage ~= "" then
        table.insert(parts, " log: " .. entry.logMessage:gsub("\n", " "))
    end
    return table.concat(parts, "")
end

---@class loop.pages.BreakpointsPage : loop.pages.ItemListPage
---@field new fun(self: loop.pages.BreakpointsPage, keymaps:loop.pages.page.KeyMaps): loop.pages.BreakpointsPage
local BreakpointsPage = class(ItemListPage)

---@param keymaps loop.pages.page.KeyMaps
function BreakpointsPage:init(keymaps)
    ItemListPage.init(self, "Breakpoints", keymaps)

    self:set_select_handler(function(item)
        ---@type loop.pages.ItemListPage.Item
        if item then
            uitools.smart_open_file(item.data.file, item.data.entry.line)
        end
    end)
end

---@param breakpoints loop.dap.proto.SourceBreakpoint[]
---@param proj_dir string
function BreakpointsPage:set_breakpoints(breakpoints, proj_dir)
    ---@type loop.pages.ItemListPage.highlight[]
    local highlights = { {
        group = "ErrorMsg",
        start_col = 0,
        end_col = 5
    } }

    ---@type loop.pages.ItemListPage.Item[]
    local items = {}
    for file, lines in pairs(breakpoints or {}) do
        for _, entry in ipairs(lines) do
            table.insert(items, {
                id = #items,
                text = _breakpoint_sign(entry) .. ' ' .. file .. _format_entry(entry),
                data = { file = file, entry = entry },
                highlights = highlights,
            })
        end
    end
    self:set_items(items)
end

return BreakpointsPage


---@param bp loop.dap.session.SourceBreakpoint
local function _refresh_breakpoint_sign(bp)
    if bp.file and bp.line then
        local verified = _verified[bp.usr_id]
        if verified == nil then verified = true end
        local sign = verified and "active_breakpoint" or "inactive_breakpoint"
        signs.place_file_sign(bp.file, bp.line, "breakpoints", sign)
        window.get_breakpoints_page():set_item({ id = bp.usr_id, text = vim.inspect(bp) })
    end
end

--- Remove a single breakpoint and its sign.
---@param file string File path
---@param line integer Line number
---@return boolean removed True if a breakpoint was removed
local function _remove_source_breakpoint(file, line)
    local lines = _source_breakpoints[file]
    if not lines then return false end

    local id = lines[line]
    if not id then return false end

    lines[line] = nil
    _by_id[id] = nil

    for type, tracker in pairs(_trackers) do
        tracker.on_removed(id)
    end

    signs.remove_file_sign(file, line, "breakpoints")
    window.get_breakpoints_page():remove_item(id)
    return true
end

---@param file string File path
local function _clear_file_breakpoints(file)
    local page = window.get_breakpoints_page()
    local lines = _source_breakpoints[file]
    if not lines then return end
    for _, id in pairs(lines) do
        _by_id[id] = nil
        page:remove_item(id)
    end
    _source_breakpoints[file] = nil
    signs.remove_file_signs(file, "breakpoints")
end

local function _clear_breakpoints()
    for file, _ in pairs(_source_breakpoints) do
        signs.remove_file_signs(file, "breakpoints")
    end
    window.get_breakpoints_page():set_items({})
    _by_id = {}
    _source_breakpoints = {}
    _need_saving = true
end


--- Add a new breakpoint and display its sign.
---@param file string File path
---@param line integer Line number
---@param condition? string condition
---@param hitCondition? string Optional hit condition
---@param logMessage? string Optional log message
---@return boolean added
local function _add_breakpoint(file, line, condition, hitCondition, logMessage)
    if _have_source_breakpoint(file, line) then
        return false
    end
    local id = _last_breakpoint_id + 1
    _last_breakpoint_id = id

    ---@type loop.dap.session.SourceBreakpoint
    local bp = {
        usr_id = id,
        file = file,
        line = line,
        condition = condition,
        hitCondition = hitCondition,
        logMessage = logMessage
    }

    _by_id[id] = bp

    _source_breakpoints[file] = _source_breakpoints[file] or {}
    local lines = _source_breakpoints[file]

    lines[line] = lines[line] or {}
    lines[line] = id

    _need_saving = true

    _refresh_breakpoint_sign(bp)
    return true
end

-- ----------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------

--- Toggle a breakpoint on the current line.
--- If a breakpoint exists, remove it; otherwise, add one.
function M.toggle_breakpoint()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return
    end
    local file = vim.fn.expand("%:p")
    if file == "" then
        return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if not _remove_source_breakpoint(file, lnum) then
        _add_breakpoint(file, lnum)
    end
end

---@param file string
function M.clear_file_breakpoints(file)
    file = vim.fn.fnamemodify(file, ":p")
    _clear_file_breakpoints(file)
end

--- clear all breakpoints.
function M.clear_all_breakpoints()
    _clear_breakpoints()
end

---@param id number
---@param verified boolean
function M.update_verified_status(id, verified)
    local bp = _by_id[id]
    if bp then
        _verified[id] = verified
        _refresh_breakpoint_sign(bp)
    end
end

function M.reset_verified_status()
    for _, bp in pairs(_by_id) do
        _verified[bp.usr_id] = nil
        _refresh_breakpoint_sign(bp)
    end
end

--- Load breakpoints from a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True on success
---@return string|nil errmsg Optional error message
function M.load_breakpoints(proj_config_dir)
    assert(_setup_done)
    assert(proj_config_dir and type(proj_config_dir) == 'string')
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')

    local loaded, data = json.load_from_file(breakpoints_file)
    if not loaded or type(data) ~= "table" then
        return false, data
    end

    _clear_breakpoints()

    ---@type loop.dap.session.SourceBreakpoint[]
    local breakpoints = data
    for _, bp in ipairs(breakpoints) do
        local file = vim.fn.fnamemodify(bp.file, ":p")
        _add_breakpoint(file, bp.line, bp.condition, bp.hitCondition, bp.logMessage)
    end

    _need_saving = false
    return true, nil
end

--- Save all breakpoints to a JSON file in the given project config directory.
---@param proj_config_dir string Path to project config directory
---@return boolean success True if saved or no save needed
---@return string|nil errmsg Optional error message
function M.save_breakpoints(proj_config_dir)
    assert(_setup_done)
    if not _need_saving then
        return true
    end
    if type(proj_config_dir) ~= 'string' or vim.fn.isdirectory(proj_config_dir) == 0 then
        return false, "Invalid argument"
    end

    local data = vim.tbl_values(_by_id)

    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
    local ok, err = json.save_to_file(breakpoints_file, data)
    if not ok then
        return false, err
    end

    _need_saving = false
    return true
end

---@return boolean
function M.have_breakpoints()
    return next(_by_id) ~= nil
end

---@return number[]
function M.get_ids()
    return vim.tbl_keys(_by_id)
end

---@return table<number,loop.dap.session.SourceBreakpoint>
function M.get_breakpoints()
    local arr = {}
    for id, bp in pairs(_by_id) do
        table.insert(arr, vim.deepcopy(bp))
    end
    return arr
end

---@param type loop.loop.breakpoints.TrackerType
---@param data loop.breakpoints.TrackerCallbacks|nil
function M.set_tracking_callbacks(type, data)
    _trackers[type] =data
end

]]--\\\\
