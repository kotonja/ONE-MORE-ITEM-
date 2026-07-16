--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local GameConfig = require(Root.Shared.Config.GameConfig)
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local OccupancyGrid = require(Root.Shared.Grid.OccupancyGrid)
local IntegerValidation = require(Root.Shared.Grid.IntegerValidation)
local NetworkTypes = require(Root.Shared.Net.NetworkTypes)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)
local RoundTypes = require(Root.Shared.Round.RoundTypes)
local RoundMath = require(Root.Shared.Round.RoundMath)
local DisplayNameSanitizer = require(Root.Shared.World.DisplayNameSanitizer)
local SequenceService = require(script.Parent.SequenceService)
local PlacementService = require(script.Parent.PlacementService)
local StationServiceModule = require(script.Parent.StationService)
local WorldItemServiceModule = require(script.Parent.WorldItemService)
local ShipmentRecordServiceModule = require(script.Parent.ShipmentRecordService)

type RoundRecord = RoundTypes.RoundRecord
type RoundState = RoundTypes.RoundState
type PreparationMode = "INITIAL" | "RESTART"
type RoundSnapshot = NetworkTypes.RoundSnapshot
type Cell = NetworkTypes.Cell
type PlacementResult = PlacementService.PlacementResult
type Sequence = SequenceService.Service
type StationServiceContract = StationServiceModule.Service
type WorldItemServiceContract = WorldItemServiceModule.Service
type ShipmentRecordServiceContract = ShipmentRecordServiceModule.Service
export type ShipmentRecord = ShipmentRecordServiceModule.ShipmentRecord
type PlacedItemPresentation = RoundTypes.PlacedItemPresentation
type ProgressionReward = ProgressionTypes.ProgressionReward

type Scheduler = (number, () -> ()) -> ()
type Clock = () -> number
type SnapshotSink = (Player, RoundSnapshot) -> ()

type ProfileServiceContract = {
	CanEnterGameplay: (self: ProfileServiceContract, userId: number) -> boolean,
	CanMutate: (self: ProfileServiceContract, userId: number) -> boolean,
	GetTape: (self: ProfileServiceContract, userId: number) -> number?,
}

type ProgressionServiceContract = {
	ApplyShipment: (
		self: ProgressionServiceContract,
		userId: number,
		roundId: number,
		outcomeId: string,
		shipmentRecord: ShipmentRecord
	) -> (ProgressionReward?, string),
	ApplyFailure: (
		self: ProgressionServiceContract,
		userId: number,
		roundId: number,
		outcomeId: string,
		itemCount: number
	) -> (ProgressionReward?, string),
}

export type RoundStateEvent = {
	PlayerUserId: number,
	StationId: string,
	RoundId: number,
	StateVersion: number,
	State: RoundState,
	ItemCount: number,
	ShipmentValue: number,
	ResultReason: string?,
	ResultValue: number,
	ResultLostValue: number,
}

export type HighRiskMilestoneEvent = {
	PlayerUserId: number,
	PlayerDisplayName: string,
	StationId: string,
	RoundId: number,
	ItemCount: number,
	ShipmentValue: number,
}

export type RoundFailureEvent = {
	PlayerUserId: number,
	PlayerDisplayName: string,
	StationId: string,
	RoundId: number,
	ItemCount: number,
	LostValue: number,
	Reason: string,
}

export type RoundStartedEvent = {
	PlayerUserId: number,
	StationId: string,
	RoundId: number,
	StartedAt: number,
	GuidedOnboarding: boolean,
}

export type PlacementAcceptedEvent = {
	PlayerUserId: number,
	StationId: string,
	RoundId: number,
	ItemId: string,
	ItemCount: number,
}

export type DecisionAcceptedEvent = {
	PlayerUserId: number,
	StationId: string,
	RoundId: number,
	Choice: "SHIP" | "ONE_MORE",
	ItemCount: number,
	Difficulty: string?,
}

export type RoundEndedEvent = {
	PlayerUserId: number,
	StationId: string,
	RoundId: number,
	Phase: "ship" | "fail",
	DurationSeconds: number,
	ItemCount: number,
	Reason: string,
	TapeDelta: number,
	NewTape: number,
}

