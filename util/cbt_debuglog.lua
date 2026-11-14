-- File-based runtime diagnostics (Debug ON or errors).
-- api.File:Write only accepts a Lua table with a `dump` string; the file lives
-- flat inside the addon folder so it can be copied to the SMB share.
local api = require("api")

local M = {}

local PATH = "CooldawnBuffTracker/cbt_debug.log"
local CAP = 800
local lines = {}
local enabled = false
local nextHeartbeat = 0

local function nowMs()
    local ok, ms = pcall(function() return api.Time:GetUiMsec() end)
    if ok and type(ms) == "number" then return ms end
    return 0
end

local function writeAll()
    if not (api.File and api.File.Write) then return end
    local text = table.concat(lines, "\n")
    pcall(function()
        api.File:Write(PATH, { version = 1, count = #lines, dump = text .. "\n" })
    end)
end

local function append(level, message)
    if #lines >= CAP then
        table.remove(lines, 1)
    end
    lines[#lines + 1] = string.format("%s [%s] %s", tostring(nowMs()), level, tostring(message))
    writeAll()
end

function M.setEnabled(on)
    enabled = on and true or false
    if enabled then
        append("info", "debug file enabled")
    end
end

function M.info(message) if enabled then append("info", message) end end
function M.warn(message) append("warn", message) end
function M.error(message) append("error", message) end

function M.flush()
    writeAll()
end

function M.reset()
    lines = {}
    append("info", "=== session start ===")
end

-- Call from OnUpdate; only logs while Debug is ON, at most every 2 s.
function M.heartbeat(extra)
    if not enabled then return end
    local ms = nowMs()
    if ms < nextHeartbeat then return end
    nextHeartbeat = ms + 2000
    append("alive", extra or "UPDATE")
end

return M
