local schema = {
    __name = "Command",
    required = { "command" },
    __order = { "name", "type", "command", "cwd", "save_buffers", "quickfix_matcher", "depends_on", "depends_order" },
    properties = {
        command = {
            description = "Command to run (string or array of strings).",
            oneOf = {
                { type = "string", minLength = 1 },
                {
                    type = "array",
                    minItems = 1,
                    items = { type = "string", minLength = 1 },
                },
                { type = "null" },
            },
        },

        cwd = {
            type = { "string", "null" },
            description = "working directory",
        },

        env = {
            type = { "object", "null" },
            additionalProperties = { type = "string" },
            description = "Optional environment variables",
        },

        quickfix_matcher = {
            type = { "string", "null" },
        },
    },
}

return schema
