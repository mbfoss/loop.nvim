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

**loop.nvim** is a workspace and task management system for Neovim. It provides structured task definitions, dependency resolution, and execution directly from your editor using project-specific configuration stored in `.nvimloop` directories.

### Features

- **Workspace Management**: Auto-detects and loads configuration from `.nvimloop` directories
- **Task Scheduling**: Dependency resolution with parallel/sequential execution
- **Task Types**: Build, run, vimcmd, and composite tasks
- **Quickfix Integration**: Parses compiler output (GCC, Clang, luacheck, cargo, go, tsc ...) into the quickfix list
- **Macro System**: Variable substitution using `${macro}` syntax
- **UI Management**: Window and page management for task outputs
- **Variables**: Custom workspace variables managed via `:Loop var`

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
     -- UI selector, possible values: 
     -- builtin: built-in selector/picker window
     -- default: vim.ui.select (Neovim default or managed by a plugin such as Mini, Snacks, Telescope...)
    selector = "builtin",
    -- Use per-workspace persistence of shared file history, registers, global marks, undo history, etc.
    -- Enabling this will make Neovim use persistence data stored inside the workspace folder (.nvimloop)
    persistence = { 
        shada = false,    -- Enable workspace shada persistence
        undo = false,     -- Enable workspace undo persistence
    },
})
```

### Workspace Configuration

Workspaces are stored in `.nvimloop` directories containing:
- `workspace.json` - Workspace configuration
- `tasks.json` - Task definitions
- Provider-specific configuration files

Workspaces are auto-loaded when Neovim is opened without arguments and a `.nvimloop` directory is detected in the current working directory.

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
- `command` (string|array): Command to execute
- `cwd` (string): Working directory
- `quickfix_matcher` (string): Parser for compiler output (`"gcc"`, `"luacheck"`, `"cargo"`, `"go"`, `"tsc"`)
- `env` (object): Optional environment variables
- `save_buffers` (boolean): Save buffers before execution
- `depends_on` (array): Task dependencies
- `depends_order` (string): `"parallel"` or `"sequence"` (default: `"sequence"`)

---

## Macros

Macros enable dynamic variable substitution using `${macro}` syntax.

### Built-in Macros

| Macro | Description | Example |
|-------|-------------|---------|
| `${wsdir}` | Workspace root directory | `/path/to/project` |
| `${cwd}` | Current working directory | `/path/to/current` |
| `${file}` | Full path of current file | `/path/to/file.txt` |
| `${file:type}` | Full path if filetype is type, task fails otherwise | `/path/to/file.txt` |
| `${filename}` | Current filename | `file.txt` |
| `${filename:type}` | Filename if filetype is type, task fails otherwise | `file.txt` |
| `${fileroot}` | File path without extension | `/path/to/file` |
| `${filedir}` | Directory of current file | `/path/to` |
| `${fileext}` | File extension | `txt` |
| `${filetype}` | Current buffer filetype | `text` |
| `${home}` | User home directory | `/home/user` |
| `${tmpdir}` | System temp directory | `/tmp` |
| `${date}` | Current date (YYYY-MM-DD) | `2024-01-15` |
| `${time}` | Current time (HH:MM:SS) | `14:30:00` |
| `${timestamp}` | ISO timestamp | `2024-01-15T14:30:00` |
| `${env:NAME}` | Environment variable | Value of `$NAME` |
| `${var:NAME}` | User variables  | Value of user variable |
| `${var:NAME,subst1,subst2...}` | User variable with lua string substitutions | Value of `$VAR` after substitution |
| `${prompt:Message}` | User input prompt | User-provided value |
| `${prompt:Message,Default,CompletionType}` | User input prompt with default value and completion (example: ${prompt:Enter Path,/,file}) | User-provided value |

### Example

```json
{
  "name": "Compile Current File",
  "type": "build",
  "command": "gcc ${file} -o ${fileroot}.out",
  "cwd": "${wsdir}"
}
```

```json
{
  "name": "Run with Port",
  "type": "run",
  "command": "python server.py --port ${prompt:Enter port,8000}",
  "cwd": "${wsdir}"
}
```


### Persistence

Loop supports optional per-workspace persistence. When enabled, Loop will cause Neovim to use persistence data stored inside the workspace (.nvimloop) while that workspace is active. This isolates things like:
- shada (command/file history, registers, global marks)
- undo history

Enable or disable these features in the global setup via the `persistence` table shown above. Persistence data is kept alongside the workspace to avoid cross-project leakage of history and state.

## Variables

Loop provides workspace variables that can be created and edited with the `:Loop var` commands (`:Loop var add`, `:Loop var configure`). Variables are stored in the workspace configuration and are available to the macro substitution system. Reference variables using the `${var:NAME}` macro in task definitions, commands, and provider configuration. Variable values take effect for tasks run in that workspace and persist with the workspace configuration.



## License
Distributed under the MIT License.
