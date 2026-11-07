-- Turns Blizzard's loot roll chat messages (CHAT_MSG_LOOT) into events.
-- The patterns are built from the client's own global strings, so every
-- game language works without translating anything here.
--
-- Which argument is what is worked out from the message itself instead of
-- fixed positions, because clients differ: newer ones put a loot history link
-- in front ("|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"),
-- and some languages reorder the arguments ("%2$s ... %1$s").
--   item    = the text argument holding an item link
--   player  = the other text argument
--   history = the number right after "lootHistory:"
--   roll    = any other number
local _, ns = ...
local P = {}
ns.Parser = P

-- Global string name, event kind, choice, own message?
-- Strings the client does not have are skipped.
P.DEFS = {
    { "LOOT_ROLL_NEED", "choice", "need" },
    { "LOOT_ROLL_GREED", "choice", "greed" },
    { "LOOT_ROLL_DISENCHANT", "choice", "disenchant" },
    { "LOOT_ROLL_PASSED", "choice", "pass" },
    { "LOOT_ROLL_PASSED_AUTO", "choice", "pass" },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "choice", "pass" },
    { "LOOT_ROLL_NEED_SELF", "choice", "need", true },
    { "LOOT_ROLL_GREED_SELF", "choice", "greed", true },
    { "LOOT_ROLL_DISENCHANT_SELF", "choice", "disenchant", true },
    { "LOOT_ROLL_PASSED_SELF", "choice", "pass", true },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "choice", "pass", true },

    { "LOOT_ROLL_ROLLED_NEED", "roll", "need" },
    { "LOOT_ROLL_ROLLED_GREED", "roll", "greed" },
    { "LOOT_ROLL_ROLLED_DE", "roll", "disenchant" },
    { "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "roll", "need" },
    { "LOOT_ROLL_ROLLED_GREED_ROLE_BONUS", "roll", "greed" },

    { "LOOT_ROLL_WON", "won", nil },
    { "LOOT_ROLL_YOU_WON", "won", nil, true },
    { "LOOT_ROLL_WON_NO_SPAM_NEED", "won", "need" },
    { "LOOT_ROLL_WON_NO_SPAM_GREED", "won", "greed" },
    { "LOOT_ROLL_WON_NO_SPAM_DE", "won", "disenchant" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", "need", true },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", "greed", true },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", "disenchant", true },
    { "LOOT_ROLL_ALL_PASSED", "allpassed", nil },
}

-- Converts a printf-style format into an anchored Lua pattern. Returns the
-- pattern, one { conv = "s"|"d", history = bool } per capture, and the length
-- of the fixed text (longer = more specific).
function P.Compile(fmt)
    local out, caps, literal = {}, {}, 0
    local tail = ""   -- fixed text since the last argument
    local i, len = 1, #fmt
    while i <= len do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, conv, nxt = fmt:match("^(%d+)%$([sd])()", i + 1)
            if not pos then conv, nxt = fmt:match("^([sd%%])()", i + 1) end
            if conv == "%" then
                out[#out + 1] = "%%"
                literal = literal + 1
                tail = tail .. "%"
                i = nxt
            elseif conv then
                caps[#caps + 1] = { conv = conv, history = tail:find("lootHistory:$") ~= nil }
                out[#out + 1] = (conv == "d") and "(%-?%d+)" or "(.-)"
                tail = ""
                i = nxt
            else
                out[#out + 1] = "%%"
                literal = literal + 1
                tail = tail .. "%"
                i = i + 1
            end
        else
            out[#out + 1] = (c:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
            literal = literal + 1
            tail = tail .. c
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", caps, literal
end

-- Builds the matcher list from a table of global strings (default: _G).
function P.Build(globals)
    globals = globals or _G
    local list = {}
    for _, def in ipairs(P.DEFS) do
        local fmt = globals[def[1]]
        if type(fmt) == "string" and fmt ~= "" then
            local pattern, caps, literal = P.Compile(fmt)
            list[#list + 1] = { def = def, pattern = pattern, caps = caps, literal = literal }
        end
    end
    -- Try the most specific text first: "%s automatically passed on: %s because ..."
    -- must win over "%s passed on: %s", and "You passed on: %s" over both.
    table.sort(list, function(a, b)
        if a.literal ~= b.literal then return a.literal > b.literal end
        return a.def[1] < b.def[1]
    end)
    P.matchers = list
    return list
end

-- Cuts the item link out of a text (it may carry extra bits like " x2").
-- Handles both colour styles: |cffa335ee... and the newer |cnIQ4:...
function P.ExtractLink(text)
    if type(text) ~= "string" then return nil end
    return text:match("|c[^|]*|Hitem:.-|h.-|h|r")
        or text:match("|Hitem:.-|h.-|h")
end

-- Returns { kind, choice, self, item, player, roll, history } or nil.
function P.Parse(msg)
    if type(msg) ~= "string" or not msg:find("|Hitem:", 1, true) then return nil end
    local list = P.matchers or P.Build()
    for _, m in ipairs(list) do
        local values = { msg:match(m.pattern) }
        if values[1] ~= nil then
            local def = m.def
            local ev = { kind = def[2], choice = def[3], self = def[4] or false, source = def[1] }
            for idx, cap in ipairs(m.caps) do
                local v = values[idx]
                if cap.conv == "d" then
                    if cap.history then ev.history = tonumber(v) else ev.roll = tonumber(v) end
                elseif not ev.item and v:find("|Hitem:", 1, true) then
                    ev.item = P.ExtractLink(v)
                else
                    ev.player = v
                end
            end
            local needsPlayer = not ev.self and ev.kind ~= "allpassed"
            if ev.item and (ev.player or not needsPlayer) then
                if not needsPlayer then ev.player = nil end
                return ev
            end
        end
    end
    return nil
end
