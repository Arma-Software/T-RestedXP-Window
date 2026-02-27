--[[
T-RestedXP - addon for tracking 100% rested XP in WoW 1.12
T-RestedXP - аддон для отслеживания 100% RESTED XP в WoW 1.12

Addon GitHub link: https://github.com/Arma-Software/T-RestedXP-Window.git


Compatibility:
- Designed for Turtle WoW server
--]]

-- SETTINGS / НАСТРОЙКИ

-- 0% rested XP message alert / Сообщение при 0% rested XP
local noRestedMsg = "=== NO RESTED XP / НЕТ ОТДЫХА ==="

-- 100% rested XP message alert / Сообщение при 100% rested XP
local fullRestedMsg = "=== 100% RESTED XP / 100% ОТДЫХА ==="

-- Announce channel / Канал анонса ("SELF", "EMOTE", "SAY", "PARTY", "RAID", "GUILD")
local chatChannel = "EMOTE"

-- Max 0% alerts in a row / Максимум оповещений о 0% подряд
local notifyCountZero = 3

-- Interval between 0% alerts (seconds) / Интервал между оповещениями о 0% (сек)
local notifyIntervalZero = 20

-- Show alert in center / Показывать оповещение по центру экрана
local showCenter = true

-- Time to show center message (seconds) / Время показа сообщения по центру (сек)
local centerMessageTime = 3

-- Play sound on alert / Воспроизводить звук при оповещении
local playSound = true

-- Sound for 0% rested XP / Звук для 0%
local soundNameZero = "RaidWarning"

-- Sound for 100% rested XP / Звук для 100%
local soundNameFull = "QUESTCOMPLETED"

-- Max player level / Максимальный уровень игрока
local maxLevel = 60

-- INTERNAL STATE / ВНУТРЕННЕЕ СОСТОЯНИЕ
local lastZeroRestedTime = 0
local zeroRestedCount = 0
local wasFullRested = false
local wasZeroRested = false
local zeroRestedTimerFrame = nil

-- Returns true if player is max level / Возвращает true, если игрок максимального уровня
local function IsPlayerMaxLevel()
    return UnitLevel("player") >= maxLevel
end

-- Returns rested XP percent (0-100), or nil if not available / Возвращает % rested XP (0-100), или nil если нет
local function GetRestedXPPercent()
    local exhaustion = GetXPExhaustion()
    local maxXP = UnitXPMax("player")
    
    -- If no max XP data - return nil / Если нет данных о максимальном XP - возвращаем nil
    if not maxXP or maxXP <= 0 then
        return nil
    end
    
    -- If no exhaustion (rested) - this means 0% / Если нет exhaustion (рестеда) - это означает 0%
    if not exhaustion or exhaustion <= 0 then
        return 0
    end
    
    local percent = (exhaustion / (maxXP * 1.5)) * 100
    return math.min(percent, 100)
end

-- Color for rested bar by percent / Цвет полоски в зависимости от процента
local function GetRestedBarColor(percent)
    -- No data -> default blue / Нет данных -> синий по умолчанию
    if not percent then
        return 0.2, 0.6, 1.0
    end

    -- 100% -> gold / 100% -> золотой
    if percent >= 99.9 then
        return 1.0, 0.84, 0.0 -- gold / золото
    end

    -- 0–50%: blue -> green / 0–50%: синий -> зелёный
    if percent <= 50 then
        local t = percent / 50
        local r = 1.0 + (0.0 - 1.0) * t   -- 1 -> 0
        local g = 0.0 + (1.0 - 0.0) * t   -- 0 -> 1
        local b = 0.0                     -- stays 0
        return r, g, b
    end

    -- 50–100%: green -> red / 50–100%: зелёный -> красный
    local t = (percent - 50) / 50
    local r = 0.0                         -- stays 0
    local g = 1.0 + (0.0 - 1.0) * t       -- 1 -> 0
    local b = 0.0 + (1.0 - 0.0) * t       -- 0 -> 1
    return r, g, b
end

-- SMALL WINDOW WITH CURRENT RESTED XP / ОКНО С ТЕКУЩИМ RESTED XP

local restedXPWindow = nil
local restedXPText = nil
local restedXPBar = nil   -- progress bar
local restedXPShimmer = nil -- shimmer overlay
local fullVisualActive = false
local fullPulseTime = 0
local zeroVisualActive = false
local zeroPulseTime = 0
local restedXPBarFrame = nil  -- container frame (border holder)

