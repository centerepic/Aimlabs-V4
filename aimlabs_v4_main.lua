Version = '4.1c'

local SMode = false

if UseSMode then
	SMode = true
end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StudioTestMode = false
local Camera = workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
end)

if StudioTestMode then
	Aiming = {}
	Aiming.Settings = {}
	Aiming.Settings.Ignored = {}
	Aiming.Settings.FOVSettings = {}
else
	Aiming = loadstring(game:HttpGet("https://raw.githubusercontent.com/Stefanuk12/Aiming/main/Load.lua"))()("Module")

	Aiming.Settings.VisibleCheck = false
	Aiming.Settings.Ignored.IgnoreLocalTeam = false
	Aiming.Settings.TargetPart = {"Head"}
	Aiming.Settings.FOVSettings.Colour = Color3.new(1, 0.831372, 0.949019)
	Aiming.Settings.FOVSettings.Sides = 30
	Aiming.Settings.TracerSettings.Enabled = false

	AimingSelected = Aiming.Selected
	AimingChecks = Aiming.Checks
end

--Settings--
local ESP = {
	UseDistance = true,
    Enabled = false,
    Boxes = true,
    BoxShift = CFrame.new(0,0,0),
	BoxSize = Vector3.new(4,6,0),
    Color = Color3.fromRGB(255, 170, 0),
    FaceCamera = false,
    Names = true,
    TeamColor = true,
    Thickness = 2,
    AttachShift = 1,
    TeamMates = true,
    Players = true,
    PlayerDistance = 1000,
    Objects = setmetatable({}, {__mode="kv"}),
    Overrides = {}
}

--Declarations--
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local WorldToViewportPoint = Camera.WorldToViewportPoint

--Functions--
local function Draw(obj, props)
	local new = Drawing.new(obj)
	
	props = props or {}
	for i,v in pairs(props) do
		new[i] = v
	end
	return new
end

function ESP:GetTeam(p)
	local ov = self.Overrides.GetTeam
	if ov then
		return ov(p)
	end
	
	return p and p.Team
end

function ESP:IsTeamMate(p)
    local ov = self.Overrides.IsTeamMate
	if ov then
		return ov(p)
    end
    
    return self:GetTeam(p) == self:GetTeam(LocalPlayer)
end

function ESP:GetColor(obj)
	local ov = self.Overrides.GetColor
	if ov then
		return ov(obj)
    end
    local p = self:GetPlrFromChar(obj)
	return p and self.TeamColor and p.Team and p.Team.TeamColor.Color or self.Color
end

function ESP:GetPlrFromChar(char)
	local ov = self.Overrides.GetPlrFromChar
	if ov then
		return ov(char)
	end
	
	return Players:GetPlayerFromCharacter(char)
end

function ESP:Toggle(bool)
    self.Enabled = bool
    if not bool then
        for i,v in pairs(self.Objects) do
            if v.Type == "Box" then --fov circle etc
                if v.Temporary then
                    v:Remove()
                else
                    for i,v in pairs(v.Components) do
                        v.Visible = false
                    end
                end
            end
        end
    end
end

function ESP:GetBox(obj)
    return self.Objects[obj]
end

function ESP:AddObjectListener(parent, options)
    local function NewListener(c)
        if type(options.Type) == "string" and c:IsA(options.Type) or options.Type == nil then
            if type(options.Name) == "string" and c.Name == options.Name or options.Name == nil then
                if not options.Validator or options.Validator(c) then
                    local box = ESP:Add(c, {
                        PrimaryPart = type(options.PrimaryPart) == "string" and c:WaitForChild(options.PrimaryPart) or type(options.PrimaryPart) == "function" and options.PrimaryPart(c),
                        Color = type(options.Color) == "function" and options.Color(c) or options.Color,
                        ColorDynamic = options.ColorDynamic,
                        Name = type(options.CustomName) == "function" and options.CustomName(c) or options.CustomName,
                        IsEnabled = options.IsEnabled,
                        RenderInNil = options.RenderInNil
                    })
                    --TODO: add a better way of passing options
                    if options.OnAdded then
                        coroutine.wrap(options.OnAdded)(box)
                    end
                end
            end
        end
    end

    if options.Recursive then
        parent.DescendantAdded:Connect(NewListener)
        for i,v in pairs(parent:GetDescendants()) do
            coroutine.wrap(NewListener)(v)
        end
    else
        parent.ChildAdded:Connect(NewListener)
        for i,v in pairs(parent:GetChildren()) do
            coroutine.wrap(NewListener)(v)
        end
    end
end

local boxBase = {}
boxBase.__index = boxBase

function boxBase:Remove()
    ESP.Objects[self.Object] = nil
    for i,v in pairs(self.Components) do
        v.Visible = false
        v:Remove()
        self.Components[i] = nil
    end
end

function boxBase:Update()
    if not self.PrimaryPart then
        --warn("not supposed to print", self.Object)
        return self:Remove()
    end

    local color
    if ESP.Highlighted == self.Object then
       color = ESP.HighlightColor
    else
        color = self.Color or self.ColorDynamic and self:ColorDynamic(self.Player) or ESP:GetColor(self.Object) or ESP.Color
    end

    local allow = true
    if ESP.Overrides.UpdateAllow and not ESP.Overrides.UpdateAllow(self) then
        allow = false
    end
    if self.Player and not ESP.TeamMates and ESP:IsTeamMate(self.Player) then
        allow = false
    end
    if self.Player and not ESP.Players then
        allow = false
    end
    if self.IsEnabled and (type(self.IsEnabled) == "string" and not ESP[self.IsEnabled] or type(self.IsEnabled) == "function" and not self:IsEnabled()) then
        allow = false
    end
    if not workspace:IsAncestorOf(self.PrimaryPart) and not self.RenderInNil then
        allow = false
    end

    local MaxDistance = 1000
    if type(self.MaxDistance) == 'function' then
	MaxDistance = self.MaxDistance()
    else
	MaxDistance = self.MaxDistance
    end
    local cft = self.PrimaryPart.CFrame
    if (Camera.CFrame.p - cft.p).magnitude > MaxDistance then
	allow = false
    end
	
    if not allow then
        for i,v in pairs(self.Components) do
            v.Visible = false
        end
        return
    end

    if ESP.Highlighted == self.Object then
        color = ESP.HighlightColor
    end

    --calculations--
    local cf = self.PrimaryPart.CFrame
    if ESP.FaceCamera then
        cf = CFrame.new(cf.p, Camera.CFrame.p)
    end
    local size = self.Size
    local locs = {
        TopLeft = cf * ESP.BoxShift * CFrame.new(size.X/2,size.Y/2,0),
        TopRight = cf * ESP.BoxShift * CFrame.new(-size.X/2,size.Y/2,0),
        BottomLeft = cf * ESP.BoxShift * CFrame.new(size.X/2,-size.Y/2,0),
        BottomRight = cf * ESP.BoxShift * CFrame.new(-size.X/2,-size.Y/2,0),
        TagPos = cf * ESP.BoxShift * CFrame.new(0,size.Y/2,0),
        Torso = cf * ESP.BoxShift
    }

    if ESP.Boxes and self.BoxVisible then
        local TopLeft, Vis1 = WorldToViewportPoint(Camera, locs.TopLeft.p)
        local TopRight, Vis2 = WorldToViewportPoint(Camera, locs.TopRight.p)
        local BottomLeft, Vis3 = WorldToViewportPoint(Camera, locs.BottomLeft.p)
        local BottomRight, Vis4 = WorldToViewportPoint(Camera, locs.BottomRight.p)

        if self.Components.Quad then
            if Vis1 or Vis2 or Vis3 or Vis4 then
                self.Components.Quad.Visible = true
                self.Components.Quad.PointA = Vector2.new(TopRight.X, TopRight.Y)
                self.Components.Quad.PointB = Vector2.new(TopLeft.X, TopLeft.Y)
                self.Components.Quad.PointC = Vector2.new(BottomLeft.X, BottomLeft.Y)
                self.Components.Quad.PointD = Vector2.new(BottomRight.X, BottomRight.Y)
                self.Components.Quad.Color = color
            else
                self.Components.Quad.Visible = false
            end
        end
    else
        self.Components.Quad.Visible = false
    end

    if ESP.Names or (ESP.UseDistance == false) then
        local TagPos, Vis5 = WorldToViewportPoint(Camera, locs.TagPos.p)
        
        if Vis5 then
			if ESP.Names then
				self.Components.Name.Visible = true
				self.Components.Name.Position = Vector2.new(TagPos.X, TagPos.Y)
				self.Components.Name.Text = self.Name
				self.Components.Name.Color = color
			else
				self.Components.Name.Visible = false
			end
            
            self.Components.Distance.Visible = true
            self.Components.Distance.Position = Vector2.new(TagPos.X, TagPos.Y + 14)
			if ESP.UseDistance then
				self.Components.Distance.Text = math.floor((Camera.CFrame.p - cf.p).magnitude) .."m away"
			else
				self.Components.Distance.Text = "No Tool"

				if self.Player and self.Player.Character and self.Player.Character:FindFirstChildOfClass("Tool") then
					self.Components.Distance.Text = self.Player.Character:FindFirstChildOfClass("Tool").Name
				end
			end
            self.Components.Distance.Color = color
        else
            self.Components.Name.Visible = false
            self.Components.Distance.Visible = false
        end
    else
        self.Components.Name.Visible = false
        self.Components.Distance.Visible = false
    end
    
    if ESP.Tracers then
        local TorsoPos, Vis6 = WorldToViewportPoint(Camera, locs.Torso.p)

        if Vis6 then
            self.Components.Tracer.Visible = true
            self.Components.Tracer.From = Vector2.new(TorsoPos.X, TorsoPos.Y)
            self.Components.Tracer.To = Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/ESP.AttachShift)
            self.Components.Tracer.Color = color
        else
            self.Components.Tracer.Visible = false
        end
    else
        self.Components.Tracer.Visible = false
    end
