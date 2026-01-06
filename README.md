# loop.nvim

**Workspace and Task Management for Neovim**

---

> **Work in Progress:** This plugin is in early development. Commands, interface, and APIs may change frequently as features evolve.

## Features

- **Automatic Workspace Detection:** Projects are recognized via a `.nvimloop` directory.
- **Structured, Dependency-Aware Tasks:** Define build, run, vimcmd, or composite tasks with dependencies and parallel/sequential execution.
- **Quickfix Integration:** Compiler output is parsed into the quickfix list for easy navigation.
- **Macro System:** Use `${macro}` variable substitution for dynamic commands.
- **Workspace Variables:** Manage per-project variables with `:Loop var`.
- **Optional Per-Workspace Persistence:** Isolate shada (history, marks) and undo data per workspace.
- **Extensible:** Add new task types and integrations via plugins (e.g. [loop-cmake.nvim](https://github.com/mbfoss/loop-cmake.nvim)).
- **UI Window:** Built-in interface for managing tasks and viewing output.

## Requirements

- **Neovim** >= 0.10

## Installation

**With lazy.nvim**
```lua
{
    "mbfoss/loop.nvim",
    event = "VimEnter",
}
```

**With packer.nvim**
```lua
use {
    'mbfoss/loop.nvim',
    event = "VimEnter",
}
```

After installation, generate helptags with `:helptags ALL` for documentation.

## Quick Start

1. `:Loop workspace create` — Initialize a workspace in your project.
2. `:Loop workspace open` — Open the workspace in the current directory.
3. `:Loop task add build` — Add a build task (or other types).
4. `:Loop task run` — Run a task (choose from a list).
5. `:Loop var add` — Add workspace variables (optional).
6. `:Loop show` — Open the Loop UI window.

Workspace auto opens when starting Neovim without any arguments in a workspace directory.
You can display the current workspace in your statusline:
Example with `lualine`:
```lua
lualine_c = { function() return require('loop.wsinfo').status_line() end, 'filename' }
```

## Task Types

- **build:** Run build commands with quickfix parsing (e.g. `make`, `gcc`).
- **run:** Start long-running processes (e.g. servers).
- **vimcmd:** Execute Neovim commands or Lua code.
- **composite:** Combine multiple tasks, run in sequence or parallel.

Example build task:
```json
{
  "name": "Build",
  "type": "build",
  "command": "make",
  "cwd": "${wsdir}"
}
```

## Macro Reference

Loop tasks support powerful macro expansion for dynamic commands and paths.  
Use macros in your task definitions as `${macro}` or `${macro:arg}`.

| Macro                | Description                                 | Example Value                |
|----------------------|---------------------------------------------|------------------------------|
| `${wsdir}`           | Workspace root directory                    | `/path/to/project`           |
| `${cwd}`             | Current working directory                   | `/path/to/current`           |
| `${file}`            | Full path of current file                   | `/path/to/file.txt`          |
| `${filename}`        | Current filename                            | `file.txt`                   |
| `${fileroot}`        | File path without extension                 | `/path/to/file`              |
| `${filedir}`         | Directory of current file                   | `/path/to`                   |
| `${fileext}`         | File extension                              | `txt`                        |
| `${filetype}`        | Current buffer filetype                     | `python`                     |
| `${home}`            | User home directory                         | `/home/user`                 |
| `${tmpdir}`          | System temp directory                       | `/tmp`                       |
| `${date}`            | Current date (YYYY-MM-DD)                   | `2024-01-15`                 |
| `${time}`            | Current time (HH:MM:SS)                     | `14:30:00`                   |
| `${timestamp}`       | ISO timestamp                               | `2024-01-15T14:30:00`        |
| `${env:NAME}`        | Environment variable                        | Value of `$NAME`             |
| `${var:NAME}`        | Workspace variable                          | Value of user variable       |
| `${prompt:Message}`  | Prompt user for input                       | ...                          |

You can also use type-restricted macros (e.g. `${file:lua}`), prompt with defaults (`${prompt:Port,8000}`), or apply Lua string substitutions to variables.

## Extending

Extensions can add new task providers, automatic task generation, or deeper tool integration.

Author extensions:
- [loop-debug.nvim](https://github.com/mbfoss/loop-debug.nvim) for Debug tasks
- [loop-cmake.nvim](https://github.com/mbfoss/loop-cmake.nvim) for CMake integration

## Documentation

See `:help loop` or [doc/loop.txt](doc/loop.txt) for full usage, configuration, macros, variables, and advanced features.

## License

MIT