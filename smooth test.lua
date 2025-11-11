local ImGui = require('ImGui')
local vKeys = require('vKeys')
local inicfg = require('inicfg')

-- THEME
function theme()
    local style = ImGui.GetStyle()

    style.WindowPadding = ImGui.ImVec2(8.0, 8.0)
    style.FramePadding = ImGui.ImVec2(4.0, 3.0)
    style.ItemSpacing  = ImGui.ImVec2(8.0, 4.0)
    style.ScrollbarSize = 12.0
    style.GrabMinSize = 8.0

    -- Проверка на наличие свойства перед установкой
    if style.WindowBorderSize ~= nil then
        style.WindowBorderSize = 0.0
    end
end



-- CONFIG
CFG = {
    Default = {
        WindowProc = ImGui.ImBool(false)
    },
    CheckBoxes = {
        Enable = ImGui.ImBool(false),
        AimByCrosshair = ImGui.ImBool(false),
        DisableOnStun = ImGui.ImBool(false),
        DrawFOV = ImGui.ImBool(false),
        DisableInCrosshair = ImGui.ImBool(false),
        AimHead = ImGui.ImBool(false),
        AimNeck = ImGui.ImBool(false),
        AimChest = ImGui.ImBool(true), -- Default to chest
        AimStomach = ImGui.ImBool(false),
        AimPelvis = ImGui.ImBool(false),
        AimLeftLeg = ImGui.ImBool(false),
        AimRightLeg = ImGui.ImBool(false),
        IgnoreBuildings = ImGui.ImBool(false),
        IgnoreDistance = ImGui.ImBool(false),
        LimitDistance37 = ImGui.ImBool(true),
        IgnoreSameColor = ImGui.ImBool(false),
        IgnoreDrivers = ImGui.ImBool(false)
    },
    Sliders = {
        Smooth = ImGui.ImFloat(3.0),
        FieldOfVisible = ImGui.ImFloat(10.0),
        MaxAngleX = ImGui.ImFloat(5.0), -- Max angle for X-axis aiming (degrees)
        AimSpeed = ImGui.ImFloat(1.0)   -- Aim speed multiplier
    },
    AimMode = ImGui.ImInt(0) -- 0: Legit, 1: Classic, 2: Rage
}

-- Path for config file (using Documents folder for better permissions)
local CONFIG_DIR = getFolderPath(0x05) .. "\\moonLoader\\wpgamesensez\\" -- 0x05 is My Documents
local CONFIG_FILE = CONFIG_DIR .. "config.ini"

-- Global variable to track health for stun detection
local lastHealth = nil
local healthCheckTime = 0
local STUN_HEALTH_DROP_THRESHOLD = 10 -- Health drop to consider as stun
local STUN_CHECK_INTERVAL = 0.1 -- Check interval in seconds

-- Bone offsets (approximate Z offsets relative to char center)
local BONE_OFFSETS = {
    Head = 0.8,     -- Head is ~0.8 units above center
    Neck = 0.6,     -- Neck is ~0.6 units above center
    Chest = 0.2,    -- Chest is ~0.2 units above center
    Stomach = -0.1, -- Stomach is ~0.1 units below center
    Pelvis = -0.4,  -- Pelvis is ~0.4 units below center
    LeftLeg = -0.8, -- Left leg is ~0.8 units below center
    RightLeg = -0.8 -- Right leg is ~0.8 units below center
}

-- Track mouse button states for half-slide detection
local isLeftMousePressedFirst = false
local lastLeftMousePressTime = 0

-- Normalize angle to [-π, π]
function fix(angle)
    if angle > math.pi then
        angle = angle - (math.pi * 2)
    elseif angle < -math.pi then
        angle = angle + (math.pi * 2)
    end
    return angle
end

-- Calculate angles to target (only X-axis for yaw)
function calculateAngles(myPos, enPos)
    local vector = {myPos[1] - enPos[1], myPos[2] - enPos[2], myPos[3] - enPos[3]}
    return {
        math.atan2(vector[2], vector[1]) + 0.04253, -- Yaw (X-axis)
        0 -- Pitch (Y-axis) is ignored
    }
end

