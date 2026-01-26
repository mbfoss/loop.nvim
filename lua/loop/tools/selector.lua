local M = {}

local config = require('loop.config')
local simple_selector = require('loop.tools.simpleselector')

---@param opts loop.selector.opts
function M.select(opts)
    local type = config.current.selector
    if type == "builtin" then
        return simple_selector.select(opts)
    end

    vim.ui.select(opts.items, {
        prompt = opts.prompt,
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice ~= nil then -- false is a valid choice
            opts.callback(choice.data)
        end
    end)
end

return M
