--!strict

local TweenService = game:GetService("TweenService")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)

type Snapshot = ClientRoundStore.Snapshot
type Cell = ClientRoundStore.Cell

export type Controller = {
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> (),
	Clear: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_currentViewport: ViewportFrame,
	_nextViewport: ViewportFrame,
	_template: BasePart,
	_getShapeCells: (shapeId: string) -> { Cell }?,
	_getItemColor: (itemId: string) -> Color3,
	_currentKey: string?,
	_nextKey: string?,
	_revealConnections: { [RBXScriptConnection]: boolean },
	_destroyed: boolean,
}

local ViewportPreviewController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local WORLD_NAME = "ONE_MORE_ITEM_RuntimePreviewWorld"
local CAMERA_NAME = "ONE_MORE_ITEM_RuntimePreviewCamera"

local function clearRuntime(frame: ViewportFrame)
	local world = frame:FindFirstChild(WORLD_NAME)
	if world ~= nil then
		world:Destroy()
	end
	local camera = frame:FindFirstChild(CAMERA_NAME)
	if camera ~= nil then
		camera:Destroy()
	end
	frame.CurrentCamera = nil
end

local function disconnectRevealConnections(self: InternalController)
	for connection in pairs(self._revealConnections) do
		connection:Disconnect()
	end
	table.clear(self._revealConnections)
end

local function bounds(cells: { Cell }): (Vector3, Vector3)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, cell in ipairs(cells) do
		local point = Vector3.new(cell.X, cell.Y, cell.Z)
		minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
		maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
	end
	return minimum, maximum
end

local function renderPreview(
	self: InternalController,
	frame: ViewportFrame,
	itemId: string,
	shapeId: string,
	reveal: boolean
)
	clearRuntime(frame)
	local cells = self._getShapeCells(shapeId)
	if cells == nil or #cells == 0 then
		return
	end

	local world = Instance.new("WorldModel")
	world.Name = WORLD_NAME
	world.Parent = frame
	local model = Instance.new("Model")
	model.Name = "PreviewItem"
	model.Parent = world

	local minimum, maximum = bounds(cells)
	local center = (minimum + maximum) * 0.5
	local itemColor = self._getItemColor(itemId)
	for index, cell in ipairs(cells) do
		local clone = self._template:Clone()
		clone.Name = string.format("Cell_%02d", index)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Color = itemColor
		clone.CFrame = CFrame.new((Vector3.new(cell.X, cell.Y, cell.Z) - center) * 1.55)
		clone.Parent = model
	end

	local camera = Instance.new("Camera")
	camera.Name = CAMERA_NAME
	camera.FieldOfView = 35
	local span = maximum - minimum + Vector3.one
	local distance = math.max(6, span.Magnitude * 2.1)
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.72, distance * 0.56, distance), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera

	if reveal then
		local rotation = Instance.new("CFrameValue")
		rotation.Value = CFrame.Angles(0, math.rad(-32), 0)
		rotation.Parent = world
		model:PivotTo(rotation.Value)
		local connection = rotation:GetPropertyChangedSignal("Value"):Connect(function()
			if not self._destroyed and model.Parent ~= nil then
				model:PivotTo(rotation.Value)
			end
		end)
		self._revealConnections[connection] = true
		local tween = TweenService:Create(
			rotation,
			TweenInfo.new(PresentationTokens.Timing.PreviewReveal, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Value = CFrame.Angles(0, math.rad(328), 0) }
		)
		tween:Play()
		tween.Completed:Once(function()
			connection:Disconnect()
			self._revealConnections[connection] = nil
			if rotation.Parent ~= nil then
				rotation:Destroy()
			end
		end)
	end
end

function ViewportPreviewController.new(
	currentViewport: ViewportFrame,
	nextViewport: ViewportFrame,
	template: BasePart,
	getShapeCells: (shapeId: string) -> { Cell }?,
	getItemColor: (itemId: string) -> Color3
): Controller
	local self: InternalController = setmetatable({
		_currentViewport = currentViewport,
		_nextViewport = nextViewport,
		_template = template,
		_getShapeCells = getShapeCells,
		_getItemColor = getItemColor,
		_currentKey = nil,
		_nextKey = nil,
		_revealConnections = {},
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot)
	if self._destroyed then
		return
	end
	local currentKey = if snapshot.CurrentItemId ~= nil and snapshot.CurrentShapeId ~= nil
		then string.format("%s|%s", snapshot.CurrentItemId, snapshot.CurrentShapeId)
		else nil
	if currentKey ~= self._currentKey then
		self._currentKey = currentKey
		if snapshot.CurrentItemId ~= nil and snapshot.CurrentShapeId ~= nil then
			renderPreview(self, self._currentViewport, snapshot.CurrentItemId, snapshot.CurrentShapeId, true)
		else
			clearRuntime(self._currentViewport)
		end
	end

	local nextKey = if snapshot.NextItemId ~= nil and snapshot.NextShapeId ~= nil
		then string.format("%s|%s", snapshot.NextItemId, snapshot.NextShapeId)
		else nil
	if nextKey ~= self._nextKey then
		self._nextKey = nextKey
		if snapshot.NextItemId ~= nil and snapshot.NextShapeId ~= nil then
			renderPreview(self, self._nextViewport, snapshot.NextItemId, snapshot.NextShapeId, true)
		else
			clearRuntime(self._nextViewport)
		end
	end
end

function ControllerMethods.Clear(self: InternalController)
	self._currentKey = nil
	self._nextKey = nil
	disconnectRevealConnections(self)
	clearRuntime(self._currentViewport)
	clearRuntime(self._nextViewport)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:Clear()
end

return table.freeze(ViewportPreviewController)
