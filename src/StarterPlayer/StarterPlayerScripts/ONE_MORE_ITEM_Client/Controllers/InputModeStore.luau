--!strict

local UserInputService = game:GetService("UserInputService")

export type InputMode = "KeyboardMouse" | "Touch" | "Gamepad"
export type Mode = InputMode

export type PreferredInputSource = {
	GetPreferredInput: (self: PreferredInputSource) -> Enum.PreferredInput,
	Subscribe: (self: PreferredInputSource, listener: (preferredInput: Enum.PreferredInput) -> ()) -> (() -> ()),
}

type Listener = (mode: InputMode) -> ()

export type Store = {
	GetMode: (self: Store) -> InputMode,
	Subscribe: (self: Store, listener: Listener) -> (() -> ()),
	Destroy: (self: Store) -> (),
}

type InternalStore = Store & {
	_mode: InputMode,
	_listeners: { [number]: Listener },
	_nextListenerId: number,
	_disconnectSource: (() -> ())?,
	_destroyed: boolean,
}

local InputModeStore = {}
local StoreMethods = {}
StoreMethods.__index = StoreMethods

function InputModeStore.ModeFromPreferredInput(preferredInput: Enum.PreferredInput): InputMode
	if preferredInput == Enum.PreferredInput.KeyboardAndMouse then
		return "KeyboardMouse"
	elseif preferredInput == Enum.PreferredInput.Touch then
		return "Touch"
	elseif preferredInput == Enum.PreferredInput.Gamepad then
		return "Gamepad"
	end
	error(string.format("InputModeStore received unsupported PreferredInput %s", tostring(preferredInput)), 2)
end

function InputModeStore.FromPreferredInput(preferredInput: Enum.PreferredInput): InputMode
	return InputModeStore.ModeFromPreferredInput(preferredInput)
end

local productionSource: PreferredInputSource = {
	GetPreferredInput = function(_self: PreferredInputSource): Enum.PreferredInput
		return UserInputService.PreferredInput
	end,
	Subscribe = function(_self: PreferredInputSource, listener: (preferredInput: Enum.PreferredInput) -> ()): () -> ()
		local connection = UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			listener(UserInputService.PreferredInput)
		end)
		local connected = true
		return function()
			if connected then
				connected = false
				connection:Disconnect()
			end
		end
	end,
}

local function applyPreferredInput(self: InternalStore, preferredInput: Enum.PreferredInput)
	if self._destroyed then
		return
	end
	local mode = InputModeStore.ModeFromPreferredInput(preferredInput)
	if mode == self._mode then
		return
	end
	self._mode = mode

	local finalListenerId = self._nextListenerId
	for listenerId = 1, finalListenerId do
		local listener = self._listeners[listenerId]
		if listener ~= nil then
			listener(mode)
		end
	end
end

function InputModeStore.new(source: PreferredInputSource?): Store
	local resolvedSource = source or productionSource
	local self: InternalStore = setmetatable({
		_mode = InputModeStore.ModeFromPreferredInput(resolvedSource:GetPreferredInput()),
		_listeners = {},
		_nextListenerId = 0,
		_disconnectSource = nil,
		_destroyed = false,
	}, StoreMethods) :: InternalStore

	self._disconnectSource = resolvedSource:Subscribe(function(preferredInput: Enum.PreferredInput)
		applyPreferredInput(self, preferredInput)
	end)
	return self
end

function StoreMethods.GetMode(self: InternalStore): InputMode
	return self._mode
end

function StoreMethods.Subscribe(self: InternalStore, listener: Listener): () -> ()
	if self._destroyed then
		error("Cannot subscribe to a destroyed InputModeStore", 2)
	end
	self._nextListenerId += 1
	local listenerId = self._nextListenerId
	self._listeners[listenerId] = listener

	local subscribed = true
	return function()
		if subscribed then
			subscribed = false
			self._listeners[listenerId] = nil
		end
	end
end

function StoreMethods.Destroy(self: InternalStore)
	if self._destroyed then
		return
	end
	self._destroyed = true
	local disconnectSource = self._disconnectSource
	self._disconnectSource = nil
	if disconnectSource ~= nil then
		disconnectSource()
	end
	table.clear(self._listeners)
end

return table.freeze(InputModeStore)