-- Check if player is in stun (based on health drop)
function isPlayerInStun()
    if not lastHealth then
        lastHealth = getCharHealth(PLAYER_PED)
        healthCheckTime = os.clock()
        return false
    end
    local currentTime = os.clock()
    if currentTime - healthCheckTime >= STUN_CHECK_INTERVAL then
        local currentHealth = getCharHealth(PLAYER_PED)
        local healthDrop = lastHealth - currentHealth
        lastHealth = currentHealth
        healthCheckTime = currentTime
        if healthDrop >= STUN_HEALTH_DROP_THRESHOLD and not isCharInAnyCar(PLAYER_PED) then
            return true
        end
    end
    return false
end

-- Draw FOV circle using lines
function drawFOVCircle(fov)
    local screenWidth, screenHeight = getScreenResolution()
    local centerX, centerY = screenWidth / 2, screenHeight / 2
    local fovRadius = fov * (screenHeight / 90)
    local segments = 32
    local angleStep = 2 * math.pi / segments
    for i = 0, segments - 1 do
        local angle1 = i * angleStep
        local angle2 = (i + 1) * angleStep
        local x1 = centerX + fovRadius * math.cos(angle1)
        local y1 = centerY + fovRadius * math.sin(angle1)
        local x2 = centerX + fovRadius * math.cos(angle2)
        local y2 = centerY + fovRadius * math.sin(angle2)
        renderDrawLine(x1, y1, x2, y2, 2, 0xFFFF0000)
    end
end

-- Get bone position (select random bone from enabled ones or closest to crosshair)
function getTargetBonePosition(handle, aimByCrosshair)
    local selectedBones = {}
    if CFG.CheckBoxes.AimHead.v then table.insert(selectedBones, "Head") end
    if CFG.CheckBoxes.AimNeck.v then table.insert(selectedBones, "Neck") end
    if CFG.CheckBoxes.AimChest.v then table.insert(selectedBones, "Chest") end
    if CFG.CheckBoxes.AimStomach.v then table.insert(selectedBones, "Stomach") end
    if CFG.CheckBoxes.AimPelvis.v then table.insert(selectedBones, "Pelvis") end
    if CFG.CheckBoxes.AimLeftLeg.v then table.insert(selectedBones, "LeftLeg") end
    if CFG.CheckBoxes.AimRightLeg.v then table.insert(selectedBones, "RightLeg") end
    if #selectedBones == 0 then
        selectedBones = {"Chest"}
    end

    local enPos = {getCharCoordinates(handle)}
    local myPos = {getActiveCameraCoordinates()}
    local bestBone = selectedBones[math.random(#selectedBones)]
    if aimByCrosshair then
        local minAngleDistance = math.huge
        for _, bone in ipairs(selectedBones) do
            local bonePos = {enPos[1], enPos[2], enPos[3] + (BONE_OFFSETS[bone] or 0)}
            local angle = calculateAngles(myPos, bonePos)
            local view = {fix(representIntAsFloat(readMemory(0xB6F258, 4, false))), fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))}
            local angleDistance = math.abs(angle[1] - view[1]) * 57.2957795131
            if angleDistance < minAngleDistance then
                minAngleDistance = angleDistance
                bestBone = bone
            end
        end
    end
    enPos[3] = enPos[3] + (BONE_OFFSETS[bestBone] or 0)
    return enPos
end

