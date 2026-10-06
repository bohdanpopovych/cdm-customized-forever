local ADDON_NAME, ns = ...

local DB = ns.DB
local Compat = ns.Compat
local Crop = ns.Crop
local Entries = ns.Entries
local IconFrame = ns.IconFrame
local GridLayout = ns.GridLayout

local NV = {}
ns.NativeViewers = NV

local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local MAX_ERRORS = 3

local state = {}
for _, key in ipairs(ns.VIEWER_KEYS) do
    state[key] = { icons = {}, touched = setmetatable({}, { __mode = "k" }) }
end
local childState = setmetatable({}, { __mode = "k" })

local errorCount = 0
NV.disabled = false

local function RunNextFrame_(fn)
    if RunNextFrame then
        RunNextFrame(fn)
    else
        C_Timer.After(0, fn)
    end
end

local function GetViewer(key)
    return _G[ns.VIEWERS[key].frame]
end

local function IsReady(viewer)
    if not viewer or not viewer.IsInitialized or not viewer:IsInitialized() then
        return false
    end
    if EditModeManagerFrame and EditModeManagerFrame.layoutApplyInProgress then
        return false
    end
    return true
end

function NV:IsManaged(key)
    if NV.disabled then
        return false
    end
    local cfg = DB:Viewer(key)
    if cfg.enabled then
        return true
    end
    local list = DB:Entries(key)
    return list ~= nil and #list > 0
end

