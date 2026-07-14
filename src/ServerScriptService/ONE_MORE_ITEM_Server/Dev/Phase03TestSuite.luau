--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)

local Controllers = StarterPlayer:WaitForChild("StarterPlayerScripts")
	:WaitForChild("ONE_MORE_ITEM_Client")
	:WaitForChild("Controllers")
local CameraController = require(Controllers:WaitForChild("CameraController"))
local CharacterController = require(Controllers:WaitForChild("CharacterController"))
local GamepadInputController = require(Controllers:WaitForChild("GamepadInputController"))
local InputModeStore = require(Controllers:WaitForChild("InputModeStore"))
local InputController = require(Controllers:WaitForChild("InputController"))
local InputPromptController = require(Controllers:WaitForChild("InputPromptController"))
local ResponsiveLayout = require(Controllers:WaitForChild("ResponsiveLayout"))
local TouchInputController = require(Controllers:WaitForChild("TouchInputController"))

type LayoutClass = ResponsiveLayout.LayoutClass
type TargetName = ResponsiveLayout.TargetName
type ParentName = ResponsiveLayout.ParentName
type SafeInsets = ResponsiveLayout.SafeInsets
type Bounds = ResponsiveLayout.Bounds
type Direction = GamepadInputController.Direction
type InputMode = InputModeStore.InputMode

type TestCase = {
	Name: string,
	Run: () -> (),
}

type TestSuite = {
	Name: string,
	Tests: { TestCase },
}

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	Seed: number,
}

type ViewportCase = {
	Name: string,
	Width: number,
	Height: number,
	ExpectedClass: LayoutClass,
}

type ExpectedGeometry = {
	Parent: ParentName,
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
}

type FakePreferredInputSource = {
	PreferredInput: Enum.PreferredInput,
	Listener: ((preferredInput: Enum.PreferredInput) -> ())?,
	DisconnectCount: number,
	GetPreferredInput: (self: FakePreferredInputSource) -> Enum.PreferredInput,
	Subscribe: (
		self: FakePreferredInputSource,
		listener: (preferredInput: Enum.PreferredInput) -> ()
	) -> (() -> ()),
	SetPreferredInput: (self: FakePreferredInputSource, preferredInput: Enum.PreferredInput) -> (),
}

local Phase03TestSuite = {}
local suites: { TestSuite } = {}

local REQUIRED_VIEWPORTS: { ViewportCase } = {
	{ Name = "desktop 1920x1080", Width = 1920, Height = 1080, ExpectedClass = "Wide" },
	{ Name = "desktop 1366x768", Width = 1366, Height = 768, ExpectedClass = "Wide" },
	{ Name = "desktop 2560x1440", Width = 2560, Height = 1440, ExpectedClass = "Wide" },
	{ Name = "desktop 1100x700", Width = 1100, Height = 700, ExpectedClass = "Wide" },
	{ Name = "phone portrait 360x640", Width = 360, Height = 640, ExpectedClass = "Portrait" },
	{ Name = "phone portrait 390x844", Width = 390, Height = 844, ExpectedClass = "Portrait" },
	{ Name = "phone portrait 393x852", Width = 393, Height = 852, ExpectedClass = "Portrait" },
	{ Name = "phone portrait 430x932", Width = 430, Height = 932, ExpectedClass = "Portrait" },
	{ Name = "phone landscape 640x360", Width = 640, Height = 360, ExpectedClass = "CompactLandscape" },
	{ Name = "phone landscape 844x390", Width = 844, Height = 390, ExpectedClass = "CompactLandscape" },
	{ Name = "phone landscape 932x430", Width = 932, Height = 430, ExpectedClass = "CompactLandscape" },
	{ Name = "tablet portrait 768x1024", Width = 768, Height = 1024, ExpectedClass = "Portrait" },
	{ Name = "tablet landscape 1024x768", Width = 1024, Height = 768, ExpectedClass = "CompactLandscape" },
}

local CORE_PANELS: { TargetName } = {
	"CurrentItemCard",
	"ShipmentCard",
	"PlacementControls",
	"DecisionPanel",
	"ResultsPanel",
	"StatusBanner",
}

local ALL_TARGETS: { TargetName } = {
	"CurrentItemCard",
	"ShipmentCard",
	"PlacementControls",
	"DecisionPanel",
	"ResultsPanel",
	"StatusBanner",
	"RotateButton",
	"PlaceButton",
	"ShipButton",
	"OneMoreButton",
	"PackAgainButton",
}

