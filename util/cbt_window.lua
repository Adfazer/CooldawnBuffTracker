-- Общий кастомный шелл окон аддона (тёмная тема в стиле BetterBars):
-- пустое окно + ninepart-фон + своя шапка (заголовок, крестик, drag) + ESC.
local api = require("api")
local locale = require("CooldawnBuffTracker/locale")

local M = {}
local flatSeq = 0

-- 1.31.0: оверлей цели живёт на слое normal с z-order 1000. Каждое окно
-- аддона должно рисоваться ВЫШЕ него: тот же слой, z-order 1100 и Raise,
-- иначе оверлей перекрывает настройки/диалоги, когда они пересекаются.
function M.KeepAboveOverlay(win)
    if win == nil then return end
    pcall(function() win:SetUILayer("normal") end)
    pcall(function() if win.SetZOrder then win:SetZOrder(1100) end end)
    pcall(function() win:Raise() end)
end

-- Создаёт окно с шапкой. onClose - необязательный колбэк (по умолчанию скрыть).
function M.Create(id, title, w, h, onClose)
    local win = api.Interface:CreateEmptyWindow(id)
    if not win then return nil end
    win:SetExtent(w, h)
    win:SetUILayer("normal")
    pcall(function() if win.SetZOrder then win:SetZOrder(1100) end end)
    pcall(function() win:SetCloseOnEscape(true) end)
    pcall(function() win:EnableHidingIsRemove(false) end)
    win:AddAnchor("CENTER", "UIParent", 0, 0)

    local close = function()
        if onClose then
            onClose()
        else
            win:Show(false)
        end
    end

    local bg = win:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    bg:SetTextureInfo("bg_quest")
    bg:SetInset(6, 6, 6, 6)
    bg:SetColor(0.045, 0.048, 0.055, 0.98)
    bg:AddAnchor("TOPLEFT", win, 0, 0)
    bg:AddAnchor("BOTTOMRIGHT", win, 0, 0)

    local header = win:CreateChildWidget("emptywidget", id .. "_header", 0, true)
    header:SetExtent(w, 34)
    header:AddAnchor("TOPLEFT", win, 0, 0)
    header:AddAnchor("TOPRIGHT", win, 0, 0)
    header:Clickable(true)
    local hb = header:CreateColorDrawable(0.015, 0.015, 0.020, 0.96, "background")
    hb:AddAnchor("TOPLEFT", header, 0, 0)
    hb:AddAnchor("BOTTOMRIGHT", header, 0, 0)

    local sep = header:CreateColorDrawable(0.25, 0.22, 0.12, 1, "background")
    sep:SetExtent(w - 12, 1)
    sep:AddAnchor("BOTTOMLEFT", header, 6, 0)
    sep:AddAnchor("BOTTOMRIGHT", header, -6, 0)

    local titleLabel = header:CreateChildWidget("label", id .. "_title", 0, true)
    titleLabel:SetExtent(w - 90, 24)
    titleLabel:AddAnchor("LEFT", header, 12, 0)
    titleLabel.style:SetFontSize(18)
    titleLabel.style:SetAlign(ALIGN.LEFT)
    titleLabel.style:SetColor(0.87, 0.69, 0.0, 1)
    -- Заголовок окна переводится здесь: CbtWindow.Create(id, title, ...) зовут
    -- с английским текстом, а показывается он на текущем языке.
    titleLabel:SetText(locale.L(title or ""))
    -- подпись не должна перехватывать мышь: иначе за заголовок окно не тянется
    if titleLabel.Clickable then titleLabel:Clickable(false) end
    pcall(function() titleLabel:EnablePick(false) end)

    local closeBtn = header:CreateChildWidget("button", id .. "_close", 0, true)
    closeBtn:SetExtent(20, 20)
    closeBtn:AddAnchor("RIGHT", header, -8, 0)
    api.Interface:ApplyButtonSkin(closeBtn, BUTTON_BASIC.WINDOW_SMALL_CLOSE)
    closeBtn:SetHandler("OnClick", close)

    header:EnableDrag(true)
    if header.RegisterForDrag then
        pcall(function() header:RegisterForDrag("LeftButton") end)
    end
    header:SetHandler("OnDragStart", function()
        pcall(function() win:Raise() end)
        win:StartMoving()
        pcall(function() api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0) end)
    end)
    header:SetHandler("OnDragStop", function()
        win:StopMovingOrSizing()
        pcall(function() api.Cursor:ClearCursor() end)
    end)
    header:SetHandler("OnDragEnd", function()
        win:StopMovingOrSizing()
        pcall(function() api.Cursor:ClearCursor() end)
    end)
    pcall(function()
        header:SetHandler("OnClick", function() win:Raise() end)
    end)
    if win.RegisterForDrag then
        pcall(function() win:RegisterForDrag("LeftButton") end)
    end
    win.header = header
    -- Шапка — единственная ручка перетаскивания: подсказываем это на ховере.
    M.Tooltip(header, "Drag to move the window.")
    M.Tooltip(closeBtn, "Close the window (Esc).")

    -- Тёмная подложка контента (первый ребёнок => под остальными элементами)
    local body = win:CreateChildWidget("emptywidget", id .. "_body", 0, false)
    body:SetExtent(w - 8, h - 42)
    body:AddAnchor("TOPLEFT", win, 4, 38)
    body:Show(true)
    local bb = body:CreateColorDrawable(0.055, 0.060, 0.070, 0.97, "background")
    bb:AddAnchor("TOPLEFT", body, 0, 0)
    bb:AddAnchor("BOTTOMRIGHT", body, 0, 0)
    win.body = body

    win:SetHandler("OnCloseByEsc", close)
    return win
