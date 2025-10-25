local bpts = require('loop.dap.bpts')
local json = require('loop.tools.json')
local log = require('loop.tools.Logger').create_logger("breakpoints")

local M = {}

local setup_done = false
local _need_saving = false
local signs_group = "loopplugin_bp_signs"
local sign_for_breakpoint = "loopplugin_bp_sign"

local function remove_buf_signs(bufnr)
    log:log('removing all buffer signs')
    vim.fn.sign_unplace(signs_group, { buffer = bufnr })
end

local function add_buf_sign(bufnr, line)
    log:log({ 'adding buffer sign ', line })
    vim.fn.sign_place(
        line,                -- id (0 to auto-assign)
        signs_group,         -- group (can be any string)
        sign_for_breakpoint, -- name of the sign type (defined above)
        bufnr,               -- buffer number
        { lnum = line, priority = 10 }
    )
end

local function add_buf_signs(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    local file = vim.fn.fnamemodify(name, ":p")
    local bps = bpts.get_file_breakpoints(file)
    if bps then
        for _, v in pairs(bps) do
            add_buf_sign(bufnr, v.line)
        end
    end
end

local function get_loaded_bufnr(file)
    local bufnr = vim.fn.bufnr(file, false)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return bufnr
    end
    return -1
end

local function remove_file_sign(file, line)
    local bufnr = get_loaded_bufnr(file)
    if bufnr >= 0 then
        log:log({ 'removing buffer sign ', line })
        vim.fn.sign_unplace(signs_group, { buffer = bufnr, id = line })
    end
end

local function add_file_sign(file, line)
    local bufnr = get_loaded_bufnr(file)
    if bufnr >= 0 then
        add_buf_sign(bufnr, line)
    end
end

local function refresh_all_signs()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            remove_buf_signs(bufnr)
            add_buf_signs(bufnr)
        end
    end
end

local function remove_breakpoint(path, line)
    local file = vim.fn.fnamemodify(path, ":p")
    local removed = bpts.remove_file_breakpoint(file, line)
    if removed then
        remove_file_sign(file, line)
    end
    return removed
end

local function remove_all_breakpoints()
    local files = bpts.get_breakpoint_files()
    for _,file in ipairs(files) do
        local bps = bpts.get_file_breakpoints(file)
        bpts.remove_file_breakpoints(file)
        for _, b in ipairs(bps) do
            remove_file_sign(file, b.line)
        end
    end
end

local function add_breakpoint(path, line, condition, hitCondition, logMessage)
    local file = vim.fn.fnamemodify(path, ":p")
    local added = bpts.add_file_breakpoint(file, line, condition, hitCondition, logMessage)
    if added then
        add_file_sign(file, line)
    end
end

function M.toggle_breakpoint()
    local file = vim.fn.expand("%:p")
    if file == "" then
        return
    end
    _need_saving = true
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if not remove_breakpoint(file, lnum) then
        add_breakpoint(file, lnum)
    end
end


function M.reset()
    _need_saving = true
    remove_all_breakpoints()
end

function M.load_breakpoints(proj_config_dir)
    assert(setup_done)
    assert(proj_config_dir and type(proj_config_dir) == 'string')
    local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
    
    local loaded, data = json.load_from_file(breakpoints_file)
    if not loaded or type(data) ~= "table" then
        return false, data
    end
    for file, bps in pairs(data) do
        bpts.set_file_breakpoints(file, bps)
    end
    refresh_all_signs()
    _need_saving = false
    return true, nil
end

function M.save_breakpoints(proj_config_dir)
    assert(setup_done)
    if not _need_saving then
        return true
    end
    if proj_config_dir and type(proj_config_dir) == 'string' and vim.fn.isdirectory(proj_config_dir) == 1 then
        local data = {}
        local files = bpts.get_breakpoint_files()
        for _,file in ipairs(files) do
            data[file] = bpts.get_file_breakpoints(file)
        end
        local breakpoints_file = vim.fs.joinpath(proj_config_dir, 'breakpoints.json')
        return json.save_to_file(breakpoints_file, data)
    end
    _need_saving = false
    return true, nil
end

function M.setup(opts)
    assert(not setup_done, "setup alreay done")
    setup_done = true

    vim.fn.sign_define(sign_for_breakpoint, { text = '●', texthl = 'Debug' })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
        pattern = "*",
        callback = function(args)
            vim.fn.sign_unplace(signs_group, { buffer = args.buf })
        end,
    })

    -- After buffer is loaded (file read)
    vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function(args)
            add_buf_signs(args.buf)
        end,
    })

    -- When buffer is unloaded
    vim.api.nvim_create_autocmd("BufDelete", {
        callback = function(args)
            remove_buf_signs(args.buf)
        end,
    })
end

return M
