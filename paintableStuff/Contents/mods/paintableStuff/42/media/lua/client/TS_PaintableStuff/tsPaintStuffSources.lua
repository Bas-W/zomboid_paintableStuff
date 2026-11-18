-- TeaStain 18/11/2026

require "ISUI/ISInventoryPaneContextMenu"
require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff

function TSPS.getSources(player)
    local containers = {}
    local seen = {}

    local function add(container)
        if not container or seen[container] then return end
        seen[container] = true
        containers[#containers + 1] = container
    end

    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.getContainers then
        local ok, loot = pcall(ISInventoryPaneContextMenu.getContainers, player)
        if ok and loot then
            for i = 0, loot:size() - 1 do
                add(loot:get(i))
            end
        end
    end

    add(player:getInventory())

    return { containers = containers }
end
