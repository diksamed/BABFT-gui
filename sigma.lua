--[[
Flat UI Library (MacLib Structure, Linoria-inspired Flat Design)
Version: 2.0.0 (Based on MacLib structure)
Design: Flat, Sharp Edges, No Rounded Corners
Features: Windows, Tabs, Buttons, Labels, Sliders, Checkboxes, Dropdowns, TextInputs, Keybinds, ColorPicker, Config Saving/Loading, Notifications, Dialogs
Loadstring Compatible
--]]

local MacLib = {
	Options = {},    -- Stores flagged element instances for config saving/loading
	Folder = "MacLib_Flat", -- Default folder for configs
	_ActiveElements = {}, -- Internal tracking for cleanup
	_Connections = {},    -- Internal tracking for cleanup
	_DraggingInfo = {},   -- Internal tracking for window dragging
	_InputFocus = nil,    -- Internal tracking for text input focus
	_ActiveDropdown = nil,-- Internal tracking for open dropdown
	_TopZIndex = 1,       -- Internal tracking for window layering
	_ScreenGui = nil,     -- Reference to the main ScreenGui
	_Unloaded = false,    -- Flag for cleanup state
}

--// GetService Wrapper (from original MacLib)
MacLib.GetService = function(service)
	-- Using pcall for safety in potentially restricted environments
	local success, result = pcall(game.GetService, game, service)
	if success then
		return result
	else
		warn("MacLib: Could not get service:", service, "| Error:", result)
		return nil -- Return nil if service acquisition fails
	end
end

--// Services
local TweenService = MacLib.GetService("TweenService")
local RunService = MacLib.GetService("RunService")
local HttpService = MacLib.GetService("HttpService")
local ContentProvider = MacLib.GetService("ContentProvider")
local UserInputService = MacLib.GetService("UserInputService")
local Players = MacLib.GetService("Players")
local TextService = MacLib.GetService("TextService")
local Lighting = MacLib.GetService("Lighting") -- Keep for potential future use, though blur is removed

--// Variables
local isStudio = RunService and RunService:IsStudio()
local LocalPlayer = Players and Players.LocalPlayer
local PlayerGui = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")

--// Theme and Sizes (Flat Design)
MacLib.Theme = {
	Background = Color3.fromRGB(30, 30, 30),
	Primary = Color3.fromRGB(45, 45, 45),
	Secondary = Color3.fromRGB(60, 60, 60),
	Accent = Color3.fromRGB(0, 122, 204),
	AccentHover = Color3.fromRGB(28, 151, 234),
	AccentActive = Color3.fromRGB(0, 90, 158),
	Text = Color3.fromRGB(240, 240, 240),
	TextDisabled = Color3.fromRGB(120, 120, 120),
	Outline = Color3.fromRGB(80, 80, 80),
	OutlineActive = Color3.fromRGB(100, 100, 100),
	Titlebar = Color3.fromRGB(40, 40, 40),
	Error = Color3.fromRGB(200, 50, 50),
	Dropdown = Color3.fromRGB(35, 35, 35),
}

MacLib.Sizes = {
	Padding = 6,
	Spacing = 4,
	ElementHeight = 22,
	TitlebarHeight = 28,
	OutlineThickness = 1,
	TextSize = 14,
	SliderKnobSize = 12,
	CheckboxSize = 14,
	ScrollbarThickness = 8,
}

MacLib.Fonts = {
	Default = Font.fromEnum(Enum.Font.GothamSemibold), -- Changed from Inter for better Roblox availability
	Monospace = Font.fromEnum(Enum.Font.Code),
}

--// Assets (Minimal, only essential if any - keeping InterFont ID just in case)
local assets = {
	interFont = "rbxassetid://12187365364", -- Keep if you specifically want Inter
    colorWheel = "rbxassetid://2849458409", -- Keep for color picker potentially
	colorTarget = "rbxassetid://73265255323268", -- Keep for color picker potentially
    grid = "rbxassetid://121484455191370", -- Keep for color picker potentially
	-- Removed assets related to rounded corners, macOS style, etc.
}
-- Prefer GothamSemibold unless Inter is explicitly needed and available
-- MacLib.Fonts.Default = Font.new(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)


--// Helper Functions (Adapted from Flat UI Library)
local function Create(instanceType, properties)
	local inst = Instance.new(instanceType)
	inst.BorderSizePixel = 0 -- Base flat style
	for prop, value in pairs(properties or {}) do
        -- Safety check for valid properties
        local success, err = pcall(function() inst[prop] = value end)
        if not success then
            warn(string.format("MacLib.Create: Failed to set property '%s' on '%s': %s", tostring(prop), instanceType, tostring(err)))
        end
	end
    -- Explicitly remove corners if they somehow get added
	local corner = inst:FindFirstChildOfClass("UICorner")
	if corner then corner:Destroy() end
	return inst
end

local function AddOutline(instance, color, thickness)
	local stroke = instance:FindFirstChild("UIStroke_Outline")
	if not stroke then
		stroke = Create("UIStroke", {
			Name = "UIStroke_Outline",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Miter, -- Sharp corners
			Thickness = thickness or MacLib.Sizes.OutlineThickness,
			Color = color or MacLib.Theme.Outline,
			Parent = instance,
			Enabled = true,
		})
	else
		stroke.Thickness = thickness or MacLib.Sizes.OutlineThickness
		stroke.Color = color or MacLib.Theme.Outline
		stroke.Enabled = true
	end
	return stroke
end

local function AddPadding(instance, paddingValue)
	local pad = instance:FindFirstChild("UIPadding_Element")
	paddingValue = paddingValue or MacLib.Sizes.Padding
	if not pad then
		pad = Create("UIPadding", {
			Name = "UIPadding_Element",
			PaddingTop = UDim.new(0, paddingValue),
			PaddingBottom = UDim.new(0, paddingValue),
			PaddingLeft = UDim.new(0, paddingValue),
			PaddingRight = UDim.new(0, paddingValue),
			Parent = instance,
		})
	else
		pad.PaddingTop = UDim.new(0, paddingValue)
		pad.PaddingBottom = UDim.new(0, paddingValue)
		pad.PaddingLeft = UDim.new(0, paddingValue)
		pad.PaddingRight = UDim.new(0, paddingValue)
	end
	return pad
end

local function AddListLayout(instance, direction, spacing)
	local list = instance:FindFirstChild("UIListLayout_Element")
	direction = direction or Enum.FillDirection.Vertical
	spacing = spacing or MacLib.Sizes.Spacing
	if not list then
		list = Create("UIListLayout", {
			Name = "UIListLayout_Element",
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = direction,
			Padding = UDim.new(0, spacing),
			Parent = instance,
		})
	else
		list.FillDirection = direction
		list.Padding = UDim.new(0, spacing)
	end
	return list
end

local function TrackConnection(conn)
	if MacLib._Unloaded then conn:Disconnect() return conn end -- Disconnect immediately if unloaded
	table.insert(MacLib._Connections, conn)
	return conn
end

local function TrackElement(element)
	if MacLib._Unloaded then return end -- Don't track if unloaded
	table.insert(MacLib._ActiveElements, element)
end

local function UntrackElement(element)
	for i, el in ipairs(MacLib._ActiveElements) do
		if el == element then
			table.remove(MacLib._ActiveElements, i)
			break
		end
	end
end

-- Base class pattern for UI elements
local function CreateElementBase(elementType)
	local Base = {}
	Base._ClassName = elementType
	Base._Instance = nil
	Base._Connections = {}
	Base._Children = {}
	Base._Parent = nil
	Base._Visible = true
	Base._Destroyed = false
	Base.Flag = nil -- For config system

	function Base:Destroy()
		if Base._Destroyed then return end
		Base._Destroyed = true
		Base._Visible = false

		-- Destroy library children first
		for i = #Base._Children, 1, -1 do
			local child = Base._Children[i]
			if child and child.Destroy and not child._Destroyed then
				pcall(child.Destroy, child)
			end
		end
		Base._Children = {}

		-- Disconnect own connections
		for _, conn in ipairs(Base._Connections) do
			pcall(conn.Disconnect, conn)
		end
		Base._Connections = {}

		-- Destroy Roblox instance safely
		if Base._Instance and Base._Instance.Parent then
			pcall(Base._Instance.Destroy, Base._Instance)
		end
		Base._Instance = nil
		Base._Parent = nil

		-- Remove from global tracking
		UntrackElement(Base)

		-- Remove from MacLib.Options if flagged
		if Base.Flag and MacLib.Options[Base.Flag] == Base then
			MacLib.Options[Base.Flag] = nil
		end

        -- Clear fields to help GC
		for k in pairs(Base) do
            if k ~= "_Destroyed" then -- Keep destroyed flag
			    Base[k] = nil
            end
		end
        -- setmetatable(Base, nil) -- Avoid this, can cause issues if methods are somehow still called
	end

	function Base:SetVisibility(visible)
		if Base._Destroyed then return end
		Base._Visible = visible
		if Base._Instance then
			Base._Instance.Visible = visible
		end
        -- Recursively set visibility for children
        for _, child in ipairs(Base._Children) do
            if child.SetVisibility then
                child:SetVisibility(visible)
            elseif child._Instance then
                 child._Instance.Visible = visible
            end
        end
	end

	function Base:IsVisible()
		-- Check own visibility and parent visibility recursively
		if not Base._Visible or Base._Destroyed then return false end
		local parent = Base._Parent
		while parent do
			if not parent._Visible then return false end
			parent = parent._Parent
		end
		return true -- Only true if all ancestors are visible
	end


	function Base:GetInstance()
		return Base._Instance
	end

	function Base:_TrackConnection(conn)
		if MacLib._Unloaded or Base._Destroyed then conn:Disconnect() return conn end
		table.insert(Base._Connections, conn)
		return conn
	end

	function Base:_AddChild(childElement)
		if MacLib._Unloaded or Base._Destroyed then return end
		table.insert(Base._Children, childElement)
		childElement._Parent = Base
	end

	function Base:_RemoveChild(childElement)
		if MacLib._Unloaded or Base._Destroyed then return end
		for i, child in ipairs(Base._Children) do
			if child == childElement then
				table.remove(Base._Children, i)
				childElement._Parent = nil
				break
			end
		end
	end

	function Base:SetFlag(flagName)
		if Base.Flag and MacLib.Options[Base.Flag] == Base then
			MacLib.Options[Base.Flag] = nil -- Remove old flag mapping
		end
		Base.Flag = flagName
		if flagName then
			if MacLib.Options[flagName] then
				warn("MacLib: Flag '"..flagName.."' is already in use and will be overwritten.")
			end
			MacLib.Options[flagName] = Base
		end
	end

	TrackElement(Base)
	return Base
end

-- Bring window to front
local function FocusWindow(windowElement)
	if MacLib._Unloaded or not windowElement or not windowElement._Instance then return end
	MacLib._TopZIndex += 1
	windowElement._Instance.ZIndex = MacLib._TopZIndex
end

-- Close active dropdown on outside click
local function HandleDropdownCloseOnClick(input, gameProcessedEvent)
	if MacLib._Unloaded or gameProcessedEvent then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if MacLib._ActiveDropdown and MacLib._ActiveDropdown.CloseIfClickedOutside then
			local mousePos = UserInputService:GetMouseLocation()
			local dropdownInstance = MacLib._ActiveDropdown.Element:GetInstance()
			local listInstance = MacLib._ActiveDropdown.ListFrame

			if dropdownInstance and listInstance and dropdownInstance.Parent and listInstance.Parent then -- Check instances exist
				local buttonPos = dropdownInstance.AbsolutePosition
				local buttonSize = dropdownInstance.AbsoluteSize
				local listPos = listInstance.AbsolutePosition
				local listSize = listInstance.AbsoluteSize

				local clickedInButton = (mousePos.X >= buttonPos.X and mousePos.X <= buttonPos.X + buttonSize.X and
									   mousePos.Y >= buttonPos.Y and mousePos.Y <= buttonPos.Y + buttonSize.Y)
				local clickedInList = (mousePos.X >= listPos.X and mousePos.X <= listPos.X + listSize.X and
									 mousePos.Y >= listPos.Y and mousePos.Y <= listPos.Y + listSize.Y)

				if not clickedInButton and not clickedInList then
					MacLib._ActiveDropdown:Close()
				end
			else
				-- Instance might be destroyed or invalid, close just in case
                if MacLib._ActiveDropdown and MacLib._ActiveDropdown.Close then
				    MacLib._ActiveDropdown:Close()
                end
			end
		end
	end
end
if UserInputService then
    TrackConnection(UserInputService.InputBegan:Connect(HandleDropdownCloseOnClick))
end

--// GetGui Function (Adapted from original MacLib)
local function GetGui()
	if MacLib._ScreenGui and MacLib._ScreenGui.Parent then
		return MacLib._ScreenGui -- Return existing if valid
	end

	local newGui = Instance.new("ScreenGui")
	newGui.Name = "MacLib_Flat_ScreenGui_"..math.random(1000,9999)
	newGui.ScreenInsets = Enum.ScreenInsets.None -- Keep from original
	newGui.ResetOnSpawn = false
	newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	newGui.DisplayOrder = 2147483647 -- Keep from original (very high)
    newGui.IgnoreGuiInset = true -- Use full screen

	-- Determine parent (similar logic to original, prefer PlayerGui)
	local parent = PlayerGui
	if not parent then
		-- Fallback logic from original, use pcall for safety
		local coreGuiSuccess, coreGui = pcall(MacLib.GetService, "CoreGui")
		if coreGuiSuccess and coreGui then
			parent = coreGui
		else
			warn("MacLib: Could not find PlayerGui or CoreGui. UI will not be parented.")
			-- No parent found, UI won't display. Could parent to game if desperate? Not recommended.
            -- Or destroy the screengui?
            pcall(newGui.Destroy, newGui)
            return nil
		end
	end

    -- Parent safely
    local success, err = pcall(function() newGui.Parent = parent end)
    if not success then
        warn("MacLib: Failed to parent ScreenGui:", err)
        pcall(newGui.Destroy, newGui)
        return nil
    end

	MacLib._ScreenGui = newGui -- Store reference
	return newGui
end

--// Tween Wrapper (from original MacLib)
local function Tween(instance, tweeninfo, propertytable)
    if not TweenService then return { Play = function() end, Cancel = function() end, Completed = Instance.new("BindableEvent").Event } end -- Dummy tween if service failed
	return TweenService:Create(instance, tweeninfo, propertytable)
end


--// Container Mixin (Methods for Window/Tab/Section)
local ContainerMixin = {}

function ContainerMixin:AddLabel(text, options, Flag) -- Added Flag param
	if self._Destroyed then return nil end
	options = options or {}
	local Label = CreateElementBase("Label")
	if Flag then Label:SetFlag(Flag) end -- Set flag if provided

	local height = options.Height or MacLib.Sizes.ElementHeight -- Default or custom height
	local isAutoHeight = not options.Height -- Automatic height if not specified

	local TextLabel = Create("TextLabel", {
		Name = "Label_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(1, 0, 0, height),
		AutomaticSize = isAutoHeight and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
		TextSize = options.TextSize or MacLib.Sizes.TextSize,
		TextColor3 = options.Color or MacLib.Theme.Text,
		Text = text or "",
		TextWrapped = options.Wrap or isAutoHeight, -- Wrap if auto height or specified
		TextXAlignment = options.Align or Enum.TextXAlignment.Left,
		TextYAlignment = options.VAlign or Enum.TextYAlignment.Center,
		LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance, -- Parent to container's content frame
	})
	Label._Instance = TextLabel

	function Label:SetText(newText)
		if Label._Destroyed then return end
		TextLabel.Text = newText
	end

	function Label:SetColor(newColor)
		if Label._Destroyed then return end
		TextLabel.TextColor3 = newColor
	end

	self:_AddChild(Label)
	return Label