export type EventSink = {
	OnRoundStateChanged: ((Player, RoundStateEvent) -> ())?,
	OnShipmentCompleted: ((ShipmentRecord) -> ())?,
	OnHighRiskMilestone: ((HighRiskMilestoneEvent) -> ())?,
	OnRoundFailed: ((RoundFailureEvent) -> ())?,
	OnRoundStarted: ((Player, RoundStartedEvent) -> ())?,
	OnPlacementAccepted: ((Player, PlacementAcceptedEvent) -> ())?,
	OnDecisionAccepted: ((Player, DecisionAcceptedEvent) -> ())?,
	OnShipmentProgressionApplied: ((Player, ShipmentRecord, ProgressionReward) -> ())?,
	OnRoundEnded: ((Player, RoundEndedEvent) -> ())?,
}

export type Options = {
	Clock: Clock?,
	Scheduler: Scheduler?,
	SnapshotSink: SnapshotSink?,
	EventSink: EventSink?,
	ShipmentRecordService: ShipmentRecordServiceContract?,
	ProfileService: ProfileServiceContract,
	ProgressionService: ProgressionServiceContract,
	ServerSessionId: string,
	IsGuidedOnboarding: ((Player) -> boolean)?,
}

export type Service = {
	GetRound: (self: Service, player: Player) -> RoundRecord?,
	GetSnapshot: (self: Service, player: Player) -> RoundSnapshot?,
	HandleClientReady: (self: Service, player: Player) -> RoundRecord?,
	StartRound: (self: Service, player: Player, preparationMode: PreparationMode?) -> RoundRecord?,
	HandleCapturedTimer: (
		self: Service,
		player: Player,
		roundId: number,
		stateVersion: number,
		expectedState: RoundState
	) -> boolean,
	HandlePlacement: (self: Service, player: Player, payload: unknown) -> PlacementResult,
	HandleDecision: (self: Service, player: Player, payload: unknown) -> (boolean, string),
	HandleRestart: (self: Service, player: Player, payload: unknown) -> (boolean, string),
	RemovePlayer: (self: Service, player: Player) -> (),
	_emitSnapshot: (self: Service, player: Player) -> (),
	_transition: (self: Service, player: Player, newState: RoundState) -> (),
	_scheduleCurrentState: (self: Service, player: Player, duration: number) -> (),
	_enterPresentingItem: (self: Service, player: Player) -> (),
	_enterAwaitingPlacement: (self: Service, player: Player) -> (),
	_enterShipping: (self: Service, player: Player, reason: string) -> (),
	_enterFailure: (self: Service, player: Player, reason: string) -> (),
}

type RoundServiceImpl = Service & {
	_stationService: StationServiceContract,
	_worldItemService: WorldItemServiceContract,
	_clock: Clock,
	_scheduler: Scheduler,
	_snapshotSink: SnapshotSink,
	_rounds: { [Player]: RoundRecord },
	_sequences: { [Player]: Sequence },
	_roundOrdinals: { [number]: number },
	_eventSink: EventSink,
	_shipmentRecordService: ShipmentRecordServiceContract,
	_profileService: ProfileServiceContract,
	_progressionService: ProgressionServiceContract,
	_serverSessionId: string,
	_isGuidedOnboarding: (Player) -> boolean,
}

local RoundService = {}
RoundService.__index = RoundService

local function defaultClock(): number
	return workspace:GetServerTimeNow()
end

local function defaultScheduler(duration: number, callback: () -> ())
	task.delay(duration, callback)
end

local function noSnapshot(_player: Player, _snapshot: RoundSnapshot)
end

local function notGuided(_player: Player): boolean
	return false
end

function RoundService.Create(
	stationService: StationServiceContract,
	worldItemService: WorldItemServiceContract,
	options: Options
): RoundServiceImpl
	if type(options.ServerSessionId) ~= "string"
		or options.ServerSessionId == ""
		or #options.ServerSessionId > 120
	then
		error("RoundService requires a bounded non-empty ServerSessionId", 2)
	end
	local resolvedClock = options.Clock or defaultClock
	return setmetatable({
		_stationService = stationService,
		_worldItemService = worldItemService,
		_clock = resolvedClock,
		_scheduler = options.Scheduler or defaultScheduler,
		_snapshotSink = options.SnapshotSink or noSnapshot,
		_rounds = {},
		_sequences = {},
		_roundOrdinals = {},
		_eventSink = options.EventSink or {},
		_shipmentRecordService = options.ShipmentRecordService or ShipmentRecordServiceModule.Create(resolvedClock),
		_profileService = options.ProfileService,
		_progressionService = options.ProgressionService,
		_serverSessionId = options.ServerSessionId,
		_isGuidedOnboarding = options.IsGuidedOnboarding or notGuided,
	}, RoundService) :: RoundServiceImpl
