-- Loot history window: every item ever rolled on, newest first, grouped by
-- visit (dungeon, raid or zone). Only the visible rows exist as frames, so
-- long histories stay fast.
local _, ns = ...
local L, A, S = ns.L, ns.Archive, ns.Skin

local H = {}
ns.HistoryUI = H

local WIDTH, HEIGHT = 380, 460
local PAD = 16
local TOP = 52            -- banner + filter row
local BOTTOM = 40         -- delete button row
local ROW_H = 22
local SCROLLBAR_W = 14
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local CHOICE_TEX = {
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local QUESTION_TEX = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return ("ff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
    end
    return "ffe6e6e6"
end

local function QualityColor(e)
    local q = e.link and tonumber(e.link:match("|cnIQ(%d+):") or "")
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    local hex = e.link and e.link:match("|c%x%x(%x%x%x%x%x%x)")
    if hex then
        return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end
    return 1, 1, 1
end

local function Date(fmt, ts)
    if not (date and ts and ts > 0) then return "" end
    return date(fmt, ts)
end

local function WinnerText(e)
    if e.result == "won" then
        local p = A.WinnerOf(e)
        local text = A.IsMine(e) and ("|cff33ff33" .. L.you .. "|r")
            or ("|c" .. ClassHex(p and p.class) .. tostring(e.winner) .. "|r")
        local tex = p and p.choice and CHOICE_TEX[p.choice]
        if tex then text = ("|T%s:14:14|t "):format(tex) .. text end
        if p and p.roll then text = text .. " |cffffd100" .. p.roll .. "|r" end
        return text
    elseif e.result == "allpassed" then
        return "|cff808080" .. L.allPassedShort .. "|r"
    end
    return "|cff808080?|r"
end

local function GroupTitle(g)
    local kind = (g.zoneType == "party" and L.typeParty) or (g.zoneType == "raid" and L.typeRaid) or nil
    local title = g.zone .. (kind and (" |cff999999(" .. kind .. ")|r") or "")
    local from, to = Date(L.dateFormat, g.from), Date("%H:%M", g.to)
    if Date("%d%m%y", g.from) ~= Date("%d%m%y", g.to) then to = Date(L.dateFormat, g.to) end
    return title, (from == to or to == "") and from or (from .. "–" .. to)
end

local function ShowEntryTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = e.link and e.link:find("|H") and pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
    if not shown then GameTooltip:SetText(ns.Rolls.ItemName(e.link) or "?") end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("%s  ·  %s"):format(e.zone or "?", Date(L.dateFormat, e.ts)), 0.6, 0.6, 0.6)
    for _, p in ipairs(e.players or {}) do
        if p.choice or p.roll then
            local right = (p.choice and L[p.choice] or "–") .. (p.roll and ("  " .. p.roll) or "")
            if p.winner then right = "|cff33ff33" .. right .. "|r" end
            GameTooltip:AddDoubleLine("|c" .. ClassHex(p.class) .. p.name .. "|r", right, 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:AddLine(L.historyRowTip, 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------- rows

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    -- native: the reputation list header art for groups (row.headerBg)
    row.headerBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.headerBg:SetAllPoints()
    if not (H.native and S.Atlas(row.headerBg, "header")) then row.headerBg:Hide() row.headerBg = nil end
    -- hover: native line highlight, or the classic quest log highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if H.native and S.Atlas(hl, "hover") then
        hl:SetAlpha(0.6)
    else
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.5)
    end

    -- group header: + / - (native: on the right like reputation headers,
    -- classic: on the left like the quest log)
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetSize(14, 14)
    row.arrow:SetPoint(H.native and "RIGHT" or "LEFT", H.native and -14 or 0, 0)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("LEFT", H.native and 16 or 16, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.when:SetPoint("RIGHT", H.native and -32 or -4, 0)
    row.when:SetTextColor(0.7, 0.7, 0.7)
    row.title:SetPoint("RIGHT", row.when, "LEFT", -6, 0)

    -- item
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.time:SetPoint("LEFT", 14, 0)
    row.time:SetWidth(34)
    row.time:SetJustifyH("LEFT")
    row.time:SetTextColor(0.55, 0.55, 0.55)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 50, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.winner = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.winner:SetPoint("RIGHT", -4, 0)
    row.winner:SetJustifyH("RIGHT")
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.item:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.item:SetPoint("RIGHT", row.winner, "LEFT", -6, 0)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        local data = self.data
        if not data then return end
        if data.kind == "group" then
            A:Toggle(data.id)
            H:Refresh()
        elseif IsModifiedClick and IsModifiedClick() and data.entry.link and HandleModifiedItemClick then
            HandleModifiedItemClick(data.entry.link)   -- shift: link in chat, ctrl: try on
        else
            A:ToggleEntry(data.entry)                  -- show / hide all rolls
            H:Refresh()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.data and self.data.kind ~= "group" then ShowEntryTooltip(self, self.data.entry) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function FillRow(row, data)
    row.data = data
    local isGroup = data.kind == "group"
    if row.headerBg then row.headerBg:SetShown(isGroup) end
    row.arrow:SetShown(isGroup)
    row.title:SetShown(isGroup)
    row.when:SetShown(isGroup)
    row.time:SetShown(not isGroup)
    row.icon:SetShown(not isGroup)
    row.item:SetShown(not isGroup)
    row.winner:SetShown(not isGroup)
    if isGroup then
        local title, when = GroupTitle(data)
        if not (H.native and S.Atlas(row.arrow, data.collapsed and "plus" or "minus")) then
            row.arrow:SetTexture(data.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
        end
        row.title:SetText(title .. " |cffbbbbbb(" .. data.count .. ")|r")
        row.when:SetText(when)
        if row.headerBg then
            row.bg:SetColorTexture(0, 0, 0, 0)
        else
            row.bg:SetColorTexture(1, 0.82, 0, 0.12)
        end
    elseif data.kind == "player" then
        -- one player's roll under an opened item
        local p, e = data.player, data.entry
        row.time:SetText("")
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", 72, 0)
        row.icon:SetSize(14, 14)
        row.icon:SetTexCoord(0, 1, 0, 1)
        row.icon:SetTexture(p.choice and CHOICE_TEX[p.choice] or QUESTION_TEX)
        row.icon:SetAlpha(p.choice == "pass" and 0.6 or 1)
        row.item:SetText(p.name or "?")
        if p.choice == "pass" or not p.choice then
            row.item:SetTextColor(0.5, 0.5, 0.5)
        else
            local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            if c then row.item:SetTextColor(c.r, c.g, c.b) else row.item:SetTextColor(0.9, 0.9, 0.9) end
        end
        local right = "|cff999999" .. (p.choice and L[p.choice] or "–") .. "|r"
        if p.roll then right = right .. (p.winner and "  |cff33ff33" or "  |cffffd100") .. p.roll .. "|r" end
        if p.winner then right = right .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" end
        row.winner:SetText(right)
        if A.IsMine(e) and p.winner then
            row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.18)
        elseif not (H.native and S.Atlas(row.bg, "line")) then
            row.bg:SetColorTexture(0, 0, 0, 0.3)
        end
    else
        local e = data.entry
        row.time:SetText(Date("%H:%M", e.ts))
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", 50, 0)
        row.icon:SetSize(18, 18)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon:SetAlpha(1)
        row.icon:SetTexture(e.texture or (ns.ItemIcon and ns.ItemIcon(e.link)) or QUESTION_TEX)
        row.item:SetText(ns.Rolls.ItemName(e.link) or "?")
        row.item:SetTextColor(QualityColor(e))
        row.winner:SetText(WinnerText(e))
        if A.IsMine(e) then
            row.bg:SetColorTexture(0.1, 0.6, 0.1, 0.18)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end
    end
end

-- ---------------------------------------------------------------- window

function H:Create()
    if self.frame then return self.frame end
    -- native WoW Forever window if the client has it, else the classic dialog
    local f = S.Panel("ForeverLootRollsHistoryFrame", UIParent, L.history)
    self.native = f ~= nil
    f = f or CreateFrame("Frame", "ForeverLootRollsHistoryFrame", UIParent, BACKDROP_TEMPLATE)
    f:SetSize(WIDTH, HEIGHT)
    if not self.native and f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",   -- black, opacity from the settings
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    f:SetFrameStrata("MEDIUM")  -- a normal window, like the bags
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 12, 0) end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    self.frame = f

    if self.native then
        self.insetBg = S.Inset(f, 6, 24, 4, BOTTOM - 6)
    else
        local banner = f:CreateTexture(nil, "ARTWORK")
        banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        banner:SetSize(260, 56)
        banner:SetPoint("TOP", 0, 12)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOP", banner, "TOP", 0, -12)
        title:SetText(L.history)

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetSize(28, 28)
        close:SetPoint("TOPRIGHT", -4, -4)
    end

    -- filter: only my wins (native: the minimal checkbox from the reputation pane)
    local mine = (self.native and S.CheckButton(f)) or CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    mine:SetSize(24, 24)
    mine:SetPoint("TOPLEFT", PAD - 4, -24)
    local mineText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mineText:SetPoint("LEFT", mine, "RIGHT", 2, 0)
    mineText:SetText(L.onlyMine)
    mine:SetScript("OnClick", function()
        H.onlyMine = not H.onlyMine
        mine:SetChecked(H.onlyMine)
        H.offset = 0
        H:Refresh()
    end)
    -- quality filter: all / from uncommon / from rare / from epic.
    -- Blizzard's dropdown where the client has it, else a button that cycles.
    local function SetMinQuality(q)
        if ns.db then ns.db.historyMinQuality = q end
        H.offset = 0
        H:Refresh()
    end
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetWidth(150)
        dropdown:SetPoint("RIGHT", f, "TOPRIGHT", -PAD - 2, -36)
        dropdown:SetupMenu(function(_, root)
            for _, q in ipairs(H.QUALITY_STEPS) do
                root:CreateRadio(H.QualityLabel(q),
                    function() return H:MinQuality() == q end,
                    function() SetMinQuality(q) end, q)
            end
        end)
        self.qualityDropdown = dropdown
    else
        local quality = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        quality:SetSize(130, 20)
        quality:SetPoint("RIGHT", f, "TOPRIGHT", -PAD - 2, -36)
        quality:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        quality:SetScript("OnClick", function(_, mouse)
            local idx = 1
            for i, q in ipairs(H.QUALITY_STEPS) do if q == H:MinQuality() then idx = i end end
            idx = idx + (mouse == "RightButton" and -1 or 1)
            if idx > #H.QUALITY_STEPS then idx = 1 elseif idx < 1 then idx = #H.QUALITY_STEPS end
            SetMinQuality(H.QUALITY_STEPS[idx])
        end)
        quality:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(L.qualityFilter)
            GameTooltip:AddLine(L.qualityFilterTip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        quality:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.qualityButton = quality
    end

    self.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.count:SetPoint("BOTTOMRIGHT", -PAD - 2, 20)   -- re-anchored to the bottom bar (native)
    self.count:SetTextColor(0.7, 0.7, 0.7)

    -- list area
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", PAD, -TOP)
    view:SetPoint("BOTTOMRIGHT", -PAD - SCROLLBAR_W - 4, BOTTOM)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) H:ScrollBy(-delta * 3) end)
    self.view = view
    self.visible = math.floor((HEIGHT - TOP - BOTTOM) / ROW_H)
    self.rows = {}
    for i = 1, self.visible do
        local row = CreateRow(view)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        self.rows[i] = row
    end

    self.empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("TOP", 0, -30)
    self.empty:SetText(L.historyEmpty)

    -- native: Blizzard's slim scroll bar, driving the row offset
    local nativeBar = self.native and S.ScrollBar(f)
    if nativeBar then
        nativeBar:SetPoint("TOPRIGHT", -PAD + 4, -TOP)
        nativeBar:SetPoint("BOTTOMRIGHT", -PAD + 4, BOTTOM)
        local event = (BaseScrollBoxEvents and BaseScrollBoxEvents.OnScroll) or "OnScroll"
        nativeBar:RegisterCallback(event, function(_, pct)
            if H.settingBar then return end
            local maxOffset = math.max(0, #(H.data or {}) - H.visible)
            H.offset = math.floor((tonumber(pct) or 0) * maxOffset + 0.5)
            H:Draw()
        end, H)
        self.nativeBar = nativeBar
    end
    local bar = CreateFrame("Slider", nil, f)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", -PAD + 2, -TOP)
    bar:SetPoint("BOTTOMRIGHT", -PAD + 2, BOTTOM)
    bar:SetValueStep(1)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.5)
    bar.thumb = bar:CreateTexture(nil, "OVERLAY")
    bar.thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    bar.thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875)
    bar.thumb:SetSize(SCROLLBAR_W, 24)
    bar:SetThumbTexture(bar.thumb)
    bar:SetScript("OnValueChanged", function(_, v)
        if H.settingBar then return end
        H.offset = math.floor(v + 0.5)
        H:Draw()
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta) H:ScrollBy(-delta * 3) end)
    if nativeBar then
        bar:Hide()
        self.bar = nativeBar
    else
        self.bar = bar
    end

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(130, 22)
    if self.native then
        -- bottom bar under the list: button left, item count right, both centred
        local footer = S.Footer(f, BOTTOM - 6)
        clear:SetPoint("LEFT", footer, "LEFT", 6, 0)
        clear:SetFrameLevel((footer:GetFrameLevel() or 1) + 2)
        self.count:SetParent(footer)
        self.count:ClearAllPoints()
        self.count:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
        self.footer = footer
    else
        clear:SetPoint("BOTTOMLEFT", PAD - 2, 14)
    end
    clear:SetText(L.historyClear)
    clear:SetScript("OnClick", function()
        if StaticPopup_Show then StaticPopup_Show("FOREVERLOOTROLLS_CLEAR_HISTORY") end
    end)
    self.clearButton = clear

    if UISpecialFrames then tinsert(UISpecialFrames, f:GetName()) end
    self.offset = 0
    return f
