---@type loop.WorkspaceConfig
return {
    __order = {"version", "name", "save", "isolation"},
    version = "1.0",
    name = "",
    save = {
        __order = {"include", "exclude", "follow_symlinks"},
        include = { "**/*" },
        exclude = { },
        follow_symlinks = false,
    },
    --variables = vim.empty_dict()
}
