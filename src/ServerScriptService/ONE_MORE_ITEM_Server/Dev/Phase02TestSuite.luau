--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local GameConfig = require(Root.Shared.Config.GameConfig)
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local OccupancyGrid = require(Root.Shared.Grid.OccupancyGrid)
local PlacementSolver = require(Root.Shared.Grid.PlacementSolver)
local ShapeRotation = require(Root.Shared.Grid.ShapeRotation)
local GridTypes = require(Root.Shared.Grid.GridTypes)
local RoundTypes = require(Root.Shared.Round.RoundTypes)
local RoundMath = require(Root.Shared.Round.RoundMath)
local GridWorldTransform = require(Root.Shared.World.GridWorldTransform)
local DevelopmentItemRenderer = require(Root.Shared.World.DevelopmentItemRenderer)

local ClientRoundStore = require(
	StarterPlayer:WaitForChild("StarterPlayerScripts")
		:WaitForChild("ONE_MORE_ITEM_Client")
		:WaitForChild("Controllers")
		:WaitForChild("ClientRoundStore")
)
local PlacementController = require(
	StarterPlayer:WaitForChild("StarterPlayerScripts")
		:WaitForChild("ONE_MORE_ITEM_Client")
		:WaitForChild("Controllers")
		:WaitForChild("PlacementController")
)
local PresentationTokens = require(
	StarterPlayer:WaitForChild("StarterPlayerScripts")
		:WaitForChild("ONE_MORE_ITEM_Client")
		:WaitForChild("Controllers")
		:WaitForChild("PresentationTokens")
)
local WorldMotionController = require(
	StarterPlayer:WaitForChild("StarterPlayerScripts")
		:WaitForChild("ONE_MORE_ITEM_Client")
		:WaitForChild("Controllers")
		:WaitForChild("WorldMotionController")
)

local PlacementService = require(script.Parent.Parent.Services.PlacementService)
local RequestRateLimiter = require(script.Parent.Parent.Services.RequestRateLimiter)
local RoundService = require(script.Parent.Parent.Services.RoundService)
local SequenceService = require(script.Parent.Parent.Services.SequenceService)
local StationService = require(script.Parent.Parent.Services.StationService)
local WorldItemService = require(script.Parent.Parent.Services.WorldItemService)

type Cell = GridTypes.Cell
type Grid = GridTypes.Grid
type Placement = GridTypes.Placement
type RoundRecord = RoundTypes.RoundRecord
type ClientSnapshot = ClientRoundStore.Snapshot
type ClientCell = ClientRoundStore.Cell

type TestCase = {
	Name: string,
	Run: () -> (),
}

type TestSuite = {
	Name: string,
	Tests: { TestCase },
}

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	Seed: number,
}

local Phase02TestSuite = {}
local suites: { TestSuite } = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual: unknown, expected: unknown, message: string?)
	if actual ~= expected then
		error(message or string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local function expectNear(actual: number, expected: number, epsilon: number)
	if math.abs(actual - expected) > epsilon then
		error(string.format("Expected %.8f, got %.8f", expected, actual), 2)
	end
end

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, { Name = name, Tests = tests })
end

local function newGrid(): Grid
	return OccupancyGrid.CreateGrid(GameConfig.BOX_WIDTH, GameConfig.BOX_HEIGHT, GameConfig.BOX_DEPTH)
end

local function fixturePlacement(cells: { Cell }): Placement
	return {
		ShapeId = "fixture",
		RotationIndex = 1,
		QuarterTurns = 0,
		Origin = { X = 0, Y = 0, Z = 0 },
		Cells = cells,
		Key = "fixture",
	}
end

local function fillGrid(grid: Grid, exceptCell: Cell?)
	local cells: { Cell } = {}
	for x = 0, grid.Width - 1 do
		for y = 0, grid.Height - 1 do
			for z = 0, grid.Depth - 1 do
				if not exceptCell or x ~= exceptCell.X or y ~= exceptCell.Y or z ~= exceptCell.Z then
					table.insert(cells, { X = x, Y = y, Z = z })
				end
			end
		end
	end
	expect(grid:ApplyPlacement(fixturePlacement(cells)), "Grid fixture should apply")
end

local function makeRound(): RoundRecord
	return {
		PlayerUserId = 101,
		RoundId = 7,
		StateVersion = 3,
		State = "AwaitingPlacement",
		StationId = "station_01",
		CurrentItemId = "parcel",
		PreviewedNextItemId = nil,
		PreviewDifficulty = nil,
		Grid = newGrid(),
		ItemCount = 0,
		BaseValueSum = 0,
		ShipmentValue = 0,
		SessionBank = 0,
		PlacementDeadline = 200,
		DecisionDeadline = nil,
		LastClientSequences = { Place = -1, Decision = -1, Restart = -1 },
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
		ShipmentBanked = false,
	}
end

local function validPlacementRequest(round: RoundRecord, sequence: number): { [string]: unknown }
	return {
		RoundId = round.RoundId,
		StateVersion = round.StateVersion,
		ItemId = round.CurrentItemId,
		QuarterTurns = 0,
		OriginX = 0,
		OriginZ = 0,
		ClientSequence = sequence,
	}
end

