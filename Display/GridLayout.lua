local ADDON_NAME, ns = ...

local GridLayout = {}
ns.GridLayout = GridLayout

local function Vector(direction)
    if direction == "LEFT" then
        return -1, 0
    elseif direction == "RIGHT" then
        return 1, 0
    elseif direction == "UP" then
        return 0, 1
    elseif direction == "DOWN" then
        return 0, -1
    end
end

local function Snap(value, frame)
    if value == 0 or not (PixelUtil and PixelUtil.GetNearestPixelSize) then
        return value
    end
    local sign = value < 0 and -1 or 1
    return sign * PixelUtil.GetNearestPixelSize(math.abs(value), frame:GetEffectiveScale(), 0)
end

local function SetPointIfChanged(frame, point, relativeTo, x, y)
    local p, rel, relPoint, ox, oy = frame:GetPoint()
    if p == point and rel == relativeTo and relPoint == point and ox and oy and math.abs(ox - x) < 0.001 and math.abs(oy - y) < 0.001 then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, point, x, y)
end

function GridLayout.Apply(frames, opts)
    local count = #frames
    local w, h, spacing = opts.w, opts.h, opts.spacing or 0
    local perLine = math.max(1, opts.perLine or count)
    local horizontal = opts.orientation ~= "VERTICAL"

    local dx, dy
    if horizontal then
        dx = select(1, Vector(opts.primary)) or 1
        dy = select(2, Vector(opts.secondary)) or -1
    else
        dy = select(2, Vector(opts.primary)) or -1
        dx = select(1, Vector(opts.secondary)) or 1
    end
    if dx == 0 then dx = 1 end
    if dy == 0 then dy = -1 end

    local point = (dy > 0 and "BOTTOM" or "TOP") .. (dx > 0 and "LEFT" or "RIGHT")

    for i, frame in ipairs(frames) do
        local index = i - 1
        local a, b = index % perLine, math.floor(index / perLine)
        local x, y
        if horizontal then
            x, y = a * (w + spacing) * dx, b * (h + spacing) * dy
        else
            x, y = b * (w + spacing) * dx, a * (h + spacing) * dy
        end
        SetPointIfChanged(frame, point, opts.anchorFrame, Snap(x, frame), Snap(y, frame))
    end

    if count == 0 then
        return 0, 0
    end
    local lineCount = math.min(perLine, count)
    local lines = math.ceil(count / perLine)
    if horizontal then
        return lineCount * w + (lineCount - 1) * spacing, lines * h + (lines - 1) * spacing
    end
    return lines * w + (lines - 1) * spacing, lineCount * h + (lineCount - 1) * spacing
end
