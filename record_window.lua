-- Record window (debug mode): lists active buffs/debuffs or skills seen in the
-- combat log and lets the user add any of them to tracking with one click.
local api = require("api")
local helpers = require("CooldawnBuffTracker/helpers")
local CbtWindow = require("CooldawnBuffTracker/util/cbt_window")

local M = {}

local win
local rows = {}
local countLabel
local statusLabel
local pageLabel
local mode = "buff" -- "buff" | "log"
local unit = "player"
local modeButtons = {}
local PER_PAGE = 8
local page = 1
local results = {}
-- Журнал баффов больше не хранится в окне: его копит main.lua (UPDATE,
-- пока Debug: ON), окно только читает готовый журнал юнита.
local providerBuffLog
local providerLog
local addBuff
local addSpell
local clearLog       -- очистка журнала навыков
local clearBuffLog   -- очистка журнала баффов
local clearBtn
local refreshAcc = 0

local COLORS = {
    text  = {0.87, 0.69, 0.00, 1},
    muted = {0.72, 0.74, 0.80, 1},
}

local function setColor(widget, c)
    if widget and widget.style then
        widget.style:SetColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function refresh()
    if not win or not win:IsVisible() then return end
    results = {}
    local activeCount = 0
    if mode == "buff" then
        -- Журнал копится в main.lua, пока Debug: ON, — окно показывает и то,
        -- что было записано до его открытия (закрытое окно ничего не теряет).
        local list = {}
        if providerBuffLog then
            local ok, l = pcall(providerBuffLog, unit)
            if ok and type(l) == "table" then list = l end
        end
        for _, e in ipairs(list) do
            if e.active then activeCount = activeCount + 1 end
        end
        results = list
    else
        -- Журнал навыков боевого лога — свой на каждый юнит (Player/Mount/Target).
        if providerLog then
            local ok, list = pcall(providerLog, unit, 60)
            if ok and type(list) == "table" then results = list end
        end
    end

    local total = #results
    local pages = math.max(1, math.ceil(total / PER_PAGE))
    if page > pages then page = pages end
    if page < 1 then page = 1 end

    if countLabel then
        if mode == "buff" then
            countLabel:SetText("Buffs seen: " .. total .. " (active " .. activeCount .. ")")
        else
            countLabel:SetText("Skills seen in combat log: " .. total)
        end
    end
    if pageLabel then pageLabel:SetText(page .. "/" .. pages) end

    for i = 1, PER_PAGE do
        local row = rows[i]
        local item = results[(page - 1) * PER_PAGE + i]
        if row then
            if item then
                row.item = item
                if row.nameLabel then
                    local title = tostring(item.name or item.id or "")
                    if mode == "buff" then
                        -- name [id] (xN) — как строка журнала навыков.
                        if item.id ~= nil and item.name ~= item.id then
                            title = title .. " [" .. tostring(item.id) .. "]"
                        end
                        if item.count then
                            title = title .. "  (x" .. tostring(item.count) .. ")"
                        end
                    elseif item.count then
                        title = title .. "  (x" .. tostring(item.count) .. ")"
                    end
                    row.nameLabel:SetText(title)
                end
                if row.icon then
                    F_SLOT.SetIconBackGround(row.icon, item.icon or "game/ui/icon/icon_buff_debuff.dds")
                end
                if row.nameLabel then
                    -- Активные записи — золотом, снятые — серым; журнал навыков
                    -- всегда обычным цветом (строка переиспользуется между вкладками).
                    local live = (mode ~= "buff") or item.active
                    setColor(row.nameLabel, live and COLORS.text or COLORS.muted)
                end
                row:Show(true)
            else
                row:Show(false)
            end
        end
    end
end

local function setMode(m)
    mode = m
    page = 1
    if modeButtons.buff and modeButtons.log then
        setColor(modeButtons.buff.textLabel, (mode == "buff") and COLORS.text or COLORS.muted)
        setColor(modeButtons.log.textLabel, (mode == "log") and COLORS.text or COLORS.muted)
    end
    if clearBtn then
        clearBtn:Show(true)
    end
    refresh()
end