addSuite("Round math", {
	{ Name = "zero items uses neutral multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(0), 1) end },
	{ Name = "one item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(1), 1.00) end },
	{ Name = "two item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(2), 1.15) end },
	{ Name = "three item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(3), 1.35) end },
	{ Name = "four item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(4), 1.60) end },
	{ Name = "five item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(5), 1.90) end },
	{ Name = "six item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(6), 2.25) end },
	{ Name = "seven item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(7), 2.65) end },
	{ Name = "eight item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(8), 3.20) end },
	{ Name = "nine item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(9), 3.90) end },
	{ Name = "ten item multiplier", Run = function() expectEqual(RoundMath.GetMultiplier(10), 5.00) end },
	{
		Name = "shipment value floors fractional products",
		Run = function() expectEqual(RoundMath.CalculateShipmentValue(41, 2), 47) end,
	},
	{
		Name = "exact multiplier boundaries do not underpay from floating point",
		Run = function() expectEqual(RoundMath.CalculateShipmentValue(100, 2), 115) end,
	},
	{
		Name = "preview uses next item and next multiplier",
		Run = function() expectEqual(RoundMath.CalculatePossibleShipmentValue(15, 1, 25), 46) end,
	},
	{
		Name = "failure preserves existing session Tape",
		Run = function() expectEqual(RoundMath.BankAfterFailure(215), 215) end,
	},
	{
		Name = "shipping banks exactly once",
		Run = function()
			local firstBank, banked = RoundMath.BankShipment(100, 46, false)
			local secondBank = RoundMath.BankShipment(firstBank, 46, banked)
			expectEqual(firstBank, 146)
			expectEqual(secondBank, 146)
		end,
	},
})

addSuite("Sequence fairness", {
	{
		Name = "first item is always Parcel",
		Run = function() expectEqual(SequenceService.GetFirstItem().Id, "parcel") end,
	},
	{
		Name = "every candidate has at least one legal placement",
		Run = function()
			for _, candidate in ipairs(SequenceService.Create(5):EnumerateCandidates(newGrid())) do
				expect(candidate.ValidPlacementCount > 0, "Candidate must have a legal placement")
			end
		end,
	},
	{
		Name = "impossible multi-cell candidates are excluded",
		Run = function()
			local grid = newGrid()
			fillGrid(grid, { X = 4, Y = 3, Z = 4 })
			local candidates = SequenceService.Create(5):EnumerateCandidates(grid)
			expectEqual(#candidates, 1)
			expectEqual(candidates[1].Item.Id, "parcel")
		end,
	},
	{
		Name = "candidate checking does not mutate occupancy",
		Run = function()
			local grid = newGrid()
			local before = grid:GetOccupiedCellCount()
			SequenceService.Create(5):EnumerateCandidates(grid)
			expectEqual(grid:GetOccupiedCellCount(), before)
		end,
	},
	{
		Name = "same seed and grid produce same choice",
		Run = function()
			local a = SequenceService.Create(RoundConfig.DEVELOPMENT.TEST_SEED):SelectNext(newGrid(), "parcel")
			local b = SequenceService.Create(RoundConfig.DEVELOPMENT.TEST_SEED):SelectNext(newGrid(), "parcel")
			expect(a ~= nil and b ~= nil, "Both choices should exist")
			expectEqual((a :: SequenceService.Candidate).Item.Id, (b :: SequenceService.Candidate).Item.Id)
		end,
	},
	{
		Name = "immediate repetition is avoided when alternatives exist",
		Run = function()
			local candidate = SequenceService.Create(9):SelectNext(newGrid(), "parcel")
			expect(candidate ~= nil, "Choice should exist")
			expect((candidate :: SequenceService.Candidate).Item.Id ~= "parcel", "Parcel should not repeat immediately")
		end,
	},
	{
		Name = "third consecutive shape-family offer is avoided",
		Run = function()
			local service = SequenceService.Create(11)
			service:RecordOffer("table_blockout")
			service:RecordOffer("l_package")
			local candidate = service:SelectNext(newGrid(), "l_package")
			expect(candidate ~= nil, "Choice should exist")
			expect((candidate :: SequenceService.Candidate).Item.ShapeFamily ~= "Planar", "A third Planar item should be avoided")
		end,
	},
	{
		Name = "full grid returns BOX_FULL",
		Run = function()
			local grid = newGrid()
			fillGrid(grid)
			local candidate, reason = SequenceService.Create(7):SelectNext(grid, nil)
			expectEqual(candidate, nil)
			expectEqual(reason, "BOX_FULL")
		end,
	},
})

addSuite("Placement security", {
	{
		Name = "wrong player is rejected",
		Run = function()
			local round = makeRound()
			local result = PlacementService.ValidateAndApply(round, 999, "station_01", validPlacementRequest(round, 1), 100)
			expectEqual(result.Reason, "WRONG_PLAYER_OR_STATION")
		end,
	},
	{
		Name = "wrong station is rejected",
		Run = function()
			local round = makeRound()
			local result = PlacementService.ValidateAndApply(round, 101, "station_02", validPlacementRequest(round, 1), 100)
			expectEqual(result.Reason, "WRONG_PLAYER_OR_STATION")
		end,
	},
	{
		Name = "wrong RoundId is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.RoundId = 8
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "ROUND_MISMATCH")
		end,
	},
	{
		Name = "wrong StateVersion is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.StateVersion = 4
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "STATE_VERSION_MISMATCH")
		end,
	},
	{
		Name = "wrong item is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.ItemId = "heavy_cargo"
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "ITEM_MISMATCH")
		end,
	},
	{
		Name = "invalid rotation is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.QuarterTurns = 1
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "INVALID_ROTATION")
		end,
	},
	{
		Name = "NaN origin is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.OriginX = 0 / 0
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "INVALID_ORIGIN")
		end,
	},
	{
		Name = "infinite origin is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.OriginZ = math.huge
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "INVALID_ORIGIN")
		end,
	},
	{
		Name = "fractional origin is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.OriginX = 0.5
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "INVALID_ORIGIN")
		end,
	},
	{
		Name = "bounds violation is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.OriginX = 5
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "NO_LEGAL_PLACEMENT")
		end,
	},
	{
		Name = "collision is rejected",
		Run = function()
			local round = makeRound()
			expect(round.Grid:ApplyPlacement(fixturePlacement({
				{ X = 0, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 },
				{ X = 0, Y = 2, Z = 0 }, { X = 0, Y = 3, Z = 0 },
			})), "Fixture column should apply")
			expectEqual(
				PlacementService.ValidateAndApply(round, 101, "station_01", validPlacementRequest(round, 1), 100).Reason,
				"NO_LEGAL_PLACEMENT"
			)
		end,
	},
	{
		Name = "duplicate sequence is rejected",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			expect(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Accepted, "First request should pass")
			expectEqual(PlacementService.ValidateAndApply(round, 101, "station_01", request, 100).Reason, "DUPLICATE_SEQUENCE")
		end,
	},
	{
		Name = "valid placement applies exactly once",
		Run = function()
			local round = makeRound()
			local result = PlacementService.ValidateAndApply(round, 101, "station_01", validPlacementRequest(round, 1), 100)
			expect(result.Accepted, "Placement should be accepted")
			expectEqual(round.Grid:GetOccupiedCellCount(), 1)
		end,
	},
	{
		Name = "rejection never mutates grid",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 1)
			request.OriginX = -1
			PlacementService.ValidateAndApply(round, 101, "station_01", request, 100)
			expectEqual(round.Grid:GetOccupiedCellCount(), 0)
		end,
	},
	{
		Name = "rejected placement does not consume a newer sequence",
		Run = function()
			local round = makeRound()
			local invalid = validPlacementRequest(round, 1)
			invalid.OriginX = -1
			PlacementService.ValidateAndApply(round, 101, "station_01", invalid, 100)
			expectEqual(round.LastClientSequences.Place, -1)
			expect(
				PlacementService.ValidateAndApply(round, 101, "station_01", validPlacementRequest(round, 1), 100).Accepted,
				"Corrected request should be accepted with the unconsumed sequence"
			)
		end,
	},
})

type ScheduledTimer = {
	Duration: number,
	Callback: () -> (),
}

type Harness = {
	Player: Player,
	Service: any,
	ClockState: { Now: number },
	Snapshots: { any },
	ScheduledTimers: { ScheduledTimer },
	SpawnCount: { Value: number },
	ClearCount: { Value: number },
}

local function fakePlayer(userId: number): Player
	local characterAddedCallback: ((Model) -> ())? = nil
	local connection = {
		Disconnect = function()
			characterAddedCallback = nil
		end,
	}
	local signal = {
		Connect = function(_self, callback: (Model) -> ())
			characterAddedCallback = callback
			return connection
		end,
	}
	local player = {
		UserId = userId,
		Character = nil,
		CharacterAdded = signal,
		_FireCharacterAdded = function(_self, character: Model)
			local callback = characterAddedCallback
			if callback then
				callback(character)
			end
		end,
	}
	return (player :: any) :: Player
end

local function newHarness(userId: number?): Harness
	local player = fakePlayer(userId or 303)
	local clockState = { Now = 100 }
	local snapshots: { any } = {}
	local scheduledTimers: { ScheduledTimer } = {}
	local spawnCount = { Value = 0 }
	local clearCount = { Value = 0 }
	local station = ({
		GetStationId = function(_self, _player: Player): string?
			return "station_01"
		end,
	} :: any)
	local world = ({
		SpawnAcceptedPlacement = function(_self, _player: Player, _itemId: string, _placement: Placement): Model?
			spawnCount.Value += 1
			return nil
		end,
		ClearPlayer = function(_self, _player: Player)
			clearCount.Value += 1
		end,
	} :: any)
	local service = RoundService.Create(
		station,
		world,
		function(): number return clockState.Now end,
		function(duration: number, callback: () -> ())
			table.insert(scheduledTimers, { Duration = duration, Callback = callback })
		end,
		function(_player: Player, snapshot)
			table.insert(snapshots, snapshot)
		end
	)
	return {
		Player = player,
		Service = service,
		ClockState = clockState,
		Snapshots = snapshots,
		ScheduledTimers = scheduledTimers,
		SpawnCount = spawnCount,
		ClearCount = clearCount,
	}
end

local function takeScheduledTimer(harness: Harness, expectedDuration: number, message: string): ScheduledTimer
	local timer = table.remove(harness.ScheduledTimers, 1)
	expect(timer ~= nil, message .. " should schedule a timer")
	expectNear((timer :: ScheduledTimer).Duration, expectedDuration, 0.000001)
	return timer :: ScheduledTimer
end

local function startAwaiting(harness: Harness): RoundRecord
	local round = harness.Service:StartRound(harness.Player) :: RoundRecord
	expectEqual(round.State, "Preparing")
	local preparingTimer = takeScheduledTimer(
		harness,
		RoundConfig.INITIAL_PREPARING_DURATION,
		"Initial Preparing"
	)
	preparingTimer.Callback()
	expectEqual(round.State, "PresentingItem")
	local presentationTimer = takeScheduledTimer(harness, RoundConfig.PRESENTATION_DURATION, "PresentingItem")
	presentationTimer.Callback()
	expectEqual(round.State, "AwaitingPlacement")
	return round
end

local function acceptParcel(harness: Harness): RoundRecord
	local round = startAwaiting(harness)
	local result = harness.Service:HandlePlacement(harness.Player, validPlacementRequest(round, 1))
	expect(result.Accepted, "Parcel placement should pass")
	return round
end

addSuite("Round state", {
	{
		Name = "StartRound begins in Preparing",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			expectEqual(round.State, "Preparing")
			expectEqual(round.StateVersion, 0)
			expectEqual(round.PlacementDeadline, nil)
			expectEqual(round.DecisionDeadline, nil)
		end,
	},
	{
		Name = "Preparing snapshot is emitted",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			expectEqual(#harness.Snapshots, 1)
			expectEqual(harness.Snapshots[1].RoundId, round.RoundId)
			expectEqual(harness.Snapshots[1].StateVersion, 0)
			expectEqual(harness.Snapshots[1].State, "Preparing")
		end,
	},
	{
		Name = "initial Preparing timer reaches PresentingItem",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			local timer = takeScheduledTimer(
				harness,
				RoundConfig.INITIAL_PREPARING_DURATION,
				"Initial Preparing"
			)
			timer.Callback()
			expectEqual(round.State, "PresentingItem")
			expectEqual(round.StateVersion, 1)
			expectEqual(harness.Snapshots[#harness.Snapshots].State, "PresentingItem")
			takeScheduledTimer(harness, RoundConfig.PRESENTATION_DURATION, "PresentingItem")
		end,
	},
	{
		Name = "initial and restart preparation durations are distinct",
		Run = function()
			expect(
				RoundConfig.INITIAL_PREPARING_DURATION >= 0.10
					and RoundConfig.INITIAL_PREPARING_DURATION <= 0.15,
				"Initial preparation must stay within its approved timing window"
			)
			expect(
				RoundConfig.RESTART_PREPARING_DURATION >= 0.70
					and RoundConfig.RESTART_PREPARING_DURATION <= 0.75,
				"Restart preparation must stay within its approved timing window"
			)
			expect(
				RoundConfig.INITIAL_PREPARING_DURATION ~= RoundConfig.RESTART_PREPARING_DURATION,
				"Initial and restart preparation durations must be distinct"
			)
		end,
	},
	{
		Name = "restart Preparing timer reaches PresentingItem",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Decision")
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Shipping")
			table.clear(harness.ScheduledTimers)
			local accepted = harness.Service:HandleRestart(harness.Player, {
				RoundId = round.RoundId,
				StateVersion = round.StateVersion,
				ClientSequence = 1,
			})
			expect(accepted, "Restart should pass")
			local restarted = harness.Service:GetRound(harness.Player) :: RoundRecord
			expectEqual(restarted.State, "Preparing")
			expectEqual(harness.Snapshots[#harness.Snapshots].State, "Preparing")
			local timer = takeScheduledTimer(
				harness,
				RoundConfig.RESTART_PREPARING_DURATION,
				"Restart Preparing"
			)
			timer.Callback()
			expectEqual(restarted.State, "PresentingItem")
			expectEqual(restarted.StateVersion, 1)
		end,
	},
	{
		Name = "PresentingItem reaches AwaitingPlacement",
		Run = function() expectEqual(startAwaiting(newHarness()).State, "AwaitingPlacement") end,
	},
	{
		Name = "valid placement reaches Decision",
		Run = function() expectEqual(acceptParcel(newHarness()).State, "Decision") end,
	},
	{
		Name = "Ship reaches Shipping then Results",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			local accepted = harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "SHIP", ClientSequence = 1,
			})
			expect(accepted, "Ship should pass")
			expectEqual(round.State, "Shipping")
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Shipping")
			expectEqual(round.State, "Results")
		end,
	},
	{
		Name = "One More returns to item presentation",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			local accepted = harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "ONE_MORE", ClientSequence = 1,
			})
			expect(accepted, "One More should pass")
			expectEqual(round.State, "PresentingItem")
			expect(round.CurrentItemId ~= nil, "Next item should become current")
		end,
	},
	{
		Name = "placement timeout reaches Failing then Results",
		Run = function()
			local harness = newHarness()
			local round = startAwaiting(harness)
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "AwaitingPlacement")
			expectEqual(round.State, "Failing")
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Failing")
			expectEqual(round.State, "Results")
		end,
	},
	{
		Name = "decision timeout automatically ships",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Decision")
			expectEqual(round.State, "Shipping")
			expectEqual(round.ResultReason, "DECISION_TIMEOUT")
		end,
	},
	{
		Name = "invalid decision does not consume its sequence",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			local accepted, reason = harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "INVALID", ClientSequence = 1,
			})
			expect(not accepted, "Invalid choice should reject")
			expectEqual(reason, "INVALID_CHOICE")
			expectEqual(round.LastClientSequences.Decision, -1)
			local corrected = harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "SHIP", ClientSequence = 1,
			})
			expect(corrected, "Corrected decision should reuse the unconsumed sequence")
		end,
	},
	{
		Name = "expired decision does not consume its sequence",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			harness.ClockState.Now = (round.DecisionDeadline :: number) + 0.01
			local accepted, reason = harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "SHIP", ClientSequence = 1,
			})
			expect(not accepted, "Expired decision should reject")
			expectEqual(reason, "DECISION_EXPIRED")
			expectEqual(round.LastClientSequences.Decision, -1)
			expectEqual(round.State, "Decision")
		end,
	},
	{
		Name = "Pack Again creates a fresh RoundId",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Decision")
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Shipping")
			local oldId = round.RoundId
			local accepted = harness.Service:HandleRestart(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, ClientSequence = 1,
			})
			expect(accepted, "Restart should pass")
			expect((harness.Service:GetRound(harness.Player) :: RoundRecord).RoundId ~= oldId, "RoundId must change")
			expectEqual(harness.ClearCount.Value, 1)
		end,
	},
	{
		Name = "stale Preparing timer cannot affect a newer round",
		Run = function()
			local harness = newHarness()
			local oldRound = harness.Service:StartRound(harness.Player) :: RoundRecord
			local oldTimer = takeScheduledTimer(
				harness,
				RoundConfig.INITIAL_PREPARING_DURATION,
				"Initial Preparing"
			)
			local newerRound = harness.Service:StartRound(harness.Player, "RESTART") :: RoundRecord
			expect(newerRound.RoundId > oldRound.RoundId, "Fixture should create a newer round")
			oldTimer.Callback()
			expectEqual((harness.Service:GetRound(harness.Player) :: RoundRecord).RoundId, newerRound.RoundId)
			expectEqual(newerRound.State, "Preparing")
			expectEqual(newerRound.StateVersion, 0)
		end,
	},
	{
		Name = "stale delayed callbacks do nothing",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			expect(
				not harness.Service:HandleCapturedTimer(
					harness.Player,
					round.RoundId,
					round.StateVersion + 1,
					"Preparing"
				),
				"Mismatched StateVersion must reject"
			)
			expectEqual(round.State, "Preparing")
			expectEqual(round.StateVersion, 0)
		end,
	},
	{
		Name = "StateVersion increases on Preparing to PresentingItem",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			local before = round.StateVersion
			takeScheduledTimer(harness, RoundConfig.INITIAL_PREPARING_DURATION, "Initial Preparing").Callback()
			expect(round.StateVersion > before, "Version must increase")
			expectEqual(round.State, "PresentingItem")
		end,
	},
	{
		Name = "placement cannot succeed during Preparing",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			local result = harness.Service:HandlePlacement(harness.Player, validPlacementRequest(round, 1))
			expect(not result.Accepted, "Preparing placement must reject")
			expectEqual(result.Reason, "WRONG_STATE")
			expectEqual(round.State, "Preparing")
			expectEqual(round.Grid:GetOccupiedCellCount(), 0)
			expectEqual(harness.SpawnCount.Value, 0)
		end,
	},
	{
		Name = "session Tape survives a failed later round",
		Run = function()
			local harness = newHarness()
			local round = acceptParcel(harness)
			harness.Service:HandleDecision(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, Choice = "SHIP", ClientSequence = 1,
			})
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "Shipping")
			local bank = round.SessionBank
			harness.Service:HandleRestart(harness.Player, {
				RoundId = round.RoundId, StateVersion = round.StateVersion, ClientSequence = 1,
			})
			local later = harness.Service:GetRound(harness.Player) :: RoundRecord
			harness.Service:HandleCapturedTimer(harness.Player, later.RoundId, later.StateVersion, "Preparing")
			harness.Service:HandleCapturedTimer(harness.Player, later.RoundId, later.StateVersion, "PresentingItem")
			harness.Service:HandleCapturedTimer(harness.Player, later.RoundId, later.StateVersion, "AwaitingPlacement")
			expectEqual(later.SessionBank, bank)
		end,
	},
})

