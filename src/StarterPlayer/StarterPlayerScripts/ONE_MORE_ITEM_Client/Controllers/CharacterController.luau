--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local MOVE_ACTION = "ONE_MORE_ITEM_DisableStationMovement"
local JUMP_ACTION = "ONE_MORE_ITEM_DisableStationJump"

type PlayerControls = {
	controlsEnabled: boolean?,
	Disable: (self: PlayerControls) -> (),
	Enable: (self: PlayerControls) -> (),
	IsEnabled: ((self: PlayerControls) -> boolean)?,
}

export type ControlLeaseAction = "DISABLE" | "RESTORE"
export type ControlLeaseState = {
	Assigned: boolean,
	PreviousEnabled: boolean,
	DisabledByUs: boolean,
}

export type AutoRotateLeaseState = {
	Active: boolean,
	Previous: boolean,
}

export type Controller = {
	SetAssigned: (self: Controller, assigned: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_controls: PlayerControls?,
	_controlLease: ControlLeaseState,
	_assigned: boolean,
	_autoRotateHumanoid: Humanoid?,
	_autoRotateLease: AutoRotateLeaseState,
	_trackedCharacter: Model?,
	_characterChildAddedConnection: RBXScriptConnection?,
	_characterChildRemovedConnection: RBXScriptConnection?,
	_characterConnection: RBXScriptConnection,
	_bound: boolean,
	_destroyed: boolean,
}

local CharacterController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

function CharacterController.newControlLeaseState(): ControlLeaseState
	return {
		Assigned = false,
		PreviousEnabled = false,
		DisabledByUs = false,
	}
end

function CharacterController.TransitionControlLease(
	state: ControlLeaseState,
	assigned: boolean,
	controlsEnabled: boolean
): ControlLeaseAction?
	if state.Assigned == assigned then
		return nil
	end
	state.Assigned = assigned
	if assigned then
		state.PreviousEnabled = controlsEnabled
		state.DisabledByUs = controlsEnabled
		return if controlsEnabled then "DISABLE" else nil
	end
	local shouldRestore = state.DisabledByUs and state.PreviousEnabled
	state.PreviousEnabled = false
	state.DisabledByUs = false
	return if shouldRestore then "RESTORE" else nil
end

function CharacterController.RespawnControlLease(state: ControlLeaseState): ControlLeaseAction?
	if state.Assigned and state.PreviousEnabled then
		state.DisabledByUs = true
		return "DISABLE"
	end
	return nil
end

function CharacterController.DestroyControlLease(state: ControlLeaseState): ControlLeaseAction?
	return CharacterController.TransitionControlLease(state, false, false)
end

function CharacterController.newAutoRotateLeaseState(): AutoRotateLeaseState
	return {
		Active = false,
		Previous = false,
	}
end

function CharacterController.BeginAutoRotateLease(state: AutoRotateLeaseState, current: boolean): boolean
	if not state.Active then
		state.Active = true
		state.Previous = current
	end
	return false
end

function CharacterController.ReleaseAutoRotateLease(state: AutoRotateLeaseState): boolean?
	if not state.Active then
		return nil
	end
	local previous = state.Previous
	state.Active = false
	state.Previous = false
	return previous
end

function CharacterController.ShouldSuppressAutoRotate(
	assigned: boolean,
	destroyed: boolean,
	trackedCharacterMatches: boolean,
	currentCharacterMatches: boolean
): boolean
	return assigned and not destroyed and trackedCharacterMatches and currentCharacterMatches
end

local function sinkAction(
	_actionName: string,
	_inputState: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function restoreTrackedAutoRotate(self: InternalController)
	local humanoid = self._autoRotateHumanoid
	self._autoRotateHumanoid = nil
	local previous = CharacterController.ReleaseAutoRotateLease(self._autoRotateLease)
	if humanoid ~= nil and previous ~= nil then
		local targetHumanoid = humanoid :: Humanoid
		local restoreValue = previous :: boolean
		pcall(function()
			targetHumanoid.AutoRotate = restoreValue
		end)
	end
end

local function disconnectCharacterTracking(self: InternalController)
	self._trackedCharacter = nil
	local addedConnection = self._characterChildAddedConnection
	if addedConnection ~= nil then
		addedConnection:Disconnect()
		self._characterChildAddedConnection = nil
	end
	local removedConnection = self._characterChildRemovedConnection
	if removedConnection ~= nil then
		removedConnection:Disconnect()
		self._characterChildRemovedConnection = nil
	end
	restoreTrackedAutoRotate(self)
end

local function trySuppressAutoRotate(self: InternalController, character: Model, humanoid: Humanoid)
	local player = Players.LocalPlayer
	if not CharacterController.ShouldSuppressAutoRotate(
		self._assigned,
		self._destroyed,
		self._trackedCharacter == character,
		player.Character == character
	) or humanoid.Parent ~= character then
		return
	end
	if self._autoRotateHumanoid ~= humanoid then
		restoreTrackedAutoRotate(self)
		if not CharacterController.ShouldSuppressAutoRotate(
			self._assigned,
			self._destroyed,
			self._trackedCharacter == character,
			player.Character == character
		) or humanoid.Parent ~= character then
			return
		end
		self._autoRotateHumanoid = humanoid
	end
	humanoid.AutoRotate = CharacterController.BeginAutoRotateLease(self._autoRotateLease, humanoid.AutoRotate)
end

local function trackCharacterAutoRotate(self: InternalController, character: Model?)
	disconnectCharacterTracking(self)
	local player = Players.LocalPlayer
	if character == nil or self._destroyed or not self._assigned or player.Character ~= character then
		return
	end
	self._trackedCharacter = character
	self._characterChildAddedConnection = character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			trySuppressAutoRotate(self, character, child)
		end
	end)
	self._characterChildRemovedConnection = character.ChildRemoved:Connect(function(child: Instance)
		if self._trackedCharacter == character and self._autoRotateHumanoid == child then
			restoreTrackedAutoRotate(self)
		end
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		trySuppressAutoRotate(self, character, humanoid)
	end
end

local function resolvePlayerControls(): PlayerControls?
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 10)
	if playerScripts == nil then
		return nil
	end
	local playerModuleInstance = playerScripts:WaitForChild("PlayerModule", 10)
	if playerModuleInstance == nil or not playerModuleInstance:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall(require, playerModuleInstance)
	if not ok or type(playerModule) ~= "table" or type((playerModule :: any).GetControls) ~= "function" then
		return nil
	end
	local controlsOk, controls = pcall(function()
		return (playerModule :: any):GetControls()
	end)
	if not controlsOk or type(controls) ~= "table" then
		return nil
	end
	if type((controls :: any).Disable) ~= "function" or type((controls :: any).Enable) ~= "function" then
		return nil
	end
	return controls :: PlayerControls
end

local function controlsAreEnabled(controls: PlayerControls): boolean
	if type(controls.controlsEnabled) == "boolean" then
		return controls.controlsEnabled :: boolean
	end
	local isEnabled = controls.IsEnabled
	if isEnabled == nil then
		return true
	end
	local ok, enabled = pcall(function()
		return isEnabled(controls)
	end)
	return not ok or enabled == true
end

local function disablePlayerControls(self: InternalController)
	local controls = self._controls
	local controlsEnabled = controls ~= nil and controlsAreEnabled(controls)
	local action = CharacterController.TransitionControlLease(self._controlLease, true, controlsEnabled)
	if controls ~= nil and action == "DISABLE" then
		controls:Disable()
	end
end

local function restorePlayerControls(self: InternalController)
	local controls = self._controls
	local action = CharacterController.TransitionControlLease(self._controlLease, false, false)
	if controls ~= nil and action == "RESTORE" then
		controls:Enable()
	end
end

local function bindFallback(self: InternalController)
	if self._bound then
		return
	end
	ContextActionService:BindActionAtPriority(
		MOVE_ACTION,
		sinkAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight
	)
	ContextActionService:BindActionAtPriority(
		JUMP_ACTION,
		sinkAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterJump
	)
	self._bound = true
end

local function unbindFallback(self: InternalController)
	if not self._bound then
		return
	end
	ContextActionService:UnbindAction(MOVE_ACTION)
	ContextActionService:UnbindAction(JUMP_ACTION)
	self._bound = false
end

function CharacterController.new(): Controller
	local player = Players.LocalPlayer
	local self: InternalController
	self = setmetatable({
		_controls = resolvePlayerControls(),
		_controlLease = CharacterController.newControlLeaseState(),
		_assigned = false,
		_autoRotateHumanoid = nil,
		_autoRotateLease = CharacterController.newAutoRotateLeaseState(),
		_trackedCharacter = nil,
		_characterChildAddedConnection = nil,
		_characterChildRemovedConnection = nil,
		_bound = false,
		_destroyed = false,
		_characterConnection = player.CharacterAdded:Connect(function(character: Model)
			if self._destroyed or not self._assigned or player.Character ~= character then
				return
			end
			local controls = self._controls
			if controls ~= nil and CharacterController.RespawnControlLease(self._controlLease) == "DISABLE" then
				controls:Disable()
			end
			trackCharacterAutoRotate(self, character)
		end),
	}, ControllerMethods) :: InternalController
	return self
end

function ControllerMethods.SetAssigned(self: InternalController, assigned: boolean)
	if self._destroyed or self._assigned == assigned then
		return
	end
	self._assigned = assigned
	if assigned then
		disablePlayerControls(self)
		bindFallback(self)
		trackCharacterAutoRotate(self, Players.LocalPlayer.Character)
	else
		unbindFallback(self)
		restorePlayerControls(self)
		disconnectCharacterTracking(self)
	end
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self:SetAssigned(false)
	self._destroyed = true
	self._characterConnection:Disconnect()
	disconnectCharacterTracking(self)
end

return table.freeze(CharacterController)
