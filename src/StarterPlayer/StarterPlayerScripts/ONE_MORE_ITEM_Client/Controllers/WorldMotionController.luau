--!strict

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)

type Cell = ClientRoundStore.Cell

export type Controller = {
	SetState: (self: Controller, state: string, previousState: string?) -> (),
	PressButton: (self: Controller, action: string) -> (),
	SetGridFeedback: (self: Controller, cells: { Cell }, valid: boolean) -> (),
	ClearGridFeedback: (self: Controller) -> (),
	PlayPlacementImpact: (self: Controller, position: Vector3, heavy: boolean) -> (),
	PlayRejected: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_station: Model,
	_lid: BasePart,
	_lidOpen: CFrame,
	_lidClosed: CFrame,
	_lidColor: Color3,
	_lidTween: Tween?,
	_buttons: { [string]: BasePart },
	_buttonFrames: { [BasePart]: CFrame },
	_buttonColors: { [BasePart]: Color3 },
	_buttonMaterials: { [BasePart]: Enum.Material },
	_buttonSizes: { [BasePart]: Vector3 },
	_tiles: { [string]: BasePart },
	_tileColors: { [BasePart]: Color3 },
	_tileMaterials: { [BasePart]: Enum.Material },
	_placedItems: Instance,
	_runtimePresentation: Instance,
	_failureBurst: Model?,
	_suppressedParts: { [BasePart]: number },
	_effectEpoch: number,
	_destroyed: boolean,
}

