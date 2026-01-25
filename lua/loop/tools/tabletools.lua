local M = {}

-- Persistent state across plugin reloads
_G.__LoopPluginPersistentState = _G.__LoopPluginPersistentState or {}
local state = _G.__LoopPluginPersistentState

state.ordered_table_marker = state.ordered_table_marker or {}
local ORDERED_TABLE_MARKER = state.ordered_table_marker

--- Creates a table that remembers insertion order of keys
--- @return table
function M.ordered_table()
    local data  = {} -- key → value
    local order = {} -- array of keys in insertion order
    local index = {} -- key → position in order (1-based)

    local proxy = {}

    local mt    = {
        __ordered_table = ORDERED_TABLE_MARKER,

        __index = function(_, key)
            return data[key]
        end,

        __newindex = function(_, key, value)
            local exists = data[key] ~= nil

            if value == nil then
                -- delete
                if exists then
                    local pos = index[key]
                    table.remove(order, pos)
                    index[key] = nil
                    data[key] = nil
                    -- fix positions of keys that came after
                    for i = pos, #order do
                        index[order[i]] = i
                    end
                end
            else
                -- insert or update
                if not exists then
                    order[#order + 1] = key
                    index[key] = #order
                end
                data[key] = value
            end
        end,

        __pairs = function()
            local i = 0
            return function()
                i = i + 1
                local key = order[i]
                if key then
                    return key, data[key]
                end
            end
        end,

        -- Most people expect #t = total number of entries
        __len = function()
            return #order
        end,

        -- Make misuse obvious
        __ipairs = function()
            error("ipairs() is not supported on ordered_table — use pairs() or M.tbl_keys()", 2)
        end,
    }

    -- Attach the order array in a controlled way
    mt.__order  = order -- we read it via rawget(getmetatable(t), "__order")

    return setmetatable(proxy, mt)
end

--- Checks if a value is an ordered table created by this module
--- @param t any
--- @return boolean
function M.is_ordered_table(t)
    if type(t) ~= "table" then return false end
    local mt = getmetatable(t)
    return mt and mt.__ordered_table == ORDERED_TABLE_MARKER
end

--- Get keys in **insertion order** (drop-in replacement / supplement for vim.tbl_keys)
--- Falls back to vim.tbl_keys() for regular tables
--- @param t table
--- @return table keys (array)
function M.tbl_keys(t)
    if not M.is_ordered_table(t) then
        return vim.tbl_keys(t) or {}
    end

    local mt = getmetatable(t)
    local order = rawget(mt, "__order")

    if not order then
        error("ordered_table internal structure missing (__order not found)", 2)
    end

    local keys = {}
    for i, k in ipairs(order) do
        keys[i] = k
    end
    return keys
end

--- Checks if value is a "normal" list-like table (not our ordered table)
--- @param t any
--- @return boolean
function M.is_list(t)
    return type(t) == "table"
        and not M.is_ordered_table(t)
        and (vim.islist and vim.islist(t) or true) -- safe fallback
end

return M
