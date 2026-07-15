--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(script.Parent.CameraController)
local CharacterController = require(script.Parent.CharacterController)
local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PlacementController = require(script.Parent.PlacementController)
local WorldMotionController = require(script.Parent.WorldMotionController)

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local StationDefinitions = require(shared:WaitForChild("World"):WaitForChild("StationDefinitions"))

type Snapshot = ClientRoundStore.Snapshot
type PlacementResponse = ClientRoundStore.PlacementResponse
type Cell = ClientRoundStore.Cell

export type Callbacks = {
	FitChanged: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
	ButtonPressed: (action: string) -> (),
	ServerResponse: (reason: string, accepted: boolean) -> (),
	PendingChanged: (pending: boolean) -> (),
	Observability: (valid: boolean?, x: number?, y: number?, z: number?) -> (),
	AssignmentChanged: (assigned: boolean, stationId: string?) -> (),
}

export type Factories = {
	CreatePlacement: (
		remote: RemoteEvent,
		station: Model,
		template: BasePart,
		callbacks: PlacementController.Callbacks
	) -> PlacementController.Controller,
	CreateWorldMotion: (station: Model) -> WorldMotionController.Controller,
}

export type Dependencies = {
	StationsRoot: Instance,
	PlaceItemRequest: RemoteEvent,
	CellBlockTemplate: BasePart,
	Camera: CameraController.Controller,
	Character: CharacterController.Controller,
	Callbacks: Callbacks,
	Factories: Factories?,
}

export type Controller = {
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> boolean,
	GetStationId: (self: Controller) -> string?,
	IsAssignedFor: (self: Controller, stationId: string?) -> boolean,
	Move: (self: Controller, deltaX: number, deltaZ: number) -> (),
	RotateClockwise: (self: Controller) -> (),
	RequestPlacement: (self: Controller) -> (),
	UpdateFromPointerRay: (self: Controller, ray: Ray) -> (),
	IsPlacementPending: (self: Controller) -> boolean,
	HandleResponse: (self: Controller, response: PlacementResponse) -> (),
	PressButton: (self: Controller, action: string) -> (),
	Destroy: (self: Controller) -> (),
}

type Binding = {
	StationId: string,
	Station: Model,
	Placement: PlacementController.Controller,
	WorldMotion: WorldMotionController.Controller,
	PreviousState: string?,
	RoundId: number?,
}

type InternalController = Controller & {
	_stationsRoot: Instance,
	_placeItemRequest: RemoteEvent,
	_cellBlockTemplate: BasePart,
	_camera: CameraController.Controller,
	_character: CharacterController.Controller,
	_callbacks: Callbacks,
	_factories: Factories,
	_binding: Binding?,
	_bindingEpoch: number,
	_lastInvalidStationId: string?,
	_destroyed: boolean,
}

local StationContextController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local defaultFactories: Factories = {
	CreatePlacement = function(
		remote: RemoteEvent,
		station: Model,
		template: BasePart,
		callbacks: PlacementController.Callbacks
	): PlacementController.Controller
		return PlacementController.new(remote, station, template, callbacks)
	end,
	CreateWorldMotion = function(station: Model): WorldMotionController.Controller
		return WorldMotionController.new(station)
	end,
}
table.freeze(defaultFactories)

local function unbind(self: InternalController)
	local binding = self._binding
	if binding == nil then
		return
	end

	-- Invalidate callback closures before destroying either station-scoped
	-- controller. Destroy may synchronously report pending-state cleanup.
	self._bindingEpoch += 1
	self._binding = nil
	self._callbacks.AssignmentChanged(false, nil)
	self._callbacks.FitChanged(nil, nil, nil, nil)
	self._callbacks.PendingChanged(false)
	self._callbacks.Observability(nil, nil, nil, nil)
	binding.Placement:Destroy()
	binding.WorldMotion:Destroy()
	self._camera:Deactivate()
	self._character:SetAssigned(false)
end

local function bind(self: InternalController, stationId: string, station: Model)
	self._bindingEpoch += 1
	local epoch = self._bindingEpoch
	local worldMotion = self._factories.CreateWorldMotion(station)

	local function isCurrentBinding(): boolean
		local current = self._binding
		return not self._destroyed
			and self._bindingEpoch == epoch
			and current ~= nil
			and current.WorldMotion == worldMotion
	end

	local placementCallbacks: PlacementController.Callbacks = {
		FitChanged = function(valid: boolean?, x: number?, y: number?, z: number?)
			if isCurrentBinding() then
				self._callbacks.FitChanged(valid, x, y, z)
			end
		end,
		GridFeedback = function(cells: { Cell }, valid: boolean)
			if isCurrentBinding() then
				worldMotion:SetGridFeedback(cells, valid)
			end
		end,
		ClearGridFeedback = function()
			if isCurrentBinding() then
				worldMotion:ClearGridFeedback()
			end
		end,
		ButtonPressed = function(action: string)
			if isCurrentBinding() then
				self._callbacks.ButtonPressed(action)
				worldMotion:PressButton(action)
			end
		end,
		PlacementImpact = function(position: Vector3, heavy: boolean)
			if isCurrentBinding() then
				worldMotion:PlayPlacementImpact(position, heavy)
				self._camera:PlayImpulse(if heavy then "HEAVY" else "LIGHT")
			end
		end,
		ServerResponse = function(reason: string, accepted: boolean)
			if isCurrentBinding() then
				self._callbacks.ServerResponse(reason, accepted)
			end
		end,
		Rejected = function()
			if isCurrentBinding() then
				worldMotion:PlayRejected()
			end
		end,
		PendingChanged = function(pending: boolean)
			if isCurrentBinding() then
				self._callbacks.PendingChanged(pending)
			end
		end,
		Observability = function(valid: boolean?, x: number?, y: number?, z: number?)
			if isCurrentBinding() then
				self._callbacks.Observability(valid, x, y, z)
			end
		end,
	}

	local created, placementOrError = pcall(
		self._factories.CreatePlacement,
		self._placeItemRequest,
		station,
		self._cellBlockTemplate,
		placementCallbacks
	)
	if not created then
		worldMotion:Destroy()
		error(string.format(
			"[ONE_MORE_ITEM][Client] Failed to create placement context for %s: %s",
			stationId,
			tostring(placementOrError)
		), 0)
	end
	local placement = placementOrError :: PlacementController.Controller
	self._binding = {
		StationId = stationId,
		Station = station,
		Placement = placement,
		WorldMotion = worldMotion,
		PreviousState = nil,
		RoundId = nil,
	}

	local activated, activationError = pcall(function()
		self._character:SetAssigned(true)
		self._camera:Activate(station)
	end)
	if not activated then
		unbind(self)
		error(string.format(
			"[ONE_MORE_ITEM][Client] Failed to activate station context for %s: %s",
			stationId,
			tostring(activationError)
		), 0)
	end
	self._callbacks.AssignmentChanged(true, stationId)
