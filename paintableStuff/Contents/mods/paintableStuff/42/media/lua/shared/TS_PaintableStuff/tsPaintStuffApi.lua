-- TeaStain 16/11/2026

require "BuildingObjects/ISPaintMenu"

-- Paintable items can be registered as follows:

--[[
    require "TS_PaintableStuff/tsPaintStuffApi"

    TS_PaintStuff.registerPaintable("Base.Crowbar", { index = 0, worldPainted = "TS_CrowbarWorldPaint" })
]]
   
-- The optional `index` is the texture index the tint should be applied to.
-- Supplying `index` also normalises painted items to that model index (for example a
-- forged crowbar becomes the normal variant). Omit `index` to keep the item's current
-- model index, which is safer for items with variants managed by other mods.
-- A tint mask should be added, the name should be "[ItemTextureName]TINT.png".

-- The `worldPainted` option is the ground model used while painted. Without it,
-- no world model override is applied for that item.
-- It can be a model script name or a table keyed by model index (with an optional `default`).
-- Generate these models with the python script at "scripts/gen_world_models.py".

TS_PaintStuff = TS_PaintStuff or {}
local TSPS = TS_PaintStuff

TSPS.API_VERSION = 1
TSPS.MODULE = "TS_PaintableStuff"
TSPS.Paintables = TSPS.Paintables or {}
TSPS.MAX_MIX_PARTS = 10
TSPS.PETROL_PER_REMOVAL = 0.5

TSPS.DEBUG = false

function TSPS.side()
    if isServer() then return "SERVER" end
    if isClient() then return "CLIENT" end
    return "SP"
end

function TSPS.tableToString(tbl)
    if type(tbl) ~= "table" then return tostring(tbl) end
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Clamp rgb values to the valid range 0 - 0.99
function TSPS.clampRGB(r, g, b)
    local rClmp = math.max(0, math.min(0.99, tonumber(r) or 0.99))
    local gClmp = math.max(0, math.min(0.99, tonumber(g) or 0.99))
    local bClmp = math.max(0, math.min(0.99, tonumber(b) or 0.99))
    return rClmp, gClmp, bClmp
end

function TSPS.log(...)
    if not TSPS.DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print("[TSPS] " .. TSPS.side() .. " | " .. table.concat(parts, " "))
end

function TSPS.logItem(tag, item)
    if not TSPS.DEBUG then return end
    if not item then
        TSPS.log(tag, "item=nil")
        return
    end
    TSPS.log(tag,
        "type", item:getFullType(),
        "id", item:getID(),
        "painted", tostring(TSPS.isPainted(item)),
        "modelRGB", item:getColorRed(), item:getColorGreen(), item:getColorBlue(),
        "col", item:getR(), item:getG(), item:getB(),
        "customColor", tostring(item:isCustomColor()))
end

function TSPS.registerPaintable(fullType, opts)
    -- `index` is optional. When omitted, painting keeps the item's current model index.
    local index = opts and tonumber(opts.index)
    if index then index = math.max(0, math.floor(index)) end
    TSPS.Paintables[fullType] = {
        index = index,
        worldPainted = opts and opts.worldPainted,
    }
end

function TSPS.unregisterPaintable(fullType)
    TSPS.Paintables[fullType] = nil
end

function TSPS.getPaintable(fullType)
    return TSPS.Paintables[fullType]
end

function TSPS.isPaintable(item)
    return item ~= nil and TSPS.Paintables[item:getFullType()] ~= nil
end

local palette

function TSPS.getPalette()
    if not palette then
        palette = {}
        for _, entry in ipairs(ISPaintMenu.PaintMenuItems) do
            palette[entry.paint] = entry
        end
    end
    return palette
end

function TSPS.findItem(player, id)
    return player:getInventory():getFirstEvalRecurse(function(item) return item:getID() == id end)
end

function TSPS.isInPlayerInventory(player, item)
    return item ~= nil and item:getOutermostContainer() == player:getInventory()
end

function TSPS.asSources(value, player)
    if value == nil and player then value = player:getInventory() end
    if value == nil then return nil end
    if type(value) == "table" and value.containers ~= nil then
        return value
    end
    return { containers = { value } }
end

function TSPS.toArrayList(values)
    local list = ArrayList.new()
    if values then
        if values.size and values.get then
            for i = 0, values:size() - 1 do
                list:add(values:get(i))
            end
        else
            for _, value in ipairs(values) do
                list:add(value)
            end
        end
    end
    return list
end

function TSPS.toActionList(sources)
    if not sources then return nil end
    return TSPS.toArrayList(sources.containers)
end

local function eachList(list, callback)
    if not list then return end
    if list.size and list.get then
        for i = 0, list:size() - 1 do
            callback(list:get(i))
        end
    else
        for _, value in ipairs(list) do
            callback(value)
        end
    end
end

function TSPS.forEachSourceItem(sources, callback, player)
    sources = TSPS.asSources(sources, player)
    if not sources then return end

    local seen = {}
    eachList(sources.containers, function(container)
        if not container then return end
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local id = item:getID()
                if not seen[id] then
                    seen[id] = true
                    callback(item)
                end
            end
        end
    end)
