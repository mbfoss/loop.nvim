return {
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    title = "Loop Task Configuration",
    description = "Configuration file for loop.nvim tasks",
    type = "object",
    additionalProperties = false,
    required = { "tasks" },
    properties = {
        ["$schema"] = {
            type = "string"
        },
        tasks = {
            type = "array",
            items = {
                type = "object",
                additionalProperties = false,
                required = { "name", "type" },
                properties = {
                    name = {
                        type = "string",
                        minLength = 1,
                        description = "Non-empty unique task name (supports ${VAR} templates)"
                    },
                    type = {
                        type = "string",
                        enum = { "build", "run", "debug", "vimcmd", "composite" },
                        description = "Task category"
                    },
                    command = {
                        description =
                        "Command to run (string or array). Required for vimcmd/tool/app, optional for debug.",
                        oneOf = {
                            { type = "string", minLength = 1 },
                            {
                                type = "array",
                                minItems = 1,
                                items = { type = "string", minLength = 1 }
                            },
                            { type = "null" }
                        }
                    },
                    cwd = {
                        type = { "string", "null" },
                        description = "Optional working directory (supports ${VAR} templates)"
                    },
                    env = {
                        type = { "object", "null" },
                        additionalProperties = { type = "string" },
                        description = "Optional environment variables"
                    },
                    quickfix_matcher = {
                        type = { "string", "null" },
                        description = "Optional quickfix matcher name"
                    },
                    depends_on = {
                        type = { "array", "null" },
                        items = { type = "string", minLength = 1 },
                        description = "Optional list of dependent task names"
                    },
                    debug_adapter = {
                        type = { "string", "null" },
                        description = "Required for type = 'debug'. Name of the debug adapter."
                    },
                    debug_request = {
                        type = { "string", "null" },
                        enum = { "launch", "attach" },
                    },
                    debug_args = {
                        type = { "object", "null" },
                        additionalProperties = true
                    }
                }
            }
        }
    }
}
