--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local MOVE_ACTION = "ONE_MORE_ITEM_DisableStationMovement"
local JUMP_ACTION = "ONE_MORE_ITEM_DisableStationJump"

export type Controller = {
	SetAssigned: (self: Controller, assigned: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_assigned: boolean,
	_characterConnection: RBXScriptConnection,
	_bound: boolean,
	_destroyed: boolean,
}

local CharacterController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function sinkAction(_actionName: string, _inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function setAutoRotate(character: Model?, enabled: boolean)
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.AutoRotate = enabled
	end
end

function CharacterController.new(): Controller
	local player = Players.LocalPlayer
	local self: InternalController
	self = setmetatable({
		_assigned = false,
		_bound = false,
		_destroyed = false,
		_characterConnection = player.CharacterAdded:Connect(function(character: Model)
			if self._assigned then
				setAutoRotate(character, false)
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
		setAutoRotate(Players.LocalPlayer.Character, false)
	else
		if self._bound then
			ContextActionService:UnbindAction(MOVE_ACTION)
			ContextActionService:UnbindAction(JUMP_ACTION)
			self._bound = false
		end
		setAutoRotate(Players.LocalPlayer.Character, true)
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
