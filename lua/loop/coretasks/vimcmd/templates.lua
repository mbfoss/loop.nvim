local field_order = { "name", "type", "command", "depends_on" }

---@type loop.taskTemplate[]
return {
    {
        name = "Message",
        task = {
            __order = field_order,
            name = "Notify",
            type = "vimcmd",
            command = "lua vim.notify('Hello world!')",
            depends_on = {},
        },
    },
}
