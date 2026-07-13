--!strict

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local PresentationTokens = require(script.Parent.PresentationTokens)
local ResponsiveLayout = require(script.Parent.ResponsiveLayout)

type Layout = ResponsiveLayout.Layout
type LayoutClass = ResponsiveLayout.LayoutClass
type SafeInsets = ResponsiveLayout.SafeInsets
type TargetName = ResponsiveLayout.TargetName

export type Callbacks = {
	BeforeApply: (panelPositions: { [GuiObject]: UDim2 }, buttonSizes: { [TextButton]: UDim2 }) -> (),
	LayoutChanged: (layoutClass: LayoutClass) -> (),
	Observability: (layoutClass: LayoutClass, activeTweens: number) -> (),
}

export type Controller = {
	Refresh: (self: Controller) -> (),
	GetLayoutClass: (self: Controller) -> LayoutClass,
	GetLayout: (self: Controller) -> Layout?,
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_root: GuiObject,
	_objects: { [TargetName]: GuiObject },
	_constraints: { [TargetName]: UISizeConstraint },
	_callbacks: Callbacks,
	_connections: { RBXScriptConnection },
	_tweens: { [GuiObject]: Tween },
	_layout: Layout?,
	_layoutClass: LayoutClass,
	_signature: string?,
	_hasApplied: boolean,
	_destroyed: boolean,
}

local ResponsiveUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local PANEL_NAMES: { TargetName } = {
	"CurrentItemCard",
	"ShipmentCard",
	"PlacementControls",
	"DecisionPanel",
	"ResultsPanel",
}

