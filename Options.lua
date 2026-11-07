-- Settings page (Game Menu → Options → AddOns → Forever Loot Rolls),
-- also opened by the gear in the window and /lootrolls options.
local _, ns = ...
local L = ns.L

local function Refresh() if ns.UI then ns.UI:Refresh() end end
local function ApplyEscape() if ns.UI then ns.UI:ApplyEscape() end end
local function ApplyHistory() if ns.ApplyHistorySize then ns.ApplyHistorySize() end end

local COLLAPSE_CHOICES = {
    { "instant", L.collapseInstant },
    { "delay", L.collapseDelay },
    { "newroll", L.collapseNewRoll },
    { "never", L.collapseNever },
}

-- All settings, in page order.
local ROWS = {
    { "header", L.optWindow },
    { "check", "rollButtons", L.optRollButtons, L.optRollButtonsTip, Refresh },
    { "check", "closeOnEscape", L.optCloseOnEscape, L.optCloseOnEscapeTip, ApplyEscape },
    { "cycle", "collapseMode", L.optCollapse, L.optCollapseTip, Refresh, choices = COLLAPSE_CHOICES },
    { "step", "collapseDelay", L.optCollapseDelay, L.optCollapseDelayTip, nil, 1, 60, 1,
        parent = "collapseMode", active = function(db) return db.collapseMode == "delay" end },
    { "step", "maxHeight", L.optMaxHeight, L.optMaxHeightTip, Refresh, 200, 800, 20 },
    { "step", "opacity", L.optOpacity, L.optOpacityTip,
        function()
            if ns.UI then ns.UI:ApplyOpacity() end
            if ns.HistoryUI then ns.HistoryUI:ApplyOpacity() end
        end, 0, 100, 5 },

    { "header", L.optDungeon },
    { "check", "openOnEnterDungeon", L.optOpenOnEnter, L.optOpenOnEnterTip },
    { "check", "dungeonAutoOpen", L.optAutoOpen, L.optAutoOpenTip },
    { "check", "dungeonAutoClose", L.optAutoClose, L.optAutoCloseTip },
    { "step", "dungeonCloseDelay", L.optCloseDelay, L.optCloseDelayTip, nil, 2, 60, 1,
        parent = "dungeonAutoClose", active = function(db) return db.dungeonAutoClose end },

    { "header", L.optWorld },
    { "check", "worldAutoOpen", L.optAutoOpen, L.optAutoOpenTip },
    { "check", "worldAutoClose", L.optAutoClose, L.optAutoCloseTip },
    { "step", "worldCloseDelay", L.optCloseDelay, L.optCloseDelayTip, nil, 2, 60, 1,
        parent = "worldAutoClose", active = function(db) return db.worldAutoClose end },

    { "header", L.optHistory },
    { "check", "clearOnNewInstance", L.optClearOnInstance, L.optClearOnInstanceTip },
    { "step", "historySize", L.optHistorySize, L.optHistorySizeTip, ApplyHistory, 5, 100, 5 },
    { "step", "archiveSize", L.optArchiveSize, L.optArchiveSizeTip,
        function() if ns.ApplyArchiveSize then ns.ApplyArchiveSize() end end, 100, 5000, 100 },
}

-- ---------------------------------------------------------------- Blizzard page

local category

local function Register()
    if category or not (Settings and Settings.RegisterVerticalLayoutCategory and ns.db) then return end
    category = Settings.RegisterVerticalLayoutCategory(L.title)
    local inits = {}

    for _, row in ipairs(ROWS) do
        local kind, key, label, tooltip, onChange = row[1], row[2], row[3], row[4], row[5]
        if kind == "header" then
            if Settings.RegisterInitializer and CreateSettingsListSectionHeaderInitializer then
                Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(key))
            end
        else
            local vtype = (kind == "check" and Settings.VarType.Boolean)
                or (kind == "cycle" and Settings.VarType.String) or Settings.VarType.Number
            local default = ns.DEFAULTS[key]
            if kind == "check" then default = default and Settings.Default.True or Settings.Default.False end
            local setting = Settings.RegisterAddOnSetting(category, "FOREVER_LOOT_ROLLS_" .. key:upper(), key,
                ns.db, vtype, label, default)
            if onChange then setting:SetValueChangedCallback(onChange) end

            local init
            if kind == "check" then
                init = Settings.CreateCheckbox(category, setting, tooltip)
            elseif kind == "step" and Settings.CreateSlider and Settings.CreateSliderOptions then
                local options = Settings.CreateSliderOptions(row[6], row[7], row[8])
                if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
                end
                init = Settings.CreateSlider(category, setting, options, tooltip)
            elseif kind == "cycle" then
                local create = Settings.CreateDropdown or Settings.CreateDropDown
                if create and Settings.CreateControlTextContainer then
                    local function GetOptions()
                        local container = Settings.CreateControlTextContainer()
                        for _, c in ipairs(row.choices) do container:Add(c[1], c[2]) end
                        return container:GetData()
                    end
                    init = create(category, setting, GetOptions, tooltip)
                end
            end
            inits[key] = init
            -- grey out a sub-setting while its parent setting does not apply
            local parent = row.parent and inits[row.parent]
            if init and parent and init.SetParentInitializer then
                pcall(init.SetParentInitializer, init, parent, function() return row.active(ns.db) end)
            end
        end
    end

    Settings.RegisterAddOnCategory(category)
end

-- ---------------------------------------------------------------- opening

-- Blizzard's settings window cannot be opened by addons during combat
-- (protected OpenSettingsPanel). Calling it anyway leaves a half-open,
-- invisible settings frame that swallows all clicks until Escape.
function ns.OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        local msg = ERR_NOT_IN_COMBAT or L.notInCombat
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1)
        else
            ns.Print(msg)
        end
        return
    end
    Register()
    if category and Settings.OpenToCategory then
        if not pcall(Settings.OpenToCategory, category:GetID()) then pcall(Settings.OpenToCategory, category) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", Register)
