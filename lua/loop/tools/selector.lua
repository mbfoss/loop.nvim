local M = {}

local config = require('loop.config')
local simple_selector = require('loop.tools.simpleselector')

---@param prompt string The prompt/title to display
---@param items loop.SelectorItem[] List of items with label and data table
---@param previewer (fun(data:any):string,string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
function M.select(prompt, items, previewer, callback)
    local type = config.current.selector
    if type == "builtin" then
        return simple_selector.select(prompt, items, previewer, callback)
    end

    vim.ui.select(items, {
        prompt = prompt,
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice ~= nil then -- false is a valid choice
            callback(choice.data)
        end
    end)
end

return M
