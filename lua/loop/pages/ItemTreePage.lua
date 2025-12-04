local class = require('loop.tools.class')
local Page = require('loop.pages.Page')
local Trackers = require("loop.tools.Trackers")

---@class loop.pages.ItemTreePage.Highlight
---@field group string
---@field start_col number|nil 0-based
---@field end_col number|nil 0-based

---@class loop.pages.ItemTreePage.Item
---@field id number
---@field data any
---@field parent number|nil
---@field children nil|loop.pages.ItemTreePage.Item[]|fun(cb:fun(items:loop.pages.ItemTreePage.Item[])) -- ← now also accepts function
---@field expanded boolean|nil
---@field formatter_override string|nil  -- internal temporary override for loading/error messages

---@class loop.pages.ItemTreePage.TrackerCallbacks
---@field on_selection fun(item:loop.pages.ItemTreePage.Item|nil)

---@class loop.pages.ItemTreePage.InitArgs
---@field formatter fun(item:loop.pages.ItemTreePage.Item):string
---@field highlighter nil|fun(item:loop.pages.ItemTreePage.Item):loop.pages.ItemTreePage.Highlight[]
---@field expand_char string?
---@field collapse_char string?
---@field indent_string string?
---@field loading_text string?  -- ← new optional field

---@class loop.pages.ItemTreePage : loop.pages.Page
---@field new fun(self: loop.pages.ItemTreePage, name:string, args:loop.pages.ItemTreePage.InitArgs): loop.pages.ItemTreePage
local ItemTreePage = class(Page)

local NS = vim.api.nvim_create_namespace('LoopPluginItemTreePage')

---@param name string
---@param args loop.pages.ItemTreePage.InitArgs
function ItemTreePage:init(name, args)
    assert(args.formatter, "formatter is required")
    Page.init(self, "tree", name)

    self.expand_char = args.expand_char or "▸"
    self.collapse_char = args.collapse_char or "▾"
    self.indent_string = args.indent_string or " "
    self.loading_text = args.loading_text or "Loading..."

    self._trackers = Trackers:new()

    -- keymaps unchanged
    local function on_select()
        local item = self:get_cur_item()
        if item and item.children then
            self:toggle_expand(item.id)
        else
            self._trackers:invoke("on_selection", item)
        end
    end

    local function on_toggle()
        local item = self:get_cur_item()
        if item and item.children then
            self:toggle_expand(item.id)
        end
    end

    self:add_keymap('<CR>', { callback = on_select, desc = "Select or expand/collapse" })
    self:add_keymap('<2-LeftMouse>', { callback = on_select, desc = "Select or expand/collapse" })
    self:add_keymap('zo', { callback = on_toggle, desc = "Expand node" })
    self:add_keymap('zc', { callback = on_toggle, desc = "Collapse node" })
    self:add_keymap('za', { callback = on_toggle, desc = "Toggle expand/collapse" })
end

---------------------------------------------------------
-- PUBLIC TRACKER API (unchanged)
---------------------------------------------------------

function ItemTreePage:add_tracker(cb) return self._trackers:add_tracker(cb) end

function ItemTreePage:remove_tracker(id) return self._trackers:remove_tracker(id) end

function ItemTreePage:set_items(items)
end

---------------------------------------------------------
-- PUBLIC: upsert_item (same API, optimized render)
---------------------------------------------------------

function ItemTreePage:upsert_item(item)
end

function ItemTreePage:toggle_expand(id)
end

--
function ItemTreePage:expand(id)
end

function ItemTreePage:collapse(id)
end

---------------------------------------------------------
-- Public API: getters (unchanged)
---------------------------------------------------------

function ItemTreePage:get_item(id)
end

function ItemTreePage:get_all_items()
end

-- Find current item using extmarks (instead of _flat)
function ItemTreePage:get_cur_item()
end

return ItemTreePage
