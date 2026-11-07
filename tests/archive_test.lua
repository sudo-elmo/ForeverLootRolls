-- Offline test for the long-term loot history (Archive.lua).
-- Run from the addon folder:  lua5.1 tests/archive_test.lua .
local dir = arg[1] or "."
local fails, checks = 0, 0
local function eq(a, b, msg)
    checks = checks + 1
    if a ~= b then fails = fails + 1 print("FAIL", msg, tostring(a), tostring(b)) end
end

local ns = {}
local clock, zone, kind = 1000000, "Die Todesminen", "party"
ns.Now = function() return clock end
ns.Clock = function() return clock end
ns.PlayerName = function() return "Me" end
ns.GetZone = function() return zone, kind end
ns.GetRoster = function() return { { name = "Me" }, { name = "Tank" } } end
loadfile(dir .. "/Rolls.lua")("ForeverLootRolls", ns)
loadfile(dir .. "/Archive.lua")("ForeverLootRolls", ns)
local R, A = ns.Rolls, ns.Archive
R:On(function(event, roll) if event == "finished" then A:Record(roll) end end)

local saved = {}
A:Attach(saved)
local function Link(id, name) return ("|cnIQ2:|Hitem:%d::::|h[%s]|h|r"):format(id, name) end

local function Drop(id, name, winner)
    local roll = R:Start(id, { link = Link(id, name) })
    if winner then
        R:Apply({ kind = "won", player = winner, item = roll.link, self = winner == "Me" })
    else
        R:Apply({ kind = "allpassed", item = roll.link })
    end
    clock = clock + 60
    return roll
end

Drop(1, "Schwert", "Tank")
Drop(2, "Ring", "Me")
zone, kind = "Westfall", "none"
Drop(3, "Leinen", nil)
zone, kind = "Die Todesminen", "party"
Drop(4, "Helm", "Me")
eq(#saved, 4, "all finished rolls archived")
eq(saved[1].zone, "Die Todesminen", "zone stored"); eq(saved[1].zoneType, "party", "zone type stored")

-- clearing the roll window does not touch the history
R:ClearFinished()
eq(#saved, 4, "clearing the window keeps the history")

-- newest first, one group per visit
local rows = A:Rows(false)
eq(rows[1].kind, "group", "starts with a group"); eq(rows[1].zone, "Die Todesminen", "newest visit first")
eq(rows[2].entry.link:match("%[(.-)%]"), "Helm", "newest item first")
eq(rows[3].zone, "Westfall", "zone change starts a new group")
eq(rows[5].zone, "Die Todesminen", "first visit is its own group")
eq(rows[5].count, 2, "group count"); eq(rows[6].entry.link:match("%[(.-)%]"), "Ring", "older items below")

-- a long pause in the same place is a new visit
clock = clock + A.RUN_GAP + 1
Drop(5, "Stiefel", "Tank")
rows = A:Rows(false)
eq(rows[1].count, 1, "new visit after a long pause"); eq(rows[3].kind, "group", "old visit separate")

-- only my wins
rows = A:Rows(true)
local items, groups = 0, 0
for _, r in ipairs(rows) do
    if r.kind == "item" then items = items + 1; eq(A.IsMine(r.entry), true, "filter keeps only my wins") end
    if r.kind == "group" then groups = groups + 1 end
end
eq(items, 2, "two of my wins"); eq(groups, 2, "empty groups dropped by the filter")

-- dungeon runs: the same dungeon twice in a row = two groups; one run with a
-- long break = one group
do
    local list = {}
    local A2 = setmetatable({ list = list, collapsed = {}, expanded = {}, listeners = {} }, { __index = A })
    local function E(ts, run) return { link = "|cnIQ2:|Hitem:1::::|h[X]|h|r", ts = ts, zone = "Höhlen des Wehklagens",
        zoneType = "party", run = run, result = "allpassed", players = {} } end
    list[1] = E(1000, "43:1111"); list[2] = E(1100, "43:1111")
    list[3] = E(1200, "43:2222"); list[4] = E(1200 + A.RUN_GAP + 500, "43:2222")
    local groups = {}
    for _, r in ipairs(A2:Rows(false)) do if r.kind == "group" then groups[#groups + 1] = r end end
    eq(#groups, 2, "two runs of the same dungeon = two groups")
    eq(groups[1].count, 2, "one run with a long break stays one group")
    eq(groups[2].count, 2, "first run")
end

-- quality filter: the drops are green (|cnIQ2), so "from rare" hides them all
eq(A.QualityOf(saved[1]), 2, "quality read from the link")
eq(A.QualityOf({ link = "|cffa335ee|Hitem:1::::|h[Epic]|h|r" }), 4, "quality from an old-style colour")
local function CountItems(r) local n = 0 for _, x in ipairs(r) do if x.kind == "item" then n = n + 1 end end return n end
eq(CountItems(A:Rows(false, 2)), CountItems(A:Rows(false, 0)), "from uncommon keeps green")
eq(CountItems(A:Rows(false, 3)), 0, "from rare drops green")
eq(#A:Rows(false, 3), 0, "and their empty groups")

-- folding a group in
rows = A:Rows(false)
A:Toggle(rows[3].id)
local folded = A:Rows(false)
eq(folded[3].collapsed, true, "group folded"); eq(folded[4].kind, "group", "its items are hidden")
A:Toggle(rows[3].id)

-- clicking an item shows every player's roll below it
rows = A:Rows(false)
local first = rows[2].entry
A:ToggleEntry(first)
rows = A:Rows(false)
eq(rows[2].expanded, true, "item opened")
eq(rows[3].kind, "player", "player rows below the item")
eq(rows[3].player.winner, true, "winner first")
A:ToggleEntry(first)
eq(A:Rows(false)[3].kind ~= "player", true, "closed again")

-- a late result replaces "?" in the same entry
local late = R:Start(6, { link = Link(6, "Umhang") })
clock = clock + 200
R:Tick()
eq(saved[#saved].result, "unknown", "gave up -> archived as unknown")
local n = #saved
R:Apply({ kind = "won", player = "Tank", item = late.link })
eq(#saved, n, "late result updates, no duplicate"); eq(saved[#saved].winner, "Tank", "late winner stored")

-- demo rolls stay out
R:Start("demo1", { link = Link(7, "Demo"), demo = true })
R:Apply({ kind = "allpassed", item = Link(7, "Demo") })
eq(#saved, n, "demo rolls not archived")

-- limit
A.maxEntries = 3
A:Trim()
eq(#saved, 3, "trimmed to the limit"); eq(saved[3].winner, "Tank", "newest kept")
A:Clear()
eq(#saved, 0, "clear")

print(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
