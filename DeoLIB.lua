local CoreGui = game:GetService("CoreGui")
if CoreGui:FindFirstChild("DeoLibLoaded") then
    warn("[DeoLib] already running — skipping")
    return
end
local _guard = Instance.new("BoolValue")
_guard.Name   = "DeoLibLoaded"
_guard.Parent = CoreGui

local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local userId      = tostring(localPlayer.UserId)

local WHITELIST_URL = nil
local KEY_FORMULA   = nil
local KEY_FILE      = "deolib_key.txt"
local PORTAL_URL    = nil

local AddMultiplier, nativeClick, AddToggle, AddSlider, AddDivider

local LUCIDE_SOURCE = nil

local Lucide = nil
if LUCIDE_SOURCE then
    local ok, result = pcall(function()
        local fn = load(LUCIDE_SOURCE)
        return fn and fn()
    end)
    if ok then Lucide = result end
end

local function makeIcon(parent, iconName, size, color)
    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.BorderSizePixel        = 0
    img.ScaleType              = Enum.ScaleType.Fit
    img.ImageColor3            = color or Color3.new(1, 1, 1)
    img.Name                   = "Icon_" .. (iconName or "unknown")
    if Lucide then
        local ok, asset = pcall(Lucide.GetAsset, iconName or "circle-help", size or 48)
        if ok and asset then
            img.Image           = asset.Url
            img.ImageRectSize   = asset.ImageRectSize
            img.ImageRectOffset = asset.ImageRectOffset
        end
    end
    img.Parent = parent
    return img
end

local DeoLib = {}

function DeoLib:GetMyKey()
    if KEY_FORMULA then
        local k = KEY_FORMULA(userId)
        print("[DeoLib] Your key:", k)
        return k
    end
    print("[DeoLib] No formula key configured")
end

function DeoLib:SetKeySystem(cfg)
    if cfg.formula     then KEY_FORMULA     = cfg.formula     end
    if cfg.whitelist   then WHITELIST_URL   = cfg.whitelist   end
    if cfg.portal      then PORTAL_URL      = cfg.portal      end
    if cfg.file        then KEY_FILE        = cfg.file        end
end

