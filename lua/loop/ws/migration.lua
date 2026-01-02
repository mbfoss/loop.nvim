local M = {}

---@class loop.ws.Migration
---@field from_version string|number
---@field to_version string|number
---@field migrate fun(config: table): table, string|nil

---@type loop.ws.Migration[]
local migrations = {}

--- Register a migration function
---@param from_version string|number
---@param to_version string|number
---@param migrate_fn fun(config: table): table, string|nil
function M.register_migration(from_version, to_version, migrate_fn)
    table.insert(migrations, {
        from_version = tostring(from_version),
        to_version = tostring(to_version),
        migrate = migrate_fn,
    })
end

--- Get the current schema version
---@return string
function M.get_current_version()
    return "1.0"
end

--- Migrate a workspace configuration to the current version
---@param config table The workspace configuration
---@return table migrated_config, string|nil error
function M.migrate_config(config)
    local current_version = M.get_current_version()
    local config_version = tostring(config.version or "0.0")
    
    if config_version == current_version then
        return config, nil
    end
    
    -- Sort migrations by version
    table.sort(migrations, function(a, b)
        return a.from_version < b.from_version
    end)
    
    local current_config = vim.deepcopy(config)
    local current_ver = config_version
    
    -- Apply migrations in sequence
    for _, migration in ipairs(migrations) do
        if current_ver == migration.from_version then
            local migrated, err = migration.migrate(current_config)
            if err then
                return nil, "Migration from " .. migration.from_version .. " to " .. migration.to_version .. " failed: " .. err
            end
            current_config = migrated
            current_config.version = migration.to_version
            current_ver = migration.to_version
            
            -- If we've reached the current version, stop
            if current_ver == current_version then
                break
            end
        end
    end
    
    -- Ensure version is set
    if current_config.version ~= current_version then
        return nil, "Could not migrate from version " .. config_version .. " to " .. current_version
    end
    
    return current_config, nil
end

--- Check if a config needs migration
---@param config table
---@return boolean needs_migration, string|nil current_version
function M.needs_migration(config)
    local current_version = M.get_current_version()
    local config_version = tostring(config.version or "0.0")
    return config_version ~= current_version, config_version
end

return M

