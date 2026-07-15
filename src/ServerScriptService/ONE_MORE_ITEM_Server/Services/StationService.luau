--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local StationDefinitions = require(Root.Shared.World.StationDefinitions) :: any

type StationDefinition = {
	Id: string,
	Index: number,
	ModelName: string,
}

export type StationRecord = {
	Id: string,
	Index: number,
	Model: Model,
	PlayerStand: BasePart,
	PlacedItems: Folder,
	RuntimePresentation: Folder,
}

export type AssignmentResult = {
	Assigned: boolean,
	Waiting: boolean,
	StationId: string?,
	StationIndex: number?,
	QueuePosition: number?,
	Reason: string,
}

export type ReleaseResult = {
	Released: boolean,
	ReleasedStationId: string?,
	PromotedPlayer: Player?,
	PromotedStationId: string?,
}

export type Callbacks = {
	OnAssigned: ((Player, StationRecord, string) -> ())?,
	OnReleased: ((Player, StationRecord) -> ())?,
}

export type Options = {
	Callbacks: Callbacks?,
	IsPlayerEligible: ((Player) -> boolean)?,
}

export type Service = {
	RebindCharacter: (self: Service, player: Player, character: Model?) -> (),
	AssignPlayer: (self: Service, player: Player) -> AssignmentResult,
	ReleasePlayer: (self: Service, player: Player) -> ReleaseResult,
	GetStationId: (self: Service, player: Player) -> string?,
	GetStationModel: (self: Service, player: Player) -> Model?,
	GetStationById: (self: Service, stationId: string) -> StationRecord?,
	GetStations: (self: Service) -> { StationRecord },
	GetOwner: (self: Service, stationModel: Model) -> Player?,
	GetStationCount: (self: Service) -> number,
	IsWaiting: (self: Service, player: Player) -> boolean,
	GetQueuePosition: (self: Service, player: Player) -> number?,
	SetCallbacks: (self: Service, callbacks: Callbacks) -> (),
	Destroy: (self: Service) -> (),
}

type StationServiceImpl = Service & {
	_stations: { StationRecord },
	_stationById: { [string]: StationRecord },
	_playerToStation: { [Player]: StationRecord },
	_stationToPlayer: { [Model]: Player },
	_characterConnections: { [Player]: RBXScriptConnection },
	_waiting: { Player },
	_waitingSet: { [Player]: boolean },
	_callbacks: Callbacks,
	_isPlayerEligible: (Player) -> boolean,
}

local StationService = {}
StationService.__index = StationService