end

function H:ScrollBy(n)
    self.offset = (self.offset or 0) + n
    self:Draw()
end

function H:Draw()
    local rows = self.data or {}
    local maxOffset = math.max(0, #rows - self.visible)
    self.offset = math.min(maxOffset, math.max(0, self.offset or 0))
    for i, row in ipairs(self.rows) do
        local data = rows[self.offset + i]
        if data then
            FillRow(row, data)
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end
    self.empty:SetShown(#rows == 0)
    if maxOffset > 0 and self.nativeBar then
        self.settingBar = true
        if self.bar.SetVisibleExtentPercentage then self.bar:SetVisibleExtentPercentage(self.visible / #rows) end
        if self.bar.SetPanExtentPercentage then self.bar:SetPanExtentPercentage(math.min(1, 3 / maxOffset)) end
        self.bar:SetScrollPercentage(self.offset / maxOffset,
            ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation)
        self.settingBar = nil
        self.bar:Show()
    elseif maxOffset > 0 then
        self.bar:SetMinMaxValues(0, maxOffset)
        self.settingBar = true
        self.bar:SetValue(self.offset)
        self.settingBar = nil
        self.bar:Show()
    else
        self.bar:Hide()
    end
end

-- same background opacity setting as the roll window
function H:ApplyOpacity()
    local f = self.frame
    if self.native then
        local v = ns.db and ns.db.opacity
        if v == nil then v = ns.DEFAULTS and ns.DEFAULTS.opacity or 100 end
        local a = math.max(0, math.min(1, (tonumber(v) or 100) / 100))
        if self.insetBg then self.insetBg:SetAlpha(a) end
        if type(f.Bg) == "table" and f.Bg.SetAlpha then f.Bg:SetAlpha(a) end
        return
    end
    if f and f.SetBackdropColor then
        local v = ns.db and ns.db.opacity
        if v == nil then v = ns.DEFAULTS and ns.DEFAULTS.opacity or 100 end
        f:SetBackdropColor(0, 0, 0, math.max(0, math.min(1, (tonumber(v) or 100) / 100)))
    end
end

H.QUALITY_STEPS = { 0, 2, 3, 4 }

function H:MinQuality()
    return tonumber(ns.db and ns.db.historyMinQuality) or 0
end

function H.QualityLabel(q)
    if not q or q <= 0 then return L.allQualities end
    return L.fromQuality:format(H.QualityName(q))
end

function H.QualityName(q)
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then
        name = ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
    end
    return name
end

function H:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    self:ApplyOpacity()
    local minQ = self:MinQuality()
    if self.qualityDropdown then
        if self.qualityDropdown.GenerateMenu then self.qualityDropdown:GenerateMenu() end
    elseif self.qualityButton then
        self.qualityButton:SetText(H.QualityLabel(minQ))
    end
    self.data = A:Rows(self.onlyMine, minQ)
    local items = 0
    for _, r in ipairs(self.data) do
        if r.kind == "group" then items = items + r.count end
    end
    self.count:SetText(L.historyCount:format(items))
    self:Draw()
end

function H:Toggle()
    local f = self:Create()
    if f:IsShown() then
        f:Hide()
        return
    end
    f:ClearAllPoints()
    local main = ns.UI and ns.UI.frame
    if main and main:IsShown() then
        f:SetPoint("TOPRIGHT", main, "TOPLEFT", -2, 0)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    self.offset = 0
    self:Refresh()
end

if StaticPopupDialogs then
    StaticPopupDialogs["FOREVERLOOTROLLS_CLEAR_HISTORY"] = {
        text = L.historyClearConfirm,
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function() A:Clear() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

A:On(function() H:Refresh() end)
