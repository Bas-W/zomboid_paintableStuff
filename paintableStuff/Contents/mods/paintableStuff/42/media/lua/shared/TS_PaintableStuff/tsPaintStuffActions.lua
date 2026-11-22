-- TeaStain 16/11/2026

require "TimedActions/ISBaseTimedAction"
require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = TSPS.MODULE
local ACTION_DUR = 50

local function notifyItemClients(player, item)
    if not isServer() then return end
    if item == player:getPrimaryHandItem() or item == player:getSecondaryHandItem() then
        sendEquip(player)
    end
    if player:isAttachedItem(item) then
        local attached = player:getAttachedItems()
        local location = attached and attached:getLocation(item)
        if location then sendAttachedItem(player, location, item) end
    end
end

local function actionSources(action)
    if not action.containers then return nil end
    return { containers = action.containers }
end

local function syncItem(item)
    if not isServer() then return end
    item:syncItemFields()
    if sendItemStats then sendItemStats(item) end
end

local ECHO_RADIUS = 10

local function sendContainerEcho(player, square, command, args)
    if not isServer() then return end
    local players = getOnlinePlayers and getOnlinePlayers()
    if not players then
        sendServerCommand(MODULE, command, args)
        return
    end
    for i = 0, players:size() - 1 do
        local target = players:get(i)
        if target then
            local inRange = target == player
            if not inRange and square and target:getCurrentSquare() then
                inRange = square:DistToProper(target:getCurrentSquare()) <= ECHO_RADIUS
            end
            if inRange then
                sendServerCommand(target, MODULE, command, args)
            end
        end
    end
end

local function sendPaintEcho(player, playerNum, item, worldItem, r, g, b, mix)
    if not isServer() then return end
    local paint = item:getModData().TS_Paint
    local idx = paint and paint.idx or nil

    if worldItem then
        local square = worldItem:getSquare()
        if not square then return end
        sendServerCommand(MODULE, "paintedWorld", {
            playerNum = playerNum,
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            itemId = item:getID(),
            r = r,
            g = g,
            b = b,
            mix = TSPS.mixToString(mix),
            idx = idx,
        })
    else
        local container = item:getContainer()
        sendContainerEcho(player, container and container:getSquare() or nil, "paintedNearby", {
            itemId = item:getID(),
            r = r,
            g = g,
            b = b,
            mix = TSPS.mixToString(mix),
            idx = idx,
        })
    end
end

local function sendClearEcho(player, playerNum, item, worldItem)
    if not isServer() then return end
    local idx = item:getModelIndex()
    if worldItem then
        local square = worldItem:getSquare()
        if not square then return end
        sendServerCommand(MODULE, "unpaintedWorld", {
            playerNum = playerNum,
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
            itemId = item:getID(),
            idx = idx,
        })
    else
        local container = item:getContainer()
        sendContainerEcho(player, container and container:getSquare() or nil, "unpaintedNearby", {
            itemId = item:getID(),
            idx = idx,
        })
    end
end

-- Paint application

TSPaintItemAction = ISBaseTimedAction:derive("TSPaintItemAction")

function TSPaintItemAction:new(character, item, mix, r, g, b, containers, worldItem)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.mix = mix
    o.r = r
    o.g = g
    o.b = b
    o.containers = containers
    o.worldItem = worldItem
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.caloriesModifier = 4
    return o
end

function TSPaintItemAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return ACTION_DUR
end

function TSPaintItemAction:isValid()
    local item = TSPS.resolveTarget(self.character, self.item, self.worldItem)
    if not item then return false end
    self.item = item
    return true
end

function TSPaintItemAction:update()
    if self.item then self.item:setJobDelta(self:getJobDelta()) end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function TSPaintItemAction:start()
    TSPS.log("TSPaintItemAction:start",
        "playerNum", self.character:getPlayerNum(),
        "itemId", self.item and self.item:getID(),
        "rgb", self.r, self.g, self.b,
        "mix", TSPS.mixToString(self.mix))
    self:setActionAnim(CharacterActionAnims.Paint)
    self:setOverrideHandModels("PaintBrush", nil)
    self.sound = self.character:playSound("Painting")
    if self.item then
        self.item:setJobType(getText("ContextMenu_TS_PaintableStuff_Painting"))
        self.item:setJobDelta(0)
    end
end

function TSPaintItemAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0) end
    ISBaseTimedAction.stop(self)
end

function TSPaintItemAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0) end
    ISBaseTimedAction.perform(self)
end

