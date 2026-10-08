local Core=dofile('core.lua')
local P=dofile('predict.lua')(Core)
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function config(overrides)
    local c=dofile('config.lua');for k,v in pairs(overrides or {})do c[k]=v end;return c
end
test('range validation and one or two DISTINCT required targets',function()
    assert(not Core.validate(config()))
    assert(Core.validate(config{joker=''}))
    assert(Core.validate(config{joker2='j_blueprint'}))
    assert(Core.validate(config{shop_min=4,shop_max=2}))
    assert(Core.validate(config{shop_max=2.5}))
    assert(Core.validate(config{shop_max=24}))
end)
test('boss shop ante increments before generating cards',function()
    assert(Core.ante(1)==1 and Core.ante(2)==1 and Core.ante(3)==2)
    assert(Core.ante(5)==2 and Core.ante(6)==3 and Core.ante(23)==8)
end)
test('two targets can be split across shelf reroll and Buffoon',function()
    local c=config{joker2='j_brainstorm',shop_min=2,shop_max=3}
    local rows={{shop=1,source='initial',cards={'j_brainstorm'}},
        {shop=2,source='reroll',reroll=1,ante=1,cards={'j_blueprint'}},
        {shop=3,source='buffoon',pack_slot=2,ante=2,cards={'j_brainstorm'}}}
    local ok,h=Core.match(c,rows);assert(ok and h.j_blueprint.reroll==1 and h.j_brainstorm.pack_slot==2)
    rows[3]=nil;assert(not Core.match(c,rows))
end)
test('range endpoints included, outside excluded, one target sufficient',function()
    local c=config{shop_min=2,shop_max=2}
    assert(not Core.match(c,{{shop=1,cards={'j_blueprint'}},{shop=3,cards={'j_blueprint'}}}))
    assert(Core.match(c,{{shop=2,cards={'j_blueprint'}}}))
end)
local function fixture()
    G={SETTINGS={},ARGS={TEMP_POOL={original=true}},P_CENTERS={},P_CENTER_POOLS={Booster={}},playing_cards={},jokers={cards={}},
       GAME={pseudorandom={seed='TEST'},round_resets={ante=1},used_jokers={},used_vouchers={},banned_keys={},pool_flags={},
           shop={joker_max=2},joker_rate=1,tarot_rate=0,planet_rate=0,playing_card_rate=0,
           starting_params={boosters_in_shop=2},modifiers={}}}
    for _,key in ipairs({'j_blueprint','j_brainstorm','j_joker','j_third','j_fourth','j_fifth','j_sixth'})do
        G.P_CENTERS[key]={key=key,set='Joker',unlocked=true,rarity=1}
    end
    for _,key in ipairs({'p_buffoon_normal_1','p_buffoon_normal_2'})do
        G.P_CENTERS[key]={key=key,kind='Buffoon',config={extra=2}}
    end
    G.P_CENTER_POOLS.Booster={G.P_CENTERS.p_buffoon_normal_1,G.P_CENTERS.p_buffoon_normal_2}
    SMODS={optional_features={},ConsumableType={obj_buffer={'Tarot','Planet','Spectral'}}}
    function pseudoseed(key)
        G.GAME.pseudorandom[key]=(G.GAME.pseudorandom[key] or 0)+1;return key
    end
    function pseudorandom()return 0.5 end
    function get_current_pool(set,rarity,legend,append)
        G.ARGS.TEMP_POOL.mutated=true
        local out={}
        for _,key in ipairs({'j_blueprint','j_brainstorm','j_joker','j_third','j_fourth','j_fifth','j_sixth'})do
            if not G.GAME.used_jokers[key] then out[#out+1]=key end
        end
        return out,'Joker'..append..G.GAME.round_resets.ante
    end
    function pseudorandom_element(pool,key)return pool[1]end
    function get_pack()
        pseudoseed('shop_pack'..G.GAME.round_resets.ante)
        G.P_CENTERS.p_buffoon_normal_2.current_weight=999
        return G.P_CENTERS.p_buffoon_normal_2
    end
end
test('both shelves and both Buffoons projected; pack duplicate rules',function()
    fixture();local rows=P.shops(config{shop_max=1})
    assert(#rows==4 and rows[1].source=='initial' and rows[2].source=='reroll' and rows[4].source=='buffoon')
    assert(rows[1].cards[1]=='j_blueprint' and rows[2].cards[1]=='j_blueprint')
    assert(rows[3].cards[1]=='j_joker' and rows[3].cards[2]=='j_third')
    assert(rows[4].cards[1]=='j_joker') -- first pack skipped, shelf cards still visible
end)
test('all earlier shops simulated even when N is later',function()
    fixture();local a=P.shops(config{shop_min=3,shop_max=3})
    local b=P.shops(config{shop_min=1,shop_max=3})
    assert(#a==#b and #a==12 and a[1].shop==1 and a[9].ante==2)
end)
test('original RNG, pools, ante, flags and pack weights restored',function()
    fixture();local original,pool=G.GAME,G.ARGS.TEMP_POOL
    P.shops(config{shop_max=4})
    assert(G.GAME==original and G.ARGS.TEMP_POOL==pool and not pool.mutated)
    assert(original.round_resets.ante==1 and not original.first_shop_buffoon)
    assert(not original.pseudorandom.cdt1 and not next(original.used_jokers))
    assert(not G.P_CENTERS.p_buffoon_normal_2.current_weight)
end)
test('rollback on prediction error',function()
    fixture();local original,pool=G.GAME,G.ARGS.TEMP_POOL
    get_pack=function()G.GAME.round_resets.ante=99;error('fault')end
    assert(not pcall(P.shops,config()))
    assert(G.GAME==original and G.ARGS.TEMP_POOL==pool and original.round_resets.ante==1)
end)
test('paused prediction refused and unsupported content rejected',function()
    fixture();G.SETTINGS.paused=true;assert(not pcall(P.shops,config()))
    G.SETTINGS.paused=false;assert(not P.check_support(config()))
    SMODS.optional_features.object_weights=true;assert(P.check_support(config()))
    SMODS.optional_features.object_weights=false;G.P_CENTERS.j_blueprint.mod={id='content'};assert(P.check_support(config()))
end)
test('locked, legendary and conditional targets rejected',function()
    fixture();G.P_CENTERS.j_blueprint.unlocked=false;assert(P.check_support(config()))
    G.P_CENTERS.j_blueprint.unlocked=true;G.P_CENTERS.j_blueprint.rarity=4;assert(P.check_support(config()))
    G.P_CENTERS.j_blueprint.rarity=1;G.P_CENTERS.j_blueprint.yes_pool_flag='missing';assert(P.check_support(config()))
end)
local function runtime(seeded)
    fixture()
    local function engine_game(mode)
        local g=Core.copy(G.GAME)
        rawset(g,'seeded',nil);g._engine_seeded=mode
        setmetatable(g,{__index=function(t,k)if k=='seeded'then return rawget(t,'_engine_seeded')end end,
            __newindex=function(t,k,v)assert(k~='seeded','Mod must never assign seeded');rawset(t,k,v)end})
        return g
    end
    G.GAME=engine_game(seeded or false)
    local g=G.GAME;g.round=0;g.skips=0;g.stake=2;g.selected_back={effect={center={name='Blue Deck',key='b_blue'}}}
    G.STAGES={RUN=1};G.STATES={BLIND_SELECT=2};G.STAGE=1;G.STATE=2
    G.SETTINGS={profile=1,tutorial_complete=true,language='zh_CN'};G.CONTROLLER={locks={}}
    G.FUNCS={exit_overlay_menu=function()G.OVERLAY_MENU=nil;G.SETTINGS.paused=false end}
    G.UIT={ROOT='root',R='row',C='column',T='text'};G.C={BLACK={},UI={TEXT_LIGHT={}}}
    Game={update=function()end};setmetatable(G,{__index=Game})
    G.files={};love={draw=function()end,mousepressed=function()end,mousereleased=function()end,
        filesystem={createDirectory=function()return true end,write=function(k,v)G.files[k]=v;return true end}}
    SMODS.current_mod={id='SeedRoller',config=config()}
    SMODS.load_file=function(file)return loadfile(file)end
    SMODS.save_mod_config=function()end
    SMODS.Keybind=function()error('No shortcuts allowed')end
    STR_PACK=function(record)G.last_record=record;return 'record'end
    save_run=function()G.saved=true end
    function Game:delete_run()self.deleted=(self.deleted or 0)+1 end
    function Game:start_run(args)
        assert(args.seed==nil and args.savetext==nil and args.challenge==nil,'Must use native unseeded start')
        self.last_args=args
        self.GAME=engine_game(false)
        self.GAME.pseudorandom={seed='NATIVE'..self.deleted}
    end
    function UIBox_button(args)return {n=args.col and G.UIT.C or G.UIT.R,args=args,nodes={{n=G.UIT.C,config={button=args.button}}}}end
    function create_UIBox_options()return {nodes={{nodes={UIBox_button{button='settings'}}}}}end
    function create_option_cycle(args)G.cycles=G.cycles or {};G.cycles[#G.cycles+1]=args;return {n=G.UIT.R,args=args}end
    function localize(a)return a.key end
    function create_UIBox_generic_options(args)return args end
    function UIBox(args)
        G.last_overlay=args.definition
        return {remove=function()end,align_to_major=function()end}
    end
    G.FUNCS.overlay_menu=function(args)G.overlay_opens=(G.overlay_opens or 0)+1;G.OVERLAY_MENU=UIBox(args)end
    G.original_draw=love.draw;G.original_press=love.mousepressed
    dofile('main.lua');return SeedRoller
end
test('matched candidate is original unseeded run, not reopened by seed',function()
    local r=runtime();local g=G.GAME;r.start();G:update(1)
    assert(not r.active and G.GAME==g and not G.GAME.seeded and not G.deleted)
    assert(G.saved and G.last_record.seeded==false and G.last_record.hits.j_blueprint)
end)
test('failed candidate uses native random start preserving deck/stake',function()
    local r=runtime();r.predictor.shops=function()return {}end;r.start();G:update(1)
    assert(r.active and G.deleted==1 and not G.GAME.seeded)
    assert(G.last_args.seed==nil and G.last_args.stake==2 and G.last_args.deck_choice.key=='b_blue')
end)
test('existing seeded opening discarded, never converted by flag write',function()
    local r=runtime(true);local old=G.GAME;r.start()
    assert(old.seeded and G.GAME~=old and not G.GAME.seeded and G.deleted==1)
    G:update(1);assert(G.last_record.seeded==false)
end)
test('all selected targets required including pack hits',function()
    local r=runtime();r.mod.config.joker='j_joker';r.mod.config.joker2='j_third';r.start();G:update(1)
    assert(not r.active and G.last_record.hits.j_joker.source=='buffoon')
end)
test('limit stops without launching an extra candidate',function()
    local r=runtime();r.mod.config.max_attempts=2;r.predictor.shops=function()return {}end;r.start();G:update(1);G:update(1)
    assert(not r.active and r.attempts==2 and G.deleted==1)
end)
test('explicit stop cancels next evaluation',function()
    local r=runtime();r.start();r.stop();G:update(1);assert(not G.deleted and r.attempts==0)
end)
test('menus pause and foreign run replacement aborts',function()
    local r=runtime();r.start();G.OVERLAY_MENU={};G:update(40);assert(r.active and r.attempts==0)
    G.OVERLAY_MENU=nil;G.GAME=Core.copy(G.GAME);G:update(1);assert(not r.active)
end)
test('progressed run rejected and load timeout handled',function()
    local r=runtime();G.GAME.round=1;r.start();assert(not r.active)
    G.GAME.round=0;r.start();G.CONTROLLER.locks.load=true;G:update(31);assert(not r.active)
end)
test('another mod changing random mode causes stop',function()
    local r=runtime();r.start();G.GAME._engine_seeded=true;G:update(1);assert(not r.active and not G.saved)
end)
test('legacy configuration migrated to minimal schema',function()
    local r=runtime();r.mod.config.schema=3;r.mod.config.soul=true
    dofile('main.lua');assert(SeedRoller.mod.config.schema==4 and SeedRoller.mod.config.soul==nil)
end)
test('compact UI keeps numeric cycles and replaces target cycles with lists',function()
    local r=runtime();local p=r.mod.config_tab();assert(#G.cycles==2 and not r.mod.extra_tabs)
    for _,a in ipairs(G.cycles)do assert(a.no_pips and a.h*a.scale<0.4)end
    local actions=p.nodes[#p.nodes];assert(#actions.nodes==2 and actions.nodes[1].n==G.UIT.C)
    assert(love.draw==G.original_draw and love.mousepressed==G.original_press)
end)
test('options entry and start close native menu without hotkeys',function()
    local r=runtime();local rows=create_UIBox_options().nodes[1].nodes
    assert(rows[2].nodes[1].config.button=='sroll_open')
    G.FUNCS.sroll_open();assert(G.last_overlay.back_func=='options' and G.SETTINGS.paused)
    G.FUNCS.sroll_start();assert(r.active and not G.SETTINGS.paused and not G.OVERLAY_MENU)
end)
local function collect_text(node,out)
    out=out or {}
    if node.config and node.config.text then out[#out+1]=node.config.text end
    for _,child in ipairs(node.nodes or {})do collect_text(child,out)end
    return out
end
local function assert_no_root(node)
    assert(node.n~=G.UIT.ROOT,'Nested ROOT recreates the offset bug')
    for _,child in ipairs(node.nodes or {})do assert_no_root(child)end
end
test('match auto-opens paused result dialog and Continue preserves random run',function()
    local r=runtime();local original=G.GAME;r.start();G:update(1)
    assert(not r.active and G.SETTINGS.paused and G.OVERLAY_MENU)
    assert(G.last_overlay.back_func=='exit_overlay_menu' and G.last_overlay.back_label=='继续对局')
    assert(G.GAME==original and not G.GAME.seeded)
    G.FUNCS.exit_overlay_menu();G:update(1)
    assert(not G.SETTINGS.paused and not G.deleted and G.GAME==original)
end)
test('result dialog distinguishes initial shelf, reroll and pack positions',function()
    local r=runtime()
    r.match_record={seed='LOCATIONS',config={joker='j_blueprint',joker2='j_brainstorm'},hits={
        j_blueprint={shop=3,source='initial',reroll=0,slot=2},
        j_brainstorm={shop=4,source='buffoon',pack_slot=2,slot=1},
    }}
    r.open_results()
    local txt=table.concat(collect_text(G.last_overlay.contents[1]),'\n')
    assert(txt:find('第 3 次商店 · 初始货架',1,true) and txt:find('货架左起第 2 格',1,true))
    assert(txt:find('第 4 次商店 · 左起第 2 个卡包（小丑包）',1,true) and txt:find('包内左起第 1 张',1,true))
    r.match_record.hits.j_blueprint.reroll=1;r.match_record.hits.j_blueprint.source='reroll'
    r.open_results();txt=table.concat(collect_text(G.last_overlay.contents[1]),'\n')
    assert(txt:find('刷新一次后的货架',1,true))
end)
test('settings and results share native frame origin with no embedded ROOT',function()
    local r=runtime();r.open_menu()
    assert(G.last_overlay.minw==7 and G.last_overlay.contents[1].n==G.UIT.C)
    assert_no_root(G.last_overlay.contents[1])
    assert(r.mod.config_tab().n==G.UIT.ROOT) -- independent SMODS config UI keeps its own root
    G.FUNCS.sroll_start();G:update(1)
    assert(G.last_overlay.back_label=='继续对局')
    assert_no_root(G.last_overlay.contents[1])
end)
test('last match can be reopened and uses captured targets not changed settings',function()
    local r=runtime();r.start();G:update(1)
    G.FUNCS.exit_overlay_menu();r.mod.config.joker='j_brainstorm'
    G.FUNCS.sroll_results()
    local txt=table.concat(collect_text(G.last_overlay.contents[1]),'\n')
    assert(txt:find('j_blueprint',1,true) and not txt:find('j_brainstorm',1,true))
end)
test('dirty targets rejected; later clean copies and independent switches accepted',function()
    local c=config{joker2='j_brainstorm'}
    local rows={
        {shop=1,cards={'j_blueprint','j_brainstorm'},attributes={{perishable=true},{rental=true}}},
        {shop=2,source='buffoon',pack_slot=2,cards={'j_blueprint'},attributes={{}}},
        {shop=3,source='reroll',cards={'j_brainstorm'},attributes={{}}},
    }
    local ok,h=Core.match(c,rows)
    assert(ok and h.j_blueprint.shop==2 and h.j_brainstorm.shop==3)
    rows[3]=nil;assert(not Core.match(c,rows))
    c.exclude_rental=false;assert(Core.match(c,rows))
    rows[2]=nil;assert(not Core.match(c,rows))
    c.exclude_perishable=false;ok,h=Core.match(c,rows)
    assert(ok and h.j_blueprint.perishable and h.j_brainstorm.rental)
end)
test('sticker polls use distinct shelf/pack streams and exact boundary rules',function()
    fixture();local m=G.GAME.modifiers
    m.enable_eternals_in_shop=true;m.enable_perishables_in_shop=true;m.enable_rentals_in_shop=true
    for _,obj in pairs(G.P_CENTERS)do obj.perishable_compat=true;obj.eternal_compat=true end
    local rolls={etperpoll1=0.7,packetper1=0.4,ssjr1=0.71,packssjr1=0.7}
    local seen={}
    pseudorandom=function(key)seen[key]=(seen[key] or 0)+1;return rolls[key] or 0.5 end
    local rows=P.shops(config{shop_max=1})
    assert(rows[1].attributes[1].perishable and rows[1].attributes[1].rental)
    assert(not rows[3].attributes[1].perishable and not rows[3].attributes[1].rental)
    assert(seen.etperpoll1==4 and seen.packetper1==4 and seen.ssjr1==4 and seen.packssjr1==4)
    m.all_eternal=true;rows=P.shops(config{shop_max=1});assert(not rows[1].attributes[1].perishable)
    m.all_eternal=false;G.P_CENTERS.j_blueprint.perishable_compat=false
    rows=P.shops(config{shop_max=1});assert(not rows[1].attributes[1].perishable)
    m.enable_rentals_in_shop=false;seen={};P.shops(config{shop_max=1});assert(not seen.ssjr1)
end)
test('changed sticker generation rules refused',function()
    fixture();SMODS.Stickers={rental={should_apply=function()end}}
    assert(P.check_support(config()))
end)
test('list wheel scroll clamps, preserves overlay context and selects clicked key',function()
    local r=runtime()
    for i=1,40 do local key='j_list_'..i;G.P_CENTERS[key]={key=key,set='Joker',order=i,rarity=1,unlocked=true} end
    r.open_picker('joker');local opens=G.overlay_opens
    assert_no_root(G.last_overlay.contents[1])
    love.wheelmoved(0,-1);assert(r.picker.first==4 and G.overlay_opens==opens)
    love.wheelmoved(0,-100);assert(r.picker.first==#r.picker.entries-7)
    love.wheelmoved(0,100);assert(r.picker.first==1)
    G.FUNCS.sroll_scroll_down();assert(r.picker.first==9)
    local row=G.last_overlay.contents[1].nodes[3]
    G.FUNCS.sroll_pick{config={ref_table=row.args.ref_table}}
    assert(r.mod.config.joker==row.args.ref_table.key and r.picker==nil)
    r.open_picker('joker2');assert(r.picker.entries[1][1]=='')
    G.FUNCS.sroll_pick{config={ref_table={field='joker2',key=''}}};assert(r.mod.config.joker2=='')
end)
test('wheel only consumed by the active picker and supports fractional input',function()
    local r=runtime();local calls=0
    love.wheelmoved=function()calls=calls+1 end
    dofile('ui.lua')(r)
    love.wheelmoved(0,-1);assert(calls==1)
    for i=1,20 do G.P_CENTERS['j_scroll'..i]={set='Joker',rarity=1} end
    r.open_picker('joker2');love.wheelmoved(0,-0.2);assert(r.picker.first==1)
    love.wheelmoved(0,-0.2);assert(r.picker.first==2 and calls==1)
    G.FUNCS.exit_overlay_menu();love.wheelmoved(0,-1);assert(calls==2)
    r.open_picker('joker');G.OVERLAY_MENU={};love.wheelmoved(0,-1);assert(calls==3)
end)
test('exclusion toggles default on, save independently and preserve selected targets',function()
    local r=runtime();local c=r.mod.config;r.open_menu()
    assert(c.exclude_perishable and c.exclude_rental)
    G.FUNCS.sroll_exclude_perishable();assert(not c.exclude_perishable and c.exclude_rental and c.joker=='j_blueprint')
    G.FUNCS.sroll_exclude_rental();assert(not c.exclude_rental)
    c.exclude_perishable=nil;c.exclude_rental=nil;c.shop_min=2
    dofile('main.lua');assert(c.exclude_perishable and c.exclude_rental and c.shop_min==2)
end)
print(('ALL %d TESTS PASSED'):format(count))
