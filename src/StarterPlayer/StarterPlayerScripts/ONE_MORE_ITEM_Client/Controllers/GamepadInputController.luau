--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MOVE_ACTION = "ONE_MORE_ITEM_GamepadMove"
local ROTATE_ACTION = "ONE_MORE_ITEM_GamepadRotate"
local CONFIRM_ACTION = "ONE_MORE_ITEM_GamepadConfirm"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local DEADZONE = 0.55
local INITIAL_REPEAT_DELAY = 0.28
local REPEAT_INTERVAL = 0.12

export type SelectedAction = "SHIP" | "ONE_MORE" | "RESTART"
export type ActionCommand =
	"MOVE_UP"
	| "MOVE_DOWN"
	| "MOVE_LEFT"
	| "MOVE_RIGHT"
	| "ROTATE"
	| "PLACE"
	| "SELECT_SHIP"
	| "SELECT_ONE_MORE"
	| "CONFIRM_SHIP"
	| "CONFIRM_ONE_MORE"
	| "RESTART"

export type Direction = {
	X: number,
	Z: number,
}

export type RepeatState = {
	X: number,
	Z: number,
	NextRepeatAt: number?,
}

export type Buttons = {
	Ship: TextButton,
	OneMore: TextButton,
	PackAgain: TextButton,
}

export type Callbacks = {
	Move: (deltaX: number, deltaZ: number) -> (),
	Rotate: () -> (),
	Place: () -> (),
	Decision: (choice: string) -> (),
	Restart: () -> (),
	IsPlacementPending: () -> boolean,
	SelectionChanged: (action: SelectedAction?) -> (),
	Observability: (boundActions: number, repeatActive: boolean, selectedAction: SelectedAction?) -> (),
}

export type Controller = {
	SetContext: (self: Controller, gamepadMode: boolean, assigned: boolean, state: string) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_buttons: Buttons,
	_callbacks: Callbacks,
	_repeat: RepeatState,
	_gamepadMode: boolean,
	_assigned: boolean,
	_state: string,
	_bound: boolean,
	_selectedAction: SelectedAction?,
	_decisionAxis: number,
	_heartbeat: RBXScriptConnection?,
	_connections: { RBXScriptConnection },
	_destroyed: boolean,
}

local GamepadInputController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

function GamepadInputController.newRepeatState(): RepeatState
	return {
		X = 0,
		Z = 0,
		NextRepeatAt = nil,
	}
end

function GamepadInputController.ResolveDirection(position: Vector2): Direction
	local absoluteX = math.abs(position.X)
	local absoluteY = math.abs(position.Y)
	if absoluteX < DEADZONE and absoluteY < DEADZONE then
		return { X = 0, Z = 0 }
	end
	-- Equal diagonals deliberately choose X so the tie rule is deterministic.
	if absoluteX >= absoluteY then
		return { X = if position.X >= 0 then 1 else -1, Z = 0 }
	end
	return { X = 0, Z = if position.Y >= 0 then -1 else 1 }
end

function GamepadInputController.UpdateAnalog(
	state: RepeatState,
	position: Vector2,
	now: number
): Direction?
	local direction = GamepadInputController.ResolveDirection(position)
	if direction.X == 0 and direction.Z == 0 then
		state.X = 0
		state.Z = 0
		state.NextRepeatAt = nil
		return nil
	end
	if direction.X ~= state.X or direction.Z ~= state.Z then
		state.X = direction.X
		state.Z = direction.Z
		state.NextRepeatAt = now + INITIAL_REPEAT_DELAY
		return direction
	end
	return nil
end

function GamepadInputController.PollRepeat(state: RepeatState, now: number): Direction?
	local nextRepeatAt = state.NextRepeatAt
	if (state.X == 0 and state.Z == 0) or nextRepeatAt == nil or now < nextRepeatAt then
		return nil
	end
	-- Emit at most one cell per poll; late frames never create multi-cell jumps.
	state.NextRepeatAt = now + REPEAT_INTERVAL
	return { X = state.X, Z = state.Z }
end

function GamepadInputController.ResetRepeat(state: RepeatState)
	state.X = 0
	state.Z = 0
	state.NextRepeatAt = nil
end

function GamepadInputController.GetRepeatConstants(): (number, number, number)
	return DEADZONE, INITIAL_REPEAT_DELAY, REPEAT_INTERVAL
end

