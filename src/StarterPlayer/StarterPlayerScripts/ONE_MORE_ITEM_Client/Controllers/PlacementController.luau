--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local DevelopmentItemDefinitions = require(shared:WaitForChild("Content"):WaitForChild("DevelopmentItemDefinitions"))
local OccupancyGrid = require(shared:WaitForChild("Grid"):WaitForChild("OccupancyGrid"))
local PlacementSolver = require(shared:WaitForChild("Grid"):WaitForChild("PlacementSolver"))
local ShapeRotation = require(shared:WaitForChild("Grid"):WaitForChild("ShapeRotation"))
local GridWorldTransform = require(shared:WaitForChild("World"):WaitForChild("GridWorldTransform"))
local DevelopmentItemRenderer = require(shared:WaitForChild("World"):WaitForChild("DevelopmentItemRenderer"))

type Snapshot = ClientRoundStore.Snapshot
type PlacementResponse = ClientRoundStore.PlacementResponse
type Cell = ClientRoundStore.Cell

type Rotation = {
	QuarterTurns: number,
	Cells: { Cell },
	Key: string,
	SizeX: number,
	SizeY: number,
	SizeZ: number,
}

export type Callbacks = {
	FitChanged: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
	GridFeedback: (cells: { Cell }, valid: boolean) -> (),
	ClearGridFeedback: () -> (),
	ButtonPressed: (action: string) -> (),
	PlacementImpact: (position: Vector3, heavy: boolean) -> (),
	ServerResponse: (reason: string, accepted: boolean) -> (),
	Rejected: () -> (),
	Observability: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
}

export type Controller = {
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> (),
	Move: (self: Controller, deltaX: number, deltaZ: number) -> (),
	RotateClockwise: (self: Controller) -> (),
	UpdateFromPointerRay: (self: Controller, ray: Ray) -> (),
	RequestPlacement: (self: Controller) -> (),
	HandleResponse: (self: Controller, response: PlacementResponse) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_remote: RemoteEvent,
	_station: Model,
	_template: BasePart,
	_gridOrigin: BasePart,
	_runtimeContainer: Instance,
	_callbacks: Callbacks,
	_snapshot: Snapshot?,
	_originX: number,
	_originZ: number,
	_rotationIndex: number,
	_quarterTurns: number,
	_visualCells: { Cell },
	_valid: boolean,
	_placementY: number?,
	_ghost: Model?,
	_highlight: Highlight?,
	_clientSequence: number,
	_pendingSequence: number?,
	_pendingImpactPosition: Vector3?,
	_pendingHeavy: boolean,
	_renderEpoch: number,
	_destroyed: boolean,
}