task.spawn(function()

    local Shield          = CoreGui.RobloxGui.SettingsClippingShield.SettingsShield.MenuContainer.Page
    local HubBarContainer = Shield.HubBar.TabHeaderContainer.HubBarContainer
    local PageViewClipper = Shield.PageViewClipper
    local PageView        = PageViewClipper.PageView

    local HelpTab = HubBarContainer:WaitForChild("HelpTab", 10)
    if not HelpTab then
        warn("[DeoLib] HelpTab not found")
        return
    end

    local clickSnd = Instance.new("Sound")
    clickSnd.SoundId = "rbxassetid://876939830"
    clickSnd.Volume  = 0.5
    clickSnd.Parent  = game:GetService("SoundService")
    nativeClick = function() pcall(function() clickSnd:Play() end) end

    local ourTab = HelpTab:Clone()
    ourTab.Name  = "DeoTab"
    ourTab.Parent = HubBarContainer

    for _, v in pairs(HubBarContainer:GetChildren()) do
        if v:IsA("TextButton") then
            v.Size = UDim2.new(1 / 6, 0, 1, 0)
        end
    end

    local tabLabel = ourTab:FindFirstChild("TabLabel")
    local titleLbl = tabLabel and tabLabel:FindFirstChild("Title")
    local iconLbl  = tabLabel and tabLabel:FindFirstChild("Icon")
    local tabIcon  = nil

    if titleLbl then titleLbl.Text = "Lib" end
    if iconLbl then
        iconLbl.Text = ""
        tabIcon = makeIcon(iconLbl, "zap", 48, Color3.fromRGB(255, 255, 255))
        tabIcon.Size             = UDim2.new(1, 0, 1, 0)
        tabIcon.ZIndex           = iconLbl.ZIndex + 1
        tabIcon.ImageTransparency = 0.5
    end

    local nativeSel = ourTab:FindFirstChild("TabSelection")
    if nativeSel then
        nativeSel.Visible = false
        nativeSel:GetPropertyChangedSignal("Visible"):Connect(function()
            if nativeSel.Visible then nativeSel.Visible = false end
        end)
    end

    local tabUnderline = Instance.new("Frame")
    tabUnderline.Name             = "DeoUnderline"
    tabUnderline.Size             = UDim2.new(1, 0, 0, 2)
    tabUnderline.Position         = UDim2.new(0, 0, 1, -2)
    tabUnderline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    tabUnderline.BorderSizePixel  = 0
    tabUnderline.Visible          = false
    tabUnderline.ZIndex           = 20
    tabUnderline.Parent           = ourTab

    local isActive   = false
    local lastTab    = nil
    local guardReady = false
    local heartbeat  = nil
    local page       -- scroll page, assigned below
    local keyPage    -- key entry overlay, assigned below
    local isUnlocked = false

    for _, tab in pairs(HubBarContainer:GetChildren()) do
        if tab:IsA("TextButton") and tab.Name ~= "DeoTab" then
            local sel = tab:FindFirstChild("TabSelection")
            if sel and sel.Visible then lastTab = tab end
        end
    end

    local function setTabDim(tab, dimmed)
        local lbl = tab:FindFirstChild("TabLabel")
        if not lbl then return end
        local t, i = lbl:FindFirstChild("Title"), lbl:FindFirstChild("Icon")
        local a = dimmed and 0.5 or 0
        if t then t.TextTransparency = a end
        if i then
            i.TextTransparency = a
            pcall(function() i.ImageTransparency = a end)
        end
    end

    local function resetOurTab()
        if heartbeat then heartbeat:Disconnect() heartbeat = nil end
        isActive = false
        tabUnderline.Visible = false
        if page    then page.Visible    = false end
        if keyPage then keyPage.Visible = false end
        PageView.Visible = true
        setTabDim(ourTab, true)
        if tabIcon then tabIcon.ImageTransparency = 0.5 end
    end

    local function cleanupAndHandOff(clickedTab)
        isActive = false
        tabUnderline.Visible = false
        if page    then page.Visible    = false end
        if keyPage then keyPage.Visible = false end
        PageView.Visible = true
        setTabDim(ourTab, true)
        if tabIcon then tabIcon.ImageTransparency = 0.5 end
        if clickedTab then
            lastTab = clickedTab
            setTabDim(clickedTab, false)
            local s = clickedTab:FindFirstChild("TabSelection")
            if s then s.Visible = true end
        end
    end

    local function setupGuard()
        if guardReady then tabUnderline.Visible = true return end
        guardReady = true
        for _, tab in pairs(HubBarContainer:GetChildren()) do
            if tab:IsA("TextButton") and tab.Name ~= "DeoTab" then
                local sel = tab:FindFirstChild("TabSelection")
                if sel then
                    sel:GetPropertyChangedSignal("Visible"):Connect(function()
                        if isActive and sel.Visible then sel.Visible = false end
                    end)
                end
            end
        end
        local shield = HubBarContainer.Parent.Parent.Parent.Parent
        if shield then
            shield:GetPropertyChangedSignal("Visible"):Connect(function()
                if not shield.Visible and isActive then resetOurTab() end
            end)
        end
        tabUnderline.Visible = true
    end

    local function checkWhitelist()
        if not WHITELIST_URL then return false end
        local ok, data = pcall(function()
            return game:HttpGet(WHITELIST_URL)
        end)
        if not ok or not data then return false end
        for line in data:gmatch("[^\n\r]+") do
            if line:match("^%s*(.-)%s*$") == userId then
                return true
            end
        end
        return false
    end

    local function checkFormula(input)
        if not KEY_FORMULA then return false end
        return input == KEY_FORMULA(userId)
    end

    local function saveKey(key)
        pcall(function() writefile(KEY_FILE, key) end)
    end

    local function loadSavedKey()
        local ok, data = pcall(function() return readfile(KEY_FILE) end)
        if ok and data and data ~= "" then return data:match("^%s*(.-)%s*$") end
        return nil
    end

    local CONFIG_FILE = "deolib_config.json"
    local config = {}

    local function saveConfig()
        pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(config))
        end)
    end

    local function loadConfig()
        local ok, data = pcall(function() return readfile(CONFIG_FILE) end)
        if not ok or not data or data == "" then return end
        local ok2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 and type(decoded) == "table" then config = decoded end
    end

    loadConfig()

    page = Instance.new("ScrollingFrame")
    page.Name                 = "DeoPage"
    page.Size                 = UDim2.new(1, 0, 1, 0)
    page.CanvasSize           = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize  = Enum.AutomaticSize.Y
    page.ScrollBarThickness   = 3
    page.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180)
    page.BackgroundTransparency = 1
    page.BorderSizePixel      = 0
    page.Visible              = false
    page.ZIndex               = 5
    page.Parent               = PageViewClipper

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.Padding   = UDim.new(0, 0)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Parent    = page

    local pagePadding = Instance.new("UIPadding")
    pagePadding.PaddingBottom = UDim.new(0, 12)
    pagePadding.Parent        = page

    keyPage = Instance.new("Frame")
    keyPage.Name                 = "DeoKeyPage"
    keyPage.Size                 = UDim2.new(1, 0, 1, 0)
    keyPage.BackgroundTransparency = 1
    keyPage.BorderSizePixel      = 0
    keyPage.Visible              = false
    keyPage.ZIndex               = 6
    keyPage.Parent               = PageViewClipper

    local lockFrame = Instance.new("Frame")
    lockFrame.Size                 = UDim2.new(1, 0, 0, 80)
    lockFrame.Position             = UDim2.new(0, 0, 0, 32)
    lockFrame.BackgroundTransparency = 1
    lockFrame.BorderSizePixel      = 0
    lockFrame.ZIndex               = 7
    lockFrame.Parent               = keyPage
    makeIcon(lockFrame, "lock-keyhole", 48, Color3.fromRGB(200, 200, 200)).Size = UDim2.new(0, 40, 0, 40)
    local _lockIc = lockFrame:FindFirstChildWhichIsA("ImageLabel")
    if _lockIc then _lockIc.Position = UDim2.new(0.5, -20, 0, 0) end

    local keyTitle = Instance.new("TextLabel")
    keyTitle.Size                 = UDim2.new(1, -32, 0, 28)
    keyTitle.Position             = UDim2.new(0, 16, 0, 48)
    keyTitle.BackgroundTransparency = 1
    keyTitle.Text                 = "Enter your key to continue"
    keyTitle.TextColor3           = Color3.fromRGB(255, 255, 255)
    keyTitle.TextSize             = 16
    keyTitle.Font                 = Enum.Font.GothamBold
    keyTitle.TextXAlignment       = Enum.TextXAlignment.Center
    keyTitle.ZIndex               = 7
    keyTitle.Parent               = keyPage

    local keySubtitle = Instance.new("TextLabel")
    keySubtitle.Size                 = UDim2.new(1, -32, 0, 20)
    keySubtitle.Position             = UDim2.new(0, 16, 0, 78)
    keySubtitle.BackgroundTransparency = 1
    keySubtitle.Text                 = PORTAL_URL and ("Get your key at: " .. PORTAL_URL) or "Enter your key below to continue"
    keySubtitle.TextColor3           = Color3.fromRGB(140, 140, 160)
    keySubtitle.TextSize             = 11
    keySubtitle.Font                 = Enum.Font.Gotham
    keySubtitle.TextXAlignment       = Enum.TextXAlignment.Center
    keySubtitle.TextWrapped          = true
    keySubtitle.ZIndex               = 7
    keySubtitle.Parent               = keyPage

    local uidLabel = Instance.new("TextLabel")
    uidLabel.Size                 = UDim2.new(1, -32, 0, 18)
    uidLabel.Position             = UDim2.new(0, 16, 0, 100)
    uidLabel.BackgroundTransparency = 1
    uidLabel.Text                 = "Your User ID: " .. userId
    uidLabel.TextColor3           = Color3.fromRGB(100, 100, 130)
    uidLabel.TextSize             = 10
    uidLabel.Font                 = Enum.Font.Gotham
    uidLabel.TextXAlignment       = Enum.TextXAlignment.Center
    uidLabel.ZIndex               = 7
    uidLabel.Parent               = keyPage

    local inputBg = Instance.new("Frame")
    inputBg.Size                 = UDim2.new(1, -48, 0, 44)
    inputBg.Position             = UDim2.new(0, 24, 0, 130)
    inputBg.BackgroundColor3     = Color3.fromRGB(28, 28, 35)
    inputBg.BorderSizePixel      = 0
    inputBg.ZIndex               = 7
    inputBg.Parent               = keyPage
    Instance.new("UICorner", inputBg).CornerRadius = UDim.new(0, 8)
    local inputStroke = Instance.new("UIStroke")
    inputStroke.Color       = Color3.fromRGB(255, 255, 255)
    inputStroke.Transparency = 0.85
    inputStroke.Thickness    = 1
    inputStroke.Parent       = inputBg

    local keyInput = Instance.new("TextBox")
    keyInput.Size                 = UDim2.new(1, -16, 1, 0)
    keyInput.Position             = UDim2.new(0, 8, 0, 0)
    keyInput.BackgroundTransparency = 1
    keyInput.Text                 = ""
    keyInput.PlaceholderText      = "Paste key here..."
    keyInput.PlaceholderColor3    = Color3.fromRGB(100, 100, 120)
    keyInput.TextColor3           = Color3.fromRGB(220, 220, 220)
    keyInput.TextSize             = 14
    keyInput.Font                 = Enum.Font.GothamSemibold
    keyInput.ClearTextOnFocus     = false
    keyInput.ZIndex               = 8
    keyInput.Parent               = inputBg

    local keyStatus = Instance.new("TextLabel")
    keyStatus.Size                 = UDim2.new(1, -32, 0, 20)
    keyStatus.Position             = UDim2.new(0, 16, 0, 182)
    keyStatus.BackgroundTransparency = 1
    keyStatus.Text                 = ""
    keyStatus.TextColor3           = Color3.fromRGB(255, 80, 80)
    keyStatus.TextSize             = 12
    keyStatus.Font                 = Enum.Font.GothamSemibold
    keyStatus.TextXAlignment       = Enum.TextXAlignment.Center
    keyStatus.ZIndex               = 7
    keyStatus.Parent               = keyPage

    local confirmBtn = Instance.new("TextButton")
    confirmBtn.Size                 = UDim2.new(1, -48, 0, 44)
    confirmBtn.Position             = UDim2.new(0, 24, 0, 208)
    confirmBtn.BackgroundColor3     = Color3.fromRGB(35, 35, 45)
    confirmBtn.BorderSizePixel      = 0
    confirmBtn.Text                 = "Confirm"
    confirmBtn.TextColor3           = Color3.fromRGB(255, 255, 255)
    confirmBtn.TextSize             = 15
    confirmBtn.Font                 = Enum.Font.GothamBold
    confirmBtn.ZIndex               = 7
    confirmBtn.Parent               = keyPage
    Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 8)
    local confirmStroke = Instance.new("UIStroke")
    confirmStroke.Color       = Color3.fromRGB(255, 255, 255)
    confirmStroke.Transparency = 0.78
    confirmStroke.Thickness    = 1
    confirmStroke.Parent       = confirmBtn

    local keyDivider = Instance.new("Frame")
    keyDivider.Size                 = UDim2.new(1, -48, 0, 1)
    keyDivider.Position             = UDim2.new(0, 24, 0, 264)
    keyDivider.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
    keyDivider.BackgroundTransparency = 0.85
    keyDivider.BorderSizePixel      = 0
    keyDivider.ZIndex               = 7
    keyDivider.Parent               = keyPage

    local checkingLabel = Instance.new("TextLabel")
    checkingLabel.Size                 = UDim2.new(1, -32, 0, 20)
    checkingLabel.Position             = UDim2.new(0, 16, 0, 274)
    checkingLabel.BackgroundTransparency = 1
    checkingLabel.Text                 = "Checking whitelist on first open..."
    checkingLabel.TextColor3           = Color3.fromRGB(100, 100, 120)
    checkingLabel.TextSize             = 10
    checkingLabel.Font                 = Enum.Font.Gotham
    checkingLabel.TextXAlignment       = Enum.TextXAlignment.Center
    checkingLabel.ZIndex               = 7
    checkingLabel.Parent               = keyPage

    local tabNames  = {}
    local tabFrames = {}
    local activeTab = 1

    local pillBar = Instance.new("Frame")
    pillBar.Name                 = "PillBar"
    pillBar.Size                 = UDim2.new(1, 0, 0, 40)
    pillBar.BackgroundTransparency = 1
    pillBar.BorderSizePixel      = 0
    pillBar.LayoutOrder          = -1000
    pillBar.ZIndex               = 7
    pillBar.Parent               = page

    local pillLayout = Instance.new("UIListLayout")
    pillLayout.FillDirection  = Enum.FillDirection.Horizontal
    pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    pillLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
    pillLayout.Padding        = UDim.new(0, 6)
    pillLayout.SortOrder      = Enum.SortOrder.LayoutOrder
    pillLayout.Parent         = pillBar

    local pillButtons = {}  -- stores {btn, underline} per tab

    local function showTab(idx)
        activeTab = idx
        for i, frame in pairs(tabFrames) do
            frame.Visible = (i == idx)
        end
        for i, p in pairs(pillButtons) do
            local active = (i == idx)
            p.btn.TextTransparency       = active and 0 or 0.45
            p.underline.Visible          = active
        end
    end

    local function AddSubTab(name)
        local frame = Instance.new("Frame")
        frame.Name                 = name .. "_Tab"
        frame.Size                 = UDim2.new(1, 0, 0, 0)
        frame.AutomaticSize        = Enum.AutomaticSize.Y
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel      = 0
        frame.Visible              = (#tabNames == 0)
        frame.ZIndex               = 6
        frame.LayoutOrder          = #tabNames + 1
        frame.Parent               = page

        local layout = Instance.new("UIListLayout")
        layout.Padding   = UDim.new(0, 0)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent    = frame

        local idx = #tabNames + 1
        table.insert(tabNames,  name)
        table.insert(tabFrames, frame)

        local pill = Instance.new("TextButton")
        pill.Name                 = "Pill_" .. name
        pill.Size                 = UDim2.new(0, math.max(60, #name * 9), 0, 28)
        pill.BackgroundTransparency = 1
        pill.BorderSizePixel      = 0
        pill.Text                 = name
        pill.TextColor3           = Color3.fromRGB(255, 255, 255)
        pill.TextTransparency     = (#tabNames == 1) and 0 or 0.45
        pill.TextSize             = 13
        pill.Font                 = Enum.Font.GothamBold
        pill.ZIndex               = 8
        pill.LayoutOrder          = idx
        pill.Parent               = pillBar

        local pillUnderline = Instance.new("Frame")
        pillUnderline.Size                 = UDim2.new(0.7, 0, 0, 2)
        pillUnderline.Position             = UDim2.new(0.15, 0, 1, -2)
        pillUnderline.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
        pillUnderline.BorderSizePixel      = 0
        pillUnderline.Visible              = (#tabNames == 1)
        pillUnderline.ZIndex               = 9
        pillUnderline.Parent               = pill

        local thisIdx = idx
        pill.MouseButton1Click:Connect(function()
            nativeClick()
            showTab(thisIdx)
        end)

        table.insert(pillButtons, { btn = pill, underline = pillUnderline })

        return frame
    end

    AddDivider = function(parent)
        local w = Instance.new("Frame")
        w.Size                 = UDim2.new(1, 0, 0, 1)
        w.BackgroundTransparency = 1
        w.BorderSizePixel      = 0
        w.ZIndex               = 6
        w.Parent               = parent
        local line = Instance.new("Frame")
        line.Size                 = UDim2.new(1, -32, 0, 1)
        line.Position             = UDim2.new(0, 16, 0, 0)
        line.BackgroundColor3     = Color3.fromRGB(255, 255, 255)
        line.BackgroundTransparency = 0.85
        line.BorderSizePixel      = 0
        line.ZIndex               = 6
        line.Parent               = w
        return w
    end

    local function AddSection(parent, text, icon)
        local row = Instance.new("Frame")
        row.Size                 = UDim2.new(1, 0, 0, 32)
        row.BackgroundTransparency = 1
        row.BorderSizePixel      = 0
        row.ZIndex               = 6
        row.Parent               = parent
        if Lucide and icon then
            pcall(function()
                local slot = Instance.new("Frame")
                slot.Size = UDim2.new(0, 14, 0, 14)
                slot.Position = UDim2.new(0, 16, 0.5, -7)
                slot.BackgroundTransparency = 1
                slot.ZIndex = 7
                slot.Parent = row
                local ic = makeIcon(slot, icon, 48, Color3.fromRGB(120, 120, 150))
                ic.Size = UDim2.new(1, 0, 1, 0)
            end)
        end
        local label = Instance.new("TextLabel")
        label.Size             = UDim2.new(1, -32, 1, 0)
        label.Position         = UDim2.new(0, icon and 34 or 16, 0, 0)
        label.BackgroundTransparency = 1
        label.Text             = text
        label.TextColor3       = Color3.fromRGB(160, 160, 160)
        label.TextSize         = 12
        label.Font             = Enum.Font.GothamBold
        label.TextXAlignment   = Enum.TextXAlignment.Left
        label.ZIndex           = 7
        label.Parent           = row
    end

    AddToggle = function(parent, labelText, default, callback, icon)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 48)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        if Lucide and icon then
            pcall(function()
                local slot = Instance.new("Frame")
                slot.Size = UDim2.new(0, 20, 0, 20)
                slot.Position = UDim2.new(0, 16, 0.5, -10)
                slot.BackgroundTransparency = 1
                slot.ZIndex = 7
                slot.Parent = row
                local ic = makeIcon(slot, icon, 48, Color3.fromRGB(180, 180, 210))
                ic.Size = UDim2.new(1, 0, 1, 0)
            end)
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size             = UDim2.new(0.55, -42, 1, 0)
        nameLabel.Position         = UDim2.new(0, icon and 42 or 16, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text             = labelText
        nameLabel.TextColor3       = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize         = 15
        nameLabel.Font             = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment   = Enum.TextXAlignment.Left
        nameLabel.ZIndex           = 7
        nameLabel.Parent           = row

        local val = default or false

        local leftArrow = Instance.new("TextButton")
        leftArrow.Size                 = UDim2.new(0, 28, 1, 0)
        leftArrow.Position             = UDim2.new(0.55, 0, 0, 0)
        leftArrow.BackgroundTransparency = 1
        leftArrow.Text                 = "<"
        leftArrow.TextColor3           = Color3.fromRGB(200, 200, 200)
        leftArrow.TextSize             = 18
        leftArrow.Font                 = Enum.Font.GothamBold
        leftArrow.ZIndex               = 7
        leftArrow.Parent               = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size                 = UDim2.new(0, 60, 1, 0)
        valueLabel.Position             = UDim2.new(0.55, 28, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text                 = val and "On" or "Off"
        valueLabel.TextColor3           = Color3.fromRGB(255, 255, 255)
        valueLabel.TextSize             = 15
        valueLabel.Font                 = Enum.Font.GothamSemibold
        valueLabel.TextXAlignment       = Enum.TextXAlignment.Center
        valueLabel.ZIndex               = 7
        valueLabel.Parent               = row

        local rightArrow = Instance.new("TextButton")
        rightArrow.Size                 = UDim2.new(0, 28, 1, 0)
        rightArrow.Position             = UDim2.new(0.55, 88, 0, 0)
        rightArrow.BackgroundTransparency = 1
        rightArrow.Text                 = ">"
        rightArrow.TextColor3           = Color3.fromRGB(200, 200, 200)
        rightArrow.TextSize             = 18
        rightArrow.Font                 = Enum.Font.GothamBold
        rightArrow.ZIndex               = 7
        rightArrow.Parent               = row

        local function flip()
            val = not val
            valueLabel.Text = val and "On" or "Off"
            if callback then callback(val) end
        end

        leftArrow.MouseButton1Click:Connect(function()  nativeClick() flip() end)
        rightArrow.MouseButton1Click:Connect(function() nativeClick() flip() end)
        AddDivider(parent)
        return row
    end

    local function AddStatus(parent, labelText, initialValue, icon)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 48)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        if Lucide and icon then
            pcall(function()
                local slot = Instance.new("Frame")
                slot.Size = UDim2.new(0, 20, 0, 20)
                slot.Position = UDim2.new(0, 16, 0.5, -10)
                slot.BackgroundTransparency = 1
                slot.ZIndex = 7
                slot.Parent = row
                local ic = makeIcon(slot, icon, 48, Color3.fromRGB(180, 180, 210))
                ic.Size = UDim2.new(1, 0, 1, 0)
            end)
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, -42, 1, 0)
        nameLabel.Position = UDim2.new(0, icon and 42 or 16, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = labelText
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 15
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 7
        nameLabel.Parent = row

        local dot = Instance.new("Frame")
        dot.Size             = UDim2.new(0, 8, 0, 8)
        dot.Position         = UDim2.new(1, -88, 0.5, -4)
        dot.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
        dot.BorderSizePixel  = 0
        dot.ZIndex           = 7
        dot.Parent           = row
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size             = UDim2.new(0, 74, 1, 0)
        valueLabel.Position         = UDim2.new(1, -78, 0, 0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text             = tostring(initialValue or "—")
        valueLabel.TextColor3       = Color3.fromRGB(220, 220, 220)
        valueLabel.TextSize         = 13
        valueLabel.Font             = Enum.Font.GothamSemibold
        valueLabel.TextXAlignment   = Enum.TextXAlignment.Left
        valueLabel.ZIndex           = 7
        valueLabel.Parent           = row

        AddDivider(parent)
        return function(newValue, newColor)
            if newValue  ~= nil then valueLabel.Text = tostring(newValue) end
            if newColor then
                dot.BackgroundColor3  = newColor
                valueLabel.TextColor3 = newColor
            end
        end
    end

    local function AddTextButton(parent, labelText, buttonText, callback, icon)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 56)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        if Lucide and icon then
            pcall(function()
                local slot = Instance.new("Frame")
                slot.Size = UDim2.new(0, 20, 0, 20)
                slot.Position = UDim2.new(0, 16, 0.5, -10)
                slot.BackgroundTransparency = 1
                slot.ZIndex = 7
                slot.Parent = row
                local ic = makeIcon(slot, icon, 48, Color3.fromRGB(180, 180, 210))
                ic.Size = UDim2.new(1, 0, 1, 0)
            end)
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.5, -42, 1, 0)
        nameLabel.Position = UDim2.new(0, icon and 42 or 16, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = labelText
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 15
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 7
        nameLabel.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, 110, 0, 34)
        btn.Position         = UDim2.new(1, -126, 0.5, -17)
        btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        btn.BorderSizePixel  = 0
        btn.Text             = buttonText or "Press"
        btn.TextColor3       = Color3.fromRGB(255, 255, 255)
        btn.TextSize         = 13
        btn.Font             = Enum.Font.GothamBold
        btn.ZIndex           = 7
        btn.Parent           = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke")
        stroke.Color       = Color3.fromRGB(255, 255, 255)
        stroke.Transparency = 0.82
        stroke.Thickness    = 1
        stroke.Parent       = btn

        btn.MouseButton1Click:Connect(function()
            nativeClick()
            btn.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
            task.delay(0.12, function()
                if btn and btn.Parent then
                    btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
                end
            end)
            if callback then callback() end
        end)

        AddDivider(parent)
        return btn
    end

    local function AddBind(parent, labelText, default, callback)
        local currentKey = default
        local listening  = false

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 56)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
        nameLabel.Position = UDim2.new(0, 16, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = labelText
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 15
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 7
        nameLabel.Parent = row

        local keyBtn = Instance.new("TextButton")
        keyBtn.Size             = UDim2.new(0, 88, 0, 34)
        keyBtn.Position         = UDim2.new(1, -104, 0.5, -17)
        keyBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        keyBtn.BorderSizePixel  = 0
        keyBtn.Text             = currentKey and currentKey.Name or "None"
        keyBtn.TextColor3       = Color3.fromRGB(220, 220, 220)
        keyBtn.TextSize         = 12
        keyBtn.Font             = Enum.Font.GothamBold
        keyBtn.ZIndex           = 7
        keyBtn.Parent           = row
        Instance.new("UICorner", keyBtn).CornerRadius = UDim.new(1, 0)
        local keyStroke = Instance.new("UIStroke")
        keyStroke.Color       = Color3.fromRGB(255, 255, 255)
        keyStroke.Transparency = 0.82
        keyStroke.Thickness    = 1
        keyStroke.Parent       = keyBtn

        local hint = Instance.new("TextLabel")
        hint.Size             = UDim2.new(0, 88, 0, 14)
        hint.Position         = UDim2.new(1, -104, 0.5, 18)
        hint.BackgroundTransparency = 1
        hint.Text             = "click to bind"
        hint.TextColor3       = Color3.fromRGB(120, 120, 140)
        hint.TextSize         = 10
        hint.Font             = Enum.Font.Gotham
        hint.TextXAlignment   = Enum.TextXAlignment.Center
        hint.ZIndex           = 7
        hint.Parent           = row

        keyBtn.MouseButton1Click:Connect(function()
            if listening then return end
            listening = true
            keyBtn.Text       = "..."
            keyBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
            keyStroke.Color   = Color3.fromRGB(255, 215, 0)
            hint.Text         = "press a key"
            local conn
            conn = UIS.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    currentKey        = input.KeyCode
                    keyBtn.Text       = input.KeyCode.Name
                    keyBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
                    keyStroke.Color   = Color3.fromRGB(255, 255, 255)
                    hint.Text         = "click to bind"
                    listening         = false
                    conn:Disconnect()
                    if callback then callback(currentKey) end
                end
            end)
        end)

        AddDivider(parent)
        return function() return currentKey end
    end

    AddSlider = function(parent, labelText, minVal, maxVal, defaultVal, step, suffix, callback)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 60)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, 0, 0, 24)
        nameLabel.Position = UDim2.new(0, 16, 0, 6)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = labelText
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 15
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 7
        nameLabel.Parent = row

        local val = defaultVal or minVal

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0.4, 0, 0, 20)
        valueLabel.Position = UDim2.new(0.6, 0, 0, 6)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = tostring(val) .. (suffix or "")
        valueLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        valueLabel.TextSize = 13
        valueLabel.Font = Enum.Font.GothamSemibold
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right
        valueLabel.ZIndex = 7
        valueLabel.Parent = row

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(1, -32, 0, 6)
        track.Position         = UDim2.new(0, 16, 0, 42)
        track.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
        track.BorderSizePixel  = 0
        track.ZIndex           = 7
        track.Parent           = row
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
        fill.BorderSizePixel  = 0
        fill.ZIndex           = 8
        fill.Parent           = track
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("TextButton")
        knob.Size             = UDim2.new(0, 20, 0, 20)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel  = 0
        knob.Text             = ""
        knob.ZIndex           = 9
        knob.Parent           = track
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local function setValue(newVal)
            newVal = math.clamp(newVal, minVal, maxVal)
            if step then newVal = math.round((newVal - minVal) / step) * step + minVal end
            val = newVal
            valueLabel.Text = tostring(val) .. (suffix or "")
            local pct = (val - minVal) / (maxVal - minVal)
            fill.Size     = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, -10, 0.5, -10)
            if callback then callback(val) end
        end

        setValue(val)

        local dragging = false
        local function dragTo(x)
            local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            setValue(minVal + (maxVal - minVal) * pct)
        end

        knob.MouseButton1Down:Connect(function() dragging = true end)
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragTo(input.Position.X) dragging = true
            end
        end)
        knob.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then dragging = true end
        end)
        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                dragTo(input.Position.X)
            end
        end)
        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        AddDivider(parent)
        return function(v) setValue(v) end
    end

    AddMultiplier = function(parent, labelText, values, defaultValue, callback)
        local SEG_W, SEG_H, SEG_GAP = 28, 28, 2
        local COLOR_ON  = Color3.fromRGB(220, 220, 220)
        local COLOR_OFF = Color3.fromRGB(55, 55, 60)

        local idx = 1
        if defaultValue ~= nil then
            for i, v in ipairs(values) do
                if tostring(v) == tostring(defaultValue) then idx = i break end
            end
        end

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 56)
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = parent

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.40, -16, 0, 20)
        nameLabel.Position = UDim2.new(0, 16, 0, 6)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = labelText
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.GothamSemibold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 7
        nameLabel.Parent = row

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0.40, -16, 0, 16)
        valueLabel.Position = UDim2.new(0, 16, 0, 28)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = tostring(values[idx])
        valueLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
        valueLabel.TextSize = 11
        valueLabel.Font = Enum.Font.GothamSemibold
        valueLabel.TextXAlignment = Enum.TextXAlignment.Left
        valueLabel.ZIndex = 7
        valueLabel.Parent = row

        local segCount = #values
        local trackW   = segCount * (SEG_W + SEG_GAP) - SEG_GAP
        local barHolder = Instance.new("Frame")
        barHolder.Size = UDim2.new(0, 38 + trackW + 12 + 36, 0, 56)
        barHolder.Position = UDim2.new(0.42, 0, 0, 0)
        barHolder.BackgroundTransparency = 1
        barHolder.BorderSizePixel = 0
        barHolder.ZIndex = 7
        barHolder.Parent = row

        local minusBtn = Instance.new("TextButton")
        minusBtn.Size = UDim2.new(0, 30, 0, 30)
        minusBtn.Position = UDim2.new(0, 0, 0.5, -15)
        minusBtn.BackgroundTransparency = 1
        minusBtn.Text = "−"
        minusBtn.TextColor3 = Color3.fromRGB(210, 210, 215)
        minusBtn.TextSize = 20
        minusBtn.Font = Enum.Font.GothamBold
        minusBtn.ZIndex = 8
        minusBtn.Parent = barHolder

        local trackH = SEG_H + 8
        local trackPill = Instance.new("Frame")
        trackPill.Size = UDim2.new(0, trackW + 12, 0, trackH)
        trackPill.Position = UDim2.new(0, 34, 0.5, -trackH / 2)
        trackPill.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
        trackPill.BorderSizePixel  = 0
        trackPill.ZIndex = 7
        trackPill.Parent = barHolder
        Instance.new("UICorner", trackPill).CornerRadius = UDim.new(0.5, 0)

        local plusBtn = Instance.new("TextButton")
        plusBtn.Size = UDim2.new(0, 30, 0, 30)
        plusBtn.Position = UDim2.new(0, 34 + trackW + 12 + 4, 0.5, -15)
        plusBtn.BackgroundTransparency = 1
        plusBtn.Text = "+"
        plusBtn.TextColor3 = Color3.fromRGB(210, 210, 215)
        plusBtn.TextSize = 20
        plusBtn.Font = Enum.Font.GothamBold
        plusBtn.ZIndex = 8
        plusBtn.Parent = barHolder

        local segments = {}
        for s = 1, segCount do
            local seg = Instance.new("Frame")
            seg.Size = UDim2.new(0, SEG_W, 0, SEG_H)
            seg.Position = UDim2.new(0, 6 + (s-1)*(SEG_W+SEG_GAP), 0.5, -SEG_H/2)
            seg.BackgroundColor3 = s <= idx and COLOR_ON or COLOR_OFF
            seg.BorderSizePixel = 0
            seg.ZIndex = 9
            seg.Parent = trackPill
            local corner = Instance.new("UICorner")
            corner.CornerRadius = (s == 1 or s == segCount) and UDim.new(0.5, 0) or UDim.new(0.15, 0)
            corner.Parent = seg
            table.insert(segments, seg)
        end

        local function refresh()
            valueLabel.Text = tostring(values[idx])
            for i, seg in ipairs(segments) do
                seg.BackgroundColor3 = i <= idx and COLOR_ON or COLOR_OFF
            end
            if callback then callback(values[idx]) end
        end

        for s, seg in ipairs(segments) do
            local hit = Instance.new("TextButton")
            hit.Size = UDim2.new(1,0,1,0) hit.BackgroundTransparency=1 hit.Text="" hit.ZIndex=10 hit.Parent=seg
            hit.MouseButton1Click:Connect(function() nativeClick() idx=s refresh() end)
        end

        minusBtn.MouseButton1Click:Connect(function()
            nativeClick() idx = math.max(1, idx - 1) refresh()
        end)
        plusBtn.MouseButton1Click:Connect(function()
            nativeClick() idx = math.min(#values, idx + 1) refresh()
        end)

        if callback then task.defer(function() callback(values[idx]) end) end
        AddDivider(parent)
        return function() return values[idx] end
    end

    local function Notify(title, text, duration)
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = title,
            Text     = text,
            Duration = duration or 4,
        })
    end

    local function AddToggleCfg(parent, labelText, default, callback, icon)
        local key   = "toggle_" .. labelText:gsub("%W", "_")
        local saved = (config[key] ~= nil) and config[key] or default
        local row = AddToggle(parent, labelText, saved, function(v)
            config[key] = v saveConfig()
            if callback then callback(v) end
        end, icon)
        if saved ~= default and callback then
            task.defer(function() pcall(callback, saved) end)
        end
        return row
    end

    local function AddSliderCfg(parent, labelText, minVal, maxVal, defaultVal, step, suffix, callback)
        local key   = "slider_" .. labelText:gsub("%W", "_")
        local saved = (config[key] ~= nil) and config[key] or defaultVal
        return AddSlider(parent, labelText, minVal, maxVal, saved, step, suffix, function(v)
            config[key] = v saveConfig()
            if callback then callback(v) end
        end)
    end

    local function AddMultiplierCfg(parent, labelText, values, defaultValue, callback)
        local key      = "multi_" .. labelText:gsub("%W", "_")
        local savedRaw = config[key]
        local resolved = defaultValue
        if savedRaw ~= nil then
            for _, v in ipairs(values) do
                if tostring(v) == tostring(savedRaw) then resolved = v break end
            end
        end
        local skipFirst = (savedRaw ~= nil)
        local getter = AddMultiplier(parent, labelText, values, resolved, function(v)
            if skipFirst then skipFirst = false return end
            config[key] = v saveConfig()
            if callback then callback(v) end
        end)
        if savedRaw ~= nil and callback then
            task.defer(function() pcall(callback, resolved) end)
        end
        return getter
    end

    local function enforceActive()
        tabUnderline.Visible = true
        if page    then page.Visible    = (isUnlocked) end
        if keyPage then keyPage.Visible = (not isUnlocked) end
        PageView.Visible = false
        if tabIcon then tabIcon.ImageTransparency = 0 end
        local lbl = ourTab:FindFirstChild("TabLabel")
        if lbl then
            local t = lbl:FindFirstChild("Title")
            if t then t.TextTransparency = 0 end
        end
        for _, tab in pairs(HubBarContainer:GetChildren()) do
            if tab:IsA("TextButton") and tab.Name ~= "DeoTab" then
                local sel = tab:FindFirstChild("TabSelection")
                if sel and sel.Visible then sel.Visible = false end
                setTabDim(tab, true)
            end
        end
    end

    local function openLib()
        isActive = true
        PageView.Visible = false
        pcall(function() PageView.CanvasPosition = Vector2.new(0,0) end)
        if isUnlocked then
            page.Visible    = true
            keyPage.Visible = false
        else
            page.Visible    = false
            keyPage.Visible = true
        end
        setupGuard()
        if heartbeat then heartbeat:Disconnect() end
        heartbeat = RunService.Heartbeat:Connect(enforceActive)
    end

    local function closeLib(clickedTab)
        if heartbeat then heartbeat:Disconnect() heartbeat = nil end
        cleanupAndHandOff(clickedTab)
    end

    ourTab.MouseButton1Click:Connect(openLib)

    for _, tab in pairs(HubBarContainer:GetChildren()) do
        if tab:IsA("TextButton") and tab.Name ~= "DeoTab" then
            tab.MouseButton1Click:Connect(function()
                if isActive then closeLib(tab) else lastTab = tab end
            end)
        end
        if tab:IsA("TextButton") then
            tab.MouseButton1Click:Connect(nativeClick)
        end
    end

    local statusUpdate  -- forward ref, assigned after AddStatus calls below

    local function unlock()
        isUnlocked      = true
        keyPage.Visible = false
        page.Visible    = true
        if statusUpdate then statusUpdate("Unlocked", Color3.fromRGB(127, 255, 154)) end
        Notify("DeoLib", "Access granted! Welcome.", 3)
    end

    local function tryKey(input)
        input = input:match("^%s*(.-)%s*$")  -- trim whitespace
        if checkFormula(input) then
            saveKey(input)
            unlock()
            return
        end
        keyStatus.TextColor3 = Color3.fromRGB(255, 80, 80)
        keyStatus.Text = "Invalid key. Check you used the right UserID."
    end

    confirmBtn.MouseButton1Click:Connect(function()
        nativeClick()
        confirmBtn.BackgroundColor3 = Color3.fromRGB(60,60,72)
        task.delay(0.12, function()
            if confirmBtn and confirmBtn.Parent then
                confirmBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
            end
        end)
        keyStatus.Text = "Checking..."
        keyStatus.TextColor3 = Color3.fromRGB(180,180,180)
        task.spawn(tryKey, keyInput.Text)
    end)

    keyInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            keyStatus.Text = "Checking..."
            keyStatus.TextColor3 = Color3.fromRGB(180,180,180)
            task.spawn(tryKey, keyInput.Text)
        end
    end)

    local API_URL = PORTAL_URL and (PORTAL_URL .. "/.netlify/functions/balance?userId=") or nil

    local function checkKeylessBackend()
        if not API_URL then return false end
        local ok, result = pcall(function()
            return game:HttpGet(API_URL .. userId)
        end)
        if not ok or not result then return false end
        local ok2, data = pcall(function()
            return game:GetService("HttpService"):JSONDecode(result)
        end)
        if not ok2 or type(data) ~= "table" then return false end
        return data.keyless == true or data.permanent == true
    end

    task.spawn(function()
        -- 1. check saved key file first (instant, no network)
        local saved = loadSavedKey()
        if saved and checkFormula(saved) then
            isUnlocked = true
            checkingLabel.Text = "✓ Saved key valid"
            return
        end

        -- 2. check keyless status from portal backend
        checkingLabel.Text = "Checking keyless status..."
        if checkKeylessBackend() then
            isUnlocked = true
            checkingLabel.Text = "✓ Keyless active"
            -- save formula key locally so future checks are instant
            if KEY_FORMULA then saveKey(KEY_FORMULA(userId)) end
            return
        end

        -- 3. try whitelist (needs network)
        if WHITELIST_URL then
            checkingLabel.Text = "Checking whitelist..."
            if checkWhitelist() then
                isUnlocked = true
                checkingLabel.Text = "✓ Whitelisted"
                if KEY_FORMULA then saveKey(KEY_FORMULA(userId)) end
                return
            end
        end

        checkingLabel.Text = "Not keyless — enter your key or visit the portal"
    end)

    -- TAB 1: Main
    local mainTab = AddSubTab("Main")
    AddSection(mainTab, "PLAYER")
    AddToggle(mainTab, "God Mode", false, function(v)
        print("God Mode:", v)
    end)
    AddToggle(mainTab, "Infinite Jump", false, function(v)
        print("Infinite Jump:", v)
    end)
    AddSlider(mainTab, "Walk Speed", 8, 100, 16, 1, " st", function(v)
        local char = game.Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.WalkSpeed = v
        end
    end)
    AddSlider(mainTab, "Jump Power", 50, 300, 50, 10, "", function(v)
        local char = game.Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") then
            char.Humanoid.JumpPower = v
        end
    end)
    AddSection(mainTab, "ACTIONS")
    AddTextButton(mainTab, "Respawn", "Go", function()
        game.Players.LocalPlayer:LoadCharacter()
    end)
    AddTextButton(mainTab, "Copy UserID", "Copy", function()
        pcall(function() setclipboard(userId) end)
        Notify("Copied!", "UserID: " .. userId, 3)
    end)

    -- TAB 2: Visuals
    local visualsTab = AddSubTab("Visuals")
    AddSection(visualsTab, "LIGHTING")
    AddToggle(visualsTab, "Full Bright", false, function(v)
        local L = game:GetService("Lighting")
        if v then
            L.Ambient = Color3.new(1,1,1)
            L.OutdoorAmbient = Color3.new(1,1,1)
            L.Brightness = 3
            L.GlobalShadows = false
        else
            L.Ambient = Color3.new(0,0,0)
            L.OutdoorAmbient = Color3.fromRGB(128,128,128)
            L.Brightness = 2
            L.GlobalShadows = true
        end
    end)
    AddSection(visualsTab, "RENDER")
    AddMultiplier(visualsTab, "Render Distance", {64, 128, 256, 512, 1024}, 256, function(v)
        -- MaxDistanceLimit controls how far parts are rendered for LocalScripts
        pcall(function()
            game:GetService("Workspace").StreamingTargetRadius = v
        end)
        print("Render Distance:", v)
    end)
    AddStatus(visualsTab, "FPS", "—")

    -- TAB 3: Misc
    local miscTab = AddSubTab("Misc")
    AddSection(miscTab, "TOOLS")
    AddTextButton(miscTab, "Infinite Yield", "Load", function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
    end)
    AddSection(miscTab, "INFO")
    AddStatus(miscTab, "User ID", userId)
    statusUpdate = AddStatus(miscTab, "Status", isUnlocked and "Unlocked" or "Locked")
    AddSection(miscTab, "BINDS")
    AddBind(miscTab, "Toggle Menu", Enum.KeyCode.RightShift, function(key)
        print("Bind set to:", key.Name)
    end)

    DeoLib.AddTab           = AddSubTab
    DeoLib.AddSection       = AddSection
    DeoLib.AddDivider       = AddDivider
    DeoLib.AddToggle        = AddToggle
    DeoLib.AddToggleCfg     = AddToggleCfg
    DeoLib.AddStatus        = AddStatus
    DeoLib.AddTextButton    = AddTextButton
    DeoLib.AddBind          = AddBind
    DeoLib.AddSlider        = AddSlider
    DeoLib.AddSliderCfg     = AddSliderCfg
    DeoLib.AddMultiplier    = AddMultiplier
    DeoLib.AddMultiplierCfg = AddMultiplierCfg
    DeoLib.Notify           = Notify
    DeoLib.CreateIcon       = makeIcon
    DeoLib.SaveConfig       = saveConfig
    DeoLib.LoadConfig       = loadConfig

    print("[DeoLib] ready —", #tabNames, "tab(s) | unlocked:", isUnlocked)
end)

return DeoLib