end

function ContainerMixin:AddButton(text, callback, options, Flag)
	if self._Destroyed then return nil end
	options = options or {}
	local Button = CreateElementBase("Button")
	Button.Class = "Button" -- For config parser
	if Flag then Button:SetFlag(Flag) end

	local height = options.Height or MacLib.Sizes.ElementHeight
    local useAutoSize = not options.Width and not options.FillWidth -- Auto size if no width specified

	local TextButton = Create("TextButton", {
		Name = "Button_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(options.FillWidth and 1 or 0, useAutoSize and 0 or (options.Width or 100), 0, height),
		AutomaticSize = useAutoSize and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		BackgroundColor3 = MacLib.Theme.Primary,
		TextColor3 = MacLib.Theme.Text,
		Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
		TextSize = options.TextSize or MacLib.Sizes.TextSize,
		Text = text or "Button",
		LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance,
	})

    if useAutoSize then -- Add padding for auto-sized buttons
        local textBounds = TextService and TextService:GetTextSize(TextButton.Text, TextButton.TextSize, TextButton.Font, Vector2.new(math.huge, height)) or Vector2.new(50, height)
        TextButton.Size = UDim2.new(0, textBounds.X + MacLib.Sizes.Padding * 2, 0, height)
    elseif not options.FillWidth then -- If fixed width, use it
        TextButton.Size = UDim2.new(0, options.Width, 0, height)
    end

	AddOutline(TextButton)
	Button._Instance = TextButton
	Button.IsEnabled = true -- Track enabled state

	-- Interaction States
	Button:_TrackConnection(TextButton.MouseEnter:Connect(function() if Button.IsEnabled then TextButton.BackgroundColor3 = MacLib.Theme.Secondary end end))
	Button:_TrackConnection(TextButton.MouseLeave:Connect(function() if Button.IsEnabled then TextButton.BackgroundColor3 = MacLib.Theme.Primary end end))
	Button:_TrackConnection(TextButton.MouseButton1Down:Connect(function() if Button.IsEnabled then TextButton.BackgroundColor3 = MacLib.Theme.AccentActive end end))
	Button:_TrackConnection(TextButton.MouseButton1Up:Connect(function() if Button.IsEnabled then TextButton.BackgroundColor3 = MacLib.Theme.Secondary end end))
	Button:_TrackConnection(TextButton.MouseButton1Click:Connect(function()
		if Button.IsEnabled and callback then
			local success, err = pcall(callback)
			if not success then
				warn("[MacLib] Button callback error:", err)
			end
		end
	end))

	function Button:SetText(newText)
		if Button._Destroyed then return end
		TextButton.Text = newText
		if useAutoSize then -- Recalculate size if automatic
			local textBounds = TextService and TextService:GetTextSize(TextButton.Text, TextButton.TextSize, TextButton.Font, Vector2.new(math.huge, height)) or Vector2.new(50, height)
			TextButton.Size = UDim2.new(0, textBounds.X + MacLib.Sizes.Padding * 2, 0, height)
		end
	end

	function Button:SetEnabled(enabled)
		if Button._Destroyed then return end
		Button.IsEnabled = enabled
		TextButton.AutoButtonColor = enabled
		if not enabled then
			TextButton.BackgroundColor3 = MacLib.Theme.Secondary
			TextButton.TextColor3 = MacLib.Theme.TextDisabled
			AddOutline(TextButton, MacLib.Theme.TextDisabled) -- Dim outline when disabled
		else
			TextButton.BackgroundColor3 = MacLib.Theme.Primary
			TextButton.TextColor3 = MacLib.Theme.Text
			AddOutline(TextButton, MacLib.Theme.Outline) -- Restore normal outline
		end
	end

	function Button:Click() -- Programmatic click
		if Button._Destroyed or not Button.IsEnabled then return end
		if callback then
			local success, err = pcall(callback)
			if not success then warn("[MacLib] Button callback error:", err) end
		end
	end

	self:_AddChild(Button)
	return Button
end

