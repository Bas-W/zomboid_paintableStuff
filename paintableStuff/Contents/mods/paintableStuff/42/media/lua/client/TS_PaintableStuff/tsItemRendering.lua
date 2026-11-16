-- TeaStain 15/11/2026

TS_PaintStuff = TS_PaintStuff or {}
TS_PaintStuff.PaintMenu = TS_PaintStuff.PaintMenu or {}

local PaintMenu = TS_PaintStuff.PaintMenu

function PaintMenu.restoreColor(item)
    if not item then
        return
    end

    local paint = item:getModData().TS_Paint

    if not paint then
        return
    end

    item:setColorRed(paint.r)
    item:setColorGreen(paint.g)
    item:setColorBlue(paint.b)

    if item:getVisual() then
        item:getVisual():setTint(
            ImmutableColor.new(paint.r, paint.g, paint.b, 1)
        )
    end

    item:setCustomColor(true)
end

Events.OnEquipPrimary.Add(function(player, item)
    PaintMenu.restoreColor(item)
end)

Events.OnEquipSecondary.Add(function(player, item)
    PaintMenu.restoreColor(item)
end)
