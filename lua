-- init
if not game:IsLoaded() then game.Loaded:Wait() end
if not syn or not protectgui then getgenv().protectgui = function() end end

-- ============ SERVICES ============
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera

local function robloxNotify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

robloxNotify("SPENT HUB", "Initializing Premium GUI...", 2)

-- ============ SETTINGS ============
local SilentAimSettings = {
    Enabled = false,
    TeamCheck = false,
    VisibleCheck = false,
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    FOVRadius = 130,
    FOVVisible = false,
    ShowSilentAimTarget = false,
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100,
    -- Kayen-style target filters
    TargetTeams = { Guards = true, Inmates = true, Criminals = true },
    TargetMode = "Manual",
    ESP_Enabled = false,
    ESP_Team = false,
    ESP_Highlight = true,
    ESP_Name = true,
    ESP_Health = true,
    ESP_Trace = false,
    ESP_MaxDistance = 1500,
    ESP_HighlightColor = Color3.fromRGB(255, 182, 193),
    ESP_NameColor = Color3.fromRGB(255, 255, 255),
    ESP_HPColor = Color3.fromRGB(80, 255, 100),
}
getgenv().SilentAimSettings = SilentAimSettings

-- ============ THEME ============
local Theme = {
    BG_PRIMARY = Color3.fromRGB(8, 8, 12),
    BG_SECONDARY = Color3.fromRGB(15, 15, 22),
    BG_TERTIARY = Color3.fromRGB(25, 25, 35),
    BG_HOVER = Color3.fromRGB(35, 35, 50),
    ACCENT_PRIMARY = Color3.fromRGB(255, 182, 193),
    ACCENT_SECONDARY = Color3.fromRGB(200, 140, 200),
    TEXT_PRIMARY = Color3.fromRGB(250, 250, 255),
    TEXT_SECONDARY = Color3.fromRGB(150, 150, 165),
    TEXT_TERTIARY = Color3.fromRGB(100, 100, 115),
    BORDER = Color3.fromRGB(60, 60, 75),
    SUCCESS = Color3.fromRGB(80, 255, 100),
}

local mouse_box = Drawing.new("Square")
mouse_box.Visible = true
mouse_box.ZIndex = 999
mouse_box.Color = Theme.ACCENT_PRIMARY
mouse_box.Thickness = 2
mouse_box.Size = Vector2.new(20, 20)
mouse_box.Filled = false

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = 130
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Theme.ACCENT_PRIMARY

local MainFileName = "UniversalSilentAim"
local FileToSave = ""
local Mouse = LocalPlayer:GetMouse()
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local GetMouseLocation = UserInputService.GetMouseLocation
local PredictionAmount = 0.165

-- ============ UTILITY FUNCTIONS ============
local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = { ArgCountRequired = 3 },
    FindPartOnRayWithWhitelist = { ArgCountRequired = 3 },
    FindPartOnRay = { ArgCountRequired = 2 },
    Raycast = { ArgCountRequired = 3 }
}

local lastRollTime = 0
local lastRollResult = false

function CalculateChance(Percentage)
    local now = tick()
    if now - lastRollTime < 0.15 then return lastRollResult end
    lastRollTime = now
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100
    lastRollResult = chance <= Percentage / 100
    return lastRollResult
end

do
    if not isfolder(MainFileName) then makefolder(MainFileName) end
    if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then
        makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
    end
end

local function GetFiles()
    local Files = listfiles(string.format("%s/%s", "UniversalSilentAim", tostring(game.PlaceId)))
    local out = {}
    for i = 1, #Files do
        local file = Files[i]
        if file:sub(-4) == '.lua' then
            local pos = file:find('.lua', 1, true)
            local start = pos
            while pos > 1 do
                pos = pos - 1
                local char = file:sub(pos, pos)
                if char == '/' or char == '\\' then
                    table.insert(out, file:sub(pos + 1, start - 1))
                    break
                end
            end
        end
    end
    return out
end

local function UpdateFile(FileName)
    pcall(function()
        writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
    end)
end

local function LoadFile(FileName)
    pcall(function()
        local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
        local ConfigData = HttpService:JSONDecode(readfile(File))
        for Index, Value in next, ConfigData do SilentAimSettings[Index] = Value end
    end)
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    if not (PlayerCharacter or LocalPlayerCharacter) then return end
    local PlayerRoot = FindFirstChild(PlayerCharacter, SilentAimSettings.TargetPart) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    if not PlayerRoot then return end
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    return ObscuringObjects == 0
end

local function getTeamColor(player)
    if player.Team and player.Team.TeamColor then
        return player.Team.TeamColor.Color
    end
    return Theme.ACCENT_PRIMARY
end

-- ============ KAYEN STYLE TARGET FILTERS ============
local function matchesTeam(Player)
    if not Player.Team then return true end
    local teamName = Player.Team.Name
    local map = SilentAimSettings.TargetTeams
    if not map then return true end
    if teamName == "Guards" and not map.Guards then return false end
    if teamName == "Inmates" and not map.Inmates then return false end
    if teamName == "Criminals" and not map.Criminals then return false end
    return true
end

