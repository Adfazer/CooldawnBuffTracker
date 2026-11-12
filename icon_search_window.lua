-- Окно поиска иконки: живой фильтр по базе баффов с превью.
-- Данные и запуск скана приходят извне (setProvider/setScanStarter),
-- выбор иконки отдаётся наружу через setPicker.
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")

local M = {}

local win
local editBox
local countLabel
local pageLabel
local rows = {}
local results = {}
local page = 1
local PER_PAGE = 9

local provider = nil
local setSpell = false
local scanStarter = nil
local picker = nil

local COLORS = {
    bg       = {0.055, 0.060, 0.070, 0.97},
    row      = {0.100, 0.110, 0.130, 0.92},
    rowHover = {0.170, 0.190, 0.230, 0.95},
    text     = {0.870, 0.690, 0.000, 1},
    muted    = {0.760, 0.630, 0.280, 1},
    accent   = {0.850, 0.700, 0.320, 1},
}

local function setLabelColor(label, c)
    if label and label.style then
        label.style:SetColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function makeRow(index)
    local row = win:CreateChildWidget("button", "cbtIconRow" .. index, 0, true)
    row:SetExtent(516, 34)
    row:AddAnchor("TOPLEFT", win, 20, 96 + (index - 1) * 38)
    row:SetText("")

    local bg = row:CreateColorDrawable(COLORS.row[1], COLORS.row[2], COLORS.row[3], COLORS.row[4], "background")
    bg:AddAnchor("TOPLEFT", row, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", row, 0, 0)
    row.bg = bg

    local icon = CreateItemIconButton("cbtIconRowIcon" .. index, row)
    if icon then
        icon:SetExtent(28, 28)
        icon:AddAnchor("LEFT", row, 4, 0)
        icon:Show(true)
        row.icon = icon
    end

    local label = row:CreateChildWidget("label", "cbtIconRowLabel" .. index, 0, true)
    label:SetExtent(430, 20)
    label:AddAnchor("LEFT", row, 42, 0)
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(14)
    label:SetText("")
    setLabelColor(label, COLORS.text)
    if label.Clickable then label:Clickable(false) end
    row.nameLabel = label

    row:SetHandler("OnEnter", function(self)
        if self.bg then
            self.bg:SetColor(COLORS.rowHover[1], COLORS.rowHover[2], COLORS.rowHover[3], COLORS.rowHover[4])
        end
    end)
    row:SetHandler("OnLeave", function(self)
        if self.bg then
            self.bg:SetColor(COLORS.row[1], COLORS.row[2], COLORS.row[3], COLORS.row[4])
        end
    end)
    row:SetHandler("OnClick", function(self)
        if picker and self.iconPath then
            picker(self.iconPath, self.iconName, setSpell)
        end
    end)

    row:Show(false)
    return row
end

local function refresh()
    if not win or not win:IsVisible() then return end
    local query = ""
    if editBox and editBox.GetText then
        query = editBox:GetText() or ""
    end
    results = {}
    if provider then
        local ok, list = pcall(provider, query, 500)
        if ok and type(list) == "table" then
            results = list
        end
    end
    local total = #results
    local pages = 1
    if total > 0 then
        pages = math.ceil(total / PER_PAGE)
    end
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    if countLabel then
        if total == 0 then
            countLabel:SetText("Nothing found. Press Scan dump or change the query.")
        else
            countLabel:SetText("Found: " .. total .. " (click a row to apply the icon)")
        end
    end
    if pageLabel then
        pageLabel:SetText(page .. "/" .. pages)
    end

    for i = 1, PER_PAGE do
        local row = rows[i]
        if row then
            local index = (page - 1) * PER_PAGE + i
            local item = results[index]
            if item then
                row.iconPath = item.path
                row.iconName = item.name
                if row.nameLabel then row.nameLabel:SetText(tostring(item.name or "")) end
                if row.icon then
                    F_SLOT.SetIconBackGround(row.icon, item.path or "game/ui/icon/icon_buff_debuff.dds")
                end
                row:Show(true)
            else
                row:Show(false)
            end
        end
    end
end

local function buildWindow()
    win = api.Interface:CreateEmptyWindow("cbtIconSearch")
    if not win then return end
    win:SetExtent(560, 520)
    win:SetUILayer("dialog")
    pcall(function() win:SetCloseOnEscape(true) end)
    pcall(function() win:EnableHidingIsRemove(false) end)
    win:AddAnchor("CENTER", "UIParent", 0, 0)
    win:SetHandler("OnCloseByEsc", function() win:Show(false) end)

    local winBg = win:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    winBg:SetTextureInfo("bg_quest")
    winBg:SetInset(6, 6, 6, 6)
    winBg:SetColor(0.045, 0.048, 0.055, 0.98)
    winBg:AddAnchor("TOPLEFT", win, 0, 0)
    winBg:AddAnchor("BOTTOMRIGHT", win, 0, 0)

    local header = win:CreateChildWidget("emptywidget", "cbtIconSearchHeader", 0, true)
    header:SetExtent(560, 30)
    header:AddAnchor("TOPLEFT", win, 0, 0)
    header:AddAnchor("TOPRIGHT", win, 0, 0)
    header:Clickable(true)
    local headerBg = header:CreateColorDrawable(0.015, 0.015, 0.020, 0.96, "background")
    headerBg:AddAnchor("TOPLEFT", header, 0, 0)
    headerBg:AddAnchor("BOTTOMRIGHT", header, 0, 0)

    local titleLabel = header:CreateChildWidget("label", "cbtIconSearchTitle", 0, true)
    titleLabel:SetExtent(300, 22)
    titleLabel:AddAnchor("LEFT", header, 12, 0)
    titleLabel.style:SetFontSize(18)
    titleLabel.style:SetAlign(ALIGN.LEFT)
    titleLabel.style:SetColor(0.87, 0.69, 0.0, 1)
    titleLabel:SetText("Icon search")

    local closeBtn = header:CreateChildWidget("button", "cbtIconSearchCloseBtn", 0, true)
    closeBtn:SetExtent(20, 20)
    closeBtn:AddAnchor("RIGHT", header, -8, 0)
    api.Interface:ApplyButtonSkin(closeBtn, BUTTON_BASIC.WINDOW_SMALL_CLOSE)
    closeBtn:SetHandler("OnClick", function() win:Show(false) end)

    header:EnableDrag(true)
    header:SetHandler("OnDragStart", function()
        win:StartMoving()
        pcall(function() api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0) end)
    end)
    header:SetHandler("OnDragStop", function()
        win:StopMovingOrSizing()
        pcall(function() api.Cursor:ClearCursor() end)
    end)
    win.header = header

    local bg = win:CreateChildWidget("emptywidget", "cbtIconSearchBody", 0, false)
    if bg then
        bg:SetExtent(552, 482)
        bg:AddAnchor("TOPLEFT", win, 4, 34)
        bg:Show(true)
        local plate = bg:CreateColorDrawable(COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], COLORS.bg[4], "background")
        plate:AddAnchor("TOPLEFT", bg, 0, 0)
        plate:AddAnchor("BOTTOMRIGHT", bg, 0, 0)
    end

    editBox = helpers.createEdit("cbtIconSearchEdit", win, "", 20, 44)
    editBox:SetExtent(380, 24)
    if editBox.CreateGuideText then
        pcall(function() editBox:CreateGuideText("Start typing a skill or buff name...", ALIGN.LEFT) end)
    end
    editBox:SetHandler("OnTextChanged", function()
        page = 1
        refresh()
    end)
    editBox:SetHandler("OnEnterPressed", function(self)
        if self and self.ClearFocus then self:ClearFocus() end
    end)

    local scanButton = helpers.createButton("cbtIconSearchScan", win, "Scan dump", 410, 44)
    scanButton:SetExtent(126, 24)
    scanButton:Show(true)
    scanButton:SetHandler("OnClick", function()
        if scanStarter then
            scanStarter()
        end
        if countLabel then
            countLabel:SetText("Scan started... the database will refresh when done")
        end
    end)

    countLabel = helpers.createLabel("cbtIconSearchCount", win, "", 20, 74, 14)
    countLabel:SetExtent(380, 18)
    setLabelColor(countLabel, COLORS.muted)

    -- Опция: вместе с иконкой подставлять и Spell (имя выбранного баффа)
    local spellToggle = helpers.createButton("cbtIconSearchSpell", win, "Spell: OFF", 410, 72)
    spellToggle:SetExtent(126, 24)
    spellToggle:Show(true)
    spellToggle:SetHandler("OnClick", function()
        setSpell = not setSpell
        spellToggle:SetText(setSpell and "Spell: ON" or "Spell: OFF")
        if setSpell then
            setLabelColor(spellToggle.textLabel, COLORS.text)
        else
            setLabelColor(spellToggle.textLabel, COLORS.muted)
        end
    end)

    for i = 1, PER_PAGE do
        rows[i] = makeRow(i)
    end

    local prev = helpers.createButton("cbtIconSearchPrev", win, "<", 20, 448)
    prev:SetExtent(70, 26)
    prev:Show(true)
    prev:SetHandler("OnClick", function()
        if page > 1 then
            page = page - 1
            refresh()
        end
    end)

    pageLabel = helpers.createLabel("cbtIconSearchPage", win, "1/1", 100, 452, 14)
    pageLabel:SetExtent(80, 20)
    setLabelColor(pageLabel, COLORS.text)

    local nextBtn = helpers.createButton("cbtIconSearchNext", win, ">", 190, 448)
    nextBtn:SetExtent(70, 26)
    nextBtn:Show(true)
    nextBtn:SetHandler("OnClick", function()
        page = page + 1
        refresh()
    end)

    local closeBtn = helpers.createButton("cbtIconSearchClose", win, "Close", 436, 448)
    closeBtn:SetExtent(100, 26)
    closeBtn:Show(true)
    closeBtn:SetHandler("OnClick", function()
        win:Show(false)
    end)
end

function M.setProvider(fn) provider = fn end
function M.setScanStarter(fn) scanStarter = fn end
function M.setPicker(fn) picker = fn end

function M.open(initialText)
    if not win then
        buildWindow()
    end
    if not win then return end
    win:Show(true)
    if editBox then
        editBox:SetText(tostring(initialText or ""))
        if editBox.SetFocus then pcall(function() editBox:SetFocus() end) end
    end
    page = 1
    refresh()
end

function M.refresh()
    refresh()
end

function M.close()
    if win then win:Show(false) end
end

function M.Unload()
    if win ~= nil then
        if win.header then
            pcall(function() win.header:ReleaseHandler("OnDragStop") end)
            pcall(function() win.header:ReleaseHandler("OnDragStart") end)
        end
        pcall(function() win:Show(false) end)
        pcall(function() api.Interface:Free(win) end)
        win = nil
    end
    rows = {}
    results = {}
    editBox = nil
    countLabel = nil
    pageLabel = nil
end

return M
