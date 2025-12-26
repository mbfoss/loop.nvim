local class = require('loop.tools.class')
local strtools = require('loop.tools.strtools')
local uitools = require('loop.tools.uitools')
local BaseBuffer = require('loop.buf.BaseBuffer')

---@class loop.comp.ReplBuffer : loop.comp.BaseBuffer
---@field private _chan number|nil The terminal channel ID
---@field private _current_line string Current raw string in the input buffer
---@field private _cursor_pos number 1-indexed position of the cursor
---@field private _history string[] List of submitted commands
---@field private _history_idx number Navigation index for history
---@field private _prompt string The shell prompt with ANSI colors
---@field private _completion loop.ReplCompletionState Internal completion state
---@field private _input_handler fun(input: string)|nil Handler for Enter key
---@field private _completion_handler loop.ReplCompletionHandler|nil Provider for Tab suggestions
local ReplBuffer = class(BaseBuffer)

---@class loop.ReplCompletionState
---@field request_counter number Unique ID for the latest async request
---@field current_request number The ID of the request currently being waited on
---@field cycle_list string[] List of strings to cycle through
---@field cycle_idx number Current index in the cycle_list
---@field line_before_cycle string The left-hand side of the line before cycling started
---@field tail_after_cycle string The right-hand side of the line before cycling started

---@type table<string, string>
local COLORS = {
    RESET = "\27[0m",
    BOLD  = "\27[1m",
    GREEN = "\27[32m",
    BLUE  = "\27[34m",
    RED   = "\27[31m",
    CYAN  = "\27[36m",
}

---Initializes a new ReplBuffer
---@param type string
---@param name string
function ReplBuffer:init(type, name)
    BaseBuffer.init(self, type, name)
    self._chan = nil
    self._current_line = ""
    self._cursor_pos = 1
    self._history = {}
    self._history_idx = 0
    self._prompt = COLORS.BOLD .. COLORS.GREEN .. "> " .. COLORS.RESET

    self._completion = {
        request_counter = 0,
        current_request = -1,
        cycle_list = {},
        cycle_idx = 0,
        line_before_cycle = "",
        tail_after_cycle = "",
    }

    self._input_handler = nil
    self._completion_handler = nil
end

---@return loop.ReplController
function ReplBuffer:make_controller()
    return {
        set_input_handler = function(handler) self._input_handler = handler end,
        set_completion_handler = function(handler) self._completion_handler = handler end,
        add_output = function(text) self:send_line(text) end
    }
end

---Sends output text to the buffer and redraws the prompt
---@param text string
function ReplBuffer:send_line(text)
    if self._chan then
        -- Clear current prompt line, print output, then restore prompt
        local formatted = "\r\27[K" .. text .. "\r\n" .. self._prompt .. self._current_line
        vim.api.nvim_chan_send(self._chan, formatted)
        self:_redraw_line()
    end
end

