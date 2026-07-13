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

export type Controller = {
	SetAssigned: (self: Controller, assigned: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_controls: PlayerControls?,
	_controlLease: ControlLeaseState,
	_assigned: boolean,
	_autoRotatePrevious: { [Humanoid]: boolean },
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

local function sinkAction(
	_actionName: string,
	_inputState: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function disableAutoRotate(self: InternalController, character: Model?)
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		if self._autoRotatePrevious[humanoid] == nil then
			self._autoRotatePrevious[humanoid] = humanoid.AutoRotate
		end
		humanoid.AutoRotate = false
	end
end

local function restoreAutoRotate(self: InternalController, character: Model?)
	if character ~= nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			local previous = self._autoRotatePrevious[humanoid]
			if previous ~= nil then
				humanoid.AutoRotate = previous
			end
		end
	end
	table.clear(self._autoRotatePrevious)
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
		_autoRotatePrevious = {},
		_bound = false,
		_destroyed = false,
		_characterConnection = player.CharacterAdded:Connect(function(character: Model)
			if self._assigned then
				local controls = self._controls
				if controls ~= nil and CharacterController.RespawnControlLease(self._controlLease) == "DISABLE" then
					controls:Disable()
				end
				disableAutoRotate(self, character)
			end
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
		disableAutoRotate(self, Players.LocalPlayer.Character)
	else
		unbindFallback(self)
		restorePlayerControls(self)
		restoreAutoRotate(self, Players.LocalPlayer.Character)
	end
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self:SetAssigned(false)
	self._destroyed = true
	self._characterConnection:Disconnect()
end

return table.freeze(CharacterController)
