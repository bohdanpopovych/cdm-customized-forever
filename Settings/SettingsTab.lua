local ADDON_NAME, ns = ...

local DB = ns.DB
local Compat = ns.Compat
local Entries = ns.Entries

local ST = {}
ns.SettingsTab = ST

local SECTION_ORDER = { "Essential", "Utility", "Left", "Right" }
local HEADER_HEIGHT = 94
local ROW_HEIGHT = 30
local TAB_ATLASES = { "unitframeicon-chromietime", "communities-icon-addgroupplus", "Garr_Building-AddFollowerPlus" }

local built = false
local active, wasActive = false, false
local panel, tab, scroll, scrollChild
local sections = {}
local focusedBox

local function MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    return b
end

local function ShowError(key, text)
    local s = sections[key]
    if s then
        s.error:SetText(text or "")
    end
end

local function SubmitAdd(key)
    local s = sections[key]
    local kind, id = Entries:Parse(s.addBox:GetText())
    if not kind then
        ShowError(key, id or "Couldn't parse.")
        return
    end
    local ok, err = DB:AddEntry(key, kind, id)
    if not ok then
        ShowError(key, err or "Couldn't add.")
        return
    end
    ShowError(key, "")
    s.addBox:SetText("")
    s.addBox:ClearFocus()
end

local function DropOnSection(key)
    if InCombatLockdown() then
        return
    end
    local kind, id = Compat.GetCursorEntry()
    if not kind then
        return
    end
    if kind == "spell" and C_Spell.GetBaseSpell then
        id = C_Spell.GetBaseSpell(id) or id
    end
    local ok, err = DB:AddEntry(key, kind, id)
    if ok then
        ShowError(key, "")
        ClearCursor()
    else
        ShowError(key, err or "Couldn't add.")
    end
end

