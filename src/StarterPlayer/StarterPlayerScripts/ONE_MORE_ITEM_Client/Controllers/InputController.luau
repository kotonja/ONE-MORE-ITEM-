--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local GamepadInputController = require(script.Parent.GamepadInputController)
local InputModeStore = require(script.Parent.InputModeStore)
local InputPromptController = require(script.Parent.InputPromptController)
local TouchInputController = require(script.Parent.TouchInputController)

type Snapshot = ClientRoundStore.Snapshot
type InputMode = InputModeStore.InputMode
type SelectedAction = GamepadInputController.SelectedAction

export type RoutedAction = "MOVE" | "POINTER" | "ROTATE" | "PLACE" | "SHIP" | "ONE_MORE" | "RESTART"
export type NetworkRequest = "PlaceItemRequest" | "DecisionRequest" | "RestartRequest"

export type NetworkCallbacks = {
	Place: () -> (),
	Decision: (choice: string) -> (),
	Restart: () -> (),
}

export type Callbacks = {
	Move: (deltaX: number, deltaZ: number) -> (),
	Rotate: () -> (),
	Place: () -> (),
	Decision: (choice: string) -> (),
	Restart: () -> (),
	PointerRay: (ray: Ray) -> (),
	IsPlacementPending: () -> boolean,
	ModeChanged: (mode: InputMode) -> (),
	Observability: (
		mode: InputMode,
		touchActive: boolean,
		boundGamepadActions: number,
		repeatActive: boolean,
		selectedAction: SelectedAction?
	) -> (),
}

export type Buttons = {
	Rotate: TextButton,
	Place: TextButton,
	Ship: TextButton,
	OneMore: TextButton,
	PackAgain: TextButton,
}

export type Controller = {
	GetMode: (self: Controller) -> InputMode,
	ApplySnapshot: (self: Controller, snapshot: Snapshot, assigned: boolean) -> (),
	SetAssigned: (self: Controller, assigned: boolean) -> (),
	SetProfileMenuOpen: (self: Controller, isOpen: boolean) -> (),
	SetModalBlocked: (self: Controller, blockerName: string, isBlocked: boolean) -> (),
	IsModalBlocked: (self: Controller) -> boolean,
	RefreshContext: (self: Controller) -> (),
	RefreshPointer: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_callbacks: Callbacks,
	_connections: { RBXScriptConnection },
	_modeStore: InputModeStore.Store,
	_unsubscribeMode: (() -> ())?,
	_prompt: InputPromptController.Controller,
	_touch: TouchInputController.Controller?,
	_gamepad: GamepadInputController.Controller?,
	_snapshot: Snapshot?,
	_mode: InputMode,
	_assigned: boolean,
	_modalBlockers: { [string]: boolean },
	_touchActive: boolean,
	_boundGamepadActions: number,
	_repeatActive: boolean,
	_selectedAction: SelectedAction?,
	_destroyed: boolean,
}

local InputController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function modalBlocked(self: InternalController): boolean
	return next(self._modalBlockers) ~= nil
end

function InputController.NetworkRequestForAction(action: RoutedAction): NetworkRequest?
	if action == "PLACE" then
		return "PlaceItemRequest"
	elseif action == "SHIP" or action == "ONE_MORE" then
		return "DecisionRequest"
	elseif action == "RESTART" then
		return "RestartRequest"
	end
	return nil
end

function InputController.DispatchNetworkAction(callbacks: NetworkCallbacks, action: RoutedAction): NetworkRequest?
	local request = InputController.NetworkRequestForAction(action)
	if request == "PlaceItemRequest" then
		callbacks.Place()
	elseif request == "DecisionRequest" then
		callbacks.Decision(if action == "ONE_MORE" then "ONE_MORE" else "SHIP")
	elseif request == "RestartRequest" then
		callbacks.Restart()
	end
	return request
end

local function isTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function isPointerOverButton(): boolean
	local pointer = UserInputService:GetMouseLocation()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(pointer.X, pointer.Y)) do
		if guiObject:IsA("GuiButton") and guiObject.Visible and guiObject.Active then
			return true
		end
	end
	return false
end

local function pointerRay(): Ray?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local pointer = UserInputService:GetMouseLocation()
	-- GetMouseLocation and ViewportPointToRay both use the device-safe viewport
	-- origin. No Core UI or device-safe inset is subtracted a second time.
	return camera:ViewportPointToRay(pointer.X, pointer.Y)
end

local function currentState(self: InternalController): string
	local snapshot = self._snapshot
	return if snapshot ~= nil then snapshot.State else ""
end

