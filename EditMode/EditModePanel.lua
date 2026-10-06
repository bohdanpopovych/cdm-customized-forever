local ADDON_NAME, ns = ...

local DB = ns.DB

local Panel = {}
ns.EditModePanel = Panel

local PANEL_WIDTH, GAP, MAX_HEIGHT_FRACTION = 300, 6, 0.85

local panel, scroll, titleText
local viewerContent, groupContent
local viewerWidgets, groupWidgets
local mode, currentViewer, currentGroup, anchorTarget
local squareLink = false

local viewerByFrame = {}
for key, data in pairs(ns.VIEWERS) do
    viewerByFrame[data.frame] = key
end

local VIEWER_LABELS = {
    Essential = ns.GROUP_LABELS.Essential,
    Utility = ns.GROUP_LABELS.Utility,
    BuffIcon = "Buff icons",
}

local function Percent(v)
    return v .. "%"
end

function Panel:GetMode()
    return mode
end

local function EnsurePanel()
    if panel then
        return
    end
    panel = CreateFrame("Frame", "CDMC_EditModePanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, 300)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:Hide()
    if BACKDROP_DIALOG_32_32 then
        panel:SetBackdrop(BACKDROP_DIALOG_32_32)
    else
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        panel:SetBackdropColor(0, 0, 0, 0.9)
    end

    local titleBar = CreateFrame("Frame", nil, panel)
    titleBar:SetPoint("TOPLEFT", 8, -6)
    titleBar:SetPoint("TOPRIGHT", -30, -6)
    titleBar:SetHeight(24)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 6, 0)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -36)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    if scroll.ScrollBar then
        scroll.ScrollBar:ClearAllPoints()
        scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
        scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    end

    viewerContent = CreateFrame("Frame", nil, scroll)
    viewerContent:SetSize(ns.Widgets.WIDTH, 1)
    viewerContent:Hide()
    groupContent = CreateFrame("Frame", nil, scroll)
    groupContent:SetSize(ns.Widgets.WIDTH, 1)
    groupContent:Hide()
end

local function RefreshList(list)
    for _, w in ipairs(list or {}) do
        w:Refresh()
    end
end

function Panel:Refresh()
    if mode == "viewer" and viewerWidgets then
        RefreshList(viewerWidgets.list)
        local custom = DB:Viewer(currentViewer).enabled
        viewerWidgets.width:SetEnabledState(custom)
        viewerWidgets.height:SetEnabledState(custom)
        viewerWidgets.square:SetEnabledState(custom)
        viewerWidgets.zoom:SetEnabledState(custom)
    elseif mode == "group" and groupWidgets then
        RefreshList(groupWidgets.list)
    end
end

local function Place(target)
    if not (panel and target) then
        return
    end
    local panelWidthPx = PANEL_WIDTH * panel:GetEffectiveScale()
    local right = target:GetRight()
    local screenRight = UIParent:GetRight()
    panel:ClearAllPoints()
    if right and screenRight then
        local rightPx = right * target:GetEffectiveScale()
        local gapPx = GAP * panel:GetEffectiveScale()
        if rightPx + gapPx + panelWidthPx > screenRight * UIParent:GetEffectiveScale() then
            panel:SetPoint("TOPRIGHT", target, "TOPLEFT", -GAP, 0)
            return
        end
    end
    panel:SetPoint("TOPLEFT", target, "TOPRIGHT", GAP, 0)
end

function Panel:Reanchor()
    if panel and panel:IsShown() then
        Place(anchorTarget)
    end
end

local function FitHeight(contentHeight)
    local maxHeight = math.floor(UIParent:GetHeight() * MAX_HEIGHT_FRACTION)
    panel:SetHeight(math.min(contentHeight + 52, maxHeight))
end

local function ShowContent(content)
    viewerContent:SetShown(content == viewerContent)
    groupContent:SetShown(content == groupContent)
    scroll:SetScrollChild(content)
    scroll:SetVerticalScroll(0)
end

function Panel:Hide()
    mode = nil
    if panel then
        panel:Hide()
    end
end

