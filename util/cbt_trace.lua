-- Независимый от UPDATE файловый след. Пишет каждую строку сразу, без
-- enabled-флага и без буфера, поэтому остаётся живым, даже если OnUpdate
-- перестал вызываться. Два пути: основной и аварийный.
local api = require("api")

local M = {}

local PATH = "CooldawnBuffTracker/cbt_trace.log"
local ALT_PATH = "CooldawnBuffTracker/cbt_trace_fallback.log"
local CAP = 1200
local lines = {}
local writeFailed = false

local function nowMs()
    local ok, ms = pcall(function() return api.Time:GetUiMsec() end)
    if ok and type(ms) == "number" then return ms end
    return 0
end

local function writeTo(path, text)
    local ok, res = pcall(function()
        return api.File:Write(path, { version = 1, count = #lines, dump = text })
    end)
    return ok and res ~= false
end

local function writeAll()
    if not (api.File and api.File.Write) then return false end
    local text = table.concat(lines, "\n") .. "\n"
    if writeTo(PATH, text) then
        writeFailed = false
        return true
    end
    if writeTo(ALT_PATH, text) then
        writeFailed = false
        return true
    end
    writeFailed = true
    return false
end

local function append(level, message)
    if #lines >= CAP then
        table.remove(lines, 1)
    end
    lines[#lines + 1] = string.format("%s [%s] %s", tostring(nowMs()), level, tostring(message))
    local ok = writeAll()
    if not ok and not writeFailed then
        pcall(function()
            api.Log:Info("|cFF87CEEB[CBT]|r |cFFFF5555trace write failed|r")
        end)
    end
end

function M.log(level, message)
    append(level or "info", message)
end

function M.info(message) append("info", message) end
function M.warn(message) append("warn", message) end
function M.error(message) append("error", message) end

function M.reset(tag)
    lines = {}
    append("info", "=== trace session " .. tostring(tag or "") .. " ===")
end

function M.flush()
    writeAll()
end

-- Последняя достигнутая стадия кадра. Если UPDATE зависает, в файле остаётся
-- именно та стадия, на которой он остановился. Не чаще 0.5 с на стадию.
local stageName, stageAt = nil, 0
function M.stage(name)
    local ms = nowMs()
    if stageName ~= name or (ms - stageAt) >= 500 then
        stageName, stageAt = name, ms
        append("stage", name)
    end
end

return M
