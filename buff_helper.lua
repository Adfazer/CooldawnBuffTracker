-- buff_helper.lua
local BuffList = {}

-- This table contains some examples of buffs that can be tracked
-- Kept for backwards compatibility and as examples
BuffList.ALL_BUFFS = {
    {id = 3523, name = "Dash", cooldown = 30, timeOfAction = 3},
    {id = 1933, name = "Run!", cooldown = 30, timeOfAction = 10},
    {id = 6413, name = "Bear Defense", cooldown = 60, timeOfAction = 5},
    {id = 6747, name = "Heavenly Wings", cooldown = 60, timeOfAction = 0.1},
    {id = 21817, name = "move speed", cooldown = 35, timeOfAction = 3},
    {id = 2405, name = "Stealth Move", cooldown = 180, timeOfAction = 30},
    {id = 7556, name = "Inspiration Cloak", cooldown = 20, timeOfAction = 3},
    {id = 2611, name = "Deflect and Retaliate", cooldown = 12, timeOfAction = 0.1},
    {id = 2786, name = "Unassailable", cooldown = 20, timeOfAction = 2},
    {id = 559, name = "Quick Recovery", cooldown = 12, timeOfAction = 0.1},
    {id = 3779, name = "Mitigation", cooldown = 20, timeOfAction = 3},
    {id = 3780, name = "Mitigation", cooldown = 20, timeOfAction = 3},
}

-- Some common buff icons - also kept for backwards compatibility and as examples
BuffList.ddsData = {
    [3523] = "icon_skill_wild03.dds",
    [1933] = "icon_skill_snowlion05.dds",
    [6413] = "icon_skill_horseback06.dds",
    [6747] = "icon_skill_horseback13.dds",
    [21817] = "icon_skill_buff70.dds",
    [2405] = "icon_skill_tare01.dds",
    [7556] = "icon_skill_buff70.dds",
    [2611] = "icon_skill_fight23.dds",
    [2786] = "icon_skill_streak16.dds",
    [559] = "icon_skill_love04.dds",
    [3779] = "icon_skill_illusion23.dds",
    [3780] = "icon_skill_illusion23.dds",
}

-- This function returns the buff info given a buff ID
-- It will try to find the buff in predefined list or return a generic data object
function BuffList.GetBuffInfo(buffId)
    for _, buffInfo in ipairs(BuffList.ALL_BUFFS) do
        if buffInfo.id == buffId then
            return buffInfo
        end
    end
    
    -- If buff is not in predefined list, return a generic object
    return {
        id = buffId, 
        name = "Бафф #" .. buffId, 
        cooldown = 30, 
        timeOfAction = 5
    }
end

-- This function returns the buff name given a buff ID
function BuffList.GetBuffName(buffId)
    local buffInfo = BuffList.GetBuffInfo(buffId)
    
    -- Try to get actual buff name from game API if possible
    local buffName = nil
    pcall(function()
        local api = require("api")
        if api and api.Ability and api.Ability.GetBuffTooltip then
            local tooltip = api.Ability.GetBuffTooltip(buffId)
            if tooltip and tooltip.name then
                buffName = tooltip.name
            end
        end
    end)
    
    return buffName or buffInfo.name or "Бафф #" .. buffId
end

function BuffList.GetBuffCooldown(buffId)
    local buffInfo = BuffList.GetBuffInfo(buffId)
    return buffInfo and buffInfo.cooldown or 30
end

function BuffList.GetBuffTimeOfAction(buffId)
    local buffInfo = BuffList.GetBuffInfo(buffId)
    return buffInfo and buffInfo.timeOfAction or 5
end

-- Function to get the icon path for a given buff ID
function BuffList.GetBuffIcon(buffId)
    -- Check predefined icons first
    local iconPath = BuffList.ddsData[buffId]
    
    -- If no predefined icon, try to get icon from game API
    if not iconPath then
        pcall(function()
            local api = require("api")
            if api and api.Ability and api.Ability.GetBuffTooltip then
                local tooltip = api.Ability.GetBuffTooltip(buffId)
                if tooltip and tooltip.path then
                    iconPath = tooltip.path
                end
            end
        end)
    end
    
    -- Return icon path or default
    return iconPath and ("game/ui/icon/" .. iconPath) or "game/ui/icon/icon_skill_buff274.dds"
end

-- Function to check if a buff ID is valid and exists in the game
function BuffList.IsValidBuff(buffId)
    -- Check if buff is in predefined list
    for _, buffInfo in ipairs(BuffList.ALL_BUFFS) do
        if buffInfo.id == buffId then
            return true
        end
    end
    
    -- Check if buff has a predefined icon
    if BuffList.ddsData[buffId] then
        return true
    end
    
    -- Try to get buff information from game API
    local isValidFromAPI = false
    pcall(function()
        local api = require("api")
        if api and api.Ability and api.Ability.GetBuffTooltip then
            local tooltip = api.Ability.GetBuffTooltip(buffId)
            if tooltip and (tooltip.name or tooltip.path) then
                isValidFromAPI = true
            end
        end
    end)
    
    return isValidFromAPI
end

return BuffList