end

function RoundService.GetRound(self: RoundServiceImpl, player: Player): RoundRecord?
	return self._rounds[player]
end

function RoundService.GetSnapshot(self: RoundServiceImpl, player: Player): RoundSnapshot?
	local round = self._rounds[player]
	if not round then
		return nil
	end
	local current = if round.CurrentItemId then DevelopmentItemDefinitions.Get(round.CurrentItemId) else nil
	local nextItem = if round.PreviewedNextItemId then DevelopmentItemDefinitions.Get(round.PreviewedNextItemId) else nil
	local possibleValue = 0
	if nextItem and round.ItemCount < RoundConfig.MAXIMUM_ITEMS then
		possibleValue = RoundMath.CalculatePossibleShipmentValue(
			round.BaseValueSum,
			round.ItemCount,
			nextItem.BaseValue
		)
	end

	local occupiedCells = round.Grid:GetOccupiedCells()
	local copiedCells: { Cell } = table.create(#occupiedCells)
	for index, cell in ipairs(occupiedCells) do
		copiedCells[index] = { X = cell.X, Y = cell.Y, Z = cell.Z }
	end

	local profileTape = self._profileService:GetTape(player.UserId)
	if profileTape ~= nil then
		round.SessionBank = profileTape
	end
	return {
		RoundId = round.RoundId,
		OutcomeId = round.OutcomeId,
		StateVersion = round.StateVersion,
		State = round.State,
		StationId = round.StationId,
		CurrentItemId = if current then current.Id else nil,
		CurrentShapeId = if current then current.ShapeId else nil,
		NextItemId = if nextItem then nextItem.Id else nil,
		NextShapeId = if nextItem then nextItem.ShapeId else nil,
		NextDifficulty = round.PreviewDifficulty,
		OccupiedCells = copiedCells,
		ItemCount = round.ItemCount,
		BaseValueSum = round.BaseValueSum,
		ShipmentValue = round.ShipmentValue,
		PossibleNextShipmentValue = possibleValue,
		CurrentMultiplier = RoundMath.GetMultiplier(round.ItemCount),
		SessionBank = round.SessionBank,
		PlacementDeadline = round.PlacementDeadline,
		DecisionDeadline = round.DecisionDeadline,
		ResultReason = round.ResultReason,
		ResultValue = round.ResultValue,
		ResultLostValue = round.ResultLostValue,
		GuidedOnboarding = round.GuidedOnboarding,
	}
end

local function safeCallback(label: string, callback: (() -> ())?)
	if callback == nil then
		return
	end
	local ok, failure = pcall(callback)
	if not ok then
		warn(string.format("[ONE_MORE_ITEM][RoundEvent] %s callback failed: %s", label, tostring(failure)))
	end
end

local function makeRoundStateEvent(round: RoundRecord): RoundStateEvent
	return table.freeze({
		PlayerUserId = round.PlayerUserId,
		StationId = round.StationId,
		RoundId = round.RoundId,
		StateVersion = round.StateVersion,
		State = round.State,
		ItemCount = round.ItemCount,
		ShipmentValue = round.ShipmentValue,
		ResultReason = round.ResultReason,
		ResultValue = round.ResultValue,
		ResultLostValue = round.ResultLostValue,
	}) :: RoundStateEvent
end

local function notifyRoundState(self: RoundServiceImpl, player: Player, round: RoundRecord)
	local callback = self._eventSink.OnRoundStateChanged
	if callback ~= nil then
		safeCallback("OnRoundStateChanged", function()
			callback(player, makeRoundStateEvent(round))
		end)
	end
end

function RoundService._emitSnapshot(self: RoundServiceImpl, player: Player)
	local snapshot = self:GetSnapshot(player)
	if snapshot then
		self._snapshotSink(player, snapshot)
	end
end

function RoundService._transition(self: RoundServiceImpl, player: Player, newState: RoundState)
	local round = self._rounds[player]
	if not round then
		return
	end
	round.State = newState
	round.StateVersion += 1
	self:_emitSnapshot(player)
	notifyRoundState(self, player, round)
end

function RoundService._scheduleCurrentState(self: RoundServiceImpl, player: Player, duration: number)
	local round = self._rounds[player]
	if not round then
		return
	end
	local capturedRoundId = round.RoundId
	local capturedVersion = round.StateVersion
	local capturedState = round.State
	self._scheduler(duration, function()
		self:HandleCapturedTimer(player, capturedRoundId, capturedVersion, capturedState)
	end)
end

function RoundService.StartRound(
	self: RoundServiceImpl,
	player: Player,
	preparationMode: PreparationMode?
): RoundRecord?
	local stationId = self._stationService:GetStationId(player)
	if not stationId or not self._profileService:CanEnterGameplay(player.UserId) then
		return nil
	end
	local profileTape = self._profileService:GetTape(player.UserId)
	if profileTape == nil then
		return nil
	end

	local roundId = (self._roundOrdinals[player.UserId] or 0) + 1
	self._roundOrdinals[player.UserId] = roundId
	local firstItem = SequenceService.GetFirstItem()
	local sequence = SequenceService.Create(SequenceService.StableRoundSeed(player.UserId, roundId))
	sequence:RecordOffer(firstItem.Id)
	local round: RoundRecord = {
		PlayerUserId = player.UserId,
		RoundId = roundId,
		OutcomeId = string.format("%d:%s:%d", player.UserId, self._serverSessionId, roundId),
		OutcomeProcessed = false,
		StateVersion = 0,
		State = "Preparing",
		StationId = stationId,
		CurrentItemId = firstItem.Id,
		PreviewedNextItemId = nil,
		PreviewDifficulty = nil,
		Grid = OccupancyGrid.CreateGrid(GameConfig.BOX_WIDTH, GameConfig.BOX_HEIGHT, GameConfig.BOX_DEPTH),
		PlacedItems = {},
		ItemCount = 0,
		BaseValueSum = 0,
		ShipmentValue = 0,
		SessionBank = profileTape,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		LastClientSequences = { Place = -1, Decision = -1, Restart = -1 },
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
		ShipmentBanked = false,
		GuidedOnboarding = self._isGuidedOnboarding(player),
		StartedAt = self._clock(),
	}
	self._rounds[player] = round
	self._sequences[player] = sequence
	self:_emitSnapshot(player)
	notifyRoundState(self, player, round)
	local startedCallback = self._eventSink.OnRoundStarted
	if startedCallback ~= nil then
		local startedEvent = table.freeze({
			PlayerUserId = player.UserId,
			StationId = stationId,
			RoundId = roundId,
			StartedAt = round.StartedAt,
			GuidedOnboarding = round.GuidedOnboarding,
		}) :: RoundStartedEvent
		safeCallback("OnRoundStarted", function()
			startedCallback(player, startedEvent)
		end)
	end
	local preparationDuration = if preparationMode == "RESTART"
		then RoundConfig.RESTART_PREPARING_DURATION
		else RoundConfig.INITIAL_PREPARING_DURATION
	self:_scheduleCurrentState(player, preparationDuration)
	return round
end

function RoundService.HandleClientReady(self: RoundServiceImpl, player: Player): RoundRecord?
	if not self._profileService:CanEnterGameplay(player.UserId) then
		return nil
	end
	local existing = self._rounds[player]
	if existing then
		self:_emitSnapshot(player)
		return existing
	end
	return self:StartRound(player)
end

function RoundService._enterPresentingItem(self: RoundServiceImpl, player: Player)
	self:_transition(player, "PresentingItem")
	self:_scheduleCurrentState(player, RoundConfig.PRESENTATION_DURATION)
end

function RoundService._enterAwaitingPlacement(self: RoundServiceImpl, player: Player)
	local round = self._rounds[player]
	if not round then
		return
	end
	round.DecisionDeadline = nil
	local placementDuration = if round.GuidedOnboarding
		then RoundConfig.GUIDED_PLACEMENT_DURATION
		else RoundConfig.PLACEMENT_DURATION
	round.PlacementDeadline = self._clock() + placementDuration
	self:_transition(player, "AwaitingPlacement")
	self:_scheduleCurrentState(player, placementDuration)
end

function RoundService._enterShipping(self: RoundServiceImpl, player: Player, reason: string)
	local round = self._rounds[player]
	if not round or round.OutcomeProcessed or not self._profileService:CanMutate(player.UserId) then
		return
	end
	local shipmentValue = round.ShipmentValue

	local shipmentRecord: ShipmentRecord? = nil
	local captureOk, capturedOrFailure, captureReason = pcall(function(): (ShipmentRecord?, string)
		return self._shipmentRecordService:Capture(player, round)
	end)
	if captureOk then
		shipmentRecord = capturedOrFailure :: ShipmentRecord?
		if shipmentRecord == nil then
			warn(string.format("[ONE_MORE_ITEM][Shipment] record skipped reason=%s", tostring(captureReason)))
		end
	else
		warn(string.format("[ONE_MORE_ITEM][Shipment] record capture failed: %s", tostring(capturedOrFailure)))
	end
	if shipmentRecord == nil then
		round.ResultReason = "SHIPMENT_RECORD_FAILED"
		round.ResultValue = 0
		round.ResultLostValue = shipmentValue
		round.PlacementDeadline = nil
		round.DecisionDeadline = nil
		self:_transition(player, "Results")
		return
	end

	local progressionOk, rewardOrFailure, progressionCode = pcall(function(): (ProgressionReward?, string)
		return self._progressionService:ApplyShipment(
			player.UserId,
			round.RoundId,
			round.OutcomeId,
			shipmentRecord :: ShipmentRecord
		)
	end)
	local reward = if progressionOk then rewardOrFailure :: ProgressionReward? else nil
	if reward == nil or reward.Duplicate then
		local failureCode = if progressionOk then progressionCode else tostring(rewardOrFailure)
		round.OutcomeProcessed = reward ~= nil and reward.Duplicate
		round.SessionBank = if reward ~= nil then reward.NewTape else round.SessionBank
		round.ResultReason = if reward ~= nil and reward.Duplicate then "DUPLICATE_OUTCOME" else "PROFILE_REWARD_FAILED"
		round.ResultValue = 0
		round.ResultLostValue = shipmentValue
		round.PlacementDeadline = nil
		round.DecisionDeadline = nil
		warn(string.format("[ONE_MORE_ITEM][Progression] shipment rejected userId=%d code=%s", player.UserId, tostring(failureCode)))
		self:_transition(player, "Results")
		return
	end

	round.OutcomeProcessed = true
	round.ShipmentBanked = true
	round.SessionBank = reward.NewTape
	round.ResultReason = reason
	round.ResultValue = reward.TapeDelta
	round.ResultLostValue = 0
	local shipmentProgressionCallback = self._eventSink.OnShipmentProgressionApplied
	if shipmentProgressionCallback ~= nil then
		local completedRecord = shipmentRecord :: ShipmentRecord
		safeCallback("OnShipmentProgressionApplied", function()
			shipmentProgressionCallback(player, completedRecord, reward :: ProgressionReward)
		end)
	end
	local authoritativeTape = self._profileService:GetTape(player.UserId) or reward.NewTape
	round.SessionBank = authoritativeTape
	local roundEndedCallback = self._eventSink.OnRoundEnded
	if roundEndedCallback ~= nil then
		local endedEvent = table.freeze({
			PlayerUserId = player.UserId,
			StationId = round.StationId,
			RoundId = round.RoundId,
			Phase = "ship",
			DurationSeconds = math.max(0, self._clock() - round.StartedAt),
			ItemCount = round.ItemCount,
			Reason = reason,
			TapeDelta = reward.TapeDelta,
			NewTape = authoritativeTape,
		}) :: RoundEndedEvent
		safeCallback("OnRoundEnded", function()
			roundEndedCallback(player, endedEvent)
		end)
	end

	round.BaseValueSum = 0
	round.ShipmentValue = 0
	round.CurrentItemId = nil
	round.PreviewedNextItemId = nil
	round.PreviewDifficulty = nil
	round.PlacementDeadline = nil
	round.DecisionDeadline = nil
	self:_transition(player, "Shipping")
	self:_scheduleCurrentState(player, RoundConfig.SHIPPING_PRESENTATION_DURATION)

	local shipmentCallback = self._eventSink.OnShipmentCompleted
	if shipmentRecord ~= nil and shipmentCallback ~= nil then
		local completedRecord = shipmentRecord
		safeCallback("OnShipmentCompleted", function()
			shipmentCallback(completedRecord)
		end)
	end
end

function RoundService._enterFailure(self: RoundServiceImpl, player: Player, reason: string)
	local round = self._rounds[player]
	if not round or round.OutcomeProcessed or not self._profileService:CanMutate(player.UserId) then
		return
	end
	local lostValue = round.ShipmentValue
	local progressionOk, rewardOrFailure, progressionCode = pcall(function(): (ProgressionReward?, string)
		return self._progressionService:ApplyFailure(
			player.UserId,
			round.RoundId,
			round.OutcomeId,
			round.ItemCount
		)
	end)
	local reward = if progressionOk then rewardOrFailure :: ProgressionReward? else nil
	if reward == nil or reward.Duplicate then
		local failureCode = if progressionOk then progressionCode else tostring(rewardOrFailure)
		round.OutcomeProcessed = reward ~= nil and reward.Duplicate
		round.SessionBank = if reward ~= nil then reward.NewTape else round.SessionBank
		round.ResultReason = if reward ~= nil and reward.Duplicate then "DUPLICATE_OUTCOME" else "PROFILE_REWARD_FAILED"
		round.ResultValue = 0
		round.ResultLostValue = lostValue
		round.PlacementDeadline = nil
		round.DecisionDeadline = nil
		warn(string.format("[ONE_MORE_ITEM][Progression] failure rejected userId=%d code=%s", player.UserId, tostring(failureCode)))
		self:_transition(player, "Results")
		return
	end
	round.OutcomeProcessed = true
	round.SessionBank = reward.NewTape
	local failureEvent = table.freeze({
		PlayerUserId = round.PlayerUserId,
		PlayerDisplayName = DisplayNameSanitizer.Sanitize(player.DisplayName),
		StationId = round.StationId,
		RoundId = round.RoundId,
		ItemCount = round.ItemCount,
		LostValue = lostValue,
		Reason = reason,
	}) :: RoundFailureEvent
	round.ResultReason = reason
	round.ResultValue = 0
	round.ResultLostValue = lostValue
	local roundEndedCallback = self._eventSink.OnRoundEnded
	if roundEndedCallback ~= nil then
		local endedEvent = table.freeze({
			PlayerUserId = player.UserId,
			StationId = round.StationId,
			RoundId = round.RoundId,
			Phase = "fail",
			DurationSeconds = math.max(0, self._clock() - round.StartedAt),
			ItemCount = round.ItemCount,
			Reason = reason,
			TapeDelta = 0,
			NewTape = reward.NewTape,
		}) :: RoundEndedEvent
		safeCallback("OnRoundEnded", function()
			roundEndedCallback(player, endedEvent)
		end)
	end
	round.BaseValueSum = 0
	round.ShipmentValue = 0
	round.CurrentItemId = nil
	round.PreviewedNextItemId = nil
	round.PreviewDifficulty = nil
	round.PlacementDeadline = nil
	round.DecisionDeadline = nil
	self:_transition(player, "Failing")
	self:_scheduleCurrentState(player, RoundConfig.FAILURE_PRESENTATION_DURATION)
	local callback = self._eventSink.OnRoundFailed
	if callback ~= nil then
		safeCallback("OnRoundFailed", function()
			callback(failureEvent)
		end)
	end
end

function RoundService.HandleCapturedTimer(
	self: RoundServiceImpl,
	player: Player,
	roundId: number,
	stateVersion: number,
	expectedState: RoundState
): boolean
	local round = self._rounds[player]
	if not round
		or not self._profileService:CanMutate(player.UserId)
		or round.PlayerUserId ~= player.UserId
		or round.RoundId ~= roundId
		or round.StateVersion ~= stateVersion
		or round.State ~= expectedState
	then
		return false
	end

	if expectedState == "Preparing" then
		self:_enterPresentingItem(player)
	elseif expectedState == "PresentingItem" then
		self:_enterAwaitingPlacement(player)
	elseif expectedState == "AwaitingPlacement" then
		self:_enterFailure(player, "PLACEMENT_TIMEOUT")
	elseif expectedState == "Decision" then
		self:_enterShipping(player, "DECISION_TIMEOUT")
	elseif expectedState == "Shipping" or expectedState == "Failing" then
		self:_transition(player, "Results")
	else
		return false
	end
	return true
end

function RoundService.HandlePlacement(
	self: RoundServiceImpl,
	player: Player,
	payload: unknown
): PlacementResult
	local round = self._rounds[player]
	if not round or not self._profileService:CanMutate(player.UserId) then
		return { Accepted = false, Reason = "NO_ROUND", ClientSequence = -1, Placement = nil }
	end
	local currentItemId = round.CurrentItemId
	local result = PlacementService.ValidateAndApply(
		round,
		player.UserId,
		self._stationService:GetStationId(player),
		payload,
		self._clock()
	)
	if not result.Accepted or not result.Placement or not currentItemId then
		return result
	end

	local definition = DevelopmentItemDefinitions.Get(currentItemId)
	if not definition then
		return { Accepted = false, Reason = "UNKNOWN_ITEM", ClientSequence = result.ClientSequence, Placement = nil }
	end
	self._worldItemService:SpawnAcceptedPlacement(player, currentItemId, result.Placement)
	local origin = result.Placement.Origin
	local placedItem = table.freeze({
		ItemId = currentItemId,
		ShapeId = result.Placement.ShapeId,
		QuarterTurns = result.Placement.QuarterTurns,
		OriginX = origin.X,
		OriginY = origin.Y,
		OriginZ = origin.Z,
		ColorR = definition.Color.R,
		ColorG = definition.Color.G,
		ColorB = definition.Color.B,
	}) :: PlacedItemPresentation
	table.insert(round.PlacedItems, placedItem)
	round.ItemCount += 1
	round.BaseValueSum += definition.BaseValue
	round.ShipmentValue = RoundMath.CalculateShipmentValue(round.BaseValueSum, round.ItemCount)
	round.PlacementDeadline = nil
	local placementCallback = self._eventSink.OnPlacementAccepted
	if placementCallback ~= nil then
		local placementEvent = table.freeze({
			PlayerUserId = player.UserId,
			StationId = round.StationId,
			RoundId = round.RoundId,
			ItemId = currentItemId,
			ItemCount = round.ItemCount,
		}) :: PlacementAcceptedEvent
		safeCallback("OnPlacementAccepted", function()
			placementCallback(player, placementEvent)
		end)
	end

	if round.ItemCount == 6 or round.ItemCount == 8 or round.ItemCount == RoundConfig.MAXIMUM_ITEMS then
		local callback = self._eventSink.OnHighRiskMilestone
		if callback ~= nil then
			local milestone = table.freeze({
				PlayerUserId = player.UserId,
				PlayerDisplayName = DisplayNameSanitizer.Sanitize(player.DisplayName),
				StationId = round.StationId,
				RoundId = round.RoundId,
				ItemCount = round.ItemCount,
				ShipmentValue = round.ShipmentValue,
			}) :: HighRiskMilestoneEvent
			safeCallback("OnHighRiskMilestone", function()
				callback(milestone)
			end)
		end
	end

	if round.ItemCount >= RoundConfig.MAXIMUM_ITEMS then
		self:_enterShipping(player, RoundConfig.MAXIMUM_ITEMS_REASON)
		return result
	end

	local sequence = self._sequences[player]
	local candidate: SequenceService.Candidate? = nil
	local reason: string? = RoundConfig.NO_LEGAL_CANDIDATE_REASON
	if sequence then
		candidate, reason = sequence:SelectNext(round.Grid, currentItemId)
	end
	if not candidate then
		self:_enterShipping(player, reason or RoundConfig.NO_LEGAL_CANDIDATE_REASON)
		return result
	end

	round.PreviewedNextItemId = candidate.Item.Id
	round.PreviewDifficulty = candidate.Difficulty
	local decisionDuration = if round.GuidedOnboarding
		then RoundConfig.GUIDED_DECISION_DURATION
		else RoundConfig.DECISION_DURATION
	round.DecisionDeadline = self._clock() + decisionDuration
	self:_transition(player, "Decision")
	self:_scheduleCurrentState(player, decisionDuration)
	return result
end

local function requestTable(payload: unknown): { [string]: unknown }?
	if type(payload) ~= "table" then
		return nil
	end
	return payload :: { [string]: unknown }
end

function RoundService.HandleDecision(self: RoundServiceImpl, player: Player, payload: unknown): (boolean, string)
	local round = self._rounds[player]
	local request = requestTable(payload)
	if not self._profileService:CanMutate(player.UserId) then
		return false, "PROFILE_NOT_READY"
	end
	if not round or not request then
		return false, "MALFORMED_REQUEST"
	end
	if self._stationService:GetStationId(player) ~= round.StationId or player.UserId ~= round.PlayerUserId then
		return false, "WRONG_PLAYER_OR_STATION"
	end
	if request.RoundId ~= round.RoundId then
		return false, "ROUND_MISMATCH"
	end
	if request.StateVersion ~= round.StateVersion then
		return false, "STATE_VERSION_MISMATCH"
	end
	if round.State ~= "Decision" then
		return false, "WRONG_STATE"
	end
	local sequenceValue = request.ClientSequence
	if not IntegerValidation.IsFiniteInteger(sequenceValue)
		or (sequenceValue :: number) <= round.LastClientSequences.Decision
	then
		return false, "DUPLICATE_SEQUENCE"
	end
	if round.DecisionDeadline == nil or self._clock() > round.DecisionDeadline then
		return false, "DECISION_EXPIRED"
	end

	local choice = request.Choice
	if choice == "SHIP" then
		round.LastClientSequences.Decision = sequenceValue :: number
		local decisionCallback = self._eventSink.OnDecisionAccepted
		if decisionCallback ~= nil then
			local decisionEvent = table.freeze({
				PlayerUserId = player.UserId,
				StationId = round.StationId,
				RoundId = round.RoundId,
				Choice = "SHIP",
				ItemCount = round.ItemCount,
				Difficulty = round.PreviewDifficulty,
			}) :: DecisionAcceptedEvent
			safeCallback("OnDecisionAccepted", function()
				decisionCallback(player, decisionEvent)
			end)
		end
		self:_enterShipping(player, "PLAYER_SHIPPED")
		return if round.State == "Shipping" then true else false,
			if round.State == "Shipping" then "SHIPPING" else (round.ResultReason or "PROFILE_REWARD_FAILED")
	elseif choice == "ONE_MORE" and round.PreviewedNextItemId then
		local acceptedDifficulty = round.PreviewDifficulty
		round.LastClientSequences.Decision = sequenceValue :: number
		round.CurrentItemId = round.PreviewedNextItemId
		round.PreviewedNextItemId = nil
		round.PreviewDifficulty = nil
		round.DecisionDeadline = nil
		local decisionCallback = self._eventSink.OnDecisionAccepted
		if decisionCallback ~= nil then
			local decisionEvent = table.freeze({
				PlayerUserId = player.UserId,
				StationId = round.StationId,
				RoundId = round.RoundId,
				Choice = "ONE_MORE",
				ItemCount = round.ItemCount,
				Difficulty = acceptedDifficulty,
			}) :: DecisionAcceptedEvent
			safeCallback("OnDecisionAccepted", function()
				decisionCallback(player, decisionEvent)
			end)
		end
		self:_enterPresentingItem(player)
		return true, "ONE_MORE_ACCEPTED"
	end
	return false, "INVALID_CHOICE"
end

function RoundService.HandleRestart(self: RoundServiceImpl, player: Player, payload: unknown): (boolean, string)
	local round = self._rounds[player]
	local request = requestTable(payload)
	if not self._profileService:CanMutate(player.UserId) then
		return false, "PROFILE_NOT_READY"
	end
	if not round or not request then
		return false, "MALFORMED_REQUEST"
	end
	if request.RoundId ~= round.RoundId then
		return false, "ROUND_MISMATCH"
	end
	if request.StateVersion ~= round.StateVersion then
		return false, "STATE_VERSION_MISMATCH"
	end
	if round.State ~= "Results" then
		return false, "WRONG_STATE"
	end
	if self._stationService:GetStationId(player) ~= round.StationId or player.UserId ~= round.PlayerUserId then
		return false, "WRONG_PLAYER_OR_STATION"
	end
	local sequenceValue = request.ClientSequence
	if not IntegerValidation.IsFiniteInteger(sequenceValue)
		or (sequenceValue :: number) <= round.LastClientSequences.Restart
	then
		return false, "DUPLICATE_SEQUENCE"
	end
	round.LastClientSequences.Restart = sequenceValue :: number
	self._worldItemService:ClearPlayer(player)
	local previousRoundId = round.RoundId
	local nextRound = self:StartRound(player, "RESTART")
	if not nextRound or nextRound.RoundId == previousRoundId then
		return false, "RESTART_FAILED"
	end
	return true, "RESTARTED"
end

function RoundService.RemovePlayer(self: RoundServiceImpl, player: Player)
	self._worldItemService:ClearPlayer(player)
	self._rounds[player] = nil
	self._sequences[player] = nil
end

return table.freeze(RoundService)
