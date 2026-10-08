local mod=SMODS.current_mod
local Core=assert(SMODS.load_file('core.lua'))()
local P=assert(SMODS.load_file('predict.lua'))()(Core)
local defaults=assert(SMODS.load_file('config.lua'))()
-- Replace legacy filter configuration once; keep only this version's settings.
if mod.config.schema ~= 4 then
    for k in pairs(mod.config) do mod.config[k]=nil end
    for k,v in pairs(defaults) do mod.config[k]=v end
    SMODS.save_mod_config(mod)
end
for k,v in pairs(defaults) do if mod.config[k]==nil then mod.config[k]=v end end
local R={mod=mod,core=Core,predictor=P,active=false,attempts=0,status='就绪 / Ready',result=''}
SeedRoller=R
local function message(s) R.message=tostring(s);print('[SeedRoller] '..R.message) end
function R.stop(s) R.active=false;R.status=s or '已停止 / Stopped' end
function R.safe(fn)
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then R.stop('发生错误，请查看提示');message(err) end
end
local function fresh()
    return G and G.GAME and G.STAGE==G.STAGES.RUN and G.STATE==G.STATES.BLIND_SELECT
        and G.GAME.round==0 and (G.GAME.skips or 0)==0 and G.GAME.round_resets.ante==1
        and not G.GAME.challenge and not G.SETTINGS.paused and not G.OVERLAY_MENU
        and not G.CONTROLLER.locks.load
end
local function brain_search()
    return Brainstorm and Brainstorm.AUTOREROLL and Brainstorm.AUTOREROLL.autoRerollActive
end
local function reroll()
    G:delete_run()
    -- IMPORTANT: no seed, saved run, challenge or forced-seed arguments.
    -- Game:start_run calls the game's own generate_starting_seed().
    G:start_run({stake=R.stake,deck_choice=R.deck})
    R.last_game,R.waited,R.elapsed=G.GAME,0,0
    assert(not G.GAME.seeded,'其他 Mod 将新局变成了种子局，已停止')
end
function R.start()
    if R.active then return end
    if not fresh() then message('先开普通新局，停在未打牌、未跳盲的底注 1，等加载完成再开始');return end
    if not G.SETTINGS.tutorial_complete then message('请先完成教程');return end
    if brain_search() then message('请先关闭 Brainstorm 自动搜索');return end
    local c=Core.copy(mod.config)
    local err=Core.validate(c) or P.check_support(c)
    if err then message(err);R.status='配置不可用';return end
    R.config,R.active,R.attempts,R.elapsed,R.waited=c,true,0,0,0
    R.last_game,R.profile=G.GAME,G.SETTINGS.profile
    R.stake,R.deck=G.GAME.stake,G.GAME.selected_back.effect.center
    R.seen,R.duplicates,R.result,R.result_lines,R.message={},0,'',{},nil
    R.status='正在筛选普通随机局'
    -- An existing seeded opening is discarded, never relabelled.
    if G.GAME.seeded then reroll() end
end
local function name(key)
    local ok,v=pcall(localize,{type='name_text',set='Joker',key=key})
    return ok and type(v)=='string' and v or key
end
local function found(rows,hits)
    assert(not G.GAME.seeded,'不能把种子局当作随机局交付')
    R.stop('已找到普通随机局；当前位置保留在开局')
    local parts={}
    for _,key in ipairs({R.config.joker,R.config.joker2}) do
        if key~='' then
            local h=hits[key]
            local source=h.source=='buffoon' and ('第'..h.pack_slot..'个小丑包') or (h.reroll==0 and '初始货架' or '刷新后货架')
            parts[#parts+1]=name(key)..'：第'..h.shop..'店'..source..'第'..h.slot..'格'
        end
    end
    R.result=table.concat(parts,' / ')
    R.result_lines=parts
    message(R.result)
    local record={seed=G.GAME.pseudorandom.seed,seeded=not not G.GAME.seeded,config=R.config,
        hits=hits,shops=rows,deck=R.deck.key,stake=R.stake,profile=R.profile,attempts=R.attempts,
        route='no skips; one reroll per shop from shop 1; then all Buffoon packs left-to-right; skip without taking cards; no other purchases/use',
        at=os.date('%Y-%m-%d %H:%M:%S'),projection=true}
    R.match_record=record
    local ok,err=pcall(function()
        assert(love.filesystem.createDirectory('SeedRoller'))
        assert(love.filesystem.write('SeedRoller/random_match.lua',STR_PACK(record)))
    end)
    if not ok then message('已找到，但记录保存失败：'..tostring(err)) end
    if save_run then save_run() end
    if play_sound then play_sound('coin1') end
    R.open_results()
end
local function tick(dt)
    if not R.active then return end
    if G.SETTINGS.profile~=R.profile or G.STAGE~=G.STAGES.RUN or G.GAME~=R.last_game then R.stop('对局已被外部更换');return end
    if brain_search() then R.stop('Brainstorm 正在运行');return end
    if G.OVERLAY_MENU or G.SETTINGS.paused then return end
    if G.GAME.seeded then R.stop('检测到种子局，已停止');return end
    if G.STATE~=G.STATES.BLIND_SELECT then R.stop('已离开开局选盲画面');return end
    R.waited=R.waited+dt
    if not fresh() then
        if R.waited>30 then R.stop('等待加载超时') end
        return
    end
    R.elapsed=R.elapsed+dt
    if R.elapsed<(R.config.interval or 0.25) then return end
    local seed=G.GAME.pseudorandom.seed
    if R.seen[seed] then
        R.duplicates=R.duplicates+1
        if R.duplicates>=5 then R.stop('重复随机局：移动鼠标后再开始');return end
        reroll();return
    end
    R.duplicates=0;R.seen[seed]=true;R.attempts=R.attempts+1
    R.status='已检查 '..R.attempts..' / '..R.config.max_attempts..' 个随机局'
    local rows=P.shops(R.config)
    local matched,hits=Core.match(R.config,rows)
    if matched then found(rows,hits);return end
    if R.attempts>=R.config.max_attempts then R.stop('达到搜索上限：'..R.attempts);return end
    reroll()
end
local previous_update=Game.update
function Game:update(dt)
    previous_update(self,dt)
    R.safe(function()tick(dt)end)
end
assert(SMODS.load_file('ui.lua'))()(R)
assert(SMODS.load_file('toolbar.lua'))()(R)
