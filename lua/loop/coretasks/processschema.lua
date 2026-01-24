local schema = {
    __name = "Command",
    description = "Executes a shell command as a task",
    required = { "command" },
    ["x-order"] = { "command", "cwd", "env", "quickfix_matcher" },

    properties = {
        command = {
            description =
            "Command to execute. Can be a single string, a list of arguments, or null to disable execution.",
            oneOf = {
                {
                    type = "string",
                    minLength = 1,
                    description = "Shell command executed as-is"
                },
                {
                    type = "array",
                    minItems = 1,
                    description = "Command with arguments, executed without shell interpolation",
                    items = {
                        type = "string",
                        minLength = 1,
                        description = "Command or argument token"
                    },
                },
                {
                    type = "null",
                    description = "No command execution"
                },
            },
        },

        cwd = {
            type = { "string", "null" },
            description = "Working directory used when executing the command"
        },

        env = {
            type = { "object", "null" },
            description = "Additional environment variables applied to the command execution",
            additionalProperties = {
                type = "string",
                description = "Environment variable value"
            },
        },

        quickfix_matcher = {
            type = { "string", "null" },
            description = "Name of a quickfix matcher used to parse command output into quickfix entries"
        },
    },
}

return schema