local function matchesTargetMode(Player)
    local mode = SilentAimSettings.TargetMode or "Manual"
    if mode == "Manual" then
        return true
    end
    local char = Player.Character
    if not char then return false end
    if mode == "Hostile" then
        return char:GetAttribute("Hostile") == true
    elseif mode == "Trespassing" then
        return char:GetAttribute("Trespassing") == true
    end
    return true
end

-- ============ TARGET ACQUISITION ============
local function getClosestPlayer()
    if not SilentAimSettings.TargetPart then return end
    local Closest
    local DistanceToMouse
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if SilentAimSettings.TeamCheck and Player.Team == LocalPlayer.Team then continue end
        if not matchesTeam(Player) then continue end
        if not matchesTargetMode(Player) then continue end
        local Character = Player.Character
        if not Character then continue end
        if SilentAimSettings.VisibleCheck and not IsPlayerVisible(Player) then continue end
        local HumanoidRootPart = FindFirstChild(Character, "HumanoidRootPart")
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid.Health <= 0 then continue end
        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        if not OnScreen then continue end
        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or SilentAimSettings.FOVRadius or 2000) then
            Closest = Character[SilentAimSettings.TargetPart]
            DistanceToMouse = Distance
        end
    end
    return Closest
end

-- ============ ESP SYSTEM ============
local espCache = {}
local lastESPUpdate = 0

local function newESP(player)
    return {
        name = Drawing.new("Text"),
        hpBar = Drawing.new("Line"),
        trace = Drawing.new("Line"),
    }
end

local function clearESP(player)
    local d = espCache[player]
    if d then
        for _, obj in pairs(d) do
            pcall(function() obj:Remove() end)
        end
        espCache[player] = nil
    end
end

Players.PlayerRemoving:Connect(function(player) clearESP(player) end)

local function updateESP()
    local now = tick()
    if now - lastESPUpdate < 0.033 then return end
    lastESPUpdate = now

    local camPos = Camera.CFrame.Position

    for _, player in ipairs(GetPlayers(Players)) do
        if player == LocalPlayer then continue end

        local char = player.Character
        if not char then
            if espCache[player] then clearESP(player) end
            continue
        end

        if not SilentAimSettings.ESP_Enabled then
            if espCache[player] then clearESP(player) end
            continue
        end

        local hrp = FindFirstChild(char, "HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
            if espCache[player] then clearESP(player) end
            continue
        end

        local dist = (camPos - hrp.Position).Magnitude
        if dist > SilentAimSettings.ESP_MaxDistance then
            if espCache[player] then clearESP(player) end
            continue
        end

        if not espCache[player] then
            espCache[player] = newESP(player)
        end

        local d = espCache[player]
        local head = FindFirstChild(char, "Head") or hrp
        local screenHead, onScreen = WorldToViewportPoint(Camera, head.Position + Vector3.new(0, 1.5, 0))

        if not onScreen then continue end

        if SilentAimSettings.ESP_Name then
            d.name.Visible = true
            d.name.Text = player.DisplayName
            d.name.Position = Vector2.new(screenHead.X, screenHead.Y - 20)
            d.name.Color = SilentAimSettings.ESP_NameColor
        else
            d.name.Visible = false
        end

        if SilentAimSettings.ESP_Health then
            local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            local topY = screenHead.Y - 32
            d.hpBar.Visible = true
            d.hpBar.From = Vector2.new(screenHead.X - 28, topY)
            d.hpBar.To = Vector2.new(screenHead.X - 28 + 56 * pct, topY)
            d.hpBar.Color = SilentAimSettings.ESP_HPColor
            d.hpBar.Thickness = 3
        else
            d.hpBar.Visible = false
        end

        if SilentAimSettings.ESP_Trace then
            d.trace.Visible = true
            d.trace.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
            d.trace.To = Vector2.new(screenHead.X, screenHead.Y)
            d.trace.Color = SilentAimSettings.ESP_Team and getTeamColor(player) or Theme.ACCENT_PRIMARY
            d.trace.Thickness = 1
        else
            d.trace.Visible = false
        end

        if SilentAimSettings.ESP_Highlight then
            local hl = char:FindFirstChild("SpentHubHL")
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "SpentHubHL"
                hl.Adornee = char
                hl.FillTransparency = 1
                hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = char
            end
            hl.OutlineColor = SilentAimSettings.ESP_Team and getTeamColor(player) or SilentAimSettings.ESP_HighlightColor
        end
    end
end

-- ============ CREATE PREMIUM GUI ============
local gui = Instance.new("ScreenGui")
gui.Name = "SpentHubPremium"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local mainWindow = Instance.new("Frame", gui)
mainWindow.Name = "MainWindow"
mainWindow.Size = UDim2.new(0, 1000, 0, 700)
mainWindow.Position = UDim2.new(0.5, -500, 0.5, -350)
mainWindow.BackgroundColor3 = Theme.BG_PRIMARY
mainWindow.BackgroundTransparency = 0.15
mainWindow.BorderSizePixel = 0
mainWindow.Draggable = true
mainWindow.Active = true

local mainCorner = Instance.new("UICorner", mainWindow)
mainCorner.CornerRadius = UDim.new(0, 20)

local mainStroke = Instance.new("UIStroke", mainWindow)
mainStroke.Color = Theme.BORDER
mainStroke.Thickness = 1
mainStroke.Transparency = 0.5

local shadowBlur = Instance.new("TextLabel", mainWindow)
shadowBlur.Size = UDim2.new(1, 20, 1, 20)
shadowBlur.Position = UDim2.new(0, -10, 0, -10)
shadowBlur.BackgroundColor3 = Theme.ACCENT_PRIMARY
shadowBlur.BackgroundTransparency = 0.95
shadowBlur.BorderSizePixel = 0
shadowBlur.Text = ""
shadowBlur.ZIndex = -1

Instance.new("UICorner", shadowBlur).CornerRadius = UDim.new(0, 30)

local gradientBG = Instance.new("UIGradient", mainWindow)
gradientBG.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.BG_PRIMARY),
    ColorSequenceKeypoint.new(0.5, Theme.BG_SECONDARY),
    ColorSequenceKeypoint.new(1, Theme.BG_PRIMARY),
})
gradientBG.Rotation = 45

