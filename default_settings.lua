local defaultSettings = {
    playerpet = {
        posX = 330,
        posY = 30,
        iconSize = 40,
        iconSpacing = 5,
        lockPositioning = false,
        enabled = true,
        timerTextColor = {r = 1, g = 1, b = 1, a = 1},
        labelTextColor = {r = 1, g = 1, b = 1, a = 1},
        showLabel = false,
        labelFontSize = 14,
        labelX = 0,
        labelY = -30,
        showTimer = true,
        timerFontSize = 16,
        timerX = 0,
        timerY = 0,
        trackedBuffs = {}  -- Empty array - user specifies buffs themselves
    },
    player = {
        posX = 330,
        posY = 100,  -- Slightly lower than mount
        iconSize = 40,
        iconSpacing = 5,
        lockPositioning = false,
        enabled = true,
        timerTextColor = {r = 1, g = 1, b = 1, a = 1},
        labelTextColor = {r = 1, g = 1, b = 1, a = 1},
        showLabel = false,
        labelFontSize = 14,
        labelX = 0,
        labelY = -30,
        showTimer = true,
        timerFontSize = 16,
        timerX = 0,
        timerY = 0,
        trackedBuffs = {}  -- Empty array - user specifies buffs themselves
    },
    debugBuffId = false,  -- Debug option for buff ID logging - global setting
    customBuffs = {} -- Таблица для хранения пользовательских баффов
}

return defaultSettings 