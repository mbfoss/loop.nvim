local M = {}

local uitools = require('loop.tools.uitools')
local projinfo = require("loop.projinfo")
local systools = require("loop.tools.systools")
local selector = require("loop.selector")

local _nofile_error = "No file: current buffer is not a regular saved file"

-- Fully async macros — each takes a callback: cb(value, err)
-- Return nothing directly — only call cb!

function M.home(cb)
    local home = os.getenv("HOME")
    if not home then
        return cb(nil, "Environment variable $HOME is not set")
    end
    cb(home)
end

function M.file(cb)
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return cb(nil, _nofile_error)
    end
    cb(vim.fn.expand("%:p"))
end

function M.filename(cb)
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return cb(nil, _nofile_error)
    end
    cb(vim.fn.expand("%:t"))
end

function M.fileext(cb)
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return cb(nil, _nofile_error)
    end
    local ext = vim.fn.expand("%:e")
    cb(ext ~= "" and ext or nil)
end

function M.fileroot(cb)
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return cb(nil, _nofile_error)
    end
    cb(vim.fn.expand("%:p:r"))
end

function M.filedir(cb)
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return cb(nil, _nofile_error)
    end
    cb(vim.fn.expand("%:p:h"))
end

function M.projdir(cb)
    local proj_dir = projinfo.proj_dir
    if not proj_dir then
        return cb(nil, "No active project")
    end
    cb(proj_dir)
end

function M.cwd(cb)
    cb(vim.fn.getcwd())
end

function M.filetype(cb)
    cb(vim.bo.filetype)
end

function M.tmpdir(cb)
    local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    cb(tmp)
end

function M.date(cb)
    cb(os.date("%F")) -- YYYY-MM-DD
end

function M.time(cb)
    cb(os.date("%T")) -- HH:MM:SS
end

function M.timestamp(cb)
    cb(os.date("%Y-%m-%dT%H:%M:%S"))
end

-- Async process selector (now works!)
M["select-pid"] = function(cb)
    local procs = systools.get_running_processes()
    if not procs or #procs == 0 then
        return cb(nil, "No processes found")
    end

    local choices = {}
    for _, proc in ipairs(procs) do
        table.insert(choices, {
            label = ("%8d | %s - %s"):format(proc.pid, proc.user or "unknown", proc.name or "unknown"),
            data = proc.pid,
        })
    end

    selector.select("Select process to attach", choices, nil, function(selected_pid)
        if selected_pid then
            cb(selected_pid)
        else
            cb(nil, "Process selection cancelled")
        end
    end)
end

return M
