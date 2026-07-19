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

type VisualResult = {
	Rotation: Rotation,
	Cells: { Cell },
	Valid: boolean,
	PlacementY: number?,
	Color: Color3,
}

type PendingPlacement = {
	RoundId: number,
	ClientSequence: number,
	Cells: { Cell },
	ImpactPosition: Vector3,
	Heavy: boolean,
	ResponseReceived: boolean,
	SnapshotAccepted: boolean,
	VisualCompleted: boolean,
	DeferredSnapshot: Snapshot?,
}

export type Callbacks = {
	FitChanged: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
	GridFeedback: (cells: { Cell }, valid: boolean) -> (),
	ClearGridFeedback: () -> (),
	ButtonPressed: (action: string) -> (),
	PlacementImpact: (position: Vector3, heavy: boolean) -> (),
	ServerResponse: (reason: string, accepted: boolean) -> (),
	Rejected: () -> (),
	PendingChanged: (pending: boolean) -> (),
	Observability: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
}

export type Controller = {
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> (),
	Move: (self: Controller, deltaX: number, deltaZ: number) -> (),
	RotateClockwise: (self: Controller) -> (),
	UpdateFromPointerRay: (self: Controller, ray: Ray) -> (),
	RequestPlacement: (self: Controller) -> (),
	IsPlacementPending: (self: Controller) -> boolean,
	HandleResponse: (self: Controller, response: PlacementResponse) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_remote: RemoteEvent,
	_station: Model,
	_template: BasePart,
	_gridOrigin: BasePart,
	_presentationPoint: BasePart,
	_presentationPointColor: Color3,
	_presentationPointMaterial: Enum.Material,
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
	_grounding: BasePart?,
	_presentationModel: Model?,
	_clientSequence: number,
	_pendingPlacement: PendingPlacement?,
	_acceptedCorrelations: { [string]: boolean },
	_acceptedCorrelationOrder: { string },
	_renderEpoch: number,
	_presentationEpoch: number,
	_ghostTweens: { Tween },
	_presentationTweens: { Tween },
	_destroyed: boolean,
}

local PlacementController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local MAX_ACCEPTED_CORRELATIONS = 8

local function setPendingPlacement(self: InternalController, pending: PendingPlacement?)
	if self._pendingPlacement == pending then
		return
	end
	self._pendingPlacement = pending
	self._callbacks.PendingChanged(pending ~= nil)
end

