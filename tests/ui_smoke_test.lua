-- Loads the whole addon against a stubbed WoW API and runs the demo, a real
-- roll through events and the window code. Catches nil errors and typos in
-- code paths the pure tests do not reach. It does not check how things look.
-- Run from the addon folder:  lua5.1 tests/ui_smoke_test.lua .
local dir = arg[1] or "."

-- ---------------------------------------------------------------- stubs
local now = 0
local timers = {}
local frames = {}

local function Widget(kind)
    local w = { _kind = kind, _shown = kind ~= "Frame-hidden", _scripts = {}, _points = {} }
    return setmetatable(w, { __index = function(t, k)
        -- unknown methods are no-ops that return nil
        local f = function() end
        rawset(t, k, f)
        return f
    end })
end

local function MakeFrame(kind, name)
    local f = Widget(kind)
    f._shown = true
    f._events = {}
    function f:SetScript(s, fn) self._scripts[s] = fn end
    function f:GetScript(s) return self._scripts[s] end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:Show() local was = self._shown; self._shown = true
        if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
    function f:Hide() local was = self._shown; self._shown = false
        if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
    function f:IsShown() return self._shown end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:IsMouseOver() return false end
    function f:SetupMenu(fn) self._menu = fn end
    function f:SetFrameStrata(v) self._strata = v end
    function f:SetFrameLevel(v) self._level = v end
    function f:SetAlpha(v) self._alpha = v end
    function f:SetBackdropColor(r, g, b, a) self._bgAlpha = a end
    function f:GetFrameLevel() return 1 end
    function f:GetName() return name end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:CreateTexture() local t = Widget("Texture"); return t end
    function f:CreateFontString()
        local fs = Widget("FontString")
        function fs:SetText(v) self._text = v end
        function fs:GetText() return self._text end
        function fs:GetStringHeight() return 12 end
        function fs:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
        return fs
    end
    function f:CreateMaskTexture() return Widget("Mask") end
    function f:GetNormalTexture() return Widget("Texture") end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

