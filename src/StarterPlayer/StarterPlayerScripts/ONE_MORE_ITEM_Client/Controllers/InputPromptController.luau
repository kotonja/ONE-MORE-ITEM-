--!strict

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local InputModeStore = require(script.Parent.InputModeStore)

type Snapshot = ClientRoundStore.Snapshot
type InputMode = InputModeStore.InputMode

export type Buttons = {
	Rotate: TextButton,
	Place: TextButton,
	Ship: TextButton,
	OneMore: TextButton,
	PackAgain: TextButton,
}

export type SelectedAction = "SHIP" | "ONE_MORE" | "RESTART"

export type PromptSet = {
	Rotate: string,
	Place: string,
	Ship: string,
	OneMore: string,
	PackAgain: string,
	ControlHint: string,
}

export type Controller = {
	SetMode: (self: Controller, mode: InputMode) -> (),
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> (),
	SetSelectedAction: (self: Controller, action: SelectedAction?) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_buttons: Buttons,
	_controlHint: TextLabel,
	_focusStrokes: { [string]: UIStroke },
	_mode: InputMode,
	_snapshot: Snapshot?,
	_selectedAction: SelectedAction?,
	_destroyed: boolean,
}

local InputPromptController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local GUIDANCE_ATTRIBUTE = "ONE_MORE_ITEM_OnboardingGuided"
local INPUT_FOCUS_ATTRIBUTE = "ONE_MORE_ITEM_InputFocused"

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("InputPromptController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireStroke(parent: Instance): UIStroke
	local child = parent:WaitForChild("FocusStroke", 10)
	if child == nil or not child:IsA("UIStroke") then
		error(string.format("InputPromptController requires UIStroke %s.FocusStroke", parent:GetFullName()), 3)
	end
	return child
end

local function difficultyText(snapshot: Snapshot?): string
	if snapshot == nil then
		return ""
	end
	return snapshot.NextDifficulty or ""
end

function InputPromptController.GetPrompts(mode: InputMode, snapshot: Snapshot?): PromptSet
	local shipmentValue = if snapshot ~= nil then snapshot.ShipmentValue else 0
	local possibleValue = if snapshot ~= nil then snapshot.PossibleNextShipmentValue else 0
	local difficulty = difficultyText(snapshot)
	if mode == "Touch" then
		return table.freeze({
			Rotate = "ROTATE",
			Place = "PLACE",
			Ship = string.format("SHIP NOW\nGuaranteed: %d Tape", shipmentValue),
			OneMore = string.format("ONE MORE\nPossible: %d Tape\n%s", possibleValue, difficulty),
			PackAgain = "PACK AGAIN",
			ControlHint = "DRAG TO MOVE",
		}) :: PromptSet
	elseif mode == "Gamepad" then
		local state = if snapshot ~= nil then snapshot.State else ""
		local controlHint = "LEFT STICK / D-PAD TO MOVE"
		if state == "Decision" then
			controlHint = "SELECT  ◀  ▶\nCONFIRM  [A]"
		elseif state == "Results" then
			controlHint = "CONFIRM [A]"
		end
		return table.freeze({
			Rotate = "ROTATE  [X]",
			Place = "PLACE  [A]",
			Ship = string.format("SHIP NOW\nGuaranteed: %d Tape", shipmentValue),
			OneMore = string.format("ONE MORE\nPossible: %d Tape\n%s", possibleValue, difficulty),
			PackAgain = "PACK AGAIN  [A]",
			ControlHint = controlHint,
		}) :: PromptSet
	end
	return table.freeze({
		Rotate = "ROTATE  [R]",
		Place = "PLACE  [SPACE]",
		Ship = string.format("SHIP NOW  [Q]\nGuaranteed: %d Tape", shipmentValue),
		OneMore = string.format("ONE MORE  [E]\nPossible: %d Tape\n%s", possibleValue, difficulty),
		PackAgain = "PACK AGAIN  [ENTER]",
		ControlHint = "MOUSE / WASD / ARROWS TO MOVE",
	}) :: PromptSet
end

local function applyPrompts(self: InternalController)
	local prompts = InputPromptController.GetPrompts(self._mode, self._snapshot)
	self._buttons.Rotate.Text = prompts.Rotate
	self._buttons.Place.Text = prompts.Place
	self._buttons.Ship.Text = prompts.Ship
	self._buttons.OneMore.Text = prompts.OneMore
	self._buttons.PackAgain.Text = prompts.PackAgain
	self._controlHint.Text = prompts.ControlHint
end

local function applyFocus(self: InternalController)
	for action, stroke in pairs(self._focusStrokes) do
		local guided = stroke:GetAttribute(GUIDANCE_ATTRIBUTE) == true
		local focused = self._mode == "Gamepad" and self._selectedAction == action
		stroke:SetAttribute(INPUT_FOCUS_ATTRIBUTE, focused)
		stroke.Enabled = true
		stroke.Transparency = if guided or focused then 0 else 1
	end
end

function InputPromptController.new(root: GuiObject, buttons: Buttons): Controller
	local placementControls = root:WaitForChild("PlacementControls", 10)
	if placementControls == nil or not placementControls:IsA("GuiObject") then
		error("InputPromptController requires authored PlacementControls", 2)
	end
	local self: InternalController = setmetatable({
		_buttons = buttons,
		_controlHint = requireLabel(placementControls, "ControlHint"),
		_focusStrokes = {
			ROTATE = requireStroke(buttons.Rotate),
			PLACE = requireStroke(buttons.Place),
			SHIP = requireStroke(buttons.Ship),
			ONE_MORE = requireStroke(buttons.OneMore),
			RESTART = requireStroke(buttons.PackAgain),
		},
		_mode = "KeyboardMouse",
		_snapshot = nil,
		_selectedAction = nil,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	applyPrompts(self)
	applyFocus(self)
	return self
end

function ControllerMethods.SetMode(self: InternalController, mode: InputMode)
	if self._destroyed or self._mode == mode then
		return
	end
	self._mode = mode
	if mode ~= "Gamepad" then
		self._selectedAction = nil
	end
	applyPrompts(self)
	applyFocus(self)
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot)
	if self._destroyed then
		return
	end
	self._snapshot = snapshot
	applyPrompts(self)
	applyFocus(self)
end

function ControllerMethods.SetSelectedAction(self: InternalController, action: SelectedAction?)
	if self._destroyed or self._selectedAction == action then
		return
	end
	self._selectedAction = action
	applyFocus(self)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._selectedAction = nil
	for _, stroke in pairs(self._focusStrokes) do
		stroke:SetAttribute(INPUT_FOCUS_ATTRIBUTE, nil)
		stroke.Transparency = 1
		stroke.Enabled = false
	end
	self._snapshot = nil
end

return table.freeze(InputPromptController)