end

function ESP:Add(obj, options)
    if not obj.Parent and not options.RenderInNil then
        return warn(obj, "has no parent")
    end

    local box = setmetatable({
        Name = options.Name or obj.Name,
		MaxDistance = options.MaxDistance or 1000,
        Type = "Box",
		BoxVisible = options.Box,
        Color = options.Color --[[or self:GetColor(obj)]],
        Size = options.Size or self.BoxSize,
        Object = obj,
        Player = options.Player or Players:GetPlayerFromCharacter(obj),
        PrimaryPart = options.PrimaryPart or obj.ClassName == "Model" and (obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")) or obj:IsA("BasePart") and obj,
        Components = {},
        IsEnabled = options.IsEnabled,
        Temporary = options.Temporary,
        ColorDynamic = options.ColorDynamic,
        RenderInNil = options.RenderInNil
    }, boxBase)

    if self:GetBox(obj) then
        self:GetBox(obj):Remove()
    end

    box.Components["Quad"] = Draw("Quad", {
        Thickness = self.Thickness,
        Color = box.Color,
        Transparency = 1,
        Filled = false,
        Visible = self.Enabled and self.Boxes
    })
    box.Components["Name"] = Draw("Text", {
		Text = box.Name,
		Color = box.Color,
		Center = true,
		Outline = true,
        Size = 19,
        Visible = self.Enabled and self.Names
	})
	box.Components["Distance"] = Draw("Text", {
		Color = box.Color,
		Center = true,
		Outline = true,
        Size = 19,
        Visible = self.Enabled and (self.Names or (ESP.UseDistance == false))
	})
	box.Components["Tracer"] = Draw("Line", {
		Thickness = ESP.Thickness,
		Color = box.Color,
        Transparency = 1,
        Visible = self.Enabled and self.Tracers
    })
    self.Objects[obj] = box
    
    obj.AncestryChanged:Connect(function(_, parent)
        if parent == nil and ESP.AutoRemove ~= false then
            box:Remove()
        end
    end)
    obj:GetPropertyChangedSignal("Parent"):Connect(function()
        if obj.Parent == nil and ESP.AutoRemove ~= false then
            box:Remove()
        end
    end)

    local hum = obj:FindFirstChildOfClass("Humanoid")
	if hum then
        hum.Died:Connect(function()
            if ESP.AutoRemove ~= false then
                box:Remove()
            end
		end)
    end

    return box
end

local function CharAdded(char)
    local p = Players:GetPlayerFromCharacter(char)
    if not char:FindFirstChild("HumanoidRootPart") then
        local ev
        ev = char.ChildAdded:Connect(function(c)
            if c.Name == "HumanoidRootPart" then
                ev:Disconnect()
                ESP:Add(char, {
		            Box = true,
                    Name = p.Name,
		            MaxDistance = function() return ESP.PlayerDistance end,
                    Player = p,
                    PrimaryPart = c,
                    ColorDynamic = function(Object : table)

                        local Player = Object.Player
                        local Char = Player.Character
        
                        if not Char then
                            return ESP.Color
                        end
        
                        local Hum = Char:FindFirstChildOfClass("Humanoid")
        
                        if Char and Hum then
							local Health = Hum.Health
							local MaxHealth = Hum.MaxHealth
							local Percent = Health / MaxHealth
		
							local r = 255 - (Percent * 255)
							local g = Percent * 255
							local b = 0
		
							if Health == 0 or Health > MaxHealth then
								r = 0
								g = 0
								b = 0
							end
		
							if Char:FindFirstChild("ForceField") then
								r = 0
								g = 255
								b = 255
							end
		
							return Color3.fromRGB(r, g, b)
						end
                    end
                })
            end
        end)
    else
        ESP:Add(char, {
	        Box = true,
            Name = p.Name,
	        MaxDistance = function() return ESP.PlayerDistance end,
            Player = p,
            PrimaryPart = char.HumanoidRootPart,
            ColorDynamic = function(Object : table)

                local Player = Object.Player
                local Char = Player.Character

                if not Char then
                    return ESP.Color
                end

                local Hum = Char:FindFirstChildOfClass("Humanoid")

                if Char and Hum then
                    local Health = Hum.Health
                    local MaxHealth = Hum.MaxHealth
                    local Percent = Health / MaxHealth

                    local r = 255 - (Percent * 255)
                    local g = Percent * 255
                    local b = 0

                    if Health == 0 or Health > MaxHealth then
                        r = 0
                        g = 0
                        b = 0
                    end

                    if Char:FindFirstChild("ForceField") then
                        r = 0
                        g = 255
                        b = 255
                    end

                    return Color3.fromRGB(r, g, b)
                end
            end
        })
    end
end

local function PlayerAdded(p)
    p.CharacterAdded:Connect(CharAdded)
    if p.Character then
        coroutine.wrap(CharAdded)(p.Character)
    end
end

Players.PlayerAdded:Connect(PlayerAdded)
for _,v in pairs(Players:GetPlayers()) do
    if v ~= LocalPlayer then
        PlayerAdded(v)
    end
end

RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera
    for i,v in (ESP.Enabled and pairs or ipairs)(ESP.Objects) do
        if v.Update then
            local s,e = pcall(v.Update, v)
            if not s then warn("[EU]", e, v.Object:GetFullName()) end
        end
    end
end)

local newnewVPF : ViewportFrame

-- UI Instances:
local UICore = Instance.new("ScreenGui", game.Players.LocalPlayer.PlayerGui)
UICore.Name = "AimlabsCore"
UICore.ResetOnSpawn = false
UICore.IgnoreGuiInset = true

local Container = Instance.new("Frame")
local Topbar = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local Left = Instance.new("Frame")
local Right = Instance.new("Frame")
local PartSelector = Instance.new("Frame")

