-- TeaStain 18/11/2026
--
-- Mod options

require "TS_PaintableStuff/tsPaintStuffApi"
require "TS_PaintableStuff/tsPaintStuffWorldModelOverride"

local TSPS = TS_PaintStuff

local MOD_ID = "tsPaintableStuff"
local OPTION_ID = "worldModelSwap"

local ok = pcall(require, "PZAPI/ModOptions")
if not ok or not PZAPI or not PZAPI.ModOptions then
    TSPS.log("ModOptions unavailable, world model swap defaults to", TSPS.settings.worldModelSwap)
    return
end

local options = PZAPI.ModOptions:create(MOD_ID, "UI_TS_PaintableStuff_ModOptions")
local tickbox = options:addTickBox(
    OPTION_ID,
    "UI_TS_PaintableStuff_WorldModelSwap",
    true,
    "UI_TS_PaintableStuff_WorldModelSwap_Tooltip"
)

TSPS.settings.worldModelSwap = tickbox.value == true

tickbox.onChangeApply = function(value)
    TSPS.setWorldModelSwap(value)
    if TSPS.scanWorldItemsAround then
        TSPS.scanWorldItemsAround(getPlayer and getPlayer(), true)
    end
end

local function loadSettings()
    PZAPI.ModOptions:load()
    local registered = PZAPI.ModOptions:getOptions(MOD_ID)
    local option = registered and registered:getOption(OPTION_ID)
    if option then
        TSPS.settings.worldModelSwap = option.value == true
    end
end

Events.OnGameStart.Add(function()
    loadSettings()
    TSPS.refreshLocalWorldModels()
    if TSPS.scanWorldItemsAround then
        TSPS.scanWorldItemsAround(getPlayer and getPlayer(), true)
    end
end)
