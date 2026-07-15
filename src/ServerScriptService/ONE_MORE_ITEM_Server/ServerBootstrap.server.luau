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
local ProfileNet = requireDirect(Root, "ProfileNet", "Folder")

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

local profileRemoteCount = 0
for _, child in ipairs(ProfileNet:GetChildren()) do
	if child:IsA("RemoteEvent") then
		profileRemoteCount += 1
		if child.Name ~= "ProfileSnapshot" then
			error(string.format("Unexpected profile RemoteEvent %s", child:GetFullName()))
		end
	end
end
if profileRemoteCount ~= 1 then
	error(string.format("ONE_MORE_ITEM.ProfileNet must contain exactly one RemoteEvent; found %d", profileRemoteCount))
end

local ClientReadyRequest = requireDirect(Net, "ClientReadyRequest", "RemoteEvent") :: RemoteEvent
local PlaceItemRequest = requireDirect(Net, "PlaceItemRequest", "RemoteEvent") :: RemoteEvent
local DecisionRequest = requireDirect(Net, "DecisionRequest", "RemoteEvent") :: RemoteEvent
local RestartRequest = requireDirect(Net, "RestartRequest", "RemoteEvent") :: RemoteEvent
local RoundSnapshot = requireDirect(Net, "RoundSnapshot", "RemoteEvent") :: RemoteEvent
local PlacementResponse = requireDirect(Net, "PlacementResponse", "RemoteEvent") :: RemoteEvent
local ProfileSnapshot = requireDirect(ProfileNet, "ProfileSnapshot", "RemoteEvent") :: RemoteEvent

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
local collectionShelfItemTemplate = requireDirect(
	developmentAssets,
	"CollectionShelfItemTemplate",
	"BasePart"
) :: BasePart

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
local CollectionShelfService = require(script.Parent.Services.CollectionShelfService)
local ProfileModules = script.Parent.Services.Profile
local DataStoreProfileAdapter = require(ProfileModules.DataStoreProfileAdapter)
local ProfileService = require(ProfileModules.ProfileService)
local ProgressionService = require(ProfileModules.ProgressionService)

type StationRecord = StationService.StationRecord
type RoundStateEvent = RoundService.RoundStateEvent
type HighRiskMilestoneEvent = RoundService.HighRiskMilestoneEvent
type RoundFailureEvent = RoundService.RoundFailureEvent
type ShipmentRecord = RoundService.ShipmentRecord

local readyPlayers: { [Player]: boolean } = {}
local removingPlayers: { [Player]: boolean } = {}
local shutdownStarted = false

local profileService: any = nil
local stationService: any = nil
local worldItemService: any = nil
local stationDisplayService: any = nil
local collectionShelfService: any = nil
local roundService: any = nil

