-- Offline test for the chat parser and the roll bookkeeping (no WoW client needed).
-- Run from the addon folder:  lua5.1 tests/rolls_test.lua .
local dir = arg[1] or "."
local fails, checks = 0, 0
local function eq(a, b, msg)
    checks = checks + 1
    if a ~= b then fails = fails + 1 print("FAIL", msg, tostring(a), tostring(b)) end
end

-- English client strings (as in GlobalStrings.lua)
local G = {
    LOOT_ROLL_NEED = "%s has selected Need for: %s",
    LOOT_ROLL_GREED = "%s has selected Greed for: %s",
    LOOT_ROLL_PASSED = "%s passed on: %s",
    LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item.",
    LOOT_ROLL_PASSED_AUTO_FEMALE = "%s automatically passed on: %s because she cannot loot that item.",
    LOOT_ROLL_NEED_SELF = "You have selected Need for: %s",
    LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s",
    LOOT_ROLL_PASSED_SELF = "You passed on: %s",
    LOOT_ROLL_PASSED_SELF_AUTO = "You automatically passed on: %s because you cannot loot that item.",
    LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s",
    LOOT_ROLL_WON = "%s won: %s",
    LOOT_ROLL_YOU_WON = "You won: %s",
    LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s",
}

local ns = {}
local now = 100
ns.Now = function() return now end
ns.Clock = function() return 1700000000 end
ns.PlayerName = function() return "Me" end
ns.ShortName = function(n) return (n:gsub("%-.*$", "")) end
ns.GetRoster = function()
    return { { name = "Me", class = "MAGE" }, { name = "Tank", class = "WARRIOR" },
             { name = "Heal", class = "PRIEST" } }
end
loadfile(dir .. "/Parser.lua")("ForeverLootRolls", ns)
loadfile(dir .. "/Rolls.lua")("ForeverLootRolls", ns)
local P, R = ns.Parser, ns.Rolls
P.Build(G)

local HOJ = "|cffa335ee|Hitem:11815::::::::60:::::|h[Hand of Justice]|h|r"
local HOJ_CHAT = "|cffa335ee|Hitem:11815::::::::60::::1:|h[Hand of Justice]|h|r"
local GEM = "|cff1eff00|Hitem:7909::::::::60:::::|h[Aquamarine]|h|r"

-- ------------------------------------------------ compile
local pat, order = P.Compile("%2$s – %1$d (50%%)")
eq(pat, "^(.-) – (%-?%d+) %(50%%%)$", "compile positional pattern")
eq(order[1].conv, "s", "capture 1 is text")
eq(order[2].conv, "d", "capture 2 is a number")

-- ------------------------------------------------ parse
local e = P.Parse("Tank has selected Need for: " .. HOJ)
eq(e.kind, "choice", "need kind"); eq(e.choice, "need", "need choice")
eq(e.player, "Tank", "need player"); eq(e.item, HOJ, "need item")

e = P.Parse("Heal automatically passed on: " .. HOJ .. " because she cannot loot that item.")
eq(e.choice, "pass", "auto pass"); eq(e.player, "Heal", "auto pass player (not 'Heal automatically')")

e = P.Parse("You passed on: " .. GEM)
eq(e.self, true, "self pass"); eq(e.choice, "pass", "self pass choice")

e = P.Parse("Need Roll - 87 for " .. HOJ .. " by Tank")
eq(e.kind, "roll", "roll kind"); eq(e.roll, 87, "roll value"); eq(e.player, "Tank", "roll player")

e = P.Parse("You won: " .. HOJ .. " x2")
eq(e.kind, "won", "you won"); eq(e.self, true, "you won self"); eq(e.item, HOJ, "link without ' x2'")

e = P.Parse("Tank-Forever won: " .. HOJ)
eq(e.player, "Tank-Forever", "won player")

eq(P.Parse("Brakk receives loot: " .. HOJ), nil, "unrelated loot message")

