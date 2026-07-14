--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local ShapeRotation = require(Root.Shared.Grid.ShapeRotation)
local ShipmentTypes = require(Root.Shared.World.ShipmentTypes)

type ShipmentRecord = ShipmentTypes.ShipmentRecord

type QueueEntry = {
	ReceiptSequence: number,
	Record: ShipmentRecord,
}

type ActiveShowcase = QueueEntry & {
	Model: Model,
	Elapsed: number,
	BaseTransparency: { [BasePart]: number },
}

export type Options = {
	AutoConnect: boolean?,
	WarningSink: ((message: string) -> ())?,
}

export type Service = {
	Submit: (self: Service, record: ShipmentRecord) -> (boolean, string),
	Step: (self: Service, deltaTime: number) -> (),
	GetActiveCount: (self: Service) -> number,
	GetPendingCount: (self: Service) -> number,
	GetSeenCount: (self: Service) -> number,
	IsUpdateLoopActive: (self: Service) -> boolean,
	Destroy: (self: Service) -> (),
}

type ShowcaseServiceImpl = Service & {
	_template: Model,
	_entryFrame: CFrame,
	_pathFrames: { CFrame },
	_runtime: Folder,
	_pending: { QueueEntry },
	_active: { ActiveShowcase },
	_seenIds: { [string]: boolean },
	_seenCount: number,
	_receiptSequence: number,
	_connection: RBXScriptConnection?,
	_heartbeatAccumulator: number,
	_autoConnect: boolean,
	_warningSink: (message: string) -> (),
	_overflowWarned: boolean,
	_overflowCount: number,
	_destroyed: boolean,
}

local MAX_ACTIVE = 3
local MAX_PENDING = 16
local MAX_ITEM_PROXIES = 10
local PATH_NODE_COUNT = 16
local LIFT_DURATION = 0.60
local LOOP_DURATION = 9.0
local EXIT_DURATION = 0.40
local UPDATE_INTERVAL = 1 / 30
local LAUNCH_SPACING = 1.25
local SHOWCASE_CELL_SIZE = 0.34

local ShowcaseService = {}
ShowcaseService.__index = ShowcaseService

local function requireLabel(parent: Instance, name: string): TextLabel
	local label = parent:FindFirstChild(name, true)
	if label == nil or not label:IsA("TextLabel") then
		error(string.format("Showcase template requires TextLabel %s", name), 3)
	end
	return label
end

local function requireDirectPart(parent: Instance, name: string): BasePart
	local part = parent:FindFirstChild(name)
	if part == nil or not part:IsA("BasePart") then
		error(string.format("Showcase template requires direct BasePart %s", name), 3)
	end
	return part
end

local function validateTemplate(template: Model)
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			error("ShowcaseCrateTemplate may not contain scripts", 3)
		end
	end
	requireDirectPart(template, "Base")
	requireDirectPart(template, "Lid")
	requireDirectPart(template, "WallFront")
	requireDirectPart(template, "WallBack")
	requireDirectPart(template, "WallLeft")
	requireDirectPart(template, "WallRight")
	local displayAnchor = requireDirectPart(template, "DisplayAnchor")
	requireLabel(displayAnchor, "PlayerName")
	requireLabel(displayAnchor, "ShipmentValue")
	requireLabel(displayAnchor, "ItemCount")
end

