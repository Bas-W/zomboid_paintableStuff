-- TeaStain 16/11/2026

require "ISUI/ISContextMenu"
require "TimedActions/ISTimedActionQueue"
require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffActions"
require "TS_PaintableStuff/tsPaintStuffMix"
require "TS_PaintableStuff/tsPaintStuffSources"

local TSPS = TS_PaintStuff

local function findPaintable(items)
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" and entry.items then item = entry.items[1] end
        if item and TSPS.isPaintable(item) then
            return item
        end
    end
end

local function paintSingle(player, item, entry, sources, worldItem)
    local mix = { { paint = entry.paint, parts = 1 } }
    local r, g, b = TSPS.mixColor(mix)
    local containers = TSPS.toActionList(sources)
    ISTimedActionQueue.add(TSPaintItemAction:new(player, item, mix, r, g, b, containers, worldItem))
end

local function openMixer(player, item, sources, worldItem)
    if #TSPS.getAvailablePaints(sources, player) < 2 then return end
    local panel = TSPaintMixPanel:new(player, item, sources, worldItem)
    panel:initialise()
    panel:addToUIManager()
end

local function removePaint(player, item, sources, worldItem)
    local containers = TSPS.toActionList(sources)
    ISTimedActionQueue.add(TSPaintRemoveAction:new(player, item, containers, worldItem))
end

local function addApplyOption(player, paintMenu, item, paints, hasBrush, sources, worldItem)
    local label = getText("ContextMenu_TS_PaintableStuff_Apply")
    if not hasBrush then
        label = getText("ContextMenu_TS_PaintableStuff_Apply_NeedsBrush")
    elseif #paints == 0 then
        label = getText("ContextMenu_TS_PaintableStuff_Apply_NoPaint")
    end

    local option = paintMenu:addOption(label, nil, nil)
    if not hasBrush or #paints == 0 then
        option.notAvailable = true
        return
    end

    local applyMenu = ISContextMenu:getNew(paintMenu)
    paintMenu:addSubMenu(option, applyMenu)

    for _, paint in ipairs(paints) do
        local row = applyMenu:addColorBoxOption(
            getText(paint.entry.text) .. " (" .. paint.uses .. ")",
            player,
            paintSingle,
            item,
            paint.entry,
            sources,
            worldItem)
        row.color.r = paint.entry.color[1]
        row.color.g = paint.entry.color[2]
        row.color.b = paint.entry.color[3]
    end

    local mixOption = applyMenu:addOption(getText("ContextMenu_TS_PaintableStuff_CustomMix"), player, openMixer, item, sources, worldItem)
    if #paints < 2 then mixOption.notAvailable = true end
end

local function addRemoveOption(player, paintMenu, item, sources, worldItem)
    if not TSPS.isPainted(item) then return end

    local solvent = TSPS.findSolvent(sources, player)
    local cloth = TSPS.findCloth(sources, player)
    local label = getText("ContextMenu_TS_PaintableStuff_RemovePaint")
    if not solvent and not cloth then
        label = getText("ContextMenu_TS_PaintableStuff_RemovePaint_NeedsBoth")
    elseif not solvent then
        label = getText("ContextMenu_TS_PaintableStuff_RemovePaint_NeedsPetrol")
    elseif not cloth then
        label = getText("ContextMenu_TS_PaintableStuff_RemovePaint_NeedsCloth")
    end

    local option = paintMenu:addOption(label, player, removePaint, item, sources, worldItem)
    option.notAvailable = not (solvent and cloth)
end

local function onFillInventoryContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local item = findPaintable(items)
    if not item then return end

    local sources = TSPS.getSources(player)

    local paintOption = context:addOption(getText("ContextMenu_TS_PaintableStuff_PaintMenu"), nil, nil)
    local paintMenu = ISContextMenu:getNew(context)
    context:addSubMenu(paintOption, paintMenu)

    addApplyOption(
        player,
        paintMenu,
        item,
        TSPS.getAvailablePaints(sources, player),
        TSPS.hasBrush(sources, player),
        sources,
        nil)
    addRemoveOption(player, paintMenu, item, sources, nil)
end

local function onFillWorldContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local sources
    local seen = {}
    for _, object in ipairs(worldObjects) do
        if instanceof(object, "IsoWorldInventoryObject") then
            local item = object:getItem()
            if item and TSPS.isPaintable(item) and not seen[item:getID()] then
                seen[item:getID()] = true
                sources = sources or TSPS.getSources(player)

                local paintOption = context:addOption(
                    getText("ContextMenu_TS_PaintableStuff_PaintMenu") .. " " .. item:getName(),
                    nil,
                    nil)
                local paintMenu = ISContextMenu:getNew(context)
                context:addSubMenu(paintOption, paintMenu)

                addApplyOption(
                    player,
                    paintMenu,
                    item,
                    TSPS.getAvailablePaints(sources, player),
                    TSPS.hasBrush(sources, player),
                    sources,
                    object)
                addRemoveOption(player, paintMenu, item, sources, object)
            end
        end
    end
end

Events.OnPreFillInventoryObjectContextMenu.Add(onFillInventoryContextMenu)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldContextMenu)