do -- UI Configuration
	local ToggleContainer = Instance.new("Frame")
	local ToggleName = Instance.new("TextLabel")
	local Toggle = Instance.new("ImageButton")
	local Keybind = Instance.new("TextLabel")
	local AssignKeybind = Instance.new("ImageButton")
	local UIListLayout = Instance.new("UIListLayout")
	local ToggleContainer_2 = Instance.new("Frame")
	local ToggleName_2 = Instance.new("TextLabel")
	local Toggle_2 = Instance.new("ImageButton")
	local Keybind_2 = Instance.new("TextLabel")
	local AssignKeybind_2 = Instance.new("ImageButton")
	local ToggleContainer_3 = Instance.new("Frame")
	local ToggleName_3 = Instance.new("TextLabel")
	local Toggle_3 = Instance.new("ImageButton")
	local Keybind_3 = Instance.new("TextLabel")
	local AssignKeybind_3 = Instance.new("ImageButton")
	local Divider = Instance.new("Frame")
	local ToggleContainer_4 = Instance.new("Frame")
	local ToggleName_4 = Instance.new("TextLabel")
	local Toggle_4 = Instance.new("ImageButton")
	local Keybind_4 = Instance.new("TextLabel")
	local AssignKeybind_4 = Instance.new("ImageButton")
	local ToggleContainer_5 = Instance.new("Frame")
	local ToggleName_5 = Instance.new("TextLabel")
	local Toggle_5 = Instance.new("ImageButton")
	local Keybind_5 = Instance.new("TextLabel")
	local AssignKeybind_5 = Instance.new("ImageButton")
	local ToggleContainer_6 = Instance.new("Frame")
	local ToggleName_6 = Instance.new("TextLabel")
	local Toggle_6 = Instance.new("ImageButton")
	local Keybind_6 = Instance.new("TextLabel")
	local AssignKeybind_6 = Instance.new("ImageButton")
	local Divider_2 = Instance.new("Frame")
	local ToggleContainer_7 = Instance.new("Frame")
	local ToggleName_7 = Instance.new("TextLabel")
	local Toggle_7 = Instance.new("ImageButton")
	local ToggleContainer_8 = Instance.new("Frame")
	local ToggleName_8 = Instance.new("TextLabel")
	local Toggle_8 = Instance.new("ImageButton")
	local SliderContainer = Instance.new("Frame")
	local SliderName = Instance.new("TextLabel")
	local Hold = Instance.new("ImageButton")
	local Slider = Instance.new("Frame")
	local SliderValue = Instance.new("TextLabel")
	local UIListLayout_2 = Instance.new("UIListLayout")
	local SliderContainer_2 = Instance.new("Frame")
	local SliderName_2 = Instance.new("TextLabel")
	local Hold_2 = Instance.new("ImageButton")
	local Slider_2 = Instance.new("Frame")
	local SliderValue_2 = Instance.new("TextLabel")
	local ToggleContainer_9 = Instance.new("Frame")
	local ToggleName_9 = Instance.new("TextLabel")
	local Toggle_9 = Instance.new("ImageButton")
	local Keybind_7 = Instance.new("TextLabel")
	local AssignKeybind_7 = Instance.new("ImageButton")
	local Divider_3 = Instance.new("Frame")
	local Divider_4 = Instance.new("Frame")
	local SliderContainer_3 = Instance.new("Frame")
	local SliderName_3 = Instance.new("TextLabel")
	local Hold_3 = Instance.new("ImageButton")
	local Slider_3 = Instance.new("Frame")
	local SliderValue_3 = Instance.new("TextLabel")
	local ToggleContainer_10 = Instance.new("Frame")
	local ToggleName_10 = Instance.new("TextLabel")
	local Toggle_10 = Instance.new("ImageButton")

	--Properties:

	Container.Name = "Container"
	Container.Parent = UICore
	Container.BackgroundColor3 = Color3.fromRGB(29, 29, 29)
	Container.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Container.BorderSizePixel = 0
	Container.Position = UDim2.new(0.400000006, 0, 0.324999988, 0)
	Container.Size = UDim2.new(0.25, 0, 0.349999994, 0)

	Topbar.Name = "Topbar"
	Topbar.Parent = Container
	Topbar.BackgroundColor3 = Color3.fromRGB(49, 49, 49)
	Topbar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Topbar.BorderSizePixel = 0
	Topbar.Size = UDim2.new(1, 0, 0.0599999987, 0)
	Topbar.ZIndex = 2

	Title.Name = "Title"
	Title.Parent = Topbar
	Title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Title.BackgroundTransparency = 1.000
	Title.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Title.BorderSizePixel = 0
	Title.Position = UDim2.new(0.349999994, 0, 0, 0)
	Title.Size = UDim2.new(0.300000012, 0, 1, 0)
	Title.Font = Enum.Font.Gotham
	Title.Text = "Aimlabs v" .. Version
	Title.TextColor3 = Color3.fromRGB(213, 213, 213)
	Title.TextScaled = true
	Title.TextSize = 14.000
	Title.ZIndex = 2
	Title.TextWrapped = true

	Left.Name = "Left"
	Left.Parent = Container
	Left.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	Left.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Left.BorderSizePixel = 0
	Left.Position = UDim2.new(0.0149999857, 0, 0.0749999881, 0)
	Left.Size = UDim2.new(0.970000029, 0, 0.910000026, 0)

	Right.Name = "Right"
	Right.Parent = Container
	Right.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	Right.BackgroundTransparency = 1.000
	Right.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Right.BorderSizePixel = 0
	Right.Position = UDim2.new(0.0149999857, 0, 0.0749999881, 0)
	Right.Size = UDim2.new(0.970000029, 0, 0.910000026, 0)

	ToggleContainer.Name = "ToggleContainer"
	ToggleContainer.Parent = Left
	ToggleContainer.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer.BorderSizePixel = 0
	ToggleContainer.LayoutOrder = 1
	ToggleContainer.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName.Name = "ToggleName"
	ToggleName.Parent = ToggleContainer
	ToggleName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName.BackgroundTransparency = 1.000
	ToggleName.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName.BorderSizePixel = 0
	ToggleName.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName.Font = Enum.Font.Gotham
	ToggleName.Text = "Aimbot"
	ToggleName.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName.TextSize = 18.000
	ToggleName.TextWrapped = true
	ToggleName.TextXAlignment = Enum.TextXAlignment.Left

	Toggle.Name = "Toggle"
	Toggle.Parent = ToggleContainer
	Toggle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle.BackgroundTransparency = 1.000
	Toggle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle.BorderSizePixel = 0
	Toggle.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle.ImageTransparency = 1.000

	Keybind.Name = "Keybind"
	Keybind.Parent = ToggleContainer
	Keybind.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind.BackgroundTransparency = 0.900
	Keybind.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind.BorderSizePixel = 0
	Keybind.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind.Font = Enum.Font.Gotham
	Keybind.Text = "X"
	Keybind.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind.TextSize = 18.000
	Keybind.TextWrapped = true

	AssignKeybind.Name = "AssignKeybind"
	AssignKeybind.Parent = ToggleContainer
	AssignKeybind.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind.BackgroundTransparency = 1.000
	AssignKeybind.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind.BorderSizePixel = 0
	AssignKeybind.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind.ImageTransparency = 1.000

	UIListLayout.Parent = Left
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Padding = UDim.new(0, 5)

	ToggleContainer_2.Name = "ToggleContainer"
	ToggleContainer_2.Parent = Left
	ToggleContainer_2.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_2.BorderSizePixel = 0
	ToggleContainer_2.LayoutOrder = 4
	ToggleContainer_2.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_2.Name = "ToggleName"
	ToggleName_2.Parent = ToggleContainer_2
	ToggleName_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_2.BackgroundTransparency = 1.000
	ToggleName_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_2.BorderSizePixel = 0
	ToggleName_2.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_2.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_2.Font = Enum.Font.Gotham
	ToggleName_2.Text = "ESP"
	ToggleName_2.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_2.TextSize = 18.000
	ToggleName_2.TextWrapped = true
	ToggleName_2.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_2.Name = "Toggle"
	Toggle_2.Parent = ToggleContainer_2
	Toggle_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_2.BackgroundTransparency = 1.000
	Toggle_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_2.BorderSizePixel = 0
	Toggle_2.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_2.ImageTransparency = 1.000

	Keybind_2.Name = "Keybind"
	Keybind_2.Parent = ToggleContainer_2
	Keybind_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_2.BackgroundTransparency = 0.900
	Keybind_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_2.BorderSizePixel = 0
	Keybind_2.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_2.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_2.Font = Enum.Font.Gotham
	Keybind_2.Text = "..."
	Keybind_2.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_2.TextSize = 18.000
	Keybind_2.TextWrapped = true

	AssignKeybind_2.Name = "AssignKeybind"
	AssignKeybind_2.Parent = ToggleContainer_2
	AssignKeybind_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_2.BackgroundTransparency = 1.000
	AssignKeybind_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_2.BorderSizePixel = 0
	AssignKeybind_2.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_2.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_2.ImageTransparency = 1.000

	ToggleContainer_3.Name = "ToggleContainer"
	ToggleContainer_3.Parent = Left
	ToggleContainer_3.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_3.BorderSizePixel = 0
	ToggleContainer_3.LayoutOrder = 2
	ToggleContainer_3.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_3.Name = "ToggleName"
	ToggleName_3.Parent = ToggleContainer_3
	ToggleName_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_3.BackgroundTransparency = 1.000
	ToggleName_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_3.BorderSizePixel = 0
	ToggleName_3.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_3.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_3.Font = Enum.Font.Gotham
	ToggleName_3.Text = "Wallcheck"
	ToggleName_3.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_3.TextSize = 18.000
	ToggleName_3.TextWrapped = true
	ToggleName_3.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_3.Name = "Toggle"
	Toggle_3.Parent = ToggleContainer_3
	Toggle_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_3.BackgroundTransparency = 1.000
	Toggle_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_3.BorderSizePixel = 0
	Toggle_3.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_3.ImageTransparency = 1.000

	Keybind_3.Name = "Keybind"
	Keybind_3.Parent = ToggleContainer_3
	Keybind_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_3.BackgroundTransparency = 0.900
	Keybind_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_3.BorderSizePixel = 0
	Keybind_3.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_3.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_3.Font = Enum.Font.Gotham
	Keybind_3.Text = "..."
	Keybind_3.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_3.TextSize = 18.000
	Keybind_3.TextWrapped = true

	AssignKeybind_3.Name = "AssignKeybind"
	AssignKeybind_3.Parent = ToggleContainer_3
	AssignKeybind_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_3.BackgroundTransparency = 1.000
	AssignKeybind_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_3.BorderSizePixel = 0
	AssignKeybind_3.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_3.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_3.ImageTransparency = 1.000

	Divider.Name = "Divider"
	Divider.Parent = Left
	Divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Divider.BackgroundTransparency = 0.500
	Divider.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Divider.BorderSizePixel = 0
	Divider.LayoutOrder = 3
	Divider.Size = UDim2.new(0.5, 0, 0.00999999978, 0)

	ToggleContainer_4.Name = "ToggleContainer"
	ToggleContainer_4.Parent = Left
	ToggleContainer_4.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_4.BorderSizePixel = 0
	ToggleContainer_4.LayoutOrder = 4
	ToggleContainer_4.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_4.Name = "ToggleName"
	ToggleName_4.Parent = ToggleContainer_4
	ToggleName_4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_4.BackgroundTransparency = 1.000
	ToggleName_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_4.BorderSizePixel = 0
	ToggleName_4.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_4.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_4.Font = Enum.Font.Gotham
	ToggleName_4.Text = "Boxes"
	ToggleName_4.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_4.TextSize = 18.000
	ToggleName_4.TextWrapped = true
	ToggleName_4.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_4.Name = "Toggle"
	Toggle_4.Parent = ToggleContainer_4
	Toggle_4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_4.BackgroundTransparency = 1.000
	Toggle_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_4.BorderSizePixel = 0
	Toggle_4.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_4.ImageTransparency = 1.000

	Keybind_4.Name = "Keybind"
	Keybind_4.Parent = ToggleContainer_4
	Keybind_4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_4.BackgroundTransparency = 0.900
	Keybind_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_4.BorderSizePixel = 0
	Keybind_4.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_4.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_4.Font = Enum.Font.Gotham
	Keybind_4.Text = "..."
	Keybind_4.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_4.TextSize = 18.000
	Keybind_4.TextWrapped = true

	AssignKeybind_4.Name = "AssignKeybind"
	AssignKeybind_4.Parent = ToggleContainer_4
	AssignKeybind_4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_4.BackgroundTransparency = 1.000
	AssignKeybind_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_4.BorderSizePixel = 0
	AssignKeybind_4.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_4.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_4.ImageTransparency = 1.000

	ToggleContainer_5.Name = "ToggleContainer"
	ToggleContainer_5.Parent = Left
	ToggleContainer_5.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_5.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_5.BorderSizePixel = 0
	ToggleContainer_5.LayoutOrder = 5
	ToggleContainer_5.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_5.Name = "ToggleName"
	ToggleName_5.Parent = ToggleContainer_5
	ToggleName_5.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_5.BackgroundTransparency = 1.000
	ToggleName_5.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_5.BorderSizePixel = 0
	ToggleName_5.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_5.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_5.Font = Enum.Font.Gotham
	ToggleName_5.Text = "Names"
	ToggleName_5.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_5.TextSize = 18.000
	ToggleName_5.TextWrapped = true
	ToggleName_5.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_5.Name = "Toggle"
	Toggle_5.Parent = ToggleContainer_5
	Toggle_5.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_5.BackgroundTransparency = 1.000
	Toggle_5.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_5.BorderSizePixel = 0
	Toggle_5.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_5.ImageTransparency = 1.000

	Keybind_5.Name = "Keybind"
	Keybind_5.Parent = ToggleContainer_5
	Keybind_5.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_5.BackgroundTransparency = 0.900
	Keybind_5.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_5.BorderSizePixel = 0
	Keybind_5.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_5.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_5.Font = Enum.Font.Gotham
	Keybind_5.Text = "..."
	Keybind_5.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_5.TextSize = 18.000
	Keybind_5.TextWrapped = true

	AssignKeybind_5.Name = "AssignKeybind"
	AssignKeybind_5.Parent = ToggleContainer_5
	AssignKeybind_5.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_5.BackgroundTransparency = 1.000
	AssignKeybind_5.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_5.BorderSizePixel = 0
	AssignKeybind_5.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_5.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_5.ImageTransparency = 1.000

	ToggleContainer_6.Name = "ToggleContainer"
	ToggleContainer_6.Parent = Left
	ToggleContainer_6.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_6.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_6.BorderSizePixel = 0
	ToggleContainer_6.LayoutOrder = 6
	ToggleContainer_6.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_6.Name = "ToggleName"
	ToggleName_6.Parent = ToggleContainer_6
	ToggleName_6.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_6.BackgroundTransparency = 1.000
	ToggleName_6.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_6.BorderSizePixel = 0
	ToggleName_6.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_6.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_6.Font = Enum.Font.Gotham
	ToggleName_6.Text = "Tool"
	ToggleName_6.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_6.TextSize = 18.000
	ToggleName_6.TextWrapped = true
	ToggleName_6.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_6.Name = "Toggle"
	Toggle_6.Parent = ToggleContainer_6
	Toggle_6.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_6.BackgroundTransparency = 1.000
	Toggle_6.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_6.BorderSizePixel = 0
	Toggle_6.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_6.ImageTransparency = 1.000

	Keybind_6.Name = "Keybind"
	Keybind_6.Parent = ToggleContainer_6
	Keybind_6.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_6.BackgroundTransparency = 0.900
	Keybind_6.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_6.BorderSizePixel = 0
	Keybind_6.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_6.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_6.Font = Enum.Font.Gotham
	Keybind_6.Text = "..."
	Keybind_6.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_6.TextSize = 18.000
	Keybind_6.TextWrapped = true

	AssignKeybind_6.Name = "AssignKeybind"
	AssignKeybind_6.Parent = ToggleContainer_6
	AssignKeybind_6.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_6.BackgroundTransparency = 1.000
	AssignKeybind_6.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_6.BorderSizePixel = 0
	AssignKeybind_6.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_6.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_6.ImageTransparency = 1.000

	Divider_2.Name = "Divider"
	Divider_2.Parent = Left
	Divider_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Divider_2.BackgroundTransparency = 0.500
	Divider_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Divider_2.BorderSizePixel = 0
	Divider_2.LayoutOrder = 7
	Divider_2.Size = UDim2.new(0.5, 0, 0.00999999978, 0)

	ToggleContainer_7.Name = "ToggleContainer"
	ToggleContainer_7.Parent = Left
	ToggleContainer_7.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_7.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_7.BorderSizePixel = 0
	ToggleContainer_7.LayoutOrder = 7
	ToggleContainer_7.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_7.Name = "ToggleName"
	ToggleName_7.Parent = ToggleContainer_7
	ToggleName_7.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_7.BackgroundTransparency = 1.000
	ToggleName_7.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_7.BorderSizePixel = 0
	ToggleName_7.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_7.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_7.Font = Enum.Font.Gotham
	ToggleName_7.Text = "Prediction"
	ToggleName_7.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_7.TextSize = 18.000
	ToggleName_7.TextWrapped = true
	ToggleName_7.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_7.Name = "Toggle"
	Toggle_7.Parent = ToggleContainer_7
	Toggle_7.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_7.BackgroundTransparency = 1.000
	Toggle_7.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_7.BorderSizePixel = 0
	Toggle_7.Size = UDim2.new(1, 0, 1, 0)
	Toggle_7.ImageTransparency = 1.000

	ToggleContainer_8.Name = "ToggleContainer"
	ToggleContainer_8.Parent = Left
	ToggleContainer_8.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_8.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_8.BorderSizePixel = 0
	ToggleContainer_8.LayoutOrder = 8
	ToggleContainer_8.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_8.Name = "ToggleName"
	ToggleName_8.Parent = ToggleContainer_8
	ToggleName_8.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_8.BackgroundTransparency = 1.000
	ToggleName_8.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_8.BorderSizePixel = 0
	ToggleName_8.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_8.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_8.Font = Enum.Font.Gotham
	ToggleName_8.Text = "V-Resolver"
	ToggleName_8.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_8.TextSize = 18.000
	ToggleName_8.TextWrapped = true
	ToggleName_8.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_8.Name = "Toggle"
	Toggle_8.Parent = ToggleContainer_8
	Toggle_8.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_8.BackgroundTransparency = 1.000
	Toggle_8.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_8.BorderSizePixel = 0
	Toggle_8.Size = UDim2.new(1, 0, 1, 0)
	Toggle_8.ImageTransparency = 1.000

	SliderContainer.Name = "SliderContainer"
	SliderContainer.Parent = Right
	SliderContainer.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	SliderContainer.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderContainer.BorderSizePixel = 0
	SliderContainer.LayoutOrder = 1
	SliderContainer.Position = UDim2.new(0.5, 0, 0, 0)
	SliderContainer.Size = UDim2.new(0.5, 0, 0.200000003, 5)

	SliderName.Name = "SliderName"
	SliderName.Parent = SliderContainer
	SliderName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderName.BackgroundTransparency = 1.000
	SliderName.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderName.BorderSizePixel = 0
	SliderName.Position = UDim2.new(0.0500000119, 0, 0, 0)
	SliderName.Size = UDim2.new(0.899999976, 0, 0.5, 0)
	SliderName.Font = Enum.Font.Gotham
	SliderName.Text = "Aimbot FOV"
	SliderName.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderName.TextSize = 18.000
	SliderName.TextWrapped = true

	Hold.Name = "Hold"
	Hold.Parent = SliderContainer
	Hold.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Hold.BackgroundTransparency = 1.000
	Hold.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Hold.BorderSizePixel = 0
	Hold.Size = UDim2.new(1, 0, 1, 0)
	Hold.ImageTransparency = 1.000

	Slider.Name = "Slider"
	Slider.Parent = SliderContainer
	Slider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Slider.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Slider.BorderSizePixel = 0
	Slider.Position = UDim2.new(0, 0, 0.469999999, 0)
	Slider.Size = UDim2.new(1, 0, 0.150000006, 0)

	SliderValue.Name = "SliderValue"
	SliderValue.Parent = SliderContainer
	SliderValue.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderValue.BackgroundTransparency = 1.000
	SliderValue.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderValue.BorderSizePixel = 0
	SliderValue.Position = UDim2.new(0.0500000119, 0, 0.649999976, 0)
	SliderValue.Size = UDim2.new(0.899999976, 0, 0.300000012, 0)
	SliderValue.Font = Enum.Font.Gotham
	SliderValue.Text = "60"
	SliderValue.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderValue.TextSize = 15.000
	SliderValue.TextWrapped = true

	UIListLayout_2.Parent = Right
	UIListLayout_2.HorizontalAlignment = Enum.HorizontalAlignment.Right
	UIListLayout_2.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout_2.Padding = UDim.new(0, 5)

	SliderContainer_2.Name = "SliderContainer"
	SliderContainer_2.Parent = Right
	SliderContainer_2.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	SliderContainer_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderContainer_2.BorderSizePixel = 0
	SliderContainer_2.LayoutOrder = 3
	SliderContainer_2.Position = UDim2.new(0.5, 0, 0, 0)
	SliderContainer_2.Size = UDim2.new(0.5, 0, 0.200000003, 5)

	SliderName_2.Name = "SliderName"
	SliderName_2.Parent = SliderContainer_2
	SliderName_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderName_2.BackgroundTransparency = 1.000
	SliderName_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderName_2.BorderSizePixel = 0
	SliderName_2.Position = UDim2.new(0.0500000119, 0, 0, 0)
	SliderName_2.Size = UDim2.new(0.899999976, 0, 0.5, 0)
	SliderName_2.Font = Enum.Font.Gotham
	SliderName_2.Text = "ESP Distance"
	SliderName_2.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderName_2.TextSize = 18.000
	SliderName_2.TextWrapped = true

	Hold_2.Name = "Hold"
	Hold_2.Parent = SliderContainer_2
	Hold_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Hold_2.BackgroundTransparency = 1.000
	Hold_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Hold_2.BorderSizePixel = 0
	Hold_2.Size = UDim2.new(1, 0, 1, 0)
	Hold_2.ImageTransparency = 1.000

	Slider_2.Name = "Slider"
	Slider_2.Parent = SliderContainer_2
	Slider_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Slider_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Slider_2.BorderSizePixel = 0
	Slider_2.Position = UDim2.new(0, 0, 0.469999999, 0)
	Slider_2.Size = UDim2.new(1, 0, 0.150000006, 0)

	SliderValue_2.Name = "SliderValue"
	SliderValue_2.Parent = SliderContainer_2
	SliderValue_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderValue_2.BackgroundTransparency = 1.000
	SliderValue_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderValue_2.BorderSizePixel = 0
	SliderValue_2.Position = UDim2.new(0.0500000119, 0, 0.649999976, 0)
	SliderValue_2.Size = UDim2.new(0.899999976, 0, 0.300000012, 0)
	SliderValue_2.Font = Enum.Font.Gotham
	SliderValue_2.Text = "3000"
	SliderValue_2.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderValue_2.TextSize = 15.000
	SliderValue_2.TextWrapped = true

	ToggleContainer_9.Name = "ToggleContainer"
	ToggleContainer_9.Parent = Right
	ToggleContainer_9.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_9.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_9.BorderSizePixel = 0
	ToggleContainer_9.LayoutOrder = 4
	ToggleContainer_9.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_9.Name = "ToggleName"
	ToggleName_9.Parent = ToggleContainer_9
	ToggleName_9.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_9.BackgroundTransparency = 1.000
	ToggleName_9.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_9.BorderSizePixel = 0
	ToggleName_9.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_9.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_9.Font = Enum.Font.Gotham
	ToggleName_9.Text = "Teamcheck"
	ToggleName_9.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_9.TextSize = 18.000
	ToggleName_9.TextWrapped = true
	ToggleName_9.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_9.Name = "Toggle"
	Toggle_9.Parent = ToggleContainer_9
	Toggle_9.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_9.BackgroundTransparency = 1.000
	Toggle_9.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_9.BorderSizePixel = 0
	Toggle_9.Size = UDim2.new(0.699999988, 0, 1, 0)
	Toggle_9.ImageTransparency = 1.000

	Keybind_7.Name = "Keybind"
	Keybind_7.Parent = ToggleContainer_9
	Keybind_7.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Keybind_7.BackgroundTransparency = 0.900
	Keybind_7.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Keybind_7.BorderSizePixel = 0
	Keybind_7.Position = UDim2.new(0.699999988, 0, 0, 0)
	Keybind_7.Size = UDim2.new(0.300000012, 0, 1, 0)
	Keybind_7.Font = Enum.Font.Gotham
	Keybind_7.Text = "..."
	Keybind_7.TextColor3 = Color3.fromRGB(197, 197, 197)
	Keybind_7.TextSize = 18.000
	Keybind_7.TextWrapped = true

	AssignKeybind_7.Name = "AssignKeybind"
	AssignKeybind_7.Parent = ToggleContainer_9
	AssignKeybind_7.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AssignKeybind_7.BackgroundTransparency = 1.000
	AssignKeybind_7.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AssignKeybind_7.BorderSizePixel = 0
	AssignKeybind_7.Position = UDim2.new(0.699999988, 0, 0, 0)
	AssignKeybind_7.Size = UDim2.new(0.300000012, 0, 1, 0)
	AssignKeybind_7.ImageTransparency = 1.000

	Divider_3.Name = "Divider"
	Divider_3.Parent = Right
	Divider_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Divider_3.BackgroundTransparency = 0.500
	Divider_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Divider_3.BorderSizePixel = 0
	Divider_3.LayoutOrder = 2
	Divider_3.Size = UDim2.new(0.5, 0, 0.00999999978, 0)

	Divider_4.Name = "Divider"
	Divider_4.Parent = Right
	Divider_4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Divider_4.BackgroundTransparency = 0.500
	Divider_4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Divider_4.BorderSizePixel = 0
	Divider_4.LayoutOrder = 6
	Divider_4.Size = UDim2.new(0.5, 0, 0.00999999978, 0)

	SliderContainer_3.Name = "SliderContainer"
	SliderContainer_3.Parent = Right
	SliderContainer_3.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	SliderContainer_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderContainer_3.BorderSizePixel = 0
	SliderContainer_3.LayoutOrder = 7
	SliderContainer_3.Position = UDim2.new(0.5, 0, 0, 0)
	SliderContainer_3.Size = UDim2.new(0.5, 0, 0.200000003, 5)

	SliderName_3.Name = "SliderName"
	SliderName_3.Parent = SliderContainer_3
	SliderName_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderName_3.BackgroundTransparency = 1.000
	SliderName_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderName_3.BorderSizePixel = 0
	SliderName_3.Position = UDim2.new(0.0500000119, 0, 0, 0)
	SliderName_3.Size = UDim2.new(0.899999976, 0, 0.5, 0)
	SliderName_3.Font = Enum.Font.Gotham
	SliderName_3.Text = "Coefficient"
	SliderName_3.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderName_3.TextSize = 18.000
	SliderName_3.TextWrapped = true

	Hold_3.Name = "Hold"
	Hold_3.Parent = SliderContainer_3
	Hold_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Hold_3.BackgroundTransparency = 1.000
	Hold_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Hold_3.BorderSizePixel = 0
	Hold_3.Size = UDim2.new(1, 0, 1, 0)
	Hold_3.ImageTransparency = 1.000

	Slider_3.Name = "Slider"
	Slider_3.Parent = SliderContainer_3
	Slider_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Slider_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Slider_3.BorderSizePixel = 0
	Slider_3.Position = UDim2.new(0, 0, 0.469999999, 0)
	Slider_3.Size = UDim2.new(1, 0, 0.150000006, 0)

	SliderValue_3.Name = "SliderValue"
	SliderValue_3.Parent = SliderContainer_3
	SliderValue_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SliderValue_3.BackgroundTransparency = 1.000
	SliderValue_3.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SliderValue_3.BorderSizePixel = 0
	SliderValue_3.Position = UDim2.new(0.0500000119, 0, 0.649999976, 0)
	SliderValue_3.Size = UDim2.new(0.899999976, 0, 0.300000012, 0)
	SliderValue_3.Font = Enum.Font.Gotham
	SliderValue_3.Text = "60"
	SliderValue_3.TextColor3 = Color3.fromRGB(197, 197, 197)
	SliderValue_3.TextSize = 15.000
	SliderValue_3.TextWrapped = true

	ToggleContainer_10.Name = "ToggleContainer"
	ToggleContainer_10.Parent = Right
	ToggleContainer_10.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ToggleContainer_10.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleContainer_10.BorderSizePixel = 0
	ToggleContainer_10.LayoutOrder = 5
	ToggleContainer_10.Size = UDim2.new(0.5, 0, 0.100000001, 0)

	ToggleName_10.Name = "ToggleName"
	ToggleName_10.Parent = ToggleContainer_10
	ToggleName_10.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ToggleName_10.BackgroundTransparency = 1.000
	ToggleName_10.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ToggleName_10.BorderSizePixel = 0
	ToggleName_10.Position = UDim2.new(0.0500000119, 0, 0, 0)
	ToggleName_10.Size = UDim2.new(0.899999976, 0, 1, 0)
	ToggleName_10.Font = Enum.Font.Gotham
	ToggleName_10.Text = "Show FOV"
	ToggleName_10.TextColor3 = Color3.fromRGB(197, 197, 197)
	ToggleName_10.TextSize = 18.000
	ToggleName_10.TextWrapped = true
	ToggleName_10.TextXAlignment = Enum.TextXAlignment.Left

	Toggle_10.Name = "Toggle"
	Toggle_10.Parent = ToggleContainer_10
	Toggle_10.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Toggle_10.BackgroundTransparency = 1.000
	Toggle_10.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Toggle_10.BorderSizePixel = 0
	Toggle_10.Size = UDim2.new(1, 0, 1, 0)
	Toggle_10.ImageTransparency = 1.000

	-- Scripts:

	local function KKJRVF_fake_script() -- Container.DragScript 
		local script = Instance.new('LocalScript', Container)

		local UIS = game:GetService('UserInputService')
		local frame = script.Parent
		local dragToggle = nil
		local dragSpeed = 0.05
		local dragStart = nil
		local startPos = nil

		local function updateInput(input)
			local delta = input.Position - dragStart
			local position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			game:GetService('TweenService'):Create(PartSelector, TweenInfo.new(dragSpeed), {Position = position + UDim2.new(0, Container.AbsoluteSize.X, 0, 0)}):Play()
			game:GetService('TweenService'):Create(frame, TweenInfo.new(dragSpeed), {Position = position}):Play()
		end

		frame.InputBegan:Connect(function(input)
			if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then 
				dragToggle = true
				dragStart = input.Position
				startPos = frame.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragToggle = false
					end
				end)
			end
		end)

		UIS.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				if dragToggle then
					updateInput(input)
				end
			end
		end)
	end
	coroutine.wrap(KKJRVF_fake_script)()
