local M = {}

local config = require('loop.config')

---@param text string|string[]
---@param level integer|nil One of the values from |vim.log.levels
function M.notify(text, level)
    if level and level < vim.log.levels.INFO then        
        M.log(text)
        return
    end
    -- In debug mode, also log INFO and above messages
    if config.current and config.current.debug and level and level >= vim.log.levels.INFO then
        M.log(text)
    end
    if type(text) == 'table' then
        local lines = {}
        for idx, str in ipairs(text) do
            table.insert(lines, str)
        end
        if #lines > 0 then
            lines[1] = "loop.nvim: " .. lines[1]
            vim.notify(table.concat(lines, '\n'), level)
        end
    else
        vim.notify("loop.nvim: " .. text, level)
    end
end

---@param text string|string[]
function M.log(text)
    if not text then return end
    
    local log_text = type(text) == 'table' and table.concat(text, '\n') or text
    local log_msg = "loop.nvim: " .. log_text
    
    -- Use vim.notify with DEBUG level for logging
    vim.notify(log_msg, vim.log.levels.DEBUG)
    
    -- Also write to Neovim's log file if available
    if vim.fn.has("nvim-0.10") == 1 then
        vim.schedule(function()
            vim.print(log_msg)
        end)
    end
end

return M