local function loadPathFrames(pathNodesRoot: Instance): { CFrame }
	local directNodeCount = 0
	for _, child in ipairs(pathNodesRoot:GetChildren()) do
		if child:IsA("BasePart") then
			directNodeCount += 1
		end
	end
	if directNodeCount ~= PATH_NODE_COUNT then
		error(string.format("Showcase path requires exactly %d direct BasePart nodes", PATH_NODE_COUNT), 3)
	end

	local frames: { CFrame } = table.create(PATH_NODE_COUNT)
	local seenPositions: { [string]: boolean } = {}
	for index = 1, PATH_NODE_COUNT do
		local nodeName = string.format("Node_%02d", index)
		local node = pathNodesRoot:FindFirstChild(nodeName)
		if node == nil or not node:IsA("BasePart") then
			error(string.format("Showcase path requires BasePart %s", nodeName), 3)
		end
		if not node.Anchored or node.CanCollide or node.CanTouch or node.CanQuery then
			error(string.format("Showcase path node %s has unsafe physical properties", nodeName), 3)
		end
		if node:GetAttribute("PathIndex") ~= index then
			error(string.format("Showcase path node %s must have PathIndex=%d", nodeName, index), 3)
		end
		local positionKey = string.format("%.5f:%.5f:%.5f", node.Position.X, node.Position.Y, node.Position.Z)
		if seenPositions[positionKey] then
			error(string.format("Showcase path contains duplicate position at %s", nodeName), 3)
		end
		seenPositions[positionKey] = true
		frames[index] = node.CFrame
	end
	table.freeze(frames)
	return frames
end

local function setSafePhysicalProperties(model: Model): { [BasePart]: number }
	local baseTransparency: { [BasePart]: number } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			baseTransparency[descendant] = descendant.Transparency
		end
	end
	return baseTransparency
end

local function findRotation(itemId: string, quarterTurns: number): (number?, number?, number?)
	local definition = DevelopmentItemDefinitions.Get(itemId)
	if definition == nil then
		return nil
	end
	for _, rotation in ipairs(ShapeRotation.GetUniqueRotations(definition.Shape)) do
		if rotation.QuarterTurns == quarterTurns then
			return rotation.SizeX, rotation.SizeY, rotation.SizeZ
		end
	end
	return nil
end

local function addItemProxies(model: Model, record: ShipmentRecord)
	local pivot = model:GetPivot()
	local proxySource = requireDirectPart(model, "Base")
	for index, item in ipairs(record.PlacedItems) do
		if index > MAX_ITEM_PROXIES then
			break
		end
		local sizeX, sizeY, sizeZ = findRotation(item.ItemId, item.QuarterTurns)
		if sizeX == nil or sizeY == nil or sizeZ == nil then
			error(string.format("Shipment %s contains invalid item rotation %s", record.ShipmentId, item.ItemId), 3)
		end
		local proxy = proxySource:Clone() :: BasePart
		for _, child in ipairs(proxy:GetChildren()) do
			child:Destroy()
		end
		proxy.Name = string.format("ItemProxy_%02d", index)
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanTouch = false
		proxy.CanQuery = false
		proxy.Massless = true
		proxy.Material = Enum.Material.SmoothPlastic
		proxy.Color = Color3.new(item.ColorR, item.ColorG, item.ColorB)
		proxy.Size = Vector3.new(sizeX, sizeY, sizeZ) * SHOWCASE_CELL_SIZE
		local localX = (item.OriginX + ((sizeX - 1) / 2) - 2) * SHOWCASE_CELL_SIZE
		local localY = 0.45 + ((item.OriginY + ((sizeY - 1) / 2)) * SHOWCASE_CELL_SIZE)
		local localZ = (item.OriginZ + ((sizeZ - 1) / 2) - 2) * SHOWCASE_CELL_SIZE
		proxy.CFrame = pivot * CFrame.new(localX, localY, localZ)
		proxy.Parent = model
	end
end

