--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

export type TouchToken = InputObject | string

export type Tracker = {
	Begin: (self: Tracker, token: TouchToken, position: Vector2, allowed: boolean) -> boolean,
	Move: (self: Tracker, token: TouchToken, position: Vector2) -> boolean,
	End: (self: Tracker, token: TouchToken) -> boolean,
	Cancel: (self: Tracker) -> (),
	IsActive: (self: Tracker) -> boolean,
}

type InternalTracker = Tracker & {
	_activeToken: TouchToken?,
	_lastPosition: Vector2?,
	_minimumDelta: number,
	_onPosition: (position: Vector2) -> (),
}

export type Controller = {
	SetContext: (self: Controller, touchMode: boolean, assigned: boolean, awaitingPlacement: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_surface: Frame,
	_tracker: Tracker,
	_connections: { RBXScriptConnection },
	_touchMode: boolean,
	_assigned: boolean,
	_awaitingPlacement: boolean,
	_observability: (active: boolean) -> (),
	_destroyed: boolean,
}

local TouchInputController = {}
local TrackerMethods = {}
TrackerMethods.__index = TrackerMethods
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

function TouchInputController.newTracker(minimumDelta: number, onPosition: (position: Vector2) -> ()): Tracker
	if minimumDelta < 0 or minimumDelta ~= minimumDelta or minimumDelta == math.huge then
		error("Touch tracker minimum delta must be a non-negative finite number", 2)
	end
	local self: InternalTracker = setmetatable({
		_activeToken = nil,
		_lastPosition = nil,
		_minimumDelta = minimumDelta,
		_onPosition = onPosition,
	}, TrackerMethods) :: InternalTracker
	return self
end

function TrackerMethods.Begin(self: InternalTracker, token: TouchToken, position: Vector2, allowed: boolean): boolean
	if not allowed or self._activeToken ~= nil then
		return false
	end
	self._activeToken = token
	self._lastPosition = position
	self._onPosition(position)
	return true
end

function TrackerMethods.Move(self: InternalTracker, token: TouchToken, position: Vector2): boolean
	if self._activeToken ~= token then
		return false
	end
	local previous = self._lastPosition
	if previous ~= nil and (position - previous).Magnitude < self._minimumDelta then
		return false
	end
	self._lastPosition = position
	self._onPosition(position)
	return true
end

function TrackerMethods.End(self: InternalTracker, token: TouchToken): boolean
	if self._activeToken ~= token then
		return false
	end
	self._activeToken = nil
	self._lastPosition = nil
	return true
end

function TrackerMethods.Cancel(self: InternalTracker)
	self._activeToken = nil
	self._lastPosition = nil
end

function TrackerMethods.IsActive(self: InternalTracker): boolean
	return self._activeToken ~= nil
end

function TouchInputController.ScreenPositionToRay(camera: Camera, position: Vector2): Ray
	-- InputObject.Position and Camera:ViewportPointToRay share viewport coordinates.
	-- Device-safe ScreenGui insets must not be subtracted a second time here.
	return camera:ViewportPointToRay(position.X, position.Y)
end

local function isOverInteractiveGui(surface: Frame, position: Vector2): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if guiObject ~= surface and guiObject:IsA("GuiObject") and guiObject.Visible and guiObject.Active then
			return true
		end
	end
	return false
end

local function canTrack(self: InternalController): boolean
	return self._touchMode and self._assigned and self._awaitingPlacement and not self._destroyed
end

local function refreshSurface(self: InternalController)
	local enabled = canTrack(self)
	self._surface.Visible = enabled
	self._surface.Active = enabled
	if not enabled and self._tracker:IsActive() then
		self._tracker:Cancel()
		self._observability(false)
	end
end

function TouchInputController.new(
	surface: Frame,
	onPointerRay: (ray: Ray) -> (),
	observability: ((active: boolean) -> ())?
): Controller
	local observe = observability or function(_active: boolean) end
	local tracker = TouchInputController.newTracker(1, function(position: Vector2)
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			onPointerRay(TouchInputController.ScreenPositionToRay(camera, position))
		end
	end)
	local self: InternalController = setmetatable({
		_surface = surface,
		_tracker = tracker,
		_connections = {},
		_touchMode = false,
		_assigned = false,
		_awaitingPlacement = false,
		_observability = observe,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	surface.Visible = false
	surface.Active = false
	table.insert(self._connections, surface.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or not canTrack(self) then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if self._tracker:Begin(input, position, not isOverInteractiveGui(surface, position)) then
			self._observability(true)
		end
	end))
	table.insert(self._connections, UserInputService.TouchMoved:Connect(function(input: InputObject)
		if canTrack(self) then
			self._tracker:Move(input, Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(self._connections, UserInputService.TouchEnded:Connect(function(input: InputObject)
		if self._tracker:End(input) then
			-- Ending a drag intentionally leaves the ghost at its final grid cell.
			self._observability(false)
		end
	end))
	return self
end

function ControllerMethods.SetContext(
	self: InternalController,
	touchMode: boolean,
	assigned: boolean,
	awaitingPlacement: boolean
)
	if self._destroyed then
		return
	end
	self._touchMode = touchMode
	self._assigned = assigned
	self._awaitingPlacement = awaitingPlacement
	refreshSurface(self)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._tracker:Cancel()
	self._surface.Active = false
	self._surface.Visible = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._observability(false)
end

return table.freeze(TouchInputController)