function CreateRestedXPWindow()
    if restedXPWindow then return end

    restedXPWindow = CreateFrame("Frame", "T_RestedXP_InfoFrame", UIParent)
    restedXPWindow:SetWidth(95)
    restedXPWindow:SetHeight(50)
    restedXPWindow:SetPoint("CENTER", UIParent, "CENTER", 0, -200)

-- Default position / Позиция по умолчанию
    restedXPWindow:SetPoint("CENTER", UIParent, "CENTER", 0, -200)

    -- Restore saved position if available / Восстанавливаем сохранённую позицию
    if T_RestedXP_DB and T_RestedXP_DB.windowPos then
        local pos = T_RestedXP_DB.windowPos
        restedXPWindow:ClearAllPoints()
        restedXPWindow:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end

    if restedXPWindow.SetBackdrop then
        restedXPWindow:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })

        restedXPWindow:SetBackdropColor(0, 0, 0, 1)
    end

    --makemoveable
    restedXPWindow:EnableMouse(true)
    restedXPWindow:SetMovable(true)
    restedXPWindow:RegisterForDrag("LeftButton")

    restedXPWindow:SetScript("OnDragStart", function()
        restedXPWindow:StartMoving()
    end)

    restedXPWindow:SetScript("OnDragStop", function()
        restedXPWindow:StopMovingOrSizing()

        -- Save position / Сохраняем позицию
        if not T_RestedXP_DB then T_RestedXP_DB = {} end
        local point, _, _, xOfs, yOfs = restedXPWindow:GetPoint()
        T_RestedXP_DB.windowPos = {
            point = point,
            x = xOfs,
            y = yOfs,
        }
    end)

    -- Title
    local title = restedXPWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", restedXPWindow, "TOP", 0, -10)
    title:SetText("")

    -- Text
    restedXPText = restedXPWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    restedXPText:SetPoint("TOP", restedXPWindow, "TOP", 0, -15)
    restedXPText:SetText("Rested: --.-%")

    -- Progress bar container (border + clipping)
    restedXPBarFrame = CreateFrame("Frame", "T_RestedXP_BarFrame", restedXPWindow)
    local barFrame = restedXPBarFrame
    barFrame:SetWidth(65)
    barFrame:SetHeight(12)
    barFrame:SetPoint("BOTTOM", restedXPWindow, "BOTTOM", 0, 12)

    -- This is the key: clip anything inside
    if barFrame.SetClipsChildren then
        barFrame:SetClipsChildren(true)
    end

    if barFrame.SetBackdrop then
        barFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        barFrame:SetBackdropColor(0, 0, 0, 0.7)
    end

    -- Actual status bar INSIDE the container with padding
    restedXPBar = CreateFrame("StatusBar", "T_RestedXP_StatusBar", barFrame)
    restedXPBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 2, -2)
    restedXPBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -2, 2)

    restedXPBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    restedXPBar:SetMinMaxValues(0, 100)
    restedXPBar:SetValue(0)
    restedXPBar:SetStatusBarColor(0.2, 0.6, 1.0)

    -- Shimmer overlay (for full rested) / Блик поверх полоски для 100%
    restedXPShimmer = restedXPBar:CreateTexture(nil, "OVERLAY")
    restedXPShimmer:SetAllPoints(restedXPBar)
    restedXPShimmer:SetTexture("Interface\\Buttons\\WHITE8x8")
    restedXPShimmer:SetBlendMode("ADD")
    restedXPShimmer:SetVertexColor(1, 1, 1, 0) -- start invisible
    restedXPShimmer:Hide()

end

local function SetFullRestedVisual(isFull)
    if not restedXPBar or not restedXPShimmer then
        return
    end

    if isFull then
        if fullVisualActive then return end

        fullVisualActive = true
        fullPulseTime = 0

        -- Ensure gold color on entering full state
        restedXPBar:SetStatusBarColor(1.0, 0.84, 0.0)
        restedXPBar:SetAlpha(1.0)

        restedXPShimmer:Show()
        restedXPShimmer:SetAlpha(0.0)

        -- NOTE: classic-style OnUpdate: only one argument (elapsed)
        restedXPBar:SetScript("OnUpdate", function(elapsed)
            fullPulseTime = fullPulseTime + (elapsed or 0)

            -- Bar alpha pulse (clearly visible)
            local barAlpha = 0.6 + 0.4 * math.sin(fullPulseTime * 2.0)
            restedXPBar:SetAlpha(barAlpha)

            -- Shimmer alpha pulse
            local shimmerAlpha = 0.3 + 0.3 * math.sin(fullPulseTime * 4.0)
            restedXPShimmer:SetAlpha(shimmerAlpha)
        end)

    else
        if not fullVisualActive then return end

        fullVisualActive = false
        fullPulseTime = 0

        restedXPBar:SetScript("OnUpdate", nil)
        restedXPBar:SetAlpha(1.0)

        restedXPShimmer:SetAlpha(0.0)
        restedXPShimmer:Hide()
    end
