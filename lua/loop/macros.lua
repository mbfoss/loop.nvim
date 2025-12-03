local M = {}

local uitools = require('loop.tools.uitools')
local project = require('loop.project')

local _nofile_error = "No file: current buffer is not a regular saved file"

function M.home()
    local home = os.getenv("HOME")
    if not home then
        return nil, "Environment variable $HOME is not set"
    end
    return home
end

function M.file()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return nil, _nofile_error
    end
    return vim.fn.expand("%:p")
end

function M.filename()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return nil, _nofile_error
    end
    return vim.fn.expand("%:t")
end

function M.fileext()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return nil, _nofile_error
    end
    local ext = vim.fn.expand("%:e")
    return ext ~= "" and ext or nil -- return nil if no extension
end

function M.fileroot()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return nil, _nofile_error
    end
    return vim.fn.expand("%:p:r")
end

function M.filedir()
    if not uitools.is_regular_buffer(vim.api.nvim_get_current_buf()) then
        return nil, _nofile_error
    end
    return vim.fn.expand("%:p:h")
end

function M.projdir()
    local proj_dir = project.get_proj_dir()
    if not proj_dir then
        return nil, "No active project"
    end
    return proj_dir
end

function M.cwd()
    return vim.fn.getcwd()
end

function M.filetype()
    return vim.bo.filetype
end

function M.tmpdir()
    local tmp = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return tmp
end

function M.date()
    return os.date("%F") -- YYYY-MM-DD
end

function M.time()
    return os.date("%T") -- HH:MM:SS
end

function M.timestamp()
    return os.date("%Y-%m-%dT%H:%M:%S")
end

return M
