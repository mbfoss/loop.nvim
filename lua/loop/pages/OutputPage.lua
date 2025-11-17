local Page = require('loop.pages.Page')
local strtools = require('loop.tools.strtools')
local class = require('loop.tools.class')

---@class loop.pages.OutputPage: loop.pages.Page
---@field new fun(self: loop.pages.OutputPage, name:string) : loop.pages.OutputPage
local OutputPage = class(Page)

---@param buf integer
---@param lines string[]
local function append_lines(buf, lines)
    lines = strtools.clean_and_split_lines(lines)
    local count = vim.api.nvim_buf_line_count(buf)
    -- If buffer is empty and first line is "", replace instead of append
    if count == 1 then
        local firstln = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        if firstln == "" then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, lines)
            return
        end
    end
    -- Otherwise, append at end
    vim.api.nvim_buf_set_lines(buf, count, count, false, lines)
end

---@param name string
function OutputPage:init(name)
    Page.init(self, "loop-output", name)
end

---@param lines string[]
function OutputPage:add_lines(lines)
    local buf = self:get_or_create_buf()

    vim.bo[buf].modifiable = true
    append_lines(buf, lines)
    vim.bo[buf].modifiable = false
end

return OutputPage