end

local function SetZeroRestedVisual(isZero)
    if not restedXPBarFrame or not restedXPBarFrame.SetBackdropBorderColor then
        return
    end

    if isZero then
        if zeroVisualActive then return end

        zeroVisualActive = true
        zeroPulseTime = 0

        -- Classic-style OnUpdate: one arg (elapsed)
        restedXPBarFrame:SetScript("OnUpdate", function(elapsed)
            zeroPulseTime = zeroPulseTime + (elapsed or 0)

            -- Pulse red intensity between 0.5 and 1.0
            local intensity = 0.75 + 0.25 * math.sin(zeroPulseTime * 6.0)
            restedXPBarFrame:SetBackdropBorderColor(intensity, 0, 0, 1)

            -- Small shake around original position
            if barFrameOrigPoint then
                local shakeAmount = 2  -- pixels
                local dx = math.sin(zeroPulseTime * 25.0) * shakeAmount
                local dy = math.cos(zeroPulseTime * 20.0) * (shakeAmount * 0.6)

                restedXPBarFrame:ClearAllPoints()
                restedXPBarFrame:SetPoint(
                    barFrameOrigPoint,
                    restedXPWindow,
                    barFrameOrigPoint,
                    barFrameOrigX + dx,
                    barFrameOrigY + dy
                )
            end
        end)

    else
        if not zeroVisualActive then return end

        zeroVisualActive = false
        zeroPulseTime = 0

        restedXPBarFrame:SetScript("OnUpdate", nil)

        -- Reset border color
        restedXPBarFrame:SetBackdropBorderColor(1, 1, 1, 1)

        -- Reset position exactly to original
        if barFrameOrigPoint then
            restedXPBarFrame:ClearAllPoints()
            restedXPBarFrame:SetPoint(
                barFrameOrigPoint,
                restedXPWindow,
                barFrameOrigPoint,
                barFrameOrigX,
                barFrameOrigY
            )
        end
    end
end

function UpdateRestedXPWindow()
    if not restedXPWindow then
        CreateRestedXPWindow()
    end

    local percent = GetRestedXPPercent()

    if percent == nil then
        restedXPText:SetText("Rested: n/a")
        SetFullRestedVisual(false)
        SetZeroRestedVisual(false)
        if restedXPBar then
            restedXPBar:SetValue(0)
            local r, g, b = GetRestedBarColor(nil)
            restedXPBar:SetStatusBarColor(r, g, b)
        end
        SetFullRestedVisual(false)
    else
        restedXPText:SetText(string.format("Rested: %.1f%%", percent))
        if restedXPBar then
            restedXPBar:SetValue(percent)
            local r, g, b = GetRestedBarColor(percent)
            restedXPBar:SetStatusBarColor(r, g, b)
        end

        if percent >= 99.9 then
            -- Full rested visuals
            SetFullRestedVisual(true)
            SetZeroRestedVisual(false)
        elseif percent <= 0.1 then
            -- 0% visuals
            SetFullRestedVisual(false)
            SetZeroRestedVisual(true)
        else
            -- Middle range, no special pulse/shake
            SetFullRestedVisual(false)
            SetZeroRestedVisual(false)
        end
    end
end

-- Protection from repeated frame creation / Защита от повторного создания фрейма
if T_RestedXP_MessageFrame then
    T_RestedXP_MessageFrame:Hide()
    T_RestedXP_MessageFrame = nil
end

-- Custom center message frame / Кастомный фрейм для сообщений по центру
local restedXPMessageFrame = CreateFrame("Frame", "T_RestedXP_MessageFrame", UIParent)
restedXPMessageFrame:SetWidth(800)
restedXPMessageFrame:SetHeight(120)
restedXPMessageFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
restedXPMessageFrame:Hide()

local restedXPFontString = restedXPMessageFrame:CreateFontString(nil, "OVERLAY")
local fontPath = "Interface\\AddOns\\T-RestedXP\\fonts\\ARIALN.ttf"
if not restedXPFontString:SetFont(fontPath, 96, "OUTLINE") then
    -- Fallback to default font / Фоллбэк на стандартный шрифт
    restedXPFontString:SetFont("Fonts\\FRIZQT__.TTF", 96, "OUTLINE")
