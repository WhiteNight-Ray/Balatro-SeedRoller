local M = {}
function M.copy(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}; if seen[t] then return seen[t] end
    local out = {}; seen[t] = out
    for k,v in pairs(t) do out[k] = M.copy(v,seen) end
    return setmetatable(out,getmetatable(t))
end
function M.validate(c)
    if type(c.joker) ~= 'string' or c.joker == '' then return '请选择目标小丑牌 A' end
    if type(c.joker2) ~= 'string' then return '目标 B 无效' end
    if c.joker == c.joker2 then return '请选择两张不同的小丑牌；只需一张时将 B 设为不选' end
    for _,k in ipairs({'shop_min','shop_max'}) do
        local n = c[k]
        if type(n) ~= 'number' or n ~= math.floor(n) or n < 1 or n > 23 then return '商店序号须为 1～23 的整数' end
    end
    if c.shop_min > c.shop_max then return '起始商店不能晚于结束商店' end
    if type(c.max_attempts) ~= 'number' or c.max_attempts < 1 or c.max_attempts > 100000 then return '搜索次数上限无效' end
end
-- Ante advances BEFORE the shop following a Boss victory.
function M.ante(shop) return math.floor(shop/3)+1 end
function M.match(c, rows)
    local hits = {}
    for _,row in ipairs(rows) do
        if row.shop >= c.shop_min and row.shop <= c.shop_max then
            for slot,key in ipairs(row.cards) do
                local attributes = row.attributes and row.attributes[slot] or {}
                local excluded = (c.exclude_perishable and attributes.perishable)
                    or (c.exclude_rental and attributes.rental)
                if (key == c.joker or key == c.joker2) and not hits[key] and not excluded then
                    hits[key] = {shop=row.shop,reroll=row.reroll,slot=slot,ante=row.ante,
                        source=row.source,pack_slot=row.pack_slot,pack_key=row.pack_key,
                        perishable=attributes.perishable or false,rental=attributes.rental or false}
                end
            end
        end
    end
    return hits[c.joker] ~= nil and (c.joker2 == '' or hits[c.joker2] ~= nil), hits
end
return M