end

local Head = Instance.new("TextButton")
local Torso = Instance.new("TextButton")
local RightArm = Instance.new("TextButton")
local LeftArm = Instance.new("TextButton")
local LeftLeg = Instance.new("TextButton")
local RightLeg = Instance.new("TextButton")

local UIAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
UIAspectRatioConstraint.AspectRatio = 0.8
UIAspectRatioConstraint.Parent = PartSelector
local uiar2 = UIAspectRatioConstraint:Clone()
uiar2.AspectRatio = 1
uiar2.Parent = Container

do
	local UICorner = Instance.new("UICorner")
	local UICorner_2 = Instance.new("UICorner")
	local UICorner_3 = Instance.new("UICorner")
	local UICorner_4 = Instance.new("UICorner")
	local UICorner_5 = Instance.new("UICorner")
	local UICorner_6 = Instance.new("UICorner")
	local ImageLabel = Instance.new("ImageLabel")

	--Properties:

	PartSelector.Name = "PartSelector"
	PartSelector.Parent = UICore
	PartSelector.BackgroundColor3 = Color3.fromRGB(29, 29, 29)
	PartSelector.BorderColor3 = Color3.fromRGB(0, 0, 0)
	PartSelector.BorderSizePixel = 0
	PartSelector.Position = UDim2.new(0.343609035, 0, 0.34324038, 0)
	PartSelector.Size = UDim2.new(0.200000003, 0, 0.349999994, 0)

	Head.Name = "Head"
	Head.Parent = PartSelector
	Head.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	Head.BackgroundTransparency = 0.900
	Head.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Head.BorderSizePixel = 0
	Head.Position = UDim2.new(0.377771765, 0, 0.0891948789, 0)
	Head.Size = UDim2.new(0.240584821, 0, 0.197635785, 0)
	Head.Text = ""
	Head.ZIndex = 2

	UICorner.Parent = Head

	Torso.Name = "HumanoidRootPart"
	Torso.Parent = PartSelector
	Torso.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	Torso.BackgroundTransparency = 0.900
	Torso.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Torso.BorderSizePixel = 0
	Torso.Position = UDim2.new(0.283708751, 0, 0.286831021, 0)
	Torso.Size = UDim2.new(0.428711325, 0, 0.350287288, 0)
	Torso.Text = ""
	Torso.ZIndex = 2

	UICorner_2.CornerRadius = UDim.new(0, 5)
	UICorner_2.Parent = Torso

	RightArm.Name = "Right Arm"
	RightArm.Parent = PartSelector
	RightArm.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	RightArm.BackgroundTransparency = 0.900
	RightArm.BorderColor3 = Color3.fromRGB(0, 0, 0)
	RightArm.BorderSizePixel = 0
	RightArm.Position = UDim2.new(0.710610807, 0, 0.286831021, 0)
	RightArm.Size = UDim2.new(0.218878075, 0, 0.350287288, 0)
	RightArm.Text = ""
	RightArm.ZIndex = 2

	UICorner_3.CornerRadius = UDim.new(0, 5)
	UICorner_3.Parent = RightArm

	LeftArm.Name = "Left Arm"
	LeftArm.Parent = PartSelector
	LeftArm.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	LeftArm.BackgroundTransparency = 0.900
	LeftArm.BorderColor3 = Color3.fromRGB(0, 0, 0)
	LeftArm.BorderSizePixel = 0
	LeftArm.Position = UDim2.new(0.0640492514, 0, 0.286831021, 0)
	LeftArm.Size = UDim2.new(0.218877733, 0, 0.350287288, 0)
	LeftArm.Text = ""
	LeftArm.ZIndex = 2

	UICorner_4.CornerRadius = UDim.new(0, 5)
	UICorner_4.Parent = LeftArm

	LeftLeg.Name = "Left Leg"
	LeftLeg.Parent = PartSelector
	LeftLeg.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	LeftLeg.BackgroundTransparency = 0.900
	LeftLeg.BorderColor3 = Color3.fromRGB(0, 0, 0)
	LeftLeg.BorderSizePixel = 0
	LeftLeg.Position = UDim2.new(0.283708066, 0, 0.634905636, 0)
	LeftLeg.Size = UDim2.new(0.218877777, 0, 0.350287378, 0)
	LeftLeg.Text = ""
	LeftLeg.ZIndex = 2

	UICorner_5.CornerRadius = UDim.new(0, 5)
	UICorner_5.Parent = LeftLeg

	RightLeg.Name = "Right Leg"
	RightLeg.Parent = PartSelector
	RightLeg.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	RightLeg.BackgroundTransparency = 0.900
	RightLeg.BorderColor3 = Color3.fromRGB(0, 0, 0)
	RightLeg.BorderSizePixel = 0
	RightLeg.Position = UDim2.new(0.493541986, 0, 0.634905636, 0)
	RightLeg.Size = UDim2.new(0.218877956, 0, 0.350287378, 0)
	RightLeg.Text = ""
	RightLeg.ZIndex = 2

	UICorner_6.CornerRadius = UDim.new(0, 5)
	UICorner_6.Parent = RightLeg

	ImageLabel.Parent = PartSelector
	ImageLabel.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
	ImageLabel.BackgroundTransparency = 1.000
	ImageLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ImageLabel.BorderSizePixel = 0
	ImageLabel.Position = UDim2.new(0.0640487894, 0, 0.00919681229, 0)
	ImageLabel.Size = UDim2.new(0.865439773, 0, 0.966248333, 0)
	ImageLabel.ZIndex = 1
	ImageLabel.Image = "rbxassetid://14525223042"
	ImageLabel.ImageTransparency = 0

	if SMode then
		ImageLabel:Destroy()
		pcall(function()
			newnewVPF = game:GetObjects("rbxassetid://14526593683")[1].PartSelector_.ViewportFrame
		end)
		if not newnewVPF then
			pcall(function()
				local InsertService = game:GetService("InsertService")
				newnewVPF = InsertService:LoadAsset(14526593683).PartSelector_.ViewportFrame
			end)
		end
		if not newnewVPF then
			newnewVPF = game.ReplicatedStorage:FindFirstChild("J_DC").PartSelector_.ViewportFrame
		end
		newnewVPF.Parent = PartSelector
	end