end

function StationContextController.new(dependencies: Dependencies): Controller
	local self: InternalController = setmetatable({
		_stationsRoot = dependencies.StationsRoot,
		_placeItemRequest = dependencies.PlaceItemRequest,
		_cellBlockTemplate = dependencies.CellBlockTemplate,
		_camera = dependencies.Camera,
		_character = dependencies.Character,
		_callbacks = dependencies.Callbacks,
		_factories = dependencies.Factories or defaultFactories,
		_binding = nil,
		_bindingEpoch = 0,
		_lastInvalidStationId = nil,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot): boolean
	if self._destroyed then
		return false
	end

	local definition = StationDefinitions.Get(snapshot.StationId)
	if definition == nil then
		local stationId = snapshot.StationId
		if stationId ~= nil and stationId ~= "" and stationId ~= self._lastInvalidStationId then
			warn(string.format(
				"[ONE_MORE_ITEM][Client] Ignoring non-allowlisted station assignment %q",
				stationId
			))
			self._lastInvalidStationId = stationId
		elseif stationId == nil or stationId == "" then
			self._lastInvalidStationId = nil
		end
		unbind(self)
		return false
	end
	self._lastInvalidStationId = nil

	local binding = self._binding
	if binding == nil or binding.StationId ~= definition.Id then
		unbind(self)
		local station = StationDefinitions.Resolve(self._stationsRoot, definition.Id)
		if station == nil then
			error(string.format(
				"[ONE_MORE_ITEM][Client] Missing authored %s Model with StationId=%s and StationIndex=%d",
				definition.ModelName,
				definition.Id,
				definition.Index
			), 2)
		end
		bind(self, definition.Id, station)
		binding = self._binding
	end

	if binding == nil then
		return false
	end
	binding.RoundId = snapshot.RoundId
	if binding.PreviousState ~= snapshot.State then
		binding.WorldMotion:SetState(snapshot.State, binding.PreviousState)
		if snapshot.State == "Shipping" then
			self._camera:PlayImpulse("SHIPPING")
		elseif snapshot.State == "Failing" then
			self._camera:PlayImpulse("FAILURE")
		end
		binding.PreviousState = snapshot.State
	end
	binding.Placement:ApplySnapshot(snapshot)
	return true
end

function ControllerMethods.GetStationId(self: InternalController): string?
	local binding = self._binding
	return if binding ~= nil then binding.StationId else nil
end

function ControllerMethods.IsAssignedFor(self: InternalController, stationId: string?): boolean
	local definition = StationDefinitions.Get(stationId)
	local binding = self._binding
	return definition ~= nil and binding ~= nil and binding.StationId == definition.Id
end

function ControllerMethods.Move(self: InternalController, deltaX: number, deltaZ: number)
	local binding = self._binding
	if binding ~= nil then
		binding.Placement:Move(deltaX, deltaZ)
	end
end

function ControllerMethods.RotateClockwise(self: InternalController)
	local binding = self._binding
	if binding ~= nil then
		binding.Placement:RotateClockwise()
	end
end

function ControllerMethods.RequestPlacement(self: InternalController)
	local binding = self._binding
	if binding ~= nil then
		binding.Placement:RequestPlacement()
	end
end

function ControllerMethods.UpdateFromPointerRay(self: InternalController, ray: Ray)
	local binding = self._binding
	if binding ~= nil then
		binding.Placement:UpdateFromPointerRay(ray)
	end
end

function ControllerMethods.IsPlacementPending(self: InternalController): boolean
	local binding = self._binding
	return binding ~= nil and binding.Placement:IsPlacementPending()
end

function ControllerMethods.HandleResponse(self: InternalController, response: PlacementResponse)
	local binding = self._binding
	if binding ~= nil and binding.RoundId == response.RoundId then
		binding.Placement:HandleResponse(response)
	end
end

function ControllerMethods.PressButton(self: InternalController, action: string)
	local binding = self._binding
	if binding ~= nil then
		binding.WorldMotion:PressButton(action)
	end
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	unbind(self)
	self._destroyed = true
end

return table.freeze(StationContextController)
