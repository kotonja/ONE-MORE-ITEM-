--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PresentationTokens = require(script.Parent.PresentationTokens)
local InputModeStore = require(script.Parent.InputModeStore)
local ResponsiveLayout = require(script.Parent.ResponsiveLayout)

export type ImpulseKind = "LIGHT" | "HEAVY" | "SHIPPING" | "FAILURE"
export type TransitionKind = "INACTIVE" | "ARRIVAL" | "RETARGET" | "UNCHANGED"
type InputMode = InputModeStore.InputMode
type LayoutClass = ResponsiveLayout.LayoutClass

export type ReadinessState = {
	Safe: boolean,
	Settled: boolean,
	StationId: string?,
}

type ReadinessListener = (state: ReadinessState) -> ()

export type Controller = {
	PrepareWaitingView: (self: Controller, anchor: BasePart?, focus: BasePart?, fallbackCenter: Vector3) -> boolean,
	Activate: (self: Controller, station: Model) -> (),
	SetPresentation: (self: Controller, layoutClass: LayoutClass, inputMode: InputMode) -> (),
	Deactivate: (self: Controller) -> (),
	PlayImpulse: (self: Controller, kind: ImpulseKind) -> (),
	GetReadiness: (self: Controller) -> ReadinessState,
	SubscribeReadiness: (self: Controller, listener: ReadinessListener) -> (() -> ()),
	Destroy: (self: Controller) -> (),
}

type SavedCamera = {
	CameraType: Enum.CameraType,
	CameraSubject: Humanoid | BasePart?,
	CFrame: CFrame,
	FieldOfView: number,
}

type InternalController = Controller & {
	_camera: Camera?,
	_saved: SavedCamera?,
	_station: Model?,
	_focus: BasePart?,
	_anchorName: string?,
	_layoutClass: LayoutClass,
	_inputMode: InputMode,
	_target: CFrame?,
	_waitingTarget: CFrame?,
	_tween: Tween?,
	_impulseEpoch: number,
	_readiness: ReadinessState,
	_readinessListeners: { [number]: ReadinessListener },
	_nextReadinessListenerId: number,
	_destroyed: boolean,
}

local CameraController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function requirePart(parent: Instance, name: string): BasePart
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("BasePart") then
		error(string.format("CameraController requires BasePart %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function targetFrom(anchor: BasePart, focus: BasePart): CFrame
	if (anchor.Position - focus.Position).Magnitude < 0.01 then
		return anchor.CFrame
	end
	return CFrame.lookAt(anchor.Position, focus.Position, anchor.CFrame.UpVector)
end

local function restoredCameraSubject(savedSubject: Humanoid | BasePart?): Humanoid | BasePart?
	if savedSubject ~= nil and savedSubject.Parent ~= nil then
		return savedSubject
	end
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		return character:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

local function copyReadiness(state: ReadinessState): ReadinessState
	return table.freeze({
		Safe = state.Safe,
		Settled = state.Settled,
		StationId = state.StationId,
	}) :: ReadinessState
end

local function publishReadiness(
	self: InternalController,
	safe: boolean,
	settled: boolean,
	stationId: string?
)
	local current = self._readiness
	if current.Safe == safe and current.Settled == settled and current.StationId == stationId then
		return
	end
	local nextState = copyReadiness({
		Safe = safe,
		Settled = settled,
		StationId = stationId,
	})
	self._readiness = nextState
	for _, listener in pairs(self._readinessListeners) do
		listener(nextState)
	end
end

local function stationIdFor(station: Model): string
	local stationId = station:GetAttribute("StationId")
	return if type(stationId) == "string" and stationId ~= "" then stationId else station.Name
end

local function saveCameraIfNeeded(self: InternalController, camera: Camera)
	if self._saved ~= nil then
		return
	end
	self._saved = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
	}
end

local function restoreSavedCamera(self: InternalController)
	local camera = self._camera
	local saved = self._saved
	if camera ~= nil and saved ~= nil then
		camera.CameraType = saved.CameraType
		camera.CameraSubject = restoredCameraSubject(saved.CameraSubject)
		camera.CFrame = saved.CFrame
		camera.FieldOfView = saved.FieldOfView
	end
	self._saved = nil
end

function CameraController.SelectAnchorName(layoutClass: LayoutClass, inputMode: InputMode): string
	if layoutClass == "Portrait" then
		return "CameraAnchorTouchPortrait"
	elseif layoutClass == "CompactLandscape" and inputMode == "Touch" then
		return "CameraAnchorTouchLandscape"
	end
	return "CameraAnchor"
end

function CameraController.ResolveTransition(
	active: boolean,
	currentAnchorName: string?,
	layoutClass: LayoutClass,
	inputMode: InputMode
): TransitionKind
	if not active then
		return "INACTIVE"
	end
	local nextAnchorName = CameraController.SelectAnchorName(layoutClass, inputMode)
	if currentAnchorName == nil then
		return "ARRIVAL"
	elseif currentAnchorName == nextAnchorName then
		return "UNCHANGED"
	end
	return "RETARGET"
end

function CameraController.IsCurrentImpulseEpoch(impulseEpoch: number, currentEpoch: number): boolean
	return impulseEpoch == currentEpoch
end

local function stopTween(self: InternalController)
	local tween = self._tween
	if tween ~= nil then
		self._tween = nil
		tween:Cancel()
	end
end

local function retarget(self: InternalController)
	local station = self._station
	local focus = self._focus
	local camera = self._camera
	local transition = CameraController.ResolveTransition(
		station ~= nil and focus ~= nil and camera ~= nil,
		self._anchorName,
		self._layoutClass,
		self._inputMode
	)
	if transition ~= "RETARGET" or station == nil or focus == nil or camera == nil then
		return
	end
	local anchorName = CameraController.SelectAnchorName(self._layoutClass, self._inputMode)
	local anchor = requirePart(station, anchorName)
	local target = targetFrom(anchor, focus)
	self._anchorName = anchorName
	self._target = target
	self._impulseEpoch += 1
	stopTween(self)
	camera.CameraType = Enum.CameraType.Scriptable
	publishReadiness(self, true, false, stationIdFor(station))
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(PresentationTokens.Timing.CameraRetarget, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = target, FieldOfView = PresentationTokens.Camera.FieldOfView }
	)
	self._tween = tween
	tween.Completed:Once(function()
		if self._tween == tween then
			self._tween = nil
			publishReadiness(self, true, true, stationIdFor(station))
		end
	end)
	tween:Play()