-- Get nearest player based on distance or crosshair proximity
function GetNearestPed(fov, aimByCrosshair)
    local maxDistance = CFG.CheckBoxes.IgnoreDistance.v and math.huge or 35
    local minAngleDistance = math.huge
    local nearestPED = -1
    local myColor = sampGetPlayerColor(sampGetPlayerIdByCharHandle(PLAYER_PED))
    for i = 0, sampGetMaxPlayerId(true) do
        if sampIsPlayerConnected(i) then
            local find, handle = sampGetCharHandleBySampPlayerId(i)
            if find and isCharOnScreen(handle) and not isCharDead(handle) then
                local _, currentID = sampGetPlayerIdByCharHandle(PLAYER_PED)
                if i ~= currentID then
                    -- Ignore players with same color if enabled
                    if CFG.CheckBoxes.IgnoreSameColor.v and sampGetPlayerColor(i) == myColor then
                        goto continue
                    end
                    -- Ignore drivers if enabled
                    if CFG.CheckBoxes.IgnoreDrivers.v and isCharInAnyCar(handle) then
                        goto continue
                    end
                    local enPos = getTargetBonePosition(handle, aimByCrosshair)
                    local myPos = {getActiveCameraCoordinates()}
                    local myCharPos = {getCharCoordinates(PLAYER_PED)}
                    local distance = math.sqrt(math.pow(enPos[1] - myCharPos[1], 2) + math.pow(enPos[2] - myCharPos[2], 2) + math.pow(enPos[3] - myCharPos[3], 2))
                    -- Check distance limit of 37 if enabled
                    if CFG.CheckBoxes.LimitDistance37.v and distance > 37 then
                        goto continue
                    end
                    local isClear = CFG.CheckBoxes.IgnoreBuildings.v or isLineOfSightClear(myCharPos[1], myCharPos[2], myCharPos[3], enPos[1], enPos[2], enPos[3], true, true, false, true, false)
                    if aimByCrosshair then
                        local angle = calculateAngles(myPos, enPos)
                        local view = {fix(representIntAsFloat(readMemory(0xB6F258, 4, false))), fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))}
                        local angleDistance = math.abs(angle[1] - view[1]) * 57.2957795131
                        if angleDistance <= fov and angleDistance <= CFG.Sliders.MaxAngleX.v and isClear and angleDistance < minAngleDistance then
                            minAngleDistance = angleDistance
                            nearestPED = handle
                        end
                    else
                        local angle = calculateAngles(myPos, enPos)
                        local view = {fix(representIntAsFloat(readMemory(0xB6F258, 4, false))), fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))}
                        local angleDistance = math.abs(angle[1] - view[1]) * 57.2957795131
                        if angleDistance <= fov and angleDistance <= CFG.Sliders.MaxAngleX.v and isClear and (CFG.CheckBoxes.IgnoreDistance.v or distance < maxDistance) then
                            maxDistance = distance
                            nearestPED = handle
                        end
                    end
                end
                ::continue::
            end
        end
    end
    return nearestPED
end

-- Save config to INI with error handling
function saveConfig()
    if not doesDirectoryExist(CONFIG_DIR) then
        local success = createDirectory(CONFIG_DIR)
        if not success then
            print("Warning: Failed to create directory " .. CONFIG_DIR .. ". Config will not be saved.")
            return
        end
    end
    local config = {
        CheckBoxes = {
            Enable = CFG.CheckBoxes.Enable.v,
            AimByCrosshair = CFG.CheckBoxes.AimByCrosshair.v,
            DisableOnStun = CFG.CheckBoxes.DisableOnStun.v,
            DrawFOV = CFG.CheckBoxes.DrawFOV.v,
            DisableInCrosshair = CFG.CheckBoxes.DisableInCrosshair.v,
            AimHead = CFG.CheckBoxes.AimHead.v,
            AimNeck = CFG.CheckBoxes.AimNeck.v,
            AimChest = CFG.CheckBoxes.AimChest.v,
            AimStomach = CFG.CheckBoxes.AimStomach.v,
            AimPelvis = CFG.CheckBoxes.AimPelvis.v,
            AimLeftLeg = CFG.CheckBoxes.AimLeftLeg.v,
            AimRightLeg = CFG.CheckBoxes.AimRightLeg.v,
            IgnoreBuildings = CFG.CheckBoxes.IgnoreBuildings.v,
            IgnoreDistance = CFG.CheckBoxes.IgnoreDistance.v,
            LimitDistance37 = CFG.CheckBoxes.LimitDistance37.v,
            IgnoreSameColor = CFG.CheckBoxes.IgnoreSameColor.v,
            IgnoreDrivers = CFG.CheckBoxes.IgnoreDrivers.v
        },
        Sliders = {
            Smooth = CFG.Sliders.Smooth.v,
            FieldOfVisible = CFG.Sliders.FieldOfVisible.v,
            MaxAngleX = CFG.Sliders.MaxAngleX.v,
            AimSpeed = CFG.Sliders.AimSpeed.v
        },
        AimMode = CFG.AimMode.v
    }
    local success, err = pcall(function() inicfg.save(config, CONFIG_FILE) end)
    if not success then
        print("Error saving config: " .. err)
    end
end

