-- TeaStain 16/11/2026

require "BuildingObjects/ISPaintMenu"

-- Paintable items can be registered as follows:
--[[
    require "TS_PaintableStuff/tsPaintStuffApi"

    TS_PaintStuff.registerPaintable("MyMod.Item", { index = 0 })
    Where the index is the texture index corresponding to the texture to which the tint should be applied.
    For items with only one possible texture this should always be 0.
    A tint mask should be added, the name should be "[ItemTextureName]TINT.png".
]]

TS_PaintStuff = TS_PaintStuff or {}
local TSPS = TS_PaintStuff

TSPS.API_VERSION = 1
TSPS.Paintables = TSPS.Paintables or {}
TSPS.MAX_MIX_PARTS = 10
TSPS.PETROL_PER_REMOVAL = 0.5

function TSPS.registerPaintable(fullType, opts)
    TSPS.Paintables[fullType] = { index = math.max(0, math.floor(tonumber(opts and opts.index) or 0)) }
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

-- One use per participating paint, regardless of parts
function TSPS.consumePaint(inv, mix)
    for _, part in ipairs(mix) do
        if part.parts > 0 then
            local tin = TSPS.findUsableTin(inv, part.paint)
            if not tin then return false end
            tin:UseAndSync()
        end
    end
    return true
end

function TSPS.mixColor(mix)
    local r, g, b, total = 0, 0, 0, 0
    local pal = TSPS.getPalette()
    for _, part in ipairs(mix) do
        local entry = pal[part.paint]
        if entry and part.parts > 0 then
            r = r + entry.color[1] * part.parts
            g = g + entry.color[2] * part.parts
            b = b + entry.color[3] * part.parts
            total = total + part.parts
        end
    end
    if total == 0 then return 1, 1, 1 end
    return r / total, g / total, b / total
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
    if player and player:isLocalPlayer() and player:isEquipped(item) then
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
    index = safeIndex(item, index or (registration and registration.index) or 0)
    if item:getModelIndex() ~= index then item:setModelIndex(index) end

    item:setColor(Color.new(r, g, b, 1))
    item:setColorRed(r)
    item:setColorGreen(g)
    item:setColorBlue(b)
    item:setCustomColor(true)
    item:getModData().TS_Paint = { r = r, g = g, b = b, mix = mix, v = 1 }
    refreshItem(item, player)
end

function TSPS.clearPaint(item, player)
    item:setColor(Color.new(1, 1, 1, 1))
    item:setColorRed(1)
    item:setColorGreen(1)
    item:setColorBlue(1)
    item:setCustomColor(false)
    item:getModData().TS_Paint = nil
    refreshItem(item, player)
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
    if paint then
        TSPS.applyPaint(item, paint.r, paint.g, paint.b, paint.mix, nil, player)
    end
end

Events.OnEquipPrimary.Add(restorePaint)
Events.OnEquipSecondary.Add(restorePaint)