local function requirePart(parent: Instance, name: string): BasePart
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("BasePart") then
		error(string.format("PlacementController requires BasePart %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireChild(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, 10)
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

local function correlationKey(roundId: number, clientSequence: number): string
	return string.format("%d:%d", roundId, clientSequence)
end

local function rememberAcceptedCorrelation(self: InternalController, roundId: number, clientSequence: number)
	local key = correlationKey(roundId, clientSequence)
	if self._acceptedCorrelations[key] then
		return
	end
	self._acceptedCorrelations[key] = true
	table.insert(self._acceptedCorrelationOrder, key)
	if #self._acceptedCorrelationOrder > MAX_ACCEPTED_CORRELATIONS then
		local expired = table.remove(self._acceptedCorrelationOrder, 1)
		self._acceptedCorrelations[expired] = nil
	end
end

local function consumeAcceptedCorrelation(self: InternalController, roundId: number, clientSequence: number): boolean
	local key = correlationKey(roundId, clientSequence)
	if not self._acceptedCorrelations[key] then
		return false
	end
	self._acceptedCorrelations[key] = nil
	local index = table.find(self._acceptedCorrelationOrder, key)
	if index ~= nil then
		table.remove(self._acceptedCorrelationOrder, index)
	end
	return true
end

local function translatedCells(rotation: Rotation, x: number, y: number, z: number): { Cell }
	local cells: { Cell } = {}
	for _, cell in ipairs(rotation.Cells) do
		table.insert(cells, { X = cell.X + x, Y = cell.Y + y, Z = cell.Z + z })
	end
	return cells
end

local function cancelTweens(tweens: { Tween })
	for _, tween in ipairs(tweens) do
		tween:Cancel()
	end
	table.clear(tweens)
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

local function sortedModelParts(model: Model): { BasePart }
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

local function restorePresentationPoint(self: InternalController)
	self._presentationPoint.Color = self._presentationPointColor
	self._presentationPoint.Material = self._presentationPointMaterial
end

local function clearPresentation(self: InternalController)
	self._presentationEpoch += 1
	cancelTweens(self._presentationTweens)
	if self._presentationModel ~= nil then
		self._presentationModel:Destroy()
	end
	self._presentationModel = nil
	restorePresentationPoint(self)
end

local function clearGhost(self: InternalController)
	self._renderEpoch += 1
	cancelTweens(self._ghostTweens)
	if self._ghost ~= nil then
		self._ghost:Destroy()
	end
	if self._grounding ~= nil then
		self._grounding:Destroy()
	end
	self._ghost = nil
	self._highlight = nil
	self._grounding = nil
	self._visualCells = {}
	self._callbacks.ClearGridFeedback()
	self._callbacks.FitChanged(nil, nil, nil, nil)
	self._callbacks.Observability(nil, nil, nil, nil)
end

local function createGhostHighlight(self: InternalController, model: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "GhostOutline"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.90
	highlight.OutlineTransparency = 0.14
	highlight.Parent = model
	self._highlight = highlight
end

local function updateGrounding(self: InternalController, result: VisualResult)
	if #result.Cells == 0 then
		if self._grounding ~= nil then
			self._grounding:Destroy()
			self._grounding = nil
		end
		return
	end
	local minimumX = math.huge
	local minimumY = math.huge
	local minimumZ = math.huge
	local maximumX = -math.huge
	local maximumZ = -math.huge
	for _, cell in ipairs(result.Cells) do
		minimumX = math.min(minimumX, cell.X)
		minimumY = math.min(minimumY, cell.Y)
		minimumZ = math.min(minimumZ, cell.Z)
		maximumX = math.max(maximumX, cell.X)
		maximumZ = math.max(maximumZ, cell.Z)
	end
	local grounding = self._grounding
	if grounding == nil then
		grounding = Instance.new("Part")
		grounding.Name = "LocalPlacementGrounding"
		grounding.Anchored = true
		grounding.CanCollide = false
		grounding.CanTouch = false
		grounding.CanQuery = false
		grounding.CastShadow = false
		grounding.Material = Enum.Material.SmoothPlastic
		grounding.Parent = self._runtimeContainer
		self._grounding = grounding
	end
	local centerX = (minimumX + maximumX) * 0.5
	local centerZ = (minimumZ + maximumZ) * 0.5
	local width = ((maximumX - minimumX) * PresentationTokens.Grid.CellSize) + self._template.Size.X
	local depth = ((maximumZ - minimumZ) * PresentationTokens.Grid.CellSize) + self._template.Size.Z
	local localY = (minimumY * PresentationTokens.Grid.CellSize) - (self._template.Size.Y * 0.5) - 0.035
	grounding.Size = Vector3.new(width, 0.06, depth)
	grounding.CFrame = self._gridOrigin.CFrame * CFrame.new(
		centerX * PresentationTokens.Grid.CellSize,
		localY,
		centerZ * PresentationTokens.Grid.CellSize
	)
	local semantic = if result.Valid then PresentationTokens.Color.Green else PresentationTokens.Color.Red
	grounding.Color = PresentationTokens.Color.Background:Lerp(semantic, 0.24)
	grounding.Transparency = if result.Valid then 0.42 else 0.52
end

local function solveVisual(self: InternalController, snapshot: Snapshot): VisualResult?
	if snapshot.State ~= "AwaitingPlacement" and snapshot.State ~= "PresentingItem" then
		return nil
	end
	local definition = currentDefinition(snapshot)
	if definition == nil then
		return nil
	end
	local rotations = ShapeRotation.GetUniqueRotations(definition.Shape)
	if #rotations == 0 then
		return nil
	end
	self._rotationIndex = math.clamp(self._rotationIndex, 1, #rotations)
	local rotation = rotations[self._rotationIndex]
	local placement = PlacementSolver.GetAutoDropPlacement(
		createGrid(snapshot),
		rotation,
		self._originX,
		self._originZ,
		definition.ShapeId,
		self._rotationIndex
	)
	if placement ~= nil then
		return {
			Rotation = rotation,
			Cells = copyCells(placement.Cells),
			Valid = true,
			PlacementY = placement.Origin.Y,
			Color = definition.Color,
		}
	end
	local fallbackY = math.max(0, PresentationTokens.Grid.Height - rotation.SizeY)
	return {
		Rotation = rotation,
		Cells = translatedCells(rotation, self._originX, fallbackY, self._originZ),
		Valid = false,
		PlacementY = nil,
		Color = definition.Color,
	}
end

local function applyVisualResult(self: InternalController, result: VisualResult)
	self._quarterTurns = result.Rotation.QuarterTurns
	self._valid = result.Valid
	self._placementY = result.PlacementY
	self._visualCells = copyCells(result.Cells)
	self._callbacks.GridFeedback(result.Cells, result.Valid)
	self._callbacks.FitChanged(result.Valid, self._originX, result.PlacementY, self._originZ)
	self._callbacks.Observability(result.Valid, self._originX, result.PlacementY, self._originZ)
end

local function setGhostAppearance(self: InternalController, result: VisualResult, parts: { BasePart })
	local targetColor = if result.Valid then PresentationTokens.Color.Green else PresentationTokens.Color.Red
	if self._highlight ~= nil then
		self._highlight.FillColor = targetColor
		self._highlight.OutlineColor = targetColor
	end
	for _, part in ipairs(parts) do
		part.Color = result.Color:Lerp(targetColor, 0.22)
		part.Transparency = if result.Valid
			then PresentationTokens.Ghost.Transparency
			else PresentationTokens.Ghost.InvalidTransparency
	end
	updateGrounding(self, result)
end

local function renderGhost(self: InternalController, result: VisualResult, immediate: boolean)
	cancelTweens(self._ghostTweens)
	local parts = if self._ghost ~= nil then sortedModelParts(self._ghost) else {}
	if self._ghost == nil or #parts ~= #result.Cells then
		if self._ghost ~= nil then
			self._ghost:Destroy()
		end
		self._ghost = DevelopmentItemRenderer.RenderCells(
			self._template,
			self._runtimeContainer,
			"LocalPlacementGhost",
			result.Cells,
			self._gridOrigin.CFrame,
			PresentationTokens.Grid.CellSize,
			result.Color,
			PresentationTokens.Ghost.Transparency
		)
		createGhostHighlight(self, self._ghost)
		parts = sortedModelParts(self._ghost)
	end
	setGhostAppearance(self, result, parts)
	for index, part in ipairs(parts) do
		local target = GridWorldTransform.CellToCFrame(
			self._gridOrigin.CFrame,
			result.Cells[index],
			PresentationTokens.Grid.CellSize
		)
		if immediate then
			part.CFrame = target
		else
			local tween = TweenService:Create(
				part,
				TweenInfo.new(PresentationTokens.Timing.GhostMove, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ CFrame = target }
			)
			table.insert(self._ghostTweens, tween)
			tween:Play()
		end
	end
end

local function recalculate(self: InternalController, immediate: boolean)
	local snapshot = self._snapshot
	if snapshot == nil or snapshot.State ~= "AwaitingPlacement" then
		clearGhost(self)
		return
	end
	local result = solveVisual(self, snapshot)
	if result == nil then
		clearGhost(self)
		return
	end
	applyVisualResult(self, result)
	renderGhost(self, result, immediate)
end

local function setInitialOrigin(self: InternalController, snapshot: Snapshot)
	self._rotationIndex = 1
	local definition = currentDefinition(snapshot)
	if definition == nil then
		return
	end
	local firstRotation = ShapeRotation.GetUniqueRotations(definition.Shape)[1]
	if firstRotation ~= nil then
		self._originX = math.floor((PresentationTokens.Grid.Width - firstRotation.SizeX) * 0.5)
		self._originZ = math.floor((PresentationTokens.Grid.Depth - firstRotation.SizeZ) * 0.5)
	end
end

local function presentationStartFrame(self: InternalController, cell: Cell, rotation: Rotation): CFrame
	local centerX = (rotation.SizeX - 1) * 0.5
	local centerY = (rotation.SizeY - 1) * 0.5
	local centerZ = (rotation.SizeZ - 1) * 0.5
	local verticalClearance = (self._presentationPoint.Size.Y + self._template.Size.Y) * 0.5 + 0.28
	return self._presentationPoint.CFrame * CFrame.new(
		(cell.X - centerX) * PresentationTokens.Grid.CellSize,
		((cell.Y - centerY) * PresentationTokens.Grid.CellSize) + verticalClearance,
		(cell.Z - centerZ) * PresentationTokens.Grid.CellSize
	)
end

local function beginItemPresentation(self: InternalController, snapshot: Snapshot)
	clearPresentation(self)
	clearGhost(self)
	local result = solveVisual(self, snapshot)
	if result == nil then
		return
	end
	self._presentationEpoch += 1
	local epoch = self._presentationEpoch
	local model = DevelopmentItemRenderer.RenderCells(
		self._template,
		self._runtimeContainer,
		"ItemPresentation",
		result.Rotation.Cells,
		CFrame.new(),
		PresentationTokens.Grid.CellSize,
		result.Color,
		0.08
	)
	model:SetAttribute("TravelDuration", PresentationTokens.Timing.PresentationTravel)
	model:SetAttribute("SettleDuration", PresentationTokens.Timing.PresentationSettle)
	model:SetAttribute("HoldDuration", PresentationTokens.Timing.PresentationHold)
	self._presentationModel = model
	local parts = sortedModelParts(model)
	local lift = self._gridOrigin.CFrame.UpVector * PresentationTokens.Ghost.RotationLift
	for index, part in ipairs(parts) do
		part.CFrame = presentationStartFrame(self, result.Rotation.Cells[index], result.Rotation)
		local target = GridWorldTransform.CellToCFrame(
			self._gridOrigin.CFrame,
			result.Cells[index],
			PresentationTokens.Grid.CellSize
		) + lift
		local tween = TweenService:Create(
			part,
			TweenInfo.new(PresentationTokens.Timing.PresentationTravel, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ CFrame = target, Transparency = PresentationTokens.Ghost.Transparency }
		)
		table.insert(self._presentationTweens, tween)
		tween:Play()
	end
	self._presentationPoint.Material = Enum.Material.Neon
	self._presentationPoint.Color = PresentationTokens.Color.Cyan
	local pointTween = TweenService:Create(
		self._presentationPoint,
		TweenInfo.new(PresentationTokens.Timing.Panel, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Color = self._presentationPointColor }
	)
	table.insert(self._presentationTweens, pointTween)
	pointTween:Play()

	task.delay(PresentationTokens.Timing.PresentationTravel, function()
		if self._destroyed or self._presentationEpoch ~= epoch or self._presentationModel ~= model then
			return
		end
		for index, part in ipairs(parts) do
			local target = GridWorldTransform.CellToCFrame(
				self._gridOrigin.CFrame,
				result.Cells[index],
				PresentationTokens.Grid.CellSize
			)
			local settle = TweenService:Create(
				part,
				TweenInfo.new(PresentationTokens.Timing.PresentationSettle, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ CFrame = target }
			)
			table.insert(self._presentationTweens, settle)
			settle:Play()
		end
	end)
end

local function handoffPresentationToGhost(self: InternalController): boolean
	local model = self._presentationModel
	if model == nil then
		return false
	end
	self._presentationEpoch += 1
	cancelTweens(self._presentationTweens)
	self._presentationModel = nil
	restorePresentationPoint(self)
	model.Name = "LocalPlacementGhost"
	self._ghost = model
	createGhostHighlight(self, model)
	return true
end

local function nearestTargetAssignment(starts: { CFrame }, targets: { CFrame }): { CFrame }
	local assigned: { CFrame } = {}
	local used: { [number]: boolean } = {}
	for _, start in ipairs(starts) do
		local bestIndex = 1
		local bestDistance = math.huge
		for index, target in ipairs(targets) do
			if not used[index] then
				local distance = (start.Position - target.Position).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					bestIndex = index
				end
			end
		end
		used[bestIndex] = true
		table.insert(assigned, targets[bestIndex])
	end
	return assigned
end

local function animateRotation(self: InternalController, result: VisualResult)
	local model = self._ghost
	local parts = if model ~= nil then sortedModelParts(model) else {}
	if model == nil or #parts ~= #result.Cells then
		renderGhost(self, result, true)
		return
	end
	cancelTweens(self._ghostTweens)
	self._renderEpoch += 1
	local epoch = self._renderEpoch
	setGhostAppearance(self, result, parts)

	local pivotLocal = Vector3.zero
	local localFrames: { CFrame } = {}
	for _, part in ipairs(parts) do
		local localFrame = self._gridOrigin.CFrame:ToObjectSpace(part.CFrame)
		table.insert(localFrames, localFrame)
		pivotLocal += localFrame.Position
	end
	pivotLocal /= #localFrames

	local overshootFrames: { CFrame } = {}
	local turn = CFrame.new(pivotLocal + Vector3.new(0, PresentationTokens.Ghost.RotationLift, 0))
		* CFrame.Angles(0, math.rad(-94), 0)
		* CFrame.new(-pivotLocal)
	for index, part in ipairs(parts) do
		local overshoot = self._gridOrigin.CFrame * turn * localFrames[index]
		table.insert(overshootFrames, overshoot)
		local tween = TweenService:Create(
			part,
			TweenInfo.new(PresentationTokens.Timing.GhostRotate, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ CFrame = overshoot }
		)
		table.insert(self._ghostTweens, tween)
		tween:Play()
	end

	local targetFrames: { CFrame } = {}
	for _, cell in ipairs(result.Cells) do
		table.insert(targetFrames, GridWorldTransform.CellToCFrame(
			self._gridOrigin.CFrame,
			cell,
			PresentationTokens.Grid.CellSize
		))
	end
	local settleFrames = nearestTargetAssignment(overshootFrames, targetFrames)
	task.delay(PresentationTokens.Timing.GhostRotate, function()
		if self._destroyed or self._renderEpoch ~= epoch or self._ghost ~= model then
			return
		end
		cancelTweens(self._ghostTweens)
		for index, part in ipairs(parts) do
			local tween = TweenService:Create(
				part,
				TweenInfo.new(PresentationTokens.Timing.GhostSettle, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ CFrame = settleFrames[index] }
			)
			table.insert(self._ghostTweens, tween)
			tween:Play()
		end
		task.delay(PresentationTokens.Timing.GhostSettle, function()
			if self._destroyed or self._renderEpoch ~= epoch or self._ghost ~= model then
				return
			end
			for index, part in ipairs(parts) do
				part.CFrame = settleFrames[index]
			end
			cancelTweens(self._ghostTweens)
		end)
	end)
end

local function releaseAcceptedPending(self: InternalController, pending: PendingPlacement)
	pending.VisualCompleted = true
	if not pending.ResponseReceived then
		rememberAcceptedCorrelation(self, pending.RoundId, pending.ClientSequence)
	end
	if self._pendingPlacement == pending then
		setPendingPlacement(self, nil)
	end
	local deferredSnapshot = pending.DeferredSnapshot
	pending.DeferredSnapshot = nil
	if deferredSnapshot ~= nil and not self._destroyed then
		self:ApplySnapshot(deferredSnapshot)
	end
end

local function beginAcceptedSnap(self: InternalController, pending: PendingPlacement)
	if pending.SnapshotAccepted then
		return
	end
	pending.SnapshotAccepted = true
	local model = self._ghost
	local parts = if model ~= nil then sortedModelParts(model) else {}
	if model == nil or #parts ~= #pending.Cells then
		self._callbacks.PlacementImpact(pending.ImpactPosition, pending.Heavy)
		releaseAcceptedPending(self, pending)
		return
	end
	cancelTweens(self._ghostTweens)
	self._renderEpoch += 1
	local epoch = self._renderEpoch
	local targets: { CFrame } = {}
	for _, cell in ipairs(pending.Cells) do
		table.insert(targets, GridWorldTransform.CellToCFrame(
			self._gridOrigin.CFrame,
			cell,
			PresentationTokens.Grid.CellSize
		))
	end
	local starts: { CFrame } = {}
	for _, part in ipairs(parts) do
		table.insert(starts, part.CFrame)
	end
	local assignedTargets = nearestTargetAssignment(starts, targets)
	for index, part in ipairs(parts) do
		local tween = TweenService:Create(
			part,
			TweenInfo.new(PresentationTokens.Timing.GhostAccepted, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ CFrame = assignedTargets[index], Transparency = 0.12 }
		)
		table.insert(self._ghostTweens, tween)
		tween:Play()
	end
	task.delay(PresentationTokens.Timing.GhostAccepted, function()
		if self._destroyed or self._renderEpoch ~= epoch or self._pendingPlacement ~= pending then
			return
		end
		for index, part in ipairs(parts) do
			part.CFrame = assignedTargets[index]
		end
		self._callbacks.PlacementImpact(pending.ImpactPosition, pending.Heavy)
		clearGhost(self)
		releaseAcceptedPending(self, pending)
	end)
end

function PlacementController.new(
	remote: RemoteEvent,
	station: Model,
	template: BasePart,
	callbacks: Callbacks
): Controller
	local crate = requireChild(station, "Crate")
	local presentationPoint = requirePart(station, "PresentationPoint")
	local self: InternalController = setmetatable({
		_remote = remote,
		_station = station,
		_template = template,
		_gridOrigin = requirePart(crate, "GridOrigin"),
		_presentationPoint = presentationPoint,
		_presentationPointColor = presentationPoint.Color,
		_presentationPointMaterial = presentationPoint.Material,
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
		_grounding = nil,
		_presentationModel = nil,
		_clientSequence = 0,
		_pendingPlacement = nil,
		_acceptedCorrelations = {},
		_acceptedCorrelationOrder = {},
		_renderEpoch = 0,
		_presentationEpoch = 0,
		_ghostTweens = {},
		_presentationTweens = {},
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot)
	if self._destroyed then
		return
	end
	local previous = self._snapshot
	local pending = self._pendingPlacement
	local provesAcceptance = pending ~= nil
		and previous ~= nil
		and previous.RoundId == pending.RoundId
		and previous.State == "AwaitingPlacement"
		and snapshot.RoundId == pending.RoundId
		and (snapshot.State == "Decision" or snapshot.State == "Shipping")
	if provesAcceptance and pending ~= nil then
		self._snapshot = snapshot
		clearPresentation(self)
		beginAcceptedSnap(self, pending)
		return
	end
	if pending ~= nil and pending.SnapshotAccepted then
		if snapshot.RoundId == pending.RoundId
			and (snapshot.State == "Decision" or snapshot.State == "Shipping")
		then
			-- A later authoritative snapshot in the same accepted state must not
			-- cancel the in-flight 0.10-second snap.
			self._snapshot = snapshot
		else
			-- Store the newest authoritative state immediately at the client-store
			-- layer, but defer this controller's next visual until the accepted
			-- snap releases its ghost.
			pending.DeferredSnapshot = snapshot
		end
		return
	end
	self._snapshot = snapshot

	local changedRound = previous ~= nil and previous.RoundId ~= snapshot.RoundId
	local changedItem = previous == nil
		or changedRound
		or previous.CurrentItemId ~= snapshot.CurrentItemId
		or previous.CurrentShapeId ~= snapshot.CurrentShapeId
	if changedItem then
		setInitialOrigin(self, snapshot)
		setPendingPlacement(self, nil)
	end

	if snapshot.State == "PresentingItem" then
		local enteringPresentation = previous == nil
			or previous.State ~= "PresentingItem"
			or changedItem
		if enteringPresentation then
			-- A legal sequence may repeat the same item and shape. Every authored
			-- presentation still begins from the ordinary centered orientation,
			-- never the player's prior placement transform.
			setInitialOrigin(self, snapshot)
			beginItemPresentation(self, snapshot)
		end
		return
	elseif snapshot.State == "AwaitingPlacement" then
		local handedOff = previous ~= nil
			and previous.State == "PresentingItem"
			and handoffPresentationToGhost(self)
		if not handedOff then
			clearPresentation(self)
		end
		recalculate(self, true)
		return
	end

	if pending ~= nil and not pending.SnapshotAccepted then
		setPendingPlacement(self, nil)
	end
	clearPresentation(self)
	clearGhost(self)
end

function ControllerMethods.Move(self: InternalController, deltaX: number, deltaZ: number)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingPlacement ~= nil then
		return
	end
	self._originX = math.clamp(self._originX + deltaX, 0, PresentationTokens.Grid.Width - 1)
	self._originZ = math.clamp(self._originZ + deltaZ, 0, PresentationTokens.Grid.Depth - 1)
	recalculate(self, false)
end

function ControllerMethods.RotateClockwise(self: InternalController)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingPlacement ~= nil then
		return
	end
	local definition = currentDefinition(snapshot)
	if definition == nil then
		return
	end
	local rotations = ShapeRotation.GetUniqueRotations(definition.Shape)
	if #rotations == 0 then
		return
	end
	self._rotationIndex = (self._rotationIndex % #rotations) + 1
	self._callbacks.ButtonPressed("ROTATE")
	local result = solveVisual(self, snapshot)
	if result == nil then
		clearGhost(self)
		return
	end
	applyVisualResult(self, result)
	animateRotation(self, result)
end

function ControllerMethods.UpdateFromPointerRay(self: InternalController, ray: Ray)
	local snapshot = self._snapshot
	if self._destroyed or snapshot == nil or snapshot.State ~= "AwaitingPlacement" or self._pendingPlacement ~= nil then
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

function ControllerMethods.IsPlacementPending(self: InternalController): boolean
	return self._pendingPlacement ~= nil
end

function ControllerMethods.RequestPlacement(self: InternalController)
	local snapshot = self._snapshot
	if self._destroyed
		or snapshot == nil
		or snapshot.State ~= "AwaitingPlacement"
		or snapshot.CurrentItemId == nil
		or self._pendingPlacement ~= nil
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
	local impactPosition = if #self._visualCells > 0
		then GridWorldTransform.CellToWorldPosition(
			self._gridOrigin.CFrame,
			self._visualCells[1],
			PresentationTokens.Grid.CellSize
		)
		else self._gridOrigin.Position
	local pendingPlacement: PendingPlacement = {
		RoundId = snapshot.RoundId,
		ClientSequence = sequence,
		Cells = copyCells(self._visualCells),
		ImpactPosition = impactPosition,
		Heavy = snapshot.CurrentItemId == "heavy_cargo",
		ResponseReceived = false,
		SnapshotAccepted = false,
		VisualCompleted = false,
		DeferredSnapshot = nil,
	}
	setPendingPlacement(self, pendingPlacement)
	cancelTweens(self._ghostTweens)
	for _, part in ipairs(if self._ghost ~= nil then sortedModelParts(self._ghost) else {}) do
		local tween = TweenService:Create(
			part,
			TweenInfo.new(PresentationTokens.Timing.Instant, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = part.CFrame - (self._gridOrigin.CFrame.UpVector * PresentationTokens.Ghost.RequestCompression) }
		)
		table.insert(self._ghostTweens, tween)
		tween:Play()
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
	if self._destroyed then
		return
	end
	local pending = self._pendingPlacement
	if pending == nil
		or pending.RoundId ~= response.RoundId
		or pending.ClientSequence ~= response.ClientSequence
	then
		if consumeAcceptedCorrelation(self, response.RoundId, response.ClientSequence) then
			if not response.Accepted then
				warn("[ONE_MORE_ITEM][Client] Delayed placement response disagreed with an authoritative accepted-state transition")
			end
			self._callbacks.ServerResponse(response.Reason, response.Accepted)
		end
		return
	end
	pending.ResponseReceived = true
	if response.Accepted then
		self._callbacks.ServerResponse("ACCEPTED", true)
		if pending.VisualCompleted then
			setPendingPlacement(self, nil)
		end
		return
	end

	if pending.SnapshotAccepted then
		warn("[ONE_MORE_ITEM][Client] Placement response disagreed with an authoritative accepted-state transition")
		self._callbacks.ServerResponse(response.Reason, false)
		return
	end
	setPendingPlacement(self, nil)
	self._callbacks.ServerResponse(response.Reason, false)
	self._callbacks.Rejected()
	cancelTweens(self._ghostTweens)
	local epoch = self._renderEpoch
	if self._ghost ~= nil then
		for _, part in ipairs(sortedModelParts(self._ghost)) do
			local tween = TweenService:Create(
				part,
				TweenInfo.new(PresentationTokens.Timing.GhostRejected, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ CFrame = part.CFrame + (self._gridOrigin.CFrame.RightVector * PresentationTokens.Ghost.RejectionNudge) }
			)
			table.insert(self._ghostTweens, tween)
			tween:Play()
		end
	end
	task.delay(PresentationTokens.Timing.GhostRejected, function()
		if not self._destroyed and epoch == self._renderEpoch then
			recalculate(self, false)
		end
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	clearPresentation(self)
	clearGhost(self)
	self._snapshot = nil
	setPendingPlacement(self, nil)
	table.clear(self._acceptedCorrelations)
	table.clear(self._acceptedCorrelationOrder)
end

return table.freeze(PlacementController)