local titleBar = Instance.new("Frame", mainWindow)
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 70)
titleBar.BackgroundColor3 = Theme.BG_SECONDARY
titleBar.BackgroundTransparency = 0.3
titleBar.BorderSizePixel = 0

Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 20)

local titleGlow = Instance.new("TextLabel", titleBar)
titleGlow.Size = UDim2.new(1, 0, 1, 0)
titleGlow.BackgroundColor3 = Theme.ACCENT_PRIMARY
titleGlow.BackgroundTransparency = 0.95
titleGlow.BorderSizePixel = 0
titleGlow.Text = ""
titleGlow.ZIndex = 0

Instance.new("UICorner", titleGlow).CornerRadius = UDim.new(0, 20)

local titleText = Instance.new("TextLabel", titleBar)
titleText.Size = UDim2.new(0.6, 0, 1, 0)
titleText.Position = UDim2.new(0, 20, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "SPENT HUB"
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 28
titleText.TextColor3 = Theme.ACCENT_PRIMARY
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.ZIndex = 10

local subtitleText = Instance.new("TextLabel", titleBar)
subtitleText.Size = UDim2.new(0.6, 0, 0.4, 0)
subtitleText.Position = UDim2.new(0, 20, 0.5, 0)
subtitleText.BackgroundTransparency = 1
subtitleText.Text = "Premium Silent Aim Suite v15 | Kayen Filters"
subtitleText.Font = Enum.Font.Gotham
subtitleText.TextSize = 13
subtitleText.TextColor3 = Theme.TEXT_SECONDARY
subtitleText.TextXAlignment = Enum.TextXAlignment.Left
subtitleText.ZIndex = 10

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -60, 0.5, -20)
closeBtn.BackgroundColor3 = Theme.BG_TERTIARY
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 28
closeBtn.TextColor3 = Theme.TEXT_PRIMARY
closeBtn.ZIndex = 11

local closeCorner = Instance.new("UICorner", closeBtn)
closeCorner.CornerRadius = UDim.new(0, 10)

local closeGlow = Instance.new("UIStroke", closeBtn)
closeGlow.Color = Theme.ACCENT_PRIMARY
closeGlow.Thickness = 2
closeGlow.Transparency = 1

closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = Theme.BG_HOVER,
        Size = UDim2.new(0, 44, 0, 44),
        Position = UDim2.new(1, -62, 0.5, -22)
    }):Play()
    TweenService:Create(closeGlow, TweenInfo.new(0.2), {Transparency = 0.3}):Play()
end)

closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = Theme.BG_TERTIARY,
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(1, -60, 0.5, -20)
    }):Play()
    TweenService:Create(closeGlow, TweenInfo.new(0.2), {Transparency = 1}):Play()
end)

closeBtn.MouseButton1Click:Connect(function()
    TweenService:Create(mainWindow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, -500, 1.5, 0),
        BackgroundTransparency = 1
    }):Play()
    task.wait(0.3)
    mainWindow.Visible = false
end)

local separatorLine = Instance.new("Frame", titleBar)
separatorLine.Size = UDim2.new(0, 0, 0, 2)
separatorLine.Position = UDim2.new(0, 20, 1, -2)
separatorLine.BackgroundColor3 = Theme.ACCENT_PRIMARY
separatorLine.BorderSizePixel = 0
separatorLine.BackgroundTransparency = 0

TweenService:Create(separatorLine, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    Size = UDim2.new(0, 200, 0, 2)
}):Play()

local tabContainer = Instance.new("Frame", mainWindow)
tabContainer.Name = "TabContainer"
tabContainer.Size = UDim2.new(0, 200, 1, -70)
tabContainer.Position = UDim2.new(0, 0, 0, 70)
tabContainer.BackgroundColor3 = Theme.BG_SECONDARY
tabContainer.BackgroundTransparency = 0.2
tabContainer.BorderSizePixel = 0

local tabScroll = Instance.new("ScrollingFrame", tabContainer)
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.ScrollBarThickness = 3
tabScroll.ScrollBarImageColor3 = Theme.ACCENT_PRIMARY

local tabLayout = Instance.new("UIListLayout", tabScroll)
tabLayout.Padding = UDim.new(0, 5)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder

local tabPadding = Instance.new("UIPadding", tabScroll)
tabPadding.PaddingLeft = UDim.new(0, 10)
tabPadding.PaddingRight = UDim.new(0, 10)
tabPadding.PaddingTop = UDim.new(0, 10)

local contentArea = Instance.new("Frame", mainWindow)
contentArea.Name = "ContentArea"
contentArea.Size = UDim2.new(1, -200, 1, -70)
contentArea.Position = UDim2.new(0, 200, 0, 70)
contentArea.BackgroundColor3 = Theme.BG_PRIMARY
contentArea.BackgroundTransparency = 0.5
contentArea.BorderSizePixel = 0

local contentScroll = Instance.new("ScrollingFrame", contentArea)
contentScroll.Size = UDim2.new(1, 0, 1, 0)
contentScroll.BackgroundTransparency = 1
contentScroll.ScrollBarThickness = 4
contentScroll.ScrollBarImageColor3 = Theme.ACCENT_PRIMARY
contentScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
contentScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local contentLayout = Instance.new("UIListLayout", contentScroll)
contentLayout.Padding = UDim.new(0, 15)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder

local contentPadding = Instance.new("UIPadding", contentScroll)
contentPadding.PaddingLeft = UDim.new(0, 20)
contentPadding.PaddingRight = UDim.new(0, 20)
contentPadding.PaddingTop = UDim.new(0, 20)
contentPadding.PaddingBottom = UDim.new(0, 20)

-- ============ CONTROL CREATION HELPERS ============
local currentTab = nil
local tabs = {}

local function createTab(name, displayName, icon)
    local tabBtn = Instance.new("TextButton", tabScroll)
    tabBtn.Name = name
    tabBtn.Size = UDim2.new(1, 0, 0, 50)
    tabBtn.BackgroundColor3 = Theme.BG_TERTIARY
    tabBtn.BorderSizePixel = 0
    tabBtn.Text = icon .. " " .. displayName
    tabBtn.Font = Enum.Font.GothamMedium
    tabBtn.TextSize = 13
    tabBtn.TextColor3 = Theme.TEXT_SECONDARY
    tabBtn.AutoButtonColor = false

    local tabCorner = Instance.new("UICorner", tabBtn)
    tabCorner.CornerRadius = UDim.new(0, 10)

    local tabGlow = Instance.new("UIStroke", tabBtn)
    tabGlow.Color = Theme.ACCENT_PRIMARY
    tabGlow.Thickness = 2
    tabGlow.Transparency = 1

    local tab = {
        button = tabBtn,
        content = {},
        isActive = false
    }
    tabs[name] = tab

    tabBtn.MouseButton1Click:Connect(function()
        if currentTab then
            TweenService:Create(currentTab.button, TweenInfo.new(0.2), {
                BackgroundColor3 = Theme.BG_TERTIARY,
                TextColor3 = Theme.TEXT_SECONDARY
            }):Play()
            TweenService:Create(currentTab.button:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.2), {Transparency = 1}):Play()
            
            for _, element in ipairs(currentTab.content) do
                element.Visible = false
            end
            currentTab.isActive = false
        end

        currentTab = tab
        TweenService:Create(tabBtn, TweenInfo.new(0.2), {
            BackgroundColor3 = Theme.ACCENT_PRIMARY,
            TextColor3 = Theme.BG_PRIMARY
        }):Play()
        TweenService:Create(tabGlow, TweenInfo.new(0.2), {Transparency = 0.3}):Play()
        
        for i, element in ipairs(tab.content) do
            element.Visible = true
        end
        tab.isActive = true
    end)

    tabBtn.MouseEnter:Connect(function()
        if not tab.isActive then
            TweenService:Create(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.BG_HOVER}):Play()
        end
    end)

    tabBtn.MouseLeave:Connect(function()
        if not tab.isActive then
            TweenService:Create(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.BG_TERTIARY}):Play()
        end
    end)

    return tab
end

local function addGroupLabel(tab, text)
    local label = Instance.new("TextLabel", contentScroll)
    label.Size = UDim2.new(1, -40, 0, 25)
    label.BackgroundTransparency = 1
    label.Text = text
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = Theme.ACCENT_PRIMARY
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Visible = false

    table.insert(tab.content, label)
    return label
end