end

function M.Destroy(win)
    if win == nil then return end
    if win.header then
        pcall(function() win.header:ReleaseHandler("OnDragStop") end)
        pcall(function() win.header:ReleaseHandler("OnDragStart") end)
    end
    pcall(function() win:Show(false) end)
    pcall(function() api.Interface:Free(win) end)
end

-- Чекбокс на нативной текстуре (CreateCheckButton в песочнице нет):
-- шесть состояний одного атласа + SetExtent, иначе виджет не кликается.
local CHECK_ART = (TEXTURE_PATH and TEXTURE_PATH.CHECK_BUTTON) or "ui/button/check_button.dds"
local CHECK_STATES = {
    { 0, 0, 18, 17 }, { 0, 0, 18, 17 }, { 0, 0, 18, 17 },
    { 0, 17, 18, 17 }, { 18, 0, 18, 17 }, { 18, 17, 18, 17 },
}

function M.CheckButton(id, parent, onChanged)
    if not parent then return nil end
    local w = parent:CreateChildWidget("checkbutton", id, 0, true)
    if not w then return nil end
    local bgs = {}
    for i = 1, 6 do
        local s = CHECK_STATES[i]
        local d = w:CreateImageDrawable(CHECK_ART, "background")
        if d then
            d:AddAnchor("CENTER", w, 0, 0)
            d:SetCoords(s[1], s[2], s[3], s[4])
            d:SetExtent(s[3], s[4])
        end
        bgs[i] = d
    end
    w:SetExtent(18, 17)
    if bgs[1] then w:SetNormalBackground(bgs[1]) end
    if bgs[2] then w:SetHighlightBackground(bgs[2]) end
    if bgs[3] then w:SetPushedBackground(bgs[3]) end
    if bgs[4] then w:SetDisabledBackground(bgs[4]) end
    if bgs[5] then w:SetCheckedBackground(bgs[5]) end
    if bgs[6] then w:SetDisabledCheckedBackground(bgs[6]) end
    w:SetHandler("OnCheckChanged", function(self)
        local checked = false
        pcall(function() checked = self:GetChecked() and true or false end)
        if onChanged then onChanged(checked, self) end
    end)
    return w
end

