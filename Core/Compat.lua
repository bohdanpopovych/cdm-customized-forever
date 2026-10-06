local ADDON_NAME, ns = ...

local Compat = {}
ns.Compat = Compat

local FALLBACK_ICON = 134400
Compat.FALLBACK_ICON = FALLBACK_ICON

function Compat.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function Compat.SafeNumber(v, fallback)
    if v == nil or Compat.IsSecret(v) then
        return fallback
    end
    return v
end

Compat.HasDurationObjects = C_Spell ~= nil and C_Spell.GetSpellCooldownDuration ~= nil

function Compat.GetSpellName(id)
    if C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name
end

function Compat.GetSpellTexture(id)
    return C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
end

function Compat.GetOverrideSpell(id)
    return (C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(id)) or id
end

function Compat.IsSpellPassive(id)
    return C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(id) or false
end

function Compat.IsSpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if C_SpellBook.IsSpellKnown(id) then
            return true
        end
        if Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet and C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Pet) then
            return true
        end
    end
    if IsPlayerSpell and IsPlayerSpell(id) then
        return true
    end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then
        return true
    end
    if IsSpellKnown and IsSpellKnown(id) then
        return true
    end
    return false
end

function Compat.GetItemName(id)
    return C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or nil
end

function Compat.GetItemIcon(id)
    return C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil
end

function Compat.GetItemSpell(id)
    return C_Item.GetItemSpell and C_Item.GetItemSpell(id) or nil
end

function Compat.GetItemCount(id)
    return C_Item.GetItemCount(id, false, true) or 0
end

function Compat.IsEquippedItem(id)
    return C_Item.IsEquippedItem and C_Item.IsEquippedItem(id) or false
end

function Compat.RequestItem(id)
    if C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
    end
end

function Compat.GetCursorEntry()
    local cursorType, a, b, c = GetCursorInfo()
    if cursorType == "spell" then
        local spellID = c or a
        if spellID then
            return "spell", spellID
        end
    elseif cursorType == "item" then
        if a then
            return "item", a
        end
    elseif cursorType == "petaction" then
        local spellID = c or a
        if spellID and C_Spell.GetSpellInfo(spellID) then
            return "spell", spellID
        end
    elseif cursorType == "action" and GetActionInfo then
        local actionType, id = GetActionInfo(a)
        if actionType == "spell" then
            return "spell", id
        elseif actionType == "item" then
            return "item", id
        end
    end
    return nil
end
