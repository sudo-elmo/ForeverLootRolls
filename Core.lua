-- WoW glue: events, saved variables, group roster, slash commands, addon compartment.
local ADDON, ns = ...
local L, R, P, UI = ns.L, ns.Rolls, ns.Parser, ns.UI

ns.DEFAULTS = {
    pos = nil,
    collapseMode = "delay",     -- instant | delay | newroll | never
    collapseDelay = 5,
    -- dungeons and raids
    openOnEnterDungeon = false,
    dungeonAutoOpen = true,
    dungeonAutoClose = true,
    dungeonCloseDelay = 8,
    -- open world
    worldAutoOpen = true,
    worldAutoClose = true,
    worldCloseDelay = 8,
    closeOnEscape = true,
    rollButtons = true,
    historySize = 30,
    archiveSize = 1000,
    historyMinQuality = 0,      -- loot history filter: 0 = all, 2 = from uncommon, ...
    maxHeight = 380,
    windowWidth = 320,
    opacity = 100,              -- background opacity in percent
    clearOnNewInstance = true,
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. L.title .. ":|r " .. tostring(msg))
end

ns.Now = GetTime
ns.Clock = time

function ns.PlayerName()
    return ns.ShortName((UnitName("player")))
end

-- Bare character name: chat and unit functions hand out "Name", "Name-Realm",
-- "Name Realm" or a player link, depending on the client. Rolls are matched by
-- this name, so it must come out the same every time.
function ns.ShortName(name)
    if type(name) ~= "string" then return name end
    name = name:match("|Hplayer:([^:|]+)") or name
    name = name:gsub("|c[^|]*", ""):gsub("|r", ""):gsub("|h", "")
    return name:match("^%s*([^%s%-]+)") or name
end

-- Inside a dungeon or raid (not a battleground, arena or the open world)?
function ns.InDungeon()
    if not IsInInstance then return false end
    local inInstance, kind = IsInInstance()
    return (inInstance and (kind == "party" or kind == "raid")) and true or false
end

-- Where a roll happens: dungeon / raid name, otherwise the zone.
function ns.GetZone()
    if GetInstanceInfo then
        local name, kind = GetInstanceInfo()
        if name and kind and kind ~= "none" then return name, kind end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
    if zone == "" then zone = nil end
    return zone or "?", "none"
end

function ns.ItemIcon(link)
    if not link then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

