--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PresentationTokens = require(script.Parent.PresentationTokens)

export type ImpulseKind = "LIGHT" | "HEAVY" | "SHIPPING" | "FAILURE"

export type Controller = {
	Activate: (self: Controller, station: Model) -> (),
	Deactivate: (self: Controller) -> (),
	PlayImpulse: (self: Controller, kind: ImpulseKind) -> (),
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
	_target: CFrame?,
	_tween: Tween?,
	_impulseEpoch: number,
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

function CameraController.new(): Controller
	local self: InternalController = setmetatable({
		_camera = nil,
		_saved = nil,
		_target = nil,
		_tween = nil,
		_impulseEpoch = 0,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.Activate(self: InternalController, station: Model)
	if self._destroyed then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		error("CameraController cannot activate without Workspace.CurrentCamera", 2)
	end

	local anchor = requirePart(station, "CameraAnchor")
	local focus = requirePart(station, "CameraFocus")
	local target = targetFrom(anchor, focus)
	if self._saved == nil then
		self._saved = {
			CameraType = camera.CameraType,
			CameraSubject = camera.CameraSubject,
			CFrame = camera.CFrame,
			FieldOfView = camera.FieldOfView,
		}
	end

	if self._tween ~= nil then
		self._tween:Cancel()
	end
	self._camera = camera
	self._target = target
	self._impulseEpoch += 1
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(
		(target * CFrame.new(0, PresentationTokens.Camera.ArrivalHeight, PresentationTokens.Camera.ArrivalDistance)).Position,
		focus.Position,
		anchor.CFrame.UpVector
	)
	camera.FieldOfView = math.min(55, PresentationTokens.Camera.FieldOfView + 5)

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(PresentationTokens.Timing.CameraArrival, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = target, FieldOfView = PresentationTokens.Camera.FieldOfView }
	)
	self._tween = tween
	tween:Play()
end

function ControllerMethods.Deactivate(self: InternalController)
	self._impulseEpoch += 1
	if self._tween ~= nil then
		self._tween:Cancel()
		self._tween = nil
	end
	local camera = self._camera
	local saved = self._saved
	if camera ~= nil and saved ~= nil then
		camera.CameraType = saved.CameraType
		camera.CameraSubject = saved.CameraSubject
		camera.CFrame = saved.CFrame
		camera.FieldOfView = saved.FieldOfView
	end
	self._camera = nil
	self._saved = nil
	self._target = nil
end

function ControllerMethods.PlayImpulse(self: InternalController, kind: ImpulseKind)
	local camera = self._camera
	local target = self._target
	if self._destroyed or camera == nil or target == nil then
		return
	end
	self._impulseEpoch += 1
	local epoch = self._impulseEpoch
	if self._tween ~= nil then
		self._tween:Cancel()
	end

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
		if self._destroyed or epoch ~= self._impulseEpoch or self._camera ~= camera then
			return
		end
		local settle = TweenService:Create(
			camera,
			TweenInfo.new(PresentationTokens.Timing.Snap, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		self._tween = settle
		settle:Play()
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self:Deactivate()
	self._destroyed = true
end

return table.freeze(CameraController)
