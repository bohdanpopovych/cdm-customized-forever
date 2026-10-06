local ADDON_NAME, ns = ...

local DB = {}
ns.DB = DB

local GLOBAL_DEFAULTS = { version = 1, debug = false }

local VIEWER_DEFAULTS = {
    enabled = false,
    zoom = 0,
    placement = "after",
    showGCD = false,
}

local GROUP_DEFAULTS = {
    enabled = true,
    width = 36,
    height = 36,
    zoom = 0,
    spacing = 2,
    perLine = 8,
    orientation = "HORIZONTAL",
    wrap = "DOWN",
    scale = 1,
    alpha = 1,
    visibility = "essential",
    showGCD = false,
    showTimer = true,
    showTooltips = true,
    attach = true,
}

local GROUP_SIDE_DEFAULTS = {
    Left = { grow = "LEFT", point = "RIGHT", relPoint = "LEFT", x = -4, y = 0 },
    Right = { grow = "RIGHT", point = "LEFT", relPoint = "RIGHT", x = 4, y = 0 },
}

local function Copy(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for k, v in pairs(src) do
        out[k] = Copy(v)
    end
    return out
end
DB.Copy = Copy

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function BuildProfileDefaults()
    local defaults = {
        viewers = {},
        groups = {},
        entries = { Essential = {}, Utility = {}, Left = {}, Right = {} },
        items = { showWhenMissing = true },
    }
    for _, key in ipairs(ns.VIEWER_KEYS) do
        defaults.viewers[key] = Copy(VIEWER_DEFAULTS)
    end
    for _, key in ipairs({ "Left", "Right" }) do
        local g = Copy(GROUP_DEFAULTS)
        MergeDefaults(g, GROUP_SIDE_DEFAULTS[key])
        defaults.groups[key] = g
    end
    return defaults
end

function DB:Migrate()

    CDMCustomizerDB.global.version = GLOBAL_DEFAULTS.version
end

function DB:Init()
    CDMCustomizerDB = CDMCustomizerDB or {}
    CDMCustomizerDB.global = CDMCustomizerDB.global or {}
    CDMCustomizerDB.profiles = CDMCustomizerDB.profiles or {}
    MergeDefaults(CDMCustomizerDB.global, GLOBAL_DEFAULTS)
    self:Migrate()
end

function DB:LegacyKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

function DB:CharKey()
    return UnitGUID("player") or self:LegacyKey()
end

function DB:LoadProfile()
    local key = self:CharKey()
    local legacy = self:LegacyKey()
    local profiles = CDMCustomizerDB.profiles

    if key ~= legacy and not profiles[key] and profiles[legacy] then
        profiles[key] = profiles[legacy]
        profiles[legacy] = nil
    end
    profiles[key] = profiles[key] or {}
    MergeDefaults(profiles[key], BuildProfileDefaults())
    profiles[key].meta = { name = UnitName("player"), realm = GetRealmName() }
    self.profile = profiles[key]
    self.charKey = key
end

function DB:Global()
    return CDMCustomizerDB.global
end

function DB:Profile()
    return self.profile
end

function DB:Viewer(key)
    return self.profile.viewers[key]
end

function DB:Group(key)
    return self.profile.groups[key]
end

function DB:Entries(groupKey)
    return self.profile.entries[groupKey]
end

function DB:GetViewerSize(key)
    local cfg = self:Viewer(key)
    local base = ns.VIEWERS[key]
    return cfg.width or base.w, cfg.height or base.h, cfg.enabled
end

function DB:FindEntry(kind, id)
    for _, groupKey in ipairs(ns.GROUP_KEYS) do
        local list = self.profile.entries[groupKey]
        for i, entry in ipairs(list) do
            if entry.kind == kind and entry.id == id then
                return groupKey, i
            end
        end
    end
end

function DB:AddEntry(groupKey, kind, id, index)
    if not self.profile.entries[groupKey] then
        return false, "Unknown group: " .. tostring(groupKey)
    end
    if kind ~= "spell" and kind ~= "item" then
        return false, "Entry kind must be spell or item."
    end
    id = tonumber(id)
    if not id then
        return false, "Invalid ID."
    end
    if ns.Entries and ns.Entries.Validate then
        local ok, err = ns.Entries:Validate(kind, id)
        if not ok then
            return false, err
        end
    end

    local oldGroup, oldIndex = self:FindEntry(kind, id)
    if oldGroup then
        table.remove(self.profile.entries[oldGroup], oldIndex)
    end

    local list = self.profile.entries[groupKey]
    local entry = { kind = kind, id = id }
    if index and index >= 1 and index <= #list + 1 then
        table.insert(list, index, entry)
    else
        list[#list + 1] = entry
    end

    ns.Fire("ENTRIES_CHANGED", groupKey)
    if oldGroup and oldGroup ~= groupKey then
        ns.Fire("ENTRIES_CHANGED", oldGroup)
    end
    return true
end

function DB:RemoveEntry(groupKey, index)
    local list = self.profile.entries[groupKey]
    if not list or not list[index] then
        return false
    end
    table.remove(list, index)
    ns.Fire("ENTRIES_CHANGED", groupKey)
    return true
end

function DB:MoveEntry(groupKey, from, to)
    local list = self.profile.entries[groupKey]
    if not list or not list[from] then
        return false
    end
    to = math.max(1, math.min(#list, to))
    if from == to then
        return false
    end
    local entry = table.remove(list, from)
    table.insert(list, to, entry)
    ns.Fire("ENTRIES_CHANGED", groupKey)
    return true
end

function DB:TransferEntry(fromGroup, index, toGroup)
    local from = self.profile.entries[fromGroup]
    if fromGroup == toGroup or not from or not from[index] or not self.profile.entries[toGroup] then
        return false
    end
    local entry = table.remove(from, index)
    local to = self.profile.entries[toGroup]
    to[#to + 1] = entry
    ns.Fire("ENTRIES_CHANGED", fromGroup)
    ns.Fire("ENTRIES_CHANGED", toGroup)
    return true
end

function DB:SetViewerOption(key, field, value)
    self.profile.viewers[key][field] = value
    ns.Fire("VIEWER_SIZE_CHANGED", key)
end

function DB:SetGroupOption(key, field, value)
    self.profile.groups[key][field] = value
    ns.Fire("GROUP_LAYOUT_CHANGED", key)
end

local function FireAll()
    for _, key in ipairs(ns.VIEWER_KEYS) do
        ns.Fire("VIEWER_SIZE_CHANGED", key)
    end
    for _, key in ipairs({ "Left", "Right" }) do
        ns.Fire("GROUP_LAYOUT_CHANGED", key)
    end
    for _, key in ipairs(ns.GROUP_KEYS) do
        ns.Fire("ENTRIES_CHANGED", key)
    end
    if ns.EditModePanel and ns.EditModePanel.Refresh then
        ns.EditModePanel:Refresh()
    end
end

function DB:CopyProfile(fromKey)
    local src = CDMCustomizerDB.profiles[fromKey]
    if not src or src == self.profile then
        return false
    end
    local copy = Copy(src)
    local meta = self.profile.meta
    for k in pairs(self.profile) do
        self.profile[k] = nil
    end
    for k, v in pairs(copy) do
        self.profile[k] = v
    end
    self.profile.meta = meta
    MergeDefaults(self.profile, BuildProfileDefaults())
    FireAll()
    return true
end

function DB:OtherProfiles()
    local list = {}
    for key, profile in pairs(CDMCustomizerDB.profiles) do
        if key ~= self.charKey then
            local meta = profile.meta
            local label = meta and meta.name and (meta.name .. "-" .. tostring(meta.realm)) or tostring(key)
            list[#list + 1] = { key = key, label = label }
        end
    end
    table.sort(list, function(a, b)
        return a.label < b.label or (a.label == b.label and a.key < b.key)
    end)
    return list
end

function DB:Reset(scope)
    if scope ~= "viewers" and scope ~= "groups" and scope ~= "entries" and scope ~= "all" then
        return false
    end
    local defaults = BuildProfileDefaults()
    local all = scope == "all"
    if all or scope == "viewers" then
        self.profile.viewers = defaults.viewers
        for _, key in ipairs(ns.VIEWER_KEYS) do
            ns.Fire("VIEWER_SIZE_CHANGED", key)
        end
    end
    if all or scope == "groups" then
        self.profile.groups = defaults.groups
        for _, key in ipairs({ "Left", "Right" }) do
            ns.Fire("GROUP_LAYOUT_CHANGED", key)
        end
    end
    if all or scope == "entries" then
        self.profile.entries = defaults.entries
        self.profile.items = defaults.items
        for _, key in ipairs(ns.GROUP_KEYS) do
            ns.Fire("ENTRIES_CHANGED", key)
        end
    end
    if ns.EditModePanel and ns.EditModePanel.Refresh then
        ns.EditModePanel:Refresh()
    end
    return true
end

function DB:ResetGroupPosition(key)
    local cfg, defaults = self.profile.groups[key], GROUP_SIDE_DEFAULTS[key]
    if not cfg or not defaults then
        return
    end
    cfg.attach = true
    cfg.point, cfg.relPoint, cfg.x, cfg.y = defaults.point, defaults.relPoint, defaults.x, defaults.y
    ns.Fire("GROUP_LAYOUT_CHANGED", key)
end

ns.On("ADDON_LOADED", function(_, name)
    if name == ADDON_NAME then
        DB:Init()
    end
end)

ns.On("PLAYER_LOGIN", function()
    DB:LoadProfile()
    ns.Fire("PROFILE_READY")
end)
