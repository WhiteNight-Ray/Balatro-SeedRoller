return function(R)
    local mod,C=R.mod,R.mod.config
    local function label(zh,en)
        return (G.SETTINGS.language=='zh_CN' or G.SETTINGS.language=='zh_TW') and zh or en
    end
    local function text(value,size)
        return {n=G.UIT.R,config={align='cm',maxw=6.9,padding=0.025},nodes={
            {n=G.UIT.T,config={text=value,scale=size or 0.27,colour=G.C.UI.TEXT_LIGHT}},
        }}
    end
    -- ROOT is valid only for an independent UIBox. Embedding another ROOT in
    -- generic_options causes the inner panel to be laid out at a separate origin.
    local function menu_content(definition)
        return {n=G.UIT.C,config={align='cm',minw=6.9,padding=0.06},nodes=definition.nodes}
    end
    local function changed(field,value)
        R.stop('设置已修改');R.message=nil;R.result='';R.result_lines={}
        C[field]=value;SMODS.save_mod_config(mod)
    end
    local function cycle(field,title,entries)
        local values,names,index={},{},1
        for i,row in ipairs(entries) do
            values[i],names[i]=row[1],row[2]
            if C[field]==row[1] then index=i end
        end
        G.FUNCS['sroll_'..field]=function(args)
            changed(field,values[args.to_key])
        end
        return {n=G.UIT.R,config={align='cm',padding=0.025},nodes={
            {n=G.UIT.C,config={align='cl',minw=2,maxw=2},nodes={
                {n=G.UIT.T,config={text=title,scale=0.28,colour=G.C.UI.TEXT_LIGHT}},
            }},
            {n=G.UIT.C,config={align='cm'},nodes={create_option_cycle{
                options=names,current_option=index,opt_callback='sroll_'..field,
                w=6,h=0.65,scale=0.55,text_scale=0.48,no_pips=true,
            }}},
        }}
    end
    local function short(value)
        value=(value or ''):match('[^\n]+') or ''
        if #value>150 then value=value:sub(1,150):gsub('[\194-\244][\128-\191]*$','')..'...' end
        return value
    end
    local function joker_name(key)
        if key=='' then return label('不选（只筛一张）','None (one target)') end
        local obj=G.P_CENTERS[key]
        if not obj or obj.unlocked==false then return label('请选择有效目标','Select a valid target') end
        return localize{type='name_text',set='Joker',key=key}
    end
    local function joker_entries(field)
        local entries=field=='joker2' and {{'',joker_name('')}} or {}
        local keys={}
        for key,obj in pairs(G.P_CENTERS) do
            if obj.set=='Joker' and obj.rarity~=4 and not obj.hidden and obj.unlocked~=false then keys[#keys+1]=key end
        end
        table.sort(keys,function(a,b)return (G.P_CENTERS[a].order or 0)==(G.P_CENTERS[b].order or 0) and a<b or (G.P_CENTERS[a].order or 0)<(G.P_CENTERS[b].order or 0)end)
        for _,key in ipairs(keys) do
            entries[#entries+1]={key,joker_name(key)}
        end
        return entries
    end
    local visible_count=8
    local function draw_picker()
        local p=R.picker
        local rows={text(label('选择小丑牌 ','Choose Joker ')..(p.field=='joker' and 'A' or 'B'),0.35),
            text(label('滚轮上下浏览，点击名称选中','Scroll up/down; click a name to select'),0.27)}
        local last=math.min(#p.entries,p.first+visible_count-1)
        for i=p.first,last do
            local entry=p.entries[i]
            rows[#rows+1]=UIBox_button{
                label={(C[p.field]==entry[1] and label('已选 · ','Selected · ') or '')..entry[2]},
                button='sroll_pick',ref_table={field=p.field,key=entry[1]},
                colour=C[p.field]==entry[1] and G.C.ORANGE or G.C.RED,
                minw=6.4,minh=0.43,scale=0.29,
            }
        end
        rows[#rows+1]=text(p.first..'–'..last..' / '..#p.entries,0.24)
        rows[#rows+1]={n=G.UIT.R,config={align='cm',padding=0.05},nodes={
            UIBox_button{label={label('向上滚动','Scroll up')},button='sroll_scroll_up',col=true,minw=3.1,minh=0.45,scale=0.27},
            UIBox_button{label={label('向下滚动','Scroll down')},button='sroll_scroll_down',col=true,minw=3.1,minh=0.45,scale=0.27},
        }}
        G.SETTINGS.paused=true
        local definition=create_UIBox_generic_options{
            back_func='sroll_picker_back',minw=7,padding=0.1,contents={menu_content({nodes=rows})},
        }
        if p.overlay and p.overlay==G.OVERLAY_MENU then
            -- Updating a list is not opening a new overlay: avoid adding cursor
            -- context layers, menu entrance motion or screen jiggle per wheel tick.
            local old=p.overlay
            local replacement=UIBox{definition=definition,config={align='cm',offset={x=0,y=0},major=G.ROOM_ATTACH,bond='Weak'}}
            old:remove()
            G.OVERLAY_MENU=replacement
            replacement:align_to_major()
        else
            G.FUNCS.overlay_menu{definition=definition}
        end
        p.overlay=G.OVERLAY_MENU
    end
    function R.open_picker(field)
        if field~='joker' and field~='joker2' then return end
        local entries=joker_entries(field)
        local first=1
        for i,entry in ipairs(entries) do if entry[1]==C[field] then first=i;break end end
        R.picker={field=field,entries=entries,first=math.min(first,math.max(1,#entries-visible_count+1)),wheel=0}
        draw_picker()
    end
    local function scroll_picker(delta)
        local p=R.picker
        if not p or p.overlay~=G.OVERLAY_MENU then return end
        local first=math.max(1,math.min(math.max(1,#p.entries-visible_count+1),p.first+delta))
        if first~=p.first then p.first=first;draw_picker() end
    end
    G.FUNCS.sroll_pick=function(e)
        local p=R.picker
        if not p or p.overlay~=G.OVERLAY_MENU then return end
        local choice=e.config.ref_table
        if choice.field~=p.field then return end
        changed(choice.field,choice.key);R.open_menu()
    end
    G.FUNCS.sroll_picker_back=function()R.open_menu()end
    G.FUNCS.sroll_scroll_up=function()scroll_picker(-visible_count)end
    G.FUNCS.sroll_scroll_down=function()scroll_picker(visible_count)end
    local wheel_ref=love.wheelmoved
    love.wheelmoved=function(x,y,...)
        local p=R.picker
        if p and p.overlay==G.OVERLAY_MENU then
            p.wheel=p.wheel+y*3
            local steps=p.wheel>=0 and math.floor(p.wheel) or math.ceil(p.wheel)
            p.wheel=p.wheel-steps
            if steps~=0 then R.safe(function()scroll_picker(-steps)end) end
            return
        end
        if wheel_ref then return wheel_ref(x,y,...) end
    end
    local function selector(field,title)
        G.FUNCS['sroll_choose_'..field]=function()R.open_picker(field)end
        return {n=G.UIT.R,config={align='cm',padding=0.04},nodes={
            {n=G.UIT.C,config={align='cl',minw=2,maxw=2},nodes={
                {n=G.UIT.T,config={text=title,scale=0.28,colour=G.C.UI.TEXT_LIGHT}},
            }},
            UIBox_button{label={joker_name(C[field])},button='sroll_choose_'..field,col=true,minw=3.5,minh=0.43,scale=0.28},
        }}
    end
    local function exclusion(field,title)
        G.FUNCS['sroll_'..field]=function()changed(field,not C[field]);R.open_menu()end
        return UIBox_button{label={title..(C[field] and label('：开',': ON') or label('：关',': OFF'))},
            button='sroll_'..field,col=true,minw=2.7,minh=0.43,scale=0.27,
            colour=C[field] and G.C.GREEN or G.C.RED}
    end
    local function panel()
        local numbers={}
        for i=1,23 do numbers[i]={i,tostring(i)} end
        local rows={
            text(label('普通随机局 · 商店小丑牌筛选','Random runs · Shop Joker filter'),0.35),
            selector('joker',label('小丑牌 A（必选）','Joker A (required)')),
            selector('joker2',label('小丑牌 B（可选）','Joker B (optional)')),
            cycle('shop_min',label('起始商店 N','First shop N'),numbers),
            cycle('shop_max',label('结束商店 M','Last shop M'),numbers),
            {n=G.UIT.R,config={align='cm',padding=0.05},nodes={
                exclusion('exclude_perishable',label('排除易腐','No Perishable')),
                exclusion('exclude_rental',label('排除租用','No Rental')),
            }},
            text(label('范围：初始货架 + 刷新一次 + 小丑包；两张目标需都出现','Initial shelf + one reroll + Buffoon packs; BOTH targets required'),0.25),
            text(label('路线：不跳盲；从第 1 店起每店刷新一次','Route: no skips; reroll once at every shop starting at shop 1'),0.25),
            text(label('刷新后从左到右开小丑包，只查看不拿牌','After reroll: open Buffoons left-to-right; inspect, then skip'),0.25),
            text(label('不买货架商品/优惠券，不开其他包，不用消耗牌','No other purchases, packs or consumable use'),0.25),
            text(R.status,0.25),
        }
        if R.match_record then
            rows[#rows+1]=UIBox_button{label={label('查看命中位置','View last match')},
                button='sroll_results',minw=5.6,minh=0.45,scale=0.28}
        end
        local err=R.core.validate(C) or (R.message~=R.result and R.message)
        if err then rows[#rows+1]=text(short(err),0.23) end
        rows[#rows+1]={n=G.UIT.R,config={align='cm',padding=0.06},nodes={
            UIBox_button{label={label('开始筛选','Start')},button='sroll_start',col=true,minw=2.7,minh=0.5,scale=0.3},
            UIBox_button{label={label('停止筛选','Stop')},button='sroll_stop',col=true,minw=2.7,minh=0.5,scale=0.3},
        }}
        return {n=G.UIT.ROOT,config={align='cm',padding=0.06},nodes=rows}
    end
    mod.config_tab=panel
    mod.extra_tabs=nil
    G.FUNCS.sroll_start=function()R.perform('start')end
    G.FUNCS.sroll_results=function()R.safe(R.open_results)end
    G.FUNCS.sroll_stop=function()
        R.perform('stop')
        R.open_menu()
    end
    function R.open_menu()
        R.picker=nil
        G.SETTINGS.paused=true
        G.FUNCS.overlay_menu{definition=create_UIBox_generic_options{
            back_func='options',minw=7,padding=0.1,contents={menu_content(panel())},
        }}
    end
    function R.open_results()
        R.picker=nil
        local record=R.match_record
        if not record then return end
        local rows={
            text(label('筛选命中','Match found'),0.4),
            text(label('预计出现位置（按筛选时的操作路线）','Predicted locations along the search route'),0.27),
            text(label('随机局标识：','Random run: ')..record.seed,0.25),
        }
        for _,key in ipairs({record.config.joker,record.config.joker2}) do
            if key~='' then
                local hit=record.hits[key]
                local ok,name=pcall(localize,{type='name_text',set='Joker',key=key})
                if not ok or type(name)~='string' then name=key end
                local details
                if hit.source=='buffoon' then
                    details={
                        label('第 '..hit.shop..' 次商店 · 左起第 '..hit.pack_slot..' 个卡包（小丑包）',
                            'Shop '..hit.shop..' · Booster '..hit.pack_slot..' from left (Buffoon)'),
                        label('包内左起第 '..hit.slot..' 张','Card '..hit.slot..' from left inside the pack'),
                    }
                else
                    local source=hit.reroll==0 and label('初始货架','initial shelf') or label('刷新一次后的货架','shelf after one reroll')
                    details={
                        label('第 '..hit.shop..' 次商店 · ','Shop '..hit.shop..' · ')..source,
                        label('货架左起第 '..hit.slot..' 格','Shelf slot '..hit.slot..' from left'),
                    }
                end
                rows[#rows+1]={n=G.UIT.R,config={align='cm',padding=0.06},nodes={
                    {n=G.UIT.C,config={align='cm',minw=6.5,padding=0.03},nodes={
                        text(name,0.34),text(details[1],0.27),text(details[2],0.27),
                    }},
                }}
            end
        end
        if record.config.exclude_perishable then rows[#rows+1]=text(label('目标牌已排除易腐','Target matches exclude Perishable'),0.23) end
        if record.config.exclude_rental then rows[#rows+1]=text(label('目标牌已排除租用','Target matches exclude Rental'),0.23) end
        rows[#rows+1]=text(label('位置按每店刷新一次，再从左到右开小丑包计算',
            'Route: reroll once per shop, then open Buffoons left-to-right'),0.23)
        rows[#rows+1]=text(label('买牌、拿牌或跳盲可能改变后续结果',
            'Purchases, taking pack cards or skips may change later results'),0.23)
        G.SETTINGS.paused=true
        G.FUNCS.overlay_menu{definition=create_UIBox_generic_options{
            back_func='exit_overlay_menu',back_label=label('继续对局','Continue run'),
            minw=7,padding=0.1,contents={menu_content({nodes=rows})},
        }}
    end
end