end

function TSPS.findInSources(sources, predicate, player)
    local found
    TSPS.forEachSourceItem(sources, function(item)
        if not found and predicate(item) then found = item end
    end, player)
    return found
end

function TSPS.findItemInSources(sources, id)
    return TSPS.findInSources(sources, function(item) return item:getID() == id end)
end

function TSPS.resolveItem(player, item)
    if not item then return nil end

    local worldItem = item.getWorldItem and item:getWorldItem() or nil
    if worldItem then
        local current = worldItem:getItem()
        if current and current:getID() == item:getID() then return current end
    end

    local container = item.getContainer and item:getContainer() or nil
    if container then
        local found = container:getItemWithID(item:getID())
        if found then return found end
    end

    return TSPS.findItem(player, item:getID())
end

function TSPS.resolveTarget(player, item, worldItem)
    if worldItem then
        local current = worldItem:getItem()
        if not current then return nil end
        if item and current:getID() ~= item:getID() then return nil end
        return current
    end
    return TSPS.resolveItem(player, item)
end

function TSPS.hasBrush(sources, player)
    return TSPS.findInSources(sources, function(item)
        return item:hasTag(ItemTag.PAINTBRUSH)
    end, player) ~= nil
end

function TSPS.isType(item, typeName)
    if typeName == nil then return false end
    if typeName:find(".", 1, true) then
        return item:getFullType() == typeName or item:getType() == typeName
    end
    return item:getType() == typeName
end

function TSPS.findUsableTin(sources, paintType, player)
    return TSPS.findInSources(sources, function(item)
        return TSPS.isType(item, paintType) and item:getCurrentUses() > 0
    end, player)
end

