# loop.nvim

<p align="center">
  <strong>Workspace and Task Management for Neovim.</strong>
</p>

<p align="center">
  <a href="https://neovim.io/">
    <img src="https://img.shields.io/badge/Neovim-0.10+-blueviolet.svg?style=flat-square&logo=neovim" alt="Neovim 0.10+">
  </a>
  <a href="https://github.com/mbfoss/loop.nvim/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="MIT License">
  </a>
</p>

---

> [!WARNING]
> **Work in Progress**: This plugin is in early development and not ready for public release yet.

## Introduction

**loop.nvim** is a workspace and task management system for Neovim. It provides structured task definitions, dependency resolution, and execution directly from your editor using project-specific configurations stored in `.nvimloop` directories.

### Features

- **Workspace Management**: Auto-detects and loads configurations from `.nvimloop` directories
- **Task Scheduling**: Dependency resolution with parallel/sequential execution
- **Task Types**: Build, run, vimcmd, and composite tasks
- **Quickfix Integration**: Parses compiler output (GCC, Clang, luacheck, cargo, go, tsc) into quickfix
- **Macro System**: Variable substitution using `${macro}` syntax
- **UI Management**: Window and page management for task outputs
- **Variables**: Custom workspace variables via `:Loop var`

---

## Requirements

- Neovim >= **0.10**

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "mbfoss/loop.nvim",
    cmd = { "Loop" },
    config = function()
        require("loop").setup({})
    end
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'mbfoss/loop.nvim',
    config = function()
        require('loop').setup()
    end
}
```

---

## Configuration

### Global Setup

```lua
require("loop").setup({
    selector = "builtin",
    persistence = {
        shada = false,
        undo = false,
    },
    window = {
        symbols = {
            change  = "●",
            success = "✓",
            failure = "✗",
            waiting = "⧗",
            running = "▶",
        },
    },
    macros = {},
    autosave_interval = 5,
    logs_count = 50,
})
```

### Workspace Configuration

Workspaces are stored in `.nvimloop` directories containing:
- `workspace.json` - Workspace configuration
- `tasks.json` - Task definitions
- Provider-specific configuration files

Workspaces auto-load on `VimEnter` when `.nvimloop` is detected.

---

## Usage

### Workspace Commands

| Command | Description |
|---------|-------------|
| `:Loop workspace create` | Initialize a new workspace |
| `:Loop workspace open` | Open workspace from current directory |
| `:Loop workspace info` | Display workspace information |
| `:Loop workspace configure` | Open/edit workspace configuration |
| `:Loop workspace save` | Save workspace buffers |

### Task Commands

| Command | Description |
|---------|-------------|
| `:Loop task run [name]` | Run a task (opens selector if name omitted) |
| `:Loop task repeat` | Repeat the last executed task |
| `:Loop task add [type]` | Create a new task |
| `:Loop task configure` | Open tasks configuration |
| `:Loop task configure [type]` | Configure a task provider |
| `:Loop task terminate` | Stop all running tasks |

### UI Commands

| Command | Description |
|---------|-------------|
| `:Loop toggle` | Toggle Loop UI window |
| `:Loop show` | Show Loop UI window |
| `:Loop hide` | Hide Loop UI window |
| `:Loop page switch` | Switch between output pages |
| `:Loop page open [group] [page]` | Open a specific page |

### Other Commands

| Command | Description |
|---------|-------------|
| `:Loop var add` | Create a new variable |
| `:Loop var configure` | Configure variables |
| `:Loop logs` | Show recent logs |

---

## Task Types

### Build Tasks

Execute shell commands with quickfix parsing.

```json
{
  "name": "Build",
  "type": "build",
  "command": "make",
  "cwd": "${wsdir}",
  "quickfix_matcher": "gcc",
  "env": {
    "VAR": "value"
  },
  "depends_on": []
}
```

**Properties:**
- `command` (string|array): Command to execute
- `cwd` (string): Working directory (supports macros)
- `quickfix_matcher` (string): Parser for compiler output (`"gcc"`, `"luacheck"`, `"cargo"`, `"go"`, `"tsc"`)
- `env` (object): Optional environment variables
- `depends_on` (array): Task dependencies
- `save_buffers` (boolean): Save buffers before execution

### Run Tasks

Execute long-running applications without quickfix parsing.

```json
{
  "name": "Run Server",
  "type": "run",
  "command": "python -m http.server 8000",
  "cwd": "${wsdir}",
  "env": {
    "PORT": "8000"
  },
  "depends_on": []
}
```

### Vim Command Tasks

Execute Neovim commands or Lua code.

```json
{
  "name": "Format Buffer",
  "type": "vimcmd",
  "command": "lua vim.lsp.buf.format()",
  "depends_on": []
}
```

### Composite Tasks

Combine multiple tasks with parallel or sequential execution.

```json
{
  "name": "Full Workflow",
  "type": "composite",
  "depends_on": ["task1", "task2", "task3"],
  "depends_order": "parallel"
}
```

**Properties:**
- `depends_on` (array): List of task names to execute
- `depends_order` (string): `"parallel"` or `"sequence"` (default: `"sequence"`)

---

## Macros

Macros enable dynamic variable substitution using `${macro}` syntax.

### Built-in Macros

| Macro | Description |
|-------|-------------|
| `${wsdir}` | Workspace root directory |
| `${cwd}` | Current working directory |
| `${file}` | Full path of current file |
| `${file:type}` | Full path if filetype matches |
| `${filename}` | Current filename |
| `${fileroot}` | File path without extension |
| `${filedir}` | Directory of current file |
| `${fileext}` | File extension |
| `${filetype}` | Current buffer filetype |
| `${home}` | User home directory |
| `${tmpdir}` | System temp directory |
| `${date}` | Current date (YYYY-MM-DD) |
| `${time}` | Current time (HH:MM:SS) |
| `${timestamp}` | ISO timestamp |
| `${env:VAR}` | Environment variable |
| `${prompt:Message}` | User input prompt |
| `${var:name}` | Workspace variable |

### Example

```json
{
  "name": "Compile Current File",
  "type": "build",
  "command": "g++ ${file:cpp} -o ${fileroot}.out",
  "cwd": "${wsdir}",
  "quickfix_matcher": "gcc"
}
```

---

## License

Distributed under the MIT License.
