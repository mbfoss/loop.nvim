---@class loop.SelectorItem
---@field label string The display label in the picker
---@field data any The data associated with the item

---@alias loop.SelectorCallback fun(data:any): nil

local M = {}

local pickers = nil
local finders = nil
local previewers = nil
local conf = nil
local actions = nil
local action_state = nil

--- Fallback native selector using vim.ui.select (Neovim 0.6+)
--- @param prompt string
--- @param items loop.SelectorItem[]
--- @param callback fun(item: loop.SelectorItem|nil)
local function default_select(prompt, items, callback)
    local labels = {}
    for _, item in ipairs(items) do
        table.insert(labels, item.label)
    end
    vim.ui.select(labels, {
        prompt = prompt,
    }, function(selected_label)
        if not selected_label then
            callback(nil)
            return
        end
        for _, item in ipairs(items) do
            if item.label == selected_label then
                callback(item.data)
                return
            end
        end
        callback(nil)
    end)
end
-- Load Telescope modules only if available
local function load_telescope()
    local ok1, p = pcall(require, "telescope.pickers")
    local ok2, f = pcall(require, "telescope.finders")
    local ok3, pr = pcall(require, "telescope.previewers")
    local ok4, c = pcall(require, "telescope.config")
    local ok5, a = pcall(require, "telescope.actions")
    local ok6, ast = pcall(require, "telescope.actions.state")
    if ok1 and ok2 and ok3 and ok4 and ok5 and ok6 then
        pickers = p
        finders = f
        previewers = pr
        conf = c.values
        actions = a
        action_state = ast
        return true
    end
    return false
end
--- Use Telescope to show the selector
---@param prompt string The prompt title
---@param items loop.SelectorItem[] List of items
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback fun(data:any|nil) Called with selected item or nil
local function telescope_select(prompt, items, formatter, callback)
    -- Ensure Telescope is loaded
    if not (pickers and finders and previewers and conf and actions and action_state) then
        return
    end
    local previewer
    if formatter then
        previewer = previewers.new_buffer_previewer({
            title = "Details",
            --- @param self table
            --- @param entry table
            --- @param status table
            define_preview = function(self, entry, status)
                -- Format and split data into lines
                local formatted = formatter(entry.value.data)
                local lines = vim.split(formatted, "\n")
                -- Set lines in the preview buffer
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                -- Set JSON filetype for syntax highlighting
                vim.bo[self.state.bufnr].filetype = "json"
                -- Enable line wrapping in this buffer's window
                local win = self.state.winid
                assert(win and win > 0)
                vim.wo[win].wrap = true
                vim.wo[win].linebreak = true
                vim.wo[win].foldmethod = "indent"
                vim.wo[win].spell = false
            end,
        })
    end
    pickers.new({}, {
        prompt_title = prompt,
        finder = finders.new_table({
            results = items,
            --- @param entry loop.SelectorItem
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.label,
                    ordinal = entry.label,
                }
            end,
        }),
        previewer = previewer,
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            -- Replace default select action
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local item = selection and selection.value or nil
                if item and callback then
                    callback(item.data)
                end
            end)
            -- Optional: allow <C-c> to cancel
            map("i", "<C-c>", function()
                actions.close(prompt_bufnr)
                if callback then callback(nil) end
            end)
            return true
        end,
    }):find()
end

-- Load Snacks.nvim picker if available
local function load_snacks()
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks and snacks.picker then
        return true
    end
    return false
end

-- Use Snacks.nvim picker as fallback
---@param prompt string
---@param items loop.SelectorItem[]
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback
local function snacks_select(prompt, items, formatter, callback)
    local snacks = require("snacks")

    -- Map items for Snacks.nvim
    local snack_items = {}
    for _, item in ipairs(items) do
        table.insert(snack_items, {
            text = item.label,
            value = item,
            file = ""
        })
    end

    local previewer
    if formatter then
        previewer = function(ctx)
            local jsonstr = formatter(ctx.item.value.data)
            vim.bo[ctx.buf].modifiable = true
            vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, vim.split(jsonstr, "\n"))
            vim.bo[ctx.buf].modifiable = false
            vim.bo[ctx.buf].filetype = "json"
            return true
        end
    end

    -- Show the picker
    snacks.picker({
        title = prompt,
        items = snack_items,
        format = "text",
        preview = previewer,
        confirm = function(picker, item)
            vim.schedule(function()
                picker:close()
                if callback and item and item.value then
                    callback(item.value.data)
                end
            end)
        end
    })
end

--- Select an item from a list with label and data preview.
--- Uses Telescope if available; otherwise falls back to a simple native picker.
---@param prompt string The prompt/title to display
---@param items loop.SelectorItem[] List of items with label and data table
---@param formatter (fun(data:any):string)|nil Convert the data into text for display in the preview
---@param callback loop.SelectorCallback Called with selected item or nil if cancelled
function M.select(prompt, items, formatter, callback)
    -- Input validation
    if type(prompt) ~= "string" or prompt == "" then
        prompt = "Select an item"
    end
    if not items or #items == 0 then
        if callback then callback(nil) end
        return
    end
    if type(callback) ~= "function" then
        error("selector_menu.select: callback must be a function")
    end
    -- Validate item structure
    for i, item in ipairs(items) do
        if type(item) ~= "table" or type(item.label) ~= "string" or type(item.data) == "nil" then
            error(string.format("selector_menu.select: item %d must have .label (string) and .data (non-nil)", i))
        end
    end
    if load_telescope() then
        telescope_select(prompt, items, formatter, callback)
    elseif load_snacks() then
        snacks_select(prompt, items, formatter, callback)
    else
        default_select(prompt, items, callback)
    end
end

return M
