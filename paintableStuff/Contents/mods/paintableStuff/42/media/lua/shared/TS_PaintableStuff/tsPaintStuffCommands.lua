-- TeaStain 16/11/2026

require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = "TS_PaintableStuff"

local function isEquipped(player, item)
    return player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item
end

local function respond(player, command, args)
    sendServerCommand(player, MODULE, command, args)
end

local function onPaintRequest(player, args)
    local inv = player:getInventory()
    local item = TSPS.findItem(player, args.itemId)
    local mix = TSPS.sanitizeMix(TSPS.mixFromString(args.mix))
    if not item or #mix == 0 or not TSPS.canPaint(player, item, mix) then
        return respond(player, "failed", { playerNum = args.playerNum })
    end

    local r, g, b = TSPS.mixColor(mix)
    TSPS.applyPaint(item, r, g, b, mix, nil, player)
    TSPS.consumePaint(inv, mix)
    item:syncItemFields()
    if isEquipped(player, item) then sendEquip(player) end
    respond(player, "painted", { playerNum = args.playerNum, itemId = item:getID(), mix = TSPS.mixToString(mix) })
end

local function onUnpaintRequest(player, args)
    local item = TSPS.findItem(player, args.itemId)
    local solvent = TSPS.findItem(player, args.solventId)
    local cloth = TSPS.findItem(player, args.clothId)
    local valid = item and solvent and cloth and TSPS.isPainted(item)
        and TSPS.isPetrolSource(solvent) and TSPS.isCloth(cloth)
    if not valid or not TSPS.consumePetrol(solvent) then
        return respond(player, "failed", { playerNum = args.playerNum })
    end

    TSPS.clearPaint(item, player)
    item:syncItemFields()
    if isEquipped(player, item) then sendEquip(player) end
    respond(player, "unpainted", { playerNum = args.playerNum, itemId = item:getID() })
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= MODULE then return end
        if command == "paint" then
            onPaintRequest(player, args)
        elseif command == "unpaint" then
            onUnpaintRequest(player, args)
        end
    end)
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE then return end
        local player = getSpecificPlayer(args.playerNum or 0)
        if not player then return end

        if command == "failed" then
            HaloTextHelper.addBadText(player, getText("UI_TS_Paint_Failed"))
            return
        end

        local item = TSPS.findItem(player, args.itemId)
        if not item then return end

        if command == "painted" then
            local mix = TSPS.sanitizeMix(TSPS.mixFromString(args.mix))
            local r, g, b = TSPS.mixColor(mix)
            TSPS.applyPaint(item, r, g, b, mix, nil, player)
        elseif command == "unpainted" then
            TSPS.clearPaint(item, player)
        end
    end)
end
