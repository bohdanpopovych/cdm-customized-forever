local ADDON_NAME, ns = ...

local Compat = ns.Compat

local Updater = {}
ns.CooldownUpdater = Updater

local GCD_THRESHOLD = 1.5

local active = {}
local bySpell, byItem = {}, {}
local indexDirty = true
local reported = {}
local SyncRange

local desatCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    desatCurve = C_CurveUtil.CreateCurve()
    desatCurve:AddPoint(0, 0)
    desatCurve:AddPoint(0.001, 1)
end

local function SetDesaturation(frame, value)
    if frame.Icon.SetDesaturation then
        frame.Icon:SetDesaturation(value)
    else
        frame.Icon:SetDesaturated(value ~= 0)
    end
end

local function Plain(v)
    if v == nil or Compat.IsSecret(v) then
        return nil
    end
    return v
end

function Updater:Register(frame)
    active[frame] = true
    indexDirty = true
    ns.Debounce("range-sync", function() SyncRange() end)
end

function Updater:Unregister(frame)
    active[frame] = nil
    indexDirty = true
    ns.Debounce("range-sync", function() SyncRange() end)
end

local function AddTo(map, key, frame)
    if not key then
        return
    end
    local list = map[key]
    if not list then
        list = {}
        map[key] = list
    end
    list[#list + 1] = frame
end

local function Reindex()
    if not indexDirty then
        return
    end
    indexDirty = false
    bySpell, byItem = {}, {}
    for frame in pairs(active) do
        local entry = frame.entry
        if entry then
            if entry.kind == "spell" then
                AddTo(bySpell, entry.id, frame)
                local override = Compat.GetOverrideSpell(entry.id)
                if override ~= entry.id then
                    AddTo(bySpell, override, frame)
                end
            else
                AddTo(byItem, entry.id, frame)
                local _, useSpell = Compat.GetItemSpell(entry.id)
                AddTo(bySpell, useSpell, frame)
            end
        end
    end
end

local rangeEnabled = {}
SyncRange = function()
    if not (C_Spell.EnableSpellRangeCheck and C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsEventValid("SPELL_RANGE_CHECK_UPDATE")) then
        return
    end
    local wanted = {}
    for frame in pairs(active) do
        if frame.entry and frame.entry.kind == "spell" then
            wanted[Compat.GetOverrideSpell(frame.entry.id)] = true
        end
    end
    for id in pairs(wanted) do
        if not rangeEnabled[id] then
            C_Spell.EnableSpellRangeCheck(id, true)
            rangeEnabled[id] = true
        end
    end
    for id in pairs(rangeEnabled) do
        if not wanted[id] then
            C_Spell.EnableSpellRangeCheck(id, false)
            rangeEnabled[id] = nil
        end
    end
end

local function UpdateSpell(frame, entry, opts)
    local cd = frame.Cooldown
    local id = Compat.GetOverrideSpell(entry.id)

    local charges = C_Spell.GetSpellCharges(id)
    local hasCharges = false
    if charges then
        local maxCharges = Plain(charges.maxCharges)
        hasCharges = maxCharges ~= nil and maxCharges > 1
    end
    if hasCharges then
        frame.Count:SetText(charges.currentCharges)
    else

        local castCount = C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(id)
        if castCount ~= nil and C_StringUtil and C_StringUtil.TruncateWhenZero then
            frame.Count:SetText(C_StringUtil.TruncateWhenZero(castCount))
        elseif castCount ~= nil and not Compat.IsSecret(castCount) and castCount > 0 then
            frame.Count:SetText(castCount)
        else
            frame.Count:SetText("")
        end
    end

    local info = C_Spell.GetSpellCooldown(id)
    local onGCD = info and Plain(info.isOnGCD) == true or false
    local isActive = info and Plain(info.isActive) == true or false

    cd:SetHideCountdownNumbers(opts.showTimer == false)

    local desaturation = 0
    if Compat.HasDurationObjects and desatCurve and cd.SetCooldownFromDurationObject then
        local durObj = C_Spell.GetSpellCooldownDuration(id)
        if hasCharges then
            local chargeObj = C_Spell.GetSpellChargeDuration(id)
            if chargeObj then
                cd:SetCooldownFromDurationObject(chargeObj)
            end
            local isRealCooldown = isActive and not onGCD
            cd:SetDrawSwipe(isRealCooldown)
            cd:SetDrawEdge(not isRealCooldown)
        elseif onGCD and not opts.showGCD then
            cd:Clear()
        elseif durObj then
            cd:SetCooldownFromDurationObject(durObj)
            cd:SetDrawSwipe(true)
            cd:SetDrawEdge(false)
        end
        if durObj and not onGCD then
            desaturation = durObj:EvaluateRemainingDuration(desatCurve)
        end
    elseif info then
        local start, duration = Plain(info.startTime), Plain(info.duration)
        if start and duration and duration > 0 and (opts.showGCD or not onGCD) then
            cd:SetCooldown(start, duration)
        else
            cd:Clear()
        end
        if duration and duration > GCD_THRESHOLD and not onGCD then
            desaturation = 1
        end
    else
        cd:Clear()
    end
    SetDesaturation(frame, desaturation)
    frame.Icon:SetAlpha(1)

    local usable, noMana = C_Spell.IsSpellUsable(id)
    usable, noMana = Plain(usable), Plain(noMana)
    if noMana then
        frame.Icon:SetVertexColor(0.5, 0.5, 1)
    elseif usable == false then
        frame.Icon:SetVertexColor(0.4, 0.4, 0.4)
    else
        frame.Icon:SetVertexColor(1, 1, 1)
    end
end

local function UpdateItem(frame, entry, opts)
    local cd = frame.Cooldown
    local id = entry.id
    local equipped = Compat.IsEquippedItem(id)
    local count = Compat.GetItemCount(id)
    local missing = count == 0 and not equipped

    frame.Count:SetText((count > 1 and not equipped) and count or "")
    cd:SetHideCountdownNumbers(opts.showTimer == false)

    local start, duration, enabled = C_Item.GetItemCooldown(id)
    start, duration = Plain(start), Plain(duration)
    local isEnabled = enabled == true or enabled == 1

    local desaturation = 0
    if isEnabled and start and duration and duration > 0 and (duration > GCD_THRESHOLD or opts.showGCD) then
        cd:SetCooldown(start, duration)
        cd:SetDrawSwipe(true)
        if duration > GCD_THRESHOLD then
            desaturation = 1
        end
    else
        cd:Clear()
    end

    if missing then
        desaturation = 1
    end
    SetDesaturation(frame, desaturation)
    frame.Icon:SetAlpha(missing and 0.5 or 1)

    local usable, noMana
    if not missing then
        usable, noMana = C_Item.IsUsableItem(id)
        usable, noMana = Plain(usable), Plain(noMana)
    end
    if noMana then
        frame.Icon:SetVertexColor(0.5, 0.5, 1)
    elseif usable == false then
        frame.Icon:SetVertexColor(0.4, 0.4, 0.4)
    else
        frame.Icon:SetVertexColor(1, 1, 1)
    end
end

function Updater:UpdateIcon(frame)
    local entry = frame.entry
    if not entry then
        return
    end
    local opts = frame.opts or {}
    local ok, err = pcall(entry.kind == "spell" and UpdateSpell or UpdateItem, frame, entry, opts)
    if not ok then
        local key = entry.kind .. ":" .. entry.id
        if not reported[key] then
            reported[key] = true
            ns.Print("Cooldown update failed for %s: %s", key, tostring(err))
        end
    end
end

function Updater:UpdateAll()
    for frame in pairs(active) do
        self:UpdateIcon(frame)
    end
end

function Updater:UpdateKind(kind)
    for frame in pairs(active) do
        if frame.entry and frame.entry.kind == kind then
            self:UpdateIcon(frame)
        end
    end
end

local function UpdateList(list)
    if list then
        for _, frame in ipairs(list) do
            Updater:UpdateIcon(frame)
        end
    end
end

function Updater:RefreshTextures()
    for frame in pairs(active) do
        frame:RefreshTexture()
    end
end

local function On(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return
    end
    ns.On(event, fn)
end

local function DebouncedAll()
    ns.Debounce("cdupdate-all", function()
        Updater:UpdateAll()
    end)
end

local function DebouncedKind(kind)
    ns.Debounce("cdupdate-" .. kind, function()
        Updater:UpdateKind(kind)
    end)
end

local function Availability()
    ns.Debounce("availability", function()
        Updater:RefreshTextures()
        Updater:UpdateAll()
        ns.Fire("AVAILABILITY_CHANGED")
    end)
end

On("SPELL_UPDATE_COOLDOWN", function(_, spellID, baseSpellID, category, _, itemID)
    Reindex()
    if not spellID and not baseSpellID and not itemID then
        DebouncedAll()
        return
    end
    UpdateList(bySpell[spellID])
    if baseSpellID and baseSpellID ~= spellID then
        UpdateList(bySpell[baseSpellID])
    end
    UpdateList(byItem[itemID])
    if category then

        DebouncedKind("item")
    end
end)

On("SPELL_UPDATE_CHARGES", function() DebouncedKind("spell") end)
On("SPELL_UPDATE_USABLE", function() DebouncedKind("spell") end)
On("SPELL_UPDATE_USES", function() DebouncedKind("spell") end)
On("SPELL_UPDATE_ICON", function()
    Updater:RefreshTextures()
    DebouncedKind("spell")
end)
On("BAG_UPDATE_COOLDOWN", function() DebouncedKind("item") end)
On("ITEM_COUNT_CHANGED", function() DebouncedKind("item") end)

On("SPELL_RANGE_CHECK_UPDATE", function(_, spellID, inRange, checksRange)
    Reindex()
    local list = bySpell[spellID]
    if not list then
        return
    end
    inRange, checksRange = Plain(inRange), Plain(checksRange)
    for _, frame in ipairs(list) do
        if frame.entry and frame.entry.kind == "spell" then
            frame.OutOfRange:SetShown(checksRange == true and inRange == false)
        end
    end
end)

On("SPELLS_CHANGED", Availability)
On("BAG_UPDATE_DELAYED", Availability)
On("PLAYER_EQUIPMENT_CHANGED", Availability)
On("PLAYER_ENTERING_WORLD", Availability)
On("ITEM_DATA_LOAD_RESULT", Availability)
On("GET_ITEM_INFO_RECEIVED", Availability)
On("UNIT_PET", function(_, unit)
    if unit == "player" then
        Availability()
    end
end)
