--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local CameraController = require(script.Parent.CameraController)
local ClientProfileStore = require(script.Parent.ClientProfileStore)

local presentation = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared"):WaitForChild("Presentation")
local VisualThemeDefinitions = require(presentation:WaitForChild("VisualThemeDefinitions"))

type ProfileSnapshot = ClientProfileStore.Snapshot
type ReadinessState = CameraController.ReadinessState

type FadeRecord = {
	Object: GuiObject,
	BackgroundTransparency: number,
	TextTransparency: number?,
	TextStrokeTransparency: number?,
}

export type Controller = {
	ApplyProfileSnapshot: (self: Controller, snapshot: ProfileSnapshot) -> (),
	SetAssignment: (self: Controller, assigned: boolean, stationId: string?) -> (),
	IsRevealed: (self: Controller) -> boolean,
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_curtain: GuiObject,
	_loadingStatus: TextLabel,
	_camera: CameraController.Controller,
	_cameraState: ReadinessState,
	_profileState: string,
	_assigned: boolean,
	_stationId: string?,
	_records: { FadeRecord },
	_tweens: { Tween },
	_unsubscribeCamera: (() -> ())?,
	_connections: { RBXScriptConnection },
	_fadeEpoch: number,
	_hasRevealed: boolean,
	_safetyHold: boolean,
	_firstFramePackage: Instance?,
	_handoffReleasedAt: number?,
	_holdEpoch: number,
	_holdPending: boolean,
	_destroyed: boolean,
}

local ArrivalCurtainController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local READY_PROFILE_STATES: { [string]: boolean } = table.freeze({
	Ready = true,
	Saving = true,
	SaveDelayed = true,
})

