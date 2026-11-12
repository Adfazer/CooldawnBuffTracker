-- Общий кастомный шелл окон аддона (тёмная тема в стиле BetterBars):
-- пустое окно + ninepart-фон + своя шапка (заголовок, крестик, drag) + ESC.
local api = require("api")

local M = {}
local flatSeq = 0

-- Создаёт окно с шапкой. onClose - необязательный колбэк (по умолчанию скрыть).
function M.Create(id, title, w, h, onClose)
    local win = api.Interface:CreateEmptyWindow(id)
    if not win then return nil end
    win:SetExtent(w, h)
    win:SetUILayer("game")
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
    titleLabel:SetText(title or "")
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
