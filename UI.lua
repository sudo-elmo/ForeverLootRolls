-- The roll window, kept plain: per item a line with icon, name and time bar,
-- below it every player with the icon of their choice and their roll.
-- Everything else lives in the tooltip. Newest item on top.
local _, ns = ...
local L, R = ns.L, ns.Rolls

local UI = {}
ns.UI = UI

local WIDTH = 270
local PAD = 14             -- inside the dialog border
local CONTENT_W = WIDTH - 2 * PAD
local CARD = 6             -- padding inside each item card
local INNER_W = CONTENT_W - 2 * CARD
local ROW_H = 32           -- item line
local ICON = 30
local BTN = 30             -- classic Need / Greed / Pass icon buttons
local BTN_SPACING = 14
local LINE_H = 19          -- player line
local LINE_X = 10
local BTN_ROW = 32         -- row with the Need / Greed / Pass buttons
local GAP = 8
local SCROLLBAR_W = 14
local SCROLLBAR_GAP = 4
local TITLE_SPACE = 16     -- room under the title banner and the close button
local FOOTER = 26          -- row with the clear button

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local SMALL = "GameFontHighlight"

local CHOICE_TEX = {
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local WAIT_TEX = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local WIN_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
local QUESTION_TEX = "Interface\\Icons\\INV_Misc_QuestionMark"

local ROLL_BUTTONS = {
    { choice = "need", value = 1, tex = "Interface\\Buttons\\UI-GroupLoot-Dice", tip = "rollNeedTip", can = "canNeed" },
    { choice = "greed", value = 2, tex = "Interface\\Buttons\\UI-GroupLoot-Coin", tip = "rollGreedTip", can = "canGreed" },
    { choice = "disenchant", value = 3, tex = "Interface\\Buttons\\UI-GroupLoot-DE", tip = "rollDisenchantTip", can = "canDisenchant", optional = true },
    { choice = "pass", value = 0, tex = "Interface\\Buttons\\UI-GroupLoot-Pass", tip = "rollPassTip" },
}

local function Opt(key)
    local v = ns.db and ns.db[key]
    if v == nil then return ns.DEFAULTS and ns.DEFAULTS[key] end
    return v
end

local function Font(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or SMALL)
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

local function ClassHex(class)
    local r, g, b = ClassColor(class)
    return ("ff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Time left in seconds; Blizzard knows it best for real rolls.
local function Remaining(roll)
    if roll.done then return 0 end
    if type(roll.id) == "number" and not roll.closed and GetLootRollTimeLeft then
        local ok, ms = pcall(GetLootRollTimeLeft, roll.id)
        if ok and type(ms) == "number" and ms > 0 then return ms / 1000 end
    end
    return R.Remaining(roll)
end

-- ---------------------------------------------------------------- player lines

local linePool = {}

local function AcquireLine(parent)
    local line = table.remove(linePool)
    if not line then
        line = CreateFrame("Frame")
        line:SetHeight(LINE_H)
        line.stripe = line:CreateTexture(nil, "BACKGROUND")
        line.stripe:SetAllPoints()
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(16, 16)
        line.icon:SetPoint("LEFT", LINE_X, 0)
        line.win = line:CreateTexture(nil, "ARTWORK")
        line.win:SetSize(15, 15)
        line.win:SetPoint("RIGHT", 0, 0)
        line.win:SetTexture(WIN_TEX)
        line.roll = Font(line, SMALL)
        line.roll:SetPoint("RIGHT", -19, 0)
        line.roll:SetJustifyH("RIGHT")
        line.name = Font(line, SMALL)
        line.name:SetPoint("LEFT", line.icon, "RIGHT", 6, 0)
        line.name:SetPoint("RIGHT", line.roll, "LEFT", -4, 0)
        line.name:SetJustifyH("LEFT")
        line.name:SetWordWrap(false)
    end
    line:SetParent(parent)
    line:Show()
    return line
end

local function ReleaseLines(block)
    for i = #block.lines, 1, -1 do
        local line = block.lines[i]
        line:Hide()
        line:ClearAllPoints()
        linePool[#linePool + 1] = line
        block.lines[i] = nil
    end
end

local function FillLine(line, p, roll, index)
    -- every other line slightly lighter, like classic lists
    line.stripe:SetColorTexture(1, 1, 1, (index % 2 == 0) and 0.05 or 0)
    line.icon:SetTexture(p.choice and CHOICE_TEX[p.choice] or (roll.done and QUESTION_TEX or WAIT_TEX))
    line.name:SetText(p.name)
    if p.choice == "pass" or (roll.done and not p.choice) then
        line.name:SetTextColor(0.5, 0.5, 0.5)
        line.icon:SetAlpha(0.6)
    else
        line.name:SetTextColor(ClassColor(p.class))
        line.icon:SetAlpha(1)
    end
    line.roll:SetText(p.roll and tostring(p.roll) or "")
    if p.winner then
        line.roll:SetTextColor(0.2, 1, 0.2)
        line.win:Show()
    else
        line.roll:SetTextColor(0.8, 0.8, 0.8)
        line.win:Hide()
    end
end

-- ---------------------------------------------------------------- item blocks

local blockPool = {}

-- The dice / coin / pass button exactly like on Blizzard's classic roll frame.
local function RollButton(block, def)
    local b = CreateFrame("Button", nil, block.btnRow)
    b:SetSize(BTN, BTN)
    b:SetNormalTexture(def.tex .. "-Up")
    b:SetPushedTexture(def.tex .. "-Down")
    b:SetHighlightTexture(def.tex .. "-Highlight", "ADD")
    b.def = def
    b:SetScript("OnClick", function(btn)
        if block.roll then UI:Roll(block.roll, btn.def) end
    end)
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(L[btn.def.tip])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    return b
end

-- Item tooltip, plus who chose what (handy for folded-in rolls).
local function ShowItemTooltip(owner, roll)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    local shown = false
    if type(roll.id) == "number" and not roll.done and not roll.closed and GameTooltip.SetLootRollItem then
        shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, roll.id)
    end
    if not shown and roll.link and roll.link:find("|H") then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, roll.link)
    end
    if not shown then GameTooltip:SetText(R.ItemName(roll.link) or "?") end
    GameTooltip:AddLine(" ")
    for _, p in ipairs(R.SortedPlayers(roll)) do
        local right = (p.choice and L[p.choice] or (roll.done and "–" or L.waiting))
            .. (p.roll and ("  " .. p.roll) or "")
        if p.winner then right = "|cff33ff33" .. right .. "|r" end
        GameTooltip:AddDoubleLine("|c" .. ClassHex(p.class) .. p.name .. "|r", right, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function CreateBlock()
    -- every item sits on its own dark card
    local block = CreateFrame("Frame", nil, nil, BACKDROP_TEMPLATE)
    block:SetWidth(CONTENT_W)
    if block.SetBackdrop then
        block:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        block:SetBackdropColor(0, 0, 0, 0.45)
    end
    block.lines = {}

    local header = CreateFrame("Button", nil, block)
    header:SetPoint("TOPLEFT", CARD, -CARD)
    header:SetPoint("TOPRIGHT", -CARD, -CARD)
    header:SetHeight(ROW_H)
    header:RegisterForClicks("LeftButtonUp")
    header:SetScript("OnClick", function()
        local roll = block.roll
        if not roll then return end
        if roll.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then
            HandleModifiedItemClick(roll.link)   -- shift: link in chat, ctrl: try on
            return
        end
        roll.collapsed = not UI:IsCollapsed(roll)
        roll.userToggled = true
        UI:Refresh()
    end)
    header:SetScript("OnEnter", function(btn)
        if block.roll then ShowItemTooltip(btn, block.roll) end
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    block.header = header

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("LEFT", 1, 0)
    block.icon = icon
    -- classic bag slot frame around the icon
    local slot = header:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    slot:SetSize(ICON * 1.75, ICON * 1.75)
    slot:SetPoint("CENTER", icon, "CENTER", 0, 0)
    -- quality coloured glow, like on action buttons
    local glow = header:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetSize(ICON * 1.85, ICON * 1.85)
    glow:SetPoint("CENTER", icon, "CENTER", 0, 0)
    glow:Hide()
    block.glow = glow

    block.btnRow = CreateFrame("Frame", nil, block)
    block.btnRow:SetPoint("TOPLEFT", CARD, -CARD - ROW_H - 2)
    block.btnRow:SetPoint("TOPRIGHT", -CARD, -CARD - ROW_H - 2)
    block.btnRow:SetHeight(BTN_ROW)
    block.buttons = {}
    for _, def in ipairs(ROLL_BUTTONS) do
        block.buttons[def.choice] = RollButton(block, def)
    end

    -- who got it, shown small on the right while the block is folded in
    block.winner = Font(header, "GameFontHighlightSmall")
    block.winner:SetPoint("RIGHT", 0, 0)
    block.winner:SetJustifyH("RIGHT")
    block.winner:Hide()

    block.item = Font(header, "GameFontNormal")
    block.item:SetPoint("LEFT", icon, "RIGHT", 8, 5)
    block.item:SetJustifyH("LEFT")
    block.item:SetWordWrap(false)

    -- classic status bar (as on unit and cast bars) with a dark edge
    local bar = CreateFrame("StatusBar", nil, header)
    bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 2)
    bar:SetHeight(7)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    back:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    block.bar = bar

    return block
end

local function AcquireBlock(parent)
    local block = table.remove(blockPool) or CreateBlock()
    block:SetParent(parent)
    block:Show()
    return block
end

local function ReleaseBlock(block)
    ReleaseLines(block)
    block.roll = nil
    block:Hide()
    block:ClearAllPoints()
    blockPool[#blockPool + 1] = block
end

-- Time bar and (optional) roll buttons; called often while rolls are open.
function UI:UpdateBlockLive(block)
    local roll = block.roll
    if not roll then return end
    local left = Remaining(roll)
    local showBar = not roll.done and left > 0

    -- with the time bar the name sits above it; without it (finished items)
    -- the name is centred on the icon
    local y = showBar and 5 or 0
    block.item:ClearAllPoints()
    block.item:SetPoint("LEFT", block.icon, "RIGHT", 8, y)
    if block.winner:IsShown() then
        block.item:SetPoint("RIGHT", block.winner, "LEFT", -6, y)
    else
        block.item:SetPoint("RIGHT", 0, y)
    end
    block.bar:SetPoint("RIGHT", -1, 0)

    -- the button row is laid out by FillBlock; here it only goes away in time
    if block.btnRow:IsShown() and not (R.CanRoll(roll) and left > 0) then
        block.btnRow:Hide()
    end

    if showBar then
        local frac = math.min(1, left / (roll.duration or 60))
        block.bar:SetValue(frac)
        block.bar:SetStatusBarColor(1 - frac * 0.6, 0.3 + 0.6 * frac, 0.1, 0.9)
        block.bar:Show()
    else
        block.bar:Hide()
    end
end

-- Need / Greed / (Disenchant) / Pass side by side over the full width.
local function LayoutButtons(block, roll)
    local shown = {}
    for _, def in ipairs(ROLL_BUTTONS) do
        local b = block.buttons[def.choice]
        if def.optional and not roll.canDisenchant then
            b:Hide()
        else
            shown[#shown + 1] = b
        end
    end
    -- centred, with some room between them
    local total = #shown * BTN + (#shown - 1) * BTN_SPACING
    local x = math.floor(((block.innerW or INNER_W) - total) / 2)
    for i, b in ipairs(shown) do
        local allowed = (b.def.can == nil) or roll[b.def.can] ~= false
        b:SetEnabled(allowed)
        local tex = b:GetNormalTexture()
        if tex then
            tex:SetDesaturated(not allowed)
            tex:SetAlpha(allowed and 1 or 0.4)
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", x + (i - 1) * (BTN + BTN_SPACING), 0)
        b:Show()
    end
end

local function QualityColor(roll)
    local q = roll.quality or (roll.link and tonumber(roll.link:match("|cnIQ(%d+):") or ""))
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    local hex = roll.link and roll.link:match("|c%x%x(%x%x%x%x%x%x)")
    if hex then
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end
    return 1, 1, 1
end

function UI:FillBlock(block, roll)
    block.roll = roll
    block.icon:SetTexture(roll.texture or (ns.ItemIcon and ns.ItemIcon(roll.link)) or QUESTION_TEX)
    block.item:SetText(R.ItemName(roll.link) or roll.name or "?")
    block.item:SetTextColor(QualityColor(roll))
    local q = roll.quality or (roll.link and tonumber(roll.link:match("|cnIQ(%d+):") or ""))
    if q and q >= 2 then
        block.glow:SetVertexColor(QualityColor(roll))
        block.glow:SetAlpha(roll.done and 0.35 or 0.8)
        block.glow:Show()
    else
        block.glow:Hide()
    end
    local mine = roll.result == "won" and ns.PlayerName and roll.winner == ns.PlayerName()
    block.item:SetAlpha((roll.done and not mine) and 0.6 or 1)
    block.icon:SetDesaturated(roll.done and not mine and true or false)

    local winner
    if roll.done and self:IsCollapsed(roll) then
        if roll.result == "won" and roll.winner then
            local p = roll.players[roll.winner]
            if ns.PlayerName and roll.winner == ns.PlayerName() then
                winner = "|cff33ff33" .. L.you .. "|r"
            else
                winner = "|c" .. ClassHex(p and p.class) .. roll.winner .. "|r"
            end
            -- with what: Need / Greed icon in front, the roll behind
            local tex = p and p.choice and CHOICE_TEX[p.choice]
            if tex then winner = ("|T%s:14:14|t "):format(tex) .. winner end
            if p and p.roll then winner = winner .. " |cffffd100" .. p.roll .. "|r" end
        elseif roll.result == "allpassed" then
            winner = "|cff808080" .. L.allPassedShort .. "|r"
        else
            winner = "|cff808080?|r"
        end
    end
    block.winner:SetText(winner or "")
    block.winner:SetShown(winner ~= nil)

    ReleaseLines(block)
    local y = -CARD - ROW_H - 2
    if Opt("rollButtons") and R.CanRoll(roll) and Remaining(roll) > 0 then
        LayoutButtons(block, roll)
        block.btnRow:Show()
        y = y - BTN_ROW
    else
        block.btnRow:Hide()
    end
    local height = -y - 2 + CARD
    if not self:IsCollapsed(roll) then
        for _, p in ipairs(R.SortedPlayers(roll)) do
            local line = AcquireLine(block)
            line:SetPoint("TOPLEFT", CARD, y)
            line:SetPoint("TOPRIGHT", -CARD, y)
            FillLine(line, p, roll, #block.lines + 1)
            block.lines[#block.lines + 1] = line
            y = y - LINE_H
        end
        height = -y + CARD
    end
    block:SetHeight(height)
    -- gold edge while the roll is open, grey once it is done,
    -- green with a green tint for items you won yourself
    if block.SetBackdropBorderColor then
        local mine = roll.result == "won" and ns.PlayerName and roll.winner == ns.PlayerName()
        if mine then
            block:SetBackdropBorderColor(0.2, 1, 0.2, 1)
            block:SetBackdropColor(0.05, 0.3, 0.05, 0.55)
        elseif roll.done then
            block:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
            block:SetBackdropColor(0, 0, 0, 0.45)
        else
            block:SetBackdropBorderColor(1, 0.82, 0.2, 1)
            block:SetBackdropColor(0, 0, 0, 0.45)
        end
    end
    self:UpdateBlockLive(block)
    return height
end

-- Open rolls show their players, finished ones fold in (click to toggle).
function UI:IsCollapsed(roll)
    if roll.collapsed ~= nil then return roll.collapsed end
    return false
end

-- ---------------------------------------------------------------- main frame

-- Layering: above the quest tracker, but below the bags (opened bags cover the
-- window). The tracker's layer differs between clients, so we look it up and
-- sit just above it. Called before the window gets any child frames.
local TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5 }

function UI.ApplyLayer(f)
    local strata, level = "LOW", 1
    for _, name in ipairs(TRACKERS) do
        local t = _G[name]
        if type(t) == "table" and t.GetFrameStrata and t.GetFrameLevel then
            local ts = t:GetFrameStrata()
            if (STRATA_ORDER[ts] or 0) > (STRATA_ORDER[strata] or 0) then strata, level = ts, 1 end
            if ts == strata then level = math.max(level, (t:GetFrameLevel() or 0) + 20) end
        end
    end
    f:SetFrameStrata(strata)
    f:SetFrameLevel(math.min(level, 5000))
end

function UI:Create()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "ForeverLootRollsFrame", UIParent, BACKDROP_TEMPLATE)
    f:SetSize(WIDTH, 40)
    -- same dialog frame as Forever Dice & Ale
    if f.SetBackdrop then
        f:SetBackdrop({
            -- plain black; how see-through it is comes from the opacity setting
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    -- above the quest tracker, below the bags
    UI.ApplyLayer(f)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        UI:AnchorTop()
    end)
    local pos = ns.db and ns.db.pos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 60)
    end
    f:Hide()
    self.frame = f

    -- small classic title banner on the top edge, like Forever Dice & Ale
    local banner = f:CreateTexture(nil, "ARTWORK")
    banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    banner:SetSize(240, 56)
    banner:SetPoint("TOP", 0, 12)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", banner, "TOP", 0, -12)
    title:SetText(L.title)
    if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 12, 0) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -4, -4)

    -- small gear left of the X: opens the settings page (as in Forever Dice & Ale)
    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(18, 18)
    gear:SetPoint("RIGHT", close, "LEFT", 2, 0)
    local gearTex = gear:CreateTexture(nil, "ARTWORK")
    gearTex:SetTexture("Interface\\Worldmap\\Gear_64Grey")
    gearTex:SetAllPoints()
    gearTex:SetVertexColor(0.9, 0.8, 0.55)
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnMouseDown", function() gearTex:SetPoint("TOPLEFT", 1, -1) gearTex:SetPoint("BOTTOMRIGHT", 1, -1) end)
    gear:SetScript("OnMouseUp", function() gearTex:SetAllPoints() end)
    gear:SetScript("OnClick", function()
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION) or 857)
        if ns.OpenOptions then ns.OpenOptions() end
    end)
    gear:SetScript("OnEnter", function(btn)
        gearTex:SetVertexColor(1, 0.95, 0.75)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(L.settings)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function()
        gearTex:SetVertexColor(0.9, 0.8, 0.55)
        GameTooltip:Hide()
    end)
    self.gear = gear

    -- note far left: opens the long-term loot history
    local note = CreateFrame("Button", nil, f)
    note:SetSize(18, 18)
    note:SetPoint("TOPLEFT", 12, -9)
    local noteTex = note:CreateTexture(nil, "ARTWORK")
    noteTex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    noteTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    noteTex:SetAllPoints()
    note:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    note:SetScript("OnMouseDown", function() noteTex:SetPoint("TOPLEFT", 1, -1) noteTex:SetPoint("BOTTOMRIGHT", 1, -1) end)
    note:SetScript("OnMouseUp", function() noteTex:SetAllPoints() end)
    note:SetScript("OnClick", function()
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION) or 857)
        if ns.HistoryUI then ns.HistoryUI:Toggle() end
    end)
    note:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(L.history)
        GameTooltip:AddLine(L.historyTip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    note:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.note = note

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", PAD, -PAD - TITLE_SPACE)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD + FOOTER)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        UI:ScrollTo((UI.scrollPos or 0) - delta * ROW_H * 2)
    end)

    -- slim scroll bar, only shown when the list is taller than the window
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", -PAD + 2, -PAD - TITLE_SPACE)
    bar:SetPoint("BOTTOMRIGHT", -PAD + 2, PAD + FOOTER)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(false) end
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.45)
    -- classic scroll knob
    bar.thumb = bar:CreateTexture(nil, "OVERLAY")
    bar.thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    bar.thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875)
    bar.thumb:SetSize(SCROLLBAR_W, 24)
    bar:SetThumbTexture(bar.thumb)
    bar.fixedThumb = true
    bar:SetScript("OnValueChanged", function(_, value)
        if UI.settingBar then return end
        UI:ScrollTo(value)
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta)
        UI:ScrollTo((UI.scrollPos or 0) - delta * ROW_H * 2)
    end)
    bar:Hide()
    self.bar = bar
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    self.empty = Font(content, "GameFontDisableSmall")
    self.empty:SetPoint("TOPLEFT", 2, -6)
    self.empty:SetText(L.empty)

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(80, 20)
    clear:SetPoint("BOTTOMLEFT", PAD - 1, PAD - 2)
    clear:SetText(L.clear)
    clear:SetScript("OnClick", function() R:ClearFinished() end)
    clear:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(L.clearTip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.blocks = {}

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        R:Tick()
        UI:CollapseDue()
        for _, block in ipairs(UI.blocks) do
            if block.roll and not block.roll.done then UI:UpdateBlockLive(block) end
        end
    end)
    f:SetScript("OnHide", function()
        UI.autoOpened = false
        UI.closeToken = nil
        if Opt("collapseMode") ~= "never" then UI:CollapseFinished() end
    end)

    self:ApplyEscape()
    return f
