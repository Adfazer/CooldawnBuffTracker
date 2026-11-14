-- Иконки навыков из wiki (skill_icons/*.png) на слотах аддона (1.35.0).
--
-- Почему не F_SLOT.SetIconBackGround: он кормит нативный AddTexture слота, а тот
-- берёт только DDS/TGA из клиентских архивов. Loose PNG из папки аддона через
-- него не грузится — слот остаётся пустым (именно это видел автор в игре, и с
-- PNG 48x48, и с 64x64 DDS, потому что путь один и тот же — нативный загрузчик).
--
-- Рабочий путь в этом клиенте — ImageDrawable + SetTgaTexture: так BetterBars
-- грузит ../Addon/BetterBars/textures/<name>.png, так же рисуют свои PNG ESCMenu
-- и role_identifier. Слот при этом продолжает рисовать свой фон (или пустую
-- текстуру), а PNG кладётся сверху отдельным дравейблом.
--
-- Слой: "artwork". Порядок слоёв клиента — background < artwork < overlay:
--   * фон слота (F_SLOT -> CreateIconImageDrawable(..., "background"));
--   * наша картинка ("artwork");
--   * статус-тинт и рамки HUD-иконки + декор слота ("overlay", main.lua addBuffIcon).
-- Если положить PNG на "overlay", он закроет статус-тинт (зелёный/красный) и
-- рамки, поэтому основной слой — "artwork"; "overlay" остаётся запасным, если
-- создание дравейбла на artwork почему-то не удалось.
--
-- Дравейбл создаётся один раз на слот и кэшируется в slot._cbtSkillIcon: Paint
-- вызывается из релаяута, но при том же пути ничего не пересоздаётся и не
-- перезагружается (никакой работы на кадр).
local api = require("api")
local CbtLog = require("CooldawnBuffTracker/util/cbt_log")

local M = {}

local ADDON_DIR = "CooldawnBuffTracker"
local ICON_DIR = "skill_icons"
-- Белая текстура-затравка: дальше её содержимое заменяет SetTgaTexture.
local SEED = "Textures/Defaults/White.dds"
local LAYERS = { "artwork", "overlay" }

local function endsWith(lower, suffix)
    return #lower >= #suffix and string.sub(lower, -#suffix) == suffix
end

-- Имя файла иконки навыка без расширения или nil, если путь не из skill_icons.
-- Принимает и "skill_icons/x.png", и "../Addon/CooldawnBuffTracker/skill_icons/x.dds".
function M.SkillFile(path)
    if type(path) ~= "string" or path == "" then return nil end
    local lower = string.lower(path)
    if not (endsWith(lower, ".png") or endsWith(lower, ".dds")) then return nil end
    local marker = "/" .. ICON_DIR .. "/"
    local relative = ICON_DIR .. "/"
    if not string.find(lower, marker, 1, true)
        and string.sub(lower, 1, #relative) ~= relative then
        return nil
    end
    local name = string.match(path, "([^/\\]+)$")
    if not name or #name < 5 then return nil end
    -- .png и .dds — ровно четыре символа вместе с точкой; расширение уже проверено.
    local stem = string.sub(name, 1, #name - 4)
    if stem == "" then return nil end
    return stem
end

function M.IsSkillIcon(path)
    return M.SkillFile(path) ~= nil
end

-- Кандидаты пути к PNG, в порядке проверки.
--  1. Префикс берём из самого пути дампа (../Addon/CooldawnBuffTracker) — это
--     проверенная форма BetterBars, и она же записана в skill_dump.tbl.
--  2. Жёсткая форма ../Addon/<Addon>/skill_icons/... — на случай относительного
--     пути без префикса.
--  3. Абсолютные формы от api.baseDir (это корень Addon): с папкой аддона и без.
local function candidates(iconPath, stem)
    local out, seen = {}, {}
    local function add(p)
        if p ~= nil and p ~= "" and not seen[p] then
            seen[p] = true
            out[#out + 1] = p
        end
    end
    local dir = string.match(iconPath, "^(.*)/" .. ICON_DIR .. "/[^/]+$")
    if dir ~= nil and dir ~= "" then
        add(dir .. "/" .. ICON_DIR .. "/" .. stem .. ".png")
    end
    add("../Addon/" .. ADDON_DIR .. "/" .. ICON_DIR .. "/" .. stem .. ".png")
    local base = api.baseDir
    if type(base) == "string" and base ~= "" then
        add(base .. "/" .. ADDON_DIR .. "/" .. ICON_DIR .. "/" .. stem .. ".png")
        add(base .. "/" .. ICON_DIR .. "/" .. stem .. ".png")
    end
    return out
end

-- Дравейбл один на слот: создаём, якорим по краям с отступом 1 px, прячем.
local function attach(slot)
    local d = slot._cbtSkillIcon
    if d then return d end
    for i = 1, #LAYERS do
        local ok, made = pcall(function()
            return slot:CreateImageDrawable(SEED, LAYERS[i])
        end)
        if ok and made then
            d = made
            break
        end
    end
    if not d then return nil end
    -- Без этого движок может применить к PNG sRGB-конверсию и сдвинуть цвета
    -- (та же причина, по которой SetSRGB(false) стоит в BetterBars).
    pcall(function() d:SetSRGB(false) end)
    pcall(function()
        d:RemoveAllAnchors()
        d:AddAnchor("TOPLEFT", slot, 1, 1)
        d:AddAnchor("BOTTOMRIGHT", slot, -1, -1)
    end)
    pcall(function() d:SetVisible(false) end)
    slot._cbtSkillIcon = d
    return d
end

local warned = false

local function nativeBackground(slot, path)
    if F_SLOT and F_SLOT.SetIconBackGround then
        F_SLOT.SetIconBackGround(slot, path)
    end
end

-- Нарисовать иконку на слоте. Обычные игровые пути (баффы, дебаффы, пустой слот)
-- идут прежним нативным путём без изменений; skill_icons/*.png — через PNG-дравейбл.
-- true, если PNG нарисован; false — обычная иконка или PNG не загрузился.
function M.Paint(slot, path)
    if not slot then return false end
    local stem = M.SkillFile(path)

    if not stem then
        local d = slot._cbtSkillIcon
        if d and slot._cbtSkillIconShown then
            pcall(function() d:SetVisible(false) end)
            slot._cbtSkillIconShown = false
            slot._cbtSkillIconPath = nil
        end
        nativeBackground(slot, path)
        return false
    end

    -- Тот же путь уже нарисован: ни виджетов, ни SetTgaTexture.
    if slot._cbtSkillIconPath == path and slot._cbtSkillIconShown then
        return true
    end

    local d = attach(slot)
    local used
    if d then
        local list = candidates(path, stem)
        for i = 1, #list do
            local ok, res = pcall(function() return d:SetTgaTexture(list[i]) end)
            -- SetTgaTexture возвращает, загрузился ли файл (клиент проверяет так же).
            if ok and res ~= false and res ~= nil then
                used = list[i]
                break
            end
        end
    end

    if used then
        pcall(function() d:SetVisible(true) end)
        slot._cbtSkillIconPath = path
        slot._cbtSkillIconShown = true
        -- Пустая текстура слота не должна просвечивать сквозь PNG.
        nativeBackground(slot, nil)
        CbtLog.debug("skill icon paint: %s -> %s", tostring(stem), tostring(used))
        return true
    end

    -- PNG не загрузился. Последняя попытка — нативный путь с 64x64 DDS-копией
    -- (она лежит рядом с PNG в skill_icons/): это ровно поведение 1.34.0, и
    -- абсолютный путь от api.baseDir резолвится надёжнее относительного. Если и
    -- он пуст, слот останется пустым, зато в чат уйдёт одно предупреждение за
    -- сессию — иначе 323 иконки забьют лог.
    if slot._cbtSkillIconShown then
        pcall(function() d:SetVisible(false) end)
    end
    slot._cbtSkillIconPath = nil
    slot._cbtSkillIconShown = false
    local fallback = path
    local base = api.baseDir
    if type(base) == "string" and base ~= "" then
        fallback = base .. "/" .. ADDON_DIR .. "/" .. ICON_DIR .. "/" .. stem .. ".dds"
    end
    nativeBackground(slot, fallback)
    if not warned then
        warned = true
        CbtLog.warn("skill icon paint failed: %s", tostring(stem))
    end
    return false
end

return M
