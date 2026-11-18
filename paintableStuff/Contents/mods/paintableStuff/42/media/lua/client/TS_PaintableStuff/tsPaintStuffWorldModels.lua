-- TeaStain 18/11/2026
--
-- Worldmodel override.
-- Fixes incorrect item appearence when placed or dropped.
-- Unfortunately, this is quite hacky.

require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffWorldModelOverride"

local TSPS = TS_PaintStuff

local SCAN_RADIUS = 8
local MOVE_SCAN_MS = 750
local IDLE_SCAN_MS = 5000

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

function TSPS.scanWorldItemsAround(player, force)
    player = player or (getPlayer and getPlayer())
    if not player then return end

    local now = getTimestamp and getTimestamp() or 0
    if not force then
        if now - lastMoveScan < MOVE_SCAN_MS then return end
    end
    lastMoveScan = now

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

local function onPlayerMove(player)
    if not player or not player:isLocalPlayer() then return end
    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    if x == lastX and y == lastY then return end
    lastX, lastY = x, y
    TSPS.scanWorldItemsAround(player)
end

local function onTick()
    if not TSPS.settings.worldModelSwap then return end
    local now = getTimestamp and getTimestamp() or 0
    if now - lastIdleScan < IDLE_SCAN_MS then return end
    lastIdleScan = now
    TSPS.scanWorldItemsAround(getPlayer and getPlayer(), true)
end

Events.OnObjectAdded.Add(onObjectAdded)
Events.OnPlayerMove.Add(onPlayerMove)
Events.OnTick.Add(onTick)
