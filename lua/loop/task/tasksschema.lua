local base_schema = {
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    title = "Loop Task Configuration",
    description = "Configuration file for loop.nvim tasks",
    type = "object",
    additionalProperties = false,
    required = { "tasks" },

    properties = {
        ["$schema"] = { type = "string" },

        tasks = {
            additionalProperties = false,
            type = "array",
            -- Providers will be used to populate this
            --items = {
            --    oneOf = { ... },
            --},
        },
    },
}

local base_items = {
    type = "object",
    additionalProperties = false,
    required = { "name", "type" },
    properties = {
        name = {
            type = "string",
            minLength = 1,
            description = "Non-empty unique task name"
        },
        type = { type = "string" }, -- no enum here anymore — dynamic!
        depends_on = {
            type = { "array", "null" },
            items = { type = "string", minLength = 1 }
        },
        depends_order = {
            type = "string",
            enum = { "sequence", "parallel" }
        },
        save_buffers = {
            type = { "boolean", "null" },
            description = "If true, ensures workspace buffers are saved before this task starts"
        },
    },
}

return { base_schema = base_schema, base_items = base_items }
