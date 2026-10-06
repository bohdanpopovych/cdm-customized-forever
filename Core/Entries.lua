local ADDON_NAME, ns = ...

local Compat = ns.Compat

local Entries = {}
ns.Entries = Entries

local function ItemExists(id)
    return C_Item.GetItemInfoInstant(id) ~= nil
end

function Entries:Key(entry)
    return entry.kind .. ":" .. entry.id
end

function Entries:Validate(kind, id)
    id = tonumber(id)
    if not id then
        return false, "Invalid ID."
    end
    if kind == "spell" then
        if not Compat.GetSpellName(id) then
            return false, "Unknown spell ID " .. id .. "."
        end
        if Compat.IsSpellPassive(id) then
            return false, "Passive spells have no cooldown."
        end
        return true
    elseif kind == "item" then
        if not ItemExists(id) then
            return false, "Unknown item ID " .. id .. "."
        end
        if not Compat.GetItemSpell(id) then
            return true, "Item has no Use effect \226\128\148 it will only show count."
        end
        return true
    end
    return false, "Entry kind must be spell or item."
end

function Entries:Parse(text)
    text = strtrim(text or "")
    if text == "" then
        return nil, "Nothing entered."
    end

    local linkKind, linkID = text:match("|H(%a+):(%d+)")
    if linkKind == "spell" or linkKind == "item" then
        return linkKind, tonumber(linkID)
    end

    local prefix, num = text:lower():match("^([si]):(%d+)$")
    if prefix then
        return prefix == "s" and "spell" or "item", tonumber(num)
    end

    local id = tonumber(text)
    if id then
        local spellOk = Compat.GetSpellName(id) ~= nil
        local itemOk = ItemExists(id)
        if spellOk and not itemOk then
            return "spell", id
        elseif itemOk and not spellOk then
            return "item", id
        elseif spellOk and itemOk then
            local spellKnown = Compat.IsSpellKnown(id)
            local itemOwned = Compat.IsEquippedItem(id) or Compat.GetItemCount(id) > 0
            if spellKnown and not itemOwned then
                return "spell", id
            elseif itemOwned and not spellKnown then
                return "item", id
            end
            return nil, "Ambiguous ID \226\128\148 use s:" .. id .. " or i:" .. id
        end
        return nil, "No spell or item with ID " .. id .. "."
    end

    local info = C_Spell.GetSpellInfo(text)
    if info and info.spellID then
        return "spell", info.spellID
    end
    local itemID = C_Item.GetItemInfoInstant(text)
    if itemID then
        return "item", itemID
    end
    return nil, "Couldn't find '" .. text .. "' (names work only for known spells and cached items)."
end

function Entries:GetDisplay(entry)
    if entry.kind == "spell" then
        local id = Compat.GetOverrideSpell(entry.id)
        local name = Compat.GetSpellName(id) or Compat.GetSpellName(entry.id) or ("spell:" .. entry.id)
        local texture = Compat.GetSpellTexture(id) or Compat.GetSpellTexture(entry.id) or Compat.FALLBACK_ICON
        return name, texture
    end

    local name = Compat.GetItemName(entry.id)
    local texture = Compat.GetItemIcon(entry.id)
    if not texture then
        texture = select(5, C_Item.GetItemInfoInstant(entry.id))
    end
    if not name then
        Compat.RequestItem(entry.id)
        name = "item:" .. entry.id
    end
    return name, texture or Compat.FALLBACK_ICON
end

function Entries:IsAvailable(entry)
    if entry.kind == "spell" then
        return Compat.IsSpellKnown(entry.id), false
    end
    if Compat.IsEquippedItem(entry.id) or Compat.GetItemCount(entry.id) > 0 then
        return true, false
    end
    local profile = ns.DB:Profile()
    local showMissing = profile and profile.items.showWhenMissing
    return showMissing == true, true
end
