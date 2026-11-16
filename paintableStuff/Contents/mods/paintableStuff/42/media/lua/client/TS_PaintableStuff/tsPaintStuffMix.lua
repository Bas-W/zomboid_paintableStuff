-- TeaStain 16/11/2026

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISTimedActionQueue"
require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffActions"

local TSPS = TS_PaintStuff

TSPaintMixPanel = ISPanel:derive("TSPaintMixPanel")

local PAD = 10
local ROW_H = 24
local BTN_H = 22
local BTN_W = 90
local SWATCH = 16
local PREVIEW = 44
local MINUS_X = 266
local COUNT_X = 292
local PLUS_X = 314

function TSPaintMixPanel:new(player, item)
    local paints = TSPS.getAvailablePaints(player:getInventory())
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local width = 380
    local height = 34 + #paints * ROW_H + fontH + 102
    local panel = ISPanel:new(
        math.floor((getCore():getScreenWidth() - width) / 2),
        math.floor((getCore():getScreenHeight() - height) / 2),
        width, height)

    setmetatable(panel, self)
    self.__index = self
    panel.player = player
    panel.item = item
    panel.paints = paints
    panel.parts = {}
    panel.fontH = fontH
    panel.moveWithMouse = true
    panel.wantKeyEvents = true
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    panel.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return panel
end

function TSPaintMixPanel:createChildren()
    local y = 34
    for _, paint in ipairs(self.paints) do
        local paintType = paint.entry.paint
        self.parts[paintType] = 0

        local minus = ISButton:new(MINUS_X, y, 22, BTN_H, "-", self, function() self:changePart(paintType, -1) end)
        minus:initialise()
        self:addChild(minus)

        local plus = ISButton:new(PLUS_X, y, 22, BTN_H, "+", self, function() self:changePart(paintType, 1) end)
        plus:initialise()
        self:addChild(plus)

        y = y + ROW_H
    end

    local footerY = self.height - PAD - BTN_H
    self.paintButton = ISButton:new(self.width - PAD - BTN_W * 2 - 8, footerY, BTN_W, BTN_H, getText("UI_TS_Mix_Paint"), self, self.onPaint)
    self.paintButton:initialise()
    self:addChild(self.paintButton)

    local cancelButton = ISButton:new(self.width - PAD - BTN_W, footerY, BTN_W, BTN_H, getText("UI_TS_Mix_Cancel"), self, self.onCancel)
    cancelButton:initialise()
    self:addChild(cancelButton)

    self:refreshPaintButton()
end

function TSPaintMixPanel:changePart(paintType, delta)
    self.parts[paintType] = math.max(0, math.min(TSPS.MAX_MIX_PARTS, (self.parts[paintType] or 0) + delta))
    self:refreshPaintButton()
end

function TSPaintMixPanel:refreshPaintButton()
    if self.paintButton then self.paintButton.enable = self:getCost() > 0 end
end

function TSPaintMixPanel:getMix()
    local mix = {}
    for _, paint in ipairs(self.paints) do
        local parts = self.parts[paint.entry.paint] or 0
        if parts > 0 then
            mix[#mix + 1] = { paint = paint.entry.paint, parts = parts }
        end
    end
    return mix
end

function TSPaintMixPanel:getCost()
    return #self:getMix()
end

function TSPaintMixPanel:getSelectedNames()
    local names = {}
    for _, paint in ipairs(self.paints) do
        if (self.parts[paint.entry.paint] or 0) > 0 then
            names[#names + 1] = getText(paint.entry.text)
        end
    end
    return table.concat(names, ", ")
end

function TSPaintMixPanel:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_TS_Mix_Title"), PAD, PAD, 1, 1, 1, 1, UIFont.Small)

    local y = 34
    for _, paint in ipairs(self.paints) do
        local color = paint.entry.color
        local textY = y + (ROW_H - self.fontH) / 2
        self:drawRect(PAD, y + 4, SWATCH, SWATCH, 1, color[1], color[2], color[3])
        self:drawRectBorder(PAD, y + 4, SWATCH, SWATCH, 0.4, 0, 0, 0)
        self:drawText(getText(paint.entry.text) .. " (" .. paint.uses .. ")", PAD + 24, textY, 1, 1, 1, 1, UIFont.Small)
        self:drawText(tostring(self.parts[paint.entry.paint] or 0), COUNT_X, textY, 1, 1, 1, 1, UIFont.Small)
        y = y + ROW_H
    end

    local r, g, b = TSPS.mixColor(self:getMix())
    local previewY = y + 8
    self:drawText(getText("UI_TS_Mix_Result"), PAD, previewY, 1, 1, 1, 1, UIFont.Small)
    local swatchY = previewY + self.fontH + 4
    self:drawRect(PAD, swatchY, PREVIEW, PREVIEW, 1, r, g, b)
    self:drawRectBorder(PAD, swatchY, PREVIEW, PREVIEW, 0.6, 0, 0, 0)

    local texture = self.item:getTex()
    if texture then
        self:drawTextureScaledAspect(texture, PAD + PREVIEW + 10, swatchY, PREVIEW, PREVIEW, 1, r, g, b)
    end

    local cost = getText("UI_TS_Mix_Uses", self:getCost())
    local names = self:getSelectedNames()
    if names ~= "" then cost = cost .. " (" .. names .. ")" end
    self:drawText(cost, PAD + PREVIEW * 2 + 20, swatchY, 1, 1, 1, 1, UIFont.Small)
end

function TSPaintMixPanel:onPaint()
    local mix = self:getMix()
    local item = TSPS.findItem(self.player, self.item:getID())
    if not item or not TSPS.canPaint(self.player, item, mix) then
        HaloTextHelper.addBadText(self.player, getText("UI_TS_Paint_Failed"))
        return
    end

    self:close()
    ISTimedActionQueue.add(TSPaintItemAction:new(self.player, item, mix))
end

function TSPaintMixPanel:onCancel()
    self:close()
end

function TSPaintMixPanel:onKeyPressed(key)
    if key == Keyboard.KEY_ESCAPE then
        self:close()
        return true
    end
end

function TSPaintMixPanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
end