local WorldMotionController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function requireInstance(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, 10)
	if child == nil then
		error(string.format("WorldMotionController requires %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requirePart(parent: Instance, name: string): BasePart
	local child = requireInstance(parent, name)
	if not child:IsA("BasePart") then
		error(string.format("WorldMotionController requires BasePart %s", child:GetFullName()), 3)
	end
	return child
end

local function tileKey(x: number, z: number): string
	return string.format("%d:%d", x, z)
end

local function setButtonAvailable(self: InternalController, action: string, available: boolean)
	local button = self._buttons[action]
	if button == nil then
		return
	end
	button.Color = if available
		then self._buttonColors[button]
		else self._buttonColors[button]:Lerp(PresentationTokens.Color.Background, 0.58)
	button.Material = if available then self._buttonMaterials[button] else Enum.Material.SmoothPlastic
end

local function setActionAvailability(self: InternalController, state: string)
	local placement = state == "AwaitingPlacement"
	local decision = state == "Decision"
	setButtonAvailable(self, "ROTATE", placement)
	setButtonAvailable(self, "PLACE", placement)
	setButtonAvailable(self, "SHIP", decision)
	setButtonAvailable(self, "ONE_MORE", decision)
end

local function cancelLidTween(self: InternalController)
	if self._lidTween ~= nil then
		self._lidTween:Cancel()
		self._lidTween = nil
	end
end

local function tweenLid(
	self: InternalController,
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection,
	target: CFrame,
	color: Color3
)
	cancelLidTween(self)
	local tween = TweenService:Create(
		self._lid,
		TweenInfo.new(duration, easingStyle, easingDirection),
		{ CFrame = target, Color = color }
	)
	self._lidTween = tween
	tween:Play()
end

local function restoreSuppressedParts(self: InternalController)
	for part, transparency in pairs(self._suppressedParts) do
		if part.Parent ~= nil then
			part.LocalTransparencyModifier = transparency
		end
	end
	table.clear(self._suppressedParts)
end

local function destroyFailureBurst(self: InternalController, restoreParts: boolean)
	if self._failureBurst ~= nil then
		self._failureBurst:Destroy()
	end
	self._failureBurst = nil
	if restoreParts then
		restoreSuppressedParts(self)
	end
end

local function clearOwnedRuntimeEffects(self: InternalController)
	for _, child in ipairs(self._runtimePresentation:GetChildren()) do
		if child.Name == "FailureBurst" or child.Name == "PlacementImpactRing" then
			child:Destroy()
		end
	end
	self._failureBurst = nil
end

local function sortedBurstSources(self: InternalController): { BasePart }
	local sources: { BasePart } = {}
	for _, descendant in ipairs(self._placedItems:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(sources, descendant)
		end
	end
	local ghost = self._runtimePresentation:FindFirstChild("LocalPlacementGhost")
	if ghost ~= nil then
		for _, descendant in ipairs(ghost:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(sources, descendant)
			end
		end
	end
	table.sort(sources, function(a: BasePart, b: BasePart): boolean
		return a:GetFullName() < b:GetFullName()
	end)
	return sources
end

local function beginFailureBurst(self: InternalController, epoch: number)
	destroyFailureBurst(self, true)
	local sources = sortedBurstSources(self)
	if #sources == 0 then
		return
	end
	local burst = Instance.new("Model")
	burst.Name = "FailureBurst"
	burst:SetAttribute("Deterministic", true)
	burst:SetAttribute("BlockCount", #sources)
	burst:SetAttribute("ImpactPause", PresentationTokens.Timing.FailureImpactPause)
	burst:SetAttribute(
		"BurstDelay",
		PresentationTokens.Timing.Quick + PresentationTokens.Timing.FailureImpactPause
	)
	burst:SetAttribute("BurstDuration", PresentationTokens.Timing.FailureBurst)
	burst.Parent = self._runtimePresentation
	self._failureBurst = burst

	local blocks: { BasePart } = {}
	for index, source in ipairs(sources) do
		local clone = source:Clone()
		clone:ClearAllChildren()
		clone.Name = string.format("BurstBlock_%02d", index)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.LocalTransparencyModifier = 0
		clone.Parent = burst
		table.insert(blocks, clone)
		if source:IsDescendantOf(self._placedItems) then
			self._suppressedParts[source] = source.LocalTransparencyModifier
			source.LocalTransparencyModifier = 1
		end
	end

	-- Capture the visual sources immediately, but let the failed lid-close
	-- attempt finish before the restrained impact pause and outward motion.
	task.delay(PresentationTokens.Timing.Quick + PresentationTokens.Timing.FailureImpactPause, function()
		if self._destroyed or self._effectEpoch ~= epoch or self._failureBurst ~= burst then
			return
		end
		local stationFrame = self._station:GetPivot()
		for index, block in ipairs(blocks) do
			local angle = math.rad(((index - 1) * 137.508) % 360)
			local horizontal = 2.15 + (((index * 53) % 4) * 0.32)
			local vertical = 1.35 + (((index * 37) % 5) * 0.20)
			local localOffset = Vector3.new(math.cos(angle) * horizontal, vertical, math.sin(angle) * horizontal)
			local worldOffset = stationFrame:VectorToWorldSpace(localOffset)
			local pitch = math.rad(-16 + ((index * 11) % 33))
			local yaw = math.rad(-24 + ((index * 17) % 49))
			local roll = math.rad(-18 + ((index * 23) % 37))
			local target = (block.CFrame + worldOffset) * CFrame.Angles(pitch, yaw, roll)
			TweenService:Create(
				block,
				TweenInfo.new(PresentationTokens.Timing.FailureBurst, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ CFrame = target, Transparency = 1 }
			):Play()
		end
		task.delay(PresentationTokens.Timing.FailureBurst, function()
			if not self._destroyed and self._effectEpoch == epoch and self._failureBurst == burst then
				burst:Destroy()
				self._failureBurst = nil
			end
		end)
	end)
end

local function runGridSweep(self: InternalController, epoch: number)
	local orderedTiles: { BasePart } = {}
	for x = 0, PresentationTokens.Grid.Width - 1 do
		for z = 0, PresentationTokens.Grid.Depth - 1 do
			local tile = self._tiles[tileKey(x, z)]
			if tile ~= nil then
				table.insert(orderedTiles, tile)
			end
		end
	end
	for index, tile in ipairs(orderedTiles) do
		task.delay((index - 1) * PresentationTokens.Timing.GridSweepStep, function()
			if self._destroyed or epoch ~= self._effectEpoch then
				return
			end
			tile.Color = PresentationTokens.Color.Cyan
			tile.Material = Enum.Material.Neon
			task.delay(PresentationTokens.Timing.Snap, function()
				if not self._destroyed and epoch == self._effectEpoch then
					tile.Color = self._tileColors[tile]
					tile.Material = self._tileMaterials[tile]
				end
			end)
		end)
	end
end

function WorldMotionController.new(station: Model): Controller
	local crate = requireInstance(station, "Crate")
	local console = requireInstance(station, "ControlConsole")
	local gridTiles = requireInstance(crate, "GridTiles")
	local lid = requirePart(crate, "Lid")
	local closeOffset = lid:GetAttribute("ClosedOffsetY")
	local offsetY = if type(closeOffset) == "number" then closeOffset else 2

	local buttons: { [string]: BasePart } = {
		ROTATE = requirePart(console, "RotateButton"),
		PLACE = requirePart(console, "PlaceButton"),
		SHIP = requirePart(console, "ShipButton"),
		ONE_MORE = requirePart(console, "OneMoreButton"),
	}
	local buttonFrames: { [BasePart]: CFrame } = {}
	local buttonColors: { [BasePart]: Color3 } = {}
	local buttonMaterials: { [BasePart]: Enum.Material } = {}
	local buttonSizes: { [BasePart]: Vector3 } = {}
	for _, button in pairs(buttons) do
		buttonFrames[button] = button.CFrame
		buttonColors[button] = button.Color
		buttonMaterials[button] = button.Material
		buttonSizes[button] = button.Size
	end

	local tiles: { [string]: BasePart } = {}
	local tileColors: { [BasePart]: Color3 } = {}
	local tileMaterials: { [BasePart]: Enum.Material } = {}
	for _, child in ipairs(gridTiles:GetChildren()) do
		if child:IsA("BasePart") then
			local xText, zText = string.match(child.Name, "^Cell_(%d+)_(%d+)$")
			if xText ~= nil and zText ~= nil then
				tiles[tileKey(tonumber(xText) :: number, tonumber(zText) :: number)] = child
				tileColors[child] = child.Color
				tileMaterials[child] = child.Material
			end
		end
	end

	local self: InternalController = setmetatable({
		_station = station,
		_lid = lid,
		_lidOpen = lid.CFrame,
		_lidClosed = lid.CFrame * CFrame.new(0, -offsetY, 0),
		_lidColor = lid.Color,
		_lidTween = nil,
		_buttons = buttons,
		_buttonFrames = buttonFrames,
		_buttonColors = buttonColors,
		_buttonMaterials = buttonMaterials,
		_buttonSizes = buttonSizes,
		_tiles = tiles,
		_tileColors = tileColors,
		_tileMaterials = tileMaterials,
		_placedItems = requireInstance(station, "PlacedItems"),
		_runtimePresentation = requireInstance(station, "RuntimePresentation"),
		_failureBurst = nil,
		_suppressedParts = {},
		_effectEpoch = 0,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	setActionAvailability(self, "Preparing")
	return self
end

function ControllerMethods.SetState(self: InternalController, state: string, previousState: string?)
	if self._destroyed then
		return
	end
	self._effectEpoch += 1
	local epoch = self._effectEpoch
	cancelLidTween(self)
	setActionAvailability(self, state)
	self:ClearGridFeedback()

	if state == "Shipping" then
		destroyFailureBurst(self, true)
		tweenLid(
			self,
			PresentationTokens.Timing.LidClose,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.InOut,
			self._lidClosed,
			PresentationTokens.Color.Green
		)
	elseif state == "Failing" then
		tweenLid(
			self,
			PresentationTokens.Timing.Quick,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.In,
			self._lidClosed:Lerp(self._lidOpen, 0.22),
			PresentationTokens.Color.Red
		)
		for _, tile in pairs(self._tiles) do
			tile.Color = PresentationTokens.Color.Red
			tile.Material = Enum.Material.Neon
		end
		beginFailureBurst(self, epoch)
		task.delay(PresentationTokens.Timing.Snap, function()
			if not self._destroyed and epoch == self._effectEpoch then
				self:ClearGridFeedback()
			end
		end)
	elseif state == "Preparing" then
		destroyFailureBurst(self, true)
		clearOwnedRuntimeEffects(self)
		if previousState == "Results" then
			tweenLid(
				self,
				PresentationTokens.Timing.LidOpen,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out,
				self._lidOpen,
				self._lidColor
			)
			runGridSweep(self, epoch)
		else
			self._lid.CFrame = self._lidOpen
			self._lid.Color = self._lidColor
		end
	elseif state == "Results" then
		-- A completed burst should leave the failed contents locally suppressed
		-- until Pack Again clears them and begins the reset presentation.
		if previousState == "Failing" then
			destroyFailureBurst(self, false)
		end
	elseif state == "AwaitingPlacement" and previousState ~= "PresentingItem" then
		-- Normal Preparing/PresentingItem flow already opens the lid. This is
		-- only a defensive recovery for an unexpected direct state transition.
		tweenLid(
			self,
			PresentationTokens.Timing.Snap,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.Out,
			self._lidOpen,
			self._lidColor
		)
	end
end

function ControllerMethods.PressButton(self: InternalController, action: string)
	local button = self._buttons[action]
	if self._destroyed or button == nil then
		return
	end
	local original = self._buttonFrames[button]
	local originalSize = self._buttonSizes[button]
	local down = TweenService:Create(
		button,
		TweenInfo.new(PresentationTokens.Timing.ButtonDown, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = original * CFrame.new(0, -0.12, 0), Size = Vector3.new(originalSize.X, originalSize.Y * 0.94, originalSize.Z) }
	)
	down:Play()
	down.Completed:Once(function()
		if self._destroyed then
			return
		end
		TweenService:Create(
			button,
			TweenInfo.new(PresentationTokens.Timing.ButtonReturn, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ CFrame = original, Size = originalSize }
		):Play()
	end)
end

function ControllerMethods.ClearGridFeedback(self: InternalController)
	for _, tile in pairs(self._tiles) do
		tile.Color = self._tileColors[tile]
		tile.Material = self._tileMaterials[tile]
	end
end

function ControllerMethods.SetGridFeedback(self: InternalController, cells: { Cell }, valid: boolean)
	if self._destroyed then
		return
	end
	self:ClearGridFeedback()
	local color = if valid then PresentationTokens.Color.Green else PresentationTokens.Color.Red
	local seen: { [string]: boolean } = {}
	for _, cell in ipairs(cells) do
		local key = tileKey(cell.X, cell.Z)
		if not seen[key] then
			seen[key] = true
			local tile = self._tiles[key]
			if tile ~= nil then
				tile.Color = color
				tile.Material = Enum.Material.Neon
			end
		end
	end
end

function ControllerMethods.PlayPlacementImpact(self: InternalController, position: Vector3, heavy: boolean)
	if self._destroyed then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "PlacementImpactRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = PresentationTokens.Color.Green
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.05, if heavy then 1.5 else 1.0, if heavy then 1.5 else 1.0)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = self._runtimePresentation
	TweenService:Create(
		ring,
		TweenInfo.new(if heavy then 0.32 else 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, if heavy then 4.2 else 3.0, if heavy then 4.2 else 3.0), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, 0.4)
end

function ControllerMethods.PlayRejected(self: InternalController)
	if self._destroyed then
		return
	end
	local previousEpoch = self._effectEpoch
	for _, tile in pairs(self._tiles) do
		tile.Color = PresentationTokens.Color.Red
	end
	task.delay(PresentationTokens.Timing.GhostRejected, function()
		if not self._destroyed and previousEpoch == self._effectEpoch then
			self:ClearGridFeedback()
		end
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._effectEpoch += 1
	cancelLidTween(self)
	destroyFailureBurst(self, true)
	clearOwnedRuntimeEffects(self)
	self:ClearGridFeedback()
	self._lid.CFrame = self._lidOpen
	self._lid.Color = self._lidColor
	for _, button in pairs(self._buttons) do
		button.CFrame = self._buttonFrames[button]
		button.Color = self._buttonColors[button]
		button.Material = self._buttonMaterials[button]
		button.Size = self._buttonSizes[button]
	end
end

return table.freeze(WorldMotionController)
