---@type loop.taskTemplate[]
return {
	--- empty generic task
	{
		name = "Run task",
		task = {
			name = "Run",
			type = "process",
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
			name = "Run Binary",
			type = "process",
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
			name = "Python Run",
			type = "process",
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
			name = "Static Server",
			type = "process",
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
			name = "Cargo Run",
			type = "process",
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
			name = "Cargo Run",
			type = "process",
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
			name = "Go Run",
			type = "process",
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
			name = "Node Run",
			type = "process",
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
			name = "NPM Dev",
			type = "process",
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
			name = "NPM Watch",
			type = "process",
			command = "npm run watch",
			cwd = "${wsdir}",
			env = nil,
			save_buffers = true,
			depends_on = {},
		},
	},
}