local function addToggle(tab, text, default, callback)
    local container = Instance.new("Frame", contentScroll)
    container.Size = UDim2.new(1, -40, 0, 45)
    container.BackgroundColor3 = Theme.BG_TERTIARY
    container.BackgroundTransparency = 0.1
    container.BorderSizePixel = 0
    container.Visible = false

    local containerCorner = Instance.new("UICorner", container)
    containerCorner.CornerRadius = UDim.new(0, 12)

    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Theme.BORDER
    containerStroke.Thickness = 1
    containerStroke.Transparency = 0.5

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Theme.TEXT_PRIMARY
    label.TextXAlignment = Enum.TextXAlignment.Left

    local toggleBtn = Instance.new("Frame", container)
    toggleBtn.Size = UDim2.new(0, 50, 0, 26)
    toggleBtn.Position = UDim2.new(1, -65, 0.5, -13)
    toggleBtn.BackgroundColor3 = default and Theme.ACCENT_PRIMARY or Color3.fromRGB(45, 45, 60)
    toggleBtn.BorderSizePixel = 0

    local toggleCorner = Instance.new("UICorner", toggleBtn)
    toggleCorner.CornerRadius = UDim.new(1, 0)

    local toggleGlow = Instance.new("UIStroke", toggleBtn)
    toggleGlow.Color = Theme.ACCENT_PRIMARY
    toggleGlow.Thickness = 2
    toggleGlow.Transparency = default and 0.4 or 1

    local toggleDot = Instance.new("Frame", toggleBtn)
    toggleDot.Size = UDim2.new(0, 22, 0, 22)
    toggleDot.Position = default and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
    toggleDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    toggleDot.BorderSizePixel = 0

    local toggleDotCorner = Instance.new("UICorner", toggleDot)
    toggleDotCorner.CornerRadius = UDim.new(1, 0)

    local state = default
    local toggleInput = Instance.new("TextButton", container)
    toggleInput.Size = UDim2.new(0, 50, 0, 26)
    toggleInput.Position = toggleBtn.Position
    toggleInput.BackgroundTransparency = 1
    toggleInput.Text = ""
    toggleInput.ZIndex = 10

    toggleInput.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(toggleDot, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = state and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
        }):Play()
        TweenService:Create(toggleBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = state and Theme.ACCENT_PRIMARY or Color3.fromRGB(45, 45, 60)
        }):Play()
        TweenService:Create(toggleGlow, TweenInfo.new(0.2), {Transparency = state and 0.4 or 1}):Play()
        callback(state)
    end)

    container.MouseEnter:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0.1}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0.5}):Play()
    end)

    table.insert(tab.content, container)
    return container
end

local function addSlider(tab, text, min, max, default, callback)
    local container = Instance.new("Frame", contentScroll)
    container.Size = UDim2.new(1, -40, 0, 70)
    container.BackgroundColor3 = Theme.BG_TERTIARY
    container.BackgroundTransparency = 0.1
    container.BorderSizePixel = 0
    container.Visible = false

    local containerCorner = Instance.new("UICorner", container)
    containerCorner.CornerRadius = UDim.new(0, 12)

    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Theme.BORDER
    containerStroke.Thickness = 1
    containerStroke.Transparency = 0.5

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(1, -30, 0, 20)
    label.Position = UDim2.new(0, 15, 0, 8)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. default
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = Theme.TEXT_PRIMARY
    label.TextXAlignment = Enum.TextXAlignment.Left

    local barBG = Instance.new("Frame", container)
    barBG.Size = UDim2.new(1, -30, 0, 8)
    barBG.Position = UDim2.new(0, 15, 0, 38)
    barBG.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    barBG.BorderSizePixel = 0

    local barCorner = Instance.new("UICorner", barBG)
    barCorner.CornerRadius = UDim.new(1, 0)

    local barFill = Instance.new("Frame", barBG)
    barFill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    barFill.BackgroundColor3 = Theme.ACCENT_PRIMARY
    barFill.BorderSizePixel = 0

    local barFillCorner = Instance.new("UICorner", barFill)
    barFillCorner.CornerRadius = UDim.new(1, 0)

    local barGlow = Instance.new("UIStroke", barFill)
    barGlow.Color = Theme.ACCENT_PRIMARY
    barGlow.Thickness = 1
    barGlow.Transparency = 0.5

    local dragging = false
    barBG.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((input.Position.X - barBG.AbsolutePosition.X) / barBG.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * rel)
            barFill.Size = UDim2.new(rel, 0, 1, 0)
            label.Text = text .. ": " .. val
            callback(val)
        end
    end)

    container.MouseEnter:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0.1}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0.5}):Play()
    end)

    table.insert(tab.content, container)
    return container
end