local function FindOverlay(child)
    local cs = childState[child]
    if not cs then
        cs = {}
        childState[child] = cs
    end
    if cs.overlayChecked then
        return cs.overlay, cs
    end
    cs.overlayChecked = true
    for _, region in ipairs({ child:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region:GetAtlas()
            if atlas and not Compat.IsSecret(atlas) and atlas == OVERLAY_ATLAS then
                cs.overlay = region
                cs.orig = {}
                for i = 1, region:GetNumPoints() do
                    cs.orig[i] = { region:GetPoint(i) }
                end
                break
            end
        end
    end
    return cs.overlay, cs
end

local function StyleNativeChild(key, child, w, h, zoom)
    child:SetSize(w, h)
    child.Icon:SetTexCoord(Crop.TexCoords(w, h, zoom))
    local overlay = FindOverlay(child)
    if overlay then
        local tlx, tly, brx, bry = Crop.OverlayInsets(key, w, h)
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", child.Icon, "TOPLEFT", tlx, tly)
        overlay:SetPoint("BOTTOMRIGHT", child.Icon, "BOTTOMRIGHT", brx, bry)
    end
    state[key].touched[child] = true
end

local function RestoreNativeChild(key, child)
    local base = ns.VIEWERS[key]
    child:SetSize(base.w, base.h)
    if child.Icon then
        child.Icon:SetTexCoord(0, 1, 0, 1)
    end
    local cs = childState[child]
    if cs and cs.overlay and cs.orig then
        cs.overlay:ClearAllPoints()
        for _, p in ipairs(cs.orig) do
            cs.overlay:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
    end
end

local function CollectNative(viewer)
    local natives = {}
    for _, child in ipairs({ viewer:GetChildren() }) do
        local index = child.layoutIndex
        if index ~= nil and not Compat.IsSecret(index) and child.Icon and child:IsShown() then
            natives[#natives + 1] = child
        end
    end
    table.sort(natives, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)
    return natives
end

local function EnsureHost(key)
    local st = state[key]
    if st.host then
        return st.host
    end
    local viewer = GetViewer(key)
    if not viewer then
        return nil
    end
    local host = CreateFrame("Frame", "CDMC_" .. key .. "Host", UIParent)
    host:SetAllPoints(viewer)
    host:SetFrameStrata(viewer:GetFrameStrata())
    host:SetFrameLevel(viewer:GetFrameLevel() + 1)
    host:EnableMouse(false)
    st.host = host
    return host
end

local function SyncHost(key)
    local st, viewer = state[key], GetViewer(key)
    if st.host and viewer then
        st.host:SetShown(viewer:IsShown())
        st.host:SetAlpha(viewer:GetAlpha())
    end
end

local function ReadLayout(viewer)
    local function Read(v, default)
        if v == nil then
            return default
        end
        if Compat.IsSecret(v) then
            return nil
        end
        return v
    end
    local isH = Read(viewer.isHorizontal, true)
    local limit = Read(viewer.iconLimit, 8)
    local scale = Read(viewer.iconScale, 1)
    local right = Read(viewer.layoutFramesGoingRight, true)
    local up = Read(viewer.layoutFramesGoingUp, false)
    local direction = Read(viewer.iconDirection, 1)
    local padX = Read(viewer.childXPadding, 2)
    local padY = Read(viewer.childYPadding, 2)
    if isH == nil or not limit or not scale or right == nil or up == nil or not direction or not padX or not padY then
        return nil
    end
    local horizontal = isH ~= false
    return {
        horizontal = horizontal,
        limit = limit > 0 and limit or 8,
        scale = scale > 0 and scale or 1,
        right = right ~= false,
        up = up == true,
        reverse = direction ~= 1,
        pad = (horizontal and padX or padY),
        timerShown = viewer.timerShown ~= false,
        tooltipsShown = viewer.tooltipsShown ~= false,
    }
end

local function ReleaseInjected(key)
    local st = state[key]
    for entryKey, frame in pairs(st.icons) do
        IconFrame.Release(frame)
        st.icons[entryKey] = nil
    end
end

local function Restore(key)
    local st = state[key]
    st.wasManaged = false
    for child in pairs(st.touched) do
        pcall(RestoreNativeChild, key, child)
        st.touched[child] = nil
    end
    ReleaseInjected(key)
end

local function Apply(key)
    local st, viewer = state[key], GetViewer(key)
    if not viewer or not IsReady(viewer) then
        return
    end
    if not NV:IsManaged(key) then
        if st.wasManaged then
            Restore(key)
        end
        return
    end
    if st.applying then
        return
    end
    st.applying = true
    st.wasManaged = true

    local layout = ReadLayout(viewer)
    if not layout then
        st.applying = false
        return
    end

    local cfg = DB:Viewer(key)
    local w, h, custom = DB:GetViewerSize(key)
    local zoom = cfg.zoom or 0
    local base = ns.VIEWERS[key]

    local natives = CollectNative(viewer)
    if custom then
        for _, child in ipairs(natives) do
            StyleNativeChild(key, child, w, h, zoom)
        end
    else
        w, h = base.w, base.h

        for child in pairs(st.touched) do
            pcall(RestoreNativeChild, key, child)
            st.touched[child] = nil
        end
    end

    local custom_icons = {}
    local list = DB:Entries(key)
    if list then
        local host = EnsureHost(key)
        SyncHost(key)
        local wanted = {}
        for _, entry in ipairs(list) do
            if Entries:IsAvailable(entry) then
                wanted[Entries:Key(entry)] = entry
            end
        end
        for entryKey, frame in pairs(st.icons) do
            if not wanted[entryKey] then
                IconFrame.Release(frame)
                st.icons[entryKey] = nil
            end
        end
        local opts = { showGCD = cfg.showGCD, showTimer = layout.timerShown, showTooltips = layout.tooltipsShown }
        for _, entry in ipairs(list) do
            local entryKey = Entries:Key(entry)
            if wanted[entryKey] and host then
                local frame = st.icons[entryKey]
                if not frame then
                    frame = IconFrame.Acquire(host)
                    st.icons[entryKey] = frame
                end
                frame:ApplySize(w, h, zoom, key)
                frame:SetScale(layout.scale)
                frame:SetEntry(entry, opts)
                custom_icons[#custom_icons + 1] = frame
            end
        end
    end

    local ordered = {}
    local first, second = natives, custom_icons
    if cfg.placement == "before" then
        first, second = custom_icons, natives
    end
    for _, f in ipairs(first) do ordered[#ordered + 1] = f end
    for _, f in ipairs(second) do ordered[#ordered + 1] = f end

    local primary, secondary
    if layout.horizontal then
        primary = (layout.right ~= layout.reverse) and "RIGHT" or "LEFT"
        secondary = layout.up and "UP" or "DOWN"
    else
        primary = (layout.up ~= layout.reverse) and "UP" or "DOWN"
        secondary = layout.right and "RIGHT" or "LEFT"
    end

    local totalW, totalH = GridLayout.Apply(ordered, {
        w = w,
        h = h,
        spacing = layout.pad / layout.scale,
        perLine = layout.limit,
        orientation = layout.horizontal and "HORIZONTAL" or "VERTICAL",
        primary = primary,
        secondary = secondary,
        anchorFrame = viewer,
    })

    if totalW > 0 and totalH > 0 then
        local targetW, targetH = totalW * layout.scale, totalH * layout.scale
        ns.RunOutOfCombat("resize-" .. key, function()
            if C_RestrictedActions and C_RestrictedActions.CheckAllowProtectedFunctions
                and not C_RestrictedActions.CheckAllowProtectedFunctions(viewer, true) then
                return
            end
            local cw, ch = viewer:GetWidth(), viewer:GetHeight()
            if Compat.IsSecret(cw) or Compat.IsSecret(ch) then
                return
            end
            if math.abs(cw - targetW) > 0.5 or math.abs(ch - targetH) > 0.5 then
                viewer:SetSize(targetW, targetH)
            end
        end)
    end
    st.applying = false
end

local function SafeApply(key)
    local ok, err = pcall(Apply, key)
    state[key].applying = false
    if ok then
        return
    end
    errorCount = errorCount + 1
    if errorCount == 1 then
        ns.Print("Native viewer error: %s", tostring(err))
    end
    if errorCount >= MAX_ERRORS and not NV.disabled then
        NV.disabled = true
        ns.Print("Too many errors while adjusting the native bars; disabled for this session. /reload to retry.")
        for _, k in ipairs(ns.VIEWER_KEYS) do
            pcall(Restore, k)
        end
    end
end

function NV:Request(key)
    local st = state[key]
    if not st then
        return
    end
    if st.refreshedThisFrame then
        st.deferred = true
        return
    end
    st.refreshedThisFrame = true
    SafeApply(key)
    RunNextFrame_(function()
        st.refreshedThisFrame = false
        if st.deferred then
            st.deferred = false
            NV:Request(key)
        end
    end)
end

function NV:RequestAll()
    for _, key in ipairs(ns.VIEWER_KEYS) do
        self:Request(key)
    end
end

local function InstallHooks(key)
    local st, viewer = state[key], GetViewer(key)
    if st.hooked or not viewer then
        return
    end
    st.hooked = true
    local request = ns.Safe(function() NV:Request(key) end)
    local sync = ns.Safe(function() SyncHost(key) end)
    hooksecurefunc(viewer, "Layout", request)
    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", request)
    end
    viewer:HookScript("OnShow", sync)
    viewer:HookScript("OnHide", sync)
    hooksecurefunc(viewer, "SetAlpha", sync)
    if viewer.SetTooltipsShown then
        hooksecurefunc(viewer, "SetTooltipsShown", request)
    end
end

local function InstallAll()
    if not DB:Profile() then
        return
    end
    for _, key in ipairs(ns.VIEWER_KEYS) do
        InstallHooks(key)
    end
end

ns.Subscribe("PROFILE_READY", function()
    InstallAll()
    NV:RequestAll()
end)
ns.Subscribe("VIEWER_SIZE_CHANGED", function(key)
    NV:Request(key)
end)
ns.Subscribe("ENTRIES_CHANGED", function(key)
    if state[key] then
        NV:Request(key)
    end
end)
ns.Subscribe("AVAILABILITY_CHANGED", function()
    NV:Request("Essential")
    NV:Request("Utility")
end)
for _, msg in ipairs({ "EDITMODE_ENTER", "EDITMODE_EXIT", "COMBAT_END" }) do
    ns.Subscribe(msg, function()
        NV:RequestAll()
    end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
    InstallAll()
    NV:RequestAll()
    C_Timer.After(1, function()
        InstallAll()
        NV:RequestAll()
    end)
end)

if EventRegistry then
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", ns.Safe(function()
        ns.Debounce("nv-data-changed", function()
            NV:RequestAll()
        end)
    end))
end
