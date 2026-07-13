--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local Net = Root:WaitForChild("Net")
local ClientReadyRequest = Net:WaitForChild("ClientReadyRequest") :: RemoteEvent
local PlaceItemRequest = Net:WaitForChild("PlaceItemRequest") :: RemoteEvent
local DecisionRequest = Net:WaitForChild("DecisionRequest") :: RemoteEvent
local RestartRequest = Net:WaitForChild("RestartRequest") :: RemoteEvent
local RoundSnapshot = Net:WaitForChild("RoundSnapshot") :: RemoteEvent
local PlacementResponse = Net:WaitForChild("PlacementResponse") :: RemoteEvent

local worldRoot = workspace:WaitForChild("ONE_MORE_ITEM_WORLD")
local arena = worldRoot:WaitForChild("PlaytestArena")
local stationsRoot = arena:WaitForChild("Stations")
local cellBlockTemplate = Root:WaitForChild("Assets"):WaitForChild("Development"):WaitForChild("CellBlockTemplate")
if not cellBlockTemplate:IsA("BasePart") then
	error("CellBlockTemplate must be an authored BasePart")
end

local StationService = require(script.Parent.Services.StationService)
local WorldItemService = require(script.Parent.Services.WorldItemService)
local RoundService = require(script.Parent.Services.RoundService)
local RequestRateLimiter = require(script.Parent.Services.RequestRateLimiter)
local PlacementService = require(script.Parent.Services.PlacementService)

local stationService = StationService.Create(stationsRoot)
local worldItemService = WorldItemService.Create(cellBlockTemplate, stationService)
local roundService = RoundService.Create(
	stationService,
	worldItemService,
	nil,
	nil,
	function(player: Player, snapshot)
		RoundSnapshot:FireClient(player, snapshot)
	end
)
local rateLimiter = RequestRateLimiter.Create()

local function rateAllowed(player: Player, actionName: string): boolean
	local allowed = rateLimiter:Check(player.UserId, actionName, workspace:GetServerTimeNow())
	if not allowed then
		warn(string.format("[ONE_MORE_ITEM][RateLimit] rejected user=%d action=%s", player.UserId, actionName))
	end
	return allowed
end

local function sendNoStation(player: Player)
	RoundSnapshot:FireClient(player, {
		RoundId = 0,
		StateVersion = 0,
		State = "Results",
		StationId = "",
		CurrentItemId = nil,
		CurrentShapeId = nil,
		NextItemId = nil,
		NextShapeId = nil,
		NextDifficulty = nil,
		OccupiedCells = {},
		ItemCount = 0,
		BaseValueSum = 0,
		ShipmentValue = 0,
		PossibleNextShipmentValue = 0,
		CurrentMultiplier = 1,
		SessionBank = 0,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		ResultReason = "NO_STATION",
		ResultValue = 0,
		ResultLostValue = 0,
	})
end

local function assignPlayer(player: Player)
	local assignment = stationService:AssignPlayer(player)
	if not assignment.Assigned then
		warn(string.format("[ONE_MORE_ITEM][Station] user=%d is spectator reason=%s", player.UserId, assignment.Reason))
	end
end

Players.PlayerAdded:Connect(assignPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	roundService:RemovePlayer(player)
	stationService:ReleasePlayer(player)
	rateLimiter:RemoveUser(player.UserId)
end)

for _, player in ipairs(Players:GetPlayers()) do
	assignPlayer(player)
end

ClientReadyRequest.OnServerEvent:Connect(function(player: Player)
	if not rateAllowed(player, "ClientReadyRequest") then
		return
	end
	if stationService:GetStationId(player) == nil then
		sendNoStation(player)
		return
	end
	roundService:HandleClientReady(player)
end)

PlaceItemRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "PlaceItemRequest") then
		PlacementResponse:FireClient(player, PlacementService.CreateResponse(
			roundService:GetRound(player),
			false,
			"RATE_LIMITED",
			PlacementService.GetClientSequence(payload)
		))
		return
	end
	local result = roundService:HandlePlacement(player, payload)
	local round = roundService:GetRound(player)
	PlacementResponse:FireClient(player, PlacementService.CreateResponse(
		round,
		result.Accepted,
		result.Reason,
		result.ClientSequence
	))
	if not result.Accepted then
		roundService:HandleClientReady(player)
	end
end)

DecisionRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "DecisionRequest") then
		return
	end
	local accepted = roundService:HandleDecision(player, payload)
	if not accepted then
		roundService:HandleClientReady(player)
	end
end)

RestartRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "RestartRequest") then
		return
	end
	local accepted = roundService:HandleRestart(player, payload)
	if not accepted then
		roundService:HandleClientReady(player)
	end
end)