local function addDropdown(tab, text, options, default, callback)
    local container = Instance.new("Frame", contentScroll)
    container.Size = UDim2.new(1, -40, 0, 45)
    container.BackgroundColor3 = Theme.BG_TERTIARY
    container.BackgroundTransparency = 0.1
    container.BorderSizePixel = 0
    container.Visible = false

    local containerCorner = Instance.new("UICorner", container)
    containerCorner.CornerRadius = UDim.new(0, 12)

    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Theme.BORDER
    containerStroke.Thickness = 1
    containerStroke.Transparency = 0.5

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Theme.TEXT_PRIMARY
    label.TextXAlignment = Enum.TextXAlignment.Left

    local dropdownBtn = Instance.new("TextButton", container)
    dropdownBtn.Size = UDim2.new(0, 140, 0, 32)
    dropdownBtn.Position = UDim2.new(1, -155, 0.5, -16)
    dropdownBtn.BackgroundColor3 = Theme.BG_PRIMARY
    dropdownBtn.BorderSizePixel = 0
    dropdownBtn.Text = default
    dropdownBtn.Font = Enum.Font.GothamMedium
    dropdownBtn.TextSize = 12
    dropdownBtn.TextColor3 = Theme.ACCENT_PRIMARY
    dropdownBtn.AutoButtonColor = false

    local dropdownCorner = Instance.new("UICorner", dropdownBtn)
    dropdownCorner.CornerRadius = UDim.new(0, 8)

    local dropdownStroke = Instance.new("UIStroke", dropdownBtn)
    dropdownStroke.Color = Theme.ACCENT_PRIMARY
    dropdownStroke.Thickness = 1
    dropdownStroke.Transparency = 0.5

    local idx = 1
    for i, v in ipairs(options) do if v == default then idx = i break end end

    dropdownBtn.MouseButton1Click:Connect(function()
        idx = idx + 1
        if idx > #options then idx = 1 end
        dropdownBtn.Text = options[idx]
        TweenService:Create(dropdownBtn, TweenInfo.new(0.1), {TextTransparency = 0.5}):Play()
        task.wait(0.05)
        TweenService:Create(dropdownBtn, TweenInfo.new(0.1), {TextTransparency = 0}):Play()
        callback(options[idx])
    end)

    dropdownBtn.MouseEnter:Connect(function()
        TweenService:Create(dropdownBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.BG_HOVER}):Play()
        TweenService:Create(dropdownStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
    end)

    dropdownBtn.MouseLeave:Connect(function()
        TweenService:Create(dropdownBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.BG_PRIMARY}):Play()
        TweenService:Create(dropdownStroke, TweenInfo.new(0.15), {Transparency = 0.5}):Play()
    end)

    container.MouseEnter:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.15), {BackgroundTransparency = 0.1}):Play()
        TweenService:Create(containerStroke, TweenInfo.new(0.15), {Transparency = 0.5}):Play()
    end)

    table.insert(tab.content, container)
    return container
end

local function addButton(tab, text, callback, style)
    local container = Instance.new("TextButton", contentScroll)
    container.Size = UDim2.new(1, -40, 0, 45)
    container.BackgroundColor3 = style == "danger" and Color3.fromRGB(200, 80, 80) or Theme.ACCENT_PRIMARY
    container.BorderSizePixel = 0
    container.Text = text
    container.Font = Enum.Font.GothamBold
    container.TextSize = 13
    container.TextColor3 = Theme.BG_PRIMARY
    container.AutoButtonColor = false
    container.Visible = false

    local containerCorner = Instance.new("UICorner", container)
    containerCorner.CornerRadius = UDim.new(0, 12)

    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = container.BackgroundColor3
    containerStroke.Thickness = 2
    containerStroke.Transparency = 0.5

    local containerGlow = Instance.new("UIStroke", container)
    containerGlow.Color = container.BackgroundColor3
    containerGlow.Thickness = 6
    containerGlow.Transparency = 0.8

    container.MouseButton1Click:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, -40, 0, 42)
        }):Play()
        task.wait(0.1)
        TweenService:Create(container, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, -40, 0, 45)
        }):Play()
        callback()
    end)

    container.MouseEnter:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.2), {BackgroundTransparency = 0.1}):Play()
        TweenService:Create(containerGlow, TweenInfo.new(0.2), {Transparency = 0.4}):Play()
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.2), {BackgroundTransparency = 0}):Play()
        TweenService:Create(containerGlow, TweenInfo.new(0.2), {Transparency = 0.8}):Play()
    end)

    table.insert(tab.content, container)
    return container
end

-- ============ BUILD TABS ============
local MainTab = createTab("Main", "Silent Aim", "🎯")
addGroupLabel(MainTab, "CORE FEATURES")
addToggle(MainTab, "Master Enable", false, function(v)
    SilentAimSettings.Enabled = v
    mouse_box.Visible = v
end)

addDropdown(MainTab, "Target Part", {"Head", "HumanoidRootPart", "Random"}, "HumanoidRootPart", function(v)
    SilentAimSettings.TargetPart = v
end)

addDropdown(MainTab, "Aiming Method", {"Raycast", "FindPartOnRay", "FindPartOnRayWithWhitelist", "FindPartOnRayWithIgnoreList", "Mouse.Hit/Target"}, "Raycast", function(v)
    SilentAimSettings.SilentAimMethod = v
end)

addSlider(MainTab, "Hit Chance", 0, 100, 100, function(v)
    SilentAimSettings.HitChance = v
end)

addGroupLabel(MainTab, "FILTERS")
addToggle(MainTab, "Team Check", false, function(v)
    SilentAimSettings.TeamCheck = v
end)

addToggle(MainTab, "Visible Check", false, function(v)
    SilentAimSettings.VisibleCheck = v
end)

-- ============ KAYEN TARGET TEAM (REPLACES OLD TOGGLES) ============
addGroupLabel(MainTab, "TARGET TEAM")

addToggle(MainTab, "Guards", SilentAimSettings.TargetTeams.Guards, function(v)
    SilentAimSettings.TargetTeams.Guards = v
end)

addToggle(MainTab, "Inmates", SilentAimSettings.TargetTeams.Inmates, function(v)
    SilentAimSettings.TargetTeams.Inmates = v
end)

addToggle(MainTab, "Criminals", SilentAimSettings.TargetTeams.Criminals, function(v)
    SilentAimSettings.TargetTeams.Criminals = v
end)

-- ============ KAYEN TARGET MODE (REPLACES OLD AIM MODE) ============
addGroupLabel(MainTab, "TARGET MODE")

