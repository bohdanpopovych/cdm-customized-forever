local ADDON_NAME, ns = ...

local DB = ns.DB
local Entries = ns.Entries
local IconFrame = ns.IconFrame
local GridLayout = ns.GridLayout

local Groups = {}
ns.Groups = Groups

local KEYS = { "Left", "Right" }
local FRAME_NAMES = { Left = "CDMC_AdditionalLeft", Right = "CDMC_AdditionalRight" }

local containers = {}
local icons = { Left = {}, Right = {} }
local viewerHooked = false

function Groups:GetContainer(key)
    return containers[key]
end

local function IsAdditional(key)
    return key == "Left" or key == "Right"
end

local function Create(key)
    if containers[key] then
        return containers[key]
    end
    local c = CreateFrame("Frame", FRAME_NAMES[key], UIParent)
    c:SetFrameStrata("MEDIUM")
    c:SetClampedToScreen(true)
    c:EnableMouse(false)
    c.groupKey = key
    c.editModeName = ns.GROUP_LABELS[key]
    containers[key] = c
    return c
end

local GROW_POINT = { LEFT = "RIGHT", RIGHT = "LEFT", UP = "BOTTOM", DOWN = "TOP" }

function Groups:GetAnchor(key)
    local cfg = DB:Group(key)
    local viewer = _G[ns.VIEWERS.Essential.frame]
    if cfg.attach and viewer then
        return cfg.point, viewer, cfg.relPoint
    end
    return GROW_POINT[cfg.grow] or cfg.point, UIParent, "CENTER"
end

function Groups:ApplyPosition(key)
    local c, cfg = containers[key], DB:Group(key)
    if not c then
        return
    end
    local point, relativeTo, relPoint = self:GetAnchor(key)
    c:ClearAllPoints()
    c:SetPoint(point, relativeTo, relPoint, cfg.x, cfg.y)
end

function Groups:UpdateVisibility(key)
    local c, cfg = containers[key], DB:Group(key)
    if not c then
        return
    end
    local viewer = _G[ns.VIEWERS.Essential.frame]
    local show, alpha = true, cfg.alpha

    if ns.inEditMode then
        show = true
    elseif not cfg.enabled then
        show = false
    elseif cfg.visibility == "combat" then
        show = UnitAffectingCombat("player") and true or false
    elseif cfg.visibility == "essential" then
        show = viewer ~= nil and viewer:IsShown()
        if viewer then
            alpha = cfg.alpha * viewer:GetAlpha()
        end
    end

    if c:GetAlpha() ~= alpha then
        c:SetAlpha(alpha)
    end
    if c:IsShown() ~= show then
        c:SetShown(show)
    end
end

function Groups:UpdateAllVisibility()
    for _, key in ipairs(KEYS) do
        self:UpdateVisibility(key)
    end
end

local function EnsureViewerHooks()
    if viewerHooked then
        return
    end
    local viewer = _G[ns.VIEWERS.Essential.frame]
    if not viewer then
        return
    end
    viewerHooked = true
    local update = ns.Safe(function() Groups:UpdateAllVisibility() end)
    viewer:HookScript("OnShow", update)
    viewer:HookScript("OnHide", update)
    hooksecurefunc(viewer, "SetAlpha", update)

    for _, key in ipairs(KEYS) do
        Groups:ApplyPosition(key)
    end
end

local function ReleaseAll(key)
    for entryKey, frame in pairs(icons[key]) do
        IconFrame.Release(frame)
        icons[key][entryKey] = nil
    end
end

function Groups:Rebuild(key)
    if not IsAdditional(key) or not DB:Profile() then
        return
    end
    local c = Create(key)
    EnsureViewerHooks()
    local cfg = DB:Group(key)

    if not cfg.enabled then
        ReleaseAll(key)
        c:SetSize(cfg.width, cfg.height)
        c:SetScale(cfg.scale)
        self:ApplyPosition(key)
        self:UpdateVisibility(key)
        return
    end

    local visible, wanted = {}, {}
    for _, entry in ipairs(DB:Entries(key)) do
        if Entries:IsAvailable(entry) then
            wanted[Entries:Key(entry)] = entry
        end
    end
    for entryKey, frame in pairs(icons[key]) do
        if not wanted[entryKey] then
            IconFrame.Release(frame)
            icons[key][entryKey] = nil
        end
    end

    local opts = { showGCD = cfg.showGCD, showTimer = cfg.showTimer, showTooltips = cfg.showTooltips }
    for _, entry in ipairs(DB:Entries(key)) do
        local entryKey = Entries:Key(entry)
        if wanted[entryKey] then
            local frame = icons[key][entryKey]
            if not frame then
                frame = IconFrame.Acquire(c)
                icons[key][entryKey] = frame
            end
            frame:ApplySize(cfg.width, cfg.height, cfg.zoom, "Essential")
            frame:SetEntry(entry, opts)
            visible[#visible + 1] = frame
        end
    end

    local totalW, totalH = GridLayout.Apply(visible, {
        w = cfg.width,
        h = cfg.height,
        spacing = cfg.spacing,
        perLine = cfg.perLine,
        orientation = cfg.orientation,
        primary = cfg.grow,
        secondary = cfg.wrap,
        anchorFrame = c,
    })

    c:SetSize(math.max(totalW, cfg.width), math.max(totalH, cfg.height))
    c:SetScale(cfg.scale)

    self:ApplyPosition(key)
    self:UpdateVisibility(key)
end

function Groups:RebuildAll()
    for _, key in ipairs(KEYS) do
        self:Rebuild(key)
    end
end

local function RequestRebuild(key)
    ns.Debounce("groups-rebuild-" .. key, function()
        Groups:Rebuild(key)
    end)
end

ns.Subscribe("PROFILE_READY", function()
    for _, key in ipairs(KEYS) do
        Create(key)
    end
    Groups:RebuildAll()
end)
ns.Subscribe("ENTRIES_CHANGED", function(key)
    if IsAdditional(key) then
        RequestRebuild(key)
    end
end)
ns.Subscribe("GROUP_LAYOUT_CHANGED", function(key)
    if IsAdditional(key) then
        RequestRebuild(key)
    end
end)
ns.Subscribe("AVAILABILITY_CHANGED", function()
    for _, key in ipairs(KEYS) do
        RequestRebuild(key)
    end
end)
for _, msg in ipairs({ "COMBAT_START", "COMBAT_END", "EDITMODE_ENTER", "EDITMODE_EXIT" }) do
    ns.Subscribe(msg, function()
        Groups:UpdateAllVisibility()
    end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
    if DB:Profile() then
        EnsureViewerHooks()
        Groups:UpdateAllVisibility()
    end
end)
