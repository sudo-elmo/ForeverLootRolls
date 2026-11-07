-- Long-term loot history: every finished roll, kept per character in
-- SavedVariables. Clearing the roll window or entering a new dungeon does not
-- touch it. Pure Lua; the window for it lives in HistoryUI.lua.
local _, ns = ...
local A = { maxEntries = 1000, collapsed = {}, expanded = {}, listeners = {} }
ns.Archive = A

A.RUN_GAP = 2 * 60 * 60   -- a pause this long (seconds) starts a new visit

local function Me() return ns.PlayerName and ns.PlayerName() or "" end

function A:On(fn)
    self.listeners[#self.listeners + 1] = fn
end

function A:Fire()
    for _, fn in ipairs(self.listeners) do
        local ok, err = pcall(fn)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- list: the saved table (oldest first)
function A:Attach(list)
    self.list = list
    self:Trim()
end

function A:Trim()
    if not self.list then return end
    local limit = math.max(tonumber(self.maxEntries) or 1000, 1)
    while #self.list > limit do table.remove(self.list, 1) end
end

-- Adds a finished roll, or updates its entry (a late result replacing "?").
function A:Record(roll)
    if not self.list or roll.demo or roll.restored or not roll.link then return end
    local e = roll.archiveEntry
    if not e then
        e = {}
        roll.archiveEntry = e
        self.list[#self.list + 1] = e
        self:Trim()
    end
    e.link, e.texture, e.count = roll.link, roll.texture, roll.count
    e.quality = roll.quality or A.QualityOf(e)
    e.ts = roll.ts
    e.zone, e.zoneType = roll.zone, roll.zoneType
    e.run = roll.run
    e.result, e.winner = roll.result, roll.winner
    local players = {}
    for _, name in ipairs(roll.playerOrder) do
        local p = roll.players[name]
        players[#players + 1] = { name = p.name, class = p.class, choice = p.choice, roll = p.roll, winner = p.winner }
    end
    e.players = players
    self:Fire()
end

function A:Clear()
    if not self.list then return end
    for i = #self.list, 1, -1 do self.list[i] = nil end
    self:Fire()
end

-- Item quality (0 grey … 5 orange) from the entry or its link colour.
local HEX_QUALITY = {
    ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6,
}
function A.QualityOf(e)
    if e.quality then return e.quality end
    local link = e.link or ""
    local q = tonumber(link:match("|cnIQ(%d+):") or "")
    if q then return q end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    return hex and HEX_QUALITY[hex:lower()] or nil
end

function A.IsMine(e)
    return e.result == "won" and e.winner == Me()
end

function A.WinnerOf(e)
    if e.result ~= "won" or not e.players then return nil end
    for _, p in ipairs(e.players) do
        if p.name == e.winner then return p end
    end
    return { name = e.winner }
end

-- Still the same group? At least half of the smaller group is in both.
-- Takes sets ({ name = true }) or lists of player tables ({ name = ... });
-- our own name does not count.
function A.SameGroup(a, b)
    local me = Me()
    local function Set(t)
        local s, n = {}, 0
        for k, v in pairs(t or {}) do
            local name = (v == true and k) or (type(v) == "table" and v.name) or nil
            if type(name) == "string" and name ~= me and not s[name] then s[name] = true n = n + 1 end
        end
        return s, n
    end
    local sa, na = Set(a)
    local sb, nb = Set(b)
    if na == 0 and nb == 0 then return true end
    if na == 0 or nb == 0 then return false end
    local both = 0
    for name in pairs(sa) do if sb[name] then both = both + 1 end end
    return both * 2 >= math.min(na, nb)
end

local function HasOthers(players)
    local me = Me()
    for _, p in ipairs(players or {}) do
        if p.name and p.name ~= me then return true end
    end
    return false
end

-- Flat list of rows for the window, newest first:
--   { kind = "group", id, zone, zoneType, from, to, count, collapsed }
--   { kind = "item", entry }
-- A group is one visit: one dungeon run where the run is known, else the same
-- place with the same group and without a long pause in between.
function A:Rows(onlyMine, minQuality)
    local rows, group = {}, nil
    local list = self.list or {}
    local prevTs
    local function Close()
        if group and group.count == 0 then
            -- nothing left after filtering: drop the empty header
            for i = #rows, 1, -1 do
                if rows[i] == group then table.remove(rows, i) break end
            end
        end
    end
    for i = #list, 1, -1 do
        local e = list[i]
        local zone = e.zone or "?"
        local ts = e.ts or 0
        -- one group per visit: per dungeon run where the run is known, else per
        -- place and group without a long pause (rolls of a solo player or
        -- with no one else listed say nothing about the group)
        local newRun
        if not group or group.zone ~= zone then
            newRun = true
        elseif e.run or group.run then
            newRun = e.run ~= group.run
        else
            newRun = (prevTs and prevTs - ts > A.RUN_GAP)
                or (group.players and HasOthers(e.players) and not A.SameGroup(group.players, e.players))
        end
        if newRun then
            Close()
            group = { kind = "group", zone = zone, zoneType = e.zoneType, run = e.run,
                from = ts, to = ts, count = 0 }
            rows[#rows + 1] = group
        end
        if not group.players and HasOthers(e.players) then group.players = e.players end
        group.from = ts
        prevTs = ts
        local q = A.QualityOf(e)
        local qualityOk = not minQuality or minQuality <= 0 or (q and q >= minQuality)
        if (not onlyMine or A.IsMine(e)) and qualityOk then
            group.count = group.count + 1
            group.id = zone .. "@" .. tostring(group.to)
            if not self.collapsed[group.id] then
                rows[#rows + 1] = { kind = "item", entry = e, expanded = self.expanded[e] and true or false }
                if self.expanded[e] then
                    for i, p in ipairs(A.SortedPlayers(e)) do
                        rows[#rows + 1] = { kind = "player", entry = e, player = p, index = i }
                    end
                end
            end
        end
    end
    Close()
    for _, r in ipairs(rows) do
        if r.kind == "group" then
            r.id = r.zone .. "@" .. tostring(r.to)
            r.collapsed = self.collapsed[r.id] and true or false
        end
    end
    return rows
end

local RANK = { need = 1, greed = 2, disenchant = 3, pass = 4 }

-- Winner first, then Need, Greed, Disenchant, Pass; highest roll first.
function A.SortedPlayers(e)
    local out = {}
    for _, p in ipairs(e.players or {}) do out[#out + 1] = p end
    table.sort(out, function(a, b)
        local ra = a.winner and 0 or RANK[a.choice] or 9
        local rb = b.winner and 0 or RANK[b.choice] or 9
        if ra ~= rb then return ra < rb end
        local na, nb = a.roll or -1, b.roll or -1
        if na ~= nb then return na > nb end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Shows or hides every player's roll under an item.
function A:ToggleEntry(e)
    self.expanded[e] = not self.expanded[e] or nil
end

function A:Toggle(groupId)
    self.collapsed[groupId] = not self.collapsed[groupId] or nil
end
