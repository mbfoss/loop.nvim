require("plenary.busted")

local runner = require("loop.runner")
local resolver = require("loop.tools.resolver")

require('loop.window').setup()
require('loop.debug.breakpoints').setup()

-- Mock the heavy dependencies so tests run instantly and safely
package.preload["loop.job.TermJob"] = function()
    return {
        new = function()
            return {
                start = function(self, bufnr, args)
                    vim.schedule(function()
                        if args.on_exit_handler then args.on_exit_handler(0) end
                    end)
                    return 123, nil
                end,
                kill = function() end,
            }
        end
    }
end

package.preload["loop.job.DebugJob"] = function()
    return { new = function() return { start = function() return true end, add_tracker = function() end } end }
end

package.preload["loop.job.VimCmdJob"] = function()
    return { new = function() return { start = function() return true end } end }
end

-- Minimal config mock
package.loaded["loop.config"] = package.loaded["loop.config"] or {}
package.loaded["loop.config"].current = {
    macros = {},
    debuggers = { gdb = { dap = { type = "executable" } } },
    qfmatchers = {}
}

describe("loop.task.runner", function()
    before_each(function()
        runner.terminate_task_chain()
        package.loaded["loop.config"].current.macros = {}
    end)

    -- ==================================================================
    -- get_deps_chain — same style as your original tests
    -- ==================================================================
    describe("get_deps_chain", function()
        it("returns simple linear dependency chain", function()
            local tasks = {
                { name = "clean",   command = "rm -rf build" },
                { name = "compile", command = "gcc",         depends_on = { "clean" } },
                { name = "build",   command = "make",        depends_on = { "compile" } },
            }
            local chain, err = runner.get_deps_chain(tasks, tasks[3])
            assert.is_nil(err)
            assert.is_table(chain)
            assert(chain)
            local names = vim.tbl_map(function(t) return t.name end, chain)
            assert.are.same({ "clean", "compile", "build" }, names)
        end)

        it("handles shared dependencies correctly", function()
            local tasks = {
                { name = "clean" },
                { name = "compile", depends_on = { "clean" } },
                { name = "test",    depends_on = { "clean" } },
                { name = "all",     depends_on = { "compile", "test" } },
            }
            local chain, err = runner.get_deps_chain(tasks, tasks[4])
            assert.is_nil(err)
            assert(chain)
            local names = vim.tbl_map(function(t) return t.name end, chain)
            assert.is_true(vim.tbl_contains(names, "clean"))
            assert.is_true(vim.tbl_contains(names, "compile"))
            assert.is_true(vim.tbl_contains(names, "test"))
            assert.are.equal("all", names[#names])
        end)

        it("detects cyclic dependencies", function()
            local tasks = {
                { name = "a", depends_on = { "b" } },
                { name = "b", depends_on = { "a" } },
            }
            local _, err = runner.get_deps_chain(tasks, tasks[1])
            assert.is_string(err)
            assert(err)
            assert.is_truthy(err:find("cyclic"))
        end)

        it("detects missing dependencies", function()
            local tasks = { { name = "x", depends_on = { "missing" } } }
            local _, err = runner.get_deps_chain(tasks, tasks[1])
            assert.is_string(err)
            assert(err)
            assert.is_truthy(err:find("missing dependency"))
        end)

        it("detects duplicate task names", function()
            local tasks = { { name = "dup" }, { name = "dup" } }
            local _, err = runner.get_deps_chain(tasks, tasks[1])
            assert.is_string(err)
            assert(err)
            assert.is_truthy(err:find("duplicate task name"))
        end)
    end)

    -- ==================================================================
    -- start_task_chain — real async behavior, properly waited
    -- ==================================================================
    describe("start_task_chain", function()


        it("runs a single build task successfully", function()
            local called = false
            local tasks = { { name = "hello", type = "build", command = "echo hello" } }

            runner.start_task_chain(tasks, function() called = true end)

            vim.wait(2000, function() return called end)
            assert.is_true(called)
        end)

        it("calls on_complete even when macro resolution fails", function()
            package.loaded["loop.config"].current.macros.boom = function(cb)
                cb(nil, "boom failed")
            end

            local tasks = { { name = "bad", type = "build", command = "${boom}" } }
            local completed = false

            runner.start_task_chain(tasks, function() completed = true end)

            vim.wait(2000, function() return completed end)
            assert.is_true(completed)
        end)

        it("supports vimcmd tasks", function()
            local called = false
            local tasks = { { name = "vimcmd", type = "vimcmd", command = "messages" } }

            runner.start_task_chain(tasks, function() called = true end)
            vim.wait(2000, function() return called end)
            assert.is_true(called)
        end)

        it("supports debug tasks with minimal config", function()
            local tasks = {
                {
                    name = "debugme",
                    type = "debug",
                    debug_adapter = "gdb",
                    debug_request = "launch",
                    debug_args = {},
                }
            }

            local started = false
            runner.start_task_chain(tasks, function() started = true end)
            vim.wait(2000, function() return started end)
            assert.is_true(started)
        end)
    end)

    -- ==================================================================
    -- terminate_task_chain
    -- ==================================================================
    describe("terminate_task_chain", function()
        it("stops currently running chain", function()

            runner.start_task_chain({
                {
                    name = "long task",
                    type = "build",
                    command = "sleep 1000",
                }
            })

            runner.terminate_task_chain()

            vim.wait(1000, function()
                return runner._current_task_chain == nil or runner._current_task_chain.interrupted
            end)

            local chain = runner._current_task_chain
            assert(chain == nil or chain.interrupted, "chain should be interrupted or gone")
        end)
    end)
end)