local function makeRow(index)
    -- emptywidget, не button: кнопка-родитель перехватывает клики дочерних
    -- кнопок (см. references/ui-widgets-and-layout.md), Add перестал бы работать
    local row = win:CreateChildWidget("emptywidget", "cbtRecRow" .. index, 0, true)
    row:SetExtent(420, 30)
    row:AddAnchor("TOPLEFT", win, 20, 150 + (index - 1) * 34)

    local bg = row:CreateColorDrawable(0.10, 0.11, 0.13, 0.92, "background")
    bg:AddAnchor("TOPLEFT", row, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", row, 0, 0)
    row.bg = bg

    local icon = CreateItemIconButton("cbtRecIcon" .. index, row)
    if icon then
        icon:SetExtent(26, 26)
        icon:AddAnchor("LEFT", row, 4, 0)
        icon:Show(true)
        row.icon = icon
    end

    local label = row:CreateChildWidget("label", "cbtRecLabel" .. index, 0, true)
    label:SetExtent(270, 20)
    label:AddAnchor("LEFT", row, 36, 0)
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(13)
    setColor(label, COLORS.text)
    if label.Clickable then label:Clickable(false) end
    row.nameLabel = label

    local addBtn = helpers.createButton("cbtRecAdd" .. index, row, "Add", 330, 4)
    addBtn:SetExtent(80, 22)
    addBtn:Show(true)
    CbtWindow.Tooltip(addBtn,
        "Add to tracking on the current unit (creates a custom entry with a default CD/D when needed).")
    addBtn:SetHandler("OnClick", function()
        local item = row.item
        if not item then return end
        local ok, msg
        if mode == "buff" then
            if addBuff then ok, msg = addBuff(item.id) end
        else
            if addSpell then ok, msg = addSpell(item.name) end
        end
        if statusLabel then
            statusLabel:SetText(tostring(msg or ((ok and "Added: ") or "Failed: ") .. tostring(item.name or item.id or "")))
        end
        refresh()
    end)

    CbtWindow.Hover(row, function(self)
        if self.bg then self.bg:SetColor(0.16, 0.18, 0.22, 0.95) end
    end, function(self)
        if self.bg then self.bg:SetColor(0.10, 0.11, 0.13, 0.92) end
    end)
    CbtWindow.TooltipDynamic(row, function(self)
        local item = self.item
        if not item then return nil end
        local name = tostring(item.name or item.id or "")
        if mode == "buff" then
            return string.format("%s (id %s) - %s, seen %s time(s).",
                name, tostring(item.id), item.active and "active" or "faded",
                tostring(item.count or 1))
        end
        return string.format("%s - seen %s time(s) in the combat log.",
            name, tostring(item.count or 1))
    end)

    row:Show(false)
    return row
end

local function build()
    win = CbtWindow.Create("cbtRecord", "Record (Debug)", 460, 500, function()
        if win then win:Show(false) end
    end)
    if not win then return end

    modeButtons.buff = helpers.createButton("cbtRecModeBuff", win, "Buff log", 20, 42)
    modeButtons.buff:SetExtent(150, 26)
    modeButtons.buff:Show(true)
    CbtWindow.Tooltip(modeButtons.buff,
        "Buff journal: every buff/debuff seen while Debug is ON, active and faded, newest first.")
    modeButtons.buff:SetHandler("OnClick", function() setMode("buff") end)

    modeButtons.log = helpers.createButton("cbtRecModeLog", win, "Log skills", 180, 42)
    modeButtons.log:SetExtent(150, 26)
    modeButtons.log:Show(true)
    CbtWindow.Tooltip(modeButtons.log,
        "Skills seen in the combat log for the selected unit, newest first.")
    modeButtons.log:SetHandler("OnClick", function() setMode("log") end)

    local scanBtn = helpers.createButton("cbtRecScan", win, "Rescan dump", 340, 42)
    scanBtn:SetExtent(100, 26)
    CbtWindow.Tooltip(scanBtn, "Scan the client buff table again and rebuild the icon/name dump.")
    scanBtn:Show(true)
    scanBtn:SetHandler("OnClick", function()
        if M.scanStarter then M.scanStarter() end
        if statusLabel then statusLabel:SetText("Dump scan started...") end
    end)

    -- юнит для вкладки Active buffs
    local unitLabel = helpers.createLabel("cbtRecUnitLabel", win, "Unit:", 20, 76, 13)
    unitLabel:SetExtent(40, 18)
    setColor(unitLabel, COLORS.muted)
    unitLabel:Show(true)
    CbtWindow.Tooltip(unitLabel, "Unit whose journal is listed below.")

    local unitButtons = {}
    local function setUnit(u)
        unit = u
        for key, btn in pairs(unitButtons) do
            setColor(btn.textLabel, (key == unit) and COLORS.text or COLORS.muted)
        end
        refresh()
    end
    local ux = 64
    for _, u in ipairs({ "player", "playerpet", "target" }) do
        local btn = helpers.createButton("cbtRecUnit_" .. u, win, (u == "playerpet") and "Mount" or (u == "player") and "Player" or "Target", ux, 72)
        btn:SetExtent(80, 22)
        btn:Show(true)
        CbtWindow.Tooltip(btn, "Show the " .. ((u == "playerpet") and "Mount"
            or (u == "player") and "Player" or "Target") .. " journal.")
        unitButtons[u] = btn
        btn:SetHandler("OnClick", function() setUnit(u) end)
        ux = ux + 86
    end
    M.setUnit = setUnit

    clearBtn = helpers.createButton("cbtRecClear", win, "Clear log", 330, 72)
    clearBtn:SetExtent(110, 24)
    clearBtn:Show(true)
    CbtWindow.TooltipDynamic(clearBtn, function()
        return "Clear the " .. (mode == "buff" and "buff journal" or "skill log")
            .. " of the selected unit."
    end)
    clearBtn:SetHandler("OnClick", function()
        if mode == "buff" then
            if clearBuffLog then clearBuffLog(unit) end
            if statusLabel then statusLabel:SetText("Buff log cleared") end
        else
            if clearLog then clearLog(unit) end
            if statusLabel then statusLabel:SetText("Skill log cleared") end
        end
        page = 1
        refresh()
    end)

    countLabel = helpers.createLabel("cbtRecCount", win, "", 20, 102, 14)
    countLabel:SetExtent(420, 18)
    setColor(countLabel, COLORS.muted)
    countLabel:Show(true)
    CbtWindow.Tooltip(countLabel, "Entries in the current tab; buffs also show how many are active.")

    statusLabel = helpers.createLabel("cbtRecStatus", win, "", 20, 124, 13)
    statusLabel:SetExtent(420, 18)
    setColor(statusLabel, COLORS.text)
    statusLabel:Show(true)

    for i = 1, PER_PAGE do
        rows[i] = makeRow(i)
    end

    local prev = helpers.createButton("cbtRecPrev", win, "<", 20, 446)
    prev:SetExtent(60, 26)
    prev:Show(true)
    CbtWindow.Tooltip(prev, "Previous page.")
    prev:SetHandler("OnClick", function()
        if page > 1 then page = page - 1; refresh() end
    end)

    pageLabel = helpers.createLabel("cbtRecPage", win, "1/1", 90, 450, 14)
    pageLabel:SetExtent(80, 20)
    setColor(pageLabel, COLORS.text)
    pageLabel:Show(true)
    CbtWindow.TooltipDynamic(pageLabel, function(self)
        return "Page " .. tostring(self:GetText() or "1/1") .. " - 8 entries per page."
    end)

    local nextBtn = helpers.createButton("cbtRecNext", win, ">", 170, 446)
    nextBtn:SetExtent(60, 26)
    nextBtn:Show(true)
    CbtWindow.Tooltip(nextBtn, "Next page.")
    nextBtn:SetHandler("OnClick", function() page = page + 1; refresh() end)

    local closeBtn = helpers.createButton("cbtRecClose", win, "Close", 340, 446)
    closeBtn:SetExtent(100, 26)
    closeBtn:Show(true)
    CbtWindow.Tooltip(closeBtn, "Close the Record window.")
    closeBtn:SetHandler("OnClick", function() win:Show(false) end)

    -- Живое обновление: список обновляется, пока окно открыто (не только по вкладкам)
    win:SetHandler("OnUpdate", function(self, dt)
        if not win or not win:IsVisible() then return end
        refreshAcc = refreshAcc + (dt or 0)
        if refreshAcc >= 200 then
            refreshAcc = 0
            refresh()
        end
    end)

    local hint = helpers.createLabel("cbtRecHint", win,
        "Add: buff -> custom entry + tracking. Skill -> custom entry with Spell filled.", 20, 424, 11)
    hint:SetExtent(420, 16)
    setColor(hint, COLORS.muted)
    hint:Show(true)
end

function M.getUnit()
    return unit
end

-- Провайдеры из settings_page: журнал навыков (logFn) и журнал баффов из
-- main.lua (buffLogFn, копится, пока Debug: ON), плюс их очистка.
function M.setProviders(logFn, addBuffFn, addSpellFn, clearFn, buffLogFn, clearBuffFn)
    providerLog = logFn
    addBuff = addBuffFn
    addSpell = addSpellFn
    clearLog = clearFn
    providerBuffLog = buffLogFn
    clearBuffLog = clearBuffFn
end

function M.open()
    if not win then build() end
    if not win then return end
    win:Show(true)
    setMode("buff")
end

function M.refresh()
    refresh()
end

function M.close()
    if win then win:Show(false) end
end

function M.Unload()
    if win then
        pcall(function() CbtWindow.Destroy(win) end)
        win = nil
    end
    rows = {}
    results = {}
end

return M
