local base_schema = {
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    title = "Loop Task Configuration",
    type = "object",
    additionalProperties = false,
    required = { "tasks" },

    properties = {
        ["$schema"] = {
            type = "string",
        },
        tasks = {
            type = "array",
            description = "List of task definitions",
            additionalProperties = false,
            items = {
                description = "Single task definition entry",
                -- Providers will populate this with concrete task schemas
                oneOf = vim.empty_dict(),
            },
        },
    },
}

local base_items = {
    type = "object",
    description = "Task properties",
    additionalProperties = false,
    required = { "name", "type" },
    ["x-order"] = { "name", "type", "concurrency", "depends_on", "depends_order", "save_buffers" },

    properties = {
        name = {
            type = "string",
            minLength = 1,
            description = "Unique, non-empty name for the task"
        },

        type = {
            type = "string",
            description = "Task type"
        },

        concurrency = {
            type = "string",
            description =
            "Action to take if the task is already running\nrestart: Stop the existing task and start a new one\nrefuse: The new task is not started\nparallel: A new instance of the task is started in parallel",
            enum = { "restart", "refuse", "parallel" }
        },

        stop_dependants = {
            type = { "boolean", "null" },
            description = "Stop any running task that depends on this task before starting"
        },

        depends_on = {
            type = { "array", "null" },
            description = "List of task names that must complete before this task runs",
            items = {
                type = "string",
                minLength = 1,
                description = "Referenced task name"
            }
        },

        depends_order = {
            type = "string",
            description = "Execution order for dependencies",
            enum = { "sequence", "parallel" }
        },

        save_buffers = {
            type = { "boolean", "null" },
            description = "If true, saves all modified workspace buffers before executing this task"
        },
    },
}

return {
    base_schema = base_schema,
    base_items = base_items,
}