-- Load config from INI
function loadConfig()
    if doesFileExist(CONFIG_FILE) then
        local config = inicfg.load(nil, CONFIG_FILE)
        if config then
            CFG.CheckBoxes.Enable.v = config.CheckBoxes.Enable or false
            CFG.CheckBoxes.AimByCrosshair.v = config.CheckBoxes.AimByCrosshair or false
            CFG.CheckBoxes.DisableOnStun.v = config.CheckBoxes.DisableOnStun or false
            CFG.CheckBoxes.DrawFOV.v = config.CheckBoxes.DrawFOV or false
            CFG.CheckBoxes.DisableInCrosshair.v = config.CheckBoxes.DisableInCrosshair or false
            CFG.CheckBoxes.AimHead.v = config.CheckBoxes.AimHead or false
            CFG.CheckBoxes.AimNeck.v = config.CheckBoxes.AimNeck or false
            CFG.CheckBoxes.AimChest.v = config.CheckBoxes.AimChest or true
            CFG.CheckBoxes.AimStomach.v = config.CheckBoxes.AimStomach or false
            CFG.CheckBoxes.AimPelvis.v = config.CheckBoxes.AimPelvis or false
            CFG.CheckBoxes.AimLeftLeg.v = config.CheckBoxes.AimLeftLeg or false
            CFG.CheckBoxes.AimRightLeg.v = config.CheckBoxes.AimRightLeg or false
            CFG.CheckBoxes.IgnoreBuildings.v = config.CheckBoxes.IgnoreBuildings or false
            CFG.CheckBoxes.IgnoreDistance.v = config.CheckBoxes.IgnoreDistance or false
            CFG.CheckBoxes.LimitDistance37.v = config.CheckBoxes.LimitDistance37 or true
            CFG.CheckBoxes.IgnoreSameColor.v = config.CheckBoxes.IgnoreSameColor or false
            CFG.CheckBoxes.IgnoreDrivers.v = config.CheckBoxes.IgnoreDrivers or false
            CFG.Sliders.Smooth.v = config.Sliders.Smooth or 3.0
            CFG.Sliders.FieldOfVisible.v = config.Sliders.FieldOfVisible or 10.0
            CFG.Sliders.MaxAngleX.v = config.Sliders.MaxAngleX or 5.0
            CFG.Sliders.AimSpeed.v = config.Sliders.AimSpeed or 1.0
            CFG.AimMode.v = config.AimMode or 0
        end
    end
end

-- Reset aim settings to default
function resetAimSettings()
    CFG.Sliders.MaxAngleX.v = 5.0
    CFG.Sliders.AimSpeed.v = 1.0
    saveConfig()
end

-- Aimbot logic with smoother camera movement
function Aimbot()
    -- Detect half-slide (LMB pressed before RMB)
    if isKeyDown(vKeys.VK_LBUTTON) and not isKeyDown(vKeys.VK_RBUTTON) then
        isLeftMousePressedFirst = true
        lastLeftMousePressTime = os.clock()
    elseif isKeyDown(vKeys.VK_RBUTTON) and isLeftMousePressedFirst then
        if os.clock() - lastLeftMousePressTime > 0.5 then
            isLeftMousePressedFirst = false
        end
    else
        isLeftMousePressedFirst = false
    end

    if CFG.CheckBoxes.Enable.v then
        -- Check for stun if DisableOnStun is enabled
        if CFG.CheckBoxes.DisableOnStun.v and isPlayerInStun() then
            return false
        end
        -- Draw FOV circle if enabled and right mouse button is held
        if CFG.CheckBoxes.DrawFOV.v and isKeyDown(vKeys.VK_RBUTTON) then
            drawFOVCircle(CFG.Sliders.FieldOfVisible.v)
        end
        -- Check aim conditions: disable aimbot when aiming with crosshair if DisableInCrosshair is enabled
        local shouldAim = true
        if CFG.CheckBoxes.DisableInCrosshair.v then
            if isKeyDown(vKeys.VK_RBUTTON) then
                shouldAim = false
            end
        end
        if shouldAim and isKeyDown(vKeys.VK_LBUTTON) then
            local handle = GetNearestPed(CFG.Sliders.FieldOfVisible.v, CFG.CheckBoxes.AimByCrosshair.v)
            if handle ~= -1 then
                local myPos = {getActiveCameraCoordinates()}
                local enPos = getTargetBonePosition(handle, CFG.CheckBoxes.AimByCrosshair.v)
                local angle = calculateAngles(myPos, enPos)
                local view = {fix(representIntAsFloat(readMemory(0xB6F258, 4, false))), fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))}
                local difference = angle[1] - view[1] -- Only X-axis (yaw)

                -- Smooth factor adjusted for smoother movement
                local smoothFactor = 0
                if CFG.AimMode.v == 2 then -- Rage mode
                    smoothFactor = 0.3 * CFG.Sliders.AimSpeed.v
                elseif CFG.AimMode.v == 1 then -- Classic mode
                    smoothFactor = 0.2 * CFG.Sliders.AimSpeed.v
                else -- Legit mode
                    smoothFactor = (0.07 / CFG.Sliders.Smooth.v) * CFG.Sliders.AimSpeed.v
                    smoothFactor = math.min(smoothFactor, 0.7)
                end

                -- Limit max step to avoid jerking
                local maxStep = 0.03 * CFG.Sliders.AimSpeed.v
                local deltaTime = 1 / 60
                local smooth = math.max(math.min(difference * smoothFactor, maxStep), -maxStep) * deltaTime * 60

                setCameraPositionUnfixed(view[2], view[1] + smooth)
            end
        end
    end
    return false