local function makeClientSnapshot(roundId: number, stateVersion: number): ClientSnapshot
	return {
		RoundId = roundId,
		StateVersion = stateVersion,
		State = "AwaitingPlacement",
		StationId = "station_01",
		CurrentItemId = "parcel",
		CurrentShapeId = "single_cube",
		NextItemId = nil,
		NextShapeId = nil,
		NextDifficulty = nil,
		OccupiedCells = { { X = 1, Y = 0, Z = 2 } },
		ItemCount = 1,
		BaseValueSum = 15,
		ShipmentValue = 15,
		PossibleNextShipmentValue = 0,
		CurrentMultiplier = 1,
		SessionBank = 0,
		PlacementDeadline = 130,
		DecisionDeadline = nil,
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
	}
end

addSuite("Client round store", {
	{
		Name = "older RoundId arriving late is rejected",
		Run = function()
			local store = ClientRoundStore.new()
			expect(store:ApplySnapshot(makeClientSnapshot(8, 4)), "Initial snapshot should apply")
			expect(
				not store:ApplySnapshot(makeClientSnapshot(7, 99)),
				"A lower RoundId must reject even when its StateVersion is higher"
			)
			local current = store:GetSnapshot() :: ClientSnapshot
			expectEqual(current.RoundId, 8)
			expectEqual(current.StateVersion, 4)
			store:Destroy()
		end,
	},
	{
		Name = "equal RoundId and equal StateVersion is rejected",
		Run = function()
			local store = ClientRoundStore.new()
			expect(store:ApplySnapshot(makeClientSnapshot(8, 4)), "Initial snapshot should apply")
			expect(
				not store:ApplySnapshot(makeClientSnapshot(8, 4)),
				"A duplicate StateVersion must reject"
			)
			local current = store:GetSnapshot() :: ClientSnapshot
			expectEqual(current.RoundId, 8)
			expectEqual(current.StateVersion, 4)
			store:Destroy()
		end,
	},
	{
		Name = "equal RoundId and lower StateVersion is rejected",
		Run = function()
			local store = ClientRoundStore.new()
			expect(store:ApplySnapshot(makeClientSnapshot(8, 4)), "Initial snapshot should apply")
			expect(
				not store:ApplySnapshot(makeClientSnapshot(8, 3)),
				"A lower StateVersion in the current round must reject"
			)
			local current = store:GetSnapshot() :: ClientSnapshot
			expectEqual(current.RoundId, 8)
			expectEqual(current.StateVersion, 4)
			store:Destroy()
		end,
	},
	{
		Name = "higher RoundId with reset StateVersion is accepted",
		Run = function()
			local store = ClientRoundStore.new()
			expect(store:ApplySnapshot(makeClientSnapshot(8, 12)), "Initial snapshot should apply")
			expect(
				store:ApplySnapshot(makeClientSnapshot(9, 0)),
				"A newer round must accept when its StateVersion restarts at zero"
			)
			local current = store:GetSnapshot() :: ClientSnapshot
			expectEqual(current.RoundId, 9)
			expectEqual(current.StateVersion, 0)
			store:Destroy()
		end,
	},
	{
		Name = "snapshot mutation remains isolated from stored data",
		Run = function()
			local store = ClientRoundStore.new()
			local source = makeClientSnapshot(8, 4)
			expect(store:ApplySnapshot(source), "Snapshot should apply")

			source.State = "Results"
			source.OccupiedCells[1].X = 4
			table.insert(source.OccupiedCells, { X = 3, Y = 2, Z = 1 })

			local current = store:GetSnapshot() :: ClientSnapshot
			expectEqual(current.State, "AwaitingPlacement")
			expectEqual(#current.OccupiedCells, 1)
			expectEqual(current.OccupiedCells[1].X, 1)
			expectEqual(current.OccupiedCells[1].Y, 0)
			expectEqual(current.OccupiedCells[1].Z, 2)
			store:Destroy()
		end,
	},
})

addSuite("Serialization", {
	{
		Name = "snapshot cells are independent from server grid",
		Run = function()
			local harness = newHarness()
			local round = startAwaiting(harness)
			local parcel = DevelopmentItemDefinitions.Get("parcel")
			expect(parcel ~= nil, "Parcel definition should exist")
			local rotation = ShapeRotation.GetUniqueRotations((parcel :: DevelopmentItemDefinitions.DevelopmentItemDefinition).Shape)[1]
			local placement = PlacementSolver.GetAutoDropPlacement(round.Grid, rotation, 0, 0, "single_cube", 1)
			expect(round.Grid:ApplyPlacement(placement :: Placement), "Fixture should apply")
			local snapshot = harness.Service:GetSnapshot(harness.Player)
			expect(snapshot ~= nil and #snapshot.OccupiedCells == 1, "Snapshot should contain copied cell")
			local resolved = snapshot :: any
			resolved.OccupiedCells[1].X = 4
			table.clear(resolved.OccupiedCells)
			expect(round.Grid:IsCellOccupied({ X = 0, Y = 0, Z = 0 }), "Server grid must remain unchanged")
		end,
	},
	{
		Name = "occupied cells serialize deterministically",
		Run = function()
			local harness = newHarness()
			local round = startAwaiting(harness)
			expect(round.Grid:ApplyPlacement(fixturePlacement({ { X = 2, Y = 0, Z = 1 }, { X = 0, Y = 1, Z = 4 } })), "Fixture should apply")
			local snapshot = harness.Service:GetSnapshot(harness.Player) :: any
			expectEqual(snapshot.OccupiedCells[1].X, 0)
			expectEqual(snapshot.OccupiedCells[2].X, 2)
		end,
	},
	{
		Name = "internal service references are not exposed",
		Run = function()
			local harness = newHarness()
			harness.Service:StartRound(harness.Player)
			local snapshot = harness.Service:GetSnapshot(harness.Player) :: any
			expectEqual(snapshot.Grid, nil)
			expectEqual(snapshot.Service, nil)
			expectEqual(snapshot.ValidPlacements, nil)
		end,
	},
})

addSuite("World transform", {
	{
		Name = "cell zero maps to GridOrigin",
		Run = function()
			local origin = CFrame.new(12, 4, -8) * CFrame.Angles(0, math.rad(35), 0)
			expectEqual(GridWorldTransform.CellToCFrame(origin, { X = 0, Y = 0, Z = 0 }, 2), origin)
		end,
	},
	{
		Name = "X increments by CellSize",
		Run = function()
			local position = GridWorldTransform.CellToWorldPosition(CFrame.new(), { X = 1, Y = 0, Z = 0 }, 2)
			expectNear(position.X, 2, 0.000001)
		end,
	},
	{
		Name = "Y increments by CellSize",
		Run = function()
			local position = GridWorldTransform.CellToWorldPosition(CFrame.new(), { X = 0, Y = 1, Z = 0 }, 2)
			expectNear(position.Y, 2, 0.000001)
		end,
	},
	{
		Name = "Z increments by CellSize",
		Run = function()
			local position = GridWorldTransform.CellToWorldPosition(CFrame.new(), { X = 0, Y = 0, Z = 1 }, 2)
			expectNear(position.Z, 2, 0.000001)
		end,
	},
	{
		Name = "transform remains deterministic",
		Run = function()
			local origin = CFrame.new(-4, 1, -4)
			local a = GridWorldTransform.CellToCFrame(origin, { X = 3, Y = 2, Z = 4 }, 2)
			local b = GridWorldTransform.CellToCFrame(origin, { X = 3, Y = 2, Z = 4 }, 2)
			expectEqual(a, b)
		end,
	},
})

local function makeStationsFixture(): (Folder, Model)
	local root = Instance.new("Folder")
	local station = Instance.new("Model")
	station.Name = "Station_01"
	station:SetAttribute("StationId", "station_01")
	station:SetAttribute("Active", true)
	local stand = Instance.new("Part")
	stand.Name = "PlayerStand"
	stand.Anchored = true
	stand.CFrame = CFrame.new(3, 5, 7)
	stand.Parent = station
	station.Parent = root
	return root, station
end

addSuite("Station assignment", {
	{
		Name = "first player receives Station 01",
		Run = function()
			local root = makeStationsFixture()
			local service = StationService.Create(root)
			local player = fakePlayer(1)
			expectEqual(service:AssignPlayer(player).StationId, "station_01")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "second simultaneous player cannot own Station 01",
		Run = function()
			local root = makeStationsFixture()
			local service = StationService.Create(root)
			local first = fakePlayer(1)
			local second = fakePlayer(2)
			expect(service:AssignPlayer(first).Assigned, "First assignment should pass")
			expectEqual(service:AssignPlayer(second).Reason, "NO_STATION")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "player removal releases Station 01",
		Run = function()
			local root = makeStationsFixture()
			local service = StationService.Create(root)
			local first = fakePlayer(1)
			local second = fakePlayer(2)
			service:AssignPlayer(first)
			service:ReleasePlayer(first)
			expect(service:AssignPlayer(second).Assigned, "Released station should be reusable")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "character respawn keeps assignment and rebinds to stand",
		Run = function()
			local root, station = makeStationsFixture()
			local service = StationService.Create(root)
			local player = fakePlayer(1)
			service:AssignPlayer(player)
			local character = Instance.new("Model")
			local rootPart = Instance.new("Part")
			rootPart.Name = "HumanoidRootPart"
			rootPart.Parent = character
			local testPlayer = player :: any
			testPlayer:_FireCharacterAdded(character)
			expectNear((rootPart.Position - (station.PlayerStand :: BasePart).Position).Magnitude, 0, 0.000001)
			expectEqual(service:GetStationId(player), "station_01")
			service:Destroy()
			character:Destroy()
			root:Destroy()
		end,
	},
})

addSuite("Rate limiting", {
	{
		Name = "rate-limited placement response preserves request correlation",
		Run = function()
			local round = makeRound()
			local request = validPlacementRequest(round, 42)
			local response = PlacementService.CreateResponse(
				round,
				false,
				"RATE_LIMITED",
				PlacementService.GetClientSequence(request)
			)
			expectEqual(response.ClientSequence, 42)
			expectEqual(response.RoundId, round.RoundId)
			expectEqual(response.StateVersion, round.StateVersion)
		end,
	},
	{
		Name = "configured request count is accepted within one second",
		Run = function()
			local limiter = RequestRateLimiter.Create()
			for _ = 1, 10 do
				expect(limiter:Check(1, "PlaceItemRequest", 5), "Allowed request should pass")
			end
		end,
	},
	{
		Name = "request beyond configured count is rejected",
		Run = function()
			local limiter = RequestRateLimiter.Create()
			for _ = 1, 10 do limiter:Check(1, "PlaceItemRequest", 5) end
			expect(not limiter:Check(1, "PlaceItemRequest", 5), "Eleventh placement request should reject")
		end,
	},
	{
		Name = "window recovers after one second",
		Run = function()
			local limiter = RequestRateLimiter.Create()
			limiter:Check(1, "ClientReadyRequest", 1)
			limiter:Check(1, "ClientReadyRequest", 1)
			expect(limiter:Check(1, "ClientReadyRequest", 2.01), "Expired requests should leave the window")
		end,
	},
})

type ClientMotionFixture = {
	Station: Model,
	RuntimePresentation: Folder,
	PlacedItems: Folder,
	PlacedBlock: BasePart,
	PresentationPoint: BasePart,
	Template: BasePart,
}

type PlacementCallbackLog = {
	ImpactCount: number,
	RejectedCount: number,
	AcceptedResponseCount: number,
}

type PendingPlacementFixture = {
	RoundId: number,
	ClientSequence: number,
	Cells: { ClientCell },
	ImpactPosition: Vector3,
	Heavy: boolean,
	ResponseReceived: boolean,
	SnapshotAccepted: boolean,
	VisualCompleted: boolean,
	DeferredSnapshot: ClientSnapshot?,
}

type InspectablePlacementController = PlacementController.Controller & {
	_pendingPlacement: PendingPlacementFixture?,
	_acceptedCorrelations: { [string]: boolean },
	_acceptedCorrelationOrder: { string },
	_ghost: Model?,
	_originX: number,
	_originZ: number,
	_rotationIndex: number,
}

local function makeClientMotionFixture(): ClientMotionFixture
	local station = Instance.new("Model")
	station.Name = "ClientMotionFixture"

	local crate = Instance.new("Folder")
	crate.Name = "Crate"
	crate.Parent = station

	local gridOrigin = Instance.new("Part")
	gridOrigin.Name = "GridOrigin"
	gridOrigin.Anchored = true
	gridOrigin.Size = Vector3.new(0.25, 0.25, 0.25)
	gridOrigin.CFrame = CFrame.new(0, 2, 0)
	gridOrigin.Parent = crate

	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Anchored = true
	lid.Size = Vector3.new(11, 0.5, 11)
	lid.CFrame = CFrame.new(0, 10.5, 0)
	lid.Color = Color3.fromRGB(22, 33, 44)
	lid:SetAttribute("ClosedOffsetY", 2)
	lid.Parent = crate

	local gridTiles = Instance.new("Folder")
	gridTiles.Name = "GridTiles"
	gridTiles.Parent = crate
	for x = 0, PresentationTokens.Grid.Width - 1 do
		for z = 0, PresentationTokens.Grid.Depth - 1 do
			local tile = Instance.new("Part")
			tile.Name = string.format("Cell_%d_%d", x, z)
			tile.Anchored = true
			tile.Size = Vector3.new(1.8, 0.1, 1.8)
			tile.CFrame = CFrame.new(x * PresentationTokens.Grid.CellSize, 1.8, z * PresentationTokens.Grid.CellSize)
			tile.Color = Color3.fromRGB(30, 43, 55)
			tile.Parent = gridTiles
		end
	end

	local controlConsole = Instance.new("Folder")
	controlConsole.Name = "ControlConsole"
	controlConsole.Parent = station
	for index, name in ipairs({ "RotateButton", "PlaceButton", "ShipButton", "OneMoreButton" }) do
		local button = Instance.new("Part")
		button.Name = name
		button.Anchored = true
		button.Size = Vector3.new(1.5, 0.5, 1.5)
		button.CFrame = CFrame.new((index - 1) * 2, 1, -3)
		button.Color = Color3.fromRGB(34, 211, 230)
		button.Material = Enum.Material.Metal
		button.Parent = controlConsole
	end

	local presentationPoint = Instance.new("Part")
	presentationPoint.Name = "PresentationPoint"
	presentationPoint.Anchored = true
	presentationPoint.Size = Vector3.new(3, 0.5, 3)
	presentationPoint.CFrame = CFrame.new(0, 7, -4)
	presentationPoint.Color = Color3.fromRGB(76, 89, 103)
	presentationPoint.Material = Enum.Material.Metal
	presentationPoint.Parent = station

	local placedItems = Instance.new("Folder")
	placedItems.Name = "PlacedItems"
	placedItems.Parent = station
	local placedBlock = Instance.new("Part")
	placedBlock.Name = "PlacedFixture"
	placedBlock.Anchored = true
	placedBlock.Size = Vector3.new(2, 2, 2)
	placedBlock.CFrame = CFrame.new(2, 3, 2)
	placedBlock.LocalTransparencyModifier = 0.35
	placedBlock.Parent = placedItems

	local runtimePresentation = Instance.new("Folder")
	runtimePresentation.Name = "RuntimePresentation"
	runtimePresentation.Parent = station

	local template = Instance.new("Part")
	template.Name = "DevelopmentItemTemplate"
	template.Anchored = true
	template.Size = Vector3.new(1.8, 1.8, 1.8)

	return {
		Station = station,
		RuntimePresentation = runtimePresentation,
		PlacedItems = placedItems,
		PlacedBlock = placedBlock,
		PresentationPoint = presentationPoint,
		Template = template,
	}
end

local function destroyClientMotionFixture(fixture: ClientMotionFixture)
	fixture.Template:Destroy()
	fixture.Station:Destroy()
end

local function countNamedChildren(parent: Instance, name: string): number
	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			count += 1
		end
	end
	return count
end

local function makePlacementCallbacks(log: PlacementCallbackLog): PlacementController.Callbacks
	return {
		FitChanged = function(_valid: boolean?, _x: number?, _y: number?, _z: number?) end,
		GridFeedback = function(_cells: { ClientCell }, _valid: boolean) end,
		ClearGridFeedback = function() end,
		ButtonPressed = function(_action: string) end,
		PlacementImpact = function(_position: Vector3, _heavy: boolean)
			log.ImpactCount += 1
		end,
		ServerResponse = function(_reason: string, accepted: boolean)
			if accepted then
				log.AcceptedResponseCount += 1
			end
		end,
		Rejected = function()
			log.RejectedCount += 1
		end,
		Observability = function(_valid: boolean?, _x: number?, _y: number?, _z: number?) end,
	}
end

local function makeMotionSnapshot(state: string, stateVersion: number, itemId: string?): ClientSnapshot
	local resolvedItemId = itemId or "parcel"
	local definition = DevelopmentItemDefinitions.Get(resolvedItemId)
	if definition == nil then
		error(string.format("Client motion fixture requires known item %s", resolvedItemId), 2)
	end
	local snapshot = makeClientSnapshot(21, stateVersion)
	snapshot.State = state
	snapshot.CurrentItemId = resolvedItemId
	snapshot.CurrentShapeId = definition.ShapeId
	snapshot.OccupiedCells = {}
	snapshot.ItemCount = 0
	snapshot.BaseValueSum = 0
	snapshot.ShipmentValue = 0
	return snapshot
end

local function newPlacementHarness(): (
	ClientMotionFixture,
	PlacementController.Controller,
	InspectablePlacementController,
	PlacementCallbackLog
)
	local fixture = makeClientMotionFixture()
	local log: PlacementCallbackLog = {
		ImpactCount = 0,
		RejectedCount = 0,
		AcceptedResponseCount = 0,
	}
	local placeItemRequest = Root:WaitForChild("Net"):WaitForChild("PlaceItemRequest")
	if not placeItemRequest:IsA("RemoteEvent") then
		error("Client motion fixture requires ONE_MORE_ITEM.Net.PlaceItemRequest RemoteEvent", 2)
	end
	local controller = PlacementController.new(
		placeItemRequest,
		fixture.Station,
		fixture.Template,
		makePlacementCallbacks(log)
	)
	local inspectable: InspectablePlacementController = controller :: any
	return fixture, controller, inspectable, log
end

local function injectPendingPlacement(controller: InspectablePlacementController, clientSequence: number)
	controller._pendingPlacement = {
		RoundId = 21,
		ClientSequence = clientSequence,
		Cells = { { X = 2, Y = 0, Z = 2 } },
		ImpactPosition = Vector3.new(4, 2, 4),
		Heavy = false,
		ResponseReceived = false,
		SnapshotAccepted = false,
		VisualCompleted = false,
		DeferredSnapshot = nil,
	}
end

local function acceptedPlacementResponse(clientSequence: number): ClientRoundStore.PlacementResponse
	return {
		Accepted = true,
		Reason = "ACCEPTED",
		ClientSequence = clientSequence,
		RoundId = 21,
		StateVersion = 2,
	}
end

local function rejectedPlacementResponse(clientSequence: number): ClientRoundStore.PlacementResponse
	return {
		Accepted = false,
		Reason = "NO_LEGAL_PLACEMENT",
		ClientSequence = clientSequence,
		RoundId = 21,
		StateVersion = 1,
	}
end

addSuite("Client motion cleanup", {
	{
		Name = "presentation and failure timings match the approved state windows",
		Run = function()
			expectNear(PresentationTokens.Timing.PresentationTravel, 0.35, 0.000001)
			expectNear(PresentationTokens.Timing.PresentationSettle, 0.06, 0.000001)
			expectNear(PresentationTokens.Timing.PresentationHold, 0.04, 0.000001)
			expectNear(
				PresentationTokens.Timing.PresentationTravel
					+ PresentationTokens.Timing.PresentationSettle
					+ PresentationTokens.Timing.PresentationHold,
				RoundConfig.PRESENTATION_DURATION,
				0.000001
			)
			expectNear(PresentationTokens.Timing.GhostRotate, 0.18, 0.000001)
			expectNear(PresentationTokens.Timing.GhostSettle, 0.08, 0.000001)
			expectNear(PresentationTokens.Timing.GhostAccepted, 0.10, 0.000001)
			expectNear(PresentationTokens.Timing.FailureBurst, 0.64, 0.000001)
			expect(
				PresentationTokens.Timing.Quick
					+ PresentationTokens.Timing.FailureImpactPause
					+ PresentationTokens.Timing.FailureBurst
				<= RoundConfig.FAILURE_PRESENTATION_DURATION,
				"Failed close, impact pause, and burst must finish before Results"
			)
		end,
	},
	{
		Name = "repeated PresentingItem replacement owns at most one presentation",
		Run = function()
			local fixture, controller = newPlacementHarness()
			for index = 1, 10 do
				local itemId = if index % 2 == 0 then "parcel" else "long_package"
				controller:ApplySnapshot(makeMotionSnapshot("PresentingItem", index, itemId))
				expectEqual(
					countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"),
					1,
					"Every replacement must destroy the prior presentation before creating the next"
				)
			end
			controller:Destroy()
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "leaving PresentingItem clears presentation and restores its authored point",
		Run = function()
			local fixture, controller = newPlacementHarness()
			local originalColor = fixture.PresentationPoint.Color
			local originalMaterial = fixture.PresentationPoint.Material
			controller:ApplySnapshot(makeMotionSnapshot("PresentingItem", 1))
			expectEqual(fixture.PresentationPoint.Material, Enum.Material.Neon)
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"), 1)

			controller:ApplySnapshot(makeMotionSnapshot("Preparing", 2))
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"), 0)
			expectEqual(fixture.PresentationPoint.Color, originalColor)
			expectEqual(fixture.PresentationPoint.Material, originalMaterial)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "same-item next presentation resets placement origin and rotation",
		Run = function()
			local fixture, controller, inspectable = newPlacementHarness()
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1, "parcel"))
			inspectable._originX = 4
			inspectable._originZ = 0
			inspectable._rotationIndex = 3
			controller:ApplySnapshot(makeMotionSnapshot("Decision", 2, "parcel"))
			controller:ApplySnapshot(makeMotionSnapshot("PresentingItem", 3, "parcel"))

			expectEqual(inspectable._originX, 2)
			expectEqual(inspectable._originZ, 2)
			expectEqual(inspectable._rotationIndex, 1)
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"), 1)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "FailureBurst clears after Results and Preparing restores suppression",
		Run = function()
			local fixture = makeClientMotionFixture()
			local controller = WorldMotionController.new(fixture.Station)
			local originalTransparency = fixture.PlacedBlock.LocalTransparencyModifier

			controller:SetState("Failing", "AwaitingPlacement")
			local burst = fixture.RuntimePresentation:FindFirstChild("FailureBurst")
			expect(burst ~= nil and burst:IsA("Model"), "Failing must create a visible FailureBurst model")
			expectEqual((burst :: Model):GetAttribute("Deterministic"), true)
			expectEqual((burst :: Model):GetAttribute("BlockCount"), 1)
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, 1)

			controller:SetState("Results", "Failing")
			expectEqual(fixture.RuntimePresentation:FindFirstChild("FailureBurst"), nil)
			expectEqual(
				fixture.PlacedBlock.LocalTransparencyModifier,
				1,
				"Failed contents remain suppressed while the Results state is visible"
			)

			controller:SetState("Preparing", "Results")
			expectEqual(fixture.RuntimePresentation:FindFirstChild("FailureBurst"), nil)
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, originalTransparency)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "Preparing interrupts FailureBurst and restores local transparency",
		Run = function()
			local fixture = makeClientMotionFixture()
			local controller = WorldMotionController.new(fixture.Station)
			local originalTransparency = fixture.PlacedBlock.LocalTransparencyModifier
			controller:SetState("Failing", "AwaitingPlacement")
			expect(fixture.RuntimePresentation:FindFirstChild("FailureBurst") ~= nil, "Burst should begin synchronously")
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, 1)

			controller:SetState("Preparing", "Failing")
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, originalTransparency)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "failure capture clones placed contents and ghost before placement cleanup",
		Run = function()
			local fixture, placementController = newPlacementHarness()
			local worldController = WorldMotionController.new(fixture.Station)
			local originalTransparency = fixture.PlacedBlock.LocalTransparencyModifier
			placementController:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1))
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "LocalPlacementGhost"), 1)

			worldController:SetState("Failing", "AwaitingPlacement")
			local burst = fixture.RuntimePresentation:FindFirstChild("FailureBurst")
			expect(burst ~= nil and burst:IsA("Model"), "World failure motion must capture before ghost cleanup")
			expectEqual(
				(burst :: Model):GetAttribute("BlockCount"),
				2,
				"FailureBurst must include one placed block and the one-cell placement ghost"
			)

			placementController:ApplySnapshot(makeMotionSnapshot("Failing", 2))
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "LocalPlacementGhost"), 0)
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "FailureBurst"), 1)
			expectEqual(#(burst :: Model):GetChildren(), 2, "Captured burst clones must survive source cleanup")

			worldController:SetState("Preparing", "Failing")
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, originalTransparency)
			worldController:Destroy()
			placementController:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "ten presentation and failure reset cycles return to baseline",
		Run = function()
			local fixture, placementController = newPlacementHarness()
			local worldController = WorldMotionController.new(fixture.Station)
			local originalTransparency = fixture.PlacedBlock.LocalTransparencyModifier
			for index = 1, 10 do
				local version = (index - 1) * 2
				placementController:ApplySnapshot(makeMotionSnapshot("PresentingItem", version + 1))
				expectEqual(countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"), 1)
				placementController:ApplySnapshot(makeMotionSnapshot("Preparing", version + 2))
				expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)

				worldController:SetState("Failing", "AwaitingPlacement")
				expectEqual(countNamedChildren(fixture.RuntimePresentation, "FailureBurst"), 1)
				worldController:SetState("Preparing", "Failing")
				expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
				expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, originalTransparency)
			end

			task.wait(math.max(PresentationTokens.Timing.PresentationTravel, PresentationTokens.Timing.FailureImpactPause) + 0.08)
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0, "Stale delayed effects must not reappear")
			expectEqual(fixture.PlacedBlock.LocalTransparencyModifier, originalTransparency)
			worldController:Destroy()
			placementController:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "response first plus duplicate accepted snapshot completes once",
		Run = function()
			local fixture, controller, inspectable, log = newPlacementHarness()
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1))
			expect(inspectable._ghost ~= nil, "AwaitingPlacement should create a local ghost")
			injectPendingPlacement(inspectable, 41)

			controller:HandleResponse(acceptedPlacementResponse(41))
			controller:ApplySnapshot(makeMotionSnapshot("Decision", 2))
			controller:ApplySnapshot(makeMotionSnapshot("Decision", 3))
			task.wait(PresentationTokens.Timing.GhostAccepted + 0.06)

			expectEqual(log.ImpactCount, 1, "Accepted visual must impact exactly once")
			expectEqual(log.AcceptedResponseCount, 1)
			expectEqual(log.RejectedCount, 0)
			expectEqual(inspectable._pendingPlacement, nil, "Accepted response must release the request lock")
			expectEqual(inspectable._ghost, nil)
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "snapshot first retains delayed response correlation without locking",
		Run = function()
			local fixture, controller, inspectable, log = newPlacementHarness()
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1))
			injectPendingPlacement(inspectable, 42)
			controller:ApplySnapshot(makeMotionSnapshot("Decision", 2))
			controller:ApplySnapshot(makeMotionSnapshot("PresentingItem", 3, "long_package"))
			task.wait(PresentationTokens.Timing.GhostAccepted + 0.06)

			expectEqual(log.ImpactCount, 1)
			expectEqual(log.AcceptedResponseCount, 0)
			expectEqual(inspectable._pendingPlacement, nil, "Visual completion must not retain the request lock")
			expectEqual(
				inspectable._acceptedCorrelations["21:42"],
				true,
				"Delayed response correlation must remain after visual completion"
			)
			expectEqual(inspectable._ghost, nil)
			expectEqual(
				countNamedChildren(fixture.RuntimePresentation, "ItemPresentation"),
				1,
				"A fast next-item snapshot must start after the accepted snap completes"
			)
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 4, "long_package"))
			expect(inspectable._ghost ~= nil, "A later item must become placeable without waiting for the old response")
			expectEqual(inspectable._pendingPlacement, nil)
			expectEqual(
				inspectable._acceptedCorrelations["21:42"],
				true,
				"Starting the next item must preserve delayed correlation"
			)

			controller:HandleResponse(acceptedPlacementResponse(42))
			expectEqual(log.AcceptedResponseCount, 1)
			expectEqual(log.RejectedCount, 0)
			expectEqual(inspectable._acceptedCorrelations["21:42"], nil)
			expectEqual(#inspectable._acceptedCorrelationOrder, 0)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "rejected response clears its lock and restores the placement ghost",
		Run = function()
			local fixture, controller, inspectable, log = newPlacementHarness()
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1))
			expect(inspectable._ghost ~= nil, "AwaitingPlacement should create a local ghost")
			injectPendingPlacement(inspectable, 43)
			controller:HandleResponse(rejectedPlacementResponse(43))
			task.wait(PresentationTokens.Timing.GhostRejected + 0.06)

			expectEqual(log.ImpactCount, 0)
			expectEqual(log.AcceptedResponseCount, 0)
			expectEqual(log.RejectedCount, 1)
			expectEqual(inspectable._pendingPlacement, nil, "A rejected response must release the request lock")
			expect(inspectable._ghost ~= nil, "Rejection feedback must return to the live placement ghost")
			expectEqual(countNamedChildren(fixture.RuntimePresentation, "LocalPlacementGhost"), 1)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
	{
		Name = "non-accepted Failing snapshot never produces placement impact",
		Run = function()
			local fixture, controller, inspectable, log = newPlacementHarness()
			controller:ApplySnapshot(makeMotionSnapshot("AwaitingPlacement", 1))
			injectPendingPlacement(inspectable, 44)
			controller:ApplySnapshot(makeMotionSnapshot("Failing", 2))
			task.wait(PresentationTokens.Timing.GhostAccepted + 0.03)

			expectEqual(log.ImpactCount, 0)
			expectEqual(log.AcceptedResponseCount, 0)
			expectEqual(log.RejectedCount, 0)
			expectEqual(inspectable._pendingPlacement, nil)
			expectEqual(inspectable._ghost, nil)
			expectEqual(#fixture.RuntimePresentation:GetChildren(), 0)
			controller:Destroy()
			destroyClientMotionFixture(fixture)
		end,
	},
})

