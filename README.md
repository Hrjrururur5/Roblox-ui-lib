# DeoLib

A lightweight UI library for Roblox that hooks into the native settings menu. Feels right at home — same fonts, same style, same click sounds.

---

## Quick Start

```lua
local Lib = loadstring(game:HttpGet("YOUR_RAW_URL"))()

local main = Lib:AddTab("Main")

Lib:AddToggle(main, "God Mode", false, function(v)
    print("God Mode:", v)
end)
```

---

## Key System (Optional)

If you want to lock your script behind a key, call `SetKeySystem` before adding any tabs:

```lua
Lib:SetKeySystem({
    formula  = function(uid) return uid .. "-yourkey" end,
    portal   = "https://yoursite.com",       -- shown to users on key screen
    whitelist = "https://pastebin.com/raw/X", -- optional, one UserID per line
})
```

If you don't call `SetKeySystem`, no key screen appears.

---

## API

### `Lib:AddTab(name)`
Creates a new tab in the menu. Returns the tab frame to pass into other functions.

```lua
local main = Lib:AddTab("Main")
local visuals = Lib:AddTab("Visuals")
```

---

### `Lib:AddSection(tab, text)`
Adds a section header label inside a tab.

```lua
Lib:AddSection(main, "PLAYER")
```

---

### `Lib:AddToggle(tab, label, default, callback, icon?)`
Adds an on/off toggle.

| Param | Type | Description |
|-------|------|-------------|
| tab | frame | Tab to add to |
| label | string | Display name |
| default | bool | Starting value |
| callback | function(v) | Called when toggled |
| icon | string? | Lucide icon name (optional) |

```lua
Lib:AddToggle(main, "Infinite Jump", false, function(v)
    -- v = true or false
end)
```

---

### `Lib:AddSlider(tab, label, min, max, default, step, suffix, callback)`
Adds a draggable slider.

| Param | Type | Description |
|-------|------|-------------|
| tab | frame | Tab to add to |
| label | string | Display name |
| min | number | Minimum value |
| max | number | Maximum value |
| default | number | Starting value |
| step | number | Snap increment |
| suffix | string | Unit label e.g. `" st"` |
| callback | function(v) | Called on change |

```lua
Lib:AddSlider(main, "Walk Speed", 8, 100, 16, 1, " st", function(v)
    game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = v
end)
```

---

### `Lib:AddMultiplier(tab, label, values, default, callback)`
Adds a segmented bar picker for selecting from a list of values.

| Param | Type | Description |
|-------|------|-------------|
| tab | frame | Tab to add to |
| label | string | Display name |
| values | table | List of values e.g. `{1, 2, 5, 10}` |
| default | any | Starting value |
| callback | function(v) | Called on change |

```lua
Lib:AddMultiplier(main, "FOV", {70, 90, 110, 130}, 90, function(v)
    game.Workspace.CurrentCamera.FieldOfView = v
end)
```

---

### `Lib:AddTextButton(tab, label, buttonText, callback, icon?)`
Adds a row with a clickable button on the right.

```lua
Lib:AddTextButton(main, "Respawn", "Go", function()
    game.Players.LocalPlayer:LoadCharacter()
end)
```

---

### `Lib:AddStatus(tab, label, initialValue, icon?)`
Adds a read-only status row. Returns an updater function to change the value later.

```lua
local setHP = Lib:AddStatus(main, "Health", "100")

-- update it later
setHP("50", Color3.fromRGB(255, 80, 80))
```

---

### `Lib:AddBind(tab, label, default, callback)`
Adds a keybind row. User clicks the button then presses a key to bind it.

```lua
Lib:AddBind(main, "Toggle ESP", Enum.KeyCode.X, function(key)
    print("Bound to", key.Name)
end)
```

---

### `Lib:AddDivider(tab)`
Adds a thin divider line.

```lua
Lib:AddDivider(main)
```

---

### `Lib:AddToggleCfg(tab, label, default, callback, icon?)`
Same as `AddToggle` but automatically saves and restores the value across sessions.

```lua
Lib:AddToggleCfg(main, "God Mode", false, function(v) end)
```

---

### `Lib:AddSliderCfg(tab, label, min, max, default, step, suffix, callback)`
Same as `AddSlider` but saves and restores the value across sessions.

---

### `Lib:AddMultiplierCfg(tab, label, values, default, callback)`
Same as `AddMultiplier` but saves and restores the value across sessions.

---

### `Lib:Notify(title, text, duration?)`
Sends a native Roblox notification.

```lua
Lib:Notify("DeoLib", "Script loaded!", 4)
```

---

### `Lib:GetMyKey()`
Prints and returns the formula key for the current user. Useful for testing your key system.

```lua
Lib:GetMyKey()
-- prints: [DeoLib] Your key: 123456789-17578613
```

---

## Config Persistence

Use the `Cfg` variants (`AddToggleCfg`, `AddSliderCfg`, `AddMultiplierCfg`) to automatically save values to a JSON file. Settings are restored the next time the script runs.

```lua
-- saved to deolib_config.json in the executor's workspace folder
Lib:AddToggleCfg(main, "Auto Farm", false, function(v) end)
Lib:AddSliderCfg(main, "Speed", 8, 100, 16, 1, " st", function(v) end)
```

---

## Full Example

```lua
local Lib = loadstring(game:HttpGet("YOUR_RAW_URL"))()

-- optional key system
Lib:SetKeySystem({
    formula = function(uid) return uid .. "-abc123" end,
    portal  = "https://yourportal.netlify.app",
})

-- tabs
local main    = Lib:AddTab("Main")
local visuals = Lib:AddTab("Visuals")
local misc    = Lib:AddTab("Misc")

-- main tab
Lib:AddSection(main, "PLAYER")
Lib:AddToggleCfg(main, "God Mode", false, function(v)
    -- toggle god mode
end)
Lib:AddSliderCfg(main, "Walk Speed", 8, 100, 16, 1, " st", function(v)
    game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = v
end)
Lib:AddSection(main, "ACTIONS")
Lib:AddTextButton(main, "Respawn", "Go", function()
    game.Players.LocalPlayer:LoadCharacter()
end)

-- visuals tab
Lib:AddSection(visuals, "LIGHTING")
Lib:AddToggle(visuals, "Full Bright", false, function(v)
    local L = game:GetService("Lighting")
    L.Ambient = v and Color3.new(1,1,1) or Color3.new(0,0,0)
    L.GlobalShadows = not v
end)

local setFPS = Lib:AddStatus(visuals, "FPS", "—")
game:GetService("RunService").Heartbeat:Connect(function()
    setFPS(math.floor(1 / game:GetService("RunService").Heartbeat:Wait()))
end)

-- misc tab
Lib:AddSection(misc, "BINDS")
Lib:AddBind(misc, "Toggle Menu", Enum.KeyCode.RightShift, function(key) end)

Lib:Notify("Loaded", "Script ready!", 3)
```

---

## Notes

- DeoLib hooks into Roblox's native settings menu — open it with the **Roblox menu button** then click the **Lib** tab
- Config files are saved to your executor's workspace folder
- Icons require the `lucide-roblox` module — set `LUCIDE_SOURCE` at the top of the lib if you want icons
