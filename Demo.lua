-- /lootrolls test: made-up rolls with made-up group members, to try the window
-- without a dungeon. Nothing is sent to anyone.
local _, ns = ...
local R = ns.Rolls

local Demo = { seq = 0 }
ns.Demo = Demo

local MATES = {
    { name = "Brakk", class = "WARRIOR" },
    { name = "Lunara", class = "PRIEST" },
    { name = "Fizzwick", class = "MAGE" },
    { name = "Shadra", class = "ROGUE" },
}

local ITEMS = {
    { id = 11815, name = "Hand of Justice", quality = 4, icon = "Interface\\Icons\\INV_Jewelry_Talisman_01", bop = true },
    { id = 13965, name = "Blackhand's Breadth", quality = 3, icon = "Interface\\Icons\\INV_Misc_StoneTablet_01", bop = true },
    { id = 7909, name = "Aquamarine", quality = 2, icon = "Interface\\Icons\\INV_Misc_Gem_Crystal_02" },
}

local QUALITY_HEX = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" }

local function Link(item)
    if GetItemInfo then
        local _, link = GetItemInfo(item.id)
        if link then return link end
    end
    return ("|c%s|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(QUALITY_HEX[item.quality] or "ffffffff", item.id, item.name)
end

local function After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

local function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Simulates the result once everyone has chosen (or time is up).
local function Resolve(roll)
    if roll.done or roll.resolving then return end
    roll.resolving = true
    local delay = 0.4
    local best, bestRoll, bestRank
    for _, name in ipairs(roll.playerOrder) do
        local p = roll.players[name]
        if not p.choice then
            p.choice = "pass"
        end
        if p.choice ~= "pass" then
            local n = math.random(1, 100)
            local rank = R.CHOICE_RANK[p.choice]
            After(delay, function()
                R:Apply({ kind = "roll", choice = p.choice, player = name, roll = n, item = roll.link })
            end)
            delay = delay + 0.4
            if not best or rank < bestRank or (rank == bestRank and n > bestRoll) then
                best, bestRoll, bestRank = name, n, rank
            end
        end
    end
    After(delay + 0.4, function()
        if best then
            R:Apply({ kind = "won", player = best, item = roll.link })
        else
            R:Apply({ kind = "allpassed", item = roll.link })
        end
    end)
end

local function MaybeResolve(roll)
    for _, name in ipairs(roll.playerOrder) do
        if not roll.players[name].choice then return end
    end
    roll.closed = true
    roll.closedAt = ns.Now()
    Resolve(roll)
end

function Demo:Choose(roll, choice)
    R:Apply({ kind = "choice", choice = choice, self = true, item = roll.link })
    MaybeResolve(roll)
end

function Demo:Start()
    local me = ns.PlayerName()
    local _, myClass = UnitClass("player")
    local roster = { { name = me, class = myClass } }
    for _, m in ipairs(MATES) do roster[#roster + 1] = m end

    for i, item in ipairs(ITEMS) do
        self.seq = self.seq + 1
        local duration = 20 + i * 4
        local roll = R:Start("demo" .. self.seq, {
            link = Link(item), name = item.name, texture = item.icon, count = 1,
            quality = item.quality, bop = item.bop, canNeed = item.id ~= 7909, canGreed = true,
            duration = duration, roster = roster, demo = true,
        })
        local mates = Shuffle({ 2, 3, 4, 5 })
        for k, idx in ipairs(mates) do
            local m = roster[idx]
            After(1 + k * (1 + math.random() * 2), function()
                if roll.done or roll.players[m.name].choice then return end
                local r = math.random()
                local choice = (r < 0.3 and roll.canNeed) and "need" or (r < 0.75 and "greed") or "pass"
                R:Apply({ kind = "choice", choice = choice, player = m.name, item = roll.link })
                MaybeResolve(roll)
            end)
        end
        After(duration, function()
            if roll.done then return end
            roll.closed = true
            roll.closedAt = ns.Now()
            Resolve(roll)
        end)
    end
end