local BUTTON_NAMES: { TargetName } = {
	"RotateButton",
	"PlaceButton",
	"ShipButton",
	"OneMoreButton",
	"PackAgainButton",
}

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("ResponsiveUIController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextButton") then
		error(string.format("ResponsiveUIController requires TextButton %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireConstraint(parent: Instance): UISizeConstraint
	local child = parent:WaitForChild("CompactMinimum", 10)
	if child == nil or not child:IsA("UISizeConstraint") then
		error(string.format("ResponsiveUIController requires UISizeConstraint %s.CompactMinimum", parent:GetFullName()), 3)
	end
	return child
end

local function activeTweenCount(self: InternalController): number
	local count = 0
	for _object in pairs(self._tweens) do
		count += 1
	end
	return count
end

local function observe(self: InternalController)
	self._callbacks.Observability(self._layoutClass, activeTweenCount(self))
end

local function zeroInsets(): SafeInsets
	return {
		Left = 0,
		Top = 0,
		Right = 0,
		Bottom = 0,
	}
end

local function coreInsetsInsideDeviceSafe(viewport: Vector2): SafeInsets
	local deviceArea = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
	local coreArea = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local left = math.max(0, coreArea.Min.X - deviceArea.Min.X)
	local top = math.max(0, coreArea.Min.Y - deviceArea.Min.Y)
	local right = math.max(0, deviceArea.Max.X - coreArea.Max.X)
	local bottom = math.max(0, deviceArea.Max.Y - coreArea.Max.Y)
	if left + right >= viewport.X or top + bottom >= viewport.Y then
		return zeroInsets()
	end
	return {
		Left = left,
		Top = top,
		Right = right,
		Bottom = bottom,
	}
end

local function layoutInsets(viewport: Vector2): SafeInsets
	local coreInsets = coreInsetsInsideDeviceSafe(viewport)
	if ResponsiveLayout.Classify(viewport.X, viewport.Y, nil) ~= "Wide" then
		return coreInsets
	end
	-- Wide keeps the exact Phase 02 scale geometry whenever it already clears
	-- the dynamic top bar. Narrow desktop windows reserve only the minimum
	-- additional top space needed by the highest authored target.
	local highestAuthoredScale = 0.035
	local authoredTop = viewport.Y * highestAuthoredScale
	if coreInsets.Top <= authoredTop then
		return zeroInsets()
	end
	return {
		Left = 0,
		Top = (coreInsets.Top - authoredTop) / (1 - highestAuthoredScale),
		Right = 0,
		Bottom = 0,
	}
end

local function signatureFor(viewport: Vector2, insets: SafeInsets): string
	return string.format(
		"%.3f:%.3f:%.3f:%.3f:%.3f:%.3f",
		viewport.X,
		viewport.Y,
		insets.Left,
		insets.Top,
		insets.Right,
		insets.Bottom
	)
end

local function applyCompactMinimums(self: InternalController, layoutClass: LayoutClass)
	for targetName, constraint in pairs(self._constraints) do
		if layoutClass == "Wide" then
			constraint.MinSize = Vector2.zero
		elseif targetName == "RotateButton" or targetName == "PlaceButton" then
			constraint.MinSize = Vector2.new(72, 64)
		else
			constraint.MinSize = Vector2.new(120, 64)
		end
	end
end

local function cancelTween(self: InternalController, object: GuiObject)
	local existing = self._tweens[object]
	if existing ~= nil then
		self._tweens[object] = nil
		existing:Cancel()
	end
end

local function applyLayout(self: InternalController, layout: Layout)
	local panelPositions: { [GuiObject]: UDim2 } = {}
	local buttonSizes: { [TextButton]: UDim2 } = {}
	for _, targetName in ipairs(PANEL_NAMES) do
		panelPositions[self._objects[targetName]] = layout.Targets[targetName].Position
	end
	for _, targetName in ipairs(BUTTON_NAMES) do
		local object = self._objects[targetName]
		if object:IsA("TextButton") then
			buttonSizes[object] = layout.Targets[targetName].Size
		end
	end
	self._callbacks.BeforeApply(panelPositions, buttonSizes)
	applyCompactMinimums(self, layout.Class)

	local instant = not self._hasApplied
	for targetName, target in pairs(layout.Targets) do
		local object = self._objects[targetName]
		cancelTween(self, object)
		if instant then
			object.AnchorPoint = target.AnchorPoint
			object.Position = target.Position
			object.Size = target.Size
		else
			local tween = TweenService:Create(
				object,
				TweenInfo.new(PresentationTokens.Timing.Layout, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{
					AnchorPoint = target.AnchorPoint,
					Position = target.Position,
					Size = target.Size,
				}
			)
			self._tweens[object] = tween
			tween.Completed:Once(function()
				if self._tweens[object] == tween then
					self._tweens[object] = nil
					observe(self)
				end
			end)
			tween:Play()
		end
	end
	self._hasApplied = true
	observe(self)
end

function ResponsiveUIController.new(root: GuiObject, callbacks: Callbacks): Controller
	local currentItemCard = requireGui(root, "CurrentItemCard")
	local shipmentCard = requireGui(root, "ShipmentCard")
	local placementControls = requireGui(root, "PlacementControls")
	local decisionPanel = requireGui(root, "DecisionPanel")
	local resultsPanel = requireGui(root, "ResultsPanel")
	local rotateButton = requireButton(placementControls, "RotateButton")
	local placeButton = requireButton(placementControls, "PlaceButton")
	local shipButton = requireButton(decisionPanel, "ShipButton")
	local oneMoreButton = requireButton(decisionPanel, "OneMoreButton")
	local packAgainButton = requireButton(resultsPanel, "PackAgainButton")

	local self: InternalController = setmetatable({
		_root = root,
		_objects = {
			CurrentItemCard = currentItemCard,
			ShipmentCard = shipmentCard,
			PlacementControls = placementControls,
			DecisionPanel = decisionPanel,
			ResultsPanel = resultsPanel,
			StatusBanner = requireGui(root, "StatusBanner"),
			RotateButton = rotateButton,
			PlaceButton = placeButton,
			ShipButton = shipButton,
			OneMoreButton = oneMoreButton,
			PackAgainButton = packAgainButton,
		},
		_constraints = {
			RotateButton = requireConstraint(rotateButton),
			PlaceButton = requireConstraint(placeButton),
			ShipButton = requireConstraint(shipButton),
			OneMoreButton = requireConstraint(oneMoreButton),
			PackAgainButton = requireConstraint(packAgainButton),
		},
		_callbacks = callbacks,
		_connections = {},
		_tweens = {},
		_layout = nil,
		_layoutClass = "Wide",
		_signature = nil,
		_hasApplied = false,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	table.insert(self._connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Refresh()
	end))
	table.insert(self._connections, GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		self:Refresh()
	end))
	self:Refresh()
	return self
end

function ControllerMethods.Refresh(self: InternalController)
	if self._destroyed then
		return
	end
	local viewport = self._root.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local insets = layoutInsets(viewport)
	local signature = signatureFor(viewport, insets)
	if signature == self._signature then
		return
	end
	local previousClass = if self._layout ~= nil then self._layout.Class else nil
	local layout = ResponsiveLayout.Resolve(viewport.X, viewport.Y, insets)
	self._signature = signature
	self._layout = layout
	self._layoutClass = layout.Class
	applyLayout(self, layout)
	if previousClass ~= layout.Class then
		self._callbacks.LayoutChanged(layout.Class)
	end
end

function ControllerMethods.GetLayoutClass(self: InternalController): LayoutClass
	return self._layoutClass
end

function ControllerMethods.GetLayout(self: InternalController): Layout?
	return self._layout
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for object, tween in pairs(self._tweens) do
		self._tweens[object] = nil
		tween:Cancel()
	end
	observe(self)
end

return table.freeze(ResponsiveUIController)
