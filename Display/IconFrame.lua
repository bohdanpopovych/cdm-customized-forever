local ADDON_NAME, ns = ...

local Compat = ns.Compat
local Crop = ns.Crop
local Entries = ns.Entries

local IconFrame = {}
ns.IconFrame = IconFrame

local MASK_ATLAS = "UI-HUD-CoolDownManager-Mask"
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local OOR_ATLAS = "UI-CooldownManager-OORshadow"
local SWIPE_TEXTURE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

local pool = {}
local Mixin_ = {}

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function Mixin_:RefreshTexture()
    if not self.entry then
        return
    end
    local _, texture = Entries:GetDisplay(self.entry)
    self.Icon:SetTexture(texture)
end

function Mixin_:ApplySize(w, h, zoom, viewerKey)
    zoom = zoom or 0
    viewerKey = viewerKey or "Essential"
    if self.sizeW == w and self.sizeH == h and self.sizeZoom == zoom and self.sizeViewer == viewerKey then
        return
    end
    self.sizeW, self.sizeH, self.sizeZoom, self.sizeViewer = w, h, zoom, viewerKey

    self:SetSize(w, h)
    self.Icon:SetTexCoord(Crop.TexCoords(w, h, zoom))

    local tlx, tly, brx, bry = Crop.OverlayInsets(viewerKey, w, h)
    self.Overlay:ClearAllPoints()
    self.Overlay:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", tlx, tly)
    self.Overlay:SetPoint("BOTTOMRIGHT", self.Icon, "BOTTOMRIGHT", brx, bry)
end

function Mixin_:SetEntry(entry, opts)
    self.entry = entry
    self.opts = opts or {}
    self:SetMouseMotionEnabled(self.opts.showTooltips ~= false)
    self:RefreshTexture()
    ns.CooldownUpdater:Register(self)
    ns.CooldownUpdater:UpdateIcon(self)
end

local function OnEnter(self)
    local entry = self.entry
    if not entry then
        return
    end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    if entry.kind == "spell" then
        GameTooltip:SetSpellByID(entry.id)
    else
        GameTooltip:SetItemByID(entry.id)
    end
    GameTooltip:Show()
end

local function OnLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetMouseClickEnabled(false)
    Mixin(f, Mixin_)

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints(f)
    if HasAtlas(MASK_ATLAS) then
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.Icon)
        mask:SetAtlas(MASK_ATLAS)
        f.Icon:AddMaskTexture(mask)
        f.mask = mask
    end

    f.Overlay = f:CreateTexture(nil, "OVERLAY", nil, 1)
    if HasAtlas(OVERLAY_ATLAS) then
        f.Overlay:SetAtlas(OVERLAY_ATLAS)
    else
        f.Overlay:Hide()
    end

    f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.Cooldown:SetAllPoints(f)
    f.Cooldown:SetDrawEdge(false)
    f.Cooldown:SetDrawBling(false)
    f.Cooldown:SetSwipeTexture(SWIPE_TEXTURE)
    if f.Cooldown.SetCountdownFont then
        pcall(f.Cooldown.SetCountdownFont, f.Cooldown, "GameFontHighlightHugeOutline")
    end
    f.Cooldown:HookScript("OnCooldownDone", function()

        ns.Debounce("cd-done", function()
            ns.CooldownUpdater:UpdateAll()
        end)
    end)

    f.TextHolder = CreateFrame("Frame", nil, f)
    f.TextHolder:SetAllPoints(f)
    f.TextHolder:SetFrameLevel(f.Cooldown:GetFrameLevel() + 5)
    f.Count = f.TextHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.Count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

    f.OutOfRange = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.OutOfRange:SetAllPoints(f)
    if HasAtlas(OOR_ATLAS) then
        f.OutOfRange:SetAtlas(OOR_ATLAS)
    end
    f.OutOfRange:SetAlpha(0.5)
    f.OutOfRange:Hide()

    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", OnLeave)
    return f
end

function IconFrame.Acquire(parent)
    local f = table.remove(pool)
    if f then
        f:SetParent(parent)
    else
        f = Create(parent)
    end
    f:Show()
    return f
end

function IconFrame.Release(f)
    ns.CooldownUpdater:Unregister(f)
    OnLeave(f)
    f.entry, f.opts = nil, nil
    f.sizeW, f.sizeH, f.sizeZoom, f.sizeViewer = nil, nil, nil, nil
    f:Hide()
    f:ClearAllPoints()
    f.Cooldown:Clear()
    f.Count:SetText("")
    f.Icon:SetDesaturation(0)
    f.Icon:SetVertexColor(1, 1, 1)
    f.Icon:SetAlpha(1)
    f.OutOfRange:Hide()
    f:SetParent(UIParent)
    pool[#pool + 1] = f
end