local function requireDirect(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA(className) then
		error(string.format("Station registry requires %s.%s to be %s", parent:GetFullName(), name, className), 3)
	end
	return child
end

local function requireNumberAttribute(model: Model, name: string, expected: number)
	local value = model:GetAttribute(name)
	if type(value) ~= "number" or value ~= expected then
		error(string.format("%s attribute %s must equal %s", model:GetFullName(), name, tostring(expected)), 3)
	end
end

local function validateGridTiles(gridTiles: Folder)
	local tileCount = 0
	for _, child in ipairs(gridTiles:GetChildren()) do
		if child:IsA("BasePart") then
			tileCount += 1
		end
	end
	if tileCount ~= 25 then
		error(string.format("%s must contain exactly 25 BasePart grid tiles", gridTiles:GetFullName()), 3)
	end
	for x = 0, 4 do
		for z = 0, 4 do
			requireDirect(gridTiles, string.format("Cell_%d_%d", x, z), "BasePart")
		end
	end
end

local function validateStationModel(model: Model, definition: StationDefinition): StationRecord
	if model:GetAttribute("Active") ~= true then
		error(string.format("%s must have Active=true", model:GetFullName()), 3)
	end
	if model:GetAttribute("StationId") ~= definition.Id then
		error(string.format("%s must have StationId=%s", model:GetFullName(), definition.Id), 3)
	end
	if model:GetAttribute("StationIndex") ~= definition.Index then
		error(string.format("%s must have StationIndex=%d", model:GetFullName(), definition.Index), 3)
	end
	requireNumberAttribute(model, "GridWidth", 5)
	requireNumberAttribute(model, "GridHeight", 4)
	requireNumberAttribute(model, "GridDepth", 5)
	requireNumberAttribute(model, "CellSize", 2)

	requireDirect(model, "StationRoot", "BasePart")
	local playerStand = requireDirect(model, "PlayerStand", "BasePart") :: BasePart
	requireDirect(model, "CameraAnchor", "BasePart")
	requireDirect(model, "CameraAnchorTouchLandscape", "BasePart")
	requireDirect(model, "CameraAnchorTouchPortrait", "BasePart")
	requireDirect(model, "CameraFocus", "BasePart")
	requireDirect(model, "PresentationPoint", "BasePart")
	requireDirect(model, "DispatchPort", "BasePart")

	local crate = requireDirect(model, "Crate", "Folder") :: Folder
	requireDirect(crate, "Base", "BasePart")
	requireDirect(crate, "GridOrigin", "BasePart")
	local gridTiles = requireDirect(crate, "GridTiles", "Folder") :: Folder
	validateGridTiles(gridTiles)
	requireDirect(crate, "WallFront", "BasePart")
	requireDirect(crate, "WallBack", "BasePart")
	requireDirect(crate, "WallLeft", "BasePart")
	requireDirect(crate, "WallRight", "BasePart")
	requireDirect(crate, "Lid", "BasePart")
	requireDirect(crate, "CrateFocus", "BasePart")

	local console = requireDirect(model, "ControlConsole", "Folder") :: Folder
	requireDirect(console, "RotateButton", "BasePart")
	requireDirect(console, "PlaceButton", "BasePart")
	requireDirect(console, "ShipButton", "BasePart")
	requireDirect(console, "OneMoreButton", "BasePart")

	local ownerDisplay = requireDirect(model, "OwnerDisplay", "BasePart")
	local ownerBillboard = requireDirect(ownerDisplay, "BillboardGui", "BillboardGui")
	requireDirect(ownerBillboard, "PlayerName", "TextLabel")
	requireDirect(ownerBillboard, "RoundStatus", "TextLabel")
	requireDirect(ownerBillboard, "RiskValue", "TextLabel")
	requireDirect(ownerBillboard, "StationNumber", "TextLabel")

	local riskIndicator = requireDirect(model, "RiskIndicator", "Folder")
	local indicatorPart = requireDirect(riskIndicator, "IndicatorPart", "BasePart")
	requireDirect(indicatorPart, "Light", "PointLight")

	local placedItems = requireDirect(model, "PlacedItems", "Folder") :: Folder
	local runtimePresentation = requireDirect(model, "RuntimePresentation", "Folder") :: Folder

	return table.freeze({
		Id = definition.Id,
		Index = definition.Index,
		Model = model,
		PlayerStand = playerStand,
		PlacedItems = placedItems,
		RuntimePresentation = runtimePresentation,
	}) :: StationRecord
end

local function discoverStations(stationsRoot: Instance): ({ StationRecord }, { [string]: StationRecord })
	local orderedDefinitions = StationDefinitions.Ordered :: { StationDefinition }
	local capacity = StationDefinitions.Capacity :: number
	if type(orderedDefinitions) ~= "table" or capacity ~= 8 or #orderedDefinitions ~= 8 then
		error("StationDefinitions must expose exactly eight ordered definitions", 2)
	end

	local records: { StationRecord } = {}
	local byId: { [string]: StationRecord } = {}
	local seenIndexes: { [number]: boolean } = {}
	local activeModelCount = 0

	for _, child in ipairs(stationsRoot:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Active") == true then
			activeModelCount += 1
		end
	end
	if activeModelCount ~= capacity then
		error(string.format("Station registry requires exactly %d active Models; found %d", capacity, activeModelCount), 2)
	end

	for position, definition in ipairs(orderedDefinitions) do
		if type(definition.Id) ~= "string"
			or type(definition.Index) ~= "number"
			or type(definition.ModelName) ~= "string"
			or definition.Index ~= position
		then
			error(string.format("StationDefinitions entry %d is malformed or out of order", position), 2)
		end
		if byId[definition.Id] ~= nil or seenIndexes[definition.Index] then
			error(string.format("StationDefinitions contains duplicate id or index at %s", definition.Id), 2)
		end
		local model = stationsRoot:FindFirstChild(definition.ModelName)
		if model == nil or not model:IsA("Model") then
			error(string.format("Station registry requires authored Model %s", definition.ModelName), 2)
		end
		local record = validateStationModel(model, definition)
		byId[record.Id] = record
		seenIndexes[record.Index] = true
		table.insert(records, record)
	end

	for _, child in ipairs(stationsRoot:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Active") == true then
			local stationId = child:GetAttribute("StationId")
			if type(stationId) ~= "string" or byId[stationId] == nil or byId[stationId].Model ~= child then
				error(string.format("Unexpected or duplicate active station Model %s", child:GetFullName()), 2)
			end
		end
	end

	table.freeze(records)
	return records, byId
end

local function defaultEligibility(player: Player): boolean
	if typeof(player) ~= "Instance" then
		return true
	end
	return player.Parent == Players
end

function StationService.Create(stationsRoot: Instance, options: Options?): StationServiceImpl
	local stations, stationById = discoverStations(stationsRoot)
	local resolvedOptions = options or {}
	return setmetatable({
		_stations = stations,
		_stationById = stationById,
		_playerToStation = {},
		_stationToPlayer = {},
		_characterConnections = {},
		_waiting = {},
		_waitingSet = {},
		_callbacks = resolvedOptions.Callbacks or {},
		_isPlayerEligible = resolvedOptions.IsPlayerEligible or defaultEligibility,
	}, StationService) :: StationServiceImpl
end

function StationService.SetCallbacks(self: StationServiceImpl, callbacks: Callbacks)
	self._callbacks = callbacks
end

function StationService.RebindCharacter(self: StationServiceImpl, player: Player, character: Model?)
	local station = self._playerToStation[player]
	if station == nil then
		return
	end
	local resolvedCharacter = character or player.Character
	if resolvedCharacter ~= nil then
		resolvedCharacter:PivotTo(station.PlayerStand.CFrame)
	end
end

local function connectCharacter(self: StationServiceImpl, player: Player)
	local previous = self._characterConnections[player]
	if previous ~= nil then
		previous:Disconnect()
	end
	self._characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		self:RebindCharacter(player, character)
	end)
end

local function assignRecord(
	self: StationServiceImpl,
	player: Player,
	station: StationRecord,
	reason: string
): AssignmentResult
	self._playerToStation[player] = station
	self._stationToPlayer[station.Model] = player
	connectCharacter(self, player)
	self:RebindCharacter(player, player.Character)
	local callback = self._callbacks.OnAssigned
	if callback ~= nil then
		callback(player, station, reason)
	end
	return {
		Assigned = true,
		Waiting = false,
		StationId = station.Id,
		StationIndex = station.Index,
		QueuePosition = nil,
		Reason = reason,
	}
end

function StationService.GetQueuePosition(self: StationServiceImpl, player: Player): number?
	for index, queuedPlayer in ipairs(self._waiting) do
		if queuedPlayer == player then
			return index
		end
	end
	return nil
end

function StationService.IsWaiting(self: StationServiceImpl, player: Player): boolean
	return self._waitingSet[player] == true
end

function StationService.AssignPlayer(self: StationServiceImpl, player: Player): AssignmentResult
	if not self._isPlayerEligible(player) then
		return {
			Assigned = false,
			Waiting = false,
			StationId = nil,
			StationIndex = nil,
			QueuePosition = nil,
			Reason = "INELIGIBLE",
		}
	end
	local existing = self._playerToStation[player]
	if existing ~= nil then
		self:RebindCharacter(player, player.Character)
		return {
			Assigned = true,
			Waiting = false,
			StationId = existing.Id,
			StationIndex = existing.Index,
			QueuePosition = nil,
			Reason = "ALREADY_ASSIGNED",
		}
	end

	if self._waitingSet[player] then
		return {
			Assigned = false,
			Waiting = true,
			StationId = nil,
			StationIndex = nil,
			QueuePosition = self:GetQueuePosition(player),
			Reason = "WAITING",
		}
	end

	for _, station in ipairs(self._stations) do
		if self._stationToPlayer[station.Model] == nil then
			return assignRecord(self, player, station, "ASSIGNED")
		end
	end

	table.insert(self._waiting, player)
	self._waitingSet[player] = true
	return {
		Assigned = false,
		Waiting = true,
		StationId = nil,
		StationIndex = nil,
		QueuePosition = #self._waiting,
		Reason = "WAITING",
	}
end

local function removeWaiting(self: StationServiceImpl, player: Player): boolean
	if not self._waitingSet[player] then
		return false
	end
	self._waitingSet[player] = nil
	for index, queuedPlayer in ipairs(self._waiting) do
		if queuedPlayer == player then
			table.remove(self._waiting, index)
			break
		end
	end
	return true
end

local function promoteOldest(self: StationServiceImpl, station: StationRecord): Player?
	while #self._waiting > 0 do
		local player = table.remove(self._waiting, 1)
		self._waitingSet[player] = nil
		if self._playerToStation[player] == nil and self._isPlayerEligible(player) then
			assignRecord(self, player, station, "PROMOTED")
			return player
		end
	end
	return nil
end

function StationService.ReleasePlayer(self: StationServiceImpl, player: Player): ReleaseResult
	removeWaiting(self, player)

	local connection = self._characterConnections[player]
	if connection ~= nil then
		connection:Disconnect()
		self._characterConnections[player] = nil
	end

	local station = self._playerToStation[player]
	if station == nil then
		return { Released = false, ReleasedStationId = nil, PromotedPlayer = nil, PromotedStationId = nil }
	end

	self._stationToPlayer[station.Model] = nil
	self._playerToStation[player] = nil
	local releasedCallback = self._callbacks.OnReleased
	if releasedCallback ~= nil then
		releasedCallback(player, station)
	end

	local promoted = promoteOldest(self, station)
	return {
		Released = true,
		ReleasedStationId = station.Id,
		PromotedPlayer = promoted,
		PromotedStationId = if promoted ~= nil then station.Id else nil,
	}
end

function StationService.GetStationId(self: StationServiceImpl, player: Player): string?
	local station = self._playerToStation[player]
	return if station ~= nil then station.Id else nil
end

function StationService.GetStationModel(self: StationServiceImpl, player: Player): Model?
	local station = self._playerToStation[player]
	return if station ~= nil then station.Model else nil
end

function StationService.GetStationById(self: StationServiceImpl, stationId: string): StationRecord?
	return self._stationById[stationId]
end

function StationService.GetStations(self: StationServiceImpl): { StationRecord }
	return self._stations
end

function StationService.GetOwner(self: StationServiceImpl, stationModel: Model): Player?
	return self._stationToPlayer[stationModel]
end

function StationService.GetStationCount(self: StationServiceImpl): number
	return #self._stations
end

function StationService.Destroy(self: StationServiceImpl)
	table.clear(self._waiting)
	table.clear(self._waitingSet)
	local players: { Player } = {}
	for player in pairs(self._playerToStation) do
		table.insert(players, player)
	end
	for _, player in ipairs(players) do
		self:ReleasePlayer(player)
	end
end

return table.freeze(StationService)