end

-- Folds finished rolls in, except ones the player opened or closed by hand.
-- Pins the window by its top left corner, so a longer list makes it grow
-- downwards. (Dragging lets WoW pick the nearest corner, e.g. BOTTOMRIGHT,
-- and the window would then grow upwards.)
function UI:AnchorTop()
    local f = self.frame
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    if ns.db then ns.db.pos = { "TOPLEFT", "BOTTOMLEFT", left, top } end
end

function UI:CollapseFinished()
    for _, roll in ipairs(R.list) do
        if roll.done and not roll.userToggled then roll.collapsed = true end
    end
end

-- "After X seconds" mode: fold in rolls that have been done long enough.
function UI:CollapseDue()
    if Opt("collapseMode") ~= "delay" then return end
    local delay = tonumber(Opt("collapseDelay")) or 5
    local now = ns.Now and ns.Now() or 0
    local changed = false
    for _, roll in ipairs(R.list) do
        if roll.done and roll.collapsed == nil and not roll.userToggled
            and roll.finishedAt and now - roll.finishedAt >= delay then
            roll.collapsed = true
            changed = true
        end
    end
    if changed then self:Refresh() end
end

function UI:ScrollTo(value)
    local maxScroll = self.maxScroll or 0
    value = math.min(maxScroll, math.max(0, value or 0))
    self.scrollPos = value
    self.scroll:SetVerticalScroll(value)
    if self.bar:IsShown() then
        self.settingBar = true
        self.bar:SetValue(value)
        self.settingBar = nil
    end