local function awaitingPlacement(self: InternalController): boolean
	return not modalBlocked(self)
		and self._assigned
		and currentState(self) == "AwaitingPlacement"
		and not self._callbacks.IsPlacementPending()
end

local function dispatchNetworkAction(self: InternalController, action: RoutedAction): NetworkRequest?
	return InputController.DispatchNetworkAction(self._callbacks, action)
end

local function observe(self: InternalController)
	self._callbacks.Observability(
		self._mode,
		self._touchActive,
		self._boundGamepadActions,
		self._repeatActive,
		self._selectedAction
	)
end

local function refreshContexts(self: InternalController)
	local state = currentState(self)
	local touch = self._touch
	if touch ~= nil then
		touch:SetContext(self._mode == "Touch" and not modalBlocked(self), self._assigned, awaitingPlacement(self))
	end
	local gamepad = self._gamepad
	if gamepad ~= nil then
		gamepad:SetContext(self._mode == "Gamepad" and not modalBlocked(self), self._assigned, state)
	end
	observe(self)
end

local function applyMode(self: InternalController, mode: InputMode)
	if self._destroyed or self._mode == mode then
		return
	end
	self._mode = mode
	self._prompt:SetMode(mode)
	refreshContexts(self)
	self._callbacks.ModeChanged(mode)
end

local function handleKeyboardMouse(self: InternalController, input: InputObject, gameProcessed: boolean)
	if self._destroyed
		or modalBlocked(self)
		or self._mode ~= "KeyboardMouse"
		or not self._assigned
		or gameProcessed
		or isTyping()
	then
		return
	end
	local state = currentState(self)
	local keyCode = input.KeyCode
	if state == "AwaitingPlacement" and not self._callbacks.IsPlacementPending() then
		if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
			self._callbacks.Move(0, -1)
		elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
			self._callbacks.Move(0, 1)
		elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
			self._callbacks.Move(-1, 0)
		elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
			self._callbacks.Move(1, 0)
		elseif keyCode == Enum.KeyCode.R then
			self._callbacks.Rotate()
		elseif keyCode == Enum.KeyCode.Space then
			dispatchNetworkAction(self, "PLACE")
			refreshContexts(self)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not isPointerOverButton() then
			dispatchNetworkAction(self, "PLACE")
			refreshContexts(self)
		end
	elseif state == "Decision" then
		if keyCode == Enum.KeyCode.Q then
			dispatchNetworkAction(self, "SHIP")
		elseif keyCode == Enum.KeyCode.E then
			dispatchNetworkAction(self, "ONE_MORE")
		end
	elseif state == "Results" and (keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter) then
		dispatchNetworkAction(self, "RESTART")
	end
end

function InputController.ShouldHandleAuthoredButton(
	mode: InputMode,
	assigned: boolean,
	selectedGamepadButton: boolean
): boolean
	if not assigned then
		return false
	end
	return mode ~= "Gamepad" or selectedGamepadButton
end

local function bindAuthoredButtons(self: InternalController, buttons: Buttons)
	local function connect(button: TextButton, gamepadSelectable: boolean, callback: () -> ())
		table.insert(self._connections, button.Activated:Connect(function()
			if self._destroyed
				or modalBlocked(self)
				or not InputController.ShouldHandleAuthoredButton(
					self._mode,
					self._assigned,
					gamepadSelectable and GuiService.SelectedObject == button
				)
			then
				return
			end
			callback()
		end))
	end
	connect(buttons.Rotate, false, function()
		if awaitingPlacement(self) then
			self._callbacks.Rotate()
		end
	end)
	connect(buttons.Place, false, function()
		if awaitingPlacement(self) then
			dispatchNetworkAction(self, "PLACE")
			refreshContexts(self)
		end
	end)
	connect(buttons.Ship, true, function()
		if currentState(self) == "Decision" then
			dispatchNetworkAction(self, "SHIP")
		end
	end)
	connect(buttons.OneMore, true, function()
		if currentState(self) == "Decision" then
			dispatchNetworkAction(self, "ONE_MORE")
		end
	end)
	connect(buttons.PackAgain, true, function()
		if currentState(self) == "Results" then
			dispatchNetworkAction(self, "RESTART")
		end
	end)
end

