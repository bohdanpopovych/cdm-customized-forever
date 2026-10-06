local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"

local _, _, _, tocVersion = GetBuildInfo()
ns.isForever = tocVersion >= 16000 and tocVersion < 20000

ns.VIEWERS = {
    Essential = { frame = "EssentialCooldownViewer", w = 50, h = 50, overlay = { -9, 8, 9, -8 } },
    Utility = { frame = "UtilityCooldownViewer", w = 30, h = 30, overlay = { -6, 5, 6, -5 } },
    BuffIcon = { frame = "BuffIconCooldownViewer", w = 40, h = 40, overlay = { -8, 7, 8, -7 } },
}
ns.VIEWER_KEYS = { "Essential", "Utility", "BuffIcon" }
ns.GROUP_KEYS = { "Essential", "Utility", "Left", "Right" }
ns.GROUP_LABELS = {
    Essential = "Essential cooldowns",
    Utility = "Utility cooldowns",
    Left = "Additional cooldowns left",
    Right = "Additional cooldowns right",
}
ns.MIN_SIZE, ns.MAX_SIZE = 12, 128

ns.L = setmetatable({}, { __index = function(_, k) return k end })

function ns.Print(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    print("|cff33ccffCDM Customizer|r: " .. (ok and text or tostring(fmt)))
end

function ns.Debug(fmt, ...)
    if CDMCustomizerDB and CDMCustomizerDB.global and CDMCustomizerDB.global.debug then
        local ok, text = pcall(string.format, fmt, ...)
        print("|cff888888CDMC debug|r: " .. (ok and text or tostring(fmt)))
    end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

local function Dispatch(fn, ...)
    local args, n = { ... }, select("#", ...)
    xpcall(function() fn(unpack(args, 1, n)) end, geterrorhandler())
end

function ns.Safe(fn)
    return function(...)
        Dispatch(fn, ...)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end

    local copy = { unpack(list) }
    for i = 1, #copy do
        Dispatch(copy[i], event, ...)
    end
end)

function ns.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

function ns.Off(event, fn)
    local list = handlers[event]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == fn then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

local subscribers = {}

function ns.Subscribe(msg, fn)
    subscribers[msg] = subscribers[msg] or {}
    table.insert(subscribers[msg], fn)
end

function ns.Fire(msg, ...)
    local list = subscribers[msg]
    if not list then
        return
    end
    local copy = { unpack(list) }
    for i = 1, #copy do
        Dispatch(copy[i], ...)
    end
end

local pendingDebounce = {}

function ns.Debounce(key, fn)
    if pendingDebounce[key] then
        pendingDebounce[key] = fn
        return
    end
    pendingDebounce[key] = fn
    C_Timer.After(0, function()
        local f = pendingDebounce[key]
        pendingDebounce[key] = nil
        if f then
            Dispatch(f)
        end
    end)
end

local outOfCombatQueue = {}

function ns.RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        outOfCombatQueue[key] = nil
        Dispatch(fn)
        return
    end
    outOfCombatQueue[key] = fn
end

ns.On("PLAYER_REGEN_DISABLED", function()
    ns.inCombat = true
    ns.Fire("COMBAT_START")
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    ns.inCombat = false
    local queue = outOfCombatQueue
    outOfCombatQueue = {}
    for _, fn in pairs(queue) do
        Dispatch(fn)
    end
    ns.Fire("COMBAT_END")
end)
