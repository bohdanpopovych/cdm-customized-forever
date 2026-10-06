local ADDON_NAME, ns = ...

local function PrintStatus()
    ns.Print("v%s | isForever=%s | TOC=%s", ns.VERSION, tostring(ns.isForever), tostring(select(4, GetBuildInfo())))
    local DB = ns.DB
    if not DB or not DB.profile then
        ns.Print("Profile not loaded yet.")
        return
    end
    ns.Print("Profile key: '%s' | player: %s | realm: %s | GUID: %s", tostring(DB.charKey), tostring(UnitName("player")), tostring(GetRealmName()), tostring(UnitGUID("player")))
    local profileCount = 0
    for _ in pairs(CDMCustomizerDB.profiles) do
        profileCount = profileCount + 1
    end
    ns.Print("Profiles stored this session: %d", profileCount)
    for _, key in ipairs(ns.GROUP_KEYS) do
        ns.Print("%s: %d entries", ns.GROUP_LABELS[key], #DB:Entries(key))
    end
end

local GROUP_ALIASES = { essential = "Essential", utility = "Utility", left = "Left", right = "Right" }

local function ListEntries()
    for _, key in ipairs(ns.GROUP_KEYS) do
        local list = ns.DB:Entries(key)
        ns.Print("%s (%d):", ns.GROUP_LABELS[key], #list)
        for i, entry in ipairs(list) do
            local name = ns.Entries:GetDisplay(entry)
            ns.Print("  %d. %s  [%s:%d]", i, name, entry.kind, entry.id)
        end
    end
end

local function AddEntry(rest)
    local groupText, text = rest:match("^(%S+)%s+(.+)$")
    local group = groupText and GROUP_ALIASES[groupText:lower()]
    if not group then
        ns.Print("Usage: /cdmc add <essential|utility|left|right> <s:ID | i:ID | ID | name>")
        return
    end
    local kind, id = ns.Entries:Parse(text)
    if not kind then
        ns.Print("%s", id or "Couldn't parse.")
        return
    end
    local ok, err = ns.DB:AddEntry(group, kind, id)
    if not ok then
        ns.Print("%s", err or "Couldn't add.")
        return
    end
    local name = ns.Entries:GetDisplay({ kind = kind, id = id })
    ns.Print("Added %s (%s:%d) to %s.", name, kind, id, ns.GROUP_LABELS[group])
    if group == "Essential" or group == "Utility" then
        ns.Print("Note: native Essential/Utility bars don't display added entries yet (planned Phase 6).")
    end
end

local function RemoveEntry(rest)
    local groupText, indexText = rest:match("^(%S+)%s+(%d+)$")
    local group = groupText and GROUP_ALIASES[groupText:lower()]
    if not group then
        ns.Print("Usage: /cdmc remove <essential|utility|left|right> <index>  (see /cdmc list)")
        return
    end
    if ns.DB:RemoveEntry(group, tonumber(indexText)) then
        ns.Print("Removed entry %s from %s.", indexText, ns.GROUP_LABELS[group])
    else
        ns.Print("No entry %s in %s.", indexText, ns.GROUP_LABELS[group])
    end
end

local RESET_SCOPES = { viewers = true, groups = true, entries = true, all = true }

StaticPopupDialogs["CDMC_CONFIRM_RESET"] = {
    text = "Reset CDM Customizer %s settings for this character?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if ns.DB:Reset(data) then
            ns.Print("Reset: %s.", data)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function ResetSettings(scope)
    if not RESET_SCOPES[scope] then
        ns.Print("Usage: /cdmc reset <viewers|groups|entries|all>")
        return
    end
    StaticPopup_Show("CDMC_CONFIRM_RESET", scope, nil, scope)
end

local function PrintHelp()
    ns.Print("Commands:")
    print("  /cdmc  - open the settings tab")
    print("  /cdmc status | list | debug")
    print("  /cdmc add <essential|utility|left|right> <s:ID | i:ID | ID | name>")
    print("  /cdmc remove <essential|utility|left|right> <index>")
    print("  /cdmc reset <viewers|groups|entries|all>")
    print("  /cdmc copyfrom <number>  - copy another character setup (run without a number to list)")
end

SLASH_CDMC1 = "/cdmc"
SlashCmdList["CDMC"] = function(msg)
    local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        ns.SettingsTab:Open()
    elseif command == "status" then
        PrintStatus()
    elseif command == "help" or command == "?" then
        PrintHelp()
    elseif command == "copyfrom" then
        local others = ns.DB:OtherProfiles()
        local choice = tonumber(rest) and others[tonumber(rest)]
        if rest == "" then
            if #others == 0 then
                ns.Print("No other characters have a saved setup yet.")
            else
                ns.Print("Usage: /cdmc copyfrom <number>")
                for i, other in ipairs(others) do
                    print(string.format("  %d. %s", i, other.label))
                end
            end
        elseif choice and ns.DB:CopyProfile(choice.key) then
            ns.Print("Copied the setup from %s.", choice.label)
        else
            ns.Print("No profile number '%s'. Run /cdmc copyfrom to see the list.", rest)
        end
    elseif command == "reset" then
        ResetSettings(rest:lower())
    elseif command == "debug" then
        local g = ns.DB:Global()
        g.debug = not g.debug
        ns.Print("Debug %s.", g.debug and "on" or "off")
    elseif command == "add" then
        AddEntry(rest)
    elseif command == "remove" then
        RemoveEntry(rest)
    elseif command == "list" then
        ListEntries()
    else
        ns.Print("Unknown command '%s'.", command)
    end
end

ns.On("PLAYER_LOGIN", function()
    for key in pairs(SlashCmdList) do
        for n = 1, 10 do
            local command = _G["SLASH_" .. key .. n]
            if command and command:lower() == "/cdm" then
                ns.Debug("/cdm is already taken by %s; /cdmc is available.", key)
                return
            end
        end
    end
    SLASH_CDMC_CDM1 = "/cdm"
    SlashCmdList["CDMC_CDM"] = function()
        ns.SettingsTab:Open()
    end
end)