local function BuildViewerWidgets()
    local W = ns.Widgets
    local content = viewerContent
    local function cfg()
        return DB:Viewer(currentViewer)
    end
    local function SizeOf()
        return DB:GetViewerSize(currentViewer)
    end
    local set = function(field, value)
        DB:SetViewerOption(currentViewer, field, value)
        Panel:Refresh()
    end

    local w = {}
    w.enabled = W.Checkbox(content, {
        label = "Custom icon size",
        get = function() return cfg().enabled end,
        set = function(v) set("enabled", v) end,
    })
    w.width = W.Slider(content, {
        label = "Width", min = ns.MIN_SIZE, max = ns.MAX_SIZE,
        get = function() return (SizeOf()) end,
        set = function(v)
            set("width", v)
            if squareLink then set("height", v) end
        end,
    })
    w.height = W.Slider(content, {
        label = "Height", min = ns.MIN_SIZE, max = ns.MAX_SIZE,
        get = function() return select(2, SizeOf()) end,
        set = function(v)
            set("height", v)
            if squareLink then set("width", v) end
        end,
    })
    w.square = W.Checkbox(content, {
        label = "Square (width = height)",
        get = function() return squareLink end,
        set = function(v)
            squareLink = v
            if v then set("height", (SizeOf())) end
        end,
    })
    w.zoom = W.Slider(content, {
        label = "Zoom", min = 0, max = 30, format = Percent,
        get = function() return math.floor(cfg().zoom * 100 + 0.5) end,
        set = function(v) set("zoom", v / 100) end,
    })
    w.reset = W.Button(content, {
        text = "Reset to native size",
        onClick = function()
            local key = currentViewer
            DB:SetViewerOption(key, "enabled", false)
            DB:SetViewerOption(key, "width", nil)
            DB:SetViewerOption(key, "height", nil)
            DB:SetViewerOption(key, "zoom", 0)
            Panel:Refresh()
        end,
    })
    w.list = { w.enabled, w.width, w.height, w.square, w.zoom, w.reset }
    W.Stack(content, w.list)
    return w
end

function Panel:ShowForViewer(key)
    if InCombatLockdown() or not ns.VIEWERS[key] then
        self:Hide()
        return
    end
    EnsurePanel()
    mode, currentViewer = "viewer", key
    viewerWidgets = viewerWidgets or BuildViewerWidgets()
    titleText:SetText("CDM Customizer \226\128\148 " .. VIEWER_LABELS[key])
    ShowContent(viewerContent)
    FitHeight(viewerContent:GetHeight())
    self:Refresh()

    local dialog = _G.EditModeSystemSettingsDialog
    anchorTarget = dialog
    if dialog then
        panel:SetFrameStrata(dialog:GetFrameStrata())
        panel:SetFrameLevel(dialog:GetFrameLevel() + 10)
    else
        panel:SetFrameStrata("DIALOG")
    end
    Place(dialog)
    panel:Show()
end

local DIRECTION_TEXT = { LEFT = "Left", RIGHT = "Right", UP = "Up", DOWN = "Down" }

