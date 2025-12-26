local class = require('loop.tools.class')
local CompBuffer = require('loop.comp.CompBuffer')

---@class loop.comp.TermRepl : loop.comp.CompBuffer
local TermRepl = class(CompBuffer)

local COLORS = {
    RESET = "\27[0m",
    BOLD  = "\27[1m",
    GREEN = "\27[32m",
    BLUE  = "\27[34m",
    RED   = "\27[31m",
    CYAN  = "\27[36m",
}

function TermRepl:init(name)
    CompBuffer.init(self, "repl", name)
    self._chan = nil
    self._current_line = ""
    self._history = {}
    self._history_idx = 0
    self._prompt = COLORS.BOLD .. COLORS.GREEN .. "> " .. COLORS.RESET
end

---@param line string
function TermRepl:on_input(line)
    self:send_line(COLORS.CYAN .. "Processed: " .. COLORS.RESET .. line)
end

---@param line string
---@return string[]
function TermRepl:on_complete(line)
    return {}
end

function TermRepl:send_line(text)
    if self._chan then
        vim.api.nvim_chan_send(self._chan, text .. "\r\n")
    end
end

---Refreshes the current input line in the terminal
function TermRepl:_redraw_line()
    -- \r: carriage return, \27[K: clear line from cursor right
    vim.api.nvim_chan_send(self._chan, "\r\27[K" .. self._prompt .. self._current_line)
end

function TermRepl:_setup_buf()
    CompBuffer._setup_buf(self)
    self._chan = vim.api.nvim_open_term(self._buf, {
        on_input = function(_, _, _, data)
            self:_handle_raw_input(data)
        end
    })
    vim.api.nvim_chan_send(self._chan,
        COLORS.BOLD .. "REPL Ready (Arrows for history, Tab for complete)" .. COLORS.RESET .. "\r\n" .. self._prompt)
end

function TermRepl:_handle_raw_input(data)
    -- 1. Enter
    if data == "\r" or data == "\n" then
        local line = self._current_line
        self._current_line = ""
        self._history_idx = 0 -- Reset history navigation

        if line ~= "" and self._history[#self._history] ~= line then
            table.insert(self._history, line)
        end

        vim.api.nvim_chan_send(self._chan, "\r\n")
        self:on_input(line)
        vim.api.nvim_chan_send(self._chan, self._prompt)

        -- 2. Tab (Complete)
    elseif data == "\t" then
        local suggestions = self:on_complete(self._current_line)
        if #suggestions == 1 then
            self._current_line = suggestions[1]
            self:_redraw_line()
        elseif #suggestions > 1 then
            vim.api.nvim_chan_send(self._chan, "\r\n" .. table.concat(suggestions, "  ") .. "\r\n")
            self:_redraw_line()
        end

        -- 3. Arrow Keys (History)
        -- Up: \27[A, Down: \27[B
    elseif data == "\27[A" then -- Up
        if #self._history > 0 and (self._history_idx == 0 or self._history_idx > 1) then
            if self._history_idx == 0 then
                self._history_idx = #self._history
            else
                self._history_idx = self._history_idx - 1
            end
            self._current_line = self._history[self._history_idx]
            self:_redraw_line()
        end
    elseif data == "\27[B" then -- Down
        if self._history_idx > 0 then
            if self._history_idx < #self._history then
                self._history_idx = self._history_idx + 1
                self._current_line = self._history[self._history_idx]
            else
                self._history_idx = 0
                self._current_line = ""
            end
            self:_redraw_line()
        end

        -- 4. Backspace
    elseif data == "\b" or data == string.char(127) then
        if #self._current_line > 0 then
            self._current_line = self._current_line:sub(1, -2)
            vim.api.nvim_chan_send(self._chan, "\b \b")
        end

        -- 5. Regular Input
    else
        -- Simple check to ignore other escape sequences (like Left/Right arrows for now)
        if not data:find("^\27") then
            self._current_line = self._current_line .. data
            vim.api.nvim_chan_send(self._chan, data)
        end
    end
end

return TermRepl