function ContainerMixin:AddCheckbox(text, callback, initialValue, options, Flag)
    if self._Destroyed then return nil end
    options = options or {}
    local Checkbox = CreateElementBase("Checkbox")
    Checkbox.Class = "Toggle" -- Use Toggle class for config compatibility with original MacLib example? Or make new Checkbox class? Using Toggle for now.
	if Flag then Checkbox:SetFlag(Flag) end

    local height = MacLib.Sizes.ElementHeight

    local Frame = Create("Frame", {
        Name = "CheckboxFrame_" .. (options.NameSuffix or math.random(100,999)),
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
        Parent = self.ContentFrame or self._Instance,
    })
    Checkbox._Instance = Frame
	Checkbox.State = initialValue or false -- For config system

    local CheckSquare = Create("Frame", {
        Name = "CheckSquare",
        Size = UDim2.fromOffset(MacLib.Sizes.CheckboxSize, MacLib.Sizes.CheckboxSize),
        Position = UDim2.new(0, 0, 0.5, -MacLib.Sizes.CheckboxSize / 2),
        BackgroundColor3 = MacLib.Theme.Primary,
		Visible = true,
        Parent = Frame,
    })
    AddOutline(CheckSquare)

    local CheckMark = Create("Frame", {
        Name = "CheckMark",
        Size = UDim2.new(0.6, 0, 0.6, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = MacLib.Theme.Accent,
        Visible = Checkbox.State, -- Start based on initial value
        ZIndex = CheckSquare.ZIndex + 1,
        Parent = CheckSquare,
    })
	-- No outline on the checkmark itself

    local Label = Create("TextLabel", {
        Name = "CheckboxLabel",
        Size = UDim2.new(1, -(MacLib.Sizes.CheckboxSize + MacLib.Sizes.Spacing), 1, 0),
        Position = UDim2.fromOffset(MacLib.Sizes.CheckboxSize + MacLib.Sizes.Spacing, 0),
        BackgroundTransparency = 1,
        Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
        TextSize = MacLib.Sizes.TextSize,
        TextColor3 = MacLib.Theme.Text,
        Text = text or "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
		Visible = true,
        Parent = Frame,
    })

    local function Toggle(skipCallback)
		if Checkbox._Destroyed then return end
        Checkbox.State = not Checkbox.State
        CheckMark.Visible = Checkbox.State
        CheckSquare.BackgroundColor3 = Checkbox.State and MacLib.Theme.Secondary or MacLib.Theme.Primary
        if callback and not skipCallback then
            local success, err = pcall(callback, Checkbox.State)
            if not success then warn("[MacLib] Checkbox callback error:", err) end
        end
    end

    local ClickDetector = Create("TextButton", {
        Name = "ClickDetector",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = Frame.ZIndex + 2, -- Above label and square
		Visible = true,
        Parent = Frame,
    })
    Checkbox:_TrackConnection(ClickDetector.MouseButton1Click:Connect(function() Toggle(false) end))

    Checkbox:_TrackConnection(ClickDetector.MouseEnter:Connect(function() AddOutline(CheckSquare, MacLib.Theme.OutlineActive) end))
    Checkbox:_TrackConnection(ClickDetector.MouseLeave:Connect(function() AddOutline(CheckSquare, MacLib.Theme.Outline) end))

    function Checkbox:GetValue() return Checkbox.State end
    function Checkbox:GetState() return Checkbox.State end -- Alias for config compatibility

    function Checkbox:SetValue(value, skipCallback)
		if Checkbox._Destroyed then return end
        value = not not value
        if value ~= Checkbox.State then
            Toggle(skipCallback) -- Let Toggle handle visuals and callback logic
        end
    end
	function Checkbox:UpdateState(value, skipCallback) -- Alias for config compatibility
		Checkbox:SetValue(value, skipCallback or true) -- Skip callback by default when updating from config
	end

	function Checkbox:UpdateName(newName) -- For config system compatibility (though checkboxes don't usually change names)
		if Checkbox._Destroyed then return end
		Label.Text = newName
	end


    self:_AddChild(Checkbox)
    return Checkbox
end


function ContainerMixin:AddSlider(text, min, max, initialValue, callback, options, Flag)
    if self._Destroyed then return nil end
    options = options or {}
    local Slider = CreateElementBase("Slider")
    Slider.Class = "Slider" -- For config system
	Slider.Settings = { Minimum = min, Maximum = max, Default = initialValue, Callback = callback, Precision = options.Precision, DisplayMethod = options.DisplayMethod, Prefix = options.Prefix, Suffix = options.Suffix, onInputComplete = options.onInputComplete } -- Store settings for config parser compatibility
	if Flag then Slider:SetFlag(Flag) end

    local height = MacLib.Sizes.ElementHeight

    local Frame = Create("Frame", {
        Name = "SliderFrame_" .. (options.NameSuffix or math.random(100,999)),
        Size = UDim2.new(1, 0, 0, height * 1.5), -- Taller for label + value display
        BackgroundTransparency = 1,
        LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
        Parent = self.ContentFrame or self._Instance,
    })
    Slider._Instance = Frame

    local Label = Create("TextLabel", {
        Name = "SliderLabel",
        Size = UDim2.new(0.6, -MacLib.Sizes.Spacing, 0, height), -- Use defined height
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
        TextSize = MacLib.Sizes.TextSize,
        TextColor3 = MacLib.Theme.Text,
        Text = text or "Slider",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
		Visible = true,
        Parent = Frame,
    })

    local ValueInput = Create("TextBox", { -- Use TextBox for display and input
        Name = "ValueInput",
        Size = UDim2.new(0.4, 0, 0, height), -- Use defined height
        Position = UDim2.new(0.6, MacLib.Sizes.Spacing, 0, 0),
        BackgroundTransparency = 0,
		BackgroundColor3 = MacLib.Theme.Primary,
        Font = (options.FontInput and MacLib.Fonts[options.FontInput] or MacLib.Fonts.Monospace).Font,
        TextSize = MacLib.Sizes.TextSize - 1,
        TextColor3 = MacLib.Theme.TextDisabled,
        Text = "", -- Updated later
		PlaceholderText = "...",
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		Visible = true,
        Parent = Frame,
    })
	AddOutline(ValueInput)
	AddPadding(ValueInput, 2) -- Minimal padding for input box

    local SliderTrack = Create("Frame", {
        Name = "SliderTrack",
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 1, -8),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = MacLib.Theme.Primary,
		Visible = true,
        Parent = Frame,
    })
    AddOutline(SliderTrack)

    local SliderFill = Create("Frame", {
        Name = "SliderFill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = MacLib.Theme.Accent,
        ZIndex = SliderTrack.ZIndex + 1,
		Visible = true,
        Parent = SliderTrack,
    })
	-- No outline on fill

    local SliderKnob = Create("Frame", {
        Name = "SliderKnob",
        Size = UDim2.fromOffset(MacLib.Sizes.SliderKnobSize, MacLib.Sizes.ElementHeight * 0.8), -- Taller knob
        Position = UDim2.new(0, -MacLib.Sizes.SliderKnobSize / 2, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5), -- Center anchor for easier positioning
        BackgroundColor3 = MacLib.Theme.AccentHover,
        ZIndex = SliderTrack.ZIndex + 2,
		Visible = true,
        Parent = SliderTrack,
    })
    AddOutline(SliderKnob, MacLib.Theme.OutlineActive)

    Slider.Value = initialValue or min -- Store current value for config system

	local DisplayMethods = { -- Copied from original MacLib for compatibility
		Hundredths = function(sliderValue) return string.format("%.2f", sliderValue) end,
		Tenths = function(sliderValue) return string.format("%.1f", sliderValue) end,
		Round = function(sliderValue, precision)
			if precision then return string.format("%." .. precision .. "f", sliderValue)
			else return tostring(math.floor(sliderValue + 0.5)) end -- Use floor(x+0.5) for rounding
		end,
		Degrees = function(sliderValue, precision)
			local formattedValue = precision and string.format("%." .. precision .. "f", sliderValue) or tostring(math.floor(sliderValue + 0.5))
			return formattedValue .. "°"
		end,
		Percent = function(sliderValue, precision)
            local range = max - min
            if range == 0 then return "0%" end -- Avoid division by zero
			local percentage = (sliderValue - min) / range * 100
			return precision and string.format("%." .. precision .. "f", percentage) .. "%" or tostring(math.floor(percentage + 0.5)) .. "%"
		end,
		Value = function(sliderValue, precision)
			return precision and string.format("%." .. precision .. "f", sliderValue) or tostring(math.floor(sliderValue + 0.5))
		end
	}
	local ValueDisplayMethod = DisplayMethods[options.DisplayMethod] or DisplayMethods.Value

    local function UpdateSliderVisuals(value)
		if Slider._Destroyed then return end
		local range = max - min
		local percentage = range == 0 and 0 or math.clamp((value - min) / range, 0, 1)

        SliderFill.Size = UDim2.new(percentage, 0, 1, 0)
        SliderKnob.Position = UDim2.new(percentage, 0, 0.5, 0) -- Position based on percentage

        -- Update value label safely
        local success, displayValue = pcall(ValueDisplayMethod, value, options.Precision)
        if success then
            ValueInput.Text = (options.Prefix or "") .. displayValue .. (options.Suffix or "")
        else
            ValueInput.Text = string.format("%.2f", value) -- Fallback format
            warn("[MacLib] Slider display method error:", displayValue)
        end
	end

    local function SetValue(value, skipCallback, fromInput)
		if Slider._Destroyed then return end
        local clampedValue = math.clamp(value, min, max)
		local roundedValue = clampedValue
		if options.Precision == 0 or options.Precision == nil then
			roundedValue = math.floor(clampedValue + 0.5) -- Round to nearest integer if precision is 0 or nil
		elseif options.Precision then
            local mult = 10^options.Precision
            roundedValue = math.floor(clampedValue * mult + 0.5) / mult -- Round to specified decimal places
        end

		if roundedValue ~= Slider.Value then
			Slider.Value = roundedValue
			UpdateSliderVisuals(Slider.Value)
			if callback and not skipCallback then
				local success, err = pcall(callback, Slider.Value)
				if not success then warn("[MacLib] Slider callback error:", err) end
			end
		elseif not fromInput then -- If value hasn't changed numerically, still update display
            UpdateSliderVisuals(Slider.Value)
        end
	end

    local IsDragging = false
    local function HandleInput(input)
		if Slider._Destroyed then return end
		local mouseX = input.Position.X
		local trackAbsPos = SliderTrack.AbsolutePosition
		local trackAbsSize = SliderTrack.AbsoluteSize
        if trackAbsSize.X == 0 then return end -- Avoid division by zero if track not rendered yet

		local relativeX = mouseX - trackAbsPos.X
		local percentage = math.clamp(relativeX / trackAbsSize.X, 0, 1)
		local newValue = min + percentage * (max - min)
		SetValue(newValue, false, true) -- Set value, trigger callback, indicate it's from direct input
	end

    local Hitbox = Create("TextButton", { -- Hitbox for easier dragging
        Name = "Hitbox",
        Size = UDim2.new(1, MacLib.Sizes.SliderKnobSize, 1, MacLib.Sizes.ElementHeight * 0.8), -- Cover track and knob height
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, Text = "",
        ZIndex = SliderKnob.ZIndex + 1,
		Visible = true,
        Parent = SliderTrack,
    })

    Slider:_TrackConnection(Hitbox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            IsDragging = true
            SliderKnob.BackgroundColor3 = MacLib.Theme.AccentActive
            AddOutline(SliderKnob, MacLib.Theme.Accent)
            HandleInput(input)

            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(moveInput)
                if (moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch) and IsDragging then
                    HandleInput(moveInput)
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function(endInput)
                if (endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch) then
                    if IsDragging then -- Only process if this slider was being dragged
                        IsDragging = false
                        SliderKnob.BackgroundColor3 = MacLib.Theme.AccentHover
                        AddOutline(SliderKnob, MacLib.Theme.OutlineActive)
                        if moveConn then moveConn:Disconnect() end
                        if endConn then endConn:Disconnect() end
						-- Trigger onInputComplete if defined
						if Slider.Settings.onInputComplete then
							pcall(Slider.Settings.onInputComplete, Slider.Value)
						end
                    end
                end
            end)
            Slider:_TrackConnection(moveConn)
            Slider:_TrackConnection(endConn)
        end
    end))

    -- Handle direct text input into the value box
	Slider:_TrackConnection(ValueInput.FocusLost:Connect(function(enterPressed)
		if Slider._Destroyed then return end
		local text = ValueInput.Text
		-- Attempt to remove prefix/suffix if they exist
		if options.Prefix and text:sub(1, #options.Prefix) == options.Prefix then
			text = text:sub(#options.Prefix + 1)
		end
		if options.Suffix and text:sub(-#options.Suffix) == options.Suffix then
			text = text:sub(1, #text - #options.Suffix)
		end
        -- Handle percentage input specifically if display method is Percent
        local num
        if options.DisplayMethod == "Percent" and text:sub(-1) == "%" then
            num = tonumber(text:sub(1, -2))
            if num then
                local range = max - min
                if range ~= 0 then
                    num = min + (num / 100) * range
                else
                    num = min -- If range is 0, value must be min
                end
            end
        else
		    num = tonumber(text)
        end

		if num then
			SetValue(num, false, false) -- Set value, trigger callback
		else
			-- If input is invalid, revert to current value display
			UpdateSliderVisuals(Slider.Value)
		end
		-- Trigger onInputComplete if defined
		if Slider.Settings.onInputComplete then
			pcall(Slider.Settings.onInputComplete, Slider.Value)
		end
	end))

    Slider:_TrackConnection(Hitbox.MouseEnter:Connect(function() if not IsDragging then AddOutline(SliderKnob, MacLib.Theme.Accent) end end))
    Slider:_TrackConnection(Hitbox.MouseLeave:Connect(function() if not IsDragging then AddOutline(SliderKnob, MacLib.Theme.OutlineActive) end end))

    function Slider:GetValue() return Slider.Value end
	function Slider:UpdateValue(value, skipCallback) -- Alias for config system
		SetValue(tonumber(value) or min, skipCallback or true) -- Skip callback by default
	end
    function Slider:SetValue(value, skipCallback) -- Standard method
		SetValue(value, skipCallback)
	end
	function Slider:UpdateName(newName) -- For config system
		if Slider._Destroyed then return end
		Label.Text = newName
	end


    -- Initial setup
    SetValue(Slider.Value, true) -- Set initial value without callback

    self:_AddChild(Slider)
    return Slider
end


function ContainerMixin:AddDropdown(text, items, callback, initialSelection, options, Flag)
	if self._Destroyed then return nil end
	options = options or {}
	local Dropdown = CreateElementBase("Dropdown")
	Dropdown.Class = "Dropdown" -- For config system
	Dropdown.Settings = { Name = text, Options = items, Callback = callback, Default = initialSelection, Multi = options.Multi, Required = options.Required, Search = options.Search } -- For config parser compatibility
	if Flag then Dropdown:SetFlag(Flag) end

	local height = MacLib.Sizes.ElementHeight

	local Frame = Create("Frame", {
		Name = "DropdownFrame_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = options.LayoutOrder or 0,
		ZIndex = options.ZIndex or 1, -- Allow ZIndex customization
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance,
	})
	Dropdown._Instance = Frame
	Dropdown.Element = Dropdown -- For ActiveDropdown tracking

	local Label = Create("TextLabel", {
		Name = "DropdownLabel",
		Size = UDim2.new(0.4, -MacLib.Sizes.Spacing, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = (options.FontLabel and MacLib.Fonts[options.FontLabel] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		TextColor3 = MacLib.Theme.Text,
		Text = text or "Dropdown",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = true,
		Parent = Frame,
	})

	local DropdownButton = Create("TextButton", {
		Name = "DropdownButton",
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.new(0.4, MacLib.Sizes.Spacing, 0, 0),
		BackgroundColor3 = MacLib.Theme.Primary,
		TextColor3 = MacLib.Theme.Text,
		Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		Text = "", -- Set later
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = true,
		Parent = Frame,
	})
	AddOutline(DropdownButton)
	local btnPadding = AddPadding(DropdownButton, MacLib.Sizes.Padding / 2)
	btnPadding.PaddingRight = UDim.new(0, MacLib.Sizes.ElementHeight) -- Space for arrow

	local Arrow = Create("TextLabel", {
		Name = "Arrow",
		Size = UDim2.fromOffset(MacLib.Sizes.ElementHeight / 1.5, MacLib.Sizes.ElementHeight / 1.5),
		Position = UDim2.new(1, -MacLib.Sizes.ElementHeight * 0.75, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Font = MacLib.Fonts.Default.Font, Text = "▼",
		TextColor3 = MacLib.Theme.TextDisabled, TextSize = MacLib.Sizes.TextSize,
		TextYAlignment = Enum.TextYAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = DropdownButton.ZIndex + 1,
		Visible = true,
		Parent = DropdownButton,
	})

	local ListFrame = Create("ScrollingFrame", {
		Name = "DropdownList",
		Size = UDim2.new(1, 0, 0, 0), -- Width matches button initially, height dynamic
		Position = UDim2.new(0, 0, 1, 0), -- Position below button
		AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 0, BackgroundColor3 = MacLib.Theme.Dropdown,
		BorderSizePixel = 0, ClipsDescendants = true, Visible = false,
		ZIndex = Frame.ZIndex + 100, -- High ZIndex needed
		ScrollBarThickness = MacLib.Sizes.ScrollbarThickness, ScrollBarImageColor3 = MacLib.Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0,0,0,0), -- Start empty
		Parent = Frame, -- Parent to main frame for ZIndex layering
	})
	AddOutline(ListFrame, MacLib.Theme.OutlineActive)
	AddPadding(ListFrame, 0) -- No padding for scrolling frame
	local listLayout = AddListLayout(ListFrame, Enum.FillDirection.Vertical, 0) -- No spacing between items

	Dropdown.ListFrame = ListFrame -- Reference for click outside logic

	local CurrentItems = items or {}
	local Selected = {} -- Table to hold selected item names (for multi-select)
	local IsMultiSelect = options.Multi or false
	local IsRequired = options.Required or false
	local IsOpen = false
	local ItemElements = {} -- Store refs to item buttons { ["ItemName"] = ItemButtonElement }

	-- Function to update the main button text based on selection
	local function UpdateButtonText()
		if Dropdown._Destroyed then return end
		local display = ""
		if #Selected > 0 then
			display = table.concat(Selected, ", ")
			if TextService then -- Truncate if too long
				local maxSize = DropdownButton.AbsoluteSize.X - btnPadding.PaddingLeft.Offset - btnPadding.PaddingRight.Offset - 5
				local textSize = TextService:GetTextSize(display, DropdownButton.TextSize, DropdownButton.Font, Vector2.new(maxSize, MacLib.Sizes.ElementHeight))
				while textSize.X > maxSize and #display > 3 do
					display = display:sub(1, -5) .. "..." -- Simple truncation
					textSize = TextService:GetTextSize(display, DropdownButton.TextSize, DropdownButton.Font, Vector2.new(maxSize, MacLib.Sizes.ElementHeight))
				end
			end
		else
			display = options.Placeholder or "Select..."
		end
		DropdownButton.Text = display

		-- Update checkmark visibility on items
		for itemName, itemEl in pairs(ItemElements) do
			local checkmark = itemEl:GetInstance():FindFirstChild("Checkmark")
			if checkmark then
				checkmark.Visible = table.find(Selected, itemName) ~= nil
			end
		end
	end

	-- Function to create an item button in the list
	local function CreateItemButton(itemValue, index)
		if Dropdown._Destroyed then return nil end
		local itemStr = tostring(itemValue)
		local itemButtonElement = CreateElementBase("DropdownItem")

		local itemButton = Create("TextButton", {
			Name = "Item_" .. itemStr,
			Size = UDim2.new(1, 0, 0, MacLib.Sizes.ElementHeight),
			BackgroundColor3 = MacLib.Theme.Dropdown,
			TextColor3 = MacLib.Theme.Text,
			Font = MacLib.Fonts.Default.Font,
			TextSize = MacLib.Sizes.TextSize,
			Text = " " .. itemStr, -- Indent slightly
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = index,
			Visible = true,
			Parent = ListFrame,
		})
		itemButtonElement._Instance = itemButton

		-- Add checkmark (always present, visibility toggled)
		local checkmark = Create("TextLabel", {
			Name = "Checkmark",
			Size = UDim2.fromOffset(MacLib.Sizes.ElementHeight * 0.6, MacLib.Sizes.ElementHeight * 0.6),
			Position = UDim2.new(1, -MacLib.Sizes.ElementHeight * 0.8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Font = MacLib.Fonts.Default.Font, Text = "✓", -- Checkmark symbol
			TextColor3 = MacLib.Theme.Accent, TextSize = MacLib.Sizes.TextSize + 2,
			TextYAlignment = Enum.TextYAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
			Visible = table.find(Selected, itemStr) ~= nil, -- Initial visibility
			ZIndex = itemButton.ZIndex + 1,
			Parent = itemButton,
		})

		Dropdown:_TrackConnection(itemButton.MouseEnter:Connect(function() itemButton.BackgroundColor3 = MacLib.Theme.Secondary end))
		Dropdown:_TrackConnection(itemButton.MouseLeave:Connect(function() itemButton.BackgroundColor3 = MacLib.Theme.Dropdown end))
		Dropdown:_TrackConnection(itemButton.MouseButton1Click:Connect(function()
			if Dropdown._Destroyed then return end
			local currentlySelected = table.find(Selected, itemStr) ~= nil
			local canDeselect = not IsRequired or #Selected > 1 or not IsMultiSelect

			if IsMultiSelect then
				if currentlySelected and canDeselect then
					-- Remove from selection
					for i, v in ipairs(Selected) do if v == itemStr then table.remove(Selected, i); break end end
				elseif not currentlySelected then
					-- Add to selection
					table.insert(Selected, itemStr)
				end
			else -- Single select
				if currentlySelected and canDeselect then
					Selected = {} -- Deselect
				else
					Selected = {itemStr} -- Select this one
					Dropdown:Close() -- Close after single selection
				end
			end

			Dropdown.Value = IsMultiSelect and Selected or Selected[1] -- Update Value for config system

			UpdateButtonText() -- Update visuals and checkmarks

			if callback then
				local success, err = pcall(callback, IsMultiSelect and Selected or Selected[1], IsMultiSelect and nil or index) -- Pass selection table/value
				if not success then warn("[MacLib] Dropdown callback error:", err) end
			end
		end))

		ItemElements[itemStr] = itemButtonElement
		Dropdown:_AddChild(itemButtonElement)
		return itemButtonElement
	end

	-- Function to populate/repopulate the dropdown list
	local function PopulateList()
		if Dropdown._Destroyed then return end
		-- Clear existing item elements safely
        local childrenToDestroy = {}
        for _, child in ipairs(Dropdown._Children) do
            if child._ClassName == "DropdownItem" then
                table.insert(childrenToDestroy, child)
            end
        end
        for _, child in ipairs(childrenToDestroy) do
            Dropdown:_RemoveChild(child)
            pcall(child.Destroy, child)
        end
		ItemElements = {}

		-- Create new items
		local itemHeight = MacLib.Sizes.ElementHeight
        local totalHeight = 0
		for i, item in ipairs(CurrentItems) do
			local itemEl = CreateItemButton(item, i)
            if itemEl then totalHeight = totalHeight + itemHeight end
		end

		-- Adjust ListFrame size (limit height)
		local maxListHeight = itemHeight * 7.5
		local listHeight = math.min(totalHeight, maxListHeight)
        local buttonWidth = DropdownButton.AbsoluteSize.X > 0 and DropdownButton.AbsoluteSize.X or 150 -- Use calculated or default width

        -- Need absolute positioning relative to the button
        ListFrame.Position = UDim2.fromOffset(DropdownButton.AbsolutePosition.X, DropdownButton.AbsolutePosition.Y + DropdownButton.AbsoluteSize.Y)
        ListFrame.Size = UDim2.fromOffset(buttonWidth, listHeight)

		-- CanvasSize update seems handled by AutomaticCanvasSize = Y
	end

	-- Open/Close/Toggle functions
	function Dropdown:Open()
		if IsOpen or Dropdown._Destroyed then return end
		if MacLib._ActiveDropdown and MacLib._ActiveDropdown ~= Dropdown then MacLib._ActiveDropdown:Close() end

		PopulateList() -- Repopulate and resize

		ListFrame.Visible = true
		IsOpen = true
		Arrow.Text = "▲"
		AddOutline(DropdownButton, MacLib.Theme.OutlineActive)
		MacLib._ActiveDropdown = Dropdown
		Dropdown.CloseIfClickedOutside = true -- Enable closing
	end

	function Dropdown:Close()
		if not IsOpen or Dropdown._Destroyed then return end
		ListFrame.Visible = false
		IsOpen = false
		Arrow.Text = "▼"
		AddOutline(DropdownButton, MacLib.Theme.Outline)
		if MacLib._ActiveDropdown == Dropdown then MacLib._ActiveDropdown = nil end
		Dropdown.CloseIfClickedOutside = false
	end

	function Dropdown:Toggle()
		if Dropdown._Destroyed then return end
		if IsOpen then Dropdown:Close() else Dropdown:Open() end
	end

	Dropdown:_TrackConnection(DropdownButton.MouseButton1Click:Connect(Dropdown.Toggle))
	Dropdown:_TrackConnection(DropdownButton.MouseEnter:Connect(function() if not IsOpen then AddOutline(DropdownButton, MacLib.Theme.OutlineActive) end end))
	Dropdown:_TrackConnection(DropdownButton.MouseLeave:Connect(function() if not IsOpen then AddOutline(DropdownButton, MacLib.Theme.Outline) end end))

	-- Public methods
	function Dropdown:GetValue() -- Returns table if multi, string/value if single
		if Dropdown._Destroyed then return IsMultiSelect and {} or nil end
		return IsMultiSelect and Selected or Selected[1]
	end

	function Dropdown:GetSelected() -- Always returns a table of selected values
        if Dropdown._Destroyed then return {} end
		return Selected
	end

	function Dropdown:UpdateSelection(newSelection, skipCallback) -- Used by config loader primarily
		if Dropdown._Destroyed then return end
		Selected = {} -- Clear current selection

		if IsMultiSelect then
			if type(newSelection) == "table" then
				for _, itemToSelect in ipairs(newSelection) do
					local itemStr = tostring(itemToSelect)
					if table.find(CurrentItems, itemToSelect) or table.find(CurrentItems, itemStr) then -- Check if item exists
						if not table.find(Selected, itemStr) then
							table.insert(Selected, itemStr)
						end
					else
						warn("[MacLib] Dropdown:UpdateSelection - Item not found in options:", itemStr)
					end
				end
			elseif newSelection ~= nil then
				warn("[MacLib] Dropdown:UpdateSelection - Expected a table for multi-select, got:", typeof(newSelection))
			end
		else -- Single select
			if newSelection ~= nil then
				local itemStr = tostring(newSelection)
				if table.find(CurrentItems, newSelection) or table.find(CurrentItems, itemStr) then
					Selected = {itemStr}
				else
					warn("[MacLib] Dropdown:UpdateSelection - Item not found in options:", itemStr)
				end
			end
		end

		Dropdown.Value = IsMultiSelect and Selected or Selected[1] -- Update Value for config system
		UpdateButtonText() -- Update visuals

		if callback and not skipCallback then
			local success, err = pcall(callback, IsMultiSelect and Selected or Selected[1])
			if not success then warn("[MacLib] Dropdown callback error:", err) end
		end
	end

	function Dropdown:InsertOptions(newItems) -- For config system compatibility
		if Dropdown._Destroyed then return end
		Dropdown:UpdateItems(newItems, true) -- Keep selection if possible
	end

	function Dropdown:UpdateItems(newItemsTable, keepSelection)
		if Dropdown._Destroyed then return end
		local oldSelected = Dropdown:GetSelected() -- Get table of currently selected
		CurrentItems = newItemsTable or {}
		Selected = {} -- Reset selection

		if keepSelection then
			for _, oldItem in ipairs(oldSelected) do
				-- Check if old item exists in new items
				local found = false
				for _, newItem in ipairs(CurrentItems) do
					if tostring(newItem) == oldItem then
						table.insert(Selected, oldItem)
						found = true
						break
					end
				end
                if not found then
                    -- Item removed, don't re-select
                end
			end
		end

		-- Ensure required selection is met if applicable
		if IsRequired and #Selected == 0 and #CurrentItems > 0 then
			table.insert(Selected, tostring(CurrentItems[1])) -- Select first item if required and none selected
		end

		Dropdown.Value = IsMultiSelect and Selected or Selected[1] -- Update Value for config system

		if IsOpen then PopulateList() end -- Update list view if open
		UpdateButtonText()
	end

	function Dropdown:ClearOptions() -- For config system
		if Dropdown._Destroyed then return end
		Dropdown:UpdateItems({}, false)
	end

	function Dropdown:RemoveOptions(optionsToRemove) -- For config system
		if Dropdown._Destroyed then return end
		local newItems = {}
		local itemsToRemoveLookup = {}
		for _, item in ipairs(optionsToRemove or {}) do
			itemsToRemoveLookup[tostring(item)] = true
		end

		for _, item in ipairs(CurrentItems) do
			if not itemsToRemoveLookup[tostring(item)] then
				table.insert(newItems, item)
			end
		end
		Dropdown:UpdateItems(newItems, true) -- Keep selection if possible
	end

	function Dropdown:GetOptions() -- For config system (returns item elements, maybe not what original intended?)
        if Dropdown._Destroyed then return {} end
        -- Let's return the current items list instead, seems more useful
		return CurrentItems
	end

	function Dropdown:IsOption(optionName) -- For config system
		if Dropdown._Destroyed then return false end
        for _, item in ipairs(CurrentItems) do
            if tostring(item) == tostring(optionName) then return true end
        end
		return false
	end

	function Dropdown:UpdateName(newName) -- For config system
		if Dropdown._Destroyed then return end
		Label.Text = newName
		Dropdown.Settings.Name = newName -- Update internal setting too
	end

	-- Initial setup
	Dropdown:UpdateSelection(initialSelection, true) -- Set initial selection without callback

	self:_AddChild(Dropdown)
	return Dropdown
end


function ContainerMixin:AddTextInput(text, placeholder, callback, options, Flag)
	if self._Destroyed then return nil end
	options = options or {}
	local TextInput = CreateElementBase("TextInput")
	TextInput.Class = "Input" -- Match original MacLib config class
	TextInput.Settings = { Name = text, Placeholder = placeholder, Callback = callback, Default = options.InitialValue, AcceptedCharacters = options.AcceptedCharacters, CharacterLimit = options.CharacterLimit, onChanged = options.onChanged } -- Store settings
	if Flag then TextInput:SetFlag(Flag) end

	local isMultiline = options.Multiline or false
	local height = isMultiline and MacLib.Sizes.ElementHeight * (options.Lines or 3) or MacLib.Sizes.ElementHeight

	local Frame = Create("Frame", {
		Name = "TextInputFrame_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance,
	})
	TextInput._Instance = Frame

	local Label = Create("TextLabel", {
		Name = "TextInputLabel",
		Size = UDim2.new(0.4, -MacLib.Sizes.Spacing, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = (options.FontLabel and MacLib.Fonts[options.FontLabel] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		TextColor3 = MacLib.Theme.Text,
		Text = text or "Input",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = isMultiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Visible = true,
		Parent = Frame,
	})

	local TextBox = Create("TextBox", {
		Name = "InputBox",
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.new(0.4, MacLib.Sizes.Spacing, 0, 0),
		BackgroundColor3 = MacLib.Theme.Primary,
		Font = (options.Font and MacLib.Fonts[options.Font] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		TextColor3 = MacLib.Theme.Text,
		Text = options.InitialValue or "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = MacLib.Theme.TextDisabled,
		ClearTextOnFocus = options.ClearOnFocus or false,
		TextWrapped = isMultiline, MultiLine = isMultiline,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = isMultiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Visible = true,
		Parent = Frame,
	})
	AddOutline(TextBox)
	AddPadding(TextBox, MacLib.Sizes.Padding / 2)

	TextInput.Text = TextBox.Text -- For config system

	-- Character filtering logic (from original MacLib)
	local function applyCharacterLimit(value)
		if options.CharacterLimit then return value:sub(1, options.CharacterLimit) end
		return value
	end
	local CharacterSubs = {
		All = function(value) return applyCharacterLimit(value) end,
		Numeric = function(value)
			local result = value:match("^%-?%d*%.?%d*$") and value or value:gsub("[^%d%.%-]", ""):gsub("(%-)", function(match, pos) return pos == 1 and match or "" end)
            -- Allow only one decimal point
            local dotCount = 0
            result = result:gsub("%.", function() dotCount = dotCount + 1; return dotCount == 1 and "." or "" end)
			return applyCharacterLimit(result)
		end,
		Alphabetic = function(value) return applyCharacterLimit(value:gsub("[^a-zA-Z ]", "")) end,
		AlphaNumeric = function(value) return applyCharacterLimit(value:gsub("[^a-zA-Z0-9 ]", "")) end, -- Allow space
	}
	local AcceptedCharactersFilter
	if type(options.AcceptedCharacters) == "function" then
		AcceptedCharactersFilter = options.AcceptedCharacters
	else
		AcceptedCharactersFilter = CharacterSubs[options.AcceptedCharacters] or CharacterSubs.All
	end

	TextInput:_TrackConnection(TextBox.FocusGained:Connect(function()
		if TextInput._Destroyed then return end
		if MacLib._InputFocus and MacLib._InputFocus ~= TextInput and MacLib._InputFocus.ReleaseFocus then
			pcall(MacLib._InputFocus.ReleaseFocus, MacLib._InputFocus) -- Release focus from previous input
		end
		MacLib._InputFocus = TextInput
		AddOutline(TextBox, MacLib.Theme.Accent)
	end))

	TextInput:_TrackConnection(TextBox.FocusLost:Connect(function(enterPressed, inputObject)
		if TextInput._Destroyed then return end
		if MacLib._InputFocus == TextInput then MacLib._InputFocus = nil end
		AddOutline(TextBox, MacLib.Theme.Outline)

		-- Apply filter *after* focus lost, then run callback
		local filteredText = AcceptedCharactersFilter(TextBox.Text)
        if TextBox.Text ~= filteredText then TextBox.Text = filteredText end -- Update if filter changed it
		TextInput.Text = TextBox.Text -- Update internal value

		if callback then
			local success, err = pcall(callback, TextInput.Text, enterPressed)
			if not success then warn("[MacLib] TextInput callback error:", err) end
		end
	end))

	TextInput:_TrackConnection(TextBox:GetPropertyChangedSignal("Text"):Connect(function()
		if TextInput._Destroyed or not TextBox:IsFocused() then return end -- Only filter while focused for responsiveness
		local currentText = TextBox.Text
		local filteredText = AcceptedCharactersFilter(currentText)
		if currentText ~= filteredText then
			local cursorPos = TextBox.CursorPosition
			TextBox.Text = filteredText
			-- Attempt to restore cursor position reasonably
			TextBox.CursorPosition = math.min(cursorPos, #filteredText + 1)
		end
		TextInput.Text = TextBox.Text -- Update internal value

		-- Optional immediate callback on change
		if options.onChanged then
			local success, err = pcall(options.onChanged, TextInput.Text)
			if not success then warn("[MacLib] TextInput (onChanged) callback error:", err) end
		end
	end))

	function TextInput:GetValue() return TextInput.Text end
	function TextInput:GetInput() return TextInput.Text end -- Alias for config

	function TextInput:SetValue(value, skipCallback)
		if TextInput._Destroyed then return end
		local filteredText = AcceptedCharactersFilter(tostring(value))
		TextBox.Text = filteredText
		TextInput.Text = filteredText
		if callback and not skipCallback then
			local success, err = pcall(callback, TextInput.Text, false) -- EnterPressed is false here
			if not success then warn("[MacLib] TextInput callback error:", err) end
		end
	end
	function TextInput:UpdateText(value) TextInput:SetValue(value, true) end -- Alias for config

	function TextInput:Clear() TextInput:SetValue("", false) end
	function TextInput:Focus() if not TextInput._Destroyed then TextBox:CaptureFocus() end end
	function TextInput:ReleaseFocus() if not TextInput._Destroyed then TextBox:ReleaseFocus() end end

	function TextInput:UpdateName(newName) -- For config system
		if TextInput._Destroyed then return end
		Label.Text = newName
		TextInput.Settings.Name = newName
	end
	function TextInput:UpdatePlaceholder(newPlaceholder) -- For config system
		if TextInput._Destroyed then return end
		TextBox.PlaceholderText = newPlaceholder or ""
		TextInput.Settings.Placeholder = newPlaceholder
	end


	self:_AddChild(TextInput)
	return TextInput
end


function ContainerMixin:AddKeybind(text, callback, initialKey, options, Flag)
	if self._Destroyed then return nil end
	options = options or {}
	local Keybind = CreateElementBase("Keybind")
	Keybind.Class = "Keybind" -- For config system
	Keybind.Settings = { Name = text, Callback = callback, Default = initialKey, Blacklist = options.Blacklist, onBindHeld = options.onBindHeld, onBinded = options.onBinded } -- Store settings
	if Flag then Keybind:SetFlag(Flag) end

	local height = MacLib.Sizes.ElementHeight

	local Frame = Create("Frame", {
		Name = "KeybindFrame_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance,
	})
	Keybind._Instance = Frame

	local Label = Create("TextLabel", {
		Name = "KeybindLabel",
		Size = UDim2.new(0.5, -MacLib.Sizes.Spacing, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = (options.FontLabel and MacLib.Fonts[options.FontLabel] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		TextColor3 = MacLib.Theme.Text,
		Text = text or "Keybind",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = true,
		Parent = Frame,
	})

	local KeyButton = Create("TextButton", { -- TextButton used for display and interaction
		Name = "KeyButton",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.5, MacLib.Sizes.Spacing, 0, 0),
		BackgroundColor3 = MacLib.Theme.Primary,
		TextColor3 = MacLib.Theme.Text,
		Font = MacLib.Fonts.Monospace.Font,
		TextSize = MacLib.Sizes.TextSize - 1,
		Text = "", -- Set later
		AutoButtonColor = false, -- Manual control of colors
		Visible = true,
		Parent = Frame,
	})
	AddOutline(KeyButton)
	AddPadding(KeyButton, 2)

	Keybind.Bind = initialKey or Enum.KeyCode.Unknown -- Store bind for config system

	local IsBinding = false
	local bindConnection = nil

	local function GetKeyName(key)
		if key == Enum.KeyCode.Unknown then return "[None]" end
        if key:IsA("UserInputType") then -- Mouse buttons
            if key == Enum.UserInputType.MouseButton1 then return "[Mouse1]"
            elseif key == Enum.UserInputType.MouseButton2 then return "[Mouse2]"
            elseif key == Enum.UserInputType.MouseButton3 then return "[Mouse3]"
            -- Add more mouse buttons if needed
            end
        elseif key:IsA("KeyCode") then
		    return "["..key.Name.."]"
        end
		return "[Invalid]"
	end

	local function UpdateButtonText()
		if Keybind._Destroyed then return end
		if IsBinding then
			KeyButton.Text = "[...]"
			KeyButton.TextColor3 = MacLib.Theme.Accent
		else
			KeyButton.Text = GetKeyName(Keybind.Bind)
			if Keybind.Bind == Enum.KeyCode.Unknown then
				KeyButton.TextColor3 = MacLib.Theme.TextDisabled
			else
				KeyButton.TextColor3 = MacLib.Theme.Text
			end
		end
	end

	local function StopBinding(success)
		if not IsBinding then return end -- Prevent double-stopping
		IsBinding = false
		if bindConnection then pcall(bindConnection.Disconnect, bindConnection); bindConnection = nil end
		KeyButton.BackgroundColor3 = MacLib.Theme.Primary
		AddOutline(KeyButton, MacLib.Theme.Outline)
		UpdateButtonText()
		if MacLib._InputFocus == Keybind then MacLib._InputFocus = nil end

		if success then -- Trigger onBinded only on successful bind
			if Keybind.Settings.onBinded then
				pcall(Keybind.Settings.onBinded, Keybind.Bind)
			end
            -- The main callback (Settings.Callback) should be triggered by the global listener
		end
	end

	local function StartBinding()
		if IsBinding or Keybind._Destroyed then return end

		if MacLib._InputFocus and MacLib._InputFocus ~= Keybind and MacLib._InputFocus.ReleaseFocus then
			pcall(MacLib._InputFocus.ReleaseFocus, MacLib._InputFocus)
		end
		if MacLib._ActiveDropdown then MacLib._ActiveDropdown:Close() end

		IsBinding = true
		MacLib._InputFocus = Keybind
		KeyButton.BackgroundColor3 = MacLib.Theme.AccentActive
		AddOutline(KeyButton, MacLib.Theme.Accent)
		UpdateButtonText()

		bindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
			if not IsBinding then -- Check if binding was cancelled by another event
				if bindConnection then pcall(bindConnection.Disconnect, bindConnection); bindConnection = nil end
				return
			end
			if gameProcessedEvent and not (input.KeyCode == Enum.KeyCode.Escape) then return end -- Allow Esc even if processed

			local newBind = Enum.KeyCode.Unknown
			local isValidBind = false

			if input.UserInputType == Enum.UserInputType.Keyboard then
				newBind = input.KeyCode
				isValidBind = true
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				newBind = input.UserInputType -- Store UserInputType for mouse buttons
				isValidBind = true
			end

			-- Check blacklist
			if Keybind.Settings.Blacklist then
				if (newBind:IsA("KeyCode") and table.find(Keybind.Settings.Blacklist, newBind)) or
				   (newBind:IsA("UserInputType") and table.find(Keybind.Settings.Blacklist, newBind)) then
					isValidBind = false
                    warn("[MacLib] Keybind blocked by blacklist:", GetKeyName(newBind))
                    -- Maybe flash red or something? For now, just ignore.
                    return -- Don't stop binding yet, let them try another key
				end
			end

			if newBind == Enum.KeyCode.Escape then
				StopBinding(false) -- Cancel binding on Escape
			elseif isValidBind and newBind ~= Enum.KeyCode.Unknown then
				Keybind.Bind = newBind
				StopBinding(true) -- Set key and stop binding
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then -- If clicked outside button while binding, cancel
				local mousePos = UserInputService:GetMouseLocation()
				local buttonPos = KeyButton.AbsolutePosition
				local buttonSize = KeyButton.AbsoluteSize
				if not (mousePos.X >= buttonPos.X and mousePos.X <= buttonPos.X + buttonSize.X and
						mousePos.Y >= buttonPos.Y and mousePos.Y <= buttonPos.Y + buttonSize.Y) then
					StopBinding(false)
				end
            else
                -- Ignore other input types (like mouse movement) while binding
			end
		end)
        -- Track the connection within the element itself for its own cleanup
        Keybind:_TrackConnection(bindConnection)
	end

	Keybind:_TrackConnection(KeyButton.MouseButton1Click:Connect(StartBinding))
	Keybind:_TrackConnection(KeyButton.MouseEnter:Connect(function() if not IsBinding then AddOutline(KeyButton, MacLib.Theme.OutlineActive) end end))
	Keybind:_TrackConnection(KeyButton.MouseLeave:Connect(function() if not IsBinding then AddOutline(KeyButton, MacLib.Theme.Outline) end end))

	-- Global listener for the actual keybind press/release
	local keybindHeld = false
	local globalInputConnBegan, globalInputConnEnded
	globalInputConnBegan = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if Keybind._Destroyed or IsBinding or gameProcessedEvent or Keybind.Bind == Enum.KeyCode.Unknown then return end
		if input.KeyCode == Keybind.Bind or input.UserInputType == Keybind.Bind then
			keybindHeld = true
			if Keybind.Settings.Callback then
				pcall(Keybind.Settings.Callback, Keybind.Bind)
			end
			if Keybind.Settings.onBindHeld then
				pcall(Keybind.Settings.onBindHeld, true, Keybind.Bind)
			end
		end
	end)
	globalInputConnEnded = UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		if Keybind._Destroyed or IsBinding or Keybind.Bind == Enum.KeyCode.Unknown then return end
		if input.KeyCode == Keybind.Bind or input.UserInputType == Keybind.Bind then
			if keybindHeld then -- Only trigger if it was previously held by this keybind
				keybindHeld = false
				if Keybind.Settings.onBindHeld then
					pcall(Keybind.Settings.onBindHeld, false, Keybind.Bind)
				end
			end
		end
	end)
	Keybind:_TrackConnection(globalInputConnBegan) -- Track these connections
	Keybind:_TrackConnection(globalInputConnEnded)

	function Keybind:GetKey() return Keybind.Bind end
	function Keybind:GetBind() return Keybind.Bind end -- Alias for config

	function Keybind:SetKey(key, skipCallback) -- skipCallback is not really used here as main callback is global
		if Keybind._Destroyed then return end
		local valid = false
		if key == nil then
			key = Enum.KeyCode.Unknown
			valid = true
		elseif key:IsA("EnumItem") then
			if key.EnumType == Enum.KeyCode or key.EnumType == Enum.UserInputType then
				valid = true
			end
		end

		if valid and key ~= Keybind.Bind then
			Keybind.Bind = key
			UpdateButtonText()
            -- Don't trigger main callback here, only onBinded if needed
			if Keybind.Settings.onBinded and not skipCallback then
				pcall(Keybind.Settings.onBinded, Keybind.Bind)
			end
		elseif not valid then
			warn("[MacLib] Keybind:SetKey - Invalid key provided:", key)
		end
	end
	function Keybind:Bind(key) Keybind:SetKey(key, true) end -- Alias for config

	function Keybind:Clear(skipCallback) Keybind:SetKey(nil, skipCallback) end
	function Keybind:Unbind() Keybind:SetKey(nil, true) end -- Alias for config

	function Keybind:UpdateName(newName) -- For config system
		if Keybind._Destroyed then return end
		Label.Text = newName
		Keybind.Settings.Name = newName
	end

	-- Override Destroy to ensure binding is stopped and global listeners disconnected
	local oldDestroy = Keybind.Destroy
	function Keybind:Destroy()
		if Keybind._Destroyed then return end -- Prevent double destroy
		if IsBinding then StopBinding(false) end
		-- Disconnecting globalInputConnBegan/Ended is handled by the base Destroy tracking Base._Connections
		oldDestroy(Keybind) -- Call base destroy
	end

	-- Initial setup
	UpdateButtonText()

	self:_AddChild(Keybind)
	return Keybind
end


function ContainerMixin:AddColorPicker(text, callback, initialColor, options, Flag)
	if self._Destroyed then return nil end
	options = options or {}
	local ColorPicker = CreateElementBase("ColorPicker")
	ColorPicker.Class = "Colorpicker" -- For config system
	ColorPicker.Settings = { Name = text, Callback = callback, Default = initialColor, Alpha = options.Alpha } -- Store settings
	if Flag then ColorPicker:SetFlag(Flag) end

	local initialAlpha = (options.Alpha and type(options.Alpha) == "number") and math.clamp(options.Alpha, 0, 1) or 0
	ColorPicker.Color = initialColor or Color3.new(1,1,1)
	ColorPicker.Alpha = initialAlpha -- Store alpha separately

	local height = MacLib.Sizes.ElementHeight -- Standard height for the trigger button part

	local Frame = Create("Frame", {
		Name = "ColorPickerFrame_" .. (options.NameSuffix or math.random(100,999)),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = options.LayoutOrder or 0,
		Visible = self:IsVisible(),
		Parent = self.ContentFrame or self._Instance,
	})
	ColorPicker._Instance = Frame

	local Label = Create("TextLabel", {
		Name = "ColorPickerLabel",
		Size = UDim2.new(0.6, -MacLib.Sizes.Spacing, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = (options.FontLabel and MacLib.Fonts[options.FontLabel] or MacLib.Fonts.Default).Font,
		TextSize = MacLib.Sizes.TextSize,
		TextColor3 = MacLib.Theme.Text,
		Text = text or "Color",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Visible = true,
		Parent = Frame,
	})

	-- Button to open the picker, shows color preview
	local ColorButton = Create("TextButton", {
		Name = "ColorButton",
		Size = UDim2.new(0.4, 0, 1, 0),
		Position = UDim2.new(0.6, MacLib.Sizes.Spacing, 0, 0),
		BackgroundColor3 = MacLib.Theme.Primary, -- Button background
		Text = "", AutoButtonColor = false,
		Visible = true,
		Parent = Frame,
	})
	AddOutline(ColorButton)

	-- Color Preview inside the button (checkerboard for alpha)
	local PreviewBG = Create("ImageLabel", {
		Name = "PreviewBG",
		Size = UDim2.new(1, -MacLib.Sizes.Padding, 1, -MacLib.Sizes.Padding), -- Smaller than button
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		Image = options.Alpha and assets.grid or "", -- Use grid only if alpha enabled
        ImageTransparency = options.Alpha and 0.5 or 1,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(8, 8),
		BackgroundColor3 = MacLib.Theme.Background, -- Fallback background
		BackgroundTransparency = 1, -- Let ColorDisplay show through
		ZIndex = ColorButton.ZIndex + 1,
		Visible = true,
		Parent = ColorButton,
	})

	local ColorDisplay = Create("Frame", {
		Name = "ColorDisplay",
		Size = UDim2.new(1, 0, 1, 0), -- Cover the BG
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = ColorPicker.Color,
		BackgroundTransparency = ColorPicker.Alpha,
		BorderSizePixel = 0,
		ZIndex = PreviewBG.ZIndex + 1,
		Visible = true,
		Parent = PreviewBG,
	})


	-- ///// Picker Popup Logic /////
	local PickerFrame = nil -- Created on demand

	local function DestroyPickerFrame()
		if PickerFrame and PickerFrame.Parent then
			pcall(PickerFrame.Destroy, PickerFrame)
		end
		PickerFrame = nil
        ColorPicker.IsPickerOpen = false -- Track state
        AddOutline(ColorButton, MacLib.Theme.Outline) -- Restore default outline
	end

	local function CreatePickerFrame()
		if PickerFrame then DestroyPickerFrame() end -- Destroy existing first

        ColorPicker.IsPickerOpen = true
		AddOutline(ColorButton, MacLib.Theme.OutlineActive) -- Highlight button when picker open

		PickerFrame = Create("Frame", {
			Name = "ColorPickerPopup",
			Size = UDim2.fromOffset(240, 280 + (options.Alpha and 30 or 0)), -- Width, Height (add space for alpha slider)
			Position = UDim2.fromOffset(ColorButton.AbsolutePosition.X, ColorButton.AbsolutePosition.Y + height), -- Position below button
			BackgroundColor3 = MacLib.Theme.Background,
			ClipsDescendants = true,
			ZIndex = Frame.ZIndex + 200, -- High ZIndex
			Visible = true,
			Parent = MacLib._ScreenGui, -- Parent to ScreenGui for layering
		})
		AddOutline(PickerFrame, MacLib.Theme.OutlineActive)
		AddPadding(PickerFrame, MacLib.Sizes.Padding)
		local pickerList = AddListLayout(PickerFrame, Enum.FillDirection.Vertical, MacLib.Sizes.Spacing)

		-- Close button or click-outside logic for popup? Let's use click-outside.
		-- Need a way to detect clicks outside PickerFrame AND ColorButton
		-- The global dropdown handler might work if we adapt it slightly or add another listener
		-- For simplicity now, maybe add a small close button? Or rely on user clicking confirm/cancel.

		-- Saturation/Value Box
		local SVBoxSize = 180
		local SVBox = Create("Frame", {
			Name = "SVBox",
			Size = UDim2.fromOffset(SVBoxSize, SVBoxSize),
			BackgroundColor3 = Color3.fromHSV(0, 1, 1), -- Initial Red
			ClipsDescendants = true,
			LayoutOrder = 1,
			Visible = true,
			Parent = PickerFrame,
		})
		AddOutline(SVBox)

		-- Value Gradient (Black overlay)
		local ValueGradient = Create("Frame", {
			Name = "ValueGradient",
			Size = UDim2.new(1,0,1,0), BackgroundColor3 = Color3.new(0,0,0),
			BackgroundTransparency = 0, BorderSizePixel=0, ZIndex = SVBox.ZIndex + 1, Visible = true, Parent = SVBox
		})
		local valGrad = Create("UIGradient", { Transparency = NumberSequence.new{NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)}, Parent = ValueGradient })

		-- Saturation Gradient (White overlay)
		local SatGradient = Create("Frame", {
			Name = "SatGradient",
			Size = UDim2.new(1,0,1,0), BackgroundColor3 = Color3.new(1,1,1),
			BackgroundTransparency = 0, BorderSizePixel=0, ZIndex = SVBox.ZIndex + 2, Visible = true, Parent = SVBox
		})
		local satGrad = Create("UIGradient", { Transparency = NumberSequence.new{NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)}, Rotation = 90, Parent = SatGradient })

		-- SV Picker Knob/Cursor
		local SVCursor = Create("Frame", {
			Name = "SVCursor",
			Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1,1,1), -- White initially, maybe change based on underlying color?
            BorderSizePixel = 1, BorderColor3 = Color3.new(0,0,0), -- Use border for contrast
			ZIndex = SVBox.ZIndex + 3, Visible = true, Parent = SVBox
		})
        -- No UICorner needed for sharp cursor

		-- Hue Slider
		local HueSliderFrame = Create("Frame", { Name = "HueSliderFrame", Size = UDim2.new(1, 0, 0, MacLib.Sizes.ElementHeight * 0.8), BackgroundTransparency = 1, LayoutOrder = 2, Visible = true, Parent = PickerFrame })
		local HueTrack = Create("Frame", { Name = "HueTrack", Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0,0,0.5, -4), BackgroundColor3 = Color3.new(0.5, 0.5, 0.5), Visible = true, Parent = HueSliderFrame })
		local HueGradient = Create("UIGradient", { -- Rainbow gradient
			Color = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.new(1,0,0)), ColorSequenceKeypoint.new(1/6, Color3.new(1,1,0)),
				ColorSequenceKeypoint.new(2/6, Color3.new(0,1,0)), ColorSequenceKeypoint.new(3/6, Color3.new(0,1,1)),
				ColorSequenceKeypoint.new(4/6, Color3.new(0,0,1)), ColorSequenceKeypoint.new(5/6, Color3.new(1,0,1)),
				ColorSequenceKeypoint.new(1, Color3.new(1,0,0))
			}, Parent = HueTrack
		})
		AddOutline(HueTrack)
		local HueKnob = Create("Frame", {
			Name = "HueKnob", Size = UDim2.fromOffset(6, MacLib.Sizes.ElementHeight), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = MacLib.Theme.Text, ZIndex = HueTrack.ZIndex + 1, Visible = true, Parent = HueTrack
		})
		AddOutline(HueKnob, MacLib.Theme.OutlineActive)

        -- Alpha Slider (Optional)
        local AlphaSliderFrame, AlphaTrack, AlphaKnob
        if options.Alpha then
            AlphaSliderFrame = Create("Frame", { Name = "AlphaSliderFrame", Size = UDim2.new(1, 0, 0, MacLib.Sizes.ElementHeight * 0.8), BackgroundTransparency = 1, LayoutOrder = 3, Visible = true, Parent = PickerFrame })
            AlphaTrack = Create("Frame", { Name = "AlphaTrack", Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0,0,0.5, -4), BackgroundColor3 = MacLib.Theme.Primary, ClipsDescendants = true, Visible = true, Parent = AlphaSliderFrame })
            AddOutline(AlphaTrack)
            -- Checkerboard background for alpha track
            local AlphaTrackBG = Create("ImageLabel", { Name="AlphaTrackBG", Size=UDim2.fromScale(1,1), Image=assets.grid, ScaleType=Enum.ScaleType.Tile, TileSize=UDim2.fromOffset(8,8), ImageTransparency=0.6, BackgroundTransparency=1, ZIndex=AlphaTrack.ZIndex-1, Visible=true, Parent=AlphaTrack})
            -- Gradient from transparent to opaque current color
            local AlphaGradient = Create("UIGradient", { Color = ColorSequence.new{ColorSequenceKeypoint.new(0,Color3.new(1,1,1)), ColorSequenceKeypoint.new(1,Color3.new(1,1,1))}, Transparency = NumberSequence.new{NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0)}, Parent = AlphaTrack })
            AlphaKnob = Create("Frame", { Name = "AlphaKnob", Size = UDim2.fromOffset(6, MacLib.Sizes.ElementHeight), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = MacLib.Theme.Text, ZIndex = AlphaTrack.ZIndex + 1, Visible = true, Parent = AlphaTrack })
		    AddOutline(AlphaKnob, MacLib.Theme.OutlineActive)
        end

		-- Input Fields (Optional, maybe add later for precision)
		-- ...

		-- Confirm / Cancel Buttons
        local ButtonFrame = Create("Frame", {Name="ButtonFrame", Size=UDim2.new(1,0,0,MacLib.Sizes.ElementHeight), BackgroundTransparency=1, LayoutOrder=5, Visible=true, Parent=PickerFrame})
        local btnList = AddListLayout(ButtonFrame, Enum.FillDirection.Horizontal, MacLib.Sizes.Spacing)
        btnList.HorizontalAlignment = Enum.HorizontalAlignment.Right

        local ConfirmButton = ContainerMixin.AddButton(self, "Confirm", function() -- Need self? No, use PickerFrame directly
            -- Apply color (already updated internally)
			if ColorPicker._Destroyed then DestroyPickerFrame(); return end
			ColorPicker.Color = Color3.fromHSV(ColorPicker.CurrentH, ColorPicker.CurrentS, ColorPicker.CurrentV)
			ColorPicker.Alpha = ColorPicker.CurrentA or 0
			ColorDisplay.BackgroundColor3 = ColorPicker.Color
			ColorDisplay.BackgroundTransparency = ColorPicker.Alpha

			if callback then
				pcall(callback, ColorPicker.Color, options.Alpha and ColorPicker.Alpha or nil)
			end
            DestroyPickerFrame()
        end, { Width = 70 }, nil) -- Create button directly
		if ConfirmButton then ConfirmButton:GetInstance().Parent = ButtonFrame end

        local CancelButton = ContainerMixin.AddButton(self, "Cancel", function()
            DestroyPickerFrame()
        end, { Width = 70 }, nil) -- Create button directly
		if CancelButton then CancelButton:GetInstance().Parent = ButtonFrame end


		-- ///// Picker Interaction Logic /////
		ColorPicker.CurrentH, ColorPicker.CurrentS, ColorPicker.CurrentV = ColorPicker.Color:ToHSV()
		ColorPicker.CurrentA = ColorPicker.Alpha

		local function UpdatePickerVisuals()
			if ColorPicker._Destroyed or not PickerFrame then return end
			local hueColor = Color3.fromHSV(ColorPicker.CurrentH, 1, 1)
			SVBox.BackgroundColor3 = hueColor

			local svX = ColorPicker.CurrentS
			local svY = 1 - ColorPicker.CurrentV
			SVCursor.Position = UDim2.new(svX, 0, svY, 0)
            -- Make cursor color contrasted
            local brightness = (ColorPicker.CurrentV > 0.5) and 0 or 1
            SVCursor.BackgroundColor3 = Color3.new(brightness, brightness, brightness)

			HueKnob.Position = UDim2.new(ColorPicker.CurrentH, 0, 0.5, 0)

            if options.Alpha then
                AlphaKnob.Position = UDim2.new(1 - ColorPicker.CurrentA, 0, 0.5, 0) -- Alpha 0 = transparent (right), Alpha 1 = opaque (left)
                AlphaTrack:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(hueColor) -- Update alpha gradient color
            end

			-- Update internal display immediately
			ColorDisplay.BackgroundColor3 = Color3.fromHSV(ColorPicker.CurrentH, ColorPicker.CurrentS, ColorPicker.CurrentV)
			ColorDisplay.BackgroundTransparency = ColorPicker.CurrentA
		end

		local SVDragging = false
		local HueDragging = false
        local AlphaDragging = false

		-- SV Box Interaction
		local SVInput = Create("TextButton", { Name="SVInput", Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Text="", ZIndex=SVBox.ZIndex+4, Visible=true, Parent=SVBox })
		local function HandleSVInput(input)
			if ColorPicker._Destroyed or not PickerFrame then return end
			local relPos = input.Position - SVBox.AbsolutePosition
			local size = SVBox.AbsoluteSize
            if size.X == 0 or size.Y == 0 then return end -- Avoid division by zero
			local sat = math.clamp(relPos.X / size.X, 0, 1)
			local val = 1 - math.clamp(relPos.Y / size.Y, 0, 1)
			ColorPicker.CurrentS = sat
			ColorPicker.CurrentV = val
			UpdatePickerVisuals()
		end
		ColorPicker:_TrackConnection(SVInput.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then SVDragging=true; HandleSVInput(input) end end))
		ColorPicker:_TrackConnection(SVInput.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then SVDragging=false; end end))
		ColorPicker:_TrackConnection(SVInput.InputChanged:Connect(function(input) if SVDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then HandleSVInput(input) end end))

		-- Hue Slider Interaction
		local HueInput = Create("TextButton", { Name="HueInput", Size=UDim2.new(1,MacLib.Sizes.SliderKnobSize,1,0), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5), BackgroundTransparency=1, Text="", ZIndex=HueKnob.ZIndex+1, Visible=true, Parent=HueTrack })
		local function HandleHueInput(input)
			if ColorPicker._Destroyed or not PickerFrame then return end
			local relX = input.Position.X - HueTrack.AbsolutePosition.X
			local sizeX = HueTrack.AbsoluteSize.X
            if sizeX == 0 then return end
			local hue = math.clamp(relX / sizeX, 0, 1)
			ColorPicker.CurrentH = hue
			UpdatePickerVisuals()
		end
		ColorPicker:_TrackConnection(HueInput.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then HueDragging=true; HandleHueInput(input) end end))
		ColorPicker:_TrackConnection(HueInput.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then HueDragging=false; end end))
		ColorPicker:_TrackConnection(HueInput.InputChanged:Connect(function(input) if HueDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then HandleHueInput(input) end end))

        -- Alpha Slider Interaction (if exists)
        if options.Alpha then
            local AlphaInput = Create("TextButton", { Name="AlphaInput", Size=UDim2.new(1,MacLib.Sizes.SliderKnobSize,1,0), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5), BackgroundTransparency=1, Text="", ZIndex=AlphaKnob.ZIndex+1, Visible=true, Parent=AlphaTrack })
            local function HandleAlphaInput(input)
				if ColorPicker._Destroyed or not PickerFrame then return end
                local relX = input.Position.X - AlphaTrack.AbsolutePosition.X
                local sizeX = AlphaTrack.AbsoluteSize.X
                if sizeX == 0 then return end
                local alpha = 1 - math.clamp(relX / sizeX, 0, 1) -- Inverted: left=1, right=0
                ColorPicker.CurrentA = alpha
                UpdatePickerVisuals()
            end
            ColorPicker:_TrackConnection(AlphaInput.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then AlphaDragging=true; HandleAlphaInput(input) end end))
            ColorPicker:_TrackConnection(AlphaInput.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then AlphaDragging=false; end end))
            ColorPicker:_TrackConnection(AlphaInput.InputChanged:Connect(function(input) if AlphaDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then HandleAlphaInput(input) end end))
        end

		-- Initial visual setup
		UpdatePickerVisuals()

        -- Add click outside to close logic
		ColorPicker:_TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
			if ColorPicker.IsPickerOpen and not gameProcessedEvent and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				local mousePos = UserInputService:GetMouseLocation()
                local pickerPos = PickerFrame and PickerFrame.AbsolutePosition
                local pickerSize = PickerFrame and PickerFrame.AbsoluteSize
                local buttonPos = ColorButton.AbsolutePosition
                local buttonSize = ColorButton.AbsoluteSize

                local clickedInButton = (mousePos.X >= buttonPos.X and mousePos.X <= buttonPos.X + buttonSize.X and
									   mousePos.Y >= buttonPos.Y and mousePos.Y <= buttonPos.Y + buttonSize.Y)

                local clickedInPicker = false
                if pickerPos and pickerSize then
                    clickedInPicker = (mousePos.X >= pickerPos.X and mousePos.X <= pickerPos.X + pickerSize.X and
									 mousePos.Y >= pickerPos.Y and mousePos.Y <= pickerPos.Y + pickerSize.Y)
                end

				if not clickedInButton and not clickedInPicker then
					DestroyPickerFrame()
				end
			end
		end))
	end

	-- Button action: Open the picker
	ColorPicker:_TrackConnection(ColorButton.MouseButton1Click:Connect(function()
		if ColorPicker._Destroyed then return end
		if ColorPicker.IsPickerOpen then
			DestroyPickerFrame()
		else
			CreatePickerFrame()
		end
	end))

	function ColorPicker:GetColor() return ColorPicker.Color end
	function ColorPicker:GetAlpha() return ColorPicker.Alpha end

	function ColorPicker:SetColor(color3, skipCallback)
		if ColorPicker._Destroyed then return end
		ColorPicker.Color = color3 or Color3.new(1,1,1)
        ColorPicker.CurrentH, ColorPicker.CurrentS, ColorPicker.CurrentV = ColorPicker.Color:ToHSV()
		ColorDisplay.BackgroundColor3 = ColorPicker.Color
        if ColorPicker.IsPickerOpen and PickerFrame then UpdatePickerVisuals() end -- Update picker if open
		if callback and not skipCallback then
			pcall(callback, ColorPicker.Color, options.Alpha and ColorPicker.Alpha or nil)
		end
	end

	function ColorPicker:SetAlpha(alphaValue, skipCallback)
		if ColorPicker._Destroyed or not options.Alpha then return end
		ColorPicker.Alpha = math.clamp(alphaValue or 0, 0, 1)
        ColorPicker.CurrentA = ColorPicker.Alpha
		ColorDisplay.BackgroundTransparency = ColorPicker.Alpha
        if ColorPicker.IsPickerOpen and PickerFrame then UpdatePickerVisuals() end -- Update picker if open
		if callback and not skipCallback then
			pcall(callback, ColorPicker.Color, ColorPicker.Alpha)
		end
	end

	function ColorPicker:UpdateName(newName) -- For config system
		if ColorPicker._Destroyed then return end
		Label.Text = newName
		ColorPicker.Settings.Name = newName
	end

	-- Override Destroy to close picker
	local oldDestroy = ColorPicker.Destroy
	function ColorPicker:Destroy()
		if ColorPicker._Destroyed then return end
		DestroyPickerFrame() -- Ensure picker is closed
		oldDestroy(ColorPicker)
	end


	self:_AddChild(ColorPicker)
	return ColorPicker