function TSPS.getAvailablePaints(sources, player)
    local usesByType = {}
    TSPS.forEachSourceItem(sources, function(item)
        local uses = item.getCurrentUses and item:getCurrentUses() or 0
        if uses > 0 then
            local typeName = item:getType()
            usesByType[typeName] = (usesByType[typeName] or 0) + uses
        end
    end, player)

    local result = {}
    for _, entry in ipairs(ISPaintMenu.PaintMenuItems) do
        local uses = usesByType[entry.paint] or 0
        if uses > 0 then
            result[#result + 1] = { entry = entry, uses = uses }
        end
    end
    return result
end

function TSPS.hasPaints(sources, mix, player)
    for _, part in ipairs(mix) do
        if part.parts > 0 and not TSPS.findUsableTin(sources, part.paint, player) then
            return false
        end
    end
    return true
end

function TSPS.canPaint(player, item, mix, sources)
    return TSPS.isPaintable(item)
        and TSPS.hasBrush(sources, player)
        and TSPS.hasPaints(sources, mix, player)
end

-- One use per included paint, regardless of amount used
function TSPS.consumePaint(sources, mix, player)
    for _, part in ipairs(mix) do
        if part.parts > 0 then
            local tin = TSPS.findUsableTin(sources, part.paint, player)
            if not tin then return false end
            TSPS.log("consumePaint", part.paint, "tinId", tin:getID(), "usesBefore", tin:getCurrentUses())
            tin:UseAndSync()
            if isServer() and sendItemStats then sendItemStats(tin) end
        end
    end
    return true
end

function TSPS.mixColor(mix)
    local entries = {}
    local pal = TSPS.getPalette()
    for _, part in ipairs(mix) do
        local entry = pal[part.paint]
        if entry and part.parts > 0 then
            entries[#entries + 1] = { r = entry.color[1], g = entry.color[2], b = entry.color[3], parts = part.parts }
        end
    end
    return TS_PaintColour.mix(entries, mix.sat, mix.val)
end

function TSPS.mixToString(mix)
    local parts = {}
    for _, part in ipairs(mix) do
        if part.parts > 0 then
            parts[#parts + 1] = part.paint .. "=" .. part.parts
        end
    end
    return table.concat(parts, ";")
end

function TSPS.mixFromString(str)
    local mix = {}
    for paint, parts in string.gmatch(str or "", "([^=;]+)=(%d+)") do
        mix[#mix + 1] = { paint = paint, parts = tonumber(parts) }
    end
    return mix
end

function TSPS.sanitizeMix(mix)
    local pal = TSPS.getPalette()
    local clean, seen = {}, {}
    for _, part in ipairs(mix) do
        local parts = tonumber(part.parts) or 0
        if pal[part.paint] and parts > 0 and not seen[part.paint] then
            seen[part.paint] = true
            clean[#clean + 1] = { paint = part.paint, parts = math.min(parts, TSPS.MAX_MIX_PARTS) }
        end
    end
    return clean
end

-- Painting

local function refreshItem(item, player)
    if item:getContainer() then item:getContainer():setDrawDirty(true) end
    if player and player:isLocalPlayer()
        and (player:isEquipped(item) or player:isAttachedItem(item)) then
        player:resetModelNextFrame()
    end
end

local function safeIndex(item, index)
    local lists = { item:getIconsForTexture(), item:getStaticModelsByIndex(), item:getWorldStaticModelsByIndex() }
    if instanceof(item, "HandWeapon") then
        lists[#lists + 1] = item:getWeaponSpritesByIndex()
    end
    for _, list in ipairs(lists) do
        if list and list:size() > 0 and index >= list:size() then return 0 end
    end
    return index
end

function TSPS.applyPaint(item, r, g, b, mix, index, player)
    local registration = TSPS.Paintables[item:getFullType()]
    local previous = item:getModData().TS_Paint
    local modelIdx = item:getModelIndex()
    local originalIdx = previous and previous.idx or modelIdx
    local targetIdx = index or (registration and registration.index)
    if targetIdx ~= nil then targetIdx = safeIndex(item, targetIdx) end
    TSPS.log("applyPaint",
        "id", item:getID(),
        "rgb", r, g, b,
        "mix", TSPS.tableToString(mix),
        "index", tostring(targetIdx),
        "modelIndex", modelIdx,
        "originalIdx", originalIdx,
        "localPlayer", tostring(player ~= nil and player:isLocalPlayer()))
    if targetIdx ~= nil and modelIdx ~= targetIdx then item:setModelIndex(targetIdx) end

    item:setColorRed(r)
    item:setColorGreen(g)
    item:setColorBlue(b)
    item:setColor(Color.new(1, 1, 1, 1))
    item:setCustomColor(false)
    item:getModData().TS_Paint = { r = r, g = g, b = b, mix = mix, v = 1, idx = originalIdx }
    if (isClient() or not isServer()) and TSPS.updateWorldModel then
        TSPS.updateWorldModel(item)
    end
    refreshItem(item, player)
    TSPS.logItem("applyPaint done", item)
end

function TSPS.clearPaint(item, player)
    TSPS.log("clearPaint", "id", item:getID(), "localPlayer", tostring(player ~= nil and player:isLocalPlayer()))
    TSPS.logItem("clearPaint before", item)
    local paint = item:getModData().TS_Paint
    local index = paint and paint.idx
    if index ~= nil then
        local modelIdx = item:getModelIndex()
        if modelIdx ~= index then item:setModelIndex(index) end
    end

    item:setColorRed(1)
    item:setColorGreen(1)
    item:setColorBlue(1)
    item:setColor(Color.new(1, 1, 1, 1))
    item:setCustomColor(false)
    item:getModData().TS_Paint = nil
    if (isClient() or not isServer()) and TSPS.updateWorldModel then
        TSPS.updateWorldModel(item)
    end
    refreshItem(item, player)
    TSPS.logItem("clearPaint done", item)
end

-- InventoryItem.load() copies colorRed/Green/Blue into col,
-- this causes the icon to be tinted after reload.
-- This function resets the tint.
function TSPS.ensureIconUntinted(item)
    if not item or not item:getModData().TS_Paint then return end
    if item:getR() ~= 1 or item:getG() ~= 1 or item:getB() ~= 1 then
        item:setColor(Color.new(1, 1, 1, 1))
        item:setCustomColor(false)
    end
end

function TSPS.isPainted(item)
    return item ~= nil and item:getModData().TS_Paint ~= nil
end

function TSPS.getPaintColor(item)
    return item and item:getModData().TS_Paint
end

-- Paint removal

function TSPS.isPetrolSource(item)
    local fc = item:getFluidContainer()
    return fc ~= nil and fc:contains(Fluid.Petrol) and fc:getAmount() >= TSPS.PETROL_PER_REMOVAL
end

function TSPS.findSolvent(sources, player)
    return TSPS.findInSources(sources, TSPS.isPetrolSource, player)
end

TSPS.Cloths = {
    ["Base.RippedSheets"] = true,
    ["Base.RippedSheetsDirty"] = true,
}

function TSPS.registerCloth(fullType)
    TSPS.Cloths[fullType] = true
end

function TSPS.isCloth(item)
    if item == nil or item:isBroken() or instanceof(item, "HandWeapon") then return false end
    return item:hasTag(ItemTag.CLEAN_STAINS) or TSPS.Cloths[item:getFullType()] == true
end

function TSPS.findCloth(sources, player)
    return TSPS.findInSources(sources, TSPS.isCloth, player)
end

function TSPS.consumePetrol(item)
    local fc = item and item:getFluidContainer()
    if not fc then return false end
    fc:adjustAmount(fc:getAmount() - TSPS.PETROL_PER_REMOVAL)
    item:syncItemFields()
    if isServer() and sendItemStats then sendItemStats(item) end
    return true
end

local function restorePaint(player, item)
    local paint = item and item:getModData().TS_Paint
    TSPS.log("restorePaint (OnEquip)", "hasPaint", tostring(paint ~= nil))
    TSPS.logItem("restorePaint (OnEquip) item", item)
    if paint then
        TSPS.applyPaint(item, paint.r, paint.g, paint.b, paint.mix, nil, player)
        if isServer() then
            item:syncItemFields()
        end
    end
end

Events.OnEquipPrimary.Add(restorePaint)
Events.OnEquipSecondary.Add(restorePaint)
