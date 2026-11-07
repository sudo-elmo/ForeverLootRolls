-- Roll bookkeeping: one entry per item that is rolled on, with every player's
-- choice, roll and the winner. Pure Lua; the WoW glue lives in Core.lua.
local _, ns = ...
local R = { list = {}, byId = {}, listeners = {}, seq = 0 }
ns.Rolls = R

R.RESULT_TIMEOUT = 15   -- seconds to wait for the result after the roll time is up
R.maxEntries = 30

R.CHOICE_RANK = { need = 1, greed = 2, disenchant = 3, pass = 4 }

local function Now() return ns.Now and ns.Now() or 0 end
local function Clock() return ns.Clock and ns.Clock() or 0 end
local function Me() return ns.PlayerName and ns.PlayerName() or "" end
local function Short(name) return ns.ShortName and ns.ShortName(name) or name end

-- ---------------------------------------------------------------- events

function R:On(fn)
    self.listeners[#self.listeners + 1] = fn
end

function R:Fire(event, roll)
    for _, fn in ipairs(self.listeners) do
        local ok, err = pcall(fn, event, roll)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- ---------------------------------------------------------------- helpers

-- Same item = same item ID; the rest of an item link can differ between the
-- roll frame and the chat message.
function R.ItemKey(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%-?%d+)")
    if id then return "i" .. id end
    return "n" .. (link:match("%[(.-)%]") or link)
end

function R.ItemName(link)
    return type(link) == "string" and link:match("%[(.-)%]") or link
end

local function AddPlayer(roll, name, class)
    local p = roll.players[name]
    if not p then
        p = { name = name }
        roll.players[name] = p
        roll.playerOrder[#roll.playerOrder + 1] = name
    end
    if class and not p.class then p.class = class end
    return p
end

local function AddRoster(roll)
    local roster = ns.GetRoster and ns.GetRoster()
    if not roster then return end
    for _, m in ipairs(roster) do AddPlayer(roll, m.name, m.class) end
end

function R:Trim()
    local limit = math.max(self.maxEntries or 30, 1)
    local i = 1
    while #self.list > limit and i <= #self.list do
        local r = self.list[i]
        if r.done then
            table.remove(self.list, i)
            if r.id ~= nil and self.byId[r.id] == r then self.byId[r.id] = nil end
        else
            i = i + 1
        end
    end
end

local function NewRoll(self, fields)
    local roll = {
        players = {}, playerOrder = {},
        startedAt = Now(), ts = Clock(),
    }
    for k, v in pairs(fields) do roll[k] = v end
    roll.key = roll.key or R.ItemKey(roll.link)
    if ns.GetZone and not roll.zone then roll.zone, roll.zoneType = ns.GetZone() end
    -- which copy of the dungeon (instance run), if known
    if ns.GetRun and not roll.run then roll.run = ns.GetRun() end
    self.list[#self.list + 1] = roll
    if roll.id ~= nil then self.byId[roll.id] = roll end
    self:Trim()
    return roll
end

function R:Get(id)
    return self.byId[id]
end

-- Oldest open roll on that item (that matches pred, if given).
function R:FindOpen(key, pred)
    for _, r in ipairs(self.list) do
        if r.key == key and not r.done and (not pred or pred(r)) then return r end
    end
end

-- A chat message about an item we never saw a roll start for
-- (e.g. a roll you were not part of, or after a /reload).
function R:FromChat(link)
    self.seq = self.seq + 1
    local roll = NewRoll(self, {
        id = "chat" .. self.seq, link = link, fromChat = true,
        endsAt = Now() + 60,
    })
    if ns.ItemIcon then roll.texture = ns.ItemIcon(link) end
    roll.quality = tonumber(link:match("|cnIQ(%d+):") or "")
    AddRoster(roll)
    self:Fire("started", roll)
    return roll
end

function R:Finish(roll, result)
    -- a result that comes in after we gave up still counts
    if roll.done and roll.result ~= "unknown" then return end
    roll.done = true
    roll.result = result
    roll.finishedAt = Now()
    self:Fire("finished", roll)
end

-- ---------------------------------------------------------------- inputs

-- info: link, name, texture, count, quality, bop, canNeed, canGreed,
--       canDisenchant, duration (seconds)
function R:Start(id, info)
    local roll = self.byId[id]
    if roll and not roll.done then return roll end
    info = info or {}
    roll = NewRoll(self, {
        id = id, link = info.link, name = info.name, texture = info.texture,
        count = info.count, quality = info.quality, bop = info.bop,
        canNeed = info.canNeed, canGreed = info.canGreed,
        canDisenchant = info.canDisenchant,
        duration = info.duration or 60,
        demo = info.demo,
    })
    roll.endsAt = roll.startedAt + roll.duration
    if info.roster then
        for _, m in ipairs(info.roster) do AddPlayer(roll, m.name, m.class) end
    else
        AddRoster(roll)
    end
    self:Fire("started", roll)
    return roll
end

-- CANCEL_LOOT_ROLL: our own roll frame is gone – we chose, or time ran out.
-- The others may still be choosing, so this does not end the roll.
function R:Close(id)
    local roll = self.byId[id]
    if not roll or roll.done or roll.closed then return end
    roll.closed = true
    roll.closedAt = Now()
    self:Fire("changed", roll)
end

-- Your own choice, made in this window or in Blizzard's roll frame.
function R:SetMyChoice(id, choice)
    local roll = self.byId[id]
    if not roll or roll.done then return end
    local p = AddPlayer(roll, Me())
    p.choice = p.choice or choice
    roll.myChoice = choice
    self:Fire("changed", roll)
end

-- ev: result of ns.Parser.Parse
function R:Apply(ev)
    if not ev or not ev.item then return end
    local key = R.ItemKey(ev.item)
    local name = ev.self and Me() or (ev.player and Short(ev.player))
    if not name and ev.kind ~= "allpassed" then return end
    local history = ev.history

    -- The loot history ID (newer clients) names the exact drop. Without it,
    -- or before we have seen it, fall back to the oldest open roll on that item.
    local exact
    if history then
        for _, r in ipairs(self.list) do
            if r.historyId == history then exact = r break end
        end
    end
    local function Find(pred)
        if exact then return exact end
        return self:FindOpen(key, function(r)
            if history and r.historyId and r.historyId ~= history then return false end
            return not pred or pred(r)
        end)
    end
    -- the newest roll on that item we gave up on ("unknown"), if any
    local function GaveUp()
        for i = #self.list, 1, -1 do
            local r = self.list[i]
            if r.key == key and r.result == "unknown"
                and (not history or not r.historyId or r.historyId == history) then
                return r
            end
        end
    end
    local function Pick(...)
        local roll = Find(...) or Find() or GaveUp() or self:FromChat(ev.item)
        if history and not roll.historyId then roll.historyId = history end
        return roll
    end

    local roll
    if ev.kind == "choice" then
        roll = Pick(function(r)
            local p = r.players[name]
            return not (p and p.choice)
        end)
        local p = AddPlayer(roll, name)
        p.choice = ev.choice
        if name == Me() then roll.myChoice = ev.choice end

    elseif ev.kind == "roll" then
        roll = Find(function(r)
                local p = r.players[name]
                return p and p.choice == ev.choice and not p.roll
            end)
        if not roll then
            roll = Pick(function(r)
                local p = r.players[name]
                return not (p and p.roll)
            end)
        elseif history and not roll.historyId then
            roll.historyId = history
        end
        local p = AddPlayer(roll, name)
        p.choice = p.choice or ev.choice
        p.roll = ev.roll

    elseif ev.kind == "won" then
        roll = Pick(function(r)
            local p = r.players[name]
            return p and p.choice and p.choice ~= "pass"
        end)
        local p = AddPlayer(roll, name)
        p.winner = true
        if ev.roll then p.roll = p.roll or ev.roll end
        if ev.choice then p.choice = p.choice or ev.choice end
        roll.winner = name
        self:Finish(roll, "won")
        return roll

    elseif ev.kind == "allpassed" then
        roll = Pick()
        for _, p in pairs(roll.players) do p.choice = p.choice or "pass" end
        self:Finish(roll, "allpassed")
        return roll
    else
        return
    end

    self:Fire("changed", roll)
    return roll
end

-- Gives up on rolls whose result never came (left the group, /reload, ...).
function R:Tick()
    local t = Now()
    for _, r in ipairs(self.list) do
        if not r.done then
            if r.endsAt and t > r.endsAt + R.RESULT_TIMEOUT then self:Finish(r, "unknown") end
        end
    end
end

-- ---------------------------------------------------------------- queries

function R:ActiveCount()
    local n = 0
    for _, r in ipairs(self.list) do
        if not r.done then n = n + 1 end
    end
    return n
end

function R.Remaining(roll)
    if roll.done or not roll.endsAt then return 0 end
    return math.max(0, roll.endsAt - Now())
end

function R.CanRoll(roll)
    if roll.done or roll.closed or roll.fromChat or roll.myChoice then return false end
    local me = roll.players[Me()]
    if me and me.choice then return false end
    return R.Remaining(roll) > 0
end

-- Winner first, then Need, Greed, Disenchant, Pass, still waiting;
-- highest roll first inside each group.
function R.SortedPlayers(roll)
    local out = {}
    for _, name in ipairs(roll.playerOrder) do out[#out + 1] = roll.players[name] end
    table.sort(out, function(a, b)
        local ra = a.winner and 0 or R.CHOICE_RANK[a.choice] or 9
        local rb = b.winner and 0 or R.CHOICE_RANK[b.choice] or 9
        if ra ~= rb then return ra < rb end
        local na, nb = a.roll or -1, b.roll or -1
        if na ~= nb then return na > nb end
        return a.name < b.name
    end)
    return out
end

function R.Counts(roll)
    local c = { need = 0, greed = 0, disenchant = 0, pass = 0, waiting = 0 }
    for _, p in pairs(roll.players) do
        local k = p.choice or "waiting"
        c[k] = (c[k] or 0) + 1
    end
    return c
end

-- ---------------------------------------------------------------- history

-- Finished rolls as plain tables for SavedVariables.
function R:Export()
    local out = {}
    for _, r in ipairs(self.list) do
        if r.done and not r.demo then
            local players = {}
            for _, name in ipairs(r.playerOrder) do
                local p = r.players[name]
                players[#players + 1] = { name = p.name, class = p.class, choice = p.choice,
                    roll = p.roll, winner = p.winner }
            end
            out[#out + 1] = { link = r.link, texture = r.texture, count = r.count,
                ts = r.ts, result = r.result, winner = r.winner, players = players }
        end
    end
    return out
end

function R:Import(saved)
    if type(saved) ~= "table" then return end
    for _, s in ipairs(saved) do
        if type(s) == "table" and s.link then
            self.seq = self.seq + 1
            local roll = NewRoll(self, {
                id = "saved" .. self.seq, link = s.link, texture = s.texture, count = s.count,
                result = s.result or "unknown", winner = s.winner, done = true,
                restored = true, collapsed = true,
            })
            roll.ts = s.ts or 0
            for _, p in ipairs(s.players or {}) do
                if p.name then
                    local np = AddPlayer(roll, p.name, p.class)
                    np.choice, np.roll, np.winner = p.choice, p.roll, p.winner
                end
            end
        end
    end
end

function R:ClearFinished()
    for i = #self.list, 1, -1 do
        local r = self.list[i]
        if r.done then
            table.remove(self.list, i)
            if r.id ~= nil and self.byId[r.id] == r then self.byId[r.id] = nil end
        end
    end
    self:Fire("cleared")
end