end


--// Main Window Function (Adapted from original MacLib, but using Flat UI principles)
function MacLib:Window(Settings)
	if MacLib._Unloaded then warn("MacLib is unloaded, cannot create window."); return nil end
	Settings = Settings or {}
	local WindowFunctions = { Settings = Settings } -- Keep this pattern
	local WindowElement = CreateElementBase("Window") -- Use base element pattern

	-- Use MacLib Theme/Sizes/Fonts
	local Theme = MacLib.Theme
	local Sizes = MacLib.Sizes
	local Fonts = MacLib.Fonts

	local windowSize = Settings.Size or UDim2.fromOffset(500, 400) -- Default size
	local windowPos = Settings.Position or UDim2.new(0.5, -windowSize.Offset.X / 2, 0.5, -windowSize.Offset.Y / 2) -- Default center

	local screenGui = GetGui()
	if not screenGui then return nil end -- Stop if GUI couldn't be created

	local base = Create("Frame", {
		Name = "Window_" .. (Settings.Title or "Untitled"),
		Size = windowSize,
		Position = windowPos,
		AnchorPoint = Vector2.new(0, 0), -- Top-left anchor is simpler
		BackgroundColor3 = Theme.Background,
		ClipsDescendants = true,
		ZIndex = MacLib._TopZIndex,
		Visible = true, -- Start visible by default
		Parent = screenGui,
	})
	WindowElement._Instance = base
	AddOutline(base, Theme.OutlineActive) -- Use active outline for window border

	-- Flat Title Bar
	local titleBar = Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, Sizes.TitlebarHeight),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Theme.Titlebar,
		ZIndex = base.ZIndex + 1,
		Visible = true,
		Parent = base,
	})
	-- No outline needed if it fills the top, or add thin bottom outline? Add bottom outline.
	local titleBarOutline = AddOutline(titleBar, Theme.Outline)
    titleBarOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual -- Apply only bottom border visually? No, Border is simpler.


	local titleLabel = Create("TextLabel", {
		Name = "TitleLabel",
		Size = UDim2.new(1, -(Sizes.Padding * 2 + Sizes.ElementHeight), 1, 0), -- Leave space for close button + padding
		Position = UDim2.fromOffset(Sizes.Padding, 0),
		BackgroundTransparency = 1,
		Font = Fonts.Default.Font,
		FontSize = Sizes.TextSize + 1,
		TextColor3 = Theme.Text,
		Text = Settings.Title or "Window",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = titleBar.ZIndex + 1,
		Visible = true,
		Parent = titleBar,
	})

	-- Flat Close Button
	local closeButton = Create("TextButton", {
		Name = "CloseButton",
		Size = UDim2.fromOffset(Sizes.ElementHeight * 0.8, Sizes.ElementHeight * 0.8),
		Position = UDim2.new(1, -Sizes.Padding - (Sizes.ElementHeight * 0.8), 0.5, -(Sizes.ElementHeight * 0.8)/2),
		BackgroundColor3 = Theme.Primary, BackgroundTransparency = 0,
		TextColor3 = Theme.Text, Font = Fonts.Default.Font,
		Text = "X", FontSize = Sizes.TextSize,
		ZIndex = titleBar.ZIndex + 1,
		Visible = true,
		Parent = titleBar,
	})
	AddOutline(closeButton)
	WindowElement:_TrackConnection(closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = Theme.Error end))
	WindowElement:_TrackConnection(closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = Theme.Primary end))
	WindowElement:_TrackConnection(closeButton.MouseButton1Click:Connect(function()
		-- Decide: Destroy window or just hide? Original MacLib had ToggleMenu. Let's destroy for now.
		-- Could add a setting for this later.
        if Settings.onClose then
            local success, shouldDestroy = pcall(Settings.onClose)
            if success and shouldDestroy == false then -- Allow callback to prevent closing
                return
            end
        end
		WindowElement:Destroy()
	end))

	-- Content Area
	local contentFrame = Create("Frame", {
		Name = "ContentFrame",
		Size = UDim2.new(1, 0, 1, -Sizes.TitlebarHeight),
		Position = UDim2.fromOffset(0, Sizes.TitlebarHeight),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = base.ZIndex,
		Visible = true,
		Parent = base,
	})
	WindowElement.ContentFrame = contentFrame -- Assign for direct use if no tabs
	WindowElement.Tabs = {} -- Store tab objects
	WindowElement.TabButtonsFrame = nil -- Frame for tab buttons (created on demand)
	WindowElement.CurrentTab = nil -- Currently selected tab object

	-- Dragging Logic
	local Dragging = false
	local DragStart = nil
	local StartPos = nil
	WindowElement:_TrackConnection(titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Dragging = true
			DragStart = input.Position
			StartPos = base.Position
			MacLib._DraggingInfo.Active = true
			FocusWindow(WindowElement)

			MacLib._DraggingInfo.MoveConn = UserInputService.InputChanged:Connect(function(moveInput)
				if moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch then
					if Dragging then
						local Delta = moveInput.Position - DragStart
						base.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
					end
				end
			end)
			MacLib._DraggingInfo.EndConn = UserInputService.InputEnded:Connect(function(endInput)
				if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
					Dragging = false
					MacLib._DraggingInfo.Active = false
					if MacLib._DraggingInfo.MoveConn then MacLib._DraggingInfo.MoveConn:Disconnect(); MacLib._DraggingInfo.MoveConn = nil end
					if MacLib._DraggingInfo.EndConn then MacLib._DraggingInfo.EndConn:Disconnect(); MacLib._DraggingInfo.EndConn = nil end
				end
			end)
            TrackConnection(MacLib._DraggingInfo.MoveConn) -- Track these temporary global connections
            TrackConnection(MacLib._DraggingInfo.EndConn)
		end
	end))

	-- Bring window to front on any click inside it
	WindowElement:_TrackConnection(base.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not MacLib._DraggingInfo.Active then
			FocusWindow(WindowElement)
		end
	end))

	-- Focus window initially
	FocusWindow(WindowElement)

	-- ///// Window Public Methods /////

	-- Method to Add Tabs (Flat Style)
	function WindowFunctions:AddTab(tabName, options) -- Changed signature from original MacLib
        if WindowElement._Destroyed then return nil end
		options = options or {}
		local tabOrder = options.LayoutOrder or (#WindowElement.Tabs + 1)

		if not WindowElement.TabButtonsFrame then
			-- Create Tab Button Container (only if needed)
			WindowElement.TabButtonsFrame = Create("Frame", {
				Name = "TabButtonsFrame",
				Size = UDim2.new(1, 0, 0, Sizes.ElementHeight + Sizes.Padding), -- Height for buttons + some padding
				Position = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1, -- Transparent background
				ZIndex = contentFrame.ZIndex + 1, -- Above content
				Parent = contentFrame, -- Parent to main content area initially
			})
			local btnFramePadding = AddPadding(WindowElement.TabButtonsFrame, Sizes.Padding / 2)
			btnFramePadding.PaddingBottom = UDim.new(0,0) -- Only pad top/sides
			local list = AddListLayout(WindowElement.TabButtonsFrame, Enum.FillDirection.Horizontal, Sizes.Spacing)
			list.VerticalAlignment = Enum.VerticalAlignment.Bottom -- Align buttons to bottom

			-- Adjust main content frame position and size to be below tabs
			contentFrame.Position = UDim2.fromOffset(0, Sizes.TitlebarHeight + WindowElement.TabButtonsFrame.AbsoluteSize.Y)
			contentFrame.Size = UDim2.new(1, 0, 1, -(Sizes.TitlebarHeight + WindowElement.TabButtonsFrame.AbsoluteSize.Y))
		end

		-- Create Tab Element using Base Class
		local Tab = CreateElementBase("Tab")
		Tab.Name = tabName
        Tab.Settings = { Name = tabName } -- For compatibility if needed?

		-- Tab Content Frame (actual container for elements)
		local TabContent = Create("ScrollingFrame", { -- Use ScrollingFrame for content
			Name = "TabContent_"..tabName,
			Size = UDim2.new(1, 0, 1, 0), -- Takes full space of adjusted ContentFrame
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Visible = false, -- Initially hidden
            AutomaticCanvasSize = Enum.AutomaticSize.Y, -- Auto scroll vertically
			ScrollBarThickness = Sizes.ScrollbarThickness, ScrollBarImageColor3 = Theme.Accent,
            BorderSizePixel = 0,
			Parent = contentFrame, -- Parented to the main content area
		})
		AddPadding(TabContent, Sizes.Padding)
		AddListLayout(TabContent, Enum.FillDirection.Vertical, Sizes.Spacing)
		Tab._Instance = TabContent -- The actual container instance
		Tab.ContentFrame = TabContent -- Expose for adding elements

		-- Tab Button (Flat Style)
		local TabButton = Create("TextButton", {
			Name = "TabButton_"..tabName,
			Size = UDim2.new(0, 0, 1, 0), -- Size determined by text + padding
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Primary,
			TextColor3 = Theme.TextDisabled,
			Font = Fonts.Default.Font, TextSize = Sizes.TextSize,
			Text = tabName, AutoButtonColor = false,
			ZIndex = WindowElement.TabButtonsFrame.ZIndex + 1,
			LayoutOrder = tabOrder,
			Visible = true,
			Parent = WindowElement.TabButtonsFrame,
		})
		local textBounds = TextService and TextService:GetTextSize(tabName, Sizes.TextSize, Fonts.Default.Font, Vector2.new(math.huge, Sizes.ElementHeight)) or Vector2.new(50, Sizes.ElementHeight)
		TabButton.Size = UDim2.new(0, textBounds.X + Sizes.Padding * 2, 1, 0) -- Set size based on text
		AddOutline(TabButton)

		Tab.Button = TabButton -- Reference to the button

		local function SelectTab()
            if WindowElement._Destroyed or WindowElement.CurrentTab == Tab then return end -- Already selected or destroyed

			-- Deselect previous tab
			if WindowElement.CurrentTab then
				WindowElement.CurrentTab.Button.BackgroundColor3 = Theme.Primary
				WindowElement.CurrentTab.Button.TextColor3 = Theme.TextDisabled
				WindowElement.CurrentTab._Instance.Visible = false
				local oldOutline = WindowElement.CurrentTab.Button:FindFirstChild("UIStroke_Outline")
				if oldOutline then oldOutline.Color = Theme.Outline end
			end

			-- Select this tab
			TabButton.BackgroundColor3 = Theme.Secondary -- Active tab button look
			TabButton.TextColor3 = Theme.Text
			Tab._Instance.Visible = true -- Show content
			local newOutline = TabButton:FindFirstChild("UIStroke_Outline")
			if newOutline then newOutline.Color = Theme.OutlineActive end
			WindowElement.CurrentTab = Tab

			-- Optional: Update window title/subtitle if tab has them?
			-- if Tab.Settings.Title then WindowFunctions:UpdateTitle(Tab.Settings.Title) end
		end

		Tab:_TrackConnection(TabButton.MouseButton1Click:Connect(SelectTab))
		Tab:_TrackConnection(TabButton.MouseEnter:Connect(function() if WindowElement.CurrentTab ~= Tab then TabButton.BackgroundColor3 = Theme.Secondary end end))
		Tab:_TrackConnection(TabButton.MouseLeave:Connect(function() if WindowElement.CurrentTab ~= Tab then TabButton.BackgroundColor3 = Theme.Primary end end))

		table.insert(WindowElement.Tabs, Tab)
		WindowElement:_AddChild(Tab) -- Track as library child

		-- Apply Container Mixin methods to this Tab object
        Tab.AddLabel = ContainerMixin.AddLabel
        Tab.AddButton = ContainerMixin.AddButton
        Tab.AddCheckbox = ContainerMixin.AddCheckbox
        Tab.AddSlider = ContainerMixin.AddSlider
        Tab.AddDropdown = ContainerMixin.AddDropdown
        Tab.AddTextInput = ContainerMixin.AddTextInput
        Tab.AddKeybind = ContainerMixin.AddKeybind
        Tab.AddColorPicker = ContainerMixin.AddColorPicker
		Tab.Section = ContainerMixin.Section -- Add Section alias if needed

		-- Select the first tab automatically
		if #WindowElement.Tabs == 1 then
			SelectTab()
		end

		return Tab -- Return the Tab object
	end

    -- Method to Add Sections (Mimics original MacLib structure if needed)
    function ContainerMixin:Section(options, Flag) -- Add Section function to the mixin
        if self._Destroyed then return nil end
        options = options or {}
        local Section = CreateElementBase("Section")
        Section.Class = "Section" -- Not really used by config, but for structure
		if Flag then Section:SetFlag(Flag) end -- Allow flagging sections if desired

        local sectionFrame = Create("Frame", {
            Name = "Section_" .. (options.Name or math.random(100,999)),
            Size = UDim2.new(1, 0, 0, 0), -- Height determined by content
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Primary, -- Slightly different background for sections? Or same as window? Let's use Primary.
            BackgroundTransparency = 0, -- Not transparent
            LayoutOrder = options.LayoutOrder or 0,
			Visible = self:IsVisible(),
            Parent = self.ContentFrame or self._Instance, -- Parent to the container (Tab, Window, or another Section)
        })
        AddOutline(sectionFrame, Theme.Outline)
        AddPadding(sectionFrame, Sizes.Padding)
        AddListLayout(sectionFrame, Enum.FillDirection.Vertical, Sizes.Spacing)

        Section._Instance = sectionFrame
        Section.ContentFrame = sectionFrame -- Elements added directly to the section frame

        -- Apply Container Mixin methods to the Section object, allowing nested elements
        Section.AddLabel = ContainerMixin.AddLabel
        Section.AddButton = ContainerMixin.AddButton
        Section.AddCheckbox = ContainerMixin.AddCheckbox
        Section.AddSlider = ContainerMixin.AddSlider
        Section.AddDropdown = ContainerMixin.AddDropdown
        Section.AddTextInput = ContainerMixin.AddTextInput
        Section.AddKeybind = ContainerMixin.AddKeybind
        Section.AddColorPicker = ContainerMixin.AddColorPicker
		Section.Section = ContainerMixin.Section -- Allow nested sections

		-- Add header if specified
		if options.Name then
			Section:AddLabel(options.Name, { TextSize = Sizes.TextSize + 2, Color = Theme.Text }) -- Simple header label
			-- Add divider below header
			local divider = Create("Frame", { Name="Divider", Size=UDim2.new(1,0,0,1), BackgroundColor3=Theme.Outline, LayoutOrder = 1, Parent=sectionFrame})
		end

        self:_AddChild(Section)
        return Section
    end
    -- Add Section to the main WindowFunctions as well
    WindowFunctions.Section = ContainerMixin.Section


	-- If no tabs are used, apply ContainerMixin to the Window itself
	if not WindowElement.AddLabel then
		WindowElement.AddLabel = ContainerMixin.AddLabel
		WindowElement.AddButton = ContainerMixin.AddButton
		WindowElement.AddCheckbox = ContainerMixin.AddCheckbox
		WindowElement.AddSlider = ContainerMixin.AddSlider
		WindowElement.AddDropdown = ContainerMixin.AddDropdown
		WindowElement.AddTextInput = ContainerMixin.AddTextInput
		WindowElement.AddKeybind = ContainerMixin.AddKeybind
		WindowElement.AddColorPicker = ContainerMixin.AddColorPicker
		WindowElement.Section = ContainerMixin.Section
	end

	-- Add other WindowFunctions from original MacLib (adapted)
	function WindowFunctions:UpdateTitle(NewTitle)
		if WindowElement._Destroyed then return end
		titleLabel.Text = NewTitle
		WindowFunctions.Settings.Title = NewTitle
	end
	-- No subtitle in this flat design's title bar
	-- function WindowFunctions:UpdateSubtitle(NewSubtitle) end

	-- Notification System (Adapted from Flat UI principles)
	local notificationContainer = nil
	function WindowFunctions:Notify(notifySettings)
		if WindowElement._Destroyed or MacLib._Unloaded then return nil end
		notifySettings = notifySettings or {}

		if not notificationContainer or not notificationContainer.Parent then
			notificationContainer = Create("Frame", {
				Name = "NotificationsContainer",
				Size = UDim2.new(0, 300, 1, 0), -- Fixed width, full height
				Position = UDim2.new(1, -310, 0, 10), -- Top right corner (adjust padding)
				BackgroundTransparency = 1,
				ZIndex = MacLib._TopZIndex + 1000, -- Very high ZIndex
				Parent = MacLib._ScreenGui,
			})
			local list = AddListLayout(notificationContainer, Enum.FillDirection.Vertical, Sizes.Spacing)
			list.HorizontalAlignment = Enum.HorizontalAlignment.Right
			list.VerticalAlignment = Enum.VerticalAlignment.Top
		end

		local NotifyElement = CreateElementBase("Notification") -- Track internally if needed

		local notifFrame = Create("Frame", {
			Name = "Notification",
			Size = UDim2.new(1, 0, 0, 0), -- Width 100%, auto height
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Primary,
			BackgroundTransparency = 0.1, -- Slightly transparent
			Visible = true,
			Parent = notificationContainer,
		})
		AddOutline(notifFrame, Theme.OutlineActive)
		AddPadding(notifFrame, Sizes.Padding)
		local notifList = AddListLayout(notifFrame, Enum.FillDirection.Vertical, Sizes.Spacing / 2)
		NotifyElement._Instance = notifFrame

		if notifySettings.Title then
			local title = Create("TextLabel", {
				Name = "NotifyTitle", Size = UDim2.new(1,0,0,Sizes.TextSize + 2), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency=1,
				Font = Fonts.Default.Font, TextSize = Sizes.TextSize + 1, TextColor3 = Theme.Text, Text = notifySettings.Title,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = notifFrame
			})
		end
		if notifySettings.Description then
			local desc = Create("TextLabel", {
				Name = "NotifyDesc", Size = UDim2.new(1,0,0,Sizes.TextSize), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency=1,
				Font = Fonts.Default.Font, TextSize = Sizes.TextSize -1, TextColor3 = Theme.TextDisabled, Text = notifySettings.Description,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = notifFrame
			})
		end

		-- Auto-destroy logic
		local lifetime = notifySettings.Lifetime or 5
		if lifetime > 0 then
			local startTime = tick()
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not NotifyElement or NotifyElement._Destroyed then
					if conn then conn:Disconnect() end
					return
				end
				if tick() - startTime >= lifetime then
					NotifyElement:Destroy() -- Destroy the notification element
					if conn then conn:Disconnect() end
				end
			end)
			NotifyElement:_TrackConnection(conn) -- Track the self-destruct connection
		end

		-- Return an object to potentially cancel/update?
		local NotifyFunctions = {}
		function NotifyFunctions:Cancel()
			if NotifyElement then NotifyElement:Destroy() end
		end
		return NotifyFunctions
	end

	-- Dialog System (Adapted from Flat UI principles)
	function WindowFunctions:Dialog(dialogSettings)
		if WindowElement._Destroyed or MacLib._Unloaded then return nil end
		dialogSettings = dialogSettings or {}

		-- Create Modal Overlay
		local overlay = Create("Frame", {
			Name = "DialogOverlay",
			Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0,0),
			BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.5,
			ZIndex = MacLib._TopZIndex + 500, -- Above window, below notifications
			Parent = MacLib._ScreenGui,
		})

		-- Dialog Frame
		local dialogWidth = dialogSettings.Width or 350
		local dialogFrame = Create("Frame", {
			Name = "DialogFrame",
			Size = UDim2.new(0, dialogWidth, 0, 0), -- Fixed width, auto height
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0.5, -dialogWidth/2, 0.4, 0), -- Centered-ish horizontally, slightly above vertical center
			AnchorPoint = Vector2.new(0, 0), -- Top-left anchor
			BackgroundColor3 = Theme.Background,
			Visible = true,
			Parent = overlay,
		})
		AddOutline(dialogFrame, Theme.OutlineActive)
		AddPadding(dialogFrame, Sizes.Padding * 1.5) -- More padding for dialogs
		local dialogList = AddListLayout(dialogFrame, Enum.FillDirection.Vertical, Sizes.Spacing)

		-- Title
		if dialogSettings.Title then
			local title = Create("TextLabel", {
				Name = "DialogTitle", Size = UDim2.new(1,0,0,Sizes.TextSize + 4), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency=1,
				Font = Fonts.Default.Font, TextSize = Sizes.TextSize + 2, TextColor3 = Theme.Text, Text = dialogSettings.Title,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = dialogFrame
			})
		end

		-- Description
		if dialogSettings.Description then
			local desc = Create("TextLabel", {
				Name = "DialogDesc", Size = UDim2.new(1,0,0,Sizes.TextSize), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency=1,
				Font = Fonts.Default.Font, TextSize = Sizes.TextSize, TextColor3 = Theme.TextDisabled, Text = dialogSettings.Description,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = dialogFrame
			})
            desc.LayoutOrder = 1
		end

        -- Divider
        local divider = Create("Frame", { Name="Divider", Size=UDim2.new(1,0,0,1), BackgroundColor3=Theme.Outline, LayoutOrder = 5, Parent=dialogFrame})


		-- Buttons
		local buttonFrame = Create("Frame", {
			Name = "DialogButtonFrame", Size = UDim2.new(1, 0, 0, Sizes.ElementHeight), BackgroundTransparency = 1,
			LayoutOrder = 10, Parent = dialogFrame
		})
		local buttonList = AddListLayout(buttonFrame, Enum.FillDirection.Horizontal, Sizes.Spacing)
		buttonList.HorizontalAlignment = Enum.HorizontalAlignment.Right -- Align buttons right

		local DialogElement = CreateElementBase("Dialog") -- For tracking connections/cleanup

		local function closeDialog()
			DialogElement:Destroy() -- Destroy the element, which cleans up instance and connections
		end

		if dialogSettings.Buttons then
			for i, btnInfo in ipairs(dialogSettings.Buttons) do
				local btn = ContainerMixin.AddButton(DialogElement, btnInfo.Name, function()
					closeDialog() -- Close dialog first
					if btnInfo.Callback then pcall(btnInfo.Callback) end -- Then run callback
				end, { Width = 80 }, nil) -- Create button using mixin
				if btn then
                    btn:GetInstance().Parent = buttonFrame
                    btn:GetInstance().LayoutOrder = i
                end
			end
		else -- Default OK button if none provided
			local okBtn = ContainerMixin.AddButton(DialogElement, "OK", closeDialog, { Width = 80 }, nil)
			if okBtn then
                okBtn:GetInstance().Parent = buttonFrame
                okBtn:GetInstance().LayoutOrder = 1
            end
		end

		-- Add overlay close functionality? Usually dialogs require explicit button press.
		-- DialogElement:_TrackConnection(overlay.MouseButton1Click:Connect(closeDialog)) -- Uncomment to allow closing by clicking overlay

        -- Make overlay destroy the DialogElement
        function DialogElement:Destroy()
			if DialogElement._Destroyed then return end
			DialogElement._Destroyed = true
            -- Base destroy called via loop below
			if overlay and overlay.Parent then pcall(overlay.Destroy, overlay) end
			overlay = nil
			dialogFrame = nil -- Nil out refs
			-- Call base destroy logic for connections etc.
            for k, v in pairs(DialogElement) do
                if type(v) == "function" and k:find("^_") then -- Disconnect tracked connections
                    -- Base class handles this now
                end
            end
            UntrackElement(DialogElement)
            -- Base class handles clearing fields
            local oldBaseDestroy = CreateElementBase("").Destroy -- Get base destroy
            oldBaseDestroy(DialogElement) -- Call base destroy without recreating it
		end


		return { Cancel = closeDialog } -- Return object to cancel dialog
	end

	-- Other original MacLib window functions adapted or removed
	WindowFunctions.SetState = function(visible) WindowElement:SetVisibility(visible) end -- Simple visibility toggle
	WindowFunctions.GetState = function() return WindowElement:IsVisible() end
	WindowFunctions.Unload = function() WindowElement:Destroy() end -- Use Destroy for cleanup
	WindowFunctions.onUnloaded = function(callback) WindowElement.onUnloadCallback = callback end -- Store callback on element

    -- Removed Set/Get AcrylicBlurState, Set/Get UserInfoState, Set/Get Size, Set/Get Scale as they don't fit the flat design or are handled differently.

	-- Apply the main callback *after* the Window element and its methods are defined
    local oldDestroy = WindowElement.Destroy
    function WindowElement:Destroy()
        if WindowElement._Destroyed then return end
        if WindowElement.onUnloadCallback then pcall(WindowElement.onUnloadCallback) end
        oldDestroy(WindowElement) -- Call original destroy
    end


	return WindowFunctions