end
restedXPFontString:SetPoint("CENTER", restedXPMessageFrame, "CENTER", 0, 0)
restedXPFontString:SetTextColor(1, 1, 0)

local function ShowRestedXPMessage(msg)
    -- Reset previous state / Сброс предыдущего состояния
    restedXPMessageFrame:SetScript("OnUpdate", nil)
    restedXPMessageFrame:Hide()
    
    -- Set new message and state / Установка нового сообщения и состояния
    restedXPFontString:SetText(msg)
    restedXPMessageFrame:SetAlpha(1)
    restedXPMessageFrame:Show()

    -- Save start time / Сохраняем время начала показа
    restedXPMessageFrame.startTime = GetTime()
    restedXPMessageFrame.showDuration = centerMessageTime
    restedXPMessageFrame.fadeDuration = 1

    restedXPMessageFrame:SetScript("OnUpdate", function(frame, elapsed)
        local currentTime = GetTime()
        local timeElapsed = currentTime - restedXPMessageFrame.startTime
        local totalDuration = restedXPMessageFrame.showDuration + restedXPMessageFrame.fadeDuration

        if timeElapsed >= totalDuration then
            -- Time is up, hide frame / Время вышло, скрываем фрейм
            restedXPMessageFrame:Hide()
            restedXPMessageFrame:SetScript("OnUpdate", nil)
            restedXPMessageFrame.startTime = nil
        elseif timeElapsed >= restedXPMessageFrame.showDuration then
            -- Fade phase / Фаза затухания
            local fadeProgress = (timeElapsed - restedXPMessageFrame.showDuration) / restedXPMessageFrame.fadeDuration
            restedXPMessageFrame:SetAlpha(1 - fadeProgress)
        end
    end)
end

-- Send alert to chat and/or center / Отправить оповещение в чат и/или по центру
local function SendRestedAlert(msg, soundName)
    --[[if chatChannel == "SELF" then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    elseif chatChannel then
        -- Check channel validity / Проверка на валидность канала
        local validChannels = {"EMOTE", "SAY", "PARTY", "RAID", "GUILD", "YELL"}
        local isValidChannel = false
        for _, channel in ipairs(validChannels) do
            if chatChannel == channel then
                isValidChannel = true
                break
            end
        end
        if isValidChannel then
            SendChatMessage(msg, chatChannel)
        else
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
    end
    
    if showCenter then
        ShowRestedXPMessage(msg)
    end
    if playSound and soundName then
        PlaySound(soundName)
    end--]]
end

-- Function to stop 0% rested timer / Функция для остановки таймера 0% рестеда
local function StopZeroRestedTimer()
    if zeroRestedTimerFrame then
        zeroRestedTimerFrame:SetScript("OnUpdate", nil)
        zeroRestedTimerFrame = nil
    end
end

-- Function to start 0% rested timer / Функция для запуска таймера 0% рестеда
local function StartZeroRestedTimer()
    -- First stop existing timer / Сначала останавливаем существующий таймер
    StopZeroRestedTimer()
    
    zeroRestedTimerFrame = CreateFrame("Frame")
    zeroRestedTimerFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        if zeroRestedCount < notifyCountZero and (now - lastZeroRestedTime) >= notifyIntervalZero then
            local percent = GetRestedXPPercent()
            if percent ~= nil and percent <= 0.1 then
                SendRestedAlert(noRestedMsg, soundNameZero)
                lastZeroRestedTime = now
                zeroRestedCount = zeroRestedCount + 1
            end
        end
        
        -- Stop timer if reached notification limit / Останавливаем таймер если достигли лимита оповещений
        if zeroRestedCount >= notifyCountZero then
            -- Use function instead of direct access / Используем функцию вместо прямого обращения
            StopZeroRestedTimer()
        end
    end)
end

-- Main event handler / Основная обработка событий
local function CheckRestedXP()
    if IsPlayerMaxLevel() then return end

    local percent = GetRestedXPPercent()
    local now = GetTime()

    -- Update small window / Обновляем маленькое окно
    UpdateRestedXPWindow()

    if percent == nil then
        wasFullRested = false
        wasZeroRested = false
        zeroRestedCount = 0
        StopZeroRestedTimer()
        return
    end

    -- 100% rested XP: only one alert on entering state
    if percent >= 99.9 then
        if not wasFullRested then
            SendRestedAlert(fullRestedMsg, soundNameFull)
            wasFullRested = true
        end
        wasZeroRested = false
        zeroRestedCount = 0
        StopZeroRestedTimer()
        return
    end

    -- 0% rested XP: start timer for repeated notifications / 0% rested XP: запускаем таймер для повторных оповещений
    if percent <= 0.1 then
        if not wasZeroRested then
            -- First notification immediately / Первое оповещение сразу
            SendRestedAlert(noRestedMsg, soundNameZero)
            lastZeroRestedTime = now
            zeroRestedCount = 1
            wasZeroRested = true
            
            -- Start timer for next notifications / Запускаем таймер для следующих оповещений
            StartZeroRestedTimer()
        end
        wasFullRested = false
        return
    end

    -- Reset state if in between
    wasFullRested = false
    wasZeroRested = false
    zeroRestedCount = 0
    StopZeroRestedTimer()