end -- PartSelector Setup

PartSelector.Position = Container.Position + UDim2.new(0, Container.AbsoluteSize.X, 0, 0)

local UIHandler = {
	Flags = {},
	FlagConnections = {},
	KeybindConnections = {},
	Overrides = {
		['Aimbot'] = true,
        ['Aimbot FOV'] = {30, 60, 220},
        ['ESP Distance'] = {100, 500, 2000},
        ['Coefficient'] = {5, 35, 70},
		['Head'] = true,
		['Show FOV'] = true,
		['Boxes'] = true,
		['Names'] = false
	},
	SelectedParts = {
		['Head'] = true
	}
}

function UIHandler:SetupToggle(Toggle : Frame)
	local Background = Toggle
	local Flag = Toggle:FindFirstChild('Flag')
	local ToggleButton = Toggle:FindFirstChild('Toggle')
	local KeybindButton = Toggle:FindFirstChild('AssignKeybind')
	local KeybindText = Toggle:FindFirstChild('Keybind')
	local BoolValue = Toggle:FindFirstChild('Value')

	if not BoolValue then
		BoolValue = Instance.new("BoolValue", Toggle)
	end
	
	if not Flag then
		Flag = Instance.new("StringValue", Toggle)
		Flag.Value = Toggle.ToggleName.Text
	end

	self.FlagConnections[Flag.Value] = Instance.new("BindableEvent")

	local Keybind

	ToggleButton.MouseButton1Click:Connect(function()
		BoolValue.Value = not BoolValue.Value
	end)

	if KeybindButton then

		if KeybindText.Text ~= "..." then
			Keybind = Enum.KeyCode[KeybindText.Text]
		end

		KeybindButton.MouseButton1Click:Connect(function()
			KeybindText.Text = 'Press'
			local Connection
			Connection = game:GetService('UserInputService').InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.Keyboard then
					KeybindText.Text = Input.KeyCode.Name
					Keybind = Input.KeyCode
					Connection:Disconnect()
				end
			end)
		end)

		local InputConnection; InputConnection = UserInputService.InputEnded:Connect(function(Input)
			if UserInputService:GetFocusedTextBox() then return end

			if Input.KeyCode == Keybind then
				BoolValue.Value = not BoolValue.Value
			end
		end)

		table.insert(self.KeybindConnections, InputConnection)
	end

	BoolValue.Changed:Connect(function(Value : boolean)
		self.Flags[Flag.Value] = Value
		self.FlagConnections[Flag.Value]:Fire(Value)
		if Value then
			Background.BackgroundColor3 = Color3.fromRGB(93, 93, 93)
		else
			Background.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
		end
	end)

	if self.Overrides[Flag.Value] then
		BoolValue.Value = self.Overrides[Flag.Value]
	end

	return BoolValue
