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

            -- We'll always create/attach a fresh buffer
            local buf -- will hold the buffer number we attach

            -- Priority 1: custom formatter (opts.formatter) → scratch buffer with custom text
            if type(opts.formatter) == "function" then
                local ok, preview_text, ft = pcall(opts.formatter, item.data, item)
                if not ok then
                    preview_text = "Formatter error:\n" .. vim.inspect(preview_text)
                    ft = "text"
                end

                local lines = type(preview_text) == "string"
                    and vim.split(preview_text, "\n", { plain = true, trimempty = false })
                    or { "<empty preview>" }

                -- Create scratch buffer
                buf = vim.api.nvim_create_buf(false, true) -- nomodifiable, wipe on hide
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

                -- Set options
                vim.bo[buf].buftype    = "nofile"
                vim.bo[buf].bufhidden  = "wipe"
                vim.bo[buf].swapfile   = false
                vim.bo[buf].modifiable = false -- optional: prevent accidental edits

                if ft and ft ~= "" then
                    vim.bo[buf].filetype = ft
                end

                -- Attach to preview window
                ctx.preview:set_buf(buf)

                -- Optional: set title
                ctx.preview:set_title("Preview")

                return
            end

            -- Priority 2: file + line preview → load file into a buffer and attach
            if opts.file_preview and item.file and item.lnum then
                local filepath = vim.fs.normalize(item.file)

                if vim.fn.filereadable(filepath) ~= 1 then
                    buf = vim.api.nvim_create_buf(false, true)
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                        "File not readable:",
                        filepath,
                    })
                    vim.bo[buf].filetype = "text"
                    vim.bo[buf].buftype = "nofile"
                    vim.bo[buf].bufhidden = "wipe"
                    ctx.preview:set_buf(buf)
                    ctx.preview:set_title("Preview: Error")
                    return
                end

                -- Use existing buffer if possible (avoids reload if already open)
                buf = vim.fn.bufadd(filepath) -- adds to buffer list if not present
                vim.fn.bufload(buf)           -- ensure content is loaded

                -- Ensure sane options
                vim.bo[buf].buftype   = ""    -- normal file buffer
                vim.bo[buf].bufhidden = 'delete'
                vim.bo[buf].swapfile  = false -- optional
                -- filetype is auto-detected on load, but you can force:
                -- vim.bo[buf].filetype = vim.filetype.match({ filename = filepath }) or "text"

                -- Attach
                ctx.preview:set_buf(buf)

                local ns_id = vim.api.nvim_create_namespace("LoopSelectorSnacksPreviewLine")
                pcall(vim.api.nvim_buf_clear_namespace, buf, ns_id, 0, -1)
                vim.api.nvim_buf_set_extmark(buf, ns_id, item.lnum - 1, 0, {
                    end_row = item.lnum,
                    hl_group = "Visual", -- or "PreviewTarget", "CursorLineNr", etc.
                    hl_eol = true,
                })
                
                -- Position cursor at target line (1-based)
                local win = ctx.preview.win.win -- assuming preview exposes .win (common pattern)
                if win and vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_set_cursor(win, { item.lnum, 0 })
                    vim.api.nvim_win_call(win, function()
                        vim.cmd("normal! zz") -- center line
                    end)
                end

                -- Optional title
                ctx.preview:set_title(vim.fn.fnamemodify(filepath, ":t") .. ":" .. item.lnum)

                return
            end

            -- Fallback: empty scratch buffer
            buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].bufhidden = "wipe"
            ctx.preview:set_buf(buf)
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

        -- Layout suggestion: use vertical or ivy for better preview space
        --layout = { preset = "vertical" }, -- or "ivy", "default", or custom table

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