addDropdown(MainTab, "Mode", {"Manual", "Hostile", "Trespassing"}, SilentAimSettings.TargetMode, function(v)
    SilentAimSettings.TargetMode = v
end)

-- Advanced Tab
local AdvancedTab = createTab("Advanced", "Advanced", "⚙️")
addGroupLabel(AdvancedTab, "PREDICTION")
addToggle(AdvancedTab, "Enable Prediction", false, function(v)
    SilentAimSettings.MouseHitPrediction = v
end)

addSlider(AdvancedTab, "Prediction Amount", 50, 500, 165, function(v)
    SilentAimSettings.MouseHitPredictionAmount = v / 1000
    PredictionAmount = v / 1000
end)

-- ESP Tab
local ESPTab = createTab("ESP", "ESP", "👁️")
addGroupLabel(ESPTab, "ESP CORE")
addToggle(ESPTab, "Enable ESP", false, function(v)
    SilentAimSettings.ESP_Enabled = v
end)

addToggle(ESPTab, "Team Colors", false, function(v)
    SilentAimSettings.ESP_Team = v
end)

addGroupLabel(ESPTab, "ELEMENTS")
addToggle(ESPTab, "Highlight", true, function(v)
    SilentAimSettings.ESP_Highlight = v
end)

addToggle(ESPTab, "Names", true, function(v)
    SilentAimSettings.ESP_Name = v
end)

addToggle(ESPTab, "Health Bars", true, function(v)
    SilentAimSettings.ESP_Health = v
end)

addToggle(ESPTab, "Tracers", false, function(v)
    SilentAimSettings.ESP_Trace = v
end)

addSlider(ESPTab, "Max Distance", 100, 3000, 1500, function(v)
    SilentAimSettings.ESP_MaxDistance = v
end)

-- Visuals Tab
local VisualsTab = createTab("Visuals", "Visuals", "🎨")
addGroupLabel(VisualsTab, "FOV CIRCLE")
addToggle(VisualsTab, "Show FOV", false, function(v)
    SilentAimSettings.FOVVisible = v
    fov_circle.Visible = v
end)

addSlider(VisualsTab, "FOV Radius", 0, 400, 130, function(v)
    SilentAimSettings.FOVRadius = v
    fov_circle.Radius = v
end)

addToggle(VisualsTab, "Target Box", false, function(v)
    SilentAimSettings.ShowSilentAimTarget = v
end)

addGroupLabel(VisualsTab, "THEME COLORS")
addButton(VisualsTab, "💗 Pink", function()
    mouse_box.Color = Color3.fromRGB(255, 182, 193)
    fov_circle.Color = Color3.fromRGB(255, 182, 193)
end)

addButton(VisualsTab, "💙 Blue", function()
    mouse_box.Color = Color3.fromRGB(140, 180, 255)
    fov_circle.Color = Color3.fromRGB(140, 180, 255)
end)

addButton(VisualsTab, "💚 Green", function()
    mouse_box.Color = Color3.fromRGB(140, 255, 180)
    fov_circle.Color = Color3.fromRGB(140, 255, 180)
end)

addButton(VisualsTab, "💜 Purple", function()
    mouse_box.Color = Color3.fromRGB(200, 140, 255)
    fov_circle.Color = Color3.fromRGB(200, 140, 255)
end)

addButton(VisualsTab, "⚪ White", function()
    mouse_box.Color = Color3.fromRGB(255, 255, 255)
    fov_circle.Color = Color3.fromRGB(255, 255, 255)
end)

-- Settings Tab
local SettingsTab = createTab("Settings", "Settings", "⚡")
addGroupLabel(SettingsTab, "CONFIGURATION")

local fileInput = Instance.new("TextBox", contentScroll)
fileInput.Size = UDim2.new(1, -40, 0, 45)
fileInput.Position = UDim2.new(0, 0, 0, 0)
fileInput.BackgroundColor3 = Theme.BG_TERTIARY
fileInput.BackgroundTransparency = 0.1
fileInput.BorderSizePixel = 0
fileInput.PlaceholderText = "Config name..."
fileInput.PlaceholderColor3 = Theme.TEXT_TERTIARY
fileInput.TextColor3 = Theme.TEXT_PRIMARY
fileInput.Font = Enum.Font.Gotham
fileInput.TextSize = 13
fileInput.Visible = false

local fileInputCorner = Instance.new("UICorner", fileInput)
fileInputCorner.CornerRadius = UDim.new(0, 12)

local fileInputStroke = Instance.new("UIStroke", fileInput)
fileInputStroke.Color = Theme.BORDER
fileInputStroke.Thickness = 1
fileInputStroke.Transparency = 0.5

local filePadding = Instance.new("UIPadding", fileInput)
filePadding.PaddingLeft = UDim.new(0, 15)

fileInput.FocusLost:Connect(function()
    FileToSave = fileInput.Text
end)

table.insert(SettingsTab.content, fileInput)

addButton(SettingsTab, "💾 Save Config", function()
    if FileToSave and FileToSave ~= "" then
        UpdateFile(FileToSave)
        robloxNotify("SPENT HUB", "Saved: " .. FileToSave, 2)
    end
end)