end

function UIHandler:SetupSlider(Slider : Frame)
	local Flag = Slider:FindFirstChild('Flag')
	local SliderButton = Slider:FindFirstChild('Hold')
	local SliderText = Slider:FindFirstChild('SliderValue')
	local NumberValue = Slider:FindFirstChild('Value')
    local SliderFrame = Slider:FindFirstChild('Slider')

	if not NumberValue then
		NumberValue = Instance.new("NumberValue", Slider)
	end
	
	if not Flag then
		Flag = Instance.new("StringValue", Slider)
		Flag.Value = Slider.SliderName.Text
	end

    local Max = self.Overrides[Flag.Value][3]
    local Min = self.Overrides[Flag.Value][1]

    if self.Overrides[Flag.Value] then
        SliderText.Text = tostring(self.Overrides[Flag.Value][2])
        NumberValue.Value = self.Overrides[Flag.Value][2]
        SliderFrame.Size = UDim2.new((self.Overrides[Flag.Value][2] - Min) / (Max - Min), 0, 0.150000006, 0)
		self.Flags[Flag.Value] = self.Overrides[Flag.Value][2]
    end

	local MouseDown = false

	UserInputService.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and UICore.Enabled then
			if SliderButton.AbsolutePosition.X <= Input.Position.X and SliderButton.AbsolutePosition.X + SliderButton.AbsoluteSize.X >= Input.Position.X and SliderButton.AbsolutePosition.Y <= Input.Position.Y and SliderButton.AbsolutePosition.Y + SliderButton.AbsoluteSize.Y >= Input.Position.Y then
				MouseDown = true
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(Input)
		if MouseDown and Input.UserInputType == Enum.UserInputType.MouseMovement and UICore.Enabled then
			local MousePosition = UserInputService:GetMouseLocation()
			local SliderRatio = (MousePosition.X - SliderButton.AbsolutePosition.X) / SliderButton.AbsoluteSize.X
			SliderRatio = math.clamp(SliderRatio, 0, 1)
			local Value = math.floor((SliderRatio * (Max - Min)) + Min)
			SliderText.Text = tostring(Value)
			NumberValue.Value = Value
			self.Flags[Flag.Value] = Value
			SliderFrame.Size = UDim2.new(SliderRatio, 0, 0.150000006, 0)
		end
	end)

	UserInputService.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			MouseDown = false
		end
	end)
