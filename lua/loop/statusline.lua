local M = {}

local _workspace_name = nil

---@param name string?
function M.set_workspace_name(name)
    _workspace_name = name
end

---@return string
function M.status()
    return _workspace_name and ("󰉖 " .. _workspace_name) or ""
end

return M
