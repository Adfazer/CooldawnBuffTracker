-- Центральный логгер чата: каждое сообщение начинается с цветного [CBT],
-- уровни красятся разными цветами. Только ASCII и цветовые коды |cAARRGGBB|r.
-- 1.30.0: текст переводится централизованно (locale.L), а аргументы
-- подставляются string.format — в шаблонах пишем "%s", значения передаём
-- отдельными аргументами.
local api = require("api")
local locale = require("CooldawnBuffTracker/locale")

local M = {}

-- Цветной тег: светло-голубой, как в TrackThatPlease.
local TAG = "|cFF87CEEB[CBT]|r"
local RESET = "|r"
local BODY = {
    info    = "|cFFFFFFFF", -- белый
    success = "|cFF7CFC00", -- зелёный
    warn    = "|cFFFFD700", -- жёлтый
    error   = "|cFFFF5555", -- красный
    debug   = "|cFF9E9E9E", -- серый
}
local VALUE = "|cFFDDA0DD" -- акцент для имён/id/чисел внутри текста

local debugOn = false

-- Debug-сообщения печатаются только при включённом Debug (settings.debugBuffId).
function M.setDebug(on)
    debugOn = on and true or false
end

function M.isDebug()
    return debugOn
end

-- Подсветка значения внутри сообщения: M.hl(id) / M.hl(name).
function M.hl(value)
    return VALUE .. tostring(value) .. RESET
end

-- Тело сообщения: цвет уровня + возврат к цвету уровня после каждого |r,
-- иначе вложенная подсветка значения гасила бы цвет остатка строки.
local function paint(color, message)
    local body = tostring(message or "")
    body = body:gsub("|r", "|r" .. color)
    return TAG .. " " .. color .. body .. RESET
end

local function emit(level, message)
    -- Mirror every chat line into the independent trace file. This mirror is
    -- deliberately NOT gated by the Debug flag or by CbtDebugLog.enabled: when
    -- UPDATE dies, combat-event lines still reach the file.
    pcall(function()
        local T = require("CooldawnBuffTracker/util/cbt_trace")
        if T then T.log(level, message) end
    end)
    -- Mirror every chat line into the file log. cbt_debuglog is intentionally
    -- independent of this module (no cycle) and fails silently if File is
    -- unavailable.
    pcall(function()
        local D = require("CooldawnBuffTracker/util/cbt_debuglog")
        if D then
            if level == "error" then D.error(message)
            elseif level == "warn" then D.warn(message)
            elseif level == "info" then D.info(message)
            elseif level == "debug" then D.info("debug: " .. tostring(message))
            end
        end
    end)
    local line = paint(BODY[level] or BODY.info, message)
    if level == "error" then
        if api and api.Log and api.Log.Err then
            api.Log:Err(line)
        end
        return
    end
    if api and api.Log and api.Log.Info then
        api.Log:Info(line)
    end
end

-- Перевод шаблона + подстановка аргументов: текст берётся из locale.L,
-- поэтому строка без перевода печатается как есть (английский оригинал).
local function format(message, ...)
    if type(message) ~= "string" then return tostring(message) end
    local args = { ... }
    if #args == 0 then return locale.L(message) end
    return locale.L(message, unpack(args))
end

function M.info(message, ...) emit("info", format(message, ...)) end
function M.success(message, ...) emit("success", format(message, ...)) end
function M.warn(message, ...) emit("warn", format(message, ...)) end
function M.error(message, ...) emit("error", format(message, ...)) end

function M.debug(message, ...)
    if not debugOn then return end
    emit("debug", format(message, ...))
end

return M