local function updateObservability(self: ShowcaseServiceImpl)
	self._runtime:SetAttribute("ActiveShowcases", #self._active)
	self._runtime:SetAttribute("PendingShowcases", #self._pending)
	self._runtime:SetAttribute("SeenShipments", self._seenCount)
	self._runtime:SetAttribute("OverflowCount", self._overflowCount)
	self._runtime:SetAttribute("UpdateLoopActive", self._connection ~= nil)
end

local function createShowcase(self: ShowcaseServiceImpl, entry: QueueEntry): ActiveShowcase
	local model = self._template:Clone() :: Model
	model.Name = string.format("Showcase_%06d", entry.ReceiptSequence)
	model.Parent = self._runtime
	model:PivotTo(self._entryFrame)
	requireLabel(model, "PlayerName").Text = entry.Record.PlayerDisplayName
	requireLabel(model, "ShipmentValue").Text = string.format("%d TAPE", entry.Record.ShipmentValue)
	requireLabel(model, "ItemCount").Text = string.format("%d ITEMS", entry.Record.ItemCount)
	local baseTransparency = setSafePhysicalProperties(model)
	addItemProxies(model, entry.Record)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and baseTransparency[descendant] == nil then
			baseTransparency[descendant] = descendant.Transparency
		end
	end
	model:SetAttribute("ShipmentId", entry.Record.ShipmentId)
	model:SetAttribute("ReceiptSequence", entry.ReceiptSequence)
	return {
		ReceiptSequence = entry.ReceiptSequence,
		Record = entry.Record,
		Model = model,
		Elapsed = 0,
		BaseTransparency = baseTransparency,
	}
end

local function stopLoop(self: ShowcaseServiceImpl)
	local connection = self._connection
	if connection ~= nil then
		connection:Disconnect()
		self._connection = nil
	end
	self._heartbeatAccumulator = 0
	updateObservability(self)
end

local function canLaunchNext(self: ShowcaseServiceImpl): boolean
	if #self._active >= MAX_ACTIVE or #self._pending == 0 then
		return false
	end
	local newestActive = self._active[#self._active]
	return newestActive == nil or newestActive.Elapsed >= LAUNCH_SPACING
end

local function fillActive(self: ShowcaseServiceImpl)
	if canLaunchNext(self) then
		local entry = table.remove(self._pending, 1)
		table.insert(self._active, createShowcase(self, entry))
	end
end

local function ensureLoop(self: ShowcaseServiceImpl)
	if not self._autoConnect or self._connection ~= nil or #self._active == 0 then
		updateObservability(self)
		return
	end
	self._connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if self._destroyed then
			return
		end
		self._heartbeatAccumulator = math.min(self._heartbeatAccumulator + deltaTime, 0.25)
		while self._heartbeatAccumulator >= UPDATE_INTERVAL do
			self._heartbeatAccumulator -= UPDATE_INTERVAL
			self:Step(UPDATE_INTERVAL)
		end
	end)
	updateObservability(self)
end

local function frameAt(self: ShowcaseServiceImpl, elapsed: number): (CFrame, number)
	if elapsed <= LIFT_DURATION then
		return self._entryFrame:Lerp(self._pathFrames[1], math.clamp(elapsed / LIFT_DURATION, 0, 1)), 0
	end
	local loopElapsed = elapsed - LIFT_DURATION
	if loopElapsed <= LOOP_DURATION then
		local progress = math.clamp(loopElapsed / LOOP_DURATION, 0, 1) * #self._pathFrames
		local firstIndex = (math.floor(progress) % #self._pathFrames) + 1
		local secondIndex = (firstIndex % #self._pathFrames) + 1
		local alpha = progress - math.floor(progress)
		return self._pathFrames[firstIndex]:Lerp(self._pathFrames[secondIndex], alpha), 0
	end
	local exitAlpha = math.clamp((loopElapsed - LOOP_DURATION) / EXIT_DURATION, 0, 1)
	local finalFrame = self._pathFrames[1]
	return finalFrame:Lerp(finalFrame * CFrame.new(0, -3, 0), exitAlpha), exitAlpha
end

function ShowcaseService.Create(
	template: Model,
	showcaseEntry: BasePart,
	pathNodesRoot: Instance,
	runtimeRoot: Folder,
	options: Options?
): ShowcaseServiceImpl
	validateTemplate(template)
	if #runtimeRoot:GetChildren() ~= 0 then
		error("ShowcaseLoop.Runtime must be empty before server startup", 2)
	end
	local resolvedOptions = options or {}
	local warningSink = resolvedOptions.WarningSink or function(message: string)
		warn(message)
	end
	local self: ShowcaseServiceImpl = setmetatable({
		_template = template,
		_entryFrame = showcaseEntry.CFrame,
		_pathFrames = loadPathFrames(pathNodesRoot),
		_runtime = runtimeRoot,
		_pending = {},
		_active = {},
		_seenIds = {},
		_seenCount = 0,
		_receiptSequence = 0,
		_connection = nil,
		_heartbeatAccumulator = 0,
		_autoConnect = resolvedOptions.AutoConnect ~= false,
		_warningSink = warningSink,
		_overflowWarned = false,
		_overflowCount = 0,
		_destroyed = false,
	}, ShowcaseService) :: ShowcaseServiceImpl
	updateObservability(self)
	return self
end

function ShowcaseService.Submit(self: ShowcaseServiceImpl, record: ShipmentRecord): (boolean, string)
	if self._destroyed then
		return false, "DESTROYED"
	end
	if self._seenIds[record.ShipmentId] then
		return false, "DUPLICATE_SHIPMENT"
	end
	self._seenIds[record.ShipmentId] = true
	self._seenCount += 1
	self._receiptSequence += 1
	local entry: QueueEntry = {
		ReceiptSequence = self._receiptSequence,
		Record = record,
	}

	fillActive(self)
	if #self._pending >= MAX_PENDING then
		self._overflowCount += 1
		if not self._overflowWarned then
			self._overflowWarned = true
			self._warningSink("[ONE_MORE_ITEM][Showcase] visual queue full; newest cosmetic shipment discarded")
		end
		updateObservability(self)
		return false, "QUEUE_FULL"
	end
	table.insert(self._pending, entry)
	fillActive(self)

	ensureLoop(self)
	updateObservability(self)
	return true, "ACCEPTED"
end

function ShowcaseService.Step(self: ShowcaseServiceImpl, deltaTime: number)
	if self._destroyed then
		return
	end
	if type(deltaTime) ~= "number" or deltaTime ~= deltaTime or deltaTime < 0 or deltaTime >= math.huge then
		error("Showcase Step deltaTime must be a non-negative finite number", 2)
	end

	for index = #self._active, 1, -1 do
		local active = self._active[index]
		active.Elapsed += deltaTime
		if active.Elapsed >= LIFT_DURATION + LOOP_DURATION + EXIT_DURATION then
			active.Model:Destroy()
			table.remove(self._active, index)
		else
			local frame, fade = frameAt(self, active.Elapsed)
			active.Model:PivotTo(frame)
			if fade > 0 then
				for part, baseTransparency in pairs(active.BaseTransparency) do
					if part.Parent ~= nil then
						part.Transparency = math.max(baseTransparency, fade)
					end
				end
			end
		end
	end

	fillActive(self)
	if #self._active == 0 then
		stopLoop(self)
	else
		ensureLoop(self)
	end
	updateObservability(self)
end

function ShowcaseService.GetActiveCount(self: ShowcaseServiceImpl): number
	return #self._active
end

function ShowcaseService.GetPendingCount(self: ShowcaseServiceImpl): number
	return #self._pending
end

function ShowcaseService.GetSeenCount(self: ShowcaseServiceImpl): number
	return self._seenCount
end

function ShowcaseService.IsUpdateLoopActive(self: ShowcaseServiceImpl): boolean
	return self._connection ~= nil
end

function ShowcaseService.Destroy(self: ShowcaseServiceImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	stopLoop(self)
	for _, active in ipairs(self._active) do
		active.Model:Destroy()
	end
	table.clear(self._active)
	table.clear(self._pending)
	for _, child in ipairs(self._runtime:GetChildren()) do
		child:Destroy()
	end
	updateObservability(self)
end

ShowcaseService.MAX_ACTIVE = MAX_ACTIVE
ShowcaseService.MAX_PENDING = MAX_PENDING
ShowcaseService.MAX_ITEM_PROXIES = MAX_ITEM_PROXIES
ShowcaseService.PATH_NODE_COUNT = PATH_NODE_COUNT
ShowcaseService.UPDATE_INTERVAL = UPDATE_INTERVAL
ShowcaseService.LAUNCH_SPACING = LAUNCH_SPACING

return table.freeze(ShowcaseService)
