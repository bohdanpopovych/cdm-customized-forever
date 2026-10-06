local ADDON_NAME, ns = ...

local DB = ns.DB
local Compat = ns.Compat

local Picker = {}
ns.EntryPicker = Picker

local ROW_HEIGHT = 26

local frame, searchBox, scrollBox, statusText, spellButton, itemButton
local mode, targetGroup, searchText = "spell", "Essential", ""

local function BuildSpellbook()
    local out, seen = {}, {}
    local bank = Enum.SpellBookSpellBank.Player
    local spellType, flyoutType = Enum.SpellBookItemType.Spell, Enum.SpellBookItemType.Flyout

    local function AddSpell(list, spellID, isPassive)
        if not spellID or seen[spellID] then
            return
        end
        local name = Compat.GetSpellName(spellID)
        if not name or isPassive or Compat.IsSpellPassive(spellID) then
            return
        end
        seen[spellID] = true
        local extra
        local baseCooldown = GetSpellBaseCooldown and GetSpellBaseCooldown(spellID)
        if baseCooldown == 0 and not C_Spell.GetSpellCharges(spellID) then
            extra = "(no cooldown)"
        end
        list[#list + 1] = {
            kind = "spell", id = spellID, name = name,
            texture = Compat.GetSpellTexture(spellID) or Compat.FALLBACK_ICON, extra = extra,
        }
    end

    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide then
            local items = {}
            local offset = info.itemIndexOffset or 0
            for index = offset + 1, offset + (info.numSpellBookItems or 0) do
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                local offSpec = C_SpellBook.IsSpellBookItemOffSpec and C_SpellBook.IsSpellBookItemOffSpec(index, bank)
                if item and not offSpec then
                    if item.itemType == spellType then
                        AddSpell(items, item.actionID or item.spellID, item.isPassive)
                    elseif item.itemType == flyoutType and item.actionID then
                        local _, _, numSlots = GetFlyoutInfo(item.actionID)
                        for slot = 1, numSlots or 0 do
                            local flyoutSpell, overrideSpell, isKnown = GetFlyoutSlotInfo(item.actionID, slot)
                            if isKnown then
                                AddSpell(items, flyoutSpell or overrideSpell)
                            end
                        end
                    end
                end
            end
            if #items > 0 then
                out[#out + 1] = { header = info.name }
                for _, entry in ipairs(items) do
                    out[#out + 1] = entry
                end
            end
        end
    end

    local numPet = C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() or 0
    if numPet and numPet > 0 then
        local petBank = Enum.SpellBookSpellBank.Pet
        local items = {}
        for index = 1, numPet do
            local item = C_SpellBook.GetSpellBookItemInfo(index, petBank)
            if item and item.spellID then

                AddSpell(items, item.itemType == spellType and item.actionID or item.spellID, item.isPassive)
            end
        end
        if #items > 0 then
            out[#out + 1] = { header = "Pet" }
            for _, entry in ipairs(items) do
                out[#out + 1] = entry
            end
        end
    end
    return out
end

local function BuildInventory()
    local seen = {}
    local function Consider(list, id, showCount)
        if not id or seen[id] then
            return
        end
        if not C_Item.IsItemDataCachedByID(id) then
            Compat.RequestItem(id)
        end
        local isConsumable = select(6, C_Item.GetItemInfoInstant(id)) == Enum.ItemClass.Consumable
        if not (Compat.GetItemSpell(id) or isConsumable) then
            return
        end
        seen[id] = true
        local count = Compat.GetItemCount(id)
        list[#list + 1] = {
            kind = "item", id = id,
            name = Compat.GetItemName(id) or ("item:" .. id),
            texture = Compat.GetItemIcon(id) or select(5, C_Item.GetItemInfoInstant(id)) or Compat.FALLBACK_ICON,
            extra = (showCount and count > 1) and ("x" .. count) or nil,
        }
    end
    local function ByName(a, b)
        return a.name:lower() < b.name:lower()
    end

    local equipped, bags = {}, {}
    for slot = 1, 19 do
        Consider(equipped, GetInventoryItemID("player", slot), false)
    end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            Consider(bags, C_Container.GetContainerItemID(bag, slot), true)
        end
    end
    table.sort(equipped, ByName)
    table.sort(bags, ByName)

    local out = {}
    if #equipped > 0 then
        out[#out + 1] = { header = "Equipped" }
        for _, e in ipairs(equipped) do out[#out + 1] = e end
    end
    if #bags > 0 then
        out[#out + 1] = { header = "Bags" }
        for _, e in ipairs(bags) do out[#out + 1] = e end
    end
    return out
end

local function Filter(list, text)
    if text == "" then
        return list
    end
    local out, header = {}, nil
    for _, entry in ipairs(list) do
        if entry.header then
            header = entry
        elseif entry.name:lower():find(text, 1, true) or tostring(entry.id) == text then
            if header then
                out[#out + 1] = header
                header = nil
            end
            out[#out + 1] = entry
        end
    end
    return out
end

local function TagFor(data)
    local group = DB:FindEntry(data.kind, data.id)
    if group then
        return "(in " .. ns.GROUP_LABELS[group] .. ")"
    end
    return data.extra or ""
end

local function InitRow(button, data)
    if not button.built then
        button.built = true
        button:SetHeight(ROW_HEIGHT)
        button.flash = button:CreateTexture(nil, "BACKGROUND")
        button.flash:SetAllPoints()
        button.flash:SetColorTexture(0.2, 0.9, 0.3, 1)
        button.flash:SetAlpha(0)
        button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
        button.highlight:SetAllPoints()
        button.highlight:SetColorTexture(1, 1, 1, 0.1)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(22, 22)
        button.icon:SetPoint("LEFT", 2, 0)
        button.tag = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.tag:SetPoint("RIGHT", -4, 0)
        button.tag:SetJustifyH("RIGHT")
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.text:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
        button.text:SetPoint("RIGHT", button.tag, "LEFT", -6, 0)
        button.text:SetJustifyH("LEFT")
        button.text:SetWordWrap(false)
        button.header = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.header:SetPoint("LEFT", 4, 0)
        button:SetScript("OnClick", function(self)
            Picker:OnPick(self)
        end)
        button:SetScript("OnEnter", function(self)
            local d = self.data
            if not d or d.header then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if d.kind == "spell" then
                GameTooltip:SetSpellByID(d.id)
            else
                GameTooltip:SetItemByID(d.id)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    button.data = data
    if data.header then
        button.icon:Hide()
        button.text:Hide()
        button.tag:Hide()
        button.header:SetText(data.header)
        button.header:Show()
        button.highlight:Hide()
    else
        button.header:Hide()
        button.icon:SetTexture(data.texture)
        button.icon:Show()
        button.text:SetText(data.name)
        button.text:Show()
        button.tag:SetText(TagFor(data))
        button.tag:Show()
        button.highlight:Show()
    end
end

local function UpdateVisible()
    if frame and frame:IsShown() then
        scrollBox:ForEachFrame(function(button, data)
            InitRow(button, data)
        end)
    end
end

function Picker:OnPick(button)
    local data = button.data
    if not data or data.header then
        return
    end
    local ok, err = DB:AddEntry(targetGroup, data.kind, data.id)
    if ok then
        statusText:SetText("")
        button.flash:SetAlpha(0.45)
        C_Timer.After(0.4, function()
            button.flash:SetAlpha(0)
        end)
        UpdateVisible()
    else
        statusText:SetTextColor(1, 0.3, 0.3)
        statusText:SetText(err or "Couldn't add.")
    end
end

local function Rebuild()
    if not (frame and frame:IsShown()) then
        return
    end
    local list = mode == "spell" and BuildSpellbook() or BuildInventory()
    local provider = CreateDataProvider(Filter(list, searchText))
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    scrollBox:SetDataProvider(provider, retain)
end

local function SetMode(newMode)
    mode = newMode
    spellButton:SetEnabled(mode ~= "spell")
    itemButton:SetEnabled(mode ~= "item")
    Rebuild()
end

local function Create()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "CDMC_EntryPicker", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(360, 460)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    searchBox:SetSize(190, 22)
    searchBox:SetPoint("TOPLEFT", 18, -30)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= searchText then
            searchText = text
            ns.Debounce("picker-rebuild", Rebuild)
        end
    end)

    spellButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    spellButton:SetSize(70, 22)
    spellButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    spellButton:SetText("Spellbook")
    spellButton:SetScript("OnClick", function() SetMode("spell") end)
    itemButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    itemButton:SetSize(70, 22)
    itemButton:SetPoint("LEFT", spellButton, "RIGHT", 4, 0)
    itemButton:SetText("Inventory")
    itemButton:SetScript("OnClick", function() SetMode("item") end)

    scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 12, -62)
    scrollBox:SetPoint("BOTTOMRIGHT", -28, 34)
    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 16, 12)
    statusText:SetPoint("BOTTOMRIGHT", -16, 12)
    statusText:SetJustifyH("LEFT")

    frame:SetScript("OnShow", function(self)
        for _, event in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
            if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
                self:RegisterEvent(event)
            end
        end
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
    end)
    frame:SetScript("OnEvent", function()
        ns.Debounce("picker-rebuild", Rebuild)
    end)
end

function Picker:Open(groupKey)
    Create()
    targetGroup = groupKey or targetGroup
    frame.TitleText:SetText("Add to: " .. ns.GROUP_LABELS[targetGroup])
    statusText:SetText("")
    frame:ClearAllPoints()
    local settings = _G.CooldownViewerSettings
    if settings and settings:IsShown() then
        frame:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    SetMode(mode)
end

function Picker:Hide()
    if frame then
        frame:Hide()
    end
end

ns.Subscribe("ENTRIES_CHANGED", function()
    UpdateVisible()
end)
