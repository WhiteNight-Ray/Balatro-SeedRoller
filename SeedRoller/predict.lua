-- Joker identity projection for a fixed route: no skips, one reroll at EVERY
-- shop, then open every Buffoon left-to-right and skip without taking cards.
-- No shelf/voucher purchases, other packs or consumable use.
return function(Core)
    local P = {}
    function P.check_support(c)
        if SMODS.optional_features and SMODS.optional_features.object_weights then return '不支持 object_weights 商店模式' end
        for _,key in ipairs({'eternal','perishable','rental'}) do
            if SMODS.Stickers and SMODS.Stickers[key] and SMODS.Stickers[key].should_apply then
                return '不支持被修改的贴纸生成规则：'..key
            end
        end
        for _,key in ipairs(SMODS.Sticker and SMODS.Sticker.obj_buffer or {}) do
            local sticker=SMODS.Stickers[key]
            if sticker and sticker.mod and sticker.mod.id~='Steamodded' then
                return '不支持新增贴纸：'..key
            end
        end
        for _,obj in pairs(G.P_CENTERS) do
            if obj.mod and obj.mod.id ~= 'Steamodded' then return '检测到内容 Mod，当前商店预测不支持' end
        end
        for _,set in ipairs(SMODS.ConsumableType.obj_buffer) do
            if set ~= 'Tarot' and set ~= 'Planet' and set ~= 'Spectral' then return '不支持新增消耗牌类型' end
        end
        if #(G.jokers.cards or {}) > 0 then return '预测要求开局尚未持有小丑牌' end
        for _,key in ipairs({c.joker,c.joker2}) do
            if key ~= '' then
                local obj = G.P_CENTERS[key]
                if not obj or obj.set ~= 'Joker' then return '无效的小丑牌：'..key end
                if obj.rarity == 4 or obj.hidden then return '普通商店不能直接出现该目标：'..key end
                if obj.unlocked == false then return '目标尚未解锁：'..key end
                if G.GAME.banned_keys[key] then return '目标被当前规则禁用：'..key end
                if obj.yes_pool_flag and not G.GAME.pool_flags[obj.yes_pool_flag] then return '目标需要额外牌池条件：'..key end
                if obj.enhancement_gate then
                    local found=false
                    for _,card in ipairs(G.playing_cards) do
                        if SMODS.has_enhancement(card,obj.enhancement_gate) then found=true;break end
                    end
                    if not found then return '目标需要牌组中的强化牌：'..key end
                end
            end
        end
    end
    local function joker(append)
        local pool,key = get_current_pool('Joker',nil,nil,append)
        local chosen = pseudorandom_element(pool,pseudoseed(key))
        local retry=1
        while chosen == 'UNAVAILABLE' do
            retry=retry+1; if retry > 10000 then error('商店牌池重采样超过上限') end
            chosen=pseudorandom_element(pool,pseudoseed(key..'_resample'..retry))
        end
        assert(G.P_CENTERS[chosen] and G.P_CENTERS[chosen].set=='Joker','商店小丑牌池无效')
        G.GAME.used_jokers[chosen]=true -- exclude other cards on the SAME shelf
        -- Mirror vanilla create_card and Card:set_*; advance for EVERY Joker,
        -- including non-targets and shops before N. Pack streams are separate.
        local center=G.P_CENTERS[chosen]
        local mods,ante=G.GAME.modifiers,G.GAME.round_resets.ante
        local eternal=mods.all_eternal and center.eternal_compat
        local roll=pseudorandom((append=='buf' and 'packetper' or 'etperpoll')..ante)
        local perishable=false
        if mods.enable_eternals_in_shop and roll>0.7 then
            eternal=center.eternal_compat
        elseif mods.enable_perishables_in_shop and roll>0.4 and roll<=0.7 then
            perishable=not eternal and not not center.perishable_compat
        end
        local rental=mods.enable_rentals_in_shop and
            pseudorandom((append=='buf' and 'packssjr' or 'ssjr')..ante)>0.7 or false
        return chosen,{perishable=perishable,rental=rental}
    end
    local function shelf()
        local g,out,attributes=G.GAME,{},{}
        local total=g.joker_rate+g.tarot_rate+g.planet_rate+g.playing_card_rate+(g.spectral_rate or 0)
        for slot=1,g.shop.joker_max do
            local roll=pseudorandom(pseudoseed('cdt'..g.round_resets.ante))*total
            if roll > 0 and roll <= g.joker_rate then out[slot],attributes[slot]=joker('sho')
            else out[slot]='-';attributes[slot]={} end
            -- Non-Joker pools and editions use separate keyed streams.
        end
        return out,attributes
    end
    local function packs()
        local out={}
        local total=G.GAME.starting_params.boosters_in_shop+(G.GAME.modifiers.extra_boosters or 0)
        for slot=1,total do
            if not G.GAME.first_shop_buffoon and not G.GAME.banned_keys.p_buffoon_normal_1 then
                G.GAME.first_shop_buffoon=true
                out[slot]=G.P_CENTERS.p_buffoon_normal_1 -- both art variants share card generation
            else out[slot]=get_pack('shop_pack') end
            assert(out[slot] and out[slot].config,'无法读取卡包')
        end
        return out
    end
    function P.shops(c)
        assert(not G.SETTINGS.paused,'不能在暂停菜单中预测')
        local original,temp_pool=G.GAME,G.ARGS.TEMP_POOL
        local shadow={};for k,v in pairs(original) do shadow[k]=v end
        shadow.pseudorandom=Core.copy(original.pseudorandom)
        shadow.round_resets=Core.copy(original.round_resets)
        local owned=Core.copy(original.used_jokers)
        local weights={}
        for _,pack in ipairs(G.P_CENTER_POOLS.Booster) do weights[pack]={value=pack.current_weight} end
        G.GAME,G.ARGS.TEMP_POOL=shadow,{}
        local ok,rows=xpcall(function()
            local result={}
            for shop=1,c.shop_max do
                shadow.round_resets.ante=Core.ante(shop)
                local boosters
                for reroll=0,1 do
                    -- Unbought cards leave the pool exclusion list before the next shelf.
                    shadow.used_jokers=Core.copy(owned)
                    local cards,attributes=shelf()
                    result[#result+1]={shop=shop,ante=shadow.round_resets.ante,reroll=reroll,
                        source=reroll==0 and 'initial' or 'reroll',cards=cards,attributes=attributes}
                    if reroll==0 then boosters=packs() end
                end
                local displayed=Core.copy(shadow.used_jokers)
                for slot,pack in ipairs(boosters) do
                    if pack.kind=='Buffoon' then
                        shadow.used_jokers=Core.copy(displayed)
                        local cards,attributes={},{}
                        local count=math.max(1,pack.config.extra+(shadow.modifiers.booster_size_mod or 0))
                        for i=1,count do cards[i],attributes[i]=joker('buf') end
                        result[#result+1]={shop=shop,ante=shadow.round_resets.ante,source='buffoon',
                            pack_slot=slot,pack_key=pack.key,cards=cards,attributes=attributes}
                    end
                end
            end
            return result
        end,debug.traceback)
        G.GAME,G.ARGS.TEMP_POOL=original,temp_pool
        for pack,old in pairs(weights) do pack.current_weight=old.value end
        if not ok then error(rows) end
        return rows
    end
    return P
end