local function DirectionOptions(values)
    local list = {}
    for _, v in ipairs(values) do
        list[#list + 1] = { value = v, text = DIRECTION_TEXT[v] }
    end
    return list
end

local function BuildGroupWidgets()
    local W = ns.Widgets
    local content = groupContent
    local function cfg()
        return DB:Group(currentGroup)
    end
    local set = function(field, value)
        DB:SetGroupOption(currentGroup, field, value)
        Panel:Refresh()
    end

    local w = {}
    w.enabled = W.Checkbox(content, {
        label = "Enabled",
        get = function() return cfg().enabled end,
        set = function(v) set("enabled", v) end,
    })
    w.width = W.Slider(content, {
        label = "Width", min = ns.MIN_SIZE, max = ns.MAX_SIZE,
        get = function() return cfg().width end,
        set = function(v)
            set("width", v)
            if squareLink then set("height", v) end
        end,
    })
    w.height = W.Slider(content, {
        label = "Height", min = ns.MIN_SIZE, max = ns.MAX_SIZE,
        get = function() return cfg().height end,
        set = function(v)
            set("height", v)
            if squareLink then set("width", v) end
        end,
    })
    w.square = W.Checkbox(content, {
        label = "Square (width = height)",
        get = function() return squareLink end,
        set = function(v)
            squareLink = v
            if v then set("height", cfg().width) end
        end,
    })
    w.zoom = W.Slider(content, {
        label = "Zoom", min = 0, max = 30, format = Percent,
        get = function() return math.floor(cfg().zoom * 100 + 0.5) end,
        set = function(v) set("zoom", v / 100) end,
    })
    w.spacing = W.Slider(content, {
        label = "Spacing", min = 0, max = 20,
        get = function() return cfg().spacing end,
        set = function(v) set("spacing", v) end,
    })
    w.perLine = W.Slider(content, {
        label = "Icons per line", min = 1, max = 20,
        get = function() return cfg().perLine end,
        set = function(v) set("perLine", v) end,
    })
    w.orientation = W.Dropdown(content, {
        label = "Orientation",
        options = { { value = "HORIZONTAL", text = "Horizontal" }, { value = "VERTICAL", text = "Vertical" } },
        get = function() return cfg().orientation end,
        set = function(v)
            local key = currentGroup
            DB:SetGroupOption(key, "orientation", v)
            local c = DB:Group(key)
            local side = key == "Left" and "LEFT" or "RIGHT"
            if v == "VERTICAL" then
                if c.grow ~= "UP" and c.grow ~= "DOWN" then DB:SetGroupOption(key, "grow", "DOWN") end
                if c.wrap ~= "LEFT" and c.wrap ~= "RIGHT" then DB:SetGroupOption(key, "wrap", side) end
            else
                if c.grow ~= "LEFT" and c.grow ~= "RIGHT" then DB:SetGroupOption(key, "grow", side) end
                if c.wrap ~= "UP" and c.wrap ~= "DOWN" then DB:SetGroupOption(key, "wrap", "DOWN") end
            end
            Panel:Refresh()
        end,
    })
    w.grow = W.Dropdown(content, {
        label = "Grow direction",
        options = function()
            return DirectionOptions(cfg().orientation == "VERTICAL" and { "UP", "DOWN" } or { "LEFT", "RIGHT" })
        end,
        get = function() return cfg().grow end,
        set = function(v) set("grow", v) end,
    })
    w.wrap = W.Dropdown(content, {
        label = "Wrap direction",
        options = function()
            return DirectionOptions(cfg().orientation == "VERTICAL" and { "LEFT", "RIGHT" } or { "UP", "DOWN" })
        end,
        get = function() return cfg().wrap end,
        set = function(v) set("wrap", v) end,
    })
    w.scale = W.Slider(content, {
        label = "Scale", min = 50, max = 200, format = Percent,
        get = function() return math.floor(cfg().scale * 100 + 0.5) end,
        set = function(v) set("scale", v / 100) end,
    })
    w.alpha = W.Slider(content, {
        label = "Opacity", min = 10, max = 100, format = Percent,
        get = function() return math.floor(cfg().alpha * 100 + 0.5) end,
        set = function(v) set("alpha", v / 100) end,
    })
    w.visibility = W.Dropdown(content, {
        label = "Visibility",
        options = {
            { value = "essential", text = "Follow Essential" },
            { value = "always", text = "Always" },
            { value = "combat", text = "In combat" },
        },
        get = function() return cfg().visibility end,
        set = function(v) set("visibility", v) end,
    })
    w.attach = W.Checkbox(content, {
        label = "Attach to Essential",
        get = function() return cfg().attach end,
        set = function(v)
            local key = currentGroup

            DB:Group(key).attach = v
            ns.EditModeOverlay:SavePosition(key)
            DB:SetGroupOption(key, "attach", v)
            Panel:Refresh()
        end,
    })
    w.showGCD = W.Checkbox(content, {
        label = "Show global cooldown swipe",
        get = function() return cfg().showGCD end,
        set = function(v) set("showGCD", v) end,
    })
    w.showTimer = W.Checkbox(content, {
        label = "Show timer numbers",
        get = function() return cfg().showTimer end,
        set = function(v) set("showTimer", v) end,
    })
    w.showTooltips = W.Checkbox(content, {
        label = "Show tooltips",
        get = function() return cfg().showTooltips end,
        set = function(v) set("showTooltips", v) end,
    })
    w.resetPos = W.Button(content, {
        text = "Reset position",
        onClick = function()
            DB:ResetGroupPosition(currentGroup)
            Panel:Refresh()
        end,
    })
    w.contents = W.Button(content, {
        text = "Edit contents\226\128\166",
        onClick = function()
            if ns.SettingsTab and ns.SettingsTab.Open then
                ns.SettingsTab:Open(currentGroup)
            else
                ns.Print("The contents editor arrives in a later phase. For now use /cdmc add, /cdmc remove and /cdmc list.")
            end
        end,
    })
    w.list = {
        w.enabled, w.width, w.height, w.square, w.zoom, w.spacing, w.perLine, w.orientation, w.grow, w.wrap,
        w.scale, w.alpha, w.visibility, w.attach, w.showGCD, w.showTimer, w.showTooltips, w.resetPos, w.contents,
    }
    W.Stack(content, w.list)
    return w
end

function Panel:ShowForGroup(key, container)
    if InCombatLockdown() then
        self:Hide()
        return
    end
    EnsurePanel()
    mode, currentGroup = "group", key
    groupWidgets = groupWidgets or BuildGroupWidgets()
    titleText:SetText("CDM Customizer \226\128\148 " .. ns.GROUP_LABELS[key])
    ShowContent(groupContent)
    FitHeight(groupContent:GetHeight())
    self:Refresh()

    anchorTarget = container
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    Place(container)
    panel:Show()
end

local function OnAttach(_, systemFrame)
    ns.EditModeOverlay:Deselect()
    local name = systemFrame and systemFrame.GetName and systemFrame:GetName()
    local key = name and viewerByFrame[name]
    if key then
        Panel:ShowForViewer(key)
    elseif mode == "viewer" then
        Panel:Hide()
    end
end

local initialized = false
local function Init()
    local dialog = _G.EditModeSystemSettingsDialog
    if initialized or not dialog then
        return
    end
    initialized = true
    if dialog.AttachToSystemFrame then
        hooksecurefunc(dialog, "AttachToSystemFrame", ns.Safe(OnAttach))
    end
    dialog:HookScript("OnHide", ns.Safe(function()
        if mode == "viewer" then
            Panel:Hide()
        end
    end))
end

if C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
    Init()
else
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", Init)
end

ns.Subscribe("COMBAT_START", function()
    Panel:Hide()
end)