end

function UIHandler:SetupLimb(LimbIcon : TextButton)
	local Toggled = false
	
	LimbIcon.Activated:Connect(function()
		Toggled = not Toggled
		if Toggled then
			LimbIcon.BackgroundColor3 = Color3.fromRGB(255, 123, 123)
			LimbIcon.BackgroundTransparency = 0.6
			TweenService:Create(LimbIcon, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 0.9}):Play()
			self.SelectedParts[LimbIcon.Name] = true
		else
			LimbIcon.BackgroundColor3 = Color3.fromRGB(61, 61, 61)
			LimbIcon.BackgroundTransparency = 0.9
			self.SelectedParts[LimbIcon.Name] = nil
		end
	end)

	if self.Overrides[LimbIcon.Name] then
		LimbIcon.BackgroundColor3 = Color3.fromRGB(255, 123, 123)
		LimbIcon.BackgroundTransparency = 0.6
		TweenService:Create(LimbIcon, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 0.9}):Play()
		self.SelectedParts[LimbIcon.Name] = true
		Toggled = true
	end
end

for _, Toggle in next, Left:GetChildren() do
	if Toggle.Name == "ToggleContainer" then
		UIHandler:SetupToggle(Toggle)
	end
end

for _, Toggle in next, Right:GetChildren() do
	if Toggle.Name == "ToggleContainer" then
		UIHandler:SetupToggle(Toggle)
	end