-- German-style positional format still maps args correctly
local DE = { LOOT_ROLL_ROLLED_NEED = "Bedarfswurf: %1$d für %2$s von %3$s" }
P.Build(DE)
e = P.Parse("Bedarfswurf: 42 für " .. GEM .. " von Heal")
eq(e.roll, 42, "de roll"); eq(e.player, "Heal", "de player"); eq(e.item, GEM, "de item")
local DE2 = { LOOT_ROLL_WON = "%2$s wurde gewonnen von %1$s" }
P.Build(DE2)
e = P.Parse(GEM .. " wurde gewonnen von Tank")
eq(e.player, "Tank", "swapped order player"); eq(e.item, GEM, "swapped order item")
P.Build(G)

-- ------------------------------------------------ a full roll
local events = {}
R:On(function(ev) events[#events + 1] = ev end)

local r = R:Start(1, { link = HOJ, duration = 60, canNeed = true, canGreed = true })
eq(#r.playerOrder, 3, "roster added")
eq(R:ActiveCount(), 1, "one active")
eq(R.CanRoll(r), true, "can roll")

R:Apply(P.Parse("Tank has selected Need for: " .. HOJ_CHAT))
R:Apply(P.Parse("Heal has selected Greed for: " .. HOJ_CHAT))
R:Apply(P.Parse("You have selected Need for: " .. HOJ_CHAT))
eq(r.players.Tank.choice, "need", "tank need (link differs, same item id)")
eq(r.players.Me.choice, "need", "my need")
eq(R.CanRoll(r), false, "no buttons after choosing")
local c = R.Counts(r)
eq(c.need, 2, "count need"); eq(c.greed, 1, "count greed"); eq(c.waiting, 0, "count waiting")

R:Close(1)
eq(r.closed, true, "closed")
R:Apply(P.Parse("Need Roll - 34 for " .. HOJ_CHAT .. " by Tank"))
R:Apply(P.Parse("Need Roll - 91 for " .. HOJ_CHAT .. " by Me"))
R:Apply(P.Parse("You won: " .. HOJ_CHAT))
eq(r.done, true, "done"); eq(r.result, "won", "result won"); eq(r.winner, "Me", "winner me")
eq(R:ActiveCount(), 0, "none active")
local sorted = R.SortedPlayers(r)
eq(sorted[1].name, "Me", "winner first"); eq(sorted[2].name, "Tank", "need second"); eq(sorted[3].name, "Heal", "greed last")

-- ------------------------------------------------ two identical items at once
local a = R:Start(2, { link = GEM, duration = 60 })
local b = R:Start(3, { link = GEM, duration = 60 })
R:Apply(P.Parse("Tank has selected Greed for: " .. GEM))
R:Apply(P.Parse("Tank has selected Pass for: " .. GEM)) -- not a real string: ignored
R:Apply(P.Parse("Tank passed on: " .. GEM))
eq(a.players.Tank.choice, "greed", "first copy gets first choice")
eq(b.players.Tank.choice, "pass", "second copy gets second choice")
R:Apply(P.Parse("Greed Roll - 50 for " .. GEM .. " by Tank"))
eq(a.players.Tank.roll, 50, "greed roll lands on the copy tank greeded")
R:Apply(P.Parse("Tank won: " .. GEM))
eq(a.done, true, "first copy won"); eq(not b.done, true, "second copy still open")
R:Apply(P.Parse("Everyone passed on: " .. GEM))
eq(b.done, true, "second copy all passed"); eq(b.result, "allpassed", "allpassed result")

-- ------------------------------------------------ chat about an unknown roll
local before = #R.list
local x = R:Apply(P.Parse("Heal has selected Need for: |cff0070dd|Hitem:13965::::::::60:::::|h[Blackhand's Breadth]|h|r"))
eq(#R.list, before + 1, "roll created from chat")
eq(x.fromChat, true, "fromChat flag"); eq(R.CanRoll(x), false, "no buttons for chat-only rolls")

-- ------------------------------------------------ timeout
R:Close(x.id)  -- chat rolls have no Blizzard ID, but endsAt covers them
now = now + 60 + R.RESULT_TIMEOUT + 1
R:Tick()
eq(x.done, true, "timed out"); eq(x.result, "unknown", "unknown result")

-- ------------------------------------------------ history
local saved = R:Export()
eq(#saved, 4, "export finished rolls")
local R2 = {}
local ns2 = { Now = ns.Now, Clock = ns.Clock, PlayerName = ns.PlayerName, ShortName = ns.ShortName }
loadfile(dir .. "/Rolls.lua")("ForeverLootRolls", ns2)
ns2.Rolls:Import(saved)
eq(#ns2.Rolls.list, 4, "import")
eq(ns2.Rolls.list[1].winner, "Me", "import winner")
eq(ns2.Rolls.list[1].players.Tank.roll, 34, "import player roll")

R.maxEntries = 2
R:Trim()
eq(#R.list, 2, "trim to limit")
R:ClearFinished()
eq(#R.list, 0, "clear finished")

-- reused roll ID after the old one finished
local r1 = R:Start(9, { link = GEM })
R:Apply(P.Parse("Everyone passed on: " .. GEM))
local r2 = R:Start(9, { link = HOJ })
eq(r1 ~= r2, true, "reused id makes a new roll")
eq(R:Get(9), r2, "id points to the new roll")

-- ------------------------------------------------ newer clients (WoW Forever):
-- loot history link in front, |cnIQ colours, names with realm
local NEW = {
    LOOT_ROLL_NEED = "|HlootHistory:%d|h[Beute]|h: %s hat 'Bedarf' für: %s ausgewählt",
    LOOT_ROLL_GREED = "|HlootHistory:%d|h[Beute]|h: %s hat 'Gier' für: %s ausgewählt",
    LOOT_ROLL_PASSED = "|HlootHistory:%d|h[Beute]|h: %s würfelt nicht für: %s",
    LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Beute]|h: Ihr habt 'Gier' für: %s ausgewählt",
    LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Beute]|h: Bedarfswurf - %d für %s von %s",
    LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Beute]|h: Gierwurf - %d für %s von %s",
    LOOT_ROLL_WON = "|HlootHistory:%d|h[Beute]|h: %s gewinnt: %s",
    LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Beute]|h: Ihr gewinnt: %s",
}
P.Build(NEW)
local AXE = "|cnIQ2:|Hitem:4568::::::::23:1484::1:1:12722:1:28:5254:::::|h[Grunzeraxt des Bären]|h|r"
local FEET = "|cnIQ3:|Hitem:10411::::::::23:1484::1::1:28:5254:::::|h[Fußpolster des Giftzahns]|h|r"
local H = function(id) return "|HlootHistory:" .. id .. "|h[Beute]|h: " end

e = P.Parse(H(233103106) .. "Okan Eldenlórd hat 'Bedarf' für: " .. FEET .. " ausgewählt")
eq(e.kind, "choice", "new: kind"); eq(e.choice, "need", "new: choice")
eq(e.player, "Okan Eldenlórd", "new: player"); eq(e.item, FEET, "new: item (|cnIQ colour)")
eq(e.history, 233103106, "new: history id")
e = P.Parse(H(233103364) .. "Gierwurf - 70 für " .. AXE .. " von Baldan-Thorn")
eq(e.roll, 70, "new: roll"); eq(e.player, "Baldan-Thorn", "new: roll player"); eq(e.item, AXE, "new: roll item")
eq(P.Parse(H(1) .. "Irgendwas ohne Gegenstand"), nil, "no item link -> ignored")

-- full flow with realm names in the roster and in chat
local function Short(n)
    n = n:match("|Hplayer:([^:|]+)") or n
    n = n:gsub("|c[^|]*", ""):gsub("|r", ""):gsub("|h", "")
    return n:match("^%s*([^%s%-]+)") or n
end
ns.ShortName = Short
ns.PlayerName = function() return "Sturmhüter" end
ns.GetRoster = function()
    return { { name = "Sturmhüter", class = "DRUID" }, { name = "Baldan", class = "PALADIN" },
             { name = "Okan", class = "HUNTER" } }
end
R.maxEntries = 30
local axe1 = R:Start(20, { link = AXE, duration = 60 })
local axe2 = R:Start(21, { link = AXE, duration = 60 })
local feet = R:Start(22, { link = FEET, duration = 60 })
local n0 = #R.list
R:Apply(P.Parse(H(500) .. "Okan Eldenlórd hat 'Bedarf' für: " .. FEET .. " ausgewählt"))
R:Apply(P.Parse(H(501) .. "Baldan-Thorn hat 'Gier' für: " .. AXE .. " ausgewählt"))
R:Apply(P.Parse(H(502) .. "Baldan-Thorn würfelt nicht für: " .. AXE))
R:Apply(P.Parse(H(501) .. "Ihr habt 'Gier' für: " .. AXE .. " ausgewählt"))
R:Apply(P.Parse(H(502) .. "Ihr habt 'Gier' für: " .. AXE .. " ausgewählt"))
eq(#R.list, n0, "new: no extra rolls created")
eq(#feet.playerOrder, 3, "new: realm names merged into roster")
eq(feet.players.Okan.choice, "need", "new: Okan need on feet")
eq(axe1.players.Baldan.choice, "greed", "new: Baldan greed on axe 1")
eq(axe2.players.Baldan.choice, "pass", "new: Baldan pass on axe 2")
eq(axe1.historyId, 501, "new: axe 1 history id"); eq(axe2.historyId, 502, "new: axe 2 history id")
eq(axe2.players["Sturmhüter"].choice, "greed", "new: own greed on axe 2")
R:Apply(P.Parse(H(502) .. "Gierwurf - 12 für " .. AXE .. " von Sturmhüter-Elmodal"))
R:Apply(P.Parse(H(501) .. "Gierwurf - 70 für " .. AXE .. " von Baldan-Thorn"))
R:Apply(P.Parse(H(501) .. "Gierwurf - 33 für " .. AXE .. " von Sturmhüter-Elmodal"))
eq(axe2.players["Sturmhüter"].roll, 12, "new: roll by history id (axe 2)")
eq(axe1.players["Sturmhüter"].roll, 33, "new: roll by history id (axe 1)")
R:Apply(P.Parse(H(501) .. "Baldan-Thorn gewinnt: " .. AXE))
R:Apply(P.Parse(H(502) .. "Ihr gewinnt: " .. AXE))
eq(axe1.winner, "Baldan", "new: axe 1 winner"); eq(axe2.winner, "Sturmhüter", "new: axe 2 winner")
eq(#R.list, n0, "new: still no extra rolls")

-- ------------------------------------------------ own frame closes after our choice
-- (CANCEL_LOOT_ROLL), the others take their time: must not end up as "unknown"
local slow = R:Start(60, { link = FEET, duration = 60 })
R:Apply(P.Parse(H(600) .. "Ihr habt 'Gier' für: " .. FEET .. " ausgewählt"))
R:Close(60)
now = now + 30
R:Tick()
eq(slow.done, nil, "still open 30 s after our own choice")
eq(R.Remaining(slow) > 0, true, "time keeps running after our choice")
R:Apply(P.Parse(H(600) .. "Baldan-Thorn gewinnt: " .. FEET))
eq(slow.result, "won", "late winner after our early choice")

-- a result that comes after we gave up still counts
local late = R:Start(61, { link = AXE, duration = 60 })
now = now + 60 + R.RESULT_TIMEOUT + 1
R:Tick()
eq(late.result, "unknown", "gave up")
R:Apply(P.Parse(H(601) .. "Okan-Eldenlórd gewinnt: " .. AXE))
eq(late.result, "won", "late result replaces unknown"); eq(late.winner, "Okan", "late winner name")

-- ------------------------------------------------ real deDE lines from WoW Forever
P.Build({
    LOOT_ROLL_NEED = "|HlootHistory:%d|h[Beute]|h: %s hat für %s Bedarf ausgewählt",
    LOOT_ROLL_GREED = "|HlootHistory:%d|h[Beute]|h: %s hat für %s Gier ausgewählt",
    LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Beute]|h: Ihr habt \"Bedarf\" ausgewählt für: %s",
    LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Beute]|h: Ihr habt \"Gier\" ausgewählt für: %s",
    LOOT_ROLL_PASSED_SELF = "|HlootHistory:%d|h[Beute]|h: Weitergegeben von Euch: %s",
    LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Beute]|h: Wurf für eigenen Bedarf: %d für %s von %s",
    LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Beute]|h: Wurf für Gold: %d für %s von %s",
    LOOT_ROLL_WON = "|HlootHistory:%d|h[Beute]|h: Gewonnen von %s: %s",
    LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Beute]|h: Gewonnen von Euch: %s",
})
local BAG = "|cnIQ2:|Hitem:6446::::::::23:1484:::::::::|h[Natternhauttasche]|h|r"
local MOC = "|cnIQ2:|Hitem:15111::::::::23:1484::1:1:12731:1:28:5254:::::|h[Starre Mokassins der Ausdauer]|h|r"
ns.GetRoster = function()
    return { { name = "Sturmhüter" }, { name = "Kaelthor" }, { name = "Kraggus" } }
end
local bag = R:Start(70, { link = BAG, duration = 60 })
local moc = R:Start(71, { link = MOC, duration = 60 })
local lines = {
    "|HlootHistory:233186561|h[Beute]|h: Kaelthor Lightwarden hat für " .. BAG .. " Bedarf ausgewählt",
    "|HlootHistory:233186561|h[Beute]|h: Ihr habt \"Bedarf\" ausgewählt für: " .. BAG,
    "|HlootHistory:233189378|h[Beute]|h: Ihr habt \"Gier\" ausgewählt für: " .. MOC,
    "|HlootHistory:233189378|h[Beute]|h: Kraggus Gabelbart hat für " .. MOC .. " Gier ausgewählt",
    "|HlootHistory:233186561|h[Beute]|h: Wurf für eigenen Bedarf: 90 für " .. BAG .. " von Kaelthor Lightwarden",
    "|HlootHistory:233186561|h[Beute]|h: Wurf für eigenen Bedarf: 36 für " .. BAG .. " von Sturmhüter Elmodal",
    "|HlootHistory:233189378|h[Beute]|h: Wurf für Gold: 95 für " .. MOC .. " von Sturmhüter Elmodal",
    "|HlootHistory:233186561|h[Beute]|h: Gewonnen von Kaelthor Lightwarden: " .. BAG,
    "|HlootHistory:233189378|h[Beute]|h: Gewonnen von Euch: " .. MOC,
}
for _, line in ipairs(lines) do
    eq(P.Parse(line) ~= nil, true, "real line parsed: " .. line:sub(1, 70))
    R:Apply(P.Parse(line))
end
eq(P.Parse("|HlootHistory:233189378|h[Beute]|h: " .. MOC), nil, "announcement line ignored")
eq(bag.players.Kaelthor.choice, "need", "real: Kaelthor need"); eq(bag.players.Kaelthor.roll, 90, "real: Kaelthor 90")
eq(bag.players["Sturmhüter"].roll, 36, "real: own need roll")
eq(bag.winner, "Kaelthor", "real: bag winner")
eq(moc.players["Sturmhüter"].choice, "greed", "real: own greed"); eq(moc.players["Sturmhüter"].roll, 95, "real: own greed roll")
eq(moc.winner, "Sturmhüter", "real: you won the moccasins")
eq(P.Parse("|HlootHistory:1|h[Beute]|h: Gewonnen von Euch: " .. MOC).self, true, "Euch is you, not a player")

print(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
