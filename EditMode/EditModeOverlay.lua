local ADDON_NAME, ns = ...

local DB = ns.DB
local Groups = ns.Groups

local Overlay = {}
ns.EditModeOverlay = Overlay

local KEYS = { "Left", "Right" }
local overlays = {}
local selected

local COLOR = { 0.1, 0.6, 1, 0.25 }
local COLOR_SELECTED = { 0.3, 0.8, 1, 0.5 }
local SELECTION_ATLAS = "EditModeUI-SelectionHighlight"

local function AnchorScreenPos(frame, point)
    local l, b, w, h = frame:GetRect()
    if not l then
        return nil
    end
    local s = frame:GetEffectiveScale()
    local x = (point:find("LEFT") and l) or (point:find("RIGHT") and l + w) or (l + w / 2)
    local y = (point:find("BOTTOM") and b) or (point:find("TOP") and b + h) or (b + h / 2)
    return x * s, y * s
end

function Overlay:SavePosition(key)
    local c = Groups:GetContainer(key)
    if not c then
        return
    end
    local point, target, relPoint = Groups:GetAnchor(key)
    local cx, cy = AnchorScreenPos(c, point)
    local tx, ty = AnchorScreenPos(target, relPoint)
    if not (cx and tx) then
        return
    end
    local s = c:GetEffectiveScale()
    local function Round(v)
        return math.floor(v * 10 + 0.5) / 10
    end
    DB:SetGroupOption(key, "x", Round((cx - tx) / s))
    DB:SetGroupOption(key, "y", Round((cy - ty) / s))
end

local function SetStyle(o, isSelected)
    local color = isSelected and COLOR_SELECTED or COLOR
    if o.useAtlas then
        o.bg:SetVertexColor(unpack(color))
    else
        o.bg:SetColorTexture(unpack(color))
    end
    local alpha = isSelected and 1 or 0.6
    for _, edge in ipairs(o.edges) do
        edge:SetColorTexture(0.3, 0.8, 1, alpha)
    end
end

local function UpdateStyles()
    for key, o in pairs(overlays) do
        SetStyle(o, key == selected)
    end
end

function Overlay:Select(key)
    selected = key
    UpdateStyles()
    local container = Groups:GetContainer(key)
    if container and ns.EditModePanel then
        ns.EditModePanel:ShowForGroup(key, container)
    end
end

function Overlay:Deselect()
    if not selected then
        return
    end
    selected = nil
    UpdateStyles()
    if ns.EditModePanel and ns.EditModePanel:GetMode() == "group" then
        ns.EditModePanel:Hide()
    end
end

local function CreateOverlay(key)
    if overlays[key] then
        return overlays[key]
    end
    local container = Groups:GetContainer(key)
    if not container then
        return nil
    end
    container:SetMovable(true)

    local o = CreateFrame("Button", nil, container)
    o:SetAllPoints(container)
    o:SetFrameLevel(container:GetFrameLevel() + 20)
    o:RegisterForClicks("LeftButtonUp")
    o:RegisterForDrag("LeftButton")
    o:Hide()

    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetAllPoints(o)
    o.useAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SELECTION_ATLAS) ~= nil
    if o.useAtlas then
        o.bg:SetAtlas(SELECTION_ATLAS)
    end

    o.edges = {}
    local function Edge(p1, p2, horizontal)
        local t = o:CreateTexture(nil, "BORDER")
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
        o.edges[#o.edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.label:SetPoint("CENTER")
    o.label:SetText(container.editModeName)

    o:SetScript("OnClick", function()
        Overlay:Select(key)
    end)
    o:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            return
        end
        Overlay:Select(key)
        container:StartMoving()
    end)
    o:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        Overlay:SavePosition(key)
        Groups:ApplyPosition(key)
        if ns.EditModePanel then
            ns.EditModePanel:Reanchor()
        end
    end)

    SetStyle(o, false)
    overlays[key] = o
    return o
end

ns.Subscribe("EDITMODE_ENTER", function()
    for _, key in ipairs(KEYS) do
        local o = CreateOverlay(key)
        if o then
            o:Show()
        end
    end
end)

ns.Subscribe("EDITMODE_EXIT", function()
    selected = nil
    for _, o in pairs(overlays) do
        o:Hide()
    end
    UpdateStyles()
    if ns.EditModePanel then
        ns.EditModePanel:Hide()
    end
end)

local initialized = false
local function Init()
    if initialized or not EditModeManagerFrame then
        return
    end
    initialized = true
    ns.inEditMode = EditModeManagerFrame:IsShown()
    hooksecurefunc(EditModeManagerFrame, "Show", ns.Safe(function()
        ns.inEditMode = true
        ns.Fire("EDITMODE_ENTER")
    end))
    hooksecurefunc(EditModeManagerFrame, "Hide", ns.Safe(function()
        ns.inEditMode = false
        ns.Fire("EDITMODE_EXIT")
    end))
end

if C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
    Init()
else
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", Init)
end
