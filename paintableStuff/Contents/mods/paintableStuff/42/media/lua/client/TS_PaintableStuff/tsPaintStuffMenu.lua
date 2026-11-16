-- TeaStain 16/11/2026

require "ISUI/ISContextMenu"
require "TimedActions/ISTimedActionQueue"
require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffActions"
require "TS_PaintableStuff/tsPaintStuffMix"

local TSPS = TS_PaintStuff

local function findPaintable(player, items)
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" and entry.items then item = entry.items[1] end
        if item and TSPS.isPaintable(item) and TSPS.isInPlayerInventory(player, item) then
            return item
        end
    end
end

local function paintSingle(player, item, entry)
    ISTimedActionQueue.add(TSPaintItemAction:new(player, item, { { paint = entry.paint, parts = 1 } }))
end

local function openMixer(player, item)
    if #TSPS.getAvailablePaints(player:getInventory()) < 2 then return end
    local panel = TSPaintMixPanel:new(player, item)
    panel:initialise()
    panel:addToUIManager()
end

local function removePaint(player, item)
    local inv = player:getInventory()
    ISTimedActionQueue.add(TSPaintRemoveAction:new(player, item, TSPS.findSolvent(inv), TSPS.findCloth(inv)))
end

local function addApplyOption(player, paintMenu, item, paints, hasBrush)
    local label = getText("ContextMenu_TS_Apply")
    if not hasBrush then
        label = getText("ContextMenu_TS_Apply_NeedsBrush")
    elseif #paints == 0 then
        label = getText("ContextMenu_TS_Apply_NoPaint")
    end

    local option = paintMenu:addOption(label, nil, nil)
    if not hasBrush or #paints == 0 then
        option.notAvailable = true
        return
    end

    local applyMenu = ISContextMenu:getNew(paintMenu)
    paintMenu:addSubMenu(option, applyMenu)

    for _, paint in ipairs(paints) do
        local row = applyMenu:addColorBoxOption(getText(paint.entry.text) .. " (" .. paint.uses .. ")", player, paintSingle, item, paint.entry)
        row.color.r = paint.entry.color[1]
        row.color.g = paint.entry.color[2]
        row.color.b = paint.entry.color[3]
    end

    local mixOption = applyMenu:addOption(getText("ContextMenu_TS_CustomMix"), player, openMixer, item)
    if #paints < 2 then mixOption.notAvailable = true end
end

local function addRemoveOption(player, paintMenu, item)
    if not TSPS.isPainted(item) then return end

    local inv = player:getInventory()
    local solvent = TSPS.findSolvent(inv)
    local cloth = TSPS.findCloth(inv)
    local label = getText("ContextMenu_TS_RemovePaint")
    if not solvent and not cloth then
        label = getText("ContextMenu_TS_RemovePaint_NeedsBoth")
    elseif not solvent then
        label = getText("ContextMenu_TS_RemovePaint_NeedsPetrol")
    elseif not cloth then
        label = getText("ContextMenu_TS_RemovePaint_NeedsCloth")
    end

    local option = paintMenu:addOption(label, player, removePaint, item)
    option.notAvailable = not (solvent and cloth)
end

local function onFillInventoryContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local item = findPaintable(player, items)
    if not item then return end

    local inv = player:getInventory()
    local paintOption = context:addOption(getText("ContextMenu_TS_PaintMenu"), nil, nil)
    local paintMenu = ISContextMenu:getNew(context)
    context:addSubMenu(paintOption, paintMenu)

    addApplyOption(player, paintMenu, item, TSPS.getAvailablePaints(inv), TSPS.hasBrush(inv))
    addRemoveOption(player, paintMenu, item)
end

Events.OnPreFillInventoryObjectContextMenu.Add(onFillInventoryContextMenu)