end

-- Event frame setup / Создание фрейма событий
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("UPDATE_EXHAUSTION")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function()
    CheckRestedXP()
end)

-- Slash command for manual check / Слэш-команда для ручной проверки
SLASH_TRESTEDXP1 = "/trestedxp-w"
SlashCmdList["TRESTEDXP"] = function()
    local percent = GetRestedXPPercent()
    local msg
    if percent and percent > 0 then
        msg = string.format("Rested XP: %.1f%% / Отдых: %.1f%%", percent, percent)
        DEFAULT_CHAT_FRAME:AddMessage(msg)
        if showCenter and UIErrorsFrame then
            UIErrorsFrame:AddMessage(msg, 1, 1, 0, 1, 3)
        end
    else
        msg = "NO RESTED XP / НЕТ ОТДЫХА"
        DEFAULT_CHAT_FRAME:AddMessage(msg)
        if showCenter and UIErrorsFrame then
            UIErrorsFrame:AddMessage(msg, 1, 0, 0, 1, 3)
        end
    end
end

-- Slash command for test 0% rested XP / Слэш-команда для теста 0% rested XP
SLASH_TRESTEDXPTESTZERO1 = "/trestedxp-test-0"
SlashCmdList["TRESTEDXPTESTZERO"] = function()
    local oldGetRestedXPPercent = GetRestedXPPercent
    GetRestedXPPercent = function() return 0 end
    CheckRestedXP()
    GetRestedXPPercent = oldGetRestedXPPercent
    DEFAULT_CHAT_FRAME:AddMessage("Test: forced 0% rested XP / Тест: принудительно 0% отдыха")
end

-- Slash command for test 100% rested XP / Слэш-команда для теста 100% rested XP
SLASH_TRESTEDXPTESTFULL1 = "/trestedxp-test-100"
SlashCmdList["TRESTEDXPTESTFULL"] = function()
    local oldGetRestedXPPercent = GetRestedXPPercent
    GetRestedXPPercent = function() return 100 end
    CheckRestedXP()
    GetRestedXPPercent = oldGetRestedXPPercent
    DEFAULT_CHAT_FRAME:AddMessage("Test: forced 100% rested XP / Тест: принудительно 100% отдыха")
end

SLASH_TRESTEDXPWINDOW1 = "/trestedxp-window"
SlashCmdList["TRESTEDXPWINDOW"] = function()
    if not restedXPWindow then
        CreateRestedXPWindow()
        UpdateRestedXPWindow()
        DEFAULT_CHAT_FRAME:AddMessage("T-RestedXP window created / Окно T-RestedXP создано")
        return
    end

    if restedXPWindow:IsShown() then
        restedXPWindow:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("T-RestedXP window hidden / Окно T-RestedXP скрыто")
    else
        restedXPWindow:Show()
        UpdateRestedXPWindow()
        DEFAULT_CHAT_FRAME:AddMessage("T-RestedXP window shown / Окно T-RestedXP показано")
    end
end

-- Cleanup on addon unload / Cleanup при выгрузке аддона
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:RegisterEvent("ADDON_LOADED")
cleanupFrame:RegisterEvent("PLAYER_LOGOUT")
cleanupFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "T-RestedXP" then
        -- Init SavedVariables / Инициализация SavedVariables
        T_RestedXP_DB = T_RestedXP_DB or {}

        -- Safety cleanup on reload / Очистка при перезагрузке
        StopZeroRestedTimer()
        if restedXPMessageFrame then
            restedXPMessageFrame:SetScript("OnUpdate", nil)
            restedXPMessageFrame:Hide()
        end
    elseif event == "PLAYER_LOGOUT" then
        StopZeroRestedTimer()
        if restedXPMessageFrame then
            restedXPMessageFrame:SetScript("OnUpdate", nil)
            restedXPMessageFrame:Hide()
        end
    end
end)
-- End of file / Конец файла