local function MakeRow(s, index)
    local key = s.key
    local row = CreateFrame("Frame", nil, s.frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", s.frame, "TOPLEFT", 0, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
    row:SetPoint("RIGHT", s.frame, "RIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 2, 0)

    row.remove = MakeButton(row, "x", 22, 22)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.down = MakeButton(row, "v", 22, 22)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.up = MakeButton(row, "^", 22, 22)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.move = MakeButton(row, "Move", 44, 22)
    row.move:SetPoint("RIGHT", row.up, "LEFT", -2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 6)
    row.name:SetPoint("RIGHT", row.move, "LEFT", -4, 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("LEFT", row.icon, "RIGHT", 6, -7)
    row.status:SetPoint("RIGHT", row.move, "LEFT", -4, -7)
    row.status:SetJustifyH("LEFT")
    row.status:SetWordWrap(false)

    row.remove:SetScript("OnClick", function() DB:RemoveEntry(key, row.index) end)
    row.up:SetScript("OnClick", function() DB:MoveEntry(key, row.index, row.index - 1) end)
    row.down:SetScript("OnClick", function() DB:MoveEntry(key, row.index, row.index + 1) end)
    if MenuUtil and MenuUtil.CreateContextMenu then
        row.move:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, other in ipairs(SECTION_ORDER) do
                    if other ~= key then
                        root:CreateButton(ns.GROUP_LABELS[other], function()
                            DB:TransferEntry(key, row.index, other)
                        end)
                    end
                end
            end)
        end)
    else
        row.move:Hide()
    end

    s.rows[index] = row
    return row
end

local function RefreshSection(s)
    local list = DB:Entries(s.key)
    s.count:SetText("(" .. #list .. ")")
    if s.option then
        s.option:Refresh()
    end

    for i, entry in ipairs(list) do
        local row = s.rows[i] or MakeRow(s, i)
        row.index = i
        local name, texture = Entries:GetDisplay(entry)
        local available, missing = Entries:IsAvailable(entry)
        row.icon:SetTexture(texture)
        row.icon:SetDesaturated(not available or missing)
        row.name:SetText(name)
        local status = entry.kind .. ":" .. entry.id
        if entry.kind == "spell" and not available then
            status = status .. "  |cffff8080Not known|r"
        elseif entry.kind == "item" and missing then
            status = status .. (available and "  |cffff8080None in bags|r" or "  |cffff8080None in bags (hidden)|r")
        end
        row.status:SetText(status)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row:Show()
    end
    for i = #list + 1, #s.rows do
        s.rows[i]:Hide()
    end
    s.empty:SetShown(#list == 0)
    return HEADER_HEIGHT + math.max(#list, 1) * ROW_HEIGHT + 8
end

function ST:Refresh()
    if not built then
        return
    end
    local y = 0
    for _, key in ipairs(SECTION_ORDER) do
        local s = sections[key]
        local height = RefreshSection(s)
        s.frame:ClearAllPoints()
        s.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        s.frame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        s.frame:SetHeight(height)
        s.y = y
        y = y + height + 14
    end
    scrollChild:SetHeight(y)
end

local function RequestRefresh()
    if built and panel:IsShown() then
        ns.Debounce("settings-refresh", function()
            ST:Refresh()
        end)
    end
end

local function BuildSection(key)
    local W = ns.Widgets
    local s = { key = key, rows = {} }

    local f = CreateFrame("Frame", nil, scrollChild)
    f:EnableMouse(true)
    f:SetScript("OnReceiveDrag", function() DropOnSection(key) end)
    f:SetScript("OnMouseUp", function()
        if GetCursorInfo() then
            DropOnSection(key)
        end
    end)
    s.frame = f

    s.highlight = f:CreateTexture(nil, "BACKGROUND")
    s.highlight:SetAllPoints()
    s.highlight:SetColorTexture(0.2, 0.8, 0.3, 0.15)
    s.highlight:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(ns.GROUP_LABELS[key])
    s.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.count:SetPoint("LEFT", title, "RIGHT", 6, 0)

    s.addBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    s.addBox:SetSize(150, 22)
    s.addBox:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -22)
    s.addBox:SetAutoFocus(false)
    s.hint = s.addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.hint:SetPoint("LEFT", 2, 0)
    s.hint:SetText("ID, name or drop here")
    local function UpdateHint()
        s.hint:SetShown(s.addBox:GetText() == "" and not s.addBox:HasFocus())
    end
    s.addBox:SetScript("OnEnterPressed", function() SubmitAdd(key) end)
    s.addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s.addBox:SetScript("OnTextChanged", UpdateHint)
    s.addBox:SetScript("OnEditFocusGained", function(self)
        focusedBox = self
        UpdateHint()
    end)
    s.addBox:SetScript("OnEditFocusLost", function()
        focusedBox = nil
        UpdateHint()
    end)

    s.browse = MakeButton(f, "Browse...", 80, 22)
    s.browse:SetPoint("LEFT", s.addBox, "RIGHT", 6, 0)
    s.browse:SetScript("OnClick", function()
        ns.EntryPicker:Open(key)
    end)

    if key == "Essential" or key == "Utility" then
        s.option = W.Dropdown(f, {
            label = "Place",
            options = {
                { value = "after", text = "After native icons" },
                { value = "before", text = "Before native icons" },
            },
            get = function() return DB:Viewer(key).placement end,
            set = function(v)
                DB:SetViewerOption(key, "placement", v)
                s.option:Refresh()
            end,
        })
    else
        s.option = W.Checkbox(f, {
            label = "Enabled",
            get = function() return DB:Group(key).enabled end,
            set = function(v) DB:SetGroupOption(key, "enabled", v) end,
        })
    end
    s.option:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -48)

    s.error = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.error:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -78)
    s.error:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    s.error:SetJustifyH("LEFT")
    s.error:SetTextColor(1, 0.3, 0.3)

    s.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(HEADER_HEIGHT + 6))
    s.empty:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    s.empty:SetJustifyH("LEFT")
    s.empty:SetText("Drag a spell from your spellbook or an item from your bags here.")

    UpdateHint()
    sections[key] = s
end

