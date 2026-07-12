--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local GameConfig = require(Root.Shared.Config.GameConfig)
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local OccupancyGrid = require(Root.Shared.Grid.OccupancyGrid)
local IntegerValidation = require(Root.Shared.Grid.IntegerValidation)
local NetworkTypes = require(Root.Shared.Net.NetworkTypes)
local RoundTypes = require(Root.Shared.Round.RoundTypes)
local RoundMath = require(Root.Shared.Round.RoundMath)
local SequenceService = require(script.Parent.SequenceService)
local PlacementService = require(script.Parent.PlacementService)
local StationServiceModule = require(script.Parent.StationService)
local WorldItemServiceModule = require(script.Parent.WorldItemService)

type RoundRecord = RoundTypes.RoundRecord
type RoundState = RoundTypes.RoundState
type RoundSnapshot = NetworkTypes.RoundSnapshot
type Cell = NetworkTypes.Cell
type PlacementResult = PlacementService.PlacementResult
type Sequence = SequenceService.Service
type StationServiceContract = StationServiceModule.Service
type WorldItemServiceContract = WorldItemServiceModule.Service

type Scheduler = (number, () -> ()) -> ()
type Clock = () -> number
type SnapshotSink = (Player, RoundSnapshot) -> ()

export type Service = {
	GetRound: (self: Service, player: Player) -> RoundRecord?,
	GetSnapshot: (self: Service, player: Player) -> RoundSnapshot?,
	HandleClientReady: (self: Service, player: Player) -> RoundRecord?,
	StartRound: (self: Service, player: Player) -> RoundRecord?,
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
	_sessionBanks: { [Player]: number },
	_nextRoundId: number,
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

function RoundService.Create(
	stationService: StationServiceContract,
	worldItemService: WorldItemServiceContract,
	clock: Clock?,
	scheduler: Scheduler?,
	snapshotSink: SnapshotSink?
): RoundServiceImpl
	return setmetatable({
		_stationService = stationService,
		_worldItemService = worldItemService,
		_clock = clock or defaultClock,
		_scheduler = scheduler or defaultScheduler,
		_snapshotSink = snapshotSink or noSnapshot,
		_rounds = {},
		_sequences = {},
		_sessionBanks = {},
		_nextRoundId = 0,
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

	return {
		RoundId = round.RoundId,
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
	}
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

function RoundService.StartRound(self: RoundServiceImpl, player: Player): RoundRecord?
	local stationId = self._stationService:GetStationId(player)
	if not stationId then
		return nil
	end

	self._nextRoundId += 1
	local roundId = self._nextRoundId
	local firstItem = SequenceService.GetFirstItem()
	local sequence = SequenceService.Create(SequenceService.StableRoundSeed(player.UserId, roundId))
	sequence:RecordOffer(firstItem.Id)
	local round: RoundRecord = {
		PlayerUserId = player.UserId,
		RoundId = roundId,
		StateVersion = 0,
		State = "Preparing",
		StationId = stationId,
		CurrentItemId = firstItem.Id,
		PreviewedNextItemId = nil,
		PreviewDifficulty = nil,
		Grid = OccupancyGrid.CreateGrid(GameConfig.BOX_WIDTH, GameConfig.BOX_HEIGHT, GameConfig.BOX_DEPTH),
		ItemCount = 0,
		BaseValueSum = 0,
		ShipmentValue = 0,
		SessionBank = self._sessionBanks[player] or 0,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		LastClientSequences = { Place = -1, Decision = -1, Restart = -1 },
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
		ShipmentBanked = false,
	}
	self._rounds[player] = round
	self._sequences[player] = sequence
	self:_transition(player, "PresentingItem")
	self:_scheduleCurrentState(player, RoundConfig.PRESENTATION_DURATION)
	return round
end

function RoundService.HandleClientReady(self: RoundServiceImpl, player: Player): RoundRecord?
	local existing = self._rounds[player]
	if existing then
		self:_emitSnapshot(player)
		return existing
	end
	return self:StartRound(player)
end

function RoundService._enterAwaitingPlacement(self: RoundServiceImpl, player: Player)
	local round = self._rounds[player]
	if not round then
		return
	end
	round.DecisionDeadline = nil
	round.PlacementDeadline = self._clock() + RoundConfig.PLACEMENT_DURATION
	self:_transition(player, "AwaitingPlacement")
	self:_scheduleCurrentState(player, RoundConfig.PLACEMENT_DURATION)
end

function RoundService._enterShipping(self: RoundServiceImpl, player: Player, reason: string)
	local round = self._rounds[player]
	if not round or round.ShipmentBanked then
		return
	end
	local shipmentValue = round.ShipmentValue
	local bank, banked = RoundMath.BankShipment(round.SessionBank, shipmentValue, round.ShipmentBanked)
	round.SessionBank = bank
	round.ShipmentBanked = banked
	self._sessionBanks[player] = bank
	round.ResultReason = reason
	round.ResultValue = shipmentValue
	round.ResultLostValue = 0
	round.BaseValueSum = 0
	round.ShipmentValue = 0
	round.CurrentItemId = nil
	round.PreviewedNextItemId = nil
	round.PreviewDifficulty = nil
	round.PlacementDeadline = nil
	round.DecisionDeadline = nil
	self:_transition(player, "Shipping")
	self:_scheduleCurrentState(player, RoundConfig.SHIPPING_PRESENTATION_DURATION)
end

function RoundService._enterFailure(self: RoundServiceImpl, player: Player, reason: string)
	local round = self._rounds[player]
	if not round then
		return
	end
	round.ResultReason = reason
	round.ResultValue = 0
	round.ResultLostValue = round.ShipmentValue
	round.SessionBank = RoundMath.BankAfterFailure(round.SessionBank)
	self._sessionBanks[player] = round.SessionBank
	round.BaseValueSum = 0
	round.ShipmentValue = 0
	round.CurrentItemId = nil
	round.PreviewedNextItemId = nil
	round.PreviewDifficulty = nil
	round.PlacementDeadline = nil
	round.DecisionDeadline = nil
	self:_transition(player, "Failing")
	self:_scheduleCurrentState(player, RoundConfig.FAILURE_PRESENTATION_DURATION)
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
		or round.PlayerUserId ~= player.UserId
		or round.RoundId ~= roundId
		or round.StateVersion ~= stateVersion
		or round.State ~= expectedState
	then
		return false
	end

	if expectedState == "PresentingItem" then
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
	if not round then
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
	round.ItemCount += 1
	round.BaseValueSum += definition.BaseValue
	round.ShipmentValue = RoundMath.CalculateShipmentValue(round.BaseValueSum, round.ItemCount)
	round.PlacementDeadline = nil

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
	round.DecisionDeadline = self._clock() + RoundConfig.DECISION_DURATION
	self:_transition(player, "Decision")
	self:_scheduleCurrentState(player, RoundConfig.DECISION_DURATION)
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
		self:_enterShipping(player, "PLAYER_SHIPPED")
		return true, "SHIPPING"
	elseif choice == "ONE_MORE" and round.PreviewedNextItemId then
		round.LastClientSequences.Decision = sequenceValue :: number
		round.CurrentItemId = round.PreviewedNextItemId
		round.PreviewedNextItemId = nil
		round.PreviewDifficulty = nil
		round.DecisionDeadline = nil
		self:_transition(player, "PresentingItem")
		self:_scheduleCurrentState(player, RoundConfig.PRESENTATION_DURATION)
		return true, "ONE_MORE_ACCEPTED"
	end
	return false, "INVALID_CHOICE"
end

function RoundService.HandleRestart(self: RoundServiceImpl, player: Player, payload: unknown): (boolean, string)
	local round = self._rounds[player]
	local request = requestTable(payload)
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
	local nextRound = self:StartRound(player)
	if not nextRound or nextRound.RoundId == previousRoundId then
		return false, "RESTART_FAILED"
	end
	return true, "RESTARTED"
end

function RoundService.RemovePlayer(self: RoundServiceImpl, player: Player)
	self._worldItemService:ClearPlayer(player)
	self._rounds[player] = nil
	self._sequences[player] = nil
	self._sessionBanks[player] = nil
end

return table.freeze(RoundService)
