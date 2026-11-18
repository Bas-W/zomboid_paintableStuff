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

TSPS.settings = TSPS.settings or {}
if TSPS.settings.worldModelSwap == nil then
    TSPS.settings.worldModelSwap = true
end

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
    rClmp = math.max(0, math.min(1, tonumber(r) or 0.99))
    gClmp = math.max(0, math.min(1, tonumber(g) or 0.99))
    bClmp = math.max(0, math.min(1, tonumber(b) or 0.99))
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

function TSPS.resolveItem(player, item)
    if item and TSPS.isInPlayerInventory(player, item) then return item end
    return item and TSPS.findItem(player, item:getID())
end

function TSPS.hasBrush(inv)
    return inv:getFirstTagRecurse(ItemTag.PAINTBRUSH) ~= nil
end

function TSPS.findUsableTin(inv, paintType)
    local tins = inv:getAllTypeRecurse(paintType)
    for i = 0, tins:size() - 1 do
        local tin = tins:get(i)
        if tin:getCurrentUses() > 0 then return tin end
    end
end

function TSPS.getAvailablePaints(inv)
    local result = {}
    for _, entry in ipairs(ISPaintMenu.PaintMenuItems) do
        local tins = inv:getAllTypeRecurse(entry.paint)
        local uses = 0
        for i = 0, tins:size() - 1 do
            uses = uses + tins:get(i):getCurrentUses()
        end
        if uses > 0 then
            result[#result + 1] = { entry = entry, uses = uses }
        end
    end
    return result
end

function TSPS.hasPaints(inv, mix)
    for _, part in ipairs(mix) do
        if part.parts > 0 and not TSPS.findUsableTin(inv, part.paint) then return false end
    end
    return true
end

function TSPS.canPaint(player, item, mix)
    local inv = player:getInventory()
    return TSPS.isPaintable(item) and TSPS.hasBrush(inv) and TSPS.hasPaints(inv, mix)
end

-- One use per included paint, regardless of parts used
function TSPS.consumePaint(inv, mix)
    for _, part in ipairs(mix) do
        if part.parts > 0 then
            local tin = TSPS.findUsableTin(inv, part.paint)
            if not tin then return false end
            TSPS.log("consumePaint", part.paint, "tinId", tin:getID(), "usesBefore", tin:getCurrentUses())
            tin:UseAndSync()
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
    if isClient() or not isServer() then
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
    if isClient() or not isServer() then
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

local function isLocalRenderSide()
    return isClient() or not isServer()
end

local function resolveWorldPainted(registration, item)
    local value = registration and registration.worldPainted
    if type(value) == "table" then
        return value[item:getModelIndex()] or value.default
    end
    return value
end

local function worldModelExists(name)
    local manager = getScriptManager and getScriptManager()
    return manager ~= nil and manager:getModelScript(name) ~= nil
end

function TSPS.getWorldPaintedModel(item)
    local registration = TSPS.Paintables[item:getFullType()]
    if not registration then return nil end
    return resolveWorldPainted(registration, item)
end

-- Force WorldItemAtlas refresh.
function TSPS.invalidateWorldAtlas(item)
    if not item or not item:getWorldItem() then return end
    item:setWorldZRotation(item:getWorldZRotation() + 0.001)
end

function TSPS.updateWorldModel(item)
    if not item then return end

    local md = item:getModData()
    local state = md.TS_WorldModel
    local applied = type(state) == "table" and state.applied or nil
    local current = md.worldStaticModel

    -- Avoid overriding other mod
    if current ~= nil and current ~= applied then
        return
    end

    local desired
    if TSPS.settings.worldModelSwap and TSPS.isPainted(item) then
        local candidate = TSPS.getWorldPaintedModel(item)
        if candidate and worldModelExists(candidate) then
            desired = candidate
        end
    end

    if desired == current then return end

    if desired then
        if not state then
            state = {
                had = false,
                prev = nil,
            }
            md.TS_WorldModel = state
        end
        state.applied = desired
        md.worldStaticModel = desired
        TSPS.invalidateWorldAtlas(item)
        TSPS.log("worldModel", "id", item:getID(), "model", desired)
    elseif state then
        if state.had then
            md.worldStaticModel = state.prev
        else
            md.worldStaticModel = nil
        end
        md.TS_WorldModel = nil
        TSPS.invalidateWorldAtlas(item)
        TSPS.log("worldModel", "id", item:getID(), "restored")
    end
end

function TSPS.refreshLocalWorldModels(player)
    player = player or (getPlayer and getPlayer())
    if not player then return end

    local inventory = player:getInventory()
    if inventory then
        inventory:getAllEvalRecurse(function(item)
            local md = item and item:getModData()
            if md and (md.TS_Paint or md.TS_WorldModel) then
                TSPS.updateWorldModel(item)
            end
            return false
        end)
    end

    TSPS.updateWorldModel(player:getPrimaryHandItem())
    TSPS.updateWorldModel(player:getSecondaryHandItem())
end

function TSPS.setWorldModelSwap(enabled)
    TSPS.settings.worldModelSwap = enabled == true
    if isLocalRenderSide() then
        TSPS.refreshLocalWorldModels()
    end
end

-- Paint removal

function TSPS.isPetrolSource(item)
    local fc = item:getFluidContainer()
    return fc ~= nil and fc:contains(Fluid.Petrol) and fc:getAmount() >= TSPS.PETROL_PER_REMOVAL
end

function TSPS.findSolvent(inv)
    return inv:getFirstEvalRecurse(TSPS.isPetrolSource)
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

function TSPS.findCloth(inv)
    return inv:getFirstEvalRecurse(TSPS.isCloth)
end

function TSPS.consumePetrol(item)
    local fc = item and item:getFluidContainer()
    if not fc then return false end
    fc:adjustAmount(fc:getAmount() - TSPS.PETROL_PER_REMOVAL)
    item:syncItemFields()
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
