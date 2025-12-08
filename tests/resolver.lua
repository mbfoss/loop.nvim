require("plenary.busted")

local M = require("loop.tools.resolver")

describe("loop.config.macro_resolver.resolve_macros", function()
    -- Helper to run async tests synchronously
    local function sync_resolve(tbl)
        local result, err
        local done = false

        M.resolve_macros(tbl, function(success, res, e)
            done = true
            if success then
                result = res
            else
                err = e
            end
        end)

        vim.wait(1000, function() return done end, 10) -- max 1s wait
        assert(done, "Test timed out – callback never called")
        return result, err
    end

    -- Mock macro registry
    before_each(function()
        package.loaded["loop.config"] = package.loaded["loop.config"] or {}
        package.loaded["loop.config"].current = {
            macros = {}
        }
    end)

    it("returns the table unchanged when no macros are present", function()
        local input = { msg = "hello world", number = 42, nested = { x = "abc" } }
        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same(input, result)
    end)

    it("expands a single top-level string macro", function()
        package.loaded["loop.config"].current.macros.hello = function(cb)
            cb("Hello from macro!")
        end

        local input = { greeting = "${hello}" }
        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({ greeting = "Hello from macro!" }, result)
    end)

    it("expands the entire table when it contains only one macro ${...}", function()
        package.loaded["loop.config"].current.macros.world = function(cb)
            cb({ planet = "Earth", population = 8e9 })
        end

        local input = "${world}" -- note: not a table, just the macro
        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({ planet = "Earth", population = 8000000000 }, result)
    end)

    it("supports macro arguments with spaces and colons", function()
        package.loaded["loop.config"].current.macros.echo = function(cb, arg)
            cb("You said: " .. (arg or "(nothing)"))
        end

        local input = { text = "${echo:  hello : world  }" }
        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({ text = "You said: hello : world" }, result)
    end)

    it("allows escaping with $${...} → literal ${...}", function()
        local input = { raw = "keep $${this} intact", mixed = "hello $${name} and ${real}" }

        package.loaded["loop.config"].current.macros.real = function(cb)
            cb("REAL")
        end

        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({
            raw = "keep ${this} intact",
            mixed = "hello ${name} and REAL",
        }, result)
    end)

    it("expands multiple macros in one string", function()
        package.loaded["loop.config"].current.macros.user = function(cb) cb("Alice") end
        package.loaded["loop.config"].current.macros.host = function(cb) cb("localhost") end

        local input = { url = "https://${user}:${pass}@${host}:8080" }

        package.loaded["loop.config"].current.macros.pass = function(cb) cb("secret123") end

        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({ url = "https://Alice:secret123@localhost:8080" }, result)
    end)

    it("expands macros deeply in nested tables", function()
        package.loaded["loop.config"].current.macros.env = function(cb) cb("prod") end
        package.loaded["loop.config"].current.macros.db = function(cb) cb("postgres") end

        local input = {
            environment = "${env}",
            database = {
                name = "${db}",
                url = "jdbc:${db}://localhost",
            },
        }

        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({
            environment = "prod",
            database = {
                name = "postgres",
                url = "jdbc:postgres://localhost",
            },
        }, result)
    end)

    it("rejects unknown macro", function()
        local input = { x = "${does_not_exist}" }
        local _, err = sync_resolve(input)

        assert.is_string(err)
        assert.is_truthy(err:find("Unknown macro"))
    end)

    it("rejects macro that crashes", function()
        package.loaded["loop.config"].current.macros.boom1 = function()
            error("macro exploded")
        end

        local input = { x = "${boom1}" }
        local _, err = sync_resolve(input)

        assert.is_string(err)
        assert.is_truthy(err:find("crashed"))
    end)

    it("rejects macro returning non-simple data in multi-macro context", function()
        package.loaded["loop.config"].current.macros.tbl = function(cb)
            cb({ this = "is a table" }) -- complex value
        end

        local input = { a = "hello", b = "${tbl}" }
        local val, err = sync_resolve(input)

        assert.is_nil(err)
        assert.is_equal(vim.inspect(val), vim.inspect({
            a = "hello",
            b = {
                this = "is a table" }
        }))
    end)

    it("handles macro returning a number/boolean (still simple data)", function()
        package.loaded["loop.config"].current.macros.num = function(cb) cb(123) end
        package.loaded["loop.config"].current.macros.flag = function(cb) cb(true) end

        local input = { count = "${num}", enabled = "${flag}" }
        local result, err = sync_resolve(input)

        assert.is_nil(err)
        assert.are.same({ count = 123, enabled = true }, result)
    end)
end)