end


--// Config System (Adapted from original MacLib)
MacLib.ClassParser = {
	["Toggle"] = { -- Covers Checkboxes now
		Save = function(Flag, data) return { type = "Toggle", flag = Flag, state = data.State } end,
		Load = function(Flag, data) if MacLib.Options[Flag] and MacLib.Options[Flag].UpdateState then pcall(MacLib.Options[Flag].UpdateState, MacLib.Options[Flag], data.state) end end
	},
	["Slider"] = {
		Save = function(Flag, data) return { type = "Slider", flag = Flag, value = data.Value } end,
		Load = function(Flag, data) if MacLib.Options[Flag] and MacLib.Options[Flag].UpdateValue then pcall(MacLib.Options[Flag].UpdateValue, MacLib.Options[Flag], data.value) end end
	},
	["Input"] = {
		Save = function(Flag, data) return { type = "Input", flag = Flag, text = data.Text } end,
		Load = function(Flag, data) if MacLib.Options[Flag] and MacLib.Options[Flag].UpdateText then pcall(MacLib.Options[Flag].UpdateText, MacLib.Options[Flag], data.text) end end
	},
	["Keybind"] = {
		Save = function(Flag, data) return { type = "Keybind", flag = Flag, bind = (data.Bind and data.Bind ~= Enum.KeyCode.Unknown and data.Bind.Name) or nil } end,
		Load = function(Flag, data) if MacLib.Options[Flag] and MacLib.Options[Flag].Bind then local key = data.bind and (Enum.KeyCode[data.bind] or Enum.UserInputType[data.bind]) pcall(MacLib.Options[Flag].Bind, MacLib.Options[Flag], key or Enum.KeyCode.Unknown) end end
	},
	["Dropdown"] = {
		Save = function(Flag, data) return { type = "Dropdown", flag = Flag, value = data.Value } end, -- Value is table if multi, string/value if single
		Load = function(Flag, data) if MacLib.Options[Flag] and MacLib.Options[Flag].UpdateSelection then pcall(MacLib.Options[Flag].UpdateSelection, MacLib.Options[Flag], data.value) end end
	},
	["Colorpicker"] = {
		Save = function(Flag, data)
			local colorHex = data.Color and string.format("#%02X%02X%02X", math.floor(data.Color.R * 255 + 0.5), math.floor(data.Color.G * 255 + 0.5), math.floor(data.Color.B * 255 + 0.5)) or nil
			return { type = "Colorpicker", flag = Flag, color = colorHex, alpha = data.Settings.Alpha and data.Alpha or nil }
		end,
		Load = function(Flag, data)
			if MacLib.Options[Flag] then
				if data.color then
					local success, r, g, b = pcall(function()
						local hex = data.color:gsub("#","")
						return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
					end)
					if success and r then
						pcall(MacLib.Options[Flag].SetColor, MacLib.Options[Flag], Color3.fromRGB(r, g, b))
					end
				end
				if data.alpha ~= nil and MacLib.Options[Flag].SetAlpha then
					pcall(MacLib.Options[Flag].SetAlpha, MacLib.Options[Flag], data.alpha)
				end
			end
		end
	}
}

