# loop.nvim

**Workspace and Task Management for Neovim**

---

> **Work in Progress:** Early development, not ready for public release.

## Features

- Project workspaces auto-detected via `.nvimloop`
- Structured, dependency-aware tasks (build, run, vimcmd, composite)
- Quickfix integration for compiler output
- Macro system: `${macro}` variable substitution
- Workspace variables via `:Loop var`
- Optional per-workspace persistence (shada, undo)
- Extensible via plugins (e.g. [loop-cmake.nvim](https://github.com/mbfoss/loop-cmake.nvim))

## Requirements

- Neovim >= 0.10

## Installation

**lazy.nvim**
```lua
{
    "mbfoss/loop.nvim",
    cmd = { "Loop" },
    config = function()
        require("loop").setup({})
    end
}
```

**packer.nvim**
```lua
use {
    'mbfoss/loop.nvim',
    config = function()
        require('loop').setup()
    end
}
```

## Quick Start

1. `:Loop workspace create` — Initialize workspace in your project
1. `:Loop workspace open` — One the workspace in the current working
2. `:Loop task add build` — Add a build task
3. `:Loop task run` — Run a task (choose from list)
4. `:Loop var add` — Add workspace variables (optional)
5. `:Loop show` — Open the Loop UI

## Extending

Install extensions for more task types or templates, e.g.:
- [loop-cmake.nvim](https://github.com/mbfoss/loop-cmake.nvim) for CMake integration

## Documentation

See `:help loop` or [doc/loop.txt](doc/loop.txt) for full usage, configuration, macros, variables, and advanced features.

## License

MIT
