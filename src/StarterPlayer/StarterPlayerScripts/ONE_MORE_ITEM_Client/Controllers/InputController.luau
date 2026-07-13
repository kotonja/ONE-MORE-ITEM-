--!strict

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type Callbacks = {
	Move: (deltaX: number, deltaZ: number) -> (),
	Rotate: () -> (),
	Place: () -> (),
	Decision: (choice: string) -> (),
	Restart: () -> (),
	PointerRay: (ray: Ray) -> (),
}

export type Buttons = {
	Rotate: GuiButton,
	Place: GuiButton,
	Ship: GuiButton,
	OneMore: GuiButton,
	PackAgain: GuiButton,
}

export type Controller = {
	RefreshPointer: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_callbacks: Callbacks,
	_connections: { RBXScriptConnection },
	_destroyed: boolean,
}

type ButtonBinding = {
	Button: GuiButton,
	Callback: () -> (),
}

local InputController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

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
		if guiObject:IsA("GuiButton") and guiObject.Visible then
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
	-- GetMouseLocation and ViewportPointToRay use the same inset-adjusted
	-- viewport coordinates. Pairing them avoids applying the GUI inset twice.
	return camera:ViewportPointToRay(pointer.X, pointer.Y)
end

function InputController.new(callbacks: Callbacks, buttons: Buttons): Controller
	local self: InternalController = setmetatable({
		_callbacks = callbacks,
		_connections = {},
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if self._destroyed or gameProcessed or isTyping() then
			return
		end

		local keyCode = input.KeyCode
		if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
			callbacks.Move(0, -1)
		elseif keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
			callbacks.Move(0, 1)
		elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
			callbacks.Move(-1, 0)
		elseif keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
			callbacks.Move(1, 0)
		elseif keyCode == Enum.KeyCode.R then
			callbacks.Rotate()
		elseif keyCode == Enum.KeyCode.Space then
			callbacks.Place()
		elseif keyCode == Enum.KeyCode.Q then
			callbacks.Decision("SHIP")
		elseif keyCode == Enum.KeyCode.E then
			callbacks.Decision("ONE_MORE")
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
			callbacks.Restart()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not isPointerOverButton() then
			callbacks.Place()
		end
	end))

	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if self._destroyed or isTyping() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self:RefreshPointer()
		end
	end))

	local buttonCallbacks: { ButtonBinding } = {
		{ Button = buttons.Rotate, Callback = callbacks.Rotate },
		{ Button = buttons.Place, Callback = callbacks.Place },
		{ Button = buttons.Ship, Callback = function() callbacks.Decision("SHIP") end },
		{ Button = buttons.OneMore, Callback = function() callbacks.Decision("ONE_MORE") end },
		{ Button = buttons.PackAgain, Callback = callbacks.Restart },
	}
	for _, binding in ipairs(buttonCallbacks) do
		table.insert(self._connections, binding.Button.Activated:Connect(binding.Callback))
	end

	return self
end

function ControllerMethods.RefreshPointer(self: InternalController)
	if self._destroyed then
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
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return table.freeze(InputController)
