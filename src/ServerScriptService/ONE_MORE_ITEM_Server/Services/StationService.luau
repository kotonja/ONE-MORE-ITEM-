--!strict

export type AssignmentResult = {
	Assigned: boolean,
	StationId: string?,
	Reason: string,
}

type StationRecord = {
	Id: string,
	Model: Model,
}

export type Service = {
	RebindCharacter: (self: Service, player: Player, character: Model?) -> (),
	AssignPlayer: (self: Service, player: Player) -> AssignmentResult,
	ReleasePlayer: (self: Service, player: Player) -> (),
	GetStationId: (self: Service, player: Player) -> string?,
	GetStationModel: (self: Service, player: Player) -> Model?,
	GetOwner: (self: Service, stationModel: Model) -> Player?,
	GetStationCount: (self: Service) -> number,
	Destroy: (self: Service) -> (),
}

type StationServiceImpl = Service & {
	_stations: { StationRecord },
	_playerToStation: { [Player]: StationRecord },
	_stationToPlayer: { [Model]: Player },
	_characterConnections: { [Player]: RBXScriptConnection },
}

local StationService = {}
StationService.__index = StationService

local function discoverStations(stationsRoot: Instance): { StationRecord }
	local records: { StationRecord } = {}
	for _, child in ipairs(stationsRoot:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Active") ~= false then
			local stationId = child:GetAttribute("StationId")
			if type(stationId) == "string" and stationId ~= "" then
				table.insert(records, { Id = stationId, Model = child })
			end
		end
	end
	table.sort(records, function(a: StationRecord, b: StationRecord): boolean
		return a.Id < b.Id
	end)
	return records
end

function StationService.Create(stationsRoot: Instance): StationServiceImpl
	return setmetatable({
		_stations = discoverStations(stationsRoot),
		_playerToStation = {},
		_stationToPlayer = {},
		_characterConnections = {},
	}, StationService) :: StationServiceImpl
end

function StationService.RebindCharacter(self: StationServiceImpl, player: Player, character: Model?)
	local station = self._playerToStation[player]
	if not station then
		return
	end
	local resolvedCharacter = character or player.Character
	if not resolvedCharacter then
		return
	end
	local playerStand = station.Model:FindFirstChild("PlayerStand")
	if playerStand and playerStand:IsA("BasePart") then
		resolvedCharacter:PivotTo(playerStand.CFrame)
	end
end

function StationService.AssignPlayer(self: StationServiceImpl, player: Player): AssignmentResult
	local existing = self._playerToStation[player]
	if existing then
		self:RebindCharacter(player, player.Character)
		return { Assigned = true, StationId = existing.Id, Reason = "ALREADY_ASSIGNED" }
	end

	for _, station in ipairs(self._stations) do
		if self._stationToPlayer[station.Model] == nil then
			self._playerToStation[player] = station
			self._stationToPlayer[station.Model] = player
			self:RebindCharacter(player, player.Character)
			self._characterConnections[player] = player.CharacterAdded:Connect(function(character: Model)
				self:RebindCharacter(player, character)
			end)
			return { Assigned = true, StationId = station.Id, Reason = "ASSIGNED" }
		end
	end

	return { Assigned = false, StationId = nil, Reason = "NO_STATION" }
end

function StationService.ReleasePlayer(self: StationServiceImpl, player: Player)
	local connection = self._characterConnections[player]
	if connection then
		connection:Disconnect()
		self._characterConnections[player] = nil
	end

	local station = self._playerToStation[player]
	if station then
		self._stationToPlayer[station.Model] = nil
		self._playerToStation[player] = nil
	end
end

function StationService.GetStationId(self: StationServiceImpl, player: Player): string?
	local station = self._playerToStation[player]
	return if station then station.Id else nil
end

function StationService.GetStationModel(self: StationServiceImpl, player: Player): Model?
	local station = self._playerToStation[player]
	return if station then station.Model else nil
end

function StationService.GetOwner(self: StationServiceImpl, stationModel: Model): Player?
	return self._stationToPlayer[stationModel]
end

function StationService.GetStationCount(self: StationServiceImpl): number
	return #self._stations
end

function StationService.Destroy(self: StationServiceImpl)
	local players: { Player } = {}
	for player in pairs(self._playerToStation) do
		table.insert(players, player)
	end
	for _, player in ipairs(players) do
		self:ReleasePlayer(player)
	end
end

return table.freeze(StationService)