addSuite("Runtime cleanup", {
	{
		Name = "ghost replacement does not leak old parts",
		Run = function()
			local template = Instance.new("Part")
			local container = Instance.new("Folder")
			DevelopmentItemRenderer.RenderCells(template, container, "GhostA", { { X = 0, Y = 0, Z = 0 } }, CFrame.new(), 2, Color3.new(0, 1, 0), 0.5)
			DevelopmentItemRenderer.Clear(container)
			DevelopmentItemRenderer.RenderCells(template, container, "GhostB", { { X = 1, Y = 0, Z = 0 } }, CFrame.new(), 2, Color3.new(0, 1, 0), 0.5)
			expectEqual(#container:GetChildren(), 1)
			template:Destroy()
			container:Destroy()
		end,
	},
	{
		Name = "temporary ViewportFrame content clears",
		Run = function()
			local worldModel = Instance.new("WorldModel")
			Instance.new("Model", worldModel)
			Instance.new("Camera", worldModel)
			DevelopmentItemRenderer.Clear(worldModel)
			expectEqual(#worldModel:GetChildren(), 0)
			worldModel:Destroy()
		end,
	},
	{
		Name = "placed items clear on reset without persistent growth",
		Run = function()
			local root, station = makeStationsFixture()
			local crate = Instance.new("Folder")
			crate.Name = "Crate"
			crate.Parent = station
			local origin = Instance.new("Part")
			origin.Name = "GridOrigin"
			origin.Parent = crate
			local placed = Instance.new("Folder")
			placed.Name = "PlacedItems"
			placed.Parent = station
			local template = Instance.new("Part")
			local player = fakePlayer(6)
			local stationContract = ({ GetStationModel = function(_self, _player: Player): Model? return station end } :: any)
			local service = WorldItemService.Create(template, stationContract)
			for roundIndex = 1, 3 do
				service:SpawnAcceptedPlacement(player, "parcel", fixturePlacement({ { X = roundIndex, Y = 0, Z = 0 } }))
				expectEqual(service:GetRuntimeModelCount(player), 1)
				service:ClearPlayer(player)
				expectEqual(#placed:GetChildren(), 0)
			end
			template:Destroy()
			root:Destroy()
		end,
	},
})

function Phase02TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}

	print(string.format("[ONE_MORE_ITEM][Phase02Tests] Starting %d suites seed=%d", #suites, RoundConfig.DEVELOPMENT.TEST_SEED))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase02Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase02Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase02Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		RoundConfig.DEVELOPMENT.TEST_SEED
	))

	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase02Tests] FAILURE %d: %s", index, failure))
		end
	end

	return {
		Suites = #suites,
		Tests = totalTests,
		Passed = passed,
		Failed = failed,
		Failures = failures,
		DurationSeconds = duration,
		Seed = RoundConfig.DEVELOPMENT.TEST_SEED,
	}
end

return table.freeze(Phase02TestSuite)
