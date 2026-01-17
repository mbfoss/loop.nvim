local field_order = { "name", "type", "command", "cwd", "save_buffers", "quickfix_matcher", "depends_on", "depends_order" }

---@type loop.taskTemplate[]
return {
	--- empty generic task
	{
		name = "Build task",
		task = {
			__order = field_order,
			name = "Build",
			type = "command",
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
			__order = field_order,
			name = "Make",
			type = "command",
			command = "make",
			cwd = "${wsdir}",
			quickfix_matcher = "gcc",
			save_buffers = true,
		},
	},
	{
		name = "C++: Build Single File (G++)",
		task = {
			__order = field_order,
			name = "Compile file",
			type = "command",
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
			__order = field_order,
			name = "Build",
			type = "command",
			command = "cargo build --message-format=short",
			cwd = "${wsdir}",
			quickfix_matcher = "cargo",
			save_buffers = true,
		},
	},
	{
		name = "Rust: Cargo Build (Release)",
		task = {
			__order = field_order,
			name = "Build (Release)",
			type = "command",
			command = "cargo build --release --message-format=short",
			cwd = "${wsdir}",
			quickfix_matcher = "cargo",
			save_buffers = true,
		},
	},
	{
		name = "Rust: Cargo Check",
		task = {
			__order = field_order,
			name = "Check",
			type = "command",
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
			__order = field_order,
			name = "Build",
			type = "command",
			command = "go build ./...",
			cwd = "${wsdir}",
			quickfix_matcher = "go",
			save_buffers = true,
		},
	},
	{
		name = "Go: Build Current File",
		task = {
			__order = field_order,
			name = "Build File",
			type = "command",
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
			__order = field_order,
			name = "Luacheck",
			type = "command",
			command = "luacheck ${file} --formatter plain --codes",
			cwd = "${filedir}",
			quickfix_matcher = "linter",
			save_buffers = true,
		},
	},
	{
		name = "TS: Type Check Project",
		task = {
			__order = field_order,
			name = "Check",
			type = "command",
			command = "tsc --noEmit --pretty false",
			cwd = "${wsdir}",
			quickfix_matcher = "tsc",
			save_buffers = true,
		},
	},
	{
		name = "Python: Lint Current File",
		task = {
			__order = field_order,
			name = "Pylint",
			type = "command",
			command = "pylint --output-format=parseable ${file}",
			cwd = "${filedir}",
			quickfix_matcher = "linter",
			save_buffers = true,
		},
	},
}