end

-- Lays out all cards at the given width; returns the total height.
function UI:LayoutBlocks(width)
    for i = #self.blocks, 1, -1 do
        ReleaseBlock(self.blocks[i])
        self.blocks[i] = nil
    end
    self.content:SetWidth(width)
    local y = 0
    for i = #R.list, 1, -1 do
        local block = AcquireBlock(self.content)
        block:SetWidth(width)
        block.innerW = width - 2 * CARD
        block:SetPoint("TOPLEFT", 0, -y)
        y = y + self:FillBlock(block, R.list[i]) + GAP
        self.blocks[#self.blocks + 1] = block
    end
    return #R.list > 0 and (y - GAP) or 26
end

-- Background opacity: 100 % = solid black, lower = see-through.
-- Text, border and icons always stay fully visible.
function UI:ApplyOpacity()
    local f = self.frame
    if f and f.SetBackdropColor then
        local a = math.max(0, math.min(1, (tonumber(Opt("opacity")) or 70) / 100))
        f:SetBackdropColor(0, 0, 0, a)
    end
end

function UI:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    self:ApplyOpacity()
    local chrome = 2 * PAD + TITLE_SPACE + FOOTER
    local maxH = tonumber(Opt("maxHeight")) or 380
    local visible = maxH - chrome

    local y = self:LayoutBlocks(CONTENT_W)
    local needBar = y > visible
    if needBar then
        -- make room for the scroll bar and lay out again, a bit narrower
        y = self:LayoutBlocks(CONTENT_W - SCROLLBAR_W - SCROLLBAR_GAP)
    end
    self.scroll:SetPoint("BOTTOMRIGHT", -PAD - (needBar and (SCROLLBAR_W + SCROLLBAR_GAP) or 0), PAD + FOOTER)
    self.empty:SetShown(#R.list == 0)
    self.content:SetHeight(math.max(y, 1))
    f:SetHeight(math.min(maxH, y + chrome))

    self.maxScroll = needBar and (y - visible) or 0
    if needBar then
        self.bar:SetMinMaxValues(0, self.maxScroll)
        if not self.bar.fixedThumb then self.bar.thumb:SetHeight(math.max(20, visible * visible / y)) end
        self.bar:Show()
    else
        self.bar:Hide()
    end
    self:ScrollTo(self.scrollPos or 0)
end

function UI:Show(auto)
    local f = self:Create()
    if not f:IsShown() then
        self.autoOpened = auto and true or false
        f:Show()
        -- positions saved by older versions may hang on a bottom corner
        local pos = ns.db and ns.db.pos
        if not (pos and pos[1] == "TOPLEFT" and pos[2] == "BOTTOMLEFT") then self:AnchorTop() end
    end
    self:Refresh()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
    else
        self:Show(false)
    end
end

-- Escape closes the window only while it is in UISpecialFrames (setting).
function UI:ApplyEscape()
    if not (self.frame and UISpecialFrames) then return end
    local name = self.frame:GetName()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
    if Opt("closeOnEscape") then tinsert(UISpecialFrames, name) end
end

-- ---------------------------------------------------------------- rolling

function UI:Roll(roll, def)
    if not R.CanRoll(roll) then return end
    if roll.demo then
        if ns.Demo then ns.Demo:Choose(roll, def.choice) end
        return
    end
    if type(roll.id) == "number" and RollOnLoot then
        -- Bind-on-pickup items ask for confirmation first (Blizzard popup).
        -- The choice shows up here once the chat message confirms it.
        RollOnLoot(roll.id, def.value)
    end
end

-- ---------------------------------------------------------------- auto open / close

local function InDungeon()
    return ns.InDungeon and ns.InDungeon() or false
end

-- The open / close settings exist twice: for dungeons and raids, and for
-- the open world. AreaOpt("AutoClose") -> dungeonAutoClose or worldAutoClose.
local function AreaOpt(name)
    return Opt((InDungeon() and "dungeon" or "world") .. name)
end

-- Called on every loading screen.
function UI:OnZoneChanged(dungeon)
    if dungeon and Opt("openOnEnterDungeon") then
        self:CancelClose()
        self:Show(true)
        self.instanceOpened = true
    elseif not dungeon and self.instanceOpened then
        -- left the dungeon: the window goes away again (unless a roll still runs)
        self.instanceOpened = false
        if self.frame and self.frame:IsShown() and self.autoOpened and R:ActiveCount() == 0 then
            self.frame:Hide()
        end
    end
end

function UI:CancelClose()
    self.closeToken = nil
end

function UI:CheckAutoClose()
    if not (self.frame and self.frame:IsShown() and self.autoOpened and AreaOpt("AutoClose")) then return end
    if R:ActiveCount() > 0 then
        self:CancelClose()
        return
    end
    if self.closeToken then return end
    local token = {}
    self.closeToken = token
    local function Try()
        if UI.closeToken ~= token then return end
        if R:ActiveCount() > 0 or not AreaOpt("AutoClose") then UI.closeToken = nil return end
        if UI.frame:IsMouseOver() then
            C_Timer.After(2, Try)
            return
        end
        UI.closeToken = nil
        UI.frame:Hide()
    end
    C_Timer.After(tonumber(AreaOpt("CloseDelay")) or 8, Try)
end

R:On(function(event, roll)
    if event == "started" then
        -- older finished rolls fold in so the new one is in focus
        if Opt("collapseMode") ~= "never" then UI:CollapseFinished() end
        UI:CancelClose()
        if roll.demo or AreaOpt("AutoOpen") then
            UI:Show(true)
        else
            UI:Refresh()
        end
    elseif event == "finished" then
        if Opt("collapseMode") == "instant" and not roll.userToggled then roll.collapsed = true end
        UI:Refresh()
        UI:CheckAutoClose()
    else
        UI:Refresh()
    end
end)