CreateFrame = function(kind, name) return MakeFrame(kind, name) end
UIParent = MakeFrame("Frame", "UIParent")
GameTooltip = MakeFrame("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. m) end }
UISpecialFrames = {}
tinsert = table.insert
BackdropTemplateMixin = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
SOUNDKIT = {}
PlaySound = function() end
GetLocale = function() return os.getenv("LOCALE") or "deDE" end
GetTime = function() return now end
time = os.time
date = os.date
UnitName = function(u) if u == "player" then return "Me" end if u == "party1" then return "Tank" end end
UnitClass = function() return "Mage", "MAGE" end
UnitExists = function(u) return u == "player" or u == "party1" end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 1 end
GetNumGroupMembers = function() return 2 end
local inDungeon = false
IsInInstance = function() if inDungeon then return true, "party" end return false, "none" end
UNKNOWNOBJECT = "Unknown"
GetItemInfo = function() return nil end
C_Item = { GetItemIconByID = function() return 134400 end }
C_Timer = { After = function(sec, fn) timers[#timers + 1] = { at = now + sec, fn = fn } end }
SlashCmdList = {}
local handlerErrors = 0
geterrorhandler = function() return function(e) handlerErrors = handlerErrors + 1 print("LUA ERROR", e) end end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
local rolledOn
RollOnLoot = function(id, v) rolledOn = { id, v } end
GetLootRollItemInfo = function() return 133000, "Hand of Justice", 1, 4, true, true, true, false end
GetLootRollItemLink = function() return "|cffa335ee|Hitem:11815::::::::60:::::|h[Hand of Justice]|h|r" end
GetLootRollTimeLeft = function() return 30000 end

-- minimal Settings API: records what the options page registers
local registered = {}
local function Init() return { SetParentInitializer = function(self, parent, fn) self.parent = parent; self.isActive = fn end } end
Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    Default = { True = true, False = false },
    RegisterVerticalLayoutCategory = function(name) return { GetID = function() return 1 end, name = name } end,
    RegisterAddOnSetting = function(_, var, key, tbl, vtype, label, default)
        registered[key] = { vtype = vtype, default = default }
        return { SetValueChangedCallback = function() end }
    end,
    CreateCheckbox = function() return Init() end,
    CreateSlider = function() return Init() end,
    CreateSliderOptions = function() return {} end,
    CreateDropdown = function(_, _, getOptions)
        local opts = getOptions()
        registered._dropdownOptions = #opts
        return Init()
    end,
    CreateControlTextContainer = function()
        local data = {}
        return { Add = function(_, v, l) data[#data + 1] = { value = v, label = l } end,
                 GetData = function() return data end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

StaticPopupDialogs = {}
StaticPopup_Show = function(name) StaticPopupDialogs[name].OnAccept() end
ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0 } }

-- English chat strings
LOOT_ROLL_NEED = "%s has selected Need for: %s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ROLL_WON = "%s won: %s"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s"

local function Advance(sec)
    local target = now + sec
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = timers[1]
        if not t or t.at > target then break end
        table.remove(timers, 1)
        now = t.at
        t.fn()
    end
    now = target
    -- run OnUpdate scripts once
    for _, f in ipairs(frames) do
        if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1) end
    end
end

local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- quest tracker in MEDIUM at level 5: the window must sit just above it
ObjectiveTrackerFrame = { GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 5 end }

-- ---------------------------------------------------------------- load
local ns = {}
local toc = io.open(dir .. "/ForeverLootRolls.toc"):read("*a")
for file in toc:gmatch("\n([%w_]+%.lua)") do
    local chunk = assert(loadfile(dir .. "/" .. file))
    chunk("ForeverLootRolls", ns)
end

local fails = 0
local function eq(a, b, msg) if a ~= b then fails = fails + 1 print("FAIL", msg, tostring(a), tostring(b)) end end

-- stored by a test build: old default + old open/close settings
ForeverLootRollsDB = { collapseMode = "newroll", opacity = 100, autoOpen = true, onlyInInstance = true,
    autoClose = true, keepOpenInInstance = true, closeDelay = 12 }
Fire("ADDON_LOADED", "ForeverLootRolls")
eq(ns.db.collapseMode, "delay", "old stored default moves to the new default")
eq(ns.db.worldAutoOpen, false, "migrated: only in instances -> not in the world")
eq(ns.db.dungeonAutoOpen, true, "migrated: dungeon auto open")
eq(ns.db.openOnEnterDungeon, false, "migrated to the new default: no open on entering")
eq(ns.db.dungeonAutoClose, true, "migrated to the new default: close in dungeons")
eq(ns.db.worldCloseDelay, 12, "migrated: close delay")
eq(ns.db.autoOpen, nil, "old key removed")
eq(ns.db.opacity, 70, "old stored opacity default moves to 70")
ns.db.worldAutoOpen = true
Fire("PLAYER_LOGIN")
eq(ns.db.worldAutoOpen, true, "defaults applied")
eq(ns.db.dungeonAutoClose, true, "dungeon: closes by default")
eq(ns.db.openOnEnterDungeon, false, "dungeon: does not open on entering by default")
eq(registered.collapseMode and registered.collapseMode.vtype, "string", "collapse dropdown registered")
eq(registered._dropdownOptions, 4, "four collapse choices")
eq(registered.collapseDelay and registered.collapseDelay.default, 5, "collapse delay slider")

-- demo opens the window and closes it when everything is done
SlashCmdList.FOREVERLOOTROLLS("test")
local f = _G.ForeverLootRollsFrame
eq(f and f:IsShown(), true, "demo opened the window")
ns.db.opacity = 100
ns.UI:Refresh()
eq(f._bgAlpha, 1, "100 % = solid black background")
ns.db.opacity = 40
ns.UI:Refresh()
eq(f._bgAlpha, 0.4, "lower opacity = see-through background")
eq(rawget(f, "_alpha"), nil, "text and icons are not faded")
ns.db.opacity = 70
eq(f._strata, "MEDIUM", "window in the quest tracker's layer"); eq(f._level, 25, "just above the tracker")
Advance(1)
local demo = ns.Rolls.list[#ns.Rolls.list]
ns.db.rollButtons = true
ns.UI:Roll(demo, { choice = "greed", value = 2 })
for _ = 1, 60 do Advance(1) end
eq(ns.Rolls:ActiveCount(), 0, "demo rolls all finished")
eq(f:IsShown(), false, "window closed itself")

-- real roll through events
Fire("START_LOOT_ROLL", 7, 60000)
eq(f:IsShown(), true, "real roll opened the window")
local block = ns.UI.blocks[1]
eq(block.roll.id, 7, "newest roll on top")
ns.UI:Roll(block.roll, { choice = "need", value = 1 })
eq(rolledOn and rolledOn[1], 7, "RollOnLoot called"); eq(rolledOn and rolledOn[2], 1, "with need")
local link = GetLootRollItemLink(7)
Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. link)
Fire("CHAT_MSG_LOOT", "Tank has selected Need for: " .. link)
Fire("CANCEL_LOOT_ROLL", 7)
Fire("CHAT_MSG_LOOT", "Need Roll - 12 for " .. link .. " by Tank")
Fire("CHAT_MSG_LOOT", "Need Roll - 99 for " .. link .. " by Me")
Fire("CHAT_MSG_LOOT", "You won: " .. link)
eq(ns.Rolls:Get(7).winner, "Me", "winner from chat")
Advance(30)
eq(f:IsShown(), false, "closed after the real roll")

-- manual open stays open
SlashCmdList.FOREVERLOOTROLLS("")
Advance(30)
eq(f:IsShown(), true, "manually opened window stays")

-- toggle collapse via header click, then clear
ns.UI.blocks[1].header._scripts.OnClick(ns.UI.blocks[1].header)
ns.UI.blocks[1].header._scripts.OnEnter(ns.UI.blocks[1].header)
-- with "open when entering" and no auto close: stays open; leaving closes it
ns.db.openOnEnterDungeon = true; ns.db.dungeonAutoClose = false
inDungeon = true
GetInstanceInfo = function() return "Dungeon", "party", 1, "", 5, 0, false, 99 end
f:Hide()
Fire("PLAYER_ENTERING_WORLD")
eq(f:IsShown(), true, "entering a dungeon opens the window")
Fire("START_LOOT_ROLL", 50, 60000)
Fire("CHAT_MSG_LOOT", "Everyone passed on: " .. link)
Advance(60)
eq(f:IsShown(), true, "stays open in the dungeon after all rolls")
ns.db.dungeonAutoClose = true; ns.db.dungeonCloseDelay = 3
Fire("START_LOOT_ROLL", 51, 60000)
Fire("CHAT_MSG_LOOT", "Everyone passed on: " .. link)
Advance(4)
eq(f:IsShown(), false, "dungeon auto close (own setting) closes after 3 s")
ns.db.dungeonAutoClose = false
Fire("PLAYER_ENTERING_WORLD")
eq(f:IsShown(), true, "re-entering opens it again")
inDungeon = false
Fire("PLAYER_ENTERING_WORLD")
eq(f:IsShown(), false, "leaving the dungeon closes it")
inDungeon = true

-- entering a new dungeon clears finished rolls, re-entering the same one does not
local instanceID = 100
GetInstanceInfo = function() return "Dungeon", "party", 1, "", 5, 0, false, instanceID end
Fire("PLAYER_ENTERING_WORLD")
eq(#ns.Rolls.list, 0, "first dungeon clears")
Fire("START_LOOT_ROLL", 8, 60000)
Fire("CHAT_MSG_LOOT", "Everyone passed on: " .. link)
Fire("PLAYER_ENTERING_WORLD")
eq(#ns.Rolls.list, 1, "same dungeon keeps the list")
ns.Rolls.list[1].collapsed = true
ns.UI:Refresh()
eq(ns.UI.blocks[1].winner._text, "|cff808080" .. ns.L.allPassedShort .. "|r", "folded block shows the outcome")
instanceID = 200
ns.db.clearOnNewInstance = false
Fire("PLAYER_ENTERING_WORLD")
eq(#ns.Rolls.list, 1, "option off keeps the list")
-- long list gets a scroll bar instead of a taller window
ns.db.collapseMode = "never"
for id = 40, 47 do
    Fire("START_LOOT_ROLL", id, 60000)
    Fire("CHAT_MSG_LOOT", "Everyone passed on: " .. link)
end
eq(ns.UI.bar:IsShown(), true, "scroll bar shown for a long list")
eq(ns.UI.maxScroll > 0, true, "something to scroll")
ns.UI.scroll._scripts.OnMouseWheel(ns.UI.scroll, -1)
eq(ns.UI.scrollPos > 0, true, "mouse wheel scrolls")
SlashCmdList.FOREVERLOOTROLLS("clear")
eq(ns.UI.bar:IsShown(), false, "no scroll bar for a short list")

-- collapse modes
SlashCmdList.FOREVERLOOTROLLS("clear")
local function FinishOne(id)
    Fire("START_LOOT_ROLL", id, 60000)
    Fire("CHAT_MSG_LOOT", "Everyone passed on: " .. link)
    return ns.Rolls:Get(id)
end
ns.db.collapseMode = "instant"
eq(FinishOne(30).collapsed, true, "instant: folded right away")
ns.db.collapseMode = "delay"; ns.db.collapseDelay = 5
local d = FinishOne(31)
eq(d.collapsed, nil, "delay: still open")
Advance(6)
eq(d.collapsed, true, "delay: folded after 5 s")
ns.db.collapseMode = "never"
local n = FinishOne(32)
FinishOne(33)
eq(n.collapsed, nil, "never: stays open on the next roll")
ns.db.collapseMode = "newroll"
local r1 = FinishOne(34)
eq(r1.collapsed, nil, "newroll: open until the next roll")
FinishOne(35)
eq(r1.collapsed, true, "newroll: folded when the next roll starts")
SlashCmdList.FOREVERLOOTROLLS("clear")
eq(#ns.Rolls.list, 0, "cleared")
-- auto open off everywhere: the window stays shut, but everything is still logged
f:Hide()
inDungeon = false
ns.db.worldAutoOpen, ns.db.dungeonAutoOpen = false, false
local archived = #ForeverLootRollsCharDB.archive
Fire("START_LOOT_ROLL", 90, 60000)
Fire("CHAT_MSG_LOOT", "Tank has selected Need for: " .. link)
Fire("CHAT_MSG_LOOT", "Need Roll - 55 for " .. link .. " by Tank")
Fire("CHAT_MSG_LOOT", "Tank won: " .. link)
eq(f:IsShown(), false, "auto open off: window stays closed")
eq(ns.Rolls:Get(90).winner, "Tank", "auto open off: roll still tracked")
eq(#ForeverLootRollsCharDB.archive, archived + 1, "auto open off: still in the loot history")
SlashCmdList.FOREVERLOOTROLLS("")
eq(ns.UI.blocks[1].roll.id, 90, "opening later shows the roll")
ns.db.worldAutoOpen, ns.db.dungeonAutoOpen = true, true
inDungeon = true

-- loot history: survives "clear", opens from the note button
eq(#ForeverLootRollsCharDB.archive > 0, true, "finished rolls are in the history")
ns.UI.note._scripts.OnEnter(ns.UI.note)
ns.UI.note._scripts.OnClick(ns.UI.note)
local hist = ns.HistoryUI
eq(hist.frame:IsShown(), true, "note opens the history")
eq(hist.frame._bgAlpha, ns.db.opacity / 100, "history uses the same background opacity")
eq(hist.data[1].kind, "group", "history starts with a group")
eq(hist.rows[2].data and hist.rows[2].data.kind, "item", "items listed under the group")
hist.rows[2]._scripts.OnEnter(hist.rows[2])
hist.rows[2]._scripts.OnClick(hist.rows[2])
eq(hist.rows[3].data and hist.rows[3].data.kind, "player", "clicking an item lists all rolls")
hist.rows[3]._scripts.OnEnter(hist.rows[3])
hist.rows[2]._scripts.OnClick(hist.rows[2])
hist.rows[1]._scripts.OnClick(hist.rows[1])
eq(hist.data[1].collapsed, true, "group folds in on click")
hist.rows[1]._scripts.OnClick(hist.rows[1])
hist.view._scripts.OnMouseWheel(hist.view, -1)
eq(hist.qualityDropdown ~= nil, true, "quality filter is a dropdown")
local radios = {}
local root = { CreateRadio = function(_, label, isSelected, setSelected, data)
    radios[#radios + 1] = { label = label, isSelected = isSelected, setSelected = setSelected, data = data }
end }
hist.qualityDropdown._menu(hist.qualityDropdown, root)
eq(#radios, 4, "four quality choices")
eq(radios[1].isSelected(), true, "all qualities selected at first")
radios[3].setSelected()
eq(ns.db.historyMinQuality, 3, "dropdown: from rare")
eq(radios[3].isSelected(), true, "dropdown shows the choice")
radios[1].setSelected()
eq(ns.db.historyMinQuality, 0, "dropdown: back to all")
hist.clearButton._scripts.OnClick(hist.clearButton)
eq(#ForeverLootRollsCharDB.archive, 0, "delete history (after confirming)")
eq(hist.empty and hist.data and #hist.data, 0, "history window empty")
SlashCmdList.FOREVERLOOTROLLS("history")
eq(hist.frame:IsShown(), false, "slash command toggles the history")
ns.UI.gear._scripts.OnEnter(ns.UI.gear)
ns.UI.gear._scripts.OnClick(ns.UI.gear)
-- out of combat the gear opens Blizzard's settings, in combat it only says no
local opened, errors = 0, {}
Settings.OpenToCategory = function() opened = opened + 1 end
UIErrorsFrame = { AddMessage = function(_, m) errors[#errors + 1] = m end }
ERR_NOT_IN_COMBAT = "Das geht nicht im Kampf."
InCombatLockdown = function() return false end
ns.UI.gear._scripts.OnClick(ns.UI.gear)
eq(opened, 1, "gear opens the settings out of combat")
InCombatLockdown = function() return true end
ns.UI.gear._scripts.OnClick(ns.UI.gear)
eq(opened, 1, "no settings call in combat")
eq(errors[1], ERR_NOT_IN_COMBAT, "combat message shown")
InCombatLockdown = function() return false end
SlashCmdList.FOREVERLOOTROLLS("help")

Fire("PLAYER_LOGOUT")
eq(type(ForeverLootRollsCharDB.history), "table", "history saved")

fails = fails + handlerErrors
print(fails == 0 and "ui smoke test ok" or ("ui smoke test: " .. fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