local function BuildFolderTree()
	if isStudio or not (isfolder and makefolder) then warn("MacLib: Config system unavailable in this environment."); return false end
	local success = pcall(function()
		if not isfolder(MacLib.Folder) then makefolder(MacLib.Folder) end
		local settingsFolder = MacLib.Folder .. "/settings"
		if not isfolder(settingsFolder) then makefolder(settingsFolder) end
	end)
	if not success then warn("MacLib: Failed to build folder tree.") end
	return success
end

function MacLib:LoadAutoLoadConfig()
	if isStudio or not (isfile and readfile) then return false end
	local autoloadFile = MacLib.Folder .. "/settings/autoload.txt"
	if isfile(autoloadFile) then
		local name = readfile(autoloadFile)
		if name and name:gsub("%s", "") ~= "" then
			local success, err = self:LoadConfig(name)
			if not success then
				warn("MacLib: Error loading autoload config '"..name.."':", err)
				-- Optionally notify user via UI if a window exists
			else
				print("MacLib: Autoloaded config:", name)
			end
            return success
		end
	end
    return false
end

function MacLib:SetFolder(folderName)
	if isStudio then warn("MacLib: Cannot set folder in Studio."); return end
	MacLib.Folder = folderName or "MacLib_Flat"
	BuildFolderTree()