function GamepadInputController.ResolveButtonAction(
	state: string,
	assigned: boolean,
	placementPending: boolean,
	keyCode: Enum.KeyCode,
	selectedAction: SelectedAction?
): ActionCommand?
	if not assigned then
		return nil
	end
	if state == "AwaitingPlacement" then
		if placementPending then
			return nil
		elseif keyCode == Enum.KeyCode.DPadUp then
			return "MOVE_UP"
		elseif keyCode == Enum.KeyCode.DPadDown then
			return "MOVE_DOWN"
		elseif keyCode == Enum.KeyCode.DPadLeft then
			return "MOVE_LEFT"
		elseif keyCode == Enum.KeyCode.DPadRight then
			return "MOVE_RIGHT"
		elseif keyCode == Enum.KeyCode.ButtonX then
			return "ROTATE"
		elseif keyCode == Enum.KeyCode.ButtonA then
			return "PLACE"
		end
	elseif state == "Decision" then
		if keyCode == Enum.KeyCode.DPadLeft then
			return "SELECT_SHIP"
		elseif keyCode == Enum.KeyCode.DPadRight then
			return "SELECT_ONE_MORE"
		elseif keyCode == Enum.KeyCode.ButtonA then
			return if selectedAction == "ONE_MORE" then "CONFIRM_ONE_MORE" else "CONFIRM_SHIP"
		end
	elseif state == "Results" and keyCode == Enum.KeyCode.ButtonA then
		return "RESTART"
	end
	return nil
end

function GamepadInputController.IsPlacementInputEnabled(
	state: string,
	assigned: boolean,
	placementPending: boolean
): boolean
	return state == "AwaitingPlacement" and assigned and not placementPending
end

function GamepadInputController.ResolveSafeSelection(
	gamepadMode: boolean,
	assigned: boolean,
	state: string
): SelectedAction?
	if not gamepadMode or not assigned then
		return nil
	elseif state == "Decision" then
		return "SHIP"
	elseif state == "Results" then
		return "RESTART"
	end
	return nil
end

local function isEnabled(self: InternalController): boolean
	return self._gamepadMode and self._assigned and not self._destroyed
end

local function observe(self: InternalController)
	self._callbacks.Observability(if self._bound then 3 else 0, self._repeat.NextRepeatAt ~= nil, self._selectedAction)
end

local function actionButton(self: InternalController, action: SelectedAction): TextButton
	if action == "SHIP" then
		return self._buttons.Ship
	elseif action == "ONE_MORE" then
		return self._buttons.OneMore
	end
	return self._buttons.PackAgain
end

local function setSelection(self: InternalController, action: SelectedAction?)
	if self._selectedAction == action then
		return
	end
	self._selectedAction = action
	if action == nil then
		local selected = GuiService.SelectedObject
		if selected == self._buttons.Ship or selected == self._buttons.OneMore or selected == self._buttons.PackAgain then
			GuiService.SelectedObject = nil
		end
	else
		local button = actionButton(self, action)
		if button.Visible and button.Interactable and button.Selectable then
			GuiService.SelectedObject = button
		else
			self._selectedAction = nil
			GuiService.SelectedObject = nil
		end
	end
	self._callbacks.SelectionChanged(self._selectedAction)
	observe(self)
end

local function setSafeDefault(self: InternalController)
	setSelection(self, GamepadInputController.ResolveSafeSelection(self._gamepadMode, self._assigned, self._state))
end

local function emitMove(self: InternalController, direction: Direction)
	if isEnabled(self)
		and GamepadInputController.IsPlacementInputEnabled(
			self._state,
			self._assigned,
			self._callbacks.IsPlacementPending()
		)
	then
		self._callbacks.Move(direction.X, direction.Z)
	else
		GamepadInputController.ResetRepeat(self._repeat)
	end
end

local function handleDecisionNavigation(self: InternalController, horizontal: number)
	if self._state ~= "Decision" or not isEnabled(self) or horizontal == 0 then
		return
	end
	setSelection(self, if horizontal < 0 then "SHIP" else "ONE_MORE")
end

local function dispatchButtonAction(self: InternalController, action: ActionCommand?)
	if action == "MOVE_UP" then
		emitMove(self, { X = 0, Z = -1 })
	elseif action == "MOVE_DOWN" then
		emitMove(self, { X = 0, Z = 1 })
	elseif action == "MOVE_LEFT" then
		emitMove(self, { X = -1, Z = 0 })
	elseif action == "MOVE_RIGHT" then
		emitMove(self, { X = 1, Z = 0 })
	elseif action == "ROTATE" then
		self._callbacks.Rotate()
	elseif action == "PLACE" then
		self._callbacks.Place()
	elseif action == "SELECT_SHIP" then
		setSelection(self, "SHIP")
	elseif action == "SELECT_ONE_MORE" then
		setSelection(self, "ONE_MORE")
	elseif action == "CONFIRM_SHIP" then
		self._callbacks.Decision("SHIP")
	elseif action == "CONFIRM_ONE_MORE" then
		self._callbacks.Decision("ONE_MORE")
	elseif action == "RESTART" then
		self._callbacks.Restart()
	end
end

local function resolveButtonAction(self: InternalController, keyCode: Enum.KeyCode): ActionCommand?
	return GamepadInputController.ResolveButtonAction(
		self._state,
		self._assigned,
		self._callbacks.IsPlacementPending(),
		keyCode,
		self._selectedAction
	)
end

