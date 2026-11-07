-- Native WoW Forever look ("Camelot" UI, as in the character / reputation
-- window): metal panel frame, character pane background, list headers with
-- +/-, striped rows, reputation style progress bar, minimal scroll
-- bar and minimal checkboxes.
-- Every helper checks that the client has the template or atlas and returns
-- nil / false otherwise, so the windows fall back to their classic look.
local _, ns = ...
local S = {}
ns.Skin = S

S.ATLAS = {
    panelBg = "UI-Character-Info-General-BG",
    inset = "common-insideframe",
    header = "common-button-list-collapseExpand",
    plus = "common-button-list-plus",
    minus = "common-button-list-minus",
    line = "UI-Character-Info-Line-Bounce",
    hover = "charactercreate-customize-dropdown-linemouseover-middle",
    checkbox = "checkbox-minimal",
    checkmark = "checkmark-minimal",
}

function S.HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Puts an atlas on a texture. Returns false (texture untouched) if the client lacks it.
function S.Atlas(tex, key, useAtlasSize)
    local name = S.ATLAS[key] or key
    if tex and tex.SetAtlas and S.HasAtlas(name) then
        tex:SetAtlas(name, useAtlasSize and true or false)
        return true
    end
    return false
end

local function IsTable(v) return type(v) == "table" end

-- Blizzard's standard window: metal frame, title bar, close button.
function S.Panel(name, parent, title)
    local ok, f = pcall(CreateFrame, "Frame", name, parent, "DefaultPanelFlatTemplate")
    if not (ok and f and f.NineSlice) then return nil end
    if f.SetTitle then
        pcall(f.SetTitle, f, title)
    elseif IsTable(f.TitleContainer) and IsTable(f.TitleContainer.TitleText) then
        f.TitleContainer.TitleText:SetText(title)
    end
    local okClose, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButtonDefaultAnchors")
    if not (okClose and close) then
        close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 1)
    end
    f.CloseButton = close
    return f
end

-- Dark character pane background with the thin inside frame, between the
-- given offsets from the panel edges. Returns the background texture.
function S.Inset(parent, left, top, right, bottom)
    local bg = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetPoint("TOPLEFT", left, -top)
    bg:SetPoint("BOTTOMRIGHT", -right, bottom)
    if not S.Atlas(bg, "panelBg") then bg:SetColorTexture(0, 0, 0, 1) end
    local border = parent:CreateTexture(nil, "BORDER", nil, 1)
    border:SetPoint("TOPLEFT", left - 1, -top + 1)
    border:SetPoint("BOTTOMRIGHT", -right + 1, bottom - 1)
    if not S.Atlas(border, "inset") then border:Hide() end
    return bg
end

-- Blizzard's slim scroll bar, hooked up to a ScrollFrame. nil if unavailable.
function S.ScrollBarFor(parent, scrollFrame)
    if not (ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then return nil end
    local ok, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
    if not (ok and bar and bar.SetScrollPercentage) then return nil end
    if scrollFrame then ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, bar) end
    return bar
end

-- A bare MinimalScrollBar for lists that scroll by rows themselves.
function S.ScrollBar(parent)
    local ok, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
    if ok and bar and bar.SetScrollPercentage and bar.RegisterCallback then return bar end
    return nil
end

-- The reputation bar (ColoredProgressBarTemplate). nil if unavailable.
function S.ProgressBar(parent)
    local ok, bar = pcall(CreateFrame, "Frame", nil, parent, "ColoredProgressBarTemplate")
    if ok and bar and bar.SetFillPercent then return bar end
    return nil
end

-- Minimal checkbox (as on the reputation detail pane). nil if the atlases are missing.
function S.CheckButton(parent)
    if not (S.HasAtlas(S.ATLAS.checkbox) and S.HasAtlas(S.ATLAS.checkmark)) then return nil end
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(26, 26)
    local normal = cb:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    S.Atlas(normal, "checkbox")
    cb:SetNormalTexture(normal)
    local checked = cb:CreateTexture(nil, "OVERLAY")
    checked:SetAllPoints()
    S.Atlas(checked, "checkmark")
    cb:SetCheckedTexture(checked)
    return cb
end
