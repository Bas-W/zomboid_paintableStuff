-- TeaStain 16/11/2026

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "TimedActions/ISTimedActionQueue"
require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffActions"

local TSPS = TS_PaintStuff

TSPaintMixPanel = ISPanel:derive("TSPaintMixPanel")

local PANEL_W = 450
local PAD = 10
local MARGIN = 8
local ROW_H = 24
local BTN_H = 22
local BTN_W = 90
local BTN_SMALL_W = 22
local SWATCH = 16
local PREVIEW_SIZE = 44
local SLIDER_H = 18
local SLIDER_GAP = 6
local SLIDER_W = 170
local PLUS_X = PANEL_W - PAD - BTN_SMALL_W
local COUNT_X = PLUS_X - PAD - BTN_SMALL_W / 2
local MINUS_X = COUNT_X - PAD - BTN_SMALL_W * 1.5

function TSPaintMixPanel:new(player, item)
    local paints = TSPS.getAvailablePaints(player:getInventory())
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local contentY = getTextManager():getFontHeight(UIFont.Medium) + PAD
    local sliderY = contentY + #paints * ROW_H + PAD
    local previewY = sliderY + BTN_H * 2 + SLIDER_GAP + 2 * MARGIN

    local sliderLabelW = math.min(getTextManager():MeasureStringX(UIFont.Small, getText("UI_TS_Mix_Saturation")),
     getTextManager():MeasureStringX(UIFont.Small, getText("UI_TS_Mix_Brightness")))

    local width = PANEL_W
    local height = previewY + PREVIEW_SIZE + PAD
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
    panel.sliderLabelW = sliderLabelW
    panel.contentY = contentY
    panel.sliderY = sliderY
    panel.previewY = previewY
    panel.moveWithMouse = true
    panel.wantKeyEvents = true
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    panel.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return panel
end

local function createSlider(panel, x, y)
    local slider = ISSliderPanel:new(x, y, SLIDER_W, SLIDER_H, panel, nil)
    slider:initialise()
    slider:setDoButtons(false)
    slider:setValues(0, 200, 1, 10)
    slider:setCurrentValue(100, true)
    panel:addChild(slider)
    return slider
end

function TSPaintMixPanel:createChildren()
    -- Paint selection
    local y = self.contentY
    for _, paint in ipairs(self.paints) do
        local paintType = paint.entry.paint
        self.parts[paintType] = 0

        local minus = ISButton:new(MINUS_X, y, BTN_SMALL_W, BTN_H, "-", self, function() self:changePart(paintType, -1) end)
        minus:initialise()
        self:addChild(minus)

        local plus = ISButton:new(PLUS_X, y, BTN_SMALL_W, BTN_H, "+", self, function() self:changePart(paintType, 1) end)
        plus:initialise()
        self:addChild(plus)

        y = y + ROW_H
    end

    -- Saturation/Value sliders.    
    local sliderX = PAD + self.sliderLabelW + MARGIN
    local sliderResetButtonX = self.width - PAD - BTN_W
    self.satSlider = createSlider(self, sliderX, self.sliderY)
    self.valSlider = createSlider(self, sliderX, self.sliderY + BTN_H + SLIDER_GAP)

    self.satResetButton = ISButton:new(sliderResetButtonX, self.sliderY, BTN_W, BTN_H, getText("UI_TS_Slider_Reset"), self, (function() self.satSlider:setCurrentValue(100, true) end))
    self.valResetButton = ISButton:new(sliderResetButtonX, self.sliderY + BTN_H + SLIDER_GAP, BTN_W, BTN_H, getText("UI_TS_Slider_Reset"), self, (function() self.valSlider:setCurrentValue(100, true) end))

    self.satResetButton:initialise()
    self.valResetButton:initialise()
    self:addChild(self.satResetButton)
    self:addChild(self.valResetButton)

    -- Confirm/cancel buttons
    local footerY = self.height - PAD - BTN_H
    self.paintButton = ISButton:new(self.width - PAD - BTN_W * 2 - MARGIN, footerY, BTN_W, BTN_H, getText("UI_TS_Mix_Paint"), self, self.onPaint)
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
    mix.sat = self.satSlider and self.satSlider:getCurrentValue() / 100 or 1
    mix.val = self.valSlider and self.valSlider:getCurrentValue() / 100 or 1
    return mix
end

function TSPaintMixPanel:getCost()
    return #self:getMix()
end

function TSPaintMixPanel:prerender()
    ISPanel.prerender(self)

    -- Header
    self:drawText(getText("UI_TS_Mix_Title"), PAD, PAD * 0.35, 1, 1, 1, 1, UIFont.Medium)

    -- Paint selection
    local y = self.contentY
    for _, paint in ipairs(self.paints) do
        local color = paint.entry.color
        local textY = y + (ROW_H - self.fontH) / 2
        local valueStr = tostring(self.parts[paint.entry.paint] or 0)
        local valueStrSizeX = getTextManager():MeasureStringX(UIFont.Small, valueStr)
        self:drawRect(PAD, y + 4, SWATCH, SWATCH, 1, color[1], color[2], color[3])
        self:drawRectBorder(PAD, y + 4, SWATCH, SWATCH, 0.4, 0, 0, 0)
        self:drawText(getText(paint.entry.text) .. " (" .. paint.uses .. ")", PAD + 24, textY, 1, 1, 1, 1, UIFont.Small)
        self:drawText(valueStr, COUNT_X - valueStrSizeX / 2, textY, 1, 1, 1, 1, UIFont.Small)
        y = y + ROW_H
    end

    -- Saturation/Value slider text
    local valueX = PAD + self.sliderLabelW + SLIDER_W + 2 * MARGIN
    local satY = self.sliderY + (SLIDER_H - self.fontH) / 2
    self:drawText(getText("UI_TS_Mix_Saturation"), PAD, satY, 1, 1, 1, 1, UIFont.Small)
    self:drawText(string.format("%d%%", math.floor(self.satSlider:getCurrentValue())), valueX, satY, 1, 1, 1, 1, UIFont.Small)

    local valY = self.sliderY + BTN_H + SLIDER_GAP + (SLIDER_H - self.fontH) / 2
    self:drawText(getText("UI_TS_Mix_Brightness"), PAD, valY, 1, 1, 1, 1, UIFont.Small)
    self:drawText(string.format("%d%%", math.floor(self.valSlider:getCurrentValue())), valueX, valY, 1, 1, 1, 1, UIFont.Small)

    -- Colour preview
    local r, g, b = TSPS.mixColor(self:getMix())
    self:drawRect(PAD, self.previewY, PREVIEW_SIZE, PREVIEW_SIZE, 1, r, g, b)
    self:drawRectBorder(PAD, self.previewY, PREVIEW_SIZE, PREVIEW_SIZE, 0.6, 0, 0, 0)
end

function TSPaintMixPanel:onPaint()
    local mix = self:getMix()
    local item = TSPS.findItem(self.player, self.item:getID())
    if not item or not TSPS.canPaint(self.player, item, mix) then
        HaloTextHelper.addBadText(self.player, getText("UI_TS_Paint_Failed"))
        return
    end

    local r, g, b = TSPS.mixColor(mix)
    self:close()
    ISTimedActionQueue.add(TSPaintItemAction:new(self.player, item, mix, r, g, b))
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
