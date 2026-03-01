# loop-build.nvim

Build task provider for [loop.nvim](https://github.com/mbfoss/loop.nvim). Adds a **build** task type and templates for common build and lint commands, with optional quickfix parsing.

## Requirements

- **Neovim** ≥ 0.10  
- **loop.nvim**

## Features

- **Build task type** — Run shell commands as loop tasks with `command`, `cwd`, `env`, and optional **quickfix_matcher** to turn compiler/linter output into quickfix entries.
- **Templates** — Predefined tasks under the **Build** category: generic build, Make, g++, Cargo (build/check/release), Go, luacheck, tsc, pylint.

## Installation

**lazy.nvim**

```lua
{
    "mbfoss/loop-build.nvim",
    dependencies = { "mbfoss/loop.nvim" },
}
```

**packer.nvim**

```lua
use {
    "mbfoss/loop-build.nvim",
    requires = { "mbfoss/loop.nvim" },
}
```

## Quick Start

1. Install loop.nvim and loop-build.nvim.
2. Open a loop workspace (`:Loop workspace open`).
3. Add a build task: `:Loop task configure` and add a task with `"type": "build"`, or use the **Build** templates when editing `tasks.json`.
4. Run it: `:Loop task run` (or `:Loop task run Build`).

## Build Task Schema

In `tasks.json`, a build task can look like:

```json
{
  "name": "Build",
  "type": "build",
  "command": "make",
  "cwd": "${wsdir}",
  "quickfix_matcher": "gcc",
  "save_buffers": true
}
```

| Field               | Type           | Description |
|---------------------|----------------|-------------|
| `command`           | string \| array | Command to run (string = shell, array = exec without shell). |
| `cwd`               | string         | Working directory (default: workspace root). |
| `env`               | object         | Extra environment variables. |
| `quickfix_matcher`  | string         | Parser name for turning output into quickfix (e.g. `gcc`, `cargo`, `go`, `linter`, `tsc`). Optional. |

All fields support [loop.nvim macros](https://github.com/mbfoss/loop.nvim) (e.g. `${wsdir}`, `${file}`).

## Built-in Quickfix Matchers

| Matcher  | Typical use        |
|----------|---------------------|
| `gcc`    | gcc/g++/make        |
| `cargo`  | Rust cargo          |
| `go`     | Go compiler         |
| `linter` | Generic linter (e.g. luacheck, pylint) |
| `tsc`    | TypeScript compiler  |

## Configuration

Optional setup:

```lua
require("loop-build").setup({
    quickfix_matchers = {
        -- name = function(line, ctx) return { filename, lnum, col, text } or nil end
    },
})
```

Use `quickfix_matchers` to add or override matchers. Each matcher is a function `(line, ctx) -> entry | nil` where `entry` is `{ filename, lnum, col, text }`.

## Templates

When editing tasks (e.g. via `:Loop task configure`), the **Build** category offers:

- **Build task** — Generic build (command and matcher left for you to fill).
- **C++** — Make; compile single file with g++.
- **Rust** — Cargo build, build (release), check.
- **Go** — Build project; build current file.
- **Lua** — Luacheck current file.
- **TypeScript** — `tsc --noEmit`.
- **Python** — Pylint current file.

## License

MIT
