--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireDirect(parent: Instance, name: string, className: string): Instance
	local child = parent:WaitForChild(name)
	if not child:IsA(className) then
		error(string.format("%s.%s must be %s", parent:GetFullName(), name, className), 2)
	end
	return child
end

local Root = requireDirect(ReplicatedStorage, "ONE_MORE_ITEM", "Folder")
local Net = requireDirect(Root, "Net", "Folder")

local expectedRemoteNames: { [string]: boolean } = {
	ClientReadyRequest = true,
	PlaceItemRequest = true,
	DecisionRequest = true,
	RestartRequest = true,
	RoundSnapshot = true,
	PlacementResponse = true,
}
local remoteCount = 0
for _, child in ipairs(Net:GetChildren()) do
	if child:IsA("RemoteEvent") then
		remoteCount += 1
		if not expectedRemoteNames[child.Name] then
			error(string.format("Unexpected gameplay RemoteEvent %s", child:GetFullName()))
		end
	end
end
if remoteCount ~= 6 then
	error(string.format("ONE_MORE_ITEM.Net must contain exactly six RemoteEvents; found %d", remoteCount))
end

local ClientReadyRequest = requireDirect(Net, "ClientReadyRequest", "RemoteEvent") :: RemoteEvent
local PlaceItemRequest = requireDirect(Net, "PlaceItemRequest", "RemoteEvent") :: RemoteEvent
local DecisionRequest = requireDirect(Net, "DecisionRequest", "RemoteEvent") :: RemoteEvent
local RestartRequest = requireDirect(Net, "RestartRequest", "RemoteEvent") :: RemoteEvent
local RoundSnapshot = requireDirect(Net, "RoundSnapshot", "RemoteEvent") :: RemoteEvent
local PlacementResponse = requireDirect(Net, "PlacementResponse", "RemoteEvent") :: RemoteEvent

local worldRoot = requireDirect(workspace, "ONE_MORE_ITEM_WORLD", "Folder")
local arena = requireDirect(worldRoot, "PlaytestArena", "Folder")
local stationsRoot = requireDirect(arena, "Stations", "Folder")
local centerDispatch = requireDirect(arena, "CenterDispatch", "Model")
local showcaseEntry = requireDirect(centerDispatch, "ShowcaseEntry", "BasePart") :: BasePart
local announcementDisplay = requireDirect(centerDispatch, "ArenaAnnouncement", "BasePart")
local serverBestDisplay = requireDirect(centerDispatch, "ServerBest", "BasePart")
local showcaseLoop = requireDirect(arena, "ShowcaseLoop", "Folder")
local pathNodes = requireDirect(showcaseLoop, "PathNodes", "Folder")
local showcaseRuntime = requireDirect(showcaseLoop, "Runtime", "Folder") :: Folder

local assets = requireDirect(Root, "Assets", "Folder")
local developmentAssets = requireDirect(assets, "Development", "Folder")
local cellBlockTemplate = requireDirect(developmentAssets, "CellBlockTemplate", "BasePart") :: BasePart
local showcaseCrateTemplate = requireDirect(developmentAssets, "ShowcaseCrateTemplate", "Model") :: Model

local StationService = require(script.Parent.Services.StationService)
local WorldItemService = require(script.Parent.Services.WorldItemService)
local RoundService = require(script.Parent.Services.RoundService)
local RequestRateLimiter = require(script.Parent.Services.RequestRateLimiter)
local PlacementService = require(script.Parent.Services.PlacementService)
local ShipmentRecordService = require(script.Parent.Services.ShipmentRecordService)
local ShowcaseService = require(script.Parent.Services.ShowcaseService)
local ServerBestService = require(script.Parent.Services.ServerBestService)
local StationDisplayService = require(script.Parent.Services.StationDisplayService)
local ArenaAnnouncementService = require(script.Parent.Services.ArenaAnnouncementService)

type StationRecord = StationService.StationRecord
type RoundStateEvent = RoundService.RoundStateEvent
type HighRiskMilestoneEvent = RoundService.HighRiskMilestoneEvent
type RoundFailureEvent = RoundService.RoundFailureEvent
type ShipmentRecord = RoundService.ShipmentRecord

local stationService = StationService.Create(stationsRoot)
local worldItemService = WorldItemService.Create(cellBlockTemplate, stationService)
local stationDisplayService = StationDisplayService.Create(stationService)
local showcaseService = ShowcaseService.Create(showcaseCrateTemplate, showcaseEntry, pathNodes, showcaseRuntime)
local serverBestService = ServerBestService.Create(serverBestDisplay)
local announcementService = ArenaAnnouncementService.Create(announcementDisplay)
local shipmentRecordService = ShipmentRecordService.Create()

local function runCosmetic(label: string, callback: () -> ())
	local ok, failure = pcall(callback)
	if not ok then
		warn(string.format("[ONE_MORE_ITEM][Cosmetic] %s failed: %s", label, tostring(failure)))
	end
end

