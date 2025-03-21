local api = require("api")
local defaultSettings = require('CooldawnBuffTracker/default_settings')
local helpers = {}
local CANVAS
local PLAYER_CANVAS

local settingsOpened = false

-- Функция-помощник для форматирования ID баффа (без экспоненты)
function helpers.formatBuffId(buffId)
    if type(buffId) == "number" then
        return string.format("%.0f", buffId)
    else
        return tostring(buffId)
    end
end

-- Main functions for working with settings
function helpers.getSettings(cnv, playerCnv)
    if cnv ~= nil then CANVAS = cnv end
    if playerCnv ~= nil then PLAYER_CANVAS = playerCnv end
    
    local settings = api.GetSettings("CooldawnBuffTracker")
    
    -- Check and set default settings
    if not settings.playerpet then
        settings.playerpet = {}
        for k, v in pairs(defaultSettings.playerpet) do
            settings.playerpet[k] = v
        end
    end
    
    if not settings.player then
        settings.player = {}
        for k, v in pairs(defaultSettings.player) do
            settings.player[k] = v
        end
    end
    
    return settings
end

function helpers.updateSettings(newSettings)
    local settings = newSettings or api.GetSettings("CooldawnBuffTracker")
    local currentPosX, currentPosY, playerPosX, playerPosY
    
    -- Save current mount canvas position, if it exists
    if CANVAS then
        pcall(function()
            currentPosX, currentPosY = CANVAS:GetOffset()
            if currentPosX and currentPosY then
                -- Update position in settings only if position has changed
                if settings.playerpet.posX ~= currentPosX or settings.playerpet.posY ~= currentPosY then
                    settings.playerpet.posX = currentPosX
                    settings.playerpet.posY = currentPosY
                end
            end
        end)
    end
    
    -- Save current player canvas position, if it exists
    if PLAYER_CANVAS then
        pcall(function()
            playerPosX, playerPosY = PLAYER_CANVAS:GetOffset()
            if playerPosX and playerPosY then
                -- Update position in settings only if position has changed
                if settings.player.posX ~= playerPosX or settings.player.posY ~= playerPosY then
                    settings.player.posX = playerPosX
                    settings.player.posY = playerPosY
                end
            end
        end)
    end
    
    -- Ensure changes are saved in settings
    pcall(function()
        api.SaveSettings()
    end)
    
    -- Explicit UI update via handler
    if CANVAS and CANVAS.OnSettingsSaved then
        pcall(function()
            CANVAS.OnSettingsSaved()
            
            -- Restore position after update
            if currentPosX and currentPosY then
                CANVAS:RemoveAllAnchors()
                CANVAS:AddAnchor("TOPLEFT", "UIParent", currentPosX, currentPosY)
            end
        end)
    end
    
    -- Explicit UI update for player via handler
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        pcall(function()
            PLAYER_CANVAS.OnSettingsSaved()
            
            -- Restore position after update
            if playerPosX and playerPosY then
                PLAYER_CANVAS:RemoveAllAnchors()
                PLAYER_CANVAS:AddAnchor("TOPLEFT", "UIParent", playerPosX, playerPosY)
            end
        end)
    end
    
    settings = helpers.getSettings()
    return settings
end

function helpers.resetSettingsToDefault()
    local settings = api.GetSettings("CooldawnBuffTracker")
    
    -- Copy all default settings for playerpet
    settings.playerpet = {}
    for k, v in pairs(defaultSettings.playerpet) do
        settings.playerpet[k] = v
    end
    
    -- Copy all default settings for player
    settings.player = {}
    for k, v in pairs(defaultSettings.player) do
        settings.player[k] = v
    end
    
    -- Save settings
    pcall(function()
        api.SaveSettings()
    end)
    
    -- Full UI update for mount
    if CANVAS and CANVAS.OnSettingsSaved then
        pcall(function()
            CANVAS.OnSettingsSaved()
        end)
    end
    
    -- Full UI update for player
    if PLAYER_CANVAS and PLAYER_CANVAS.OnSettingsSaved then
        pcall(function()
            PLAYER_CANVAS.OnSettingsSaved()
        end)
    end
    
    return settings
end

-- Functions for working with UI
function helpers.createLabel(id, parent, text, offsetX, offsetY, fontSize)
    local label = api.Interface:CreateWidget('label', id, parent)
    label:AddAnchor("TOPLEFT", offsetX, offsetY)
    label:SetExtent(255, 20)
    label:SetText(text)
    
    -- Set color if available
    if FONT_COLOR and FONT_COLOR.TITLE then
        label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    else
        label.style:SetColor(0.87, 0.69, 0, 1) -- Gold color by default
    end
    
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 18)
    
    return label
end

function helpers.createEdit(id, parent, text, offsetX, offsetY)
    local field = W_CTRL.CreateEdit(id, parent)
    field:SetExtent(100, 20)
    field:AddAnchor("TOPLEFT", offsetX, offsetY)
    field:SetText(tostring(text))
    field.style:SetColor(0, 0, 0, 1)
    field.style:SetAlign(ALIGN.LEFT)
    field:SetInitVal(text)
    
    return field
end

function helpers.createButton(id, parent, text, x, y)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(95, 26)  -- Increased width for buttons
    button:SetText(text)
    api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
    
    return button
end

function helpers.createCheckbox(id, parent, text, offsetX, offsetY)
    local checkBox = nil
    checkBox = api._Library.UI.CreateCheckButton(id, parent, text)
    checkBox:AddAnchor("TOPLEFT", offsetX, offsetY)
    checkBox:SetButtonStyle("default")
    return checkBox
end

-- Create color pick button
function helpers.createColorPickButton(id, parent, color, offsetX, offsetY)
    local colorButton = nil
    
    -- Продолжаем использовать локальный модуль
    local createColorPickButtonsModule = require('CooldawnBuffTracker/util/color_picker')
    
    if createColorPickButtonsModule then
        colorButton = createColorPickButtonsModule(id, parent)
        colorButton:SetExtent(23, 15)
        colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
        colorButton.colorBG:SetColor(color.r or 1, color.g or 1, color.b or 1, 1)
        
        function colorButton:SelectedProcedure(r, g, b, a)
            self.colorBG:SetColor(r, g, b, a)
        end
        
        local F_ETC = require('CooldawnBuffTracker/util/etc')
            
        if F_ETC then
            function colorButton:OnClick()
                F_ETC.HidePallet()
                local palletWindow = F_ETC.ShowPallet(self)
                function palletWindow:OnHide() F_ETC.HidePallet() end
                palletWindow:SetHandler("OnHide", palletWindow.OnHide)
            end
            colorButton:SetHandler("OnClick", colorButton.OnClick)
        end
    else
        -- Create simple color button if module is not available
        colorButton = api.Interface:CreateWidget('button', id, parent)
        colorButton:AddAnchor("TOPLEFT", parent, offsetX, offsetY)
        colorButton:SetExtent(23, 15)
        
        local colorBG = colorButton:CreateColorDrawable(color.r or 1, color.g or 1, color.b or 1, 1, "background")
        colorBG:AddAnchor("TOPLEFT", colorButton, 1, 1)
        colorBG:AddAnchor("BOTTOMRIGHT", colorButton, -1, -1)
        colorButton.colorBG = colorBG
    end
    
    return colorButton
end

-- Functions for managing settings state
function helpers.setSettingsPageOpened(state) 
    settingsOpened = state 
end

function helpers.getSettingsPageOpened() 
    return settingsOpened 
end

return helpers 