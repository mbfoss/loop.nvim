---@type loop.taskTemplate[]
return {
    {
        name = "Sequence",
        task = {
            name = "Sequence",
            type = "composite",
            depends_on = { "", "" },
            depends_order = "sequence",
            save_buffers = nil,
        },
    },
    {
        name = "Parallel",
        task = {
            name = "Parallel",
            type = "composite",
            depends_on = { "", "" },
            depends_order = "parallel",
            save_buffers = nil,
        },
    },
}
