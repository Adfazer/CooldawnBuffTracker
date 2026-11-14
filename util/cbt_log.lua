-- Центральный логгер чата: каждое сообщение начинается с цветного [CBT],
-- уровни красятся разными цветами. Только ASCII и цветовые коды |cAARRGGBB|r.
local api = require("api")

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

function M.info(message) emit("info", message) end
function M.success(message) emit("success", message) end
function M.warn(message) emit("warn", message) end
function M.error(message) emit("error", message) end

function M.debug(message)
    if not debugOn then return end
    emit("debug", message)
end

return M
