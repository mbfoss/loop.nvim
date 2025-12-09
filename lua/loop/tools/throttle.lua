local M = {}

local uv = vim.uv

-- Throttle that:
-- • Runs the first call immediately
-- • Guarantees at least `ms` between executions
-- • Never drops a call – if called during cooldown, it will run again exactly when allowed
-- • No arguments, pure side-effect trigger
function M.throttle_wrap(ms, fn)
    local timer = nil
    local last_exec = 0

    return function()
        ---@diagnostic disable-next-line: undefined-field
        local now = uv.now()
        -- Enough time passed → run immediately
        if last_exec == 0 or now - last_exec >= ms then
            last_exec = now
            fn()
            return
        end
        -- We are in cooldown
        if timer then
            return
        end
        -- Schedule the next execution for exactly when the cooldown ends
        local delay = ms - (now - last_exec)
        ---@diagnostic disable-next-line: undefined-field
        timer = uv.new_timer()
        timer:start(delay, 0, function()
            vim.schedule(function()
                timer:stop()
                timer:close()
                timer = nil
                ---@diagnostic disable-next-line: undefined-field
                last_exec = uv.now()
                fn()
            end)
        end)
    end
end

return M
