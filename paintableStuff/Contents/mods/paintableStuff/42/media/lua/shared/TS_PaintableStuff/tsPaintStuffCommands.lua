-- TeaStain 16/11/2026

require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = TSPS.MODULE

local function findWorldItem(args)
    if not args or args.x == nil or args.y == nil or args.z == nil or args.itemId == nil then
        return nil
    end
    local square = getSquare(args.x, args.y, args.z)
    if not square then return nil end
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local worldItem = objects:get(i)
        local item = worldItem:getItem()
        if item and item:getID() == args.itemId then
            return item
        end
    end
    return nil
end

local function findLocalItem(itemId)
    local player = getPlayer()
    if not player then return nil end
    local item = TSPS.findItem(player, itemId)
    if item then return item end
    for i = 1, 3 do
        local other = getSpecificPlayer(i)
        if other and other:isLocalPlayer() then
            item = TSPS.findItem(other, itemId)
            if item then return item end
        end
    end
    return nil
end

local function findEchoItem(itemId)
    local item = findLocalItem(itemId)
    if item then return item end
    local player = getPlayer()
    if player and TSPS.getSources then
        item = TSPS.findItemInSources(TSPS.getSources(player), itemId)
    end
    return item
end

local function echoPlayerFor(item)
    local player = getPlayer()
    if item then
        if player and TSPS.isInPlayerInventory(player, item) then return player end
        for i = 1, 3 do
            local other = getSpecificPlayer(i)
            if other and other:isLocalPlayer() and TSPS.isInPlayerInventory(other, item) then
                return other
            end
        end
    end
    return player
end

local function applyPaintEcho(player, item, args)
    local mix = TSPS.sanitizeMix(TSPS.mixFromString(args.mix))
    local r, g, b = TSPS.clampRGB(args.r, args.g, args.b)
    TSPS.applyPaint(item, r, g, b, mix, nil, player)
    local paint = item:getModData().TS_Paint
    if paint and args.idx ~= nil then
        paint.idx = args.idx
    end
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE then return end
        TSPS.log("OnServerCommand", command, "args", TSPS.tableToString(args))
        if not args then
            TSPS.log("OnServerCommand no args; ignoring")
            return
        end

        if command == "paintedWorld" or command == "unpaintedWorld" then
            local item = findWorldItem(args)
            if not item then return end
            if command == "paintedWorld" then
                applyPaintEcho(getPlayer(), item, args)
            else
                TSPS.clearPaint(item, getPlayer())
                if args.idx ~= nil then item:setModelIndex(args.idx) end
            end
            return
        end

        if command == "paintedNearby" or command == "unpaintedNearby" then
            local item = findEchoItem(args.itemId)
            if not item then return end
            local player = echoPlayerFor(item)
            if command == "paintedNearby" then
                applyPaintEcho(player, item, args)
            else
                TSPS.clearPaint(item, player)
                if args.idx ~= nil then item:setModelIndex(args.idx) end
            end
            return
        end

        local player = getSpecificPlayer(args.playerNum or 0)
        TSPS.log("OnServerCommand player", tostring(player ~= nil),
            "playerNum", args.playerNum,
            "isLocalPlayer", tostring(player ~= nil and player:isLocalPlayer()))
        if not player then return end

        if command == "failed" then
            TSPS.log("OnServerCommand FAILED handler")
            HaloTextHelper.addBadText(player, getText("UI_TS_PaintableStuff_Paint_Failed"))
        end
    end)
end
