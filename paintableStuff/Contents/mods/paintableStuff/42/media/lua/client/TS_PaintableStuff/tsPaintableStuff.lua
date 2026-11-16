-- TeaStain 15/11/2026

require "ISUI/ISContextMenu"

TS_PaintStuff = TS_PaintStuff or {}
TS_PaintStuff.PaintMenu = TS_PaintStuff.PaintMenu or {}

local PaintMenu = TS_PaintStuff.PaintMenu

function PaintMenu.setColor(item, r, g, b)
    if not item then
        return
    end

    local modData = item:getModData()

    modData.TS_Paint = {
        r = r,
        g = g,
        b = b
    }

    item:setColorRed(r)
    item:setColorGreen(g)
    item:setColorBlue(b)

    if item:getVisual() then
        item:getVisual():setTint(
            ImmutableColor.new(r, g, b, 1)
        )
    end

    item:setCustomColor(true)

    local player = getPlayer()

    if player and player:isEquipped(item) then
        player:resetModelNextFrame()
    end

    if item:getContainer() then
        item:getContainer():setDrawDirty(true)
    end
end

local function onPaintItem(item, color)
    if color == "red" then
        PaintMenu.setColor(item, 1, 0, 0)

    elseif color == "green" then
        PaintMenu.setColor(item, 0, 1, 0)

    elseif color == "blue" then
        PaintMenu.setColor(item, 0, 0, 1)
    end
end

local function createPaintMenu(player, context, items)

    for _, entry in ipairs(items) do
        local item = entry

        if type(entry) == "table" and entry.items then
            item = entry.items[1]
        end

        if item and item:getFullType() == "Base.Crowbar" then

            local option = context:addOption(
                "Paint item",
                nil,
                nil
            )

            local subMenu = ISContextMenu:getNew(context)
            context:addSubMenu(option, subMenu)

            subMenu:addOption("Red", item, onPaintItem, "red")
            subMenu:addOption("Green", item, onPaintItem, "green")
            subMenu:addOption("Blue", item, onPaintItem, "blue")

            break
        end
    end
end

Events.OnPreFillInventoryObjectContextMenu.Add(createPaintMenu)
