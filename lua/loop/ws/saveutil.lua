local M = {}

local notifications = require('loop.notifications')
local uitools = require('loop.tools.uitools')
local strtools = require('loop.tools.strtools')

---@param root string
---@param path string
local function _have_hidden_part(root, path)
    root = vim.fs.normalize(root)
    path = vim.fs.normalize(path)
    -- We walk up from the file to the root. If ANY parent (or the file itself)
    -- has a basename starting with a dot, it is hidden.
    local is_hidden = false
    -- Check the file itself first
    if vim.fs.basename(path):sub(1, 1) == "." then
        is_hidden = true
    else
        -- Check all parents up to the root
        for parent in vim.fs.parents(path) do
            if vim.fs.basename(parent):sub(1, 1) == "." then
                is_hidden = true
                break
            end
            if parent == root then break end
        end
    end
    return is_hidden
end

---@param root string
---@param path string
local function _is_inside_folder(root, path)
    local is_inside = false
    if path == root then
        is_inside = true
    else
        for parent in vim.fs.parents(path) do
            if parent == root then
                is_inside = true
                break
            end
        end
    end
    return is_inside
end

---Generates and displays a notification for the save operation.
---@param saved_count number Total files saved.
---@param excluded_count number Total modified files skipped.
---@param saved_paths string[] List of relative paths that were saved.
local function report_save_results(saved_count, excluded_count, saved_paths)
    if saved_count == 0 and excluded_count == 0 then return end

    local lines = {}
    if saved_count > 0 then
        table.insert(lines, ("󰄵 Saved %d file%s:"):format(saved_count, saved_count == 1 and "" or "s"))
        for i = 1, math.min(saved_count, 5) do
            table.insert(lines, ("  • %s"):format(saved_paths[i]))
        end
        if saved_count > 5 then
            table.insert(lines, ("  … and %d more"):format(saved_count - 5))
        end
    end

    if excluded_count > 0 then
        table.insert(lines, ("✖ Excluded %d modified file%s via filter"):format(
            excluded_count, excluded_count == 1 and "" or "s"
        ))
    end

    local level = saved_count > 0 and vim.log.levels.INFO or vim.log.levels.WARN
    notifications.notify(lines, level)
end

---@param ws_info loop.ws.WorkspaceInfo
function M.save_workspace_buffers(ws_info)
    local filter = ws_info.config.save
    -- Resolve the physical project root
    local root_path = vim.fs.normalize(ws_info.root_dir)
    ---@diagnostic disable-next-line: undefined-field
    local real_root = vim.uv.fs_realpath(root_path)
    if not real_root then return 0 end

    local saved, excluded, saved_paths = 0, 0, {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not uitools.is_regular_buffer(bufnr) or not vim.bo[bufnr].modified then
            goto continue
        end

        local bname = vim.api.nvim_buf_get_name(bufnr)
        if bname == "" then goto continue end

        local norm_path = vim.fs.normalize(bname)
        ---@diagnostic disable-next-line: undefined-field
        local real_file_path = vim.uv.fs_realpath(norm_path)
        if not real_file_path then goto continue end

        local is_hidden = _have_hidden_part(real_root, real_file_path)
        if is_hidden then
            excluded = excluded + 1
            goto continue
        end

        local is_inside = _is_inside_folder(root_path, real_file_path)

        if not is_inside then
            excluded = excluded + 1
            goto continue
        end

        -- 3. SYMLINK CHECK
        -- If follow_symlinks is false, we ensure the paths are identical
        -- after normalization (handles case-sensitivity/slash differences)
        if not filter.follow_symlinks and (norm_path ~= vim.fs.normalize(real_file_path)) then
            excluded = excluded + 1
            goto continue
        end

        -- 4. GLOB FILTERS (Only string part remaining, required by glob logic)
        local inc = #filter.include > 0 and strtools.matches_any(norm_path, filter.include)
        local exc = #filter.exclude > 0 and strtools.matches_any(norm_path, filter.exclude)

        if (#filter.include > 0 and not inc) or exc then
            excluded = excluded + 1
            goto continue
        end

        -- 5. SAVE
        if pcall(function() vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end) end) then
            saved = saved + 1
            table.insert(saved_paths, vim.fs.basename(norm_path))
        else
            excluded = excluded + 1
        end

        ::continue::
    end

    report_save_results(saved, excluded, saved_paths)
    return saved
end

return M
