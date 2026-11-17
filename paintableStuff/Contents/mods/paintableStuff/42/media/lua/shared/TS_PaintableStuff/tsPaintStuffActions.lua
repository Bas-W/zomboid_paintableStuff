-- TeaStain 16/11/2026

require "TimedActions/ISBaseTimedAction"
require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = TSPS.MODULE

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 1))
end

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

TSPaintItemAction = ISBaseTimedAction:derive("TSPaintItemAction")

function TSPaintItemAction:isValid()
    local item = TSPS.resolveItem(self.character, self.item)
    if not item then return false end
    self.item = item
    return TSPS.canPaint(self.character, item, self.mix)
end

function TSPaintItemAction:start()
    TSPS.log("TSPaintItemAction:start",
        "playerNum", self.character:getPlayerNum(),
        "itemId", self.item:getID(),
        "rgb", self.r, self.g, self.b,
        "mix", TSPS.mixToString(self.mix))
    self:setActionAnim(CharacterActionAnims.Paint)
    self:setOverrideHandModels("PaintBrush", nil)
    self.sound = self.character:playSound("Painting")
    self.item:setJobType(getText("ContextMenu_TS_Painting"))
    self.item:setJobDelta(0)
end

function TSPaintItemAction:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function TSPaintItemAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    self.item:setJobDelta(0)
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
    local item = TSPS.resolveItem(player, self.item)
    local mix = self.mix or {}
    local r, g, b = clamp01(self.r), clamp01(self.g), clamp01(self.b)
    TSPS.log("TSPaintItemAction:complete",
        "isServer", tostring(isServer()),
        "isClient", tostring(isClient()),
        "playerNum", playerNum,
        "itemId", item and item:getID(),
        "rgb", r, g, b,
        "mix", TSPS.mixToString(mix))
    if not item or #mix == 0 or not TSPS.canPaint(player, item, mix) then
        TSPS.log("TSPaintItemAction:complete REJECTED")
        if isServer() then
            sendServerCommand(player, MODULE, "failed", { playerNum = playerNum })
        end
        return true
    end

    if not TSPS.consumePaint(player:getInventory(), mix) then
        TSPS.log("TSPaintItemAction:complete REJECTED (consume failed)")
        if isServer() then
            sendServerCommand(player, MODULE, "failed", { playerNum = playerNum })
        end
        return true
    end
    TSPS.applyPaint(item, r, g, b, mix, nil, player)

    if isServer() then
        item:syncItemFields()
        notifyItemClients(player, item)
        sendServerCommand(player, MODULE, "painted", {
            playerNum = playerNum,
            itemId = item:getID(),
            r = r,
            g = g,
            b = b,
            mix = TSPS.mixToString(mix),
        })
        TSPS.log("TSPaintItemAction:complete sent 'painted' echo")
    end
    return true
end

function TSPaintItemAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 60
end

function TSPaintItemAction:new(character, item, mix, r, g, b)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.mix = mix
    o.r = r
    o.g = g
    o.b = b
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.caloriesModifier = 4
    return o
end

TSPaintRemoveAction = ISBaseTimedAction:derive("TSPaintRemoveAction")

function TSPaintRemoveAction:isValid()
    local item = TSPS.resolveItem(self.character, self.item)
    if not item or not TSPS.isPainted(item) then return false end
    self.item = item
    local inv = self.character:getInventory()
    self.solvent = TSPS.findSolvent(inv)
    self.cloth = TSPS.findCloth(inv)
    return self.solvent ~= nil and self.cloth ~= nil
end

function TSPaintRemoveAction:start()
    TSPS.log("TSPaintRemoveAction:start",
        "playerNum", self.character:getPlayerNum(),
        "itemId", self.item:getID(),
        "solventId", self.solvent and self.solvent:getID(),
        "clothId", self.cloth and self.cloth:getID())
    self:setActionAnim(CharacterActionAnims.Paint)
    self:setOverrideHandModels(self.cloth, self.solvent)
    self.sound = self.character:playSound("CleanBloodScrub")
    self.item:setJobType(getText("ContextMenu_TS_RemovingPaint"))
    self.item:setJobDelta(0)
end

function TSPaintRemoveAction:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function TSPaintRemoveAction:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    self.item:setJobDelta(0)
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
    local item = TSPS.resolveItem(player, self.item)
    local solvent = TSPS.resolveItem(player, self.solvent)
    local cloth = TSPS.resolveItem(player, self.cloth)
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
        item:syncItemFields()
        notifyItemClients(player, item)
        sendServerCommand(player, MODULE, "unpainted", {
            playerNum = playerNum,
            itemId = item:getID(),
        })
        TSPS.log("TSPaintRemoveAction:complete sent 'unpainted' echo")
    end
    return true
end

function TSPaintRemoveAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 100
end

function TSPaintRemoveAction:new(character, item, solvent, cloth)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.solvent = solvent
    o.cloth = cloth
    o.maxTime = o:getDuration()
    o.stopOnWalk = true
    o.stopOnRun = true
    o.caloriesModifier = 2
    return o
end
