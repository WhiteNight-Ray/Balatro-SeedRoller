-- Legacy filename retained for upgrades; controls now live in native menus.
return function(R)
    function R.perform(action)
        R.safe(function()
            if action == 'settings' then R.open_menu()
            elseif action == 'start' then
                if R.active then return end
                if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
                R.start()
            elseif action == 'stop' then R.stop()

            end
        end)
    end
    G.FUNCS.sroll_open = function() R.perform('settings') end
    local previous_options = create_UIBox_options
    function create_UIBox_options(...)
        local definition = previous_options(...)
        local function insert(node)
            for i, child in ipairs(node.nodes or {}) do
                local button = child.nodes and child.nodes[1]
                if child.n == G.UIT.R and button and button.config and button.config.button == 'settings' then
                    local chinese = G.SETTINGS.language == 'zh_CN' or G.SETTINGS.language == 'zh_TW'
                    table.insert(node.nodes, i+1, UIBox_button{
                        id='sroll_options_entry', button='sroll_open',
                        label={chinese and '种子筛选' or 'Seed Roller'}, minw=5, minh=0.65, scale=0.4,
                    })
                    return true
                end
                if insert(child) then return true end
            end
        end
        if not insert(definition) then
            print('[SeedRoller] Options layout changed; use Mods > Seed Roller instead')
        end
        return definition
    end
end