local function handleMoveAction(
	self: InternalController,
	_inputName: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if not isEnabled(self) then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			GamepadInputController.ResetRepeat(self._repeat)
			self._decisionAxis = 0
			observe(self)
			return Enum.ContextActionResult.Sink
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if self._state == "AwaitingPlacement" then
			local direction = GamepadInputController.UpdateAnalog(self._repeat, position, os.clock())
			if direction ~= nil then
				emitMove(self, direction)
			end
			observe(self)
		elseif self._state == "Decision" then
			local horizontal = if math.abs(position.X) >= DEADZONE then (if position.X < 0 then -1 else 1) else 0
			if horizontal ~= 0 and horizontal ~= self._decisionAxis then
				handleDecisionNavigation(self, horizontal)
			end
			self._decisionAxis = horizontal
		end
		return Enum.ContextActionResult.Sink
	end
	if inputState == Enum.UserInputState.Begin then
		dispatchButtonAction(self, resolveButtonAction(self, input.KeyCode))
	end
	return Enum.ContextActionResult.Sink
end

local function handleRotateAction(
	self: InternalController,
	_inputName: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if not isEnabled(self) then
		return Enum.ContextActionResult.Pass
	end
	if inputState == Enum.UserInputState.Begin then
		dispatchButtonAction(self, resolveButtonAction(self, input.KeyCode))
	end
	return Enum.ContextActionResult.Sink
end

local function handleConfirmAction(
	self: InternalController,
	_inputName: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if not isEnabled(self) then
		return Enum.ContextActionResult.Pass
	end
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	dispatchButtonAction(self, resolveButtonAction(self, input.KeyCode))
	return Enum.ContextActionResult.Sink
end

local function bind(self: InternalController)
	if self._bound then
		return
	end
	ContextActionService:BindActionAtPriority(
		MOVE_ACTION,
		function(actionName, inputState, input)
			return handleMoveAction(self, actionName, inputState, input)
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight
	)
	ContextActionService:BindActionAtPriority(
		ROTATE_ACTION,
		function(actionName, inputState, input)
			return handleRotateAction(self, actionName, inputState, input)
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindActionAtPriority(
		CONFIRM_ACTION,
		function(actionName, inputState, input)
			return handleConfirmAction(self, actionName, inputState, input)
		end,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.ButtonA
	)
	self._bound = true
	self._heartbeat = RunService.Heartbeat:Connect(function()
		if self._state ~= "AwaitingPlacement" or not isEnabled(self) then
			return
		end
		local direction = GamepadInputController.PollRepeat(self._repeat, os.clock())
		if direction ~= nil then
			emitMove(self, direction)
			observe(self)
		end
	end)
	observe(self)
end

local function unbind(self: InternalController)
	if not self._bound then
		return
	end
	ContextActionService:UnbindAction(MOVE_ACTION)
	ContextActionService:UnbindAction(ROTATE_ACTION)
	ContextActionService:UnbindAction(CONFIRM_ACTION)
	self._bound = false
	if self._heartbeat ~= nil then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	GamepadInputController.ResetRepeat(self._repeat)
	self._decisionAxis = 0
	setSelection(self, nil)
	observe(self)
end

function GamepadInputController.new(buttons: Buttons, callbacks: Callbacks): Controller
	local self: InternalController = setmetatable({
		_buttons = buttons,
		_callbacks = callbacks,
		_repeat = GamepadInputController.newRepeatState(),
		_gamepadMode = false,
		_assigned = false,
		_state = "",
		_bound = false,
		_selectedAction = nil,
		_decisionAxis = 0,
		_heartbeat = nil,
		_connections = {},
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	table.insert(self._connections, UserInputService.GamepadDisconnected:Connect(function()
		GamepadInputController.ResetRepeat(self._repeat)
		self._decisionAxis = 0
		setSelection(self, nil)
		observe(self)
	end))
	table.insert(self._connections, UserInputService.GamepadConnected:Connect(function()
		if isEnabled(self) then
			setSafeDefault(self)
		end
	end))
	return self
end

function ControllerMethods.SetContext(self: InternalController, gamepadMode: boolean, assigned: boolean, state: string)
	if self._destroyed then
		return
	end
	local wasEnabled = isEnabled(self)
	local stateChanged = self._state ~= state
	self._gamepadMode = gamepadMode
	self._assigned = assigned
	self._state = state
	local enabled = isEnabled(self)
	if enabled and not wasEnabled then
		bind(self)
	elseif not enabled and wasEnabled then
		unbind(self)
	end
	if stateChanged then
		GamepadInputController.ResetRepeat(self._repeat)
		self._decisionAxis = 0
		setSafeDefault(self)
	elseif enabled and self._selectedAction == nil and (state == "Decision" or state == "Results") then
		setSafeDefault(self)
	end
	observe(self)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	unbind(self)
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	setSelection(self, nil)
	observe(self)
end

return table.freeze(GamepadInputController)
