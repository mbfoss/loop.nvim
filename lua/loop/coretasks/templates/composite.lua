local field_order = { "name", "type", "save_buffers", "depends_on", "depends_order" }

---@type loop.taskTemplate[]
return {
    {
        name = "Sequence",
        task = {
            __order = field_order,
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
            __order = field_order,
            name = "Parallel",
            type = "composite",
            depends_on = { "", "" },
            depends_order = "parallel",
            save_buffers = nil,
        },
    },
}
