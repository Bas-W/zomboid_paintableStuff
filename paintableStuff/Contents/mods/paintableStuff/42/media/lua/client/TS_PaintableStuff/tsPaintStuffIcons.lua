-- TeaStain 16/11/2026
--
-- Prevent item icons from being tinted on reload.

require "ISUI/ISInventoryItem"
require "TS_PaintableStuff/tsPaintStuffApi"

local renderItemIcon = ISInventoryItem.renderItemIcon

function ISInventoryItem.renderItemIcon(self, item, x, y, alpha, w, h)
    TS_PaintStuff.ensureIconUntinted(item)
    return renderItemIcon(self, item, x, y, alpha, w, h)
end

local function resetIcons(player)
    if not player then return end
    local items = player:getInventory():getAllEvalRecurse(function() return true end)
    for i = 0, items:size() - 1 do
        TS_PaintStuff.ensureIconUntinted(items:get(i))
    end
end

local function onGameStart()
    for i = 0, 3 do
        resetIcons(getSpecificPlayer(i))
    end
end

local function onCreatePlayer(_, player)
    resetIcons(player)
end

Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(onCreatePlayer)
