local field_order = { "name", "type", "command", "cwd", "env", "save_buffers", "depends_on" }

---@type loop.taskTemplate[]
return {
	--- empty generic task
	{
		name = "Run task",
		task = {
			__order = field_order,
			name = "Run",
			type = "command",
			command = "",
			cwd = "${wsdir}",
			save_buffers = false,
		},
	},
	----------------------------------------------------------------------------
	-- C / C++ / BINARY
	----------------------------------------------------------------------------
	{
		name = "C++: Run Current Binary",
		task = {
			__order = field_order,
			name = "Run Binary",
			type = "command",
			command = "${fileroot}.out",
			cwd = "${filedir}",
			env = nil,
			save_buffers = false,
			depends_on = { "Compile file" },
		},
	},

	----------------------------------------------------------------------------
	-- PYTHON
	----------------------------------------------------------------------------
	{
		name = "Python: Run Current File",
		task = {
			__order = field_order,
			name = "Python Run",
			type = "command",
			command = "python3 ${file}",
			cwd = "${filedir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
	{
		name = "Python: HTTP Server",
		task = {
			__order = field_order,
			name = "Static Server",
			type = "command",
			command = "python3 -m http.server 8000",
			cwd = "${wsdir}",
			env = { PORT = "8000" },
			save_buffers = false,
			depends_on = {},
		},
	},

	----------------------------------------------------------------------------
	-- RUST / GO
	----------------------------------------------------------------------------
	{
		name = "Rust: Cargo Run",
		task = {
			__order = field_order,
			name = "Cargo Run",
			type = "command",
			command = "cargo run",
			cwd = "${wsdir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
	{
		name = "Rust: Cargo Run (Release)",
		task = {
			__order = field_order,
			name = "Cargo Run",
			type = "command",
			command = "cargo run --release",
			cwd = "${wsdir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
	{
		name = "Go: Run Current File",
		task = {
			__order = field_order,
			name = "Go Run",
			type = "command",
			command = "go run ${file}",
			cwd = "${filedir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},

	----------------------------------------------------------------------------
	-- WEB / NODE
	----------------------------------------------------------------------------
	{
		name = "Node: Run Current File",
		task = {
			__order = field_order,
			name = "Node Run",
			type = "command",
			command = "node ${file}",
			cwd = "${filedir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
	{
		name = "Web: Dev Server (NPM)",
		task = {
			__order = field_order,
			name = "NPM Dev",
			type = "command",
			command = "npm run dev",
			cwd = "${wsdir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
	{
		name = "Web: Watch Mode",
		task = {
			__order = field_order,
			name = "NPM Watch",
			type = "command",
			command = "npm run watch",
			cwd = "${wsdir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
}