end

for _, Slider in next, Right:GetChildren() do
    if Slider.Name == "SliderContainer" then
        UIHandler:SetupSlider(Slider)
    end
end

for _, Slider in next, Left:GetChildren() do
    if Slider.Name == "SliderContainer" then
        UIHandler:SetupSlider(Slider)
    end
end

for _, Limb in next, PartSelector:GetChildren() do
	if Limb:IsA("TextButton") then
		UIHandler:SetupLimb(Limb)
	end
end

if SMode then

	if not game:IsLoaded() then
		repeat wait() until game:IsLoaded()
	end

	local TweenService = game:GetService("TweenService")
	pcall(function()
		newnewVPF.CurrentCamera = newnewVPF:FindFirstChildOfClass("Camera")
		newnewVPF:FindFirstChildOfClass("Camera").FieldOfView = 10
		TweenService:Create(newnewVPF:FindFirstChildOfClass("Camera"), TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {FieldOfView = 1}):Play()
	end)
	TweenService:Create(
		newnewVPF,
		TweenInfo.new(7.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			Ambient = Color3.fromRGB(138, 104, 144),
			LightColor = Color3.fromRGB(255, 173, 165),
			LightDirection = Vector3.new(10, -10, 10),
			BackgroundColor3 = Color3.fromRGB(21, 21, 21),
			BackgroundTransparency = 1
		}
	):Play()

	for i,v in next, newnewVPF:GetDescendants() do
		if v:IsA("BasePart") and v.Material == Enum.Material.Fabric then
			v.Material = Enum.Material.Sand
		end
	end

	task.spawn(function()

		wait(7.5)

		while wait(1) do
			local LocalPlayer = game.Players.LocalPlayer
			local Character = LocalPlayer.Character
			if not Character then return end

			local Humanoid = Character:FindFirstChildOfClass("Humanoid")
			if not Humanoid then return end

			local Health = Humanoid.Health
			local MaxHealth = Humanoid.MaxHealth
			local Percent = Health / MaxHealth

			local r1 = Percent * 138
			local g1 = Percent * 104
			local b1 = Percent * 144

			local r2 = Percent * 255
			local g2 = Percent * 173
			local b2 = Percent * 165

			TweenService:Create(
				newnewVPF,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Ambient = Color3.fromRGB(r1, g1, b1),
					LightColor = Color3.fromRGB(r2, g2, b2)
				}
			):Play()
		end
	end)

	-- 	if v.Name == "F48F0352-10C6-4C51-9C47-0EA6CBB432A5" then
	-- 		local Weld = Instance.new("WeldConstraint", v)
	-- 		Weld.Part0 = v
	-- 		Weld.Part1 = newnewVPF["70A9E640-D36F-407D-853B-E4B1B8A42B34"]["E7F7851D-F7BF-4B50-AE02-CD4063840133"]
	-- 	end
	-- end

	-- for _,v in next, newnewVPF:GetDescendants() do
	-- 	if v:IsA("BasePart") then
	-- 		if v.Name ~= "HumanoidRootPart" then
	-- 			v.Anchored = false
	-- 		end
	-- 	end
	-- end

	-- animation fail

	local funny = newnewVPF["70A9E640-D36F-407D-853B-E4B1B8A42B34"]["0D120218-883B-4A4F-B289-882F02942493"]["716BA43A-E117-417B-A24D-AFA2BEBB9F46"]["2BBAD499-27B2-46B4-B32B-5B0C6F014763"]

	UserInputService.InputBegan:Connect(function(Input)
		if Input.KeyCode == Enum.KeyCode.NumLock then
			if funny.Transparency ~= 1 then
				TweenService:Create(funny, TweenInfo.new(0.05), {Transparency = 1}):Play()
			else
				TweenService:Create(funny, TweenInfo.new(0.05), {Transparency = 0}):Play()
			end
		end
	end)
end

-- oh my god finally done the ui
-- ok now ui connections

if not StudioTestMode then

	ESP.TeamMates = true
	ESP:Toggle(false)
	ESP.Boxes = true
	ESP.Names = false

	UIHandler.FlagConnections["Teamcheck"].Event:Connect(function(Value : boolean)
		Aiming.Settings.Ignored.IgnoreLocalTeam = Value
		ESP.TeamMates = (not Value)
	end)
	
	RunService.RenderStepped:Connect(function()
		Aiming.Settings.FOVSettings.Scale = UIHandler.Flags["Aimbot FOV"]

		local SelectedParts = {}

		ESP.PlayerDistance = UIHandler.Flags["ESP Distance"]

		for Part, Selected in next, UIHandler.SelectedParts do

			if Part == "HumanoidRootPart" and Selected then
				table.insert(SelectedParts, "Torso")
				table.insert(SelectedParts, "UpperTorso")
				table.insert(SelectedParts, "LowerTorso")
			end

			if Selected then
				table.insert(SelectedParts, Part)
			end
		end

		Aiming.Settings.TargetPart = SelectedParts
	end)
	
	UIHandler.FlagConnections["Boxes"].Event:Connect(function(Value : boolean)
		ESP.Boxes = Value
	end)

	UIHandler.FlagConnections["Tool"].Event:Connect(function(Value : boolean)
		ESP.UseDistance = not Value
	end)

	UIHandler.FlagConnections["Names"].Event:Connect(function(Value : boolean)
		ESP.Names = Value
	end)

	UIHandler.FlagConnections["ESP"].Event:Connect(function(Value : boolean)
		ESP:Toggle(Value)
	end)

	UIHandler.FlagConnections["Wallcheck"].Event:Connect(function(Value : boolean)
		Aiming.Settings.VisibleCheck = Value
	end)

	UIHandler.FlagConnections["Show FOV"].Event:Connect(function(Value : boolean)
		Aiming.Settings.FOVSettings.Visible = Value
	end)
	
	UIHandler.FlagConnections["Aimbot"].Event:Connect(function(Value : boolean)
		Aiming.Settings.Enabled = Value
	end)

	-- ok now the actual aimbot

	local MouseDown = false

	UserInputService.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton2 then
			MouseDown = true
		end
	end)

	UserInputService.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton2 then
			MouseDown = false
		end
	end)

	local LockEngaged = nil

	RunService.RenderStepped:Connect(function()

		if not game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Head") then return end

		if (Camera.CFrame.Position - game.Players.LocalPlayer.Character.Head.Position).Magnitude > 1 then return end

		if (AimingChecks.IsAvailable()) or (LockEngaged and LockEngaged.Parent:FindFirstChildOfClass("Humanoid") and LockEngaged.Parent:FindFirstChildOfClass("Humanoid").Health > 0) then
			if MouseDown then

				local AimPart = LockEngaged or AimingSelected.Part

				if not LockEngaged then
					LockEngaged = AimingSelected.Part
				end

				if UIHandler.Flags["Prediction"] then
					Camera.CFrame = CFrame.new(Camera.CFrame.Position, (AimPart.Position + (AimPart.Velocity / UIHandler.Flags["Coefficient"])))
				else
					Camera.CFrame = CFrame.new(Camera.CFrame.Position, AimPart.Position)
				end
			else
				LockEngaged = nil
			end
		end
	end)
end

UserInputService.InputBegan:Connect(function(Input)
	if Input.KeyCode == Enum.KeyCode.Insert then
		UICore.Enabled = not UICore.Enabled
	end
end)