local function NativeContent(show)
    local settings = _G.CooldownViewerSettings
    if settings and settings.CooldownScroll then
        pcall(settings.CooldownScroll.SetShown, settings.CooldownScroll, show)
    end
end

local function CheckNativeTabs(mode)
    local settings = _G.CooldownViewerSettings
    if not settings then
        return
    end
    if settings.SpellsTab then settings.SpellsTab:SetChecked(mode == "spells") end
    if settings.AurasTab then settings.AurasTab:SetChecked(mode == "auras") end
    if settings.GroupBuffsTab then settings.GroupBuffsTab:SetChecked(mode == "groupBuffs") end
end

local function SyncPortrait()
    local settings = _G.CooldownViewerSettings
    local dst = panel.PortraitContainer and panel.PortraitContainer.portrait
    if not dst then
        return
    end
    local src = settings and settings.PortraitContainer and settings.PortraitContainer.portrait
    if src then
        local atlas = src:GetAtlas()
        if atlas then
            dst:SetAtlas(atlas)
            return
        end
        local texture = src:GetTexture()
        if texture then
            dst:SetTexture(texture)
            dst:SetTexCoord(src:GetTexCoord())
            return
        end
    end
    local _, classFile = UnitClass("player")
    local atlas = classFile and ("classicon-" .. classFile:lower())
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        dst:SetAtlas(atlas)
    end
end

local function Activate()
    local settings = _G.CooldownViewerSettings
    if InCombatLockdown() or not built or not settings or not settings:IsShown() then
        return
    end
    CheckNativeTabs(nil)
    tab:SetChecked(true)
    panel:Show()
    settings:SetToplevel(false)
    NativeContent(false)
    SyncPortrait()
    active, wasActive = true, true
    ST:Refresh()
end

local function Deactivate()
    if not built then
        return
    end
    active, wasActive = false, false
    panel:Hide()
    tab:SetChecked(false)
    NativeContent(true)
    local settings = _G.CooldownViewerSettings
    CheckNativeTabs(settings and settings.displayMode)
end

local function ChooseTabAtlas()
    for _, atlas in ipairs(TAB_ATLASES) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            return atlas
        end
    end
    return TAB_ATLASES[1]
end