function TSPaintItemAction:complete()
    local player = self.character
    local playerNum = player:getPlayerNum()
    local item = TSPS.resolveTarget(player, self.item, self.worldItem)
    local mix = self.mix or {}
    local r, g, b = TSPS.clampRGB(self.r, self.g, self.b)
    TSPS.log("TSPaintItemAction:complete",
        "isServer", tostring(isServer()),
        "isClient", tostring(isClient()),
        "playerNum", playerNum,
        "itemId", item and item:getID(),
        "rgb", r, g, b,
        "mix", TSPS.mixToString(mix))
    if not item or #mix == 0 or not TSPS.canPaint(player, item, mix, actionSources(self)) then
        TSPS.log("TSPaintItemAction:complete REJECTED")
        if isServer() then
            sendServerCommand(player, MODULE, "failed", { playerNum = playerNum })
        end
        return true
    end

    if not TSPS.consumePaint(actionSources(self), mix, player) then
        TSPS.log("TSPaintItemAction:complete REJECTED (consume failed)")
        if isServer() then
            sendServerCommand(player, MODULE, "failed", { playerNum = playerNum })
        end
        return true
    end
    TSPS.applyPaint(item, r, g, b, mix, nil, player)

    if isServer() then
        syncItem(item)
        notifyItemClients(player, item)
        sendPaintEcho(player, playerNum, item, self.worldItem, r, g, b, mix)
        TSPS.log("TSPaintItemAction:complete sent paint echo")
    end
    return true
end

-- Paint removal

TSPaintRemoveAction = ISBaseTimedAction:derive("TSPaintRemoveAction")

function TSPaintRemoveAction:new(character, item, containers, worldItem)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.containers = containers
    o.worldItem = worldItem
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.caloriesModifier = 2
    return o
end

function TSPaintRemoveAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return ACTION_DUR
end

function TSPaintRemoveAction:isValid()
    local item = TSPS.resolveTarget(self.character, self.item, self.worldItem)
    if not item or not TSPS.isPainted(item) then return false end
    self.item = item
    return true
end

function TSPaintRemoveAction:update()
    if self.item then self.item:setJobDelta(self:getJobDelta()) end
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function TSPaintRemoveAction:start()
    self.solvent = self.solvent or TSPS.findSolvent(actionSources(self), self.character)
    self.cloth = self.cloth or TSPS.findCloth(actionSources(self), self.character)
    TSPS.log("TSPaintRemoveAction:start",
        "playerNum", self.character:getPlayerNum(),
        "itemId", self.item and self.item:getID(),
        "solventId", self.solvent and self.solvent:getID(),
        "clothId", self.cloth and self.cloth:getID())
    self:setActionAnim(CharacterActionAnims.Paint)
    self:setOverrideHandModels(self.cloth, self.solvent)
    self.sound = self.character:playSound("CleanBloodScrub")
    if self.item then
        self.item:setJobType(getText("ContextMenu_TS_PaintableStuff_RemovingPaint"))
        self.item:setJobDelta(0)
    end
end

function TSPaintRemoveAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0) end
    ISBaseTimedAction.stop(self)
end

function TSPaintRemoveAction:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    if self.item then self.item:setJobDelta(0) end
    ISBaseTimedAction.perform(self)
end

function TSPaintRemoveAction:complete()
    local player = self.character
    local playerNum = player:getPlayerNum()
    local item = TSPS.resolveTarget(player, self.item, self.worldItem)
    local solvent = TSPS.findSolvent(actionSources(self), player)
    local cloth = TSPS.findCloth(actionSources(self), player)
    TSPS.log("TSPaintRemoveAction:complete",
        "isServer", tostring(isServer()),
        "isClient", tostring(isClient()),
        "playerNum", playerNum,
        "itemId", item and item:getID(),
        "solventId", solvent and solvent:getID(),
        "clothId", cloth and cloth:getID())

    local valid = item and solvent and cloth and TSPS.isPainted(item)
        and TSPS.isPetrolSource(solvent) and TSPS.isCloth(cloth)
    if not valid or not TSPS.consumePetrol(solvent) then
        TSPS.log("TSPaintRemoveAction:complete REJECTED")
        if isServer() then
            sendServerCommand(player, MODULE, "failed", { playerNum = playerNum })
        end
        return true
    end

    TSPS.clearPaint(item, player)

    if isServer() then
        syncItem(item)
        notifyItemClients(player, item)
        sendClearEcho(player, playerNum, item, self.worldItem)
        TSPS.log("TSPaintRemoveAction:complete sent clear echo")
    end
    return true
end
