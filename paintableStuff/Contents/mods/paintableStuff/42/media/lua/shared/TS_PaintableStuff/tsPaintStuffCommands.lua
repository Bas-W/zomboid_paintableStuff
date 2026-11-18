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

        local player = getSpecificPlayer(args.playerNum or 0)
        TSPS.log("OnServerCommand player", tostring(player ~= nil),
            "playerNum", args.playerNum,
            "isLocalPlayer", tostring(player ~= nil and player:isLocalPlayer()))
        if not player then return end

        if command == "failed" then
            TSPS.log("OnServerCommand FAILED handler")
            HaloTextHelper.addBadText(player, getText("UI_TS_Paint_Failed"))
            return
        end

        local item = TSPS.findItem(player, args.itemId)
        if not item and TSPS.getSources then
            item = TSPS.findItemInSources(TSPS.getSources(player), args.itemId)
        end
        TSPS.logItem("OnServerCommand item", item)
        TSPS.log("OnServerCommand findItem", "itemId", args.itemId, "found", tostring(item ~= nil))
        if not item then return end

        if command == "painted" then
            TSPS.log("OnServerCommand applying echo", "rgb", args.r, args.g, args.b)
            applyPaintEcho(player, item, args)
        elseif command == "unpainted" then
            TSPS.log("OnServerCommand clearing echo")
            TSPS.clearPaint(item, player)
            if args.idx ~= nil then item:setModelIndex(args.idx) end
        end
    end)
end