function ns.GetRoster()
    local out = {}
    local function Add(unit)
        if not UnitExists(unit) then return end
        local name = UnitName(unit)
        if not name or name == UNKNOWNOBJECT then return end
        name = ns.ShortName(name)
        local _, class = UnitClass(unit)
        out[#out + 1] = { name = name, class = class }
    end
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    else
        Add("player")
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 4
        for i = 1, n do Add("party" .. i) end
    end
    return out
end

-- Rolling in our window leaves Blizzard's roll frame open; tidy it away
-- once the chat has confirmed our choice.
local function HideBlizzardRollFrame(id)
    if type(id) ~= "number" then return end
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local frame = _G["GroupLootFrame" .. i]
        if frame and frame.rollID == id and frame:IsShown() then
            if GroupLootContainer_RemoveFrame and GroupLootContainer then
                pcall(GroupLootContainer_RemoveFrame, GroupLootContainer, frame)
            end
            frame:Hide()
        end
    end
end

-- ---------------------------------------------------------------- new dungeon run

-- A new run starts the list fresh (setting "clear on a new dungeon run").
-- Normal dungeons have no instance ID the API hands out, and Forever hides
-- creature GUIDs (secret values) inside instances, so a run is recognised by
-- what can be seen:
--   * a different dungeon or raid                         -> new run
--   * the same one, but "<dungeon> has been reset" came   -> new run
--   * the same one with another group (fewer than half of
--     the last run's members still there)                 -> new run
--   * the same one, the same group (corpse run, back from
--     town, /reload)                                      -> same run
-- Each run gets a number; rolls and history entries carry "<map ID>:<number>".

local function Plain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

-- The other group members' names (not ours), as a set; nil if a name is not
-- known yet (still loading after login).
function ns.GroupMembers()
    local out, unknown = {}, false
    local me = ns.PlayerName()
    local function Add(unit)
        local okE, exists = pcall(UnitExists, unit)
        if not (okE and Plain(exists)) then return end
        local ok, name = pcall(UnitName, unit)
        name = ok and Plain(name)
        if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then unknown = true return end
        name = ns.ShortName(name)
        if name ~= me then out[name] = true end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do Add("raid" .. i) end
    else
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do Add("party" .. i) end
    end
    if unknown then return nil end
    return out
end

local function NewRun()
    if ns.db and ns.db.clearOnNewInstance then R:ClearFinished() end
end

-- isLogin: logging in or /reload (the group may still be loading)
function ns.OnDungeonChange(dungeon, isLogin)
    local db = ns.charDB
    if not db then return end
    db.inDungeon = dungeon and true or false
    db.lastInstance, db.lastZoneUID = nil, nil   -- GUID based detection of 0.x
    if not dungeon then return end
    local instanceID = GetInstanceInfo and select(8, GetInstanceInfo()) or 0
    local run = db.run
    local members = ns.GroupMembers()
    local new
    if not run or run.instance ~= instanceID then
        new = true
    elseif db.resetSeen then
        new = true
    elseif members and not isLogin then
        new = not ns.Archive.SameGroup(run.members, members)
    end
    db.resetSeen = nil
    if new then
        db.runCount = (db.runCount or 0) + 1
        db.run = { instance = instanceID, n = db.runCount, members = members or {} }
        NewRun()
    elseif members then
        for name in pairs(members) do run.members[name] = true end
    end
end

-- Someone joins during the run: the run remembers everyone who was in the
-- group, so a replacement does not make the next entry a new run.
function ns.OnGroupChanged()
    local db = ns.charDB
    if not (db and db.inDungeon and db.run) then return end
    for name in pairs(ns.GroupMembers() or {}) do db.run.members[name] = true end
end

-- "<dungeon> has been reset." (the group leader, and members who are outside)
local resetPattern
function ns.OnSystemMessage(msg)
    if type(msg) ~= "string" or not INSTANCE_RESET_SUCCESS then return end
    if not resetPattern then
        resetPattern = "^" .. INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", ".+") .. "$"
    end
    if msg:match(resetPattern) and ns.charDB then ns.charDB.resetSeen = true end
end

-- The current dungeon run ("<map ID>:<run number>"), nil outside.
function ns.GetRun()
    local db = ns.charDB
    if db and db.inDungeon and db.run then
        return tostring(db.run.instance) .. ":" .. tostring(db.run.n)
    end
end

local HISTORY_VERSION = 2

local function SaveHistory()
    if ns.charDB then ns.charDB.history = R:Export() end
end

function ns.ApplyArchiveSize()
    ns.Archive.maxEntries = tonumber(ns.db and ns.db.archiveSize) or ns.DEFAULTS.archiveSize
    ns.Archive:Trim()
    ns.Archive:Fire()
end

-- every finished roll also goes into the long-term history
R:On(function(event, roll)
    if event == "finished" then ns.Archive:Record(roll) end
end)

function ns.ApplyHistorySize()
    R.maxEntries = tonumber(ns.db and ns.db.historySize) or ns.DEFAULTS.historySize
    R:Trim()
    if UI then UI:Refresh() end
end

-- ---------------------------------------------------------------- events

local function OnStartRoll(rollID, rollTime)
    local texture, name, count, quality, bop, canNeed, canGreed, canDisenchant
    if GetLootRollItemInfo then
        texture, name, count, quality, bop, canNeed, canGreed, canDisenchant = GetLootRollItemInfo(rollID)
    end
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    R:Start(rollID, {
        link = link or name, name = name, texture = texture, count = count, quality = quality,
        bop = bop,
        canNeed = canNeed ~= false and canNeed ~= 0,
        canGreed = canGreed ~= false and canGreed ~= 0,
        canDisenchant = canDisenchant and canDisenchant ~= 0 or false,
        duration = (tonumber(rollTime) or 60000) / 1000,
    })
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("CANCEL_LOOT_ROLL")
ev:RegisterEvent("CHAT_MSG_LOOT")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "CHAT_MSG_SYSTEM" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        ForeverLootRollsDB = ForeverLootRollsDB or {}
        -- "fold in X s after everyone has rolled" became the default; test builds
        -- had already stored the old default ("when the next roll starts")
        if (ForeverLootRollsDB.settingsVersion or 1) < 2 then
            if ForeverLootRollsDB.collapseMode == "newroll" then ForeverLootRollsDB.collapseMode = nil end
            ForeverLootRollsDB.settingsVersion = 2
        end
        -- open / close settings split into "dungeons and raids" and "open world"
        if ForeverLootRollsDB.settingsVersion < 3 then
            local db = ForeverLootRollsDB
            if db.autoOpen ~= nil then
                db.dungeonAutoOpen = db.autoOpen
                db.worldAutoOpen = db.autoOpen and not db.onlyInInstance
            end
            if db.autoClose ~= nil then db.worldAutoClose = db.autoClose end
            if db.keepOpenInInstance ~= nil then
                db.openOnEnterDungeon = db.keepOpenInInstance
                db.dungeonAutoClose = db.autoClose and not db.keepOpenInInstance
            end
            if db.closeDelay then db.worldCloseDelay, db.dungeonCloseDelay = db.closeDelay, db.closeDelay end
            db.autoOpen, db.onlyInInstance, db.keepOpenInInstance, db.autoClose, db.closeDelay = nil, nil, nil, nil, nil
            db.settingsVersion = 3
        end
        -- new defaults: do not open on entering, close after X s in dungeons too
        if ForeverLootRollsDB.settingsVersion < 4 then
            local db = ForeverLootRollsDB
            if db.openOnEnterDungeon == true then db.openOnEnterDungeon = nil end
            if db.dungeonAutoClose == false then db.dungeonAutoClose = nil end
            db.settingsVersion = 4
        end
        -- opacity now means background opacity (100 = solid black); the first
        -- version stored 100 as its default
        if ForeverLootRollsDB.settingsVersion < 5 then
            if ForeverLootRollsDB.opacity == 100 then ForeverLootRollsDB.opacity = nil end
            ForeverLootRollsDB.settingsVersion = 5
        end
        -- the native Forever look is meant to be fully opaque: 70 (the previous
        -- default) becomes the new default of 100
        if ForeverLootRollsDB.settingsVersion < 6 then
            if ForeverLootRollsDB.opacity == 70 then ForeverLootRollsDB.opacity = nil end
            ForeverLootRollsDB.settingsVersion = 6
        end
        ApplyDefaults(ForeverLootRollsDB, ns.DEFAULTS)
        ns.db = ForeverLootRollsDB
        ForeverLootRollsCharDB = ForeverLootRollsCharDB or {}
        ns.charDB = ForeverLootRollsCharDB
        R.maxEntries = tonumber(ns.db.historySize) or ns.DEFAULTS.historySize
        -- history from 0.1.0 test builds was read with the wrong argument order
        if ns.charDB.version ~= HISTORY_VERSION then
            ns.charDB.history = nil
            ns.charDB.version = HISTORY_VERSION
        end
        R:Import(ns.charDB.history)
        ns.charDB.archive = ns.charDB.archive or {}
        ns.Archive.maxEntries = tonumber(ns.db.archiveSize) or ns.DEFAULTS.archiveSize
        ns.Archive:Attach(ns.charDB.archive)
        P.Build()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        local dungeon = ns.InDungeon()
        ns.OnDungeonChange(dungeon, isLogin or isReload)
        UI:OnZoneChanged(dungeon)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.OnGroupChanged()
    elseif event == "CHAT_MSG_SYSTEM" then
        ns.OnSystemMessage((...))
    elseif event == "PLAYER_LOGOUT" then
        SaveHistory()
    elseif event == "START_LOOT_ROLL" then
        OnStartRoll(...)
    elseif event == "CANCEL_LOOT_ROLL" then
        R:Close((...))
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        local parsed = P.Parse(msg)
        -- keep the last raw roll messages (SavedVariables) to check new client texts
        if ns.charDB and type(msg) == "string" and (parsed or msg:find("lootHistory", 1, true)) then
            local log = ns.charDB.rawLog or {}
            ns.charDB.rawLog = log
            log[#log + 1] = (parsed and "" or "UNPARSED ") .. msg
            while #log > 40 do table.remove(log, 1) end
        end
        if parsed then
            local roll = R:Apply(parsed)
            if roll and parsed.self and parsed.kind == "choice" then HideBlizzardRollFrame(roll.id) end
        end
    end
end)

-- ---------------------------------------------------------------- slash commands

SLASH_FOREVERLOOTROLLS1 = "/lootrolls"
SLASH_FOREVERLOOTROLLS2 = "/flr"
SlashCmdList.FOREVERLOOTROLLS = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" or cmd == "show" or cmd == "toggle" then
        UI:Toggle()
    elseif cmd == "test" or cmd == "demo" then
        ns.Print(L.demoStarted)
        ns.Demo:Start()
    elseif cmd == "history" or cmd == "verlauf" or cmd == "log" then
        ns.HistoryUI:Toggle()
    elseif cmd == "clear" then
        R:ClearFinished()
        ns.Print(L.cleared)
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.OpenOptions()
    else
        ns.Print(L.slashHelp)
    end
end

-- ---------------------------------------------------------------- addon compartment

function ForeverLootRolls_OnAddonCompartmentClick()
    UI:Toggle()
end

function ForeverLootRolls_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText(L.title)
    GameTooltip:AddLine("/lootrolls", 1, 1, 1)
    GameTooltip:Show()
end

function ForeverLootRolls_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
