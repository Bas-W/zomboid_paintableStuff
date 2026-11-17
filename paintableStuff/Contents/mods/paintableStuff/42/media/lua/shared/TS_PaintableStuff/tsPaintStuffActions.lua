-- TeaStain 16/11/2026

require "TimedActions/ISBaseTimedAction"
require "TS_PaintableStuff/tsPaintStuffApi"

local TSPS = TS_PaintStuff
local MODULE = "TS_PaintableStuff"

TSPaintItemAction = ISBaseTimedAction:derive("TSPaintItemAction")

function TSPaintItemAction:isValid()
    local item = TSPS.resolveItem(self.character, self.item)
    if not item then return false end
    self.item = item
    return TSPS.canPaint(self.character, item, self.mix)
end

function TSPaintItemAction:start()
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
    ISBaseTimedAction.perform(self)
end

function TSPaintItemAction:complete()
    if isClient() then
        sendClientCommand(self.character, MODULE, "paint", {
            playerNum = self.character:getPlayerNum(),
            itemId = self.item:getID(),
            r = self.r,
            g = self.g,
            b = self.b,
            mix = TSPS.mixToString(self.mix),
        })
    else
        TSPS.applyPaint(self.item, self.r, self.g, self.b, self.mix, nil, self.character)
        TSPS.consumePaint(self.character:getInventory(), self.mix)
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
    ISBaseTimedAction.perform(self)
end

function TSPaintRemoveAction:complete()
    if isClient() then
        sendClientCommand(self.character, MODULE, "unpaint", {
            playerNum = self.character:getPlayerNum(),
            itemId = self.item:getID(),
            solventId = self.solvent:getID(),
            clothId = self.cloth:getID(),
        })
    elseif TSPS.consumePetrol(self.solvent) then
        TSPS.clearPaint(self.item, self.character)
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
