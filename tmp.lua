        local idx = 0
        for _, tab in ipairs(_tabs_arr) do
            if #tab.pages > 0 then
                idx = idx + 1
                local key = "gp" .. tostring(idx)
                keymaps[key] = {
                    callback =
                        function()
                            _tab_key_handler(tab, _setup_active_tab)
                        end,
                    desc = "Go to page: " .. tab.label
                }
            end
        end