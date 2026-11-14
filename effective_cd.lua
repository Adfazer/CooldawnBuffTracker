-- Effective cooldowns (target only): user-defined flat / percent / reset
-- modifiers, aura stacks and the learned smart percentage.
--
-- Formula (author's rule): flat seconds first, then the ADDITIVE sum of the
-- percentages:
--     eff = max(0, base - sumFlat) * (1 - sumPercent / 100)
-- Each modifier's value is multiplied by the stack count read from the target's
-- aura (1 when the aura reports no stack). Conditional modifiers ('target')
-- count only while their aura is on the target; 'always' modifiers always count.
-- Reset modifiers carry no value: they zero the entry's timer when their buff
-- appears on the target (handled by main.lua).
local BuffList = require("CooldawnBuffTracker/buff_helper")
local helpers = require("CooldawnBuffTracker/helpers")
local locale = require("CooldawnBuffTracker/locale")

local M = {}

-- Кэш имён аур: id -> имя (false = имя не получено). BuffList.GetBuffName
-- дергает тултип, поэтому на каждый тик его вызывать нельзя.
local nameCache = {}

local function buffDisplayName(buffId)
    if buffId == nil then return nil end
    local key = tostring(buffId)
    local cached = nameCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local lookup = tonumber(key) or buffId
    local ok, value = pcall(BuffList.GetBuffName, lookup)
    if ok and type(value) == "string" and value ~= "" then
        nameCache[key] = value
        return value
    end
    nameCache[key] = false
    return nil
end

M.buffName = buffDisplayName

function M.resetNameCache()
    nameCache = {}
end

-- Запись с включёнными эффективными КД. Мана-навык фичу не поддерживает.
function M.isEnabled(entry)
    if type(entry) ~= "table" then return false end
    if entry.effectiveCDs ~= true then return false end
    return helpers.entryKind(entry) ~= "mana"
end

function M.mods(entry)
    if type(entry) ~= "table" then return {} end
    local list = entry.cdMods
    if type(list) ~= "table" then return {} end
    return list
end

-- Есть ли у записи reset-модификаторы (нужно, чтобы не сканировать ауры зря).
function M.hasReset(entry)
    for _, mod in ipairs(M.mods(entry)) do
        if mod.kind == "reset" then return true end
    end
    return false
end

-- Ищет ауру модификатора в снимке аур цели. Сначала точное совпадение по id,
-- затем точное совпадение по имени (без lower: кириллица не складывается).
function M.findAura(mod, snapshot)
    if type(snapshot) ~= "table" or type(mod) ~= "table" then return nil end
    local id = mod.id
    if id ~= nil and tostring(id) ~= "" then
        local aura = snapshot[tostring(id)]
        if aura then return aura end
    end
    local name = mod.name
    if type(name) == "string" and name ~= "" then
        for key, aura in pairs(snapshot) do
            local auraName = aura and aura.name
            if auraName == nil then
                auraName = buffDisplayName(key)
                if aura then aura.name = auraName or false end
            end
            if auraName == name then return aura end
        end
    end
    return nil
end

-- Стаки ауры: API может не отдавать stack -> 1.
function M.auraStacks(aura)
    if type(aura) ~= "table" then return 1 end
    local n = tonumber(aura.stack) or 1
    if n < 1 then n = 1 end
    return n
end

-- Подпись источника для списков и карточки: "Name (id)", "Name", "id".
function M.sourceLabel(mod, index)
    mod = mod or {}
    local id = mod.id
    if id ~= nil and tostring(id) == "" then id = nil end
    local name = mod.name
    if type(name) ~= "string" or name == "" then name = nil end
    if name and id and tostring(id) ~= name then
        return name .. " (" .. tostring(id) .. ")"
    end
    if name then return name end
    if id then return tostring(id) end
    return locale.L("Unconditional %s", tostring(index or 1))
end

local function applyFormula(base, flat, pct)
    local value = base - flat
    if value < 0 then value = 0 end
    local mult = 1 - (pct / 100)
    if mult < 0 then mult = 0 end
    value = value * mult
    if value < 0 then value = 0 end
    return value
end

-- Считает активные и потенциальные значения.
--   snapshot: { [idString] = { stack = n, name = "..." } } или nil (нет цели)
--   opts.learned / opts.smartPct — выученный smart-процент этой цели
-- Возвращает таблицу с итогами и списками источников.
function M.evaluate(entry, snapshot, opts)
    opts = opts or {}
    local base = tonumber(entry and entry.cooldown) or 0
    if base < 0 then base = 0 end

    local smartPct = tonumber(opts.smartPct)
    if smartPct == nil then smartPct = tonumber(entry and entry.smartPct) or 0 end
    if smartPct < 0 then smartPct = 0 end
    local learned = (opts.learned == true) and smartPct > 0
    local potentialLearned = learned
    if opts.potentialLearned ~= nil then
        potentialLearned = (opts.potentialLearned == true) and smartPct > 0
    end

    local flat, pct = 0, 0
    local potFlat, potPct = 0, 0
    local flatList, pctList = {}, {}
    local hasConditional = false

    for index, mod in ipairs(M.mods(entry)) do
        local kind = mod.kind
        if kind == "flat" or kind == "percent" then
            local value = tonumber(mod.value) or 0
            local always = (mod.condition == "always")
            if not always then hasConditional = true end

            local aura = nil
            if not always and snapshot ~= nil then
                aura = M.findAura(mod, snapshot)
            end
            local active = always or (aura ~= nil)
            local stacks = active and M.auraStacks(aura) or 1
            local scaled = value * stacks

            if kind == "flat" then
                potFlat = potFlat + scaled
                if active then
                    flat = flat + scaled
                    flatList[#flatList + 1] = {
                        label = M.sourceLabel(mod, index),
                        value = scaled,
                        stacks = stacks,
                    }
                end
            else
                potPct = potPct + scaled
                if active then
                    pct = pct + scaled
                    pctList[#pctList + 1] = {
                        label = M.sourceLabel(mod, index),
                        value = scaled,
                        stacks = stacks,
                    }
                end
            end
        end
    end

    if learned then
        pct = pct + smartPct
        pctList[#pctList + 1] = { label = locale.L("Smart"), value = smartPct, stacks = 1, smart = true }
    end
    if potentialLearned then
        potPct = potPct + smartPct
    end

    return {
        base = base,
        flat = flat,
        pct = pct,
        potFlat = potFlat,
        potPct = potPct,
        flatList = flatList,
        pctList = pctList,
        effective = applyFormula(base, flat, pct),
        potential = applyFormula(base, potFlat, potPct),
        hasTarget = (snapshot ~= nil),
        hasConditional = hasConditional,
        learned = learned,
        smartPct = smartPct,
    }
end

return M
