require("plenary.busted")
local tasks_mod = require("loop.tasks.tasks")

describe("loop.tasks.tasks.get_deps_chain", function()
    it("returns simple linear dependency chain", function()
        local tasks = {
            { name = "clean",   command = "rm -rf build" },
            { name = "compile", command = "gcc",         require = { "clean" } },
            { name = "build",   command = "make",        require = { "compile" } },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[3])
        assert.is_nil(err)
        assert(chain)
        assert.is_table(chain)

        local names = vim.tbl_map(function(t) return t.name end, chain)
        assert.are.same({ "clean", "compile", "build" }, names)
    end)

    it("handles shared dependencies correctly", function()
        local tasks = {
            { name = "clean",     command = "rm -rf build" },
            { name = "compile",   command = "gcc",         require = { "clean" } },
            { name = "test",      command = "pytest",      require = { "clean" } },
            { name = "build_all", command = "make all",    require = { "compile", "test" } },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[4])
        assert.is_nil(err)
        assert(chain)
        assert.is_table(chain)

        local names = vim.tbl_map(function(t) return t.name end, chain)
        assert.is_true(vim.tbl_contains(names, "clean"))
        assert.is_true(vim.tbl_contains(names, "compile"))
        assert.is_true(vim.tbl_contains(names, "test"))
        assert.are.equal("build_all", names[#names])
    end)

    it("returns error for missing dependency", function()
        local tasks = {
            { name = "build", command = "make", require = { "missing_task" } },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[1])
        assert.is_nil(chain)
        assert.is_string(err)
        assert(type(err) == "string")
        assert.is_truthy(err:match("missing dependency"))
    end)

    it("returns error for cyclic dependencies", function()
        local tasks = {
            { name = "a", command = "cmd", require = { "b" } },
            { name = "b", command = "cmd", require = { "a" } },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[1])
        assert.is_nil(chain)
        assert.is_string(err)
        assert(type(err) == "string")
        assert.is_truthy(err:match("cyclic dependency"))
    end)

    it("returns error for duplicate task names", function()
        local tasks = {
            { name = "a", command = "cmd" },
            { name = "a", command = "cmd" },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[1])
        assert.is_nil(chain)
        assert.is_string(err)
        assert(type(err) == "string")
        assert.is_truthy(err:match("duplicate task name"))
    end)

    it("handles task with no dependencies", function()
        local tasks = {
            { name = "solo", command = "echo hi" },
        }

        local chain, err = tasks_mod.get_deps_chain(tasks, tasks[1])
        assert.is_nil(err)
        assert.is_table(chain)
        assert(chain)
        assert.are.same({ "solo" }, vim.tbl_map(function(t) return t.name end, chain))
    end)
end)