end

function CameraController.new(): Controller
	local self: InternalController = setmetatable({
		_camera = nil,
		_saved = nil,
		_station = nil,
		_focus = nil,
		_anchorName = nil,
		_layoutClass = "Wide",
		_inputMode = "KeyboardMouse",
		_target = nil,
		_waitingTarget = nil,
		_tween = nil,
		_impulseEpoch = 0,
		_readiness = copyReadiness({ Safe = false, Settled = false, StationId = nil }),
		_readinessListeners = {},
		_nextReadinessListenerId = 0,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.PrepareWaitingView(
	self: InternalController,
	anchor: BasePart?,
	focus: BasePart?,
	fallbackCenter: Vector3
): boolean
	if self._destroyed then
		return false
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		publishReadiness(self, false, false, nil)
		return false
	end
	local target: CFrame
	if anchor ~= nil and focus ~= nil and anchor.Parent ~= nil and focus.Parent ~= nil then
		target = targetFrom(anchor, focus)
	else
		local position = fallbackCenter + Vector3.new(0, 38, 28)
		target = CFrame.lookAt(position, fallbackCenter + Vector3.new(0, 2, 0), Vector3.yAxis)
	end

	saveCameraIfNeeded(self, camera)
	stopTween(self)
	self._camera = camera
	self._station = nil
	self._focus = nil
	self._anchorName = nil
	self._target = nil
	self._waitingTarget = target
	self._impulseEpoch += 1
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = target
	camera.FieldOfView = 50
	publishReadiness(self, true, true, nil)
	return true
end

function ControllerMethods.Activate(self: InternalController, station: Model)
	if self._destroyed then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		error("CameraController cannot activate without Workspace.CurrentCamera", 2)
	end

	local activeForStation = self._camera == camera and self._station == station and self._focus ~= nil
	local transition = CameraController.ResolveTransition(
		true,
		if activeForStation then self._anchorName else nil,
		self._layoutClass,
		self._inputMode
	)
	if transition == "UNCHANGED" then
		return
	elseif transition == "RETARGET" then
		self._camera = camera
		self._station = station
		self._focus = requirePart(station, "CameraFocus")
		retarget(self)
		return
	end

	local anchorName = CameraController.SelectAnchorName(self._layoutClass, self._inputMode)
	local anchor = requirePart(station, anchorName)
	local focus = requirePart(station, "CameraFocus")
	local target = targetFrom(anchor, focus)
	saveCameraIfNeeded(self, camera)

	stopTween(self)
	self._camera = camera
	self._station = station
	self._focus = focus
	self._anchorName = anchorName
	self._target = target
	self._impulseEpoch += 1
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(
		(target * CFrame.new(0, PresentationTokens.Camera.ArrivalHeight, PresentationTokens.Camera.ArrivalDistance)).Position,
		focus.Position,
		anchor.CFrame.UpVector
	)
	camera.FieldOfView = math.min(55, PresentationTokens.Camera.FieldOfView + 5)
	publishReadiness(self, true, false, stationIdFor(station))

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(PresentationTokens.Timing.CameraArrival, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = target, FieldOfView = PresentationTokens.Camera.FieldOfView }
	)
	self._tween = tween
	tween.Completed:Once(function()
		if self._tween == tween then
			self._tween = nil
			publishReadiness(self, true, true, stationIdFor(station))
		end
	end)
	tween:Play()
end

function ControllerMethods.SetPresentation(self: InternalController, layoutClass: LayoutClass, inputMode: InputMode)
	if self._destroyed or (self._layoutClass == layoutClass and self._inputMode == inputMode) then
		return
	end
	self._layoutClass = layoutClass
	self._inputMode = inputMode
	retarget(self)
end

function ControllerMethods.Deactivate(self: InternalController)
	self._impulseEpoch += 1
	stopTween(self)
	local camera = self._camera
	local waitingTarget = self._waitingTarget
	if camera ~= nil and waitingTarget ~= nil then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = waitingTarget
		camera.FieldOfView = 50
		publishReadiness(self, true, true, nil)
	else
		restoreSavedCamera(self)
		publishReadiness(self, false, false, nil)
	end
	self._station = nil
	self._focus = nil
	self._anchorName = nil
	self._target = nil
	if waitingTarget == nil then
		self._camera = nil
	end
end

function ControllerMethods.GetReadiness(self: InternalController): ReadinessState
	return copyReadiness(self._readiness)
end

function ControllerMethods.SubscribeReadiness(
	self: InternalController,
	listener: ReadinessListener
): () -> ()
	if self._destroyed then
		error("Cannot subscribe to a destroyed CameraController", 2)
	end
	self._nextReadinessListenerId += 1
	local listenerId = self._nextReadinessListenerId
	self._readinessListeners[listenerId] = listener
	listener(copyReadiness(self._readiness))
	local connected = true
	return function()
		if connected then
			connected = false
			self._readinessListeners[listenerId] = nil
		end
	end
end

function ControllerMethods.PlayImpulse(self: InternalController, kind: ImpulseKind)
	local camera = self._camera
	local target = self._target
	if self._destroyed or camera == nil or target == nil then
		return
	end
	self._impulseEpoch += 1
	local epoch = self._impulseEpoch
	stopTween(self)

	local offset = CFrame.identity
	local duration = PresentationTokens.Timing.Instant
	if kind == "LIGHT" then
		offset = CFrame.new(0, -PresentationTokens.Camera.LightImpulse, 0)
	elseif kind == "HEAVY" then
		offset = CFrame.new(0, -PresentationTokens.Camera.HeavyImpulse, 0)
	elseif kind == "SHIPPING" then
		offset = CFrame.new(0, 0, PresentationTokens.Camera.ShippingPullback)
		duration = PresentationTokens.Timing.Panel
	else
		offset = CFrame.new(PresentationTokens.Camera.FailureShake, 0.04, 0)
	end

	local outward = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = target * offset }
	)
	self._tween = outward
	outward:Play()
	outward.Completed:Once(function()
		if self._destroyed
			or not CameraController.IsCurrentImpulseEpoch(epoch, self._impulseEpoch)
			or self._camera ~= camera
		then
			return
		end
		local settle = TweenService:Create(
			camera,
			TweenInfo.new(PresentationTokens.Timing.Snap, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		self._tween = settle
		settle.Completed:Once(function()
			if self._tween == settle then
				self._tween = nil
			end
		end)
		settle:Play()
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self:Deactivate()
	restoreSavedCamera(self)
	self._camera = nil
	self._waitingTarget = nil
	publishReadiness(self, false, false, nil)
	table.clear(self._readinessListeners)
	self._destroyed = true
end

return table.freeze(CameraController)