---Redraws the input line and positions the terminal cursor
---@private
function ReplBuffer:_redraw_line()
    -- Calculate column by stripping ANSI codes from prompt
    local clean_prompt = self._prompt:gsub("\27%[[%d;]*m", "")
    local col = #clean_prompt + self._cursor_pos
    -- \r\27[K clears the line the cursor is on, preserving grids above
    local out = "\r\27[K" .. self._prompt .. self._current_line .. "\27[" .. col .. "G"
    vim.api.nvim_chan_send(self._chan, out)
end

---Resets completion cycling state
---@private
function ReplBuffer:_reset_cycle()
    self._completion.cycle_list = {}
    self._completion.cycle_idx = 0
    self._completion.line_before_cycle = ""
    self._completion.tail_after_cycle = ""
end

---Sets up terminal buffer and keymaps
---@private
function ReplBuffer:_setup_buf()
    BaseBuffer._setup_buf(self)
    local buf = self:get_buf()

    vim.keymap.set('t', '<Esc>', function() vim.cmd('stopinsert') end, { buffer = buf })

    -- Map Tab directly to the handler to avoid interception
    vim.keymap.set('t', '<Tab>', function() self:_handle_raw_input("\t") end, { buffer = buf, silent = true })

    self._chan = vim.api.nvim_open_term(buf, {
        on_input = function(_, _, _, data) self:_handle_raw_input(data) end
    })
    self:_redraw_line()
end

---Executes an async completion request with state validation
---@param line_to_cursor string
---@param callback fun(targets: string[]|table[])
function ReplBuffer:on_complete(line_to_cursor, callback)
    if not self._completion_handler then return callback({}) end

    self._completion.request_counter = self._completion.request_counter + 1
    local request_id = self._completion.request_counter
    local pos_at_request = self._cursor_pos

    self._completion_handler(line_to_cursor, function(targets)
        vim.schedule(function()
            local current_left = self._current_line:sub(1, self._cursor_pos - 1)
            -- Only trigger if the user hasn't typed/moved since the request
            if request_id == self._completion.request_counter
                and self._cursor_pos == pos_at_request
                and current_left == line_to_cursor then
                callback(targets or {})
            end
        end)
    end)
end

---Cycles to the next completion candidate in the prompt
---@private
function ReplBuffer:_cycle_next()
    local c = self._completion
    if #c.cycle_list == 0 then return end

    c.cycle_idx = c.cycle_idx + 1
    if c.cycle_idx > #c.cycle_list then c.cycle_idx = 1 end

    local item = c.cycle_list[c.cycle_idx]
    local suggestion = type(item) == "table" and item.text or item

    local prefix, _ = c.line_before_cycle:match("(.-)([^%s]*)$")
    local new_before = (prefix or "") .. suggestion

    self._current_line = new_before .. c.tail_after_cycle
    self._cursor_pos = #new_before + 1
    self:_redraw_line()
end

---Primary input state machine
---@private
---@param data string
function ReplBuffer:_handle_raw_input(data)
    -- 1. Ctrl+C (Interrupt)
    if data == "\3" then
        self:_reset_cycle()
        vim.api.nvim_chan_send(self._chan, "^C\r\n")
        self._current_line = ""
        self._cursor_pos = 1
        self:_redraw_line()
        return
    end

    -- 2. Enter (Submit)
    if data == "\r" or data == "\n" then
        local line = self._current_line
        self:_reset_cycle()
        vim.api.nvim_chan_send(self._chan, "\r\n")
        self._current_line = ""
        self._cursor_pos = 1
        self._history_idx = 0
        if line ~= "" and self._history[#self._history] ~= line then
            table.insert(self._history, line)
            if self._input_handler then self._input_handler(line) end
            vim.api.nvim_chan_send(self._chan, "\r\27[K" .. self._prompt)
        end
        return
    end

    -- 3. Tab (Bash Style Cycle)
    if data == "\t" then
        if #self._completion.cycle_list > 0 then
            self:_cycle_next()
            return
        end

        local is_at_end = self._cursor_pos > #self._current_line
        local char_after = self._current_line:sub(self._cursor_pos, self._cursor_pos)

        if is_at_end or char_after == " " then
            local left = self._current_line:sub(1, self._cursor_pos - 1)
            local right = self._current_line:sub(self._cursor_pos)

            self:on_complete(left, function(targets)
                if #targets == 0 then return end

                local items = {}
                for _, t in ipairs(targets) do
                    table.insert(items, type(t) == "table" and t.text or t)
                end

                self._completion.cycle_list = items
                self._completion.line_before_cycle = left
                self._completion.tail_after_cycle = right

                if #items > 1 then
                    local win_width = uitools.get_window_text_width()
                    local grid = strtools.format_grid(items, win_width)
                    -- Print grid above the prompt
                    vim.api.nvim_chan_send(self._chan, "\r\n" .. grid .. "\r\n")
                end

                self:_cycle_next()
            end)
        end
        return
    end

    -- Any other input breaks the completion cycle
    self:_reset_cycle()

    -- 4. History (Up/Ctrl+P, Down/Ctrl+N)
    if data == "\27[A" or data == "\16" then
        if #self._history > 0 and (self._history_idx == 0 or self._history_idx > 1) then
            self._history_idx = self._history_idx == 0 and #self._history or self._history_idx - 1
            self._current_line = self._history[self._history_idx]
            self._cursor_pos = #self._current_line + 1
            self:_redraw_line()
        end
        return
    elseif data == "\27[B" or data == "\14" then
        if self._history_idx > 0 then
            if self._history_idx < #self._history then
                self._history_idx = self._history_idx + 1
                self._current_line = self._history[self._history_idx]
            else
                self._history_idx = 0
                self._current_line = ""
            end
            self._cursor_pos = #self._current_line + 1
            self:_redraw_line()
        end
        return
    end

    -- 5. Navigation (Left/Right)
    if data == "\27[D" then -- Left
        if self._cursor_pos > 1 then self._cursor_pos = self._cursor_pos - 1 end
        self:_redraw_line()
        return
    elseif data == "\27[C" then -- Right
        if self._cursor_pos <= #self._current_line then self._cursor_pos = self._cursor_pos + 1 end
        self:_redraw_line()
        return
    end

    -- 6. Backspace
    if data == "\b" or data == string.char(127) then
        if self._cursor_pos > 1 then
            local left = self._current_line:sub(1, self._cursor_pos - 2)
            local right = self._current_line:sub(self._cursor_pos)
            self._current_line = left .. right
            self._cursor_pos = self._cursor_pos - 1
            self:_redraw_line()
        end
        return
    end

    -- 7. Regular Input (Splicing)
    if not data:find("^\27") then
        local left = self._current_line:sub(1, self._cursor_pos - 1)
        local right = self._current_line:sub(self._cursor_pos)
        self._current_line = left .. data .. right
        self._cursor_pos = self._cursor_pos + #data
        self:_redraw_line()
        return
    end
end

return ReplBuffer