end

function MacLib:SaveConfig(path)
	if isStudio or not writefile then warn("MacLib: Saving unavailable."); return false, "Saving unavailable." end
	if not path or path:gsub("%s", "") == "" then return false, "Invalid config path." end

	if not BuildFolderTree() then return false, "Failed to ensure directory exists." end
	local fullPath = MacLib.Folder .. "/settings/" .. path .. ".json"

	local dataToSave = { objects = {} }
	for flag, element in pairs(MacLib.Options) do
		if element and element.Class and MacLib.ClassParser[element.Class] and MacLib.ClassParser[element.Class].Save then
            if not element.IgnoreConfig then -- Check IgnoreConfig flag if it exists
			    local success, savedData = pcall(MacLib.ClassParser[element.Class].Save, flag, element)
			    if success and savedData then
				    table.insert(dataToSave.objects, savedData)
			    else
				    warn("MacLib: Failed to save data for flag '", flag, "' - Element Class:", element.Class)
			    end
            end
		else
			warn("MacLib: Skipping save for flag '", flag, "' - No Class or Save method found.")
		end
	end

	local success, encodedData = pcall(HttpService.JSONEncode, HttpService, dataToSave)
	if not success then return false, "JSON encoding failed: " .. tostring(encodedData) end

	local writeSuccess, writeError = pcall(writefile, fullPath, encodedData)
	if not writeSuccess then return false, "File write failed: " .. tostring(writeError) end

	print("MacLib: Saved config to", fullPath)
	return true
