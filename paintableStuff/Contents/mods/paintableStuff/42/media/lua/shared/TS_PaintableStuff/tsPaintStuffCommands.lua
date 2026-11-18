-- TeaStain 16/11/2026

require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = TSPS.MODULE

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE then return end
        TSPS.log("OnServerCommand", command, "args", TSPS.tableToString(args))
        if not args then
            TSPS.log("OnServerCommand no args; ignoring")
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
        TSPS.logItem("OnServerCommand item", item)
        TSPS.log("OnServerCommand findItem", "itemId", args.itemId, "found", tostring(item ~= nil))
        if not item then return end

        if command == "painted" then
            local mix = TSPS.sanitizeMix(TSPS.mixFromString(args.mix))
            local r, g, b = TSPS.clampRGB(args.r, args.g, args.b)
            TSPS.log("OnServerCommand applying echo", "rgb", r, g, b, "mix", TSPS.tableToString(mix))
            TSPS.applyPaint(item, r, g, b, mix, nil, player)
        elseif command == "unpainted" then
            TSPS.log("OnServerCommand clearing echo")
            TSPS.clearPaint(item, player)
        end
    end)
end