function InputController.new(
	callbacks: Callbacks,
	buttons: Buttons,
	root: GuiObject,
	touchSurface: Frame
): Controller
	local modeStore = InputModeStore.new()
	local prompt = InputPromptController.new(root, buttons)
	local self: InternalController = setmetatable({
		_callbacks = callbacks,
		_connections = {},
		_modeStore = modeStore,
		_unsubscribeMode = nil,
		_prompt = prompt,
		_touch = nil,
		_gamepad = nil,
		_snapshot = nil,
		_mode = modeStore:GetMode(),
		_assigned = false,
		_modalBlockers = {},
		_touchActive = false,
		_boundGamepadActions = 0,
		_repeatActive = false,
		_selectedAction = nil,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	self._touch = TouchInputController.new(touchSurface, callbacks.PointerRay, function(active: boolean)
		self._touchActive = active
		observe(self)
	end)
	self._gamepad = GamepadInputController.new({
		Ship = buttons.Ship,
		OneMore = buttons.OneMore,
		PackAgain = buttons.PackAgain,
	}, {
		Move = callbacks.Move,
		Rotate = callbacks.Rotate,
		Place = function()
			dispatchNetworkAction(self, "PLACE")
			refreshContexts(self)
		end,
		Decision = function(choice: string)
			if choice == "SHIP" then
				dispatchNetworkAction(self, "SHIP")
			elseif choice == "ONE_MORE" then
				dispatchNetworkAction(self, "ONE_MORE")
			end
		end,
		Restart = function()
			dispatchNetworkAction(self, "RESTART")
		end,
		IsPlacementPending = callbacks.IsPlacementPending,
		SelectionChanged = function(action: SelectedAction?)
			self._selectedAction = action
			prompt:SetSelectedAction(action)
			observe(self)
		end,
		Observability = function(boundActions: number, repeatActive: boolean, selectedAction: SelectedAction?)
			self._boundGamepadActions = boundActions
			self._repeatActive = repeatActive
			self._selectedAction = selectedAction
			observe(self)
		end,
	})

	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		handleKeyboardMouse(self, input, gameProcessed)
	end))
	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if self._destroyed or modalBlocked(self) or self._mode ~= "KeyboardMouse" or isTyping() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self:RefreshPointer()
		end
	end))
	bindAuthoredButtons(self, buttons)
	prompt:SetMode(self._mode)
	refreshContexts(self)
	self._unsubscribeMode = modeStore:Subscribe(function(mode: InputMode)
		applyMode(self, mode)
	end)
	callbacks.ModeChanged(self._mode)
	return self
end

function ControllerMethods.GetMode(self: InternalController): InputMode
	return self._mode
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot, assigned: boolean)
	if self._destroyed then
		return
	end
	self._snapshot = snapshot
	self._assigned = assigned
	self._prompt:ApplySnapshot(snapshot)
	refreshContexts(self)
end

function ControllerMethods.SetAssigned(self: InternalController, assigned: boolean)
	if self._destroyed or self._assigned == assigned then
		return
	end
	self._assigned = assigned
	refreshContexts(self)
end

function ControllerMethods.SetProfileMenuOpen(self: InternalController, isOpen: boolean)
	self:SetModalBlocked("Collection", isOpen)
end

function ControllerMethods.SetModalBlocked(self: InternalController, blockerName: string, isBlocked: boolean)
	if self._destroyed then
		return
	end
	if blockerName == "" then
		error("InputController modal blocker name must be non-empty", 2)
	end
	local wasBlocked = self._modalBlockers[blockerName] == true
	if wasBlocked == isBlocked then
		return
	end
	if isBlocked then
		self._modalBlockers[blockerName] = true
	else
		self._modalBlockers[blockerName] = nil
	end
	refreshContexts(self)
end

function ControllerMethods.IsModalBlocked(self: InternalController): boolean
	return modalBlocked(self)
end

function ControllerMethods.RefreshContext(self: InternalController)
	if not self._destroyed then
		refreshContexts(self)
	end
end

function ControllerMethods.RefreshPointer(self: InternalController)
	if self._destroyed or self._mode ~= "KeyboardMouse" or not awaitingPlacement(self) then
		return
	end
	local ray = pointerRay()
	if ray ~= nil then
		self._callbacks.PointerRay(ray)
	end
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	local unsubscribeMode = self._unsubscribeMode
	self._unsubscribeMode = nil
	if unsubscribeMode ~= nil then
		unsubscribeMode()
	end
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	local touch = self._touch
	self._touch = nil
	if touch ~= nil then
		touch:Destroy()
	end
	local gamepad = self._gamepad
	self._gamepad = nil
	if gamepad ~= nil then
		gamepad:Destroy()
	end
	self._prompt:Destroy()
	self._modeStore:Destroy()
	self._snapshot = nil
	self._selectedAction = nil
	table.clear(self._modalBlockers)
	observe(self)
end

return table.freeze(InputController)
