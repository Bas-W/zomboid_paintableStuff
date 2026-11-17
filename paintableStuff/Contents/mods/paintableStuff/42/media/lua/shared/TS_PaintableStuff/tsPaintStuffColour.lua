-- TeaStain 17/11/2026

TS_PaintColour = TS_PaintColour or {}
local Colour = TS_PaintColour

function Colour.rgbToHsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min
    local h, s, v = 0, 0, max

    if max > 0 then s = delta / max end
    if delta > 0 then
        if max == r then
            h = (g - b) / delta
        elseif max == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
        if h < 0 then h = h + 1 end
    end

    return h, s, v
end

function Colour.hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6

    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

function Colour.adjust(r, g, b, sat, val)
    sat = sat or 1
    val = val or 1
    if sat == 1 and val == 1 then return r, g, b end

    local h, s, v = Colour.rgbToHsv(r, g, b)
    return Colour.hsvToRgb(h, math.max(0, math.min(1, s * sat)), math.max(0, math.min(1, v * val)))
end

-- Calculatest the resulting colour of all mixed parts
-- entries: { { r = ..., g = ..., b = ..., parts = ... }, ... }
function Colour.mix(entries, sat, val)
    local r, g, b, total = 0, 0, 0, 0

    for _, entry in ipairs(entries) do
        local parts = entry.parts or 0
        if parts > 0 then
            r = r + entry.r * parts
            g = g + entry.g * parts
            b = b + entry.b * parts
            total = total + parts
        end
    end

    if total == 0 then return 1, 1, 1 end
    return Colour.adjust(r / total, g / total, b / total, sat, val)
end