end

function MacLib:LoadConfig(path)
	if isStudio or not (isfile and readfile) then warn("MacLib: Loading unavailable."); return false, "Loading unavailable." end
	if not path or path:gsub("%s", "") == "" then return false, "Invalid config path." end

	local fullPath = MacLib.Folder .. "/settings/" .. path .. ".json"
	if not isfile(fullPath) then return false, "Config file not found: " .. path end

	local readSuccess, fileContent = pcall(readfile, fullPath)
	if not readSuccess then return false, "File read failed: " .. tostring(fileContent) end

	local decodeSuccess, decodedData = pcall(HttpService.JSONDecode, HttpService, fileContent)
	if not decodeSuccess then return false, "JSON decoding failed: " .. tostring(decodedData) end
	if type(decodedData) ~= "table" or type(decodedData.objects) ~= "table" then return false, "Invalid config format." end

	for _, savedObject in ipairs(decodedData.objects) do
		if type(savedObject) == "table" and savedObject.type and savedObject.flag then
			local parser = MacLib.ClassParser[savedObject.type]
			local targetElement = MacLib.Options[savedObject.flag]
			if parser and parser.Load and targetElement then
				local loadSuccess, loadError = pcall(parser.Load, savedObject.flag, savedObject)
				if not loadSuccess then
					warn("MacLib: Error loading element '", savedObject.flag, "':", loadError)
				end
			elseif parser and not targetElement then
                -- Warn if flag exists in config but not in current UI
                -- warn("MacLib: Flag '", savedObject.flag, "' found in config but not in current UI.")
            elseif not parser then
                 warn("MacLib: No loader found for type '", savedObject.type, "' (Flag: '", savedObject.flag, "')")
			end
		end
	end
	print("MacLib: Loaded config from", fullPath)
	return true
end

function MacLib:RefreshConfigList()
	if isStudio or not (isfolder and listfiles) then warn("MacLib: Config listing unavailable."); return {} end
	if not BuildFolderTree() then return {} end -- Ensure folder exists

	local files = {}
    local success, fileList = pcall(listfiles, MacLib.Folder .. "/settings")
	if not success or not fileList then return {} end

	local configNames = {}
	for _, filePath in ipairs(fileList) do
		-- Extract filename without path and extension
		local name = filePath:match("([^/\\]-)%.json$") -- Lua pattern to get filename without .json
		if name then
			table.insert(configNames, name)
		end
	end
	return configNames
end


--// Cleanup Function
function MacLib:Unload()
	if MacLib._Unloaded then return end
	print("MacLib: Unloading UI Library...")
	MacLib._Unloaded = true

	-- Destroy all tracked elements (Windows first, then others)
	-- Create a copy because element:Destroy() removes itself from the list
	local elementsToDestroy = {}
	for _, el in ipairs(MacLib._ActiveElements) do table.insert(elementsToDestroy, el) end

	for _, element in ipairs(elementsToDestroy) do
		if element and not element._Destroyed and element.Destroy then
			pcall(element.Destroy, element)
		end
	end
	MacLib._ActiveElements = {}
	MacLib.Options = {} -- Clear flagged options

	-- Disconnect all tracked global connections
	for _, conn in ipairs(MacLib._Connections) do
		pcall(conn.Disconnect, conn)
	end
	MacLib._Connections = {}

	-- Destroy the ScreenGui
	if MacLib._ScreenGui and MacLib._ScreenGui.Parent then
		pcall(MacLib._ScreenGui.Destroy, MacLib._ScreenGui)
	end
	MacLib._ScreenGui = nil

	-- Clear internal state variables
	MacLib._DraggingInfo = {}
	MacLib._InputFocus = nil
	MacLib._ActiveDropdown = nil

	print("MacLib: UI Library Unloaded.")
	-- Clear the MacLib table itself? Risky if external references exist. Best leave it.
	-- for k in pairs(MacLib) do MacLib[k] = nil end
end

MacLib.Close = MacLib.Unload -- Alias

--// Initial Setup (e.g., Build folder tree)
if not isStudio then
	BuildFolderTree()
end

print("MacLib Flat UI Library Initialized (v2.0.0)")
return MacLib