local PlacementController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function requirePart(parent: Instance, name: string): BasePart
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("BasePart") then
		error(string.format("PlacementController requires BasePart %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireChild(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	if child == nil then
		error(string.format("PlacementController requires %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function currentDefinition(snapshot: Snapshot)
	if snapshot.CurrentItemId == nil then
		return nil
	end
	return DevelopmentItemDefinitions.Get(snapshot.CurrentItemId)
end

local function copyCells(cells: { Cell }): { Cell }
	local copied: { Cell } = {}
	for _, cell in ipairs(cells) do
		table.insert(copied, { X = cell.X, Y = cell.Y, Z = cell.Z })
	end
	return copied
end

local function translatedCells(rotation: Rotation, x: number, y: number, z: number): { Cell }
	local cells: { Cell } = {}
	for _, cell in ipairs(rotation.Cells) do
		table.insert(cells, { X = cell.X + x, Y = cell.Y + y, Z = cell.Z + z })
	end
	return cells
end

local function createGrid(snapshot: Snapshot)
	local grid = OccupancyGrid.CreateGrid(
		PresentationTokens.Grid.Width,
		PresentationTokens.Grid.Height,
		PresentationTokens.Grid.Depth
	)
	if #snapshot.OccupiedCells > 0 then
		local copied = copyCells(snapshot.OccupiedCells)
		local applied = grid:ApplyPlacement({
			ShapeId = "snapshot",
			RotationIndex = 1,
			QuarterTurns = 0,
			Origin = { X = 0, Y = 0, Z = 0 },
			Cells = copied,
			Key = "snapshot",
		})
		if not applied then
			warn("[ONE_MORE_ITEM][Client] Snapshot occupancy was not a valid 5x4x5 cell set")
		end
	end
	return grid
end

local function sortedGhostParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a: BasePart, b: BasePart): boolean
		return a.Name < b.Name
	end)
	return parts
end

local function clearGhost(self: InternalController)
	self._renderEpoch += 1
	if self._ghost ~= nil then
		self._ghost:Destroy()
	end
	self._ghost = nil
	self._highlight = nil
	self._visualCells = {}
	self._callbacks.ClearGridFeedback()
	self._callbacks.FitChanged(nil, nil, nil, nil)
	self._callbacks.Observability(nil, nil, nil, nil)
end

local function renderGhost(self: InternalController, cells: { Cell }, color: Color3, immediate: boolean)
	local parts = if self._ghost ~= nil then sortedGhostParts(self._ghost) else {}
	if self._ghost == nil or #parts ~= #cells then
		if self._ghost ~= nil then
			self._ghost:Destroy()
		end
		self._ghost = DevelopmentItemRenderer.RenderCells(
			self._template,
			self._runtimeContainer,
			"LocalPlacementGhost",
			cells,
			self._gridOrigin.CFrame,
			PresentationTokens.Grid.CellSize,
			color,
			PresentationTokens.Ghost.Transparency
		)
		local highlight = Instance.new("Highlight")
		highlight.Name = "GhostOutline"
		highlight.Adornee = self._ghost
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.82
		highlight.OutlineTransparency = 0.08
		highlight.Parent = self._ghost
		self._highlight = highlight
		parts = sortedGhostParts(self._ghost)
	end

	local targetColor = if self._valid then PresentationTokens.Color.Green else PresentationTokens.Color.Red
	if self._highlight ~= nil then
		self._highlight.FillColor = targetColor
		self._highlight.OutlineColor = targetColor
	end
	for index, part in ipairs(parts) do
		local target = GridWorldTransform.CellToCFrame(
			self._gridOrigin.CFrame,
			cells[index],
			PresentationTokens.Grid.CellSize
		)
		part.Color = targetColor:Lerp(color, 0.28)
		part.Transparency = if self._valid then PresentationTokens.Ghost.Transparency else PresentationTokens.Ghost.InvalidTransparency
		if immediate then
			part.CFrame = target
		else
			TweenService:Create(
				part,
				TweenInfo.new(PresentationTokens.Timing.GhostMove, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ CFrame = target }
			):Play()
		end
	end
end

local function recalculate(self: InternalController, immediate: boolean)
	local snapshot = self._snapshot
	if snapshot == nil or snapshot.State ~= "AwaitingPlacement" then
		clearGhost(self)
		return
	end
	local definition = currentDefinition(snapshot)
	if definition == nil then
		clearGhost(self)
		return
	end

	local rotations = ShapeRotation.GetUniqueRotations(definition.Shape)
	if #rotations == 0 then
		clearGhost(self)
		return
	end
	self._rotationIndex = math.clamp(self._rotationIndex, 1, #rotations)
	local rotation = rotations[self._rotationIndex]
	self._quarterTurns = rotation.QuarterTurns
	local grid = createGrid(snapshot)
	local placement = PlacementSolver.GetAutoDropPlacement(
		grid,
		rotation,
		self._originX,
		self._originZ,
		definition.ShapeId,
		self._rotationIndex
	)

	local visualCells: { Cell }
	if placement ~= nil then
		self._valid = true
		self._placementY = placement.Origin.Y
		visualCells = copyCells(placement.Cells)
	else
		self._valid = false
		self._placementY = nil
		local fallbackY = math.max(0, PresentationTokens.Grid.Height - rotation.SizeY)
		visualCells = translatedCells(rotation, self._originX, fallbackY, self._originZ)
	end
	self._visualCells = visualCells
	renderGhost(self, visualCells, definition.Color, immediate)
	self._callbacks.GridFeedback(visualCells, self._valid)
	self._callbacks.FitChanged(self._valid, self._originX, self._placementY, self._originZ)
	self._callbacks.Observability(self._valid, self._originX, self._placementY, self._originZ)
end

function PlacementController.new(
	remote: RemoteEvent,
	station: Model,
	template: BasePart,
	callbacks: Callbacks
): Controller
	local crate = requireChild(station, "Crate")
	local self: InternalController = setmetatable({
		_remote = remote,
		_station = station,
		_template = template,
		_gridOrigin = requirePart(crate, "GridOrigin"),
		_runtimeContainer = requireChild(station, "RuntimePresentation"),
		_callbacks = callbacks,
		_snapshot = nil,
		_originX = 2,
		_originZ = 2,
		_rotationIndex = 1,
		_quarterTurns = 0,
		_visualCells = {},
		_valid = false,
		_placementY = nil,
		_ghost = nil,
		_highlight = nil,
		_clientSequence = 0,
		_pendingSequence = nil,
		_pendingImpactPosition = nil,
		_pendingHeavy = false,
		_renderEpoch = 0,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot)
	if self._destroyed then
		return
	end
	local previous = self._snapshot
	local changedItem = previous == nil
		or previous.RoundId ~= snapshot.RoundId
		or previous.CurrentItemId ~= snapshot.CurrentItemId
		or previous.CurrentShapeId ~= snapshot.CurrentShapeId
	self._snapshot = snapshot
	if changedItem then
		self._rotationIndex = 1
		local definition = currentDefinition(snapshot)
		if definition ~= nil then
			local firstRotation = ShapeRotation.GetUniqueRotations(definition.Shape)[1]
			self._originX = math.floor((PresentationTokens.Grid.Width - firstRotation.SizeX) * 0.5)
			self._originZ = math.floor((PresentationTokens.Grid.Depth - firstRotation.SizeZ) * 0.5)
		end
		if previous == nil or previous.RoundId ~= snapshot.RoundId then
			self._pendingSequence = nil
			self._pendingImpactPosition = nil
		end
	end
	if snapshot.State ~= "AwaitingPlacement" then
		if previous ~= nil and previous.RoundId ~= snapshot.RoundId then
			self._pendingSequence = nil
			self._pendingImpactPosition = nil
		end
		clearGhost(self)
		return
	end

	recalculate(self, changedItem)
end

function ControllerMethods.Move(self: InternalController, deltaX: number, deltaZ: number)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingSequence ~= nil then
		return
	end
	self._originX = math.clamp(self._originX + deltaX, 0, PresentationTokens.Grid.Width - 1)
	self._originZ = math.clamp(self._originZ + deltaZ, 0, PresentationTokens.Grid.Depth - 1)
	recalculate(self, false)
end

function ControllerMethods.RotateClockwise(self: InternalController)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingSequence ~= nil then
		return
	end
	local definition = currentDefinition(snapshot)
	if definition == nil then
		return
	end
	local rotations = ShapeRotation.GetUniqueRotations(definition.Shape)
	self._rotationIndex = (self._rotationIndex % #rotations) + 1
	self._callbacks.ButtonPressed("ROTATE")

	if self._ghost ~= nil then
		for _, part in ipairs(sortedGhostParts(self._ghost)) do
			part.CFrame *= CFrame.new(0, PresentationTokens.Ghost.RotationLift, 0)
		end
	end
	recalculate(self, false)
end

function ControllerMethods.UpdateFromPointerRay(self: InternalController, ray: Ray)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingSequence ~= nil then
		return
	end
	local planeNormal = self._gridOrigin.CFrame.UpVector
	local denominator = ray.Direction:Dot(planeNormal)
	if math.abs(denominator) < 1e-5 then
		return
	end
	local distance = (self._gridOrigin.Position - ray.Origin):Dot(planeNormal) / denominator
	if distance < 0 then
		return
	end
	local worldPosition = ray.Origin + (ray.Direction * distance)
	local x, z = GridWorldTransform.WorldPositionToGridXZ(
		self._gridOrigin.CFrame,
		worldPosition,
		PresentationTokens.Grid.CellSize
	)
	if x == self._originX and z == self._originZ then
		return
	end
	self._originX = x
	self._originZ = z
	recalculate(self, false)
end

function ControllerMethods.RequestPlacement(self: InternalController)
	local snapshot = self._snapshot
	if self._destroyed
		or snapshot == nil
		or snapshot.State ~= "AwaitingPlacement"
		or snapshot.CurrentItemId == nil
		or self._pendingSequence ~= nil
	then
		return
	end
	self._callbacks.ButtonPressed("PLACE")
	if not self._valid then
		self._callbacks.ServerResponse("CLIENT_PREDICTED_INVALID", false)
		self._callbacks.Rejected()
		return
	end

	self._clientSequence += 1
	local sequence = self._clientSequence
	self._pendingSequence = sequence
	self._pendingImpactPosition = if #self._visualCells > 0
		then GridWorldTransform.CellToWorldPosition(
			self._gridOrigin.CFrame,
			self._visualCells[1],
			PresentationTokens.Grid.CellSize
		)
		else self._gridOrigin.Position
	self._pendingHeavy = snapshot.CurrentItemId == "heavy_cargo"
	for _, part in ipairs(if self._ghost ~= nil then sortedGhostParts(self._ghost) else {}) do
		TweenService:Create(
			part,
			TweenInfo.new(PresentationTokens.Timing.Instant, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = part.CFrame * CFrame.new(0, -PresentationTokens.Ghost.RequestCompression, 0) }
		):Play()
	end

	self._remote:FireServer({
		RoundId = snapshot.RoundId,
		StateVersion = snapshot.StateVersion,
		ItemId = snapshot.CurrentItemId,
		QuarterTurns = self._quarterTurns,
		OriginX = self._originX,
		OriginZ = self._originZ,
		ClientSequence = sequence,
	})
end

function ControllerMethods.HandleResponse(self: InternalController, response: PlacementResponse)
	if self._destroyed or self._pendingSequence ~= response.ClientSequence then
		return
	end
	local snapshot = self._snapshot
	if snapshot == nil or snapshot.RoundId ~= response.RoundId then
		return
	end
	self._pendingSequence = nil
	if response.Accepted then
		self._callbacks.PlacementImpact(self._pendingImpactPosition or self._gridOrigin.Position, self._pendingHeavy)
		self._callbacks.ServerResponse("ACCEPTED", true)
	else
		self._callbacks.ServerResponse(response.Reason, false)
		self._callbacks.Rejected()
		local epoch = self._renderEpoch
		if self._ghost ~= nil then
			for _, part in ipairs(sortedGhostParts(self._ghost)) do
				TweenService:Create(
					part,
					TweenInfo.new(PresentationTokens.Timing.GhostRejected, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
					{ CFrame = part.CFrame * CFrame.new(PresentationTokens.Ghost.RejectionNudge, 0, 0) }
				):Play()
			end
		end
		task.delay(PresentationTokens.Timing.GhostRejected, function()
			if not self._destroyed and epoch == self._renderEpoch then
				recalculate(self, false)
			end
		end)
	end
	self._pendingImpactPosition = nil
	self._pendingHeavy = false
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	clearGhost(self)
	self._snapshot = nil
	self._pendingSequence = nil
	self._pendingImpactPosition = nil
end

return table.freeze(PlacementController)