-- Всплывающая подсказка на ховере (SetTooltipOnPos: nil очищает).
-- SetHandler заменяет обработчик, поэтому фабрики кнопок и строк списков
-- кладут свой ховер-обработчик в поля _cbtHoverOnEnter/_cbtHoverOnLeave:
-- тултип вызывает его первым и не гасит подсветку ховера.
local HOVER_FIELD = {
    OnEnter = "_cbtHoverOnEnter",
    OnLeave = "_cbtHoverOnLeave",
}

local function chainHandler(widget, event, fn)
    local prev = widget[HOVER_FIELD[event]]
    widget:SetHandler(event, function(self, ...)
        if prev then pcall(prev, self, ...) end
        fn(self, ...)
    end)
end

-- Регистрирует ховер-обработчик виджета так, чтобы Tooltip мог его сохранить.
function M.Hover(widget, onEnter, onLeave)
    if not widget then return widget end
    if onEnter then
        widget._cbtHoverOnEnter = onEnter
        widget:SetHandler("OnEnter", onEnter)
    end
    if onLeave then
        widget._cbtHoverOnLeave = onLeave
        widget:SetHandler("OnLeave", onLeave)
    end
    return widget
end

-- Динамическая подсказка: текст считается в момент наведения, поэтому строки
-- списков (имя/id/значения) показывают актуальные данные без OnUpdate.
function M.TooltipDynamic(widget, textFn)
    if not widget or type(textFn) ~= "function" then return widget end
    chainHandler(widget, "OnEnter", function(self)
        local ok, text = pcall(textFn, self)
        if ok and type(text) == "string" and text ~= "" then
            -- Перевод в момент наведения: смена языка видна на следующем ховере.
            text = locale.L(text)
            pcall(function() api.Interface:SetTooltipOnPos(text, self, 0, -22) end)
        end
    end)
    chainHandler(widget, "OnLeave", function(self)
        pcall(function() api.Interface:SetTooltipOnPos(nil, self, 0, 0) end)
    end)
    return widget
end

function M.Tooltip(widget, text)
    if not widget or not text or text == "" then return widget end
    return M.TooltipDynamic(widget, function() return text end)
end


-- Перекрашивает готовую кнопку в плоский тёмный стиль, сохраняя анкоры и OnClick.
function M.FlattenButton(btn)
    if not btn or btn._cbtFlat then return btn end
    local text = ""
    pcall(function() text = btn:GetText() or "" end)
    pcall(function() btn:SetText("") end)

    local border = btn:CreateColorDrawable(0.00, 0.00, 0.00, 0.90, "background")
    border:AddAnchor("TOPLEFT", btn, 0, 0)
    border:AddAnchor("BOTTOMRIGHT", btn, 0, 0)
    local fill = btn:CreateColorDrawable(0.12, 0.13, 0.15, 0.95, "background")
    fill:AddAnchor("TOPLEFT", btn, 1, 1)
    fill:AddAnchor("BOTTOMRIGHT", btn, -1, -1)

    flatSeq = flatSeq + 1
    local label = btn:CreateChildWidget("label", "cbtFlatBtn_" .. tostring(flatSeq), 0, true)
    label:SetExtent(60, 20)
    label:AddAnchor("LEFT", btn, 4, 0)
    label:AddAnchor("RIGHT", btn, -4, 0)
    label.style:SetAlign(ALIGN.CENTER)
    label.style:SetFontSize(13)
    label.style:SetColor(0.87, 0.69, 0.0, 1)
    label:SetText(text)
    if label.Clickable then label:Clickable(false) end

    btn.textLabel = label
    function btn:SetText(t)
        if self.textLabel then self.textLabel:SetText(t or "") end
    end
    btn._cbtFlat = true
    return btn
end

-- Тёмное поле ввода: притемняет родной фон и делает текст светлым.
function M.StyleEdit(edit)
    if not edit then return edit end
    pcall(function()
        if edit.bg then edit.bg:SetColor(0.22, 0.24, 0.28, 1) end
    end)
    pcall(function() edit.style:SetColor(0.92, 0.93, 0.96, 1) end)
    return edit
end

return M
