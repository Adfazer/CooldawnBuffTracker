-- buffs_to_track.lua
-- This file contains a list of buff IDs that need to be constantly tracked
local api = require("api")

local BuffsToTrack = {}

-- Load tracked buffs from settings
local function loadTrackedBuffsFromSettings(unitType)
    local settings = api.GetSettings("CooldawnBuffTracker") or {}
    
    -- Check if settings for the specified unit type exist
    if not settings[unitType] then
        settings[unitType] = {
            trackedBuffs = {},
            enabled = true
        }
        api.SaveSettings()
    end
    
    -- Check special setting that disables buff tracking for the specified unit type
    if settings[unitType].enabled == false then
        return {} -- Return an empty list if tracking is disabled
    end
    
    -- If there are no buffs in the settings, create an empty list
    if not settings[unitType].trackedBuffs then
        settings[unitType].trackedBuffs = {}
        -- Save empty list to settings
        api.SaveSettings()
    end
    
    return settings[unitType].trackedBuffs
end

-- Save the list of tracked buffs to settings
function BuffsToTrack.SaveTrackedBuffs(buffIdList, unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    local settings = api.GetSettings("CooldawnBuffTracker") or {}
    
    -- Check if settings for the specified unit type exist
    if not settings[unitType] then
        settings[unitType] = {}
    end
    
    settings[unitType].trackedBuffs = buffIdList
    
    -- If the list is empty, explicitly disable buff tracking
    if #buffIdList == 0 then
        settings[unitType].enabled = false
    else
        settings[unitType].enabled = true
    end
    
    api.SaveSettings()
    
    -- Send event to update the canvas
    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
end

-- Add a new buff to the tracked list
function BuffsToTrack.AddTrackedBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    if not buffId then return false end
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    -- Check if this buff is already being tracked
    for _, id in ipairs(trackedBuffs) do
        if id == buffId then
            return false -- Buff is already being tracked
        end
    end
    
    -- Add buff to the list
    table.insert(trackedBuffs, buffId)
    
    -- Save the updated list
    BuffsToTrack.SaveTrackedBuffs(trackedBuffs, unitType)
    
    return true -- Buff successfully added
end

-- Remove a buff from the tracked list
function BuffsToTrack.RemoveTrackedBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    if not buffId then return false end
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    -- Search for the buff in the list
    for i, id in ipairs(trackedBuffs) do
        if id == buffId then
            -- Remove the buff
            table.remove(trackedBuffs, i)
            
            -- Save the updated list
            BuffsToTrack.SaveTrackedBuffs(trackedBuffs, unitType)
            
            -- Send general event to update the canvas
            api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
            
            return true
        end
    end
    
    return false  -- Buff not found
end

-- Completely clear the list of tracked buffs
function BuffsToTrack.ClearAllTrackedBuffs(unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    -- Save empty list
    BuffsToTrack.SaveTrackedBuffs({}, unitType)
    
    -- Send event to update the canvas
    api:Emit("MOUNT_BUFF_TRACKER_UPDATE_BUFFS")
    
    return true
end

-- Check if the specified buff should be tracked
function BuffsToTrack.ShouldTrackBuff(buffId, unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    local trackedBuffs = loadTrackedBuffsFromSettings(unitType)
    
    for _, id in ipairs(trackedBuffs) do
        if id == buffId then
            return true
        end
    end
    
    return false
end

-- Get a list of all tracked buff IDs
function BuffsToTrack.GetAllTrackedBuffIds(unitType)
    unitType = unitType or "playerpet" -- Use mount by default
    
    return loadTrackedBuffsFromSettings(unitType)
end

return BuffsToTrack