local WIDE_EXPECTED: { [TargetName]: ExpectedGeometry } = {
	CurrentItemCard = {
		Parent = "Root",
		Position = UDim2.fromScale(0.025, 0.04),
		Size = UDim2.fromScale(0.22, 0.27),
		AnchorPoint = Vector2.new(0, 0),
	},
	ShipmentCard = {
		Parent = "Root",
		Position = UDim2.fromScale(0.975, 0.04),
		Size = UDim2.fromScale(0.22, 0.27),
		AnchorPoint = Vector2.new(1, 0),
	},
	PlacementControls = {
		Parent = "Root",
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.38, 0.10),
		AnchorPoint = Vector2.new(0.5, 1),
	},
	DecisionPanel = {
		Parent = "Root",
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.50, 0.30),
		AnchorPoint = Vector2.new(0.5, 1),
	},
	ResultsPanel = {
		Parent = "Root",
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.38, 0.38),
		AnchorPoint = Vector2.new(0.5, 0.5),
	},
	StatusBanner = {
		Parent = "Root",
		Position = UDim2.fromScale(0.5, 0.035),
		Size = UDim2.fromScale(0.30, 0.065),
		AnchorPoint = Vector2.new(0.5, 0),
	},
	RotateButton = {
		Parent = "PlacementControls",
		Position = UDim2.fromScale(0.05, 0.45),
		Size = UDim2.fromScale(0.43, 0.42),
		AnchorPoint = Vector2.new(0, 0),
	},
	PlaceButton = {
		Parent = "PlacementControls",
		Position = UDim2.fromScale(0.52, 0.45),
		Size = UDim2.fromScale(0.43, 0.42),
		AnchorPoint = Vector2.new(0, 0),
	},
	ShipButton = {
		Parent = "DecisionPanel",
		Position = UDim2.fromScale(0.30, 0.61),
		Size = UDim2.fromScale(0.30, 0.25),
		AnchorPoint = Vector2.new(0, 0),
	},
	OneMoreButton = {
		Parent = "DecisionPanel",
		Position = UDim2.fromScale(0.64, 0.61),
		Size = UDim2.fromScale(0.32, 0.25),
		AnchorPoint = Vector2.new(0, 0),
	},
	PackAgainButton = {
		Parent = "ResultsPanel",
		Position = UDim2.fromScale(0.15, 0.76),
		Size = UDim2.fromScale(0.70, 0.16),
		AnchorPoint = Vector2.new(0, 0),
	},
}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual: unknown, expected: unknown, message: string?)
	if actual ~= expected then
		error(message or string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local function expectNear(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(message or string.format("Expected %.8f, got %.8f", expected, actual), 2)
	end
end

local function expectError(callback: () -> (), message: string)
	local ok = pcall(callback)
	expect(not ok, message)
end

local function expectDirection(actual: Direction?, expectedX: number, expectedZ: number, message: string)
	expect(actual ~= nil, message .. ": expected a direction, got nil")
	local direction = actual :: Direction
	expectEqual(direction.X, expectedX, message .. ": wrong X")
	expectEqual(direction.Z, expectedZ, message .. ": wrong Z")
end

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, { Name = name, Tests = tests })
end

local function makeInsets(left: number, top: number, right: number, bottom: number): SafeInsets
	return {
		Left = left,
		Top = top,
		Right = right,
		Bottom = bottom,
	}
end

local function makeFakePreferredInputSource(initial: Enum.PreferredInput): FakePreferredInputSource
	local source: FakePreferredInputSource
	source = {
		PreferredInput = initial,
		Listener = nil,
		DisconnectCount = 0,
		GetPreferredInput = function(self: FakePreferredInputSource): Enum.PreferredInput
			return self.PreferredInput
		end,
		Subscribe = function(
			self: FakePreferredInputSource,
			listener: (preferredInput: Enum.PreferredInput) -> ()
		): () -> ()
			self.Listener = listener
			local connected = true
			return function()
				if connected then
					connected = false
					self.DisconnectCount += 1
					if self.Listener == listener then
						self.Listener = nil
					end
				end
			end
		end,
		SetPreferredInput = function(self: FakePreferredInputSource, preferredInput: Enum.PreferredInput)
			self.PreferredInput = preferredInput
			local listener = self.Listener
			if listener ~= nil then
				listener(preferredInput)
			end
		end,
	}
	return source
end

local function boundsOverlap(a: Bounds, b: Bounds): boolean
	return a.Left < b.Right and a.Right > b.Left and a.Top < b.Bottom and a.Bottom > b.Top
end

addSuite("Input mode store", {
	{
		Name = "KeyboardMouse maps from PreferredInput",
		Run = function()
			expectEqual(
				InputModeStore.ModeFromPreferredInput(Enum.PreferredInput.KeyboardAndMouse),
				"KeyboardMouse"
			)
		end,
	},
	{
		Name = "Touch maps from PreferredInput",
		Run = function()
			expectEqual(InputModeStore.ModeFromPreferredInput(Enum.PreferredInput.Touch), "Touch")
		end,
	},
	{
		Name = "Gamepad maps from PreferredInput",
		Run = function()
			expectEqual(InputModeStore.ModeFromPreferredInput(Enum.PreferredInput.Gamepad), "Gamepad")
		end,
	},
	{
		Name = "injected source supplies the initial mode",
		Run = function()
			local source = makeFakePreferredInputSource(Enum.PreferredInput.Touch)
			local store = InputModeStore.new(source)
			expectEqual(store:GetMode(), "Touch")
			store:Destroy()
		end,
	},
	{
		Name = "repeated mode does not notify and a change notifies once",
		Run = function()
			local source = makeFakePreferredInputSource(Enum.PreferredInput.KeyboardAndMouse)
			local store = InputModeStore.new(source)
			local notifications: { string } = {}
			store:Subscribe(function(mode)
				table.insert(notifications, mode)
			end)
			source:SetPreferredInput(Enum.PreferredInput.KeyboardAndMouse)
			expectEqual(#notifications, 0, "Repeated preferred mode must not notify")
			source:SetPreferredInput(Enum.PreferredInput.Gamepad)
			expectEqual(#notifications, 1, "One mode change must notify exactly once")
			expectEqual(notifications[1], "Gamepad")
			source:SetPreferredInput(Enum.PreferredInput.Gamepad)
			expectEqual(#notifications, 1, "Repeated changed mode must remain suppressed")
			store:Destroy()
		end,
	},
	{
		Name = "destroy disconnects the source and removes listeners",
		Run = function()
			local source = makeFakePreferredInputSource(Enum.PreferredInput.Touch)
			local store = InputModeStore.new(source)
			local notifications = 0
			store:Subscribe(function(_mode)
				notifications += 1
			end)
			store:Destroy()
			store:Destroy()
			expectEqual(source.DisconnectCount, 1, "Destroy must disconnect its injected source exactly once")
			source:SetPreferredInput(Enum.PreferredInput.Gamepad)
			expectEqual(notifications, 0, "Destroyed listeners must never receive a later mode")
			expectError(function()
				store:Subscribe(function(_mode) end)
			end, "A destroyed store must reject new subscriptions")
		end,
	},
})

addSuite("Responsive classification", {
	{
		Name = "required viewport matrix receives the intended class",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				expectEqual(
					ResponsiveLayout.Classify(viewport.Width, viewport.Height),
					viewport.ExpectedClass,
					viewport.Name .. " received the wrong layout class"
				)
			end
		end,
	},
	{
		Name = "classification and resolution are deterministic",
		Run = function()
			local insets = makeInsets(17, 31, 13, 19)
			local first = ResponsiveLayout.Resolve(932, 430, insets)
			for _ = 1, 20 do
				local nextLayout = ResponsiveLayout.Resolve(932, 430, insets)
				expectEqual(nextLayout.Class, first.Class)
				for _, targetName in ipairs(ALL_TARGETS) do
					expectEqual(nextLayout.Targets[targetName].Position, first.Targets[targetName].Position)
					expectEqual(nextLayout.Targets[targetName].Size, first.Targets[targetName].Size)
					expectEqual(nextLayout.Targets[targetName].AnchorPoint, first.Targets[targetName].AnchorPoint)
				end
			end
		end,
	},
	{
		Name = "portrait and compact aspect-ratio boundaries are explicit",
		Run = function()
			expectEqual(ResponsiveLayout.Classify(1099, 1000), "Portrait", "Ratio below 1.10 must be Portrait")
			expectEqual(ResponsiveLayout.Classify(1100, 1000), "CompactLandscape", "Ratio 1.10 must be CompactLandscape")
			expectEqual(ResponsiveLayout.Classify(1449, 1000), "CompactLandscape", "Ratio below 1.45 must be CompactLandscape")
			expectEqual(ResponsiveLayout.Classify(1450, 1000), "Wide", "Ratio 1.45 must be Wide")
		end,
	},
	{
		Name = "short landscape override is deterministic",
		Run = function()
			expectEqual(ResponsiveLayout.Classify(1600, 500), "CompactLandscape")
			expectEqual(ResponsiveLayout.Classify(1600, 501), "Wide")
		end,
	},
	{
		Name = "zero invalid and fully inset viewports reject safely",
		Run = function()
			expectError(function() ResponsiveLayout.Resolve(0, 640) end, "Zero width must reject")
			expectError(function() ResponsiveLayout.Resolve(360, 0) end, "Zero height must reject")
			expectError(function() ResponsiveLayout.Resolve(-1, 640) end, "Negative width must reject")
			expectError(function() ResponsiveLayout.Resolve(360, 0 / 0) end, "NaN height must reject")
			expectError(function() ResponsiveLayout.Resolve(math.huge, 640) end, "Infinite width must reject")
			expectError(
				function() ResponsiveLayout.Resolve(360, 640, makeInsets(-1, 0, 0, 0)) end,
				"Negative inset must reject"
			)
			expectError(
				function() ResponsiveLayout.Resolve(360, 640, makeInsets(180, 0, 180, 0)) end,
				"Insets consuming the viewport must reject"
			)
		end,
	},
})

addSuite("Responsive geometry", {
	{
		Name = "all core panels remain inside every required viewport",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
				for _, targetName in ipairs(CORE_PANELS) do
					local bounds = ResponsiveLayout.BoundsForTarget(layout, targetName)
					expect(
						ResponsiveLayout.IsContained(bounds, layout.UsableBounds),
						string.format("%s crosses the usable bounds at %s", targetName, viewport.Name)
					)
				end
			end
		end,
	},
	{
		Name = "representative safe insets preserve core-panel containment",
		Run = function()
			local insets = {
				{ Name = "none", Value = makeInsets(0, 0, 0, 0) },
				{ Name = "top", Value = makeInsets(0, 32, 0, 0) },
				{ Name = "left-right", Value = makeInsets(24, 0, 24, 0) },
				{ Name = "bottom", Value = makeInsets(0, 0, 0, 28) },
				{ Name = "combined", Value = makeInsets(20, 30, 20, 24) },
			}
			local viewports = {
				{ Width = 390, Height = 844 },
				{ Width = 844, Height = 390 },
				{ Width = 1024, Height = 768 },
				{ Width = 1920, Height = 1080 },
			}
			for _, viewport in ipairs(viewports) do
				for _, insetCase in ipairs(insets) do
					local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height, insetCase.Value)
					for _, targetName in ipairs(CORE_PANELS) do
						local bounds = ResponsiveLayout.BoundsForTarget(layout, targetName)
						expect(
							ResponsiveLayout.IsContained(bounds, layout.UsableBounds),
							string.format(
								"%s crosses %s safe bounds at %dx%d",
								targetName,
								insetCase.Name,
								viewport.Width,
								viewport.Height
							)
						)
					end
				end
			end
		end,
	},
	{
		Name = "every primary touch action meets its minimum usable size",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				if viewport.ExpectedClass ~= "Wide" then
					local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
					for _, targetName in ipairs({ "RotateButton", "PlaceButton" } :: { TargetName }) do
						local bounds = ResponsiveLayout.BoundsForTarget(layout, targetName)
						expect(
							bounds.Width >= 72 and bounds.Height >= 64,
							string.format(
								"%s is %.2fx%.2f at %s; expected at least 72x64",
								targetName,
								bounds.Width,
								bounds.Height,
								viewport.Name
							)
						)
					end
					for _, targetName in ipairs({ "ShipButton", "OneMoreButton", "PackAgainButton" } :: { TargetName }) do
						local bounds = ResponsiveLayout.BoundsForTarget(layout, targetName)
						expect(
							bounds.Width >= 120 and bounds.Height >= 64,
							string.format(
								"%s is %.2fx%.2f at %s; expected at least 120x64",
								targetName,
								bounds.Width,
								bounds.Height,
								viewport.Name
							)
						)
					end
				end
			end
		end,
	},
	{
		Name = "decision actions remain inside DecisionPanel",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
				local panelBounds = ResponsiveLayout.BoundsForTarget(layout, "DecisionPanel")
				for _, targetName in ipairs({ "ShipButton", "OneMoreButton" } :: { TargetName }) do
					expect(
						ResponsiveLayout.IsContained(ResponsiveLayout.BoundsForTarget(layout, targetName), panelBounds),
						string.format("%s leaves DecisionPanel at %s", targetName, viewport.Name)
					)
				end
			end
		end,
	},
	{
		Name = "ResultsPanel and PackAgain remain visible and contained",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
				local resultsBounds = ResponsiveLayout.BoundsForTarget(layout, "ResultsPanel")
				local packAgainBounds = ResponsiveLayout.BoundsForTarget(layout, "PackAgainButton")
				expect(resultsBounds.Width > 0 and resultsBounds.Height > 0, viewport.Name .. " ResultsPanel has no area")
				expect(ResponsiveLayout.IsContained(resultsBounds, layout.UsableBounds), viewport.Name .. " ResultsPanel is clipped")
				expect(
					ResponsiveLayout.IsContained(packAgainBounds, resultsBounds),
					viewport.Name .. " PackAgainButton leaves ResultsPanel"
				)
			end
		end,
	},
	{
		Name = "top cards do not cover placement or decision actions",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
				for _, cardName in ipairs({ "CurrentItemCard", "ShipmentCard" } :: { TargetName }) do
					local card = ResponsiveLayout.BoundsForTarget(layout, cardName)
					for _, actionName in ipairs({ "RotateButton", "PlaceButton", "ShipButton", "OneMoreButton" } :: { TargetName }) do
						local action = ResponsiveLayout.BoundsForTarget(layout, actionName)
						expect(
							not boundsOverlap(card, action),
							string.format("%s overlaps %s at %s", cardName, actionName, viewport.Name)
						)
					end
				end
			end
		end,
	},
	{
		Name = "portrait and landscape geometry differ meaningfully",
		Run = function()
			local portrait = ResponsiveLayout.Resolve(390, 844)
			local landscape = ResponsiveLayout.Resolve(844, 390)
			expectEqual(portrait.Class, "Portrait")
			expectEqual(landscape.Class, "CompactLandscape")
			expect(
				portrait.Targets.PlacementControls.Size ~= landscape.Targets.PlacementControls.Size,
				"Portrait PlacementControls must not be a scaled copy of CompactLandscape"
			)
			expect(
				portrait.Targets.CurrentItemCard.Position ~= landscape.Targets.CurrentItemCard.Position,
				"Portrait top-card placement must differ from CompactLandscape"
			)
		end,
	},
	{
		Name = "Wide geometry remains exactly Phase 02-compatible",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				if viewport.ExpectedClass == "Wide" then
					local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
					for targetName, expected in pairs(WIDE_EXPECTED) do
						local actual = layout.Targets[targetName]
						expectEqual(actual.Parent, expected.Parent, targetName .. " parent changed")
						expectEqual(actual.Position, expected.Position, targetName .. " position changed")
						expectEqual(actual.Size, expected.Size, targetName .. " size changed")
						expectEqual(actual.AnchorPoint, expected.AnchorPoint, targetName .. " anchor changed")
					end
				end
			end
		end,
	},
	{
		Name = "all responsive geometry uses scale-only UDim2 values",
		Run = function()
			for _, viewport in ipairs(REQUIRED_VIEWPORTS) do
				local layout = ResponsiveLayout.Resolve(viewport.Width, viewport.Height)
				for _, targetName in ipairs(ALL_TARGETS) do
					local target = layout.Targets[targetName]
					expectEqual(target.Position.X.Offset, 0, targetName .. " has a position X offset")
					expectEqual(target.Position.Y.Offset, 0, targetName .. " has a position Y offset")
					expectEqual(target.Size.X.Offset, 0, targetName .. " has a size X offset")
					expectEqual(target.Size.Y.Offset, 0, targetName .. " has a size Y offset")
				end
			end
		end,
	},
})

local function newTouchTracker(): (TouchInputController.Tracker, { Vector2 })
	local positions: { Vector2 } = {}
	local tracker = TouchInputController.newTracker(1, function(position: Vector2)
		table.insert(positions, position)
	end)
	return tracker, positions
end

addSuite("Touch tracking", {
	{
		Name = "first valid touch becomes active",
		Run = function()
			local tracker, positions = newTouchTracker()
			expect(tracker:Begin("first", Vector2.new(40, 50), true), "First valid touch must begin")
			expect(tracker:IsActive(), "First valid touch must become active")
			expectEqual(#positions, 1)
			expectEqual(positions[1], Vector2.new(40, 50))
		end,
	},
	{
		Name = "second simultaneous touch is ignored",
		Run = function()
			local tracker, positions = newTouchTracker()
			expect(tracker:Begin("first", Vector2.new(1, 1), true), "Fixture first touch must begin")
			expect(not tracker:Begin("second", Vector2.new(2, 2), true), "Second touch must be ignored")
			expect(not tracker:Move("second", Vector2.new(4, 4)), "Second touch must not move the pointer")
			expectEqual(#positions, 1)
		end,
	},
	{
		Name = "touch beginning over active UI is ignored by the allow gate",
		Run = function()
			local tracker, positions = newTouchTracker()
			expect(not tracker:Begin("over-ui", Vector2.new(10, 10), false), "Disallowed UI touch must not begin")
			expect(not tracker:IsActive(), "Disallowed UI touch must not become active")
			expectEqual(#positions, 0)
		end,
	},
	{
		Name = "active touch movement updates the pointer callback",
		Run = function()
			local tracker, positions = newTouchTracker()
			tracker:Begin("first", Vector2.new(0, 0), true)
			expect(not tracker:Move("first", Vector2.new(0.5, 0)), "Sub-threshold movement must be ignored")
			expect(tracker:Move("first", Vector2.new(3, 4)), "Meaningful movement must update")
			expectEqual(#positions, 2)
			expectEqual(positions[2], Vector2.new(3, 4))
		end,
	},
	{
		Name = "touch end releases only the active token",
		Run = function()
			local tracker, _positions = newTouchTracker()
			tracker:Begin("first", Vector2.zero, true)
			expect(not tracker:End("second"), "A different token must not end the drag")
			expect(tracker:IsActive(), "Wrong-token end must leave the first touch active")
			expect(tracker:End("first"), "The active token must end")
			expect(not tracker:IsActive(), "Touch end must release active state")
		end,
	},
	{
		Name = "state cancellation clears the active touch",
		Run = function()
			local tracker, _positions = newTouchTracker()
			tracker:Begin("first", Vector2.zero, true)
			tracker:Cancel()
			expect(not tracker:IsActive(), "State transition cancellation must clear the active touch")
			expect(not tracker:Move("first", Vector2.new(8, 8)), "Cancelled touch must no longer move")
		end,
	},
	{
		Name = "spectator touch does nothing through the assignment gate",
		Run = function()
			local tracker, positions = newTouchTracker()
			expect(not tracker:Begin("spectator", Vector2.new(25, 25), false), "Spectator touch must be rejected")
			expect(not tracker:IsActive(), "Spectator touch must not become active")
			expectEqual(#positions, 0, "Spectator touch must not update the pointer")
		end,
	},
})

addSuite("Gamepad repeat", {
	{
		Name = "repeat constants match the Phase 03 contract",
		Run = function()
			local deadzone, initialDelay, interval = GamepadInputController.GetRepeatConstants()
			expectNear(deadzone, 0.55, 0.000001)
			expectNear(initialDelay, 0.28, 0.000001)
			expectNear(interval, 0.12, 0.000001)
		end,
	},
	{
		Name = "new analog direction steps immediately",
		Run = function()
			local state = GamepadInputController.newRepeatState()
			expectDirection(GamepadInputController.UpdateAnalog(state, Vector2.new(0.8, 0), 10), 1, 0, "Initial step")
			expectNear(state.NextRepeatAt :: number, 10.28, 0.000001)
		end,
	},
	{
		Name = "held direction does not repeat before the initial delay",
		Run = function()
			local state = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(state, Vector2.new(0.8, 0), 10)
			expectEqual(GamepadInputController.PollRepeat(state, 10.279999), nil)
		end,
	},
	{
		Name = "held horizontal and vertical directions repeat at the delay",
		Run = function()
			local horizontal = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(horizontal, Vector2.new(-0.8, 0), 10)
			expectDirection(GamepadInputController.PollRepeat(horizontal, 10.28), -1, 0, "Horizontal repeat")

			local vertical = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(vertical, Vector2.new(0, 0.8), 20)
			expectDirection(GamepadInputController.PollRepeat(vertical, 20.28), 0, -1, "Vertical repeat")
		end,
	},
	{
		Name = "repeat interval uses fixed clocks and emits at most one step per poll",
		Run = function()
			local state = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(state, Vector2.new(0.9, 0), 10)
			GamepadInputController.PollRepeat(state, 10.28)
			expectEqual(GamepadInputController.PollRepeat(state, 10.399999), nil)
			expectDirection(GamepadInputController.PollRepeat(state, 10.4), 1, 0, "Second repeat")
			expectDirection(GamepadInputController.PollRepeat(state, 99), 1, 0, "Late poll")
			expectNear(state.NextRepeatAt :: number, 99.12, 0.000001, "Late poll must reschedule from now")
		end,
	},
	{
		Name = "direction change produces an immediate step",
		Run = function()
			local state = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(state, Vector2.new(0.8, 0), 10)
			expectDirection(
				GamepadInputController.UpdateAnalog(state, Vector2.new(0, -0.8), 10.1),
				0,
				1,
				"Changed direction"
			)
			expectNear(state.NextRepeatAt :: number, 10.38, 0.000001)
		end,
	},
	{
		Name = "release and explicit reset clear repeat state",
		Run = function()
			local state = GamepadInputController.newRepeatState()
			GamepadInputController.UpdateAnalog(state, Vector2.new(0.8, 0), 10)
			expectEqual(GamepadInputController.UpdateAnalog(state, Vector2.zero, 10.1), nil)
			expectEqual(state.X, 0)
			expectEqual(state.Z, 0)
			expectEqual(state.NextRepeatAt, nil)
			GamepadInputController.UpdateAnalog(state, Vector2.new(0, 0.8), 11)
			GamepadInputController.ResetRepeat(state)
			expectEqual(state.X, 0)
			expectEqual(state.Z, 0)
			expectEqual(state.NextRepeatAt, nil)
		end,
	},
	{
		Name = "deadzone ignores small input",
		Run = function()
			local direction = GamepadInputController.ResolveDirection(Vector2.new(0.549, -0.549))
			expectEqual(direction.X, 0)
			expectEqual(direction.Z, 0)
		end,
	},
	{
		Name = "dominant axis and equal-diagonal tie resolve deterministically",
		Run = function()
			local horizontal = GamepadInputController.ResolveDirection(Vector2.new(-0.9, 0.7))
			expectEqual(horizontal.X, -1)
			expectEqual(horizontal.Z, 0)
			local vertical = GamepadInputController.ResolveDirection(Vector2.new(0.6, -0.9))
			expectEqual(vertical.X, 0)
			expectEqual(vertical.Z, 1)
			local tie = GamepadInputController.ResolveDirection(Vector2.new(0.8, 0.8))
			expectEqual(tie.X, 1)
			expectEqual(tie.Z, 0)
		end,
	},
	{
		Name = "placement buttons route only while assigned and not pending",
		Run = function()
			expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", true, false, Enum.KeyCode.ButtonX, nil), "ROTATE")
			expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", true, false, Enum.KeyCode.ButtonA, nil), "PLACE")
			expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", true, false, Enum.KeyCode.DPadUp, nil), "MOVE_UP")
			expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", true, true, Enum.KeyCode.ButtonA, nil), nil)
			expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", true, true, Enum.KeyCode.DPadRight, nil), nil)
		end,
	},
	{
		Name = "decision defaults to Ship and One More requires deliberate selection",
		Run = function()
			expectEqual(GamepadInputController.ResolveButtonAction("Decision", true, false, Enum.KeyCode.ButtonA, nil), "CONFIRM_SHIP")
			expectEqual(GamepadInputController.ResolveButtonAction("Decision", true, false, Enum.KeyCode.DPadRight, nil), "SELECT_ONE_MORE")
			expectEqual(GamepadInputController.ResolveButtonAction("Decision", true, false, Enum.KeyCode.ButtonA, "ONE_MORE"), "CONFIRM_ONE_MORE")
		end,
	},
	{
		Name = "Pack Again routes only from Results",
		Run = function()
			expectEqual(GamepadInputController.ResolveButtonAction("Results", true, false, Enum.KeyCode.ButtonA, "RESTART"), "RESTART")
			expectEqual(GamepadInputController.ResolveButtonAction("Decision", true, false, Enum.KeyCode.ButtonA, "RESTART"), "CONFIRM_SHIP")
		end,
	},
	{
		Name = "selected Decision and Results buttons own gamepad confirmation",
		Run = function()
			expect(GamepadInputController.UsesSelectedButtonActivation("CONFIRM_SHIP"), "Ship must use selected-button activation")
			expect(GamepadInputController.UsesSelectedButtonActivation("CONFIRM_ONE_MORE"), "One More must use selected-button activation")
			expect(GamepadInputController.UsesSelectedButtonActivation("RESTART"), "Pack Again must use selected-button activation")
			expect(not GamepadInputController.UsesSelectedButtonActivation("PLACE"), "Placement must remain CAS-owned")
			expect(not GamepadInputController.UsesSelectedButtonActivation(nil), "No action must remain CAS-owned")
			expectEqual(GamepadInputController.ResolveSelectedAction("Decision", true, false, false), "SHIP")
			expectEqual(GamepadInputController.ResolveSelectedAction("Decision", false, true, false), "ONE_MORE")
			expectEqual(GamepadInputController.ResolveSelectedAction("Decision", false, false, false), nil)
			expectEqual(GamepadInputController.ResolveSelectedAction("Results", false, false, true), "RESTART")
			expectEqual(GamepadInputController.ResolveSelectedAction("Results", true, false, false), nil)
		end,
	},
	{
		Name = "spectators cannot route owner actions",
		Run = function()
			for _, keyCode in ipairs({ Enum.KeyCode.DPadUp, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonA }) do
				expectEqual(GamepadInputController.ResolveButtonAction("AwaitingPlacement", false, false, keyCode, nil), nil)
			end
		end,
	},
	{
		Name = "ButtonB never routes a risky action",
		Run = function()
			for _, state in ipairs({ "AwaitingPlacement", "Decision", "Results" }) do
				expectEqual(GamepadInputController.ResolveButtonAction(state, true, false, Enum.KeyCode.ButtonB, "ONE_MORE"), nil)
			end
		end,
	},
	{
		Name = "pending placement blocks analog and button movement",
		Run = function()
			expect(GamepadInputController.IsPlacementInputEnabled("AwaitingPlacement", true, false), "Ready owner should move")
			expect(not GamepadInputController.IsPlacementInputEnabled("AwaitingPlacement", true, true), "Pending owner must not move")
			expect(not GamepadInputController.IsPlacementInputEnabled("Decision", true, false), "Decision must not move the ghost")
			expect(not GamepadInputController.IsPlacementInputEnabled("AwaitingPlacement", false, false), "Spectator must not move")
		end,
	},
	{
		Name = "safe selection clears when leaving Gamepad or ownership",
		Run = function()
			expectEqual(GamepadInputController.ResolveSafeSelection(true, true, "Decision"), "SHIP")
			expectEqual(GamepadInputController.ResolveSafeSelection(true, true, "Results"), "RESTART")
			expectEqual(GamepadInputController.ResolveSafeSelection(true, true, "AwaitingPlacement"), nil)
			expectEqual(GamepadInputController.ResolveSafeSelection(false, true, "Decision"), nil)
			expectEqual(GamepadInputController.ResolveSafeSelection(true, false, "Decision"), nil)
		end,
	},
})

local function makePromptSnapshot(state: string): any
	return {
		State = state,
		ShipmentValue = 175,
		PossibleNextShipmentValue = 260,
		NextDifficulty = "RISKY",
	}
end

addSuite("Input prompts", {
	{
		Name = "keyboard prompts retain the approved desktop bindings",
		Run = function()
			local prompts = InputPromptController.GetPrompts("KeyboardMouse", makePromptSnapshot("AwaitingPlacement"))
			expectEqual(prompts.Rotate, "ROTATE  [R]")
			expectEqual(prompts.Place, "PLACE  [SPACE]")
			expectEqual(prompts.Ship, "SHIP NOW  [Q]\nGuaranteed: 175 Tape")
			expectEqual(prompts.OneMore, "ONE MORE  [E]\nPossible: 260 Tape\nRISKY")
			expectEqual(prompts.PackAgain, "PACK AGAIN  [ENTER]")
			expectEqual(prompts.ControlHint, "MOUSE / WASD / ARROWS TO MOVE")
		end,
	},
	{
		Name = "touch prompts contain no keyboard or gamepad key labels",
		Run = function()
			local prompts = InputPromptController.GetPrompts("Touch", makePromptSnapshot("AwaitingPlacement"))
			expectEqual(prompts.Rotate, "ROTATE")
			expectEqual(prompts.Place, "PLACE")
			expectEqual(prompts.Ship, "SHIP NOW\nGuaranteed: 175 Tape")
			expectEqual(prompts.OneMore, "ONE MORE\nPossible: 260 Tape\nRISKY")
			expectEqual(prompts.PackAgain, "PACK AGAIN")
			expectEqual(prompts.ControlHint, "DRAG TO MOVE")
			for _, text in pairs(prompts) do
				expect(string.find(text, "[", 1, true) == nil, "Touch prompts must not contain bracketed key labels")
			end
		end,
	},
	{
		Name = "gamepad placement and decision prompts match the active state",
		Run = function()
			local placement = InputPromptController.GetPrompts("Gamepad", makePromptSnapshot("AwaitingPlacement"))
			expectEqual(placement.Rotate, "ROTATE  [X]")
			expectEqual(placement.Place, "PLACE  [A]")
			expectEqual(placement.PackAgain, "PACK AGAIN  [A]")
			expectEqual(placement.ControlHint, "LEFT STICK / D-PAD TO MOVE")

			local decision = InputPromptController.GetPrompts("Gamepad", makePromptSnapshot("Decision"))
			expect(string.find(decision.ControlHint, "SELECT", 1, true) ~= nil, "Decision hint must explain selection")
			expect(string.find(decision.ControlHint, "CONFIRM", 1, true) ~= nil, "Decision hint must explain confirmation")
			expect(string.find(decision.ControlHint, "[A]", 1, true) ~= nil, "Decision hint must identify ButtonA")
		end,
	},
	{
		Name = "mode switching preserves authoritative snapshot values",
		Run = function()
			local snapshot = makePromptSnapshot("Decision")
			local keyboard = InputPromptController.GetPrompts("KeyboardMouse", snapshot)
			local touch = InputPromptController.GetPrompts("Touch", snapshot)
			local gamepad = InputPromptController.GetPrompts("Gamepad", snapshot)
			for _, prompts in ipairs({ keyboard, touch, gamepad }) do
				expect(string.find(prompts.Ship, "175", 1, true) ~= nil, "Mode switch changed ShipmentValue")
				expect(string.find(prompts.OneMore, "260", 1, true) ~= nil, "Mode switch changed possible value")
				expect(string.find(prompts.OneMore, "RISKY", 1, true) ~= nil, "Mode switch changed difficulty")
			end
			expectEqual(snapshot.State, "Decision")
			expectEqual(snapshot.ShipmentValue, 175)
			expectEqual(snapshot.PossibleNextShipmentValue, 260)
			expectEqual(snapshot.NextDifficulty, "RISKY")
		end,
	},
})

addSuite("Camera targeting", {
	{
		Name = "Wide selects the approved desktop anchor",
		Run = function()
			expectEqual(CameraController.SelectAnchorName("Wide", "KeyboardMouse"), "CameraAnchor")
			expectEqual(CameraController.SelectAnchorName("Wide", "Gamepad"), "CameraAnchor")
		end,
	},
	{
		Name = "Compact touch landscape selects the touch-landscape anchor",
		Run = function()
			expectEqual(
				CameraController.SelectAnchorName("CompactLandscape", "Touch"),
				"CameraAnchorTouchLandscape"
			)
			expectEqual(CameraController.SelectAnchorName("CompactLandscape", "KeyboardMouse"), "CameraAnchor")
		end,
	},
	{
		Name = "Portrait selects the portrait anchor for every input mode",
		Run = function()
			for _, mode in ipairs({ "KeyboardMouse", "Touch", "Gamepad" } :: { InputMode }) do
				expectEqual(CameraController.SelectAnchorName("Portrait", mode), "CameraAnchorTouchPortrait")
			end
		end,
	},
	{
		Name = "responsive resize retargets without replaying initial arrival",
		Run = function()
			expectEqual(CameraController.ResolveTransition(false, nil, "Wide", "KeyboardMouse"), "INACTIVE")
			expectEqual(CameraController.ResolveTransition(true, nil, "Wide", "KeyboardMouse"), "ARRIVAL")
			expectEqual(CameraController.ResolveTransition(true, "CameraAnchor", "Wide", "Gamepad"), "UNCHANGED")
			expectEqual(CameraController.ResolveTransition(true, "CameraAnchor", "Portrait", "Touch"), "RETARGET")
		end,
	},
	{
		Name = "obsolete camera impulses cannot settle over a newer target",
		Run = function()
			expect(CameraController.IsCurrentImpulseEpoch(9, 9), "Current impulse epoch should settle")
			expect(not CameraController.IsCurrentImpulseEpoch(9, 10), "Obsolete impulse epoch must not settle")
		end,
	},
})

addSuite("Control cleanup and remote discipline", {
	{
		Name = "assignment disables and unassignment restores previously enabled controls",
		Run = function()
			local state = CharacterController.newControlLeaseState()
			expectEqual(CharacterController.TransitionControlLease(state, true, true), "DISABLE")
			expectEqual(CharacterController.TransitionControlLease(state, true, true), nil)
			expectEqual(CharacterController.TransitionControlLease(state, false, false), "RESTORE")
		end,
	},
	{
		Name = "previously disabled controls remain disabled after the lease",
		Run = function()
			local state = CharacterController.newControlLeaseState()
			expectEqual(CharacterController.TransitionControlLease(state, true, false), nil)
			expectEqual(CharacterController.TransitionControlLease(state, false, false), nil)
		end,
	},
	{
		Name = "assigned respawn reapplies the control lease",
		Run = function()
			local state = CharacterController.newControlLeaseState()
			CharacterController.TransitionControlLease(state, true, true)
			expectEqual(CharacterController.RespawnControlLease(state), "DISABLE")
			CharacterController.TransitionControlLease(state, false, false)
			expectEqual(CharacterController.RespawnControlLease(state), nil)
		end,
	},
	{
		Name = "late humanoid suppression rechecks assignment destruction and character identity",
		Run = function()
			expect(CharacterController.ShouldSuppressAutoRotate(true, false, true, true))
			expect(not CharacterController.ShouldSuppressAutoRotate(false, false, true, true))
			expect(not CharacterController.ShouldSuppressAutoRotate(true, true, true, true))
			expect(not CharacterController.ShouldSuppressAutoRotate(true, false, false, true))
			expect(not CharacterController.ShouldSuppressAutoRotate(true, false, true, false))
		end,
	},
	{
		Name = "auto rotate lease restores the exact prior value and does not retain a released state",
		Run = function()
			local previouslyDisabled = CharacterController.newAutoRotateLeaseState()
			expectEqual(CharacterController.BeginAutoRotateLease(previouslyDisabled, false), false)
			expectEqual(CharacterController.BeginAutoRotateLease(previouslyDisabled, true), false)
			expectEqual(CharacterController.ReleaseAutoRotateLease(previouslyDisabled), false)
			expectEqual(CharacterController.ReleaseAutoRotateLease(previouslyDisabled), nil)

			local previouslyEnabled = CharacterController.newAutoRotateLeaseState()
			expectEqual(CharacterController.BeginAutoRotateLease(previouslyEnabled, true), false)
			expectEqual(CharacterController.ReleaseAutoRotateLease(previouslyEnabled), true)
		end,
	},
	{
		Name = "destroy restores controls acquired by the assignment lease",
		Run = function()
			local state = CharacterController.newControlLeaseState()
			CharacterController.TransitionControlLease(state, true, true)
			expectEqual(CharacterController.DestroyControlLease(state), "RESTORE")
			expectEqual(CharacterController.DestroyControlLease(state), nil)
		end,
	},
	{
		Name = "spectator control state remains untouched",
		Run = function()
			local state = CharacterController.newControlLeaseState()
			expectEqual(CharacterController.TransitionControlLease(state, false, true), nil)
			expect(not state.Assigned, "Spectator lease must remain unassigned")
		end,
	},
	{
		Name = "touch gamepad movement and rotation have no network request",
		Run = function()
			for _, action in ipairs({ "MOVE", "POINTER", "ROTATE" } :: { InputController.RoutedAction }) do
				expectEqual(InputController.NetworkRequestForAction(action), nil)
			end
		end,
	},
	{
		Name = "placing deciding and restarting map to one existing request family",
		Run = function()
			expectEqual(InputController.NetworkRequestForAction("PLACE"), "PlaceItemRequest")
			expectEqual(InputController.NetworkRequestForAction("SHIP"), "DecisionRequest")
			expectEqual(InputController.NetworkRequestForAction("ONE_MORE"), "DecisionRequest")
			expectEqual(InputController.NetworkRequestForAction("RESTART"), "RestartRequest")
		end,
	},
	{
		Name = "authored buttons accept only safe gamepad selection activation",
		Run = function()
			expect(InputController.ShouldHandleAuthoredButton("KeyboardMouse", true, false), "Assigned keyboard button should activate")
			expect(InputController.ShouldHandleAuthoredButton("Touch", true, false), "Assigned touch button should activate")
			expect(InputController.ShouldHandleAuthoredButton("Gamepad", true, true), "Selected gamepad button should activate")
			expect(not InputController.ShouldHandleAuthoredButton("Gamepad", true, false), "Unselected gamepad button must not activate")
			expect(not InputController.ShouldHandleAuthoredButton("Gamepad", false, true), "Spectator button must not activate")
		end,
	},
	{
		Name = "runtime network dispatcher invokes only the mapped injected handler",
		Run = function()
			local calls: { string } = {}
			local callbacks: InputController.NetworkCallbacks = {
				Place = function()
					table.insert(calls, "PLACE")
				end,
				Decision = function(choice: string)
					table.insert(calls, choice)
				end,
				Restart = function()
					table.insert(calls, "RESTART")
				end,
			}

			expectEqual(InputController.DispatchNetworkAction(callbacks, "MOVE"), nil)
			expectEqual(InputController.DispatchNetworkAction(callbacks, "ROTATE"), nil)
			expectEqual(#calls, 0, "Local-only actions must not reach a network handler")
			expectEqual(InputController.DispatchNetworkAction(callbacks, "PLACE"), "PlaceItemRequest")
			expectEqual(InputController.DispatchNetworkAction(callbacks, "SHIP"), "DecisionRequest")
			expectEqual(InputController.DispatchNetworkAction(callbacks, "ONE_MORE"), "DecisionRequest")
			expectEqual(InputController.DispatchNetworkAction(callbacks, "RESTART"), "RestartRequest")
			expectEqual(table.concat(calls, ","), "PLACE,SHIP,ONE_MORE,RESTART")
		end,
	},
	{
		Name = "network surface remains the six approved Phase 02 remotes",
		Run = function()
			local net = Root:WaitForChild("Net")
			local expected: { [string]: boolean } = {
				ClientReadyRequest = true,
				PlaceItemRequest = true,
				DecisionRequest = true,
				RestartRequest = true,
				RoundSnapshot = true,
				PlacementResponse = true,
			}
			local count = 0
			for _, child in ipairs(net:GetChildren()) do
				if child:IsA("RemoteEvent") then
					count += 1
					expect(expected[child.Name] == true, "Unexpected gameplay remote " .. child.Name)
				end
			end
			expectEqual(count, 6, "Touch and gamepad must not add gameplay remotes")
		end,
	},
})

function Phase03TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}
	local seed = RoundConfig.DEVELOPMENT.PHASE03_TEST_SEED

	print(string.format("[ONE_MORE_ITEM][Phase03Tests] Starting %d suites seed=%d", #suites, seed))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase03Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase03Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase03Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		seed
	))

	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase03Tests] FAILURE %d: %s", index, failure))
		end
	end

	return {
		Suites = #suites,
		Tests = totalTests,
		Passed = passed,
		Failed = failed,
		Failures = failures,
		DurationSeconds = duration,
		Seed = seed,
	}
end

return table.freeze(Phase03TestSuite)