local function playerForUserId(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

profileService = ProfileService.Create(DataStoreProfileAdapter.Create(), {
	SnapshotSink = function(userId: number, snapshot: any)
		local player = playerForUserId(userId)
		if player == nil then
			return
		end
		ProfileSnapshot:FireClient(player, snapshot)
		if stationService ~= nil and collectionShelfService ~= nil then
			local stationId = stationService:GetStationId(player)
			local profile = profileService:GetProfileCopy(userId)
			if stationId ~= nil and profile ~= nil then
				local ok, reason = collectionShelfService:Render(stationId, profile :: any)
				if not ok then
					warn(string.format("[ONE_MORE_ITEM][Shelf] refresh rejected station=%s reason=%s", stationId, reason))
				end
			end
		end
	end,
	LifecycleSink = function(userId: number, state: string)
		local player = playerForUserId(userId)
		if player == nil or stationService == nil or roundService == nil then
			return
		end
		if state == "Conflict" or state == "Unavailable" or state == "Releasing" or state == "Released" then
			roundService:RemovePlayer(player)
			stationService:ReleasePlayer(player)
		elseif (state == "Ready" or state == "Saving" or state == "SaveDelayed")
			and stationService:GetStationId(player) == nil
		then
			stationService:AssignPlayer(player)
		end
	end,
})
local progressionService = ProgressionService.Create(profileService)

stationService = StationService.Create(stationsRoot, {
	IsPlayerEligible = function(player: Player): boolean
		return not removingPlayers[player]
			and not shutdownStarted
			and profileService:CanEnterGameplay(player.UserId)
	end,
})
worldItemService = WorldItemService.Create(cellBlockTemplate, stationService)
stationDisplayService = StationDisplayService.Create(stationService)
collectionShelfService = CollectionShelfService.Create(stationsRoot, collectionShelfItemTemplate)
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

roundService = RoundService.Create(stationService, worldItemService, {
	SnapshotSink = function(player: Player, snapshot: any)
		RoundSnapshot:FireClient(player, snapshot)
	end,
	EventSink = eventSink,
	ShipmentRecordService = shipmentRecordService,
	ProfileService = profileService,
	ProgressionService = progressionService,
	ServerSessionId = profileService:GetServerSessionId(),
})
local rateLimiter = RequestRateLimiter.Create()

local function waitingReason(player: Player): string
	local state = profileService:GetState(player.UserId)
	if state == "Loading" or state == nil then
		return "LOADING YOUR PROFILE"
	elseif state == "Unavailable" then
		return "DATA UNAVAILABLE | REJOIN TO RETRY"
	elseif state == "Conflict" then
		return "PROFILE OPEN ELSEWHERE | CLOSE THE OTHER SESSION AND REJOIN"
	end
	return "WAITING FOR A PACKING STATION"
end

local function sendWaitingSnapshot(player: Player)
	RoundSnapshot:FireClient(player, {
		RoundId = 0,
		OutcomeId = nil,
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
		SessionBank = profileService:GetTape(player.UserId) or 0,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		ResultReason = waitingReason(player),
		ResultValue = 0,
		ResultLostValue = 0,
		QueuePosition = stationService:GetQueuePosition(player),
	})
end

stationService:SetCallbacks({
	OnReleased = function(_player: Player, station: StationRecord)
		-- Cleanup completes before FIFO promotion, preventing inherited world/profile presentation.
		worldItemService:ClearStation(station.Id)
		stationDisplayService:ReleaseStation(station.Id)
		collectionShelfService:Clear(station.Id)
	end,
	OnAssigned = function(player: Player, station: StationRecord, reason: string)
		stationDisplayService:SetOwner(player, station.Id)
		local profile = profileService:GetProfileCopy(player.UserId)
		if profile ~= nil then
			local rendered, renderReason = collectionShelfService:Render(station.Id, profile :: any)
			if not rendered then
				warn(string.format("[ONE_MORE_ITEM][Shelf] assignment render rejected station=%s reason=%s", station.Id, renderReason))
			end
		end
		print(string.format(
			"[ONE_MORE_ITEM][Station] user=%d station=%s index=%d reason=%s",
			player.UserId,
			station.Id,
			station.Index,
			reason
		))
		if readyPlayers[player] and profileService:CanEnterGameplay(player.UserId) then
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

local function assignEligiblePlayer(player: Player)
	if not profileService:CanEnterGameplay(player.UserId) then
		return
	end
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
	if not profileService:CanEnterGameplay(player.UserId) then
		sendWaitingSnapshot(player)
		return
	end
	if stationService:GetStationId(player) == nil then
		assignEligiblePlayer(player)
	end
	if stationService:GetStationId(player) == nil then
		sendWaitingSnapshot(player)
	elseif readyPlayers[player] then
		roundService:HandleClientReady(player)
	end
end

local function beginProfileLoad(player: Player)
	task.spawn(function()
		local success, code = profileService:LoadPlayer(player.UserId)
		if player.Parent ~= Players or removingPlayers[player] then
			profileService:BeginRelease(player.UserId)
			profileService:Release(player.UserId)
			return
		end
		if success then
			assignEligiblePlayer(player)
			syncPlayerState(player)
		else
			warn(string.format("[ONE_MORE_ITEM][Profile] load ended userId=%d code=%s", player.UserId, code))
			sendWaitingSnapshot(player)
		end
	end)
end

Players.PlayerAdded:Connect(beginProfileLoad)
Players.PlayerRemoving:Connect(function(player: Player)
	if removingPlayers[player] then
		return
	end
	removingPlayers[player] = true
	readyPlayers[player] = nil
	profileService:BeginRelease(player.UserId)
	roundService:RemovePlayer(player)
	stationService:ReleasePlayer(player)
	rateLimiter:RemoveUser(player.UserId)
	if not shutdownStarted then
		task.spawn(function()
			local success, code = profileService:Release(player.UserId)
			if not success then
				warn(string.format("[ONE_MORE_ITEM][Profile] release failed userId=%d code=%s", player.UserId, code))
			end
			removingPlayers[player] = nil
		end)
	else
		removingPlayers[player] = nil
	end
end)

ClientReadyRequest.OnServerEvent:Connect(function(player: Player)
	readyPlayers[player] = true
	if not rateAllowed(player, "ClientReadyRequest") then
		syncPlayerState(player)
		return
	end
	local profileSnapshot = profileService:GetSnapshot(player.UserId)
	if profileSnapshot ~= nil then
		ProfileSnapshot:FireClient(player, profileSnapshot)
	end
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
	beginProfileLoad(player)
end

game:BindToClose(function()
	shutdownStarted = true
	profileService:BeginShutdown()
	for _, player in ipairs(Players:GetPlayers()) do
		removingPlayers[player] = true
		roundService:RemovePlayer(player)
		stationService:ReleasePlayer(player)
	end
	local result = profileService:Shutdown()
	print(string.format(
		"[ONE_MORE_ITEM][Profile] shutdown successes=%d failures=%d skipped=%d",
		result.Successes,
		result.Failures,
		result.Skipped
	))
	collectionShelfService:ClearAll()
	announcementService:Destroy()
	showcaseService:Destroy()
	stationService:Destroy()
end)

print(string.format(
	"[ONE_MORE_ITEM][Phase05] server ready stations=%d gameplayRemotes=%d profileRemotes=%d profileStore=%s",
	stationService:GetStationCount(),
	remoteCount,
	profileRemoteCount,
	profileService:GetStoreEnvironment()
))
