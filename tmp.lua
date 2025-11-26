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
]]--\\\\


---@class loop.dap.session.Args.Target
---@field name string
---@field cmd string|string[]
---@field env table<string,string>|nil
---@field cwd string
---@field run_in_terminal boolean
---@field stop_on_entry boolean
---@field terminate_on_disconnect boolean|nil
  local target = self._args.debug_args.target
    if not target then
        if self._args.debug_args.dap.type == "remote" then
            -- ok with remote session
            return
        end
        -- should not happen
        self._fsm:trigger(fsmdata.trigger.launch_resp_ok)
        return
    end

    local cmdparts        = strtools.cmd_to_string_array(target.cmd)
    local target_program  = cmdparts[1]
    local target_args     = { unpack(cmdparts, 2) }
    local run_in_terminal = target.run_in_terminal
    local stop_on_entry   = target.stop_on_entry

    if run_in_terminal and not self._capabilities["supportsRunInTerminalRequest"] then
        self.log:error('run_in_terminal not supported by this adapter')
        self._fsm:trigger(fsmdata.trigger.launch_resp_error)
        return
    end

    self.log:info('launching: ' .. vim.inspect(target))
    self._base_session:request_launch({
            adapterID = self._args.debug_args.dap.name,
            columnsStartAt1 = true,
            linesStartAt1 = true,
            pathFormat = "path",
            program = target_program,
            args = target_args,
            cwd = target and target.cwd or nil,
            env = target and target.env or nil,
            runInTerminal = run_in_terminal,
            stopOnEntry = stop_on_entry,
        },
        function(err)
            self._fsm:trigger(err == nil and fsmdata.trigger.launch_resp_ok or fsmdata.trigger.launch_resp_error)
        end)
