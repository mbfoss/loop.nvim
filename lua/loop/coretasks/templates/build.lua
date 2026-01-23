---@type loop.taskTemplate[]
return {
	--- empty generic task
	{
		name = "Build task",
		task = {
			name = "Build",
			type = "process",
			command = "",
			cwd = "${wsdir}",
			quickfix_matcher = "",
			save_buffers = true,
		},
	},
	----------------------------------------------------------------------------
	-- C / C++
	----------------------------------------------------------------------------
	{
		name = "C++: Build Project (Make)",
		task = {
			name = "Make",
			type = "process",
			command = "make",
			cwd = "${wsdir}",
			quickfix_matcher = "gcc",
			save_buffers = true,
		},
	},
	{
		name = "C++: Build Single File (G++)",
		task = {
			name = "Compile file",
			type = "process",
			command = "g++ -g -Wall -Wextra ${file} -o ${fileroot}.out",
			cwd = "${filedir}",
			quickfix_matcher = "gcc",
			save_buffers = true,
		},
	},

	----------------------------------------------------------------------------
	-- RUST
	----------------------------------------------------------------------------
	{
		name = "Rust: Cargo Build",
		task = {
			name = "Build",
			type = "process",
			command = "cargo build --message-format=short",
			cwd = "${wsdir}",
			quickfix_matcher = "cargo",
			save_buffers = true,
		},
	},
	{
		name = "Rust: Cargo Build (Release)",
		task = {
			name = "Build (Release)",
			type = "process",
			command = "cargo build --release --message-format=short",
			cwd = "${wsdir}",
			quickfix_matcher = "cargo",
			save_buffers = true,
		},
	},
	{
		name = "Rust: Cargo Check",
		task = {
			name = "Check",
			type = "process",
			command = "cargo check --message-format=short",
			cwd = "${wsdir}",
			quickfix_matcher = "cargo",
			save_buffers = true,
		},
	},

	----------------------------------------------------------------------------
	-- GO
	----------------------------------------------------------------------------
	{
		name = "Go: Build Project",
		task = {
			name = "Build",
			type = "process",
			command = "go build ./...",
			cwd = "${wsdir}",
			quickfix_matcher = "go",
			save_buffers = true,
		},
	},
	{
		name = "Go: Build Current File",
		task = {
			name = "Build File",
			type = "process",
			command = "go build ${file}",
			cwd = "${filedir}",
			quickfix_matcher = "go",
			save_buffers = true,
		},
	},

	----------------------------------------------------------------------------
	-- STATIC ANALYSIS / LINTING
	----------------------------------------------------------------------------
	{
		name = "Lua: Lint Current File",
		task = {
			name = "Luacheck",
			type = "process",
			command = "luacheck ${file} --formatter plain --codes",
			cwd = "${filedir}",
			quickfix_matcher = "linter",
			save_buffers = true,
		},
	},
	{
		name = "TS: Type Check Project",
		task = {
			name = "Check",
			type = "process",
			command = "tsc --noEmit --pretty false",
			cwd = "${wsdir}",
			quickfix_matcher = "tsc",
			save_buffers = true,
		},
	},
	{
		name = "Python: Lint Current File",
		task = {
			name = "Pylint",
			type = "process",
			command = "pylint --output-format=parseable ${file}",
			cwd = "${filedir}",
			quickfix_matcher = "linter",
			save_buffers = true,
		},
	},
}
