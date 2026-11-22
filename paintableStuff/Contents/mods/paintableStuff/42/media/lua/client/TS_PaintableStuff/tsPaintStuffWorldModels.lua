-- TeaStain 18/11/2026
--
-- Worldmodel override.
-- Fixes incorrect item appearence when placed or dropped.
-- Unfortunately, this is quite hacky.

require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffWorldModelOverride"
require "TimedActions/ISTransferAction"
require "TimedActions/ISDropWorldItemAction"
require "TimedActions/ISDropVehicleItemAction"

local TSPS = TS_PaintStuff

local SCAN_RADIUS = 8
local MOVE_SCAN_S = 1
local IDLE_SCAN_S = 5

local lastMoveScan = 0
local lastIdleScan = 0
local lastX, lastY = -1, -1

local function wantsUpdate(item)
    if not item then return false end
    local md = item:getModData()
    return md.TS_Paint ~= nil or md.TS_WorldModel ~= nil
end

local function updateObject(obj)
    if not instanceof(obj, "IsoWorldInventoryObject") then return end
    local item = obj:getItem()
    if wantsUpdate(item) then
        TSPS.updateWorldModel(item)
    end
end

function TSPS.scanWorldItemsAround(player)
    player = player or (getPlayer and getPlayer())
    if not player then return end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())

    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local square = getSquare(px + dx, py + dy, pz)
            if square then
                local objects = square:getWorldObjects()
                for i = 0, objects:size() - 1 do
                    local item = objects:get(i):getItem()
                    if wantsUpdate(item) then
                        TSPS.updateWorldModel(item)
                    end
                end
            end
        end
    end
end

local function onObjectAdded(obj)
    updateObject(obj)
end

local function refreshItem(item)
    if item and (isClient() or not isServer()) and wantsUpdate(item) then
        TSPS.updateWorldModel(item)
    end
end

-- Update worldmodel when dropping item
local transferItem = ISTransferAction.transferItem
function ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)
    local result = transferItem(self, character, item, srcContainer, destContainer, dropSquare)
    local moved = result or item
    local touchesFloor = (destContainer ~= nil and destContainer:getType() == "floor")
        or (srcContainer ~= nil and srcContainer:getType() == "floor")
    if touchesFloor then
        refreshItem(moved)
    end
    return result
end

-- Update worldmodel when placing item
local function wrapPlacement(action)
    if not action or not action.perform then return end
    local perform = action.perform
    function action:perform()
        perform(self)
        refreshItem(self.item)
    end
end

wrapPlacement(ISDropWorldItemAction)
wrapPlacement(ISDropVehicleItemAction)

-- Periodic local worldmodel update
local function onPlayerMove(player)
    if not player or not player:isLocalPlayer() then return end
    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    if x == lastX and y == lastY then return end
    lastX, lastY = x, y

    local now = getTimestamp and getTimestamp() or 0
    if now - lastMoveScan > MOVE_SCAN_S then
        lastMoveScan = now
        TSPS.scanWorldItemsAround(player)
    end
end

local function onTick()
    if not TSPS.settings.worldModelSwap then return end
    local now = getTimestamp and getTimestamp() or 0
    if now - lastIdleScan > IDLE_SCAN_S then
        lastIdleScan = now
        TSPS.scanWorldItemsAround(getPlayer and getPlayer())
    end
end

Events.OnObjectAdded.Add(onObjectAdded)
Events.OnPlayerMove.Add(onPlayerMove)
Events.OnTick.Add(onTick)
