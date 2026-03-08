local M = {}

local Process = require("loop.tools.Process")
local uitools = require("loop.tools.uitools")
local simple_selector = require('loop.tools.simpleselector')
local uv = vim.loop

---@param cwd string? -- optional directory to start search
---@param query string -- user query for filtering (currently just passes through fd)
---@param callback fun(items:loop.SelectorItem[])
---@return fun() cancel -- optional cancel function
local function async_fd_search(cwd, query, callback)
    if not query or query == "" then
        return function()
        end
    end

    -- Build fd command
    local args = {"--type", "f", "--", query or "", cwd or ".", }

    local process = Process:new("fd", {
        cwd = vim.fn.getcwd(),
        cmd = "fd",
        args = args,
        on_output = function(data, is_stderr)
            if not is_stderr then
                local items = {}
                if data then
                    for line in data:gmatch("[^\r\n]+") do
                        ---@type loop.SelectorItem
                        local item = {
                            label = line,
                            file = line,
                            data = line,
                        }
                        table.insert(items, item)
                    end
                end
                -- Schedule callback after reading chunk
                if #items > 0 then
                    vim.schedule(function()
                        callback(items)
                        items = {}
                    end)
                end
            end
        end,
        on_exit = function(code, signal)
        end,
    })
    -- Return cancel function
    return function()
        process:kill()
    end
end

---@class loop.filepicker.opts
---@field cwd string

---@param opts loop.filepicker.opts
function M.select(opts)
    ---@type loop.selector.opts
    local selector_opts = {
        prompt = "Files",
        items = {
            { label = "File" },
        },
        file_preview = true,
        async_fetch = function(query, cb)
            return async_fd_search(opts and opts.cwd, query, cb)
        end

    }
    return simple_selector.select(selector_opts, function (path)
        if path then
            uitools.smart_open_file(path)
        end
    end)
end

return M
