local M = {}

local config = require('loop.config')
local simple_selector = require('loop.tools.simpleselector')

local function _snacks_select(opts) -- opts: loop.selector.opts
    local picker = require("snacks.picker")
    local items = opts.items or {}
    if #items == 0 then
        opts.callback(nil)
        return
    end

    -- Prepare items for Snacks (keep original data + add fields Snacks likes)
    local picker_items         = vim.tbl_map(function(item)
        return {
            text  = item.label, -- used for fuzzy search & default display
            label = item.label,
            file  = item.file,
            lnum  = item.line, -- 1-based, Snacks uses lnum
            data  = item.data, -- what callback receives
            -- optional: you can add more if needed (e.g. icon, description, ...)
        }
    end, items)

    local has_custom_formatter = type(opts.formatter) == "function"
    local wants_file_preview   = opts.file_preview == true

    picker({
        title = opts.prompt or "Select",
        items = picker_items,
        supports_live = true, -- live fuzzy filtering on .text / label
        -- Display: just the label (like your format_item)
        format = function(item)
            return { { item.label } } -- single segment, implicit no hl group
        end,
        -- Custom preview logic matching your original selector
        preview = function(ctx)
            local item = ctx.item
            if not item then
                ctx.preview:reset()
                ctx.preview:set_lines({ "No selection" })
                return
            end

            local win = ctx.win
            local buf = ctx.buf

            -- Priority 1: custom formatter → scratch buffer with custom text
            if type(opts.formatter) == "function" then
                local ok, preview_text, ft = pcall(opts.formatter, item.data, item)
                if not ok then
                    preview_text = "Formatter error:\n" .. vim.inspect(preview_text)
                    ft = "text"
                end
                local lines = type(preview_text) == "string"
                    and vim.split(preview_text, "\n", { plain = true, trimempty = false })
                    or { "<empty preview>" }
                ctx.preview:clear()
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false
                vim.bo[buf].buftype = "nofile"
                if ft and ft ~= "" then
                    vim.bo[buf].filetype = ft
                end
                ctx.preview:set_title("Preview")
                return
            end

            -- Priority 2: file + line preview → load file into buffer and attach
            if opts.file_preview and item.file and item.lnum then
                local filepath = vim.fs.normalize(item.file)
                if vim.fn.filereadable(filepath) ~= 1 then
                    ctx.preview:reset()
                    ctx.preview:set_lines({
                        "File not readable:",
                        filepath,
                    })
                    ctx.preview:set_title("Preview: Error")
                    return
                end

                -- Load the file into the buffer
                local lines = vim.fn.readfile(filepath)
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false

                vim.bo[buf].buftype = "" -- normal buffer
                -- Clear existing namespace marks
                local ns_id = vim.api.nvim_create_namespace("LoopSelectorSnacksPreviewLine")
                pcall(vim.api.nvim_buf_clear_namespace, buf, ns_id, 0, -1)
                -- Highlight target line
                vim.api.nvim_buf_set_extmark(buf, ns_id, item.lnum - 1, 0, {
                    end_row = item.lnum,
                    hl_group = "Visual", -- or "PreviewTarget", etc.
                    hl_eol = true,
                })
                -- Position cursor at target line and center
                if win and vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_set_cursor(win, { item.lnum, 0 })
                    vim.api.nvim_win_call(win, function()
                        vim.cmd("normal! zz")
                    end)
                end
                ctx.preview:set_title(vim.fn.fnamemodify(filepath, ":t") .. ":" .. item.lnum)
                return
            end

            -- Fallback: empty preview
            vim.bo[buf].modifiable = true
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            vim.bo[buf].modifiable = false
            ctx.preview:set_title("No Preview")
        end,
        confirm = function(picker, item)
            picker:close()
            if item then
                opts.callback(item.data)
            else
                opts.callback(nil)
            end
        end,
        -- Optional: nice close keys matching your original
        win = {
            input = {
                keys = {
                    ["<Esc>"] = { "close", mode = { "i", "n" } },
                    ["<C-c>"] = { "close", mode = { "i", "n" } },
                },
            },
        },
    })
end

---@param opts loop.selector.opts
function M.select(opts)
    local type = config.current.selector
    if type == "builtin" then
        return simple_selector.select(opts)
    end
    if type == "snacks" then
        return _snacks_select(opts)
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