end

-- Main function
function main()
    if not initialized then
        if not isSampAvailable() then return false end
        -- Load config on script start
        loadConfig()
        lua_thread.create(Aimbot)
        initialized = true
    end
    if wasKeyPressed(vKeys.VK_X) then
        CFG.Default.WindowProc.v = not CFG.Default.WindowProc.v
        ImGui.Process = CFG.Default.WindowProc.v
        saveConfig()
    end
    return false
end

function ImGui.OnInitialize()
    theme() -- применяем тему
end


local themeApplied = false


-- ImGui interface with tabbed layout and fallback
function ImGui.OnDrawFrame()

    theme()


    if CFG.Default.WindowProc.v then
        ImGui.Begin('Aimbot Menu', CFG.Default.WindowProc)

        if ImGui.BeginTabBar and ImGui.BeginTabBar('AimbotTabs') then
            -- Tab 1: Basic Aimbot Settings
            if ImGui.BeginTabItem('Basic Settings') then
                if ImGui.Checkbox('Enable Aimbot', CFG.CheckBoxes.Enable) then saveConfig() end
                local aimModes = {'Legit', 'Classic', 'Rage'}
                if ImGui.Combo('Aim Mode', CFG.AimMode, aimModes, #aimModes) then saveConfig() end
                if ImGui.Checkbox('Aim by distance', CFG.CheckBoxes.AimByCrosshair) then saveConfig() end
                if ImGui.Checkbox('Disable on Stun', CFG.CheckBoxes.DisableOnStun) then saveConfig() end
                if ImGui.Checkbox('Draw FOV', CFG.CheckBoxes.DrawFOV) then saveConfig() end
                if ImGui.Checkbox('Disable in Crosshair', CFG.CheckBoxes.DisableInCrosshair) then saveConfig() end
                if ImGui.SliderFloat('Smooth', CFG.Sliders.Smooth, 1.0, 20.0, '%.1f') then saveConfig() end
                if ImGui.SliderFloat('FOV', CFG.Sliders.FieldOfVisible, 1.0, 50.0, '%.1f') then saveConfig() end
                ImGui.EndTabItem()
            end

            -- Tab 2: Bones
            if ImGui.BeginTabItem('Bones') then
                if ImGui.Checkbox('Head', CFG.CheckBoxes.AimHead) then saveConfig() end
                if ImGui.Checkbox('Neck', CFG.CheckBoxes.AimNeck) then saveConfig() end
                if ImGui.Checkbox('Chest', CFG.CheckBoxes.AimChest) then saveConfig() end
                if ImGui.Checkbox('Stomach', CFG.CheckBoxes.AimStomach) then saveConfig() end
                if ImGui.Checkbox('Pelvis', CFG.CheckBoxes.AimPelvis) then saveConfig() end
                if ImGui.Checkbox('Left Leg', CFG.CheckBoxes.AimLeftLeg) then saveConfig() end
                if ImGui.Checkbox('Right Leg', CFG.CheckBoxes.AimRightLeg) then saveConfig() end
                ImGui.EndTabItem()
            end

            -- Tab 3: Detailed Aim Settings
            if ImGui.BeginTabItem('Aim Settings') then
                if ImGui.SliderFloat('Max Angle X (deg)', CFG.Sliders.MaxAngleX, 1.0, 30.0, '%.1f') then saveConfig() end
                if ImGui.SliderFloat('Aim Speed', CFG.Sliders.AimSpeed, 0.1, 2.0, '%.1f') then saveConfig() end
                if ImGui.Button('Reset to Default') then resetAimSettings() end
                ImGui.EndTabItem()
            end

            -- Tab 4: Conditions (Ignores)
            if ImGui.BeginTabItem('Conditions') then
                if ImGui.Checkbox('Ignore Buildings', CFG.CheckBoxes.IgnoreBuildings) then saveConfig() end
                if ImGui.Checkbox('Ignore Distance', CFG.CheckBoxes.IgnoreDistance) then saveConfig() end
                if ImGui.Checkbox('Limit Distance to 37', CFG.CheckBoxes.LimitDistance37) then saveConfig() end
                if ImGui.Checkbox('Ignore Same Color', CFG.CheckBoxes.IgnoreSameColor) then saveConfig() end
                if ImGui.Checkbox('Ignore Drivers', CFG.CheckBoxes.IgnoreDrivers) then saveConfig() end
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        else
            -- Fallback layout without tabs
            ImGui.Text('Basic Settings')
            if ImGui.Checkbox('Enable Aimbot', CFG.CheckBoxes.Enable) then saveConfig() end
            local aimModes = {'Legit', 'Classic', 'Rage'}
            if ImGui.Combo('Aim Mode', CFG.AimMode, aimModes, #aimModes) then saveConfig() end
            if ImGui.Checkbox('Aim by distance', CFG.CheckBoxes.AimByCrosshair) then saveConfig() end
            if ImGui.Checkbox('Disable on Stun', CFG.CheckBoxes.DisableOnStun) then saveConfig() end
            if ImGui.Checkbox('Draw FOV', CFG.CheckBoxes.DrawFOV) then saveConfig() end
            if ImGui.Checkbox('Disable in Crosshair', CFG.CheckBoxes.DisableInCrosshair) then saveConfig() end
            if ImGui.SliderFloat('Smooth', CFG.Sliders.Smooth, 1.0, 20.0, '%.1f') then saveConfig() end
            if ImGui.SliderFloat('FOV', CFG.Sliders.FieldOfVisible, 1.0, 50.0, '%.1f') then saveConfig() end
            ImGui.Separator()
            ImGui.Text('Bones')
            if ImGui.Checkbox('Head', CFG.CheckBoxes.AimHead) then saveConfig() end
            if ImGui.Checkbox('Neck', CFG.CheckBoxes.AimNeck) then saveConfig() end
            if ImGui.Checkbox('Chest', CFG.CheckBoxes.AimChest) then saveConfig() end
            if ImGui.Checkbox('Stomach', CFG.CheckBoxes.AimStomach) then saveConfig() end
            if ImGui.Checkbox('Pelvis', CFG.CheckBoxes.AimPelvis) then saveConfig() end
            if ImGui.Checkbox('Left Leg', CFG.CheckBoxes.AimLeftLeg) then saveConfig() end
            if ImGui.Checkbox('Right Leg', CFG.CheckBoxes.AimRightLeg) then saveConfig() end
            ImGui.Separator()
            ImGui.Text('Aim Settings')
            if ImGui.SliderFloat('Max Angle X (deg)', CFG.Sliders.MaxAngleX, 1.0, 30.0, '%.1f') then saveConfig() end
            if ImGui.SliderFloat('Aim Speed', CFG.Sliders.AimSpeed, 0.1, 2.0, '%.1f') then saveConfig() end
            if ImGui.Button('Reset to Default') then resetAimSettings() end
            ImGui.Separator()
            ImGui.Text('Conditions')
            if ImGui.Checkbox('Ignore Buildings', CFG.CheckBoxes.IgnoreBuildings) then saveConfig() end
            if ImGui.Checkbox('Ignore Distance', CFG.CheckBoxes.IgnoreDistance) then saveConfig() end
            if ImGui.Checkbox('Limit Distance to 37', CFG.CheckBoxes.LimitDistance37) then saveConfig() end
            if ImGui.Checkbox('Ignore clist color', CFG.CheckBoxes.IgnoreSameColor) then saveConfig() end
            if ImGui.Checkbox('Ignore Drivers', CFG.CheckBoxes.IgnoreDrivers) then saveConfig() end
        end

        ImGui.End()
    end
end