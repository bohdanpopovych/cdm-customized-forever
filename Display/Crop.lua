local ADDON_NAME, ns = ...

local Compat = ns.Compat

local Crop = {}
ns.Crop = Crop

local function IsValidSize(v)
    return type(v) == "number" and not Compat.IsSecret(v) and v > 0
end

function Crop.TexCoords(w, h, zoom)
    if not (IsValidSize(w) and IsValidSize(h)) then
        return 0, 1, 0, 1
    end
    zoom = zoom or 0
    local l, r, t, b = zoom, 1 - zoom, zoom, 1 - zoom
    local span = 1 - 2 * zoom
    local ratio = w / h
    if ratio > 1 then
        local pad = (span - span / ratio) / 2
        t, b = t + pad, b - pad
    elseif ratio < 1 then
        local pad = (span - span * ratio) / 2
        l, r = l + pad, r - pad
    end
    return l, r, t, b
end

function Crop.OverlayInsets(viewerKey, w, h)
    local base = ns.VIEWERS[viewerKey] or ns.VIEWERS.Essential
    local o = base.overlay
    if not (IsValidSize(w) and IsValidSize(h)) then
        return o[1], o[2], o[3], o[4]
    end
    local sx, sy = w / base.w, h / base.h
    return o[1] * sx, o[2] * sy, o[3] * sx, o[4] * sy
end