function ST:Build()
    local settings = _G.CooldownViewerSettings
    if built or InCombatLockdown() or not settings or not settings.AurasTab or not settings.CooldownScroll then
        return
    end
    built = true

    panel = CreateFrame("Frame", "CDMC_SettingsPanel", UIParent, "ButtonFrameTemplate")
    panel:SetAllPoints(settings)
    panel:SetFrameStrata("HIGH")
    panel:SetFrameLevel(settings:GetFrameLevel() + 10)
    panel:Hide()
    if panel.Inset and panel.Inset.Bg then
        panel.Inset.Bg:SetAtlas("character-panel-background", true)
        panel.Inset.Bg:SetHorizTile(false)
        panel.Inset.Bg:SetVertTile(false)
    end
    if panel.TitleContainer and panel.TitleContainer.TitleText then
        panel.TitleContainer.TitleText:SetText("CDM Customizer")
    elseif panel.SetTitle then
        panel:SetTitle("CDM Customizer")
    end

    if panel.CloseButton then
        panel.CloseButton:SetScript("OnClick", function()
            if HideUIPanel then
                HideUIPanel(settings)
            else
                settings:Hide()
            end
        end)
        panel.CloseButton:Show()
    end

    scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 17, -72)
    scroll:SetPoint("BOTTOMRIGHT", -30, 29)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(300, 1)
    scroll:SetScrollChild(scrollChild)
    if scroll.ScrollBar then
        scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
        scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    end
    scroll:SetScript("OnSizeChanged", function(self)
        scrollChild:SetWidth(self:GetWidth())
        RequestRefresh()
    end)

    for _, key in ipairs(SECTION_ORDER) do
        BuildSection(key)
    end

    local editMode = MakeButton(panel, "Open Edit Mode", 120, 22)
    editMode:SetPoint("TOP", panel, "TOP", 0, -40)
    editMode:SetScript("OnClick", function()
        if not InCombatLockdown() and EditModeManagerFrame then
            ShowUIPanel(EditModeManagerFrame)
        end
    end)

    local tip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip:SetPoint("BOTTOMLEFT", 10, 10)
    tip:SetText("Changes apply instantly. Size and position are set in Edit Mode.")

    panel:SetScript("OnEvent", function()
        local carrying = Compat.GetCursorEntry() ~= nil
        for _, s in pairs(sections) do
            s.highlight:SetShown(carrying)
        end
    end)
    panel:SetScript("OnShow", function(self)
        self:RegisterEvent("CURSOR_CHANGED")
        scrollChild:SetWidth(scroll:GetWidth())
        ST:Refresh()
    end)
    panel:SetScript("OnHide", function(self)
        self:UnregisterEvent("CURSOR_CHANGED")
        for _, s in pairs(sections) do
            s.highlight:Hide()
        end
    end)

    tab = CreateFrame("Button", "CDMC_SettingsTab", UIParent, "CooldownViewerSettingsTabTemplate")
    tab:SetFrameStrata("HIGH")
    tab.tooltipText = "CDM Customizer"
    local atlas = ChooseTabAtlas()
    tab.activeAtlas, tab.inactiveAtlas = atlas, atlas
    tab:SetChecked(false)
    tab:SetPoint("TOP", settings.GroupBuffsTab or settings.AurasTab, "BOTTOM", 0, -3)
    tab:SetScript("OnClick", function()
        Activate()
    end)

    tab:SetShown(settings:IsShown() and not InCombatLockdown())

    if settings.SetDisplayMode then
        hooksecurefunc(settings, "SetDisplayMode", ns.Safe(function()
            if active then
                Deactivate()
            end
        end))
    end
    settings:HookScript("OnShow", ns.Safe(function()
        tab:SetShown(not InCombatLockdown())
        if wasActive and not InCombatLockdown() then
            Activate()
        end
    end))
    settings:HookScript("OnHide", ns.Safe(function()

        panel:Hide()
        tab:Hide()
        active = false
        NativeContent(true)
    end))
end

function ST:Open(groupKey)
    if InCombatLockdown() then
        ns.Print("Settings can't be opened in combat.")
        return
    end
    if not _G.CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    end
    local settings = _G.CooldownViewerSettings
    if not settings then
        ns.Print("The Cooldown Manager settings window isn't available.")
        return
    end
    if not settings:IsShown() then
        settings:ShowUIPanel(false)
    end
    self:Build()
    if not built then
        ns.Print("Couldn't build the settings tab.")
        return
    end
    tab:Show()
    Activate()
    if groupKey and sections[groupKey] then
        C_Timer.After(0, function()
            local range = scroll:GetVerticalScrollRange() or 0
            scroll:SetVerticalScroll(math.min(sections[groupKey].y or 0, range))
        end)
    end
end

if EventRegistry then
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", ns.Safe(function()
        ST:Build()
    end))
end

ns.Subscribe("PROFILE_READY", function()
    ST:Build()
end)
ns.Subscribe("ENTRIES_CHANGED", RequestRefresh)
ns.Subscribe("AVAILABILITY_CHANGED", RequestRefresh)
ns.Subscribe("GROUP_LAYOUT_CHANGED", RequestRefresh)

ns.Subscribe("COMBAT_START", function()
    if not built then
        return
    end
    tab:Hide()
    panel:Hide()
    NativeContent(true)
    active = false
end)
ns.Subscribe("COMBAT_END", function()
    if not built then
        return
    end
    local settings = _G.CooldownViewerSettings
    if settings and settings:IsShown() then
        tab:Show()
        if wasActive then
            Activate()
        end
    end
end)

local function InsertLink(text)
    if focusedBox and focusedBox:HasFocus() and type(text) == "string" then
        focusedBox:Insert(text)
    end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", ns.Safe(InsertLink))
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", ns.Safe(InsertLink))
end