local MINIMUM_CANONICAL_HOLD = VisualThemeDefinitions.Timing.Hero

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("ArrivalCurtainController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("ArrivalCurtainController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function optionalPart(parent: Instance, name: string): BasePart?
	local child = parent:FindFirstChild(name)
	if child == nil then
		return nil
	end
	if not child:IsA("BasePart") then
		error(string.format("ArrivalCurtainController expected optional BasePart %s", child:GetFullName()), 3)
	end
	return child
end

local function fallbackCenter(arena: Instance): Vector3
	local centerDispatch = arena:FindFirstChild("CenterDispatch")
	if centerDispatch ~= nil then
		local showcaseEntry = centerDispatch:FindFirstChild("ShowcaseEntry", true)
		if showcaseEntry ~= nil and showcaseEntry:IsA("BasePart") then
			return showcaseEntry.Position
		end
		if centerDispatch:IsA("Model") then
			return centerDispatch:GetPivot().Position
		end
	end
	if arena:IsA("Model") then
		return arena:GetPivot().Position
	end
	return Vector3.zero
end

local function collectFadeRecords(curtain: GuiObject): { FadeRecord }
	local records: { FadeRecord } = {}
	local function collect(instance: Instance)
		if not instance:IsA("GuiObject") then
			return
		end
		local record: FadeRecord = {
			Object = instance,
			BackgroundTransparency = instance.BackgroundTransparency,
			TextTransparency = nil,
			TextStrokeTransparency = nil,
		}
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			record.TextTransparency = instance.TextTransparency
			record.TextStrokeTransparency = instance.TextStrokeTransparency
		end
		table.insert(records, record)
	end
	collect(curtain)
	for _, descendant in ipairs(curtain:GetDescendants()) do
		collect(descendant)
	end
	return records
end

local function cancelTweens(self: InternalController)
	self._fadeEpoch += 1
	for _, tween in ipairs(self._tweens) do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

local function restoreCurtain(self: InternalController)
	cancelTweens(self)
	for _, record in ipairs(self._records) do
		local object = record.Object
		if object.Parent ~= nil then
			object.BackgroundTransparency = record.BackgroundTransparency
			if record.TextTransparency ~= nil
				and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
			then
				object.TextTransparency = record.TextTransparency
				object.TextStrokeTransparency = record.TextStrokeTransparency :: number
			end
		end
	end
	self._curtain.Visible = true
end

function ArrivalCurtainController.StatusForProfile(profileState: string): string
	if profileState == "Unavailable" or profileState == "Released" or profileState == "Releasing" then
		return "DATA UNAVAILABLE"
	elseif profileState == "Conflict" then
		return "PROFILE OPEN ELSEWHERE"
	elseif READY_PROFILE_STATES[profileState] then
		return "WAITING FOR STATION"
	end
	return "LOADING PROFILE"
end

function ArrivalCurtainController.ShouldReveal(
	profileState: string,
	assigned: boolean,
	stationId: string?,
	cameraState: ReadinessState
): boolean
	if not READY_PROFILE_STATES[profileState] or not cameraState.Safe or not cameraState.Settled then
		return false
	end
	if assigned then
		return stationId ~= nil and cameraState.StationId == stationId
	end
	return cameraState.StationId == nil
end

local function fadeOut(self: InternalController)
	if self._destroyed or not self._curtain.Visible or #self._tweens > 0 then
		return
	end
	self._fadeEpoch += 1
	local epoch = self._fadeEpoch
	local remaining = 0
	local function completed()
		remaining -= 1
		if remaining == 0 and not self._destroyed and self._fadeEpoch == epoch then
			self._curtain.Visible = false
			table.clear(self._tweens)
			self._safetyHold = false
			self._hasRevealed = true
			self._curtain:SetAttribute("PresentationState", "REVEALED")
			local revealCount = self._curtain:GetAttribute("RevealCount")
			self._curtain:SetAttribute("RevealCount", if type(revealCount) == "number" then revealCount + 1 else 1)
		end
	end
	local tweenInfo = TweenInfo.new(
		VisualThemeDefinitions.Timing.ArrivalCurtainFade,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)
	for _, record in ipairs(self._records) do
		local object = record.Object
		if object.Parent ~= nil then
			local properties: { [string]: number } = {
				BackgroundTransparency = 1,
			}
			if record.TextTransparency ~= nil then
				properties.TextTransparency = 1
				properties.TextStrokeTransparency = 1
			end
			local tween = TweenService:Create(object, tweenInfo, properties)
			remaining += 1
			table.insert(self._tweens, tween)
			tween.Completed:Once(completed)
			tween:Play()
		end
	end
	if remaining == 0 then
		self._curtain.Visible = false
		self._safetyHold = false
		self._hasRevealed = true
	end
end

local function refresh(self: InternalController)
	if self._destroyed then
		return
	end
	self._curtain:SetAttribute("CameraSafe", self._cameraState.Safe)
	self._curtain:SetAttribute("CameraSettled", self._cameraState.Settled)
	self._curtain:SetAttribute("AssignedStationId", self._stationId)
	local firstFramePackage = self._firstFramePackage
	local handoffComplete = firstFramePackage == nil
		or firstFramePackage.Parent == nil
		or firstFramePackage:GetAttribute("HandoffComplete") == true
	self._curtain:SetAttribute("FirstFrameHandoffComplete", handoffComplete)
	if self._safetyHold then
		self._loadingStatus.Text = "RESTORING VIEW"
		if self._cameraState.Safe and self._cameraState.Settled then
			fadeOut(self)
		end
		return
	end
	if self._hasRevealed then
		return
	end
	self._loadingStatus.Text = ArrivalCurtainController.StatusForProfile(self._profileState)
	self._curtain:SetAttribute("PresentationState", self._loadingStatus.Text)
	if ArrivalCurtainController.ShouldReveal(
		self._profileState,
		self._assigned,
		self._stationId,
		self._cameraState
	) then
		if not handoffComplete then
			return
		end
		if self._handoffReleasedAt == nil then
			self._handoffReleasedAt = os.clock()
		end
		local remaining = MINIMUM_CANONICAL_HOLD - (os.clock() - (self._handoffReleasedAt :: number))
		if remaining > 0 then
			if not self._holdPending then
				self._holdPending = true
				self._holdEpoch += 1
				local holdEpoch = self._holdEpoch
				task.delay(remaining, function()
					if self._destroyed or self._holdEpoch ~= holdEpoch then
						return
					end
					self._holdPending = false
					refresh(self)
				end)
			end
			return
		end
		fadeOut(self)
	end
end

function ArrivalCurtainController.new(
	gameplayGui: ScreenGui,
	arena: Instance,
	camera: CameraController.Controller
): Controller
	local curtain = requireGui(gameplayGui, "ArrivalCurtain")
	requireGui(curtain, "Background")
	requireLabel(curtain, "GameTitle")
	requireLabel(curtain, "Subtitle")
	local loadingStatus = requireLabel(curtain, "LoadingStatus")
	requireGui(curtain, "AccentLine")
	local firstFramePackage = ReplicatedFirst:FindFirstChild("ONE_MORE_ITEM_FirstFrame")

	local self: InternalController = setmetatable({
		_curtain = curtain,
		_loadingStatus = loadingStatus,
		_camera = camera,
		_cameraState = camera:GetReadiness(),
		_profileState = "Loading",
		_assigned = false,
		_stationId = nil,
		_records = collectFadeRecords(curtain),
		_tweens = {},
		_unsubscribeCamera = nil,
		_connections = {},
		_fadeEpoch = 0,
		_hasRevealed = false,
		_safetyHold = false,
		_firstFramePackage = firstFramePackage,
		_handoffReleasedAt = if firstFramePackage == nil then os.clock() else nil,
		_holdEpoch = 0,
		_holdPending = false,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	restoreCurtain(self)
	self._loadingStatus.Text = "LOADING PROFILE"
	self._curtain:SetAttribute("RevealCount", 0)
	self._curtain:SetAttribute("PresentationState", "LOADING PROFILE")

	local anchor = optionalPart(arena, "ArrivalCameraAnchor")
	local focus = optionalPart(arena, "ArrivalCameraFocus")
	if (anchor == nil) ~= (focus == nil) then
		error("ArrivalCurtainController requires ArrivalCameraAnchor and ArrivalCameraFocus together", 2)
	end
	camera:PrepareWaitingView(anchor, focus, fallbackCenter(arena))
	self._cameraState = camera:GetReadiness()
	self._unsubscribeCamera = camera:SubscribeReadiness(function(state: ReadinessState)
		if self._destroyed then
			return
		end
		self._cameraState = state
		refresh(self)
	end)
	if firstFramePackage ~= nil then
		table.insert(self._connections, firstFramePackage:GetAttributeChangedSignal("HandoffComplete"):Connect(function()
			if self._destroyed or firstFramePackage:GetAttribute("HandoffComplete") ~= true then
				return
			end
			self._handoffReleasedAt = os.clock()
			refresh(self)
		end))
	end

	table.insert(self._connections, Players.LocalPlayer.CharacterAdded:Connect(function()
		if self._destroyed or not self._hasRevealed or self._camera:GetReadiness().Safe then
			return
		end
		self._safetyHold = true
		restoreCurtain(self)
		refresh(self)
	end))
	refresh(self)
	return self
end

function ControllerMethods.ApplyProfileSnapshot(self: InternalController, snapshot: ProfileSnapshot)
	if self._destroyed then
		return
	end
	self._profileState = snapshot.State
	refresh(self)
end

function ControllerMethods.SetAssignment(self: InternalController, assigned: boolean, stationId: string?)
	if self._destroyed then
		return
	end
	self._assigned = assigned and stationId ~= nil
	self._stationId = if self._assigned then stationId else nil
	refresh(self)
end

function ControllerMethods.IsRevealed(self: InternalController): boolean
	return self._hasRevealed and not self._curtain.Visible
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._holdEpoch += 1
	self._holdPending = false
	cancelTweens(self)
	local unsubscribe = self._unsubscribeCamera
	self._unsubscribeCamera = nil
	if unsubscribe ~= nil then
		unsubscribe()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._curtain.Visible = false
end

return table.freeze(ArrivalCurtainController)