local eventSink: RoundService.EventSink = {
	OnRoundStateChanged = function(_player: Player, event: RoundStateEvent)
		runCosmetic("StationDisplay", function()
			stationDisplayService:ApplyRoundState(event)
		end)
	end,
	OnShipmentCompleted = function(record: ShipmentRecord)
		local isServerBest = false
		local uniqueRecord = true
		runCosmetic("ServerBest", function()
			local accepted, newBest = serverBestService:Consider(record)
			uniqueRecord = accepted
			isServerBest = newBest
		end)
		runCosmetic("Showcase", function()
			showcaseService:Submit(record)
		end)
		if uniqueRecord then
			runCosmetic("ShipmentAnnouncement", function()
				announcementService:AnnounceShipment(record, isServerBest)
			end)
		end
	end,
	OnHighRiskMilestone = function(event: HighRiskMilestoneEvent)
		runCosmetic("HighRiskAnnouncement", function()
			announcementService:AnnounceHighRisk(event)
		end)
	end,
	OnRoundFailed = function(event: RoundFailureEvent)
		runCosmetic("FailureAnnouncement", function()
			announcementService:AnnounceFailure(event)
		end)
	end,
}

local roundService = RoundService.Create(
	stationService,
	worldItemService,
	nil,
	nil,
	function(player: Player, snapshot)
		RoundSnapshot:FireClient(player, snapshot)
	end,
	eventSink,
	shipmentRecordService
)
local rateLimiter = RequestRateLimiter.Create()
local readyPlayers: { [Player]: boolean } = {}

local WAITING_REASON = "WAITING FOR A PACKING STATION"

local function sendWaitingSnapshot(player: Player)
	RoundSnapshot:FireClient(player, {
		RoundId = 0,
		StateVersion = 0,
		State = "Waiting",
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
		ResultReason = WAITING_REASON,
		ResultValue = 0,
		ResultLostValue = 0,
		QueuePosition = stationService:GetQueuePosition(player),
	})
end

stationService:SetCallbacks({
	OnReleased = function(_player: Player, station: StationRecord)
		-- Release cleanup is synchronous and completes before StationService promotes FIFO waiters.
		worldItemService:ClearStation(station.Id)
		stationDisplayService:ReleaseStation(station.Id)
	end,
	OnAssigned = function(player: Player, station: StationRecord, reason: string)
		stationDisplayService:SetOwner(player, station.Id)
		print(string.format(
			"[ONE_MORE_ITEM][Station] user=%d station=%s index=%d reason=%s",
			player.UserId,
			station.Id,
			station.Index,
			reason
		))
		if readyPlayers[player] then
			roundService:HandleClientReady(player)
		end
	end,
})

local function rateAllowed(player: Player, actionName: string): boolean
	local allowed = rateLimiter:Check(player.UserId, actionName, workspace:GetServerTimeNow())
	if not allowed then
		warn(string.format("[ONE_MORE_ITEM][RateLimit] rejected user=%d action=%s", player.UserId, actionName))
	end
	return allowed
end

local function assignPlayer(player: Player)
	local assignment = stationService:AssignPlayer(player)
	if assignment.Waiting then
		print(string.format(
			"[ONE_MORE_ITEM][Station] user=%d is spectator reason=%s",
			player.UserId,
			assignment.Reason
		))
		print(string.format(
			"[ONE_MORE_ITEM][Station] user=%d waiting position=%s",
			player.UserId,
			tostring(assignment.QueuePosition)
		))
	end
end

local function syncPlayerState(player: Player)
	if stationService:GetStationId(player) == nil then
		stationService:AssignPlayer(player)
	end
	if stationService:GetStationId(player) == nil then
		sendWaitingSnapshot(player)
	elseif roundService:GetRound(player) ~= nil or readyPlayers[player] then
		roundService:HandleClientReady(player)
	end
end

Players.PlayerAdded:Connect(assignPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	readyPlayers[player] = nil
	roundService:RemovePlayer(player)
	stationService:ReleasePlayer(player)
	rateLimiter:RemoveUser(player.UserId)
end)

ClientReadyRequest.OnServerEvent:Connect(function(player: Player)
	readyPlayers[player] = true
	if not rateAllowed(player, "ClientReadyRequest") then
		syncPlayerState(player)
		return
	end
	assignPlayer(player)
	syncPlayerState(player)
end)

PlaceItemRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "PlaceItemRequest") then
		PlacementResponse:FireClient(player, PlacementService.CreateResponse(
			roundService:GetRound(player),
			false,
			"RATE_LIMITED",
			PlacementService.GetClientSequence(payload)
		))
		syncPlayerState(player)
		return
	end
	local result = roundService:HandlePlacement(player, payload)
	PlacementResponse:FireClient(player, PlacementService.CreateResponse(
		roundService:GetRound(player),
		result.Accepted,
		result.Reason,
		result.ClientSequence
	))
	if not result.Accepted then
		syncPlayerState(player)
	end
end)

DecisionRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "DecisionRequest") then
		syncPlayerState(player)
		return
	end
	local accepted = roundService:HandleDecision(player, payload)
	if not accepted then
		syncPlayerState(player)
	end
end)

RestartRequest.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if not rateAllowed(player, "RestartRequest") then
		syncPlayerState(player)
		return
	end
	local accepted = roundService:HandleRestart(player, payload)
	if not accepted then
		syncPlayerState(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	assignPlayer(player)
end

game:BindToClose(function()
	announcementService:Destroy()
	showcaseService:Destroy()
	stationService:Destroy()
end)

print(string.format(
	"[ONE_MORE_ITEM][Phase04] server ready stations=%d remotes=%d showcasePathNodes=%d",
	stationService:GetStationCount(),
	remoteCount,
	ShowcaseService.PATH_NODE_COUNT
))