addGroupLabel(SettingsTab, "LOAD CONFIGURATION")
local files = GetFiles()
if #files > 0 then
    for _, name in ipairs(files) do
        addButton(SettingsTab, "📥 " .. name, function()
            LoadFile(name)
            robloxNotify("SPENT HUB", "Loaded: " .. name, 2)
        end)
    end
end

-- Default to first tab
if tabs["Main"] then
    tabs["Main"].button:MouseButton1Click()
end

-- ============ MAIN GAME HOOKS ============
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)
    
    if SilentAimSettings.Enabled and self == workspace and not checkcaller() and chance then
        if Method == "FindPartOnRayWithIgnoreList" and SilentAimSettings.SilentAimMethod == Method then
            local A_Ray = Arguments[2]
            local HitPart = getClosestPlayer()
            if HitPart then
                Arguments[2] = Ray.new(A_Ray.Origin, getDirection(A_Ray.Origin, HitPart.Position))
                return oldNamecall(unpack(Arguments))
            end
        elseif Method == "FindPartOnRayWithWhitelist" and SilentAimSettings.SilentAimMethod == Method then
            local A_Ray = Arguments[2]
            local HitPart = getClosestPlayer()
            if HitPart then
                Arguments[2] = Ray.new(A_Ray.Origin, getDirection(A_Ray.Origin, HitPart.Position))
                return oldNamecall(unpack(Arguments))
            end
        elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and SilentAimSettings.SilentAimMethod:lower() == Method:lower() then
            local A_Ray = Arguments[2]
            local HitPart = getClosestPlayer()
            if HitPart then
                Arguments[2] = Ray.new(A_Ray.Origin, getDirection(A_Ray.Origin, HitPart.Position))
                return oldNamecall(unpack(Arguments))
            end
        elseif Method == "Raycast" and SilentAimSettings.SilentAimMethod == Method then
            local A_Origin = Arguments[2]
            local HitPart = getClosestPlayer()
            if HitPart then
                Arguments[3] = getDirection(A_Origin, HitPart.Position)
                return oldNamecall(unpack(Arguments))
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex = nil
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and SilentAimSettings.Enabled and SilentAimSettings.SilentAimMethod == "Mouse.Hit/Target" and getClosestPlayer() then
        local HitPart = getClosestPlayer()
        if Index == "Target" or Index == "target" then
            return HitPart
        elseif Index == "Hit" or Index == "hit" then
            return SilentAimSettings.MouseHitPrediction and (HitPart.CFrame + (HitPart.Velocity * PredictionAmount)) or HitPart.CFrame
        end
    end
    return oldIndex(self, Index)
end))

-- Main loop
coroutine.resume(coroutine.create(function()
    RenderStepped:Connect(function()
        local lockedTarget = getClosestPlayer()

        if SilentAimSettings.ShowSilentAimTarget and SilentAimSettings.Enabled then
            if lockedTarget then
                local Root = lockedTarget.Parent and lockedTarget.Parent.PrimaryPart or lockedTarget
                local RootToViewportPoint, IsOnScreen = WorldToViewportPoint(Camera, Root.Position)
                mouse_box.Visible = IsOnScreen
                mouse_box.Position = Vector2.new(RootToViewportPoint.X, RootToViewportPoint.Y)
            else
                mouse_box.Visible = false
            end
        end

        if SilentAimSettings.FOVVisible then
            fov_circle.Visible = true
            fov_circle.Position = getMousePosition()
            fov_circle.Color = lockedTarget and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
        else
            fov_circle.Visible = false
        end

        updateESP()
    end)
end))

-- Keybinds
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightAlt then
        SilentAimSettings.Enabled = not SilentAimSettings.Enabled
        robloxNotify("SPENT HUB", SilentAimSettings.Enabled and "Enabled ✓" or "Disabled ✗", 1)
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if mainWindow.Visible then
            TweenService:Create(mainWindow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, -500, 1.5, 0)
            }):Play()
            task.wait(0.3)
            mainWindow.Visible = false
        else
            mainWindow.Visible = true
            mainWindow.Position = UDim2.new(0.5, -500, 1.5, 0)
            TweenService:Create(mainWindow, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, -500, 0.5, -350)
            }):Play()
        end
    end
    if input.KeyCode == Enum.KeyCode.End then
        TweenService:Create(mainWindow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1
        }):Play()
        task.wait(0.3)
        gui:Destroy()
        pcall(function() fov_circle:Remove() end)
        pcall(function() mouse_box:Remove() end)
        for _, p in ipairs(GetPlayers(Players)) do clearESP(p) end
        robloxNotify("SPENT HUB", "Unloaded ✓", 1)
    end
end)

-- Fade-in animation
mainWindow.Position = UDim2.new(0.5, -500, 1.5, 0)
mainWindow.BackgroundTransparency = 1
TweenService:Create(mainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, -500, 0.5, -350),
    BackgroundTransparency = 0.15
}):Play()

robloxNotify("SPENT HUB v15", "Premium GUI Loaded ✓ | Kayen Filters", 2)
task.delay(0.5, function()
    robloxNotify("SPENT HUB", "RAlt: Toggle | RShift: GUI | END: Unload", 3)
end)
