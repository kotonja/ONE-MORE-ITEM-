--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

type Harness = {
	Player: Player,
	Service: any,
	ClockState: { Now: number },
	Snapshots: { any },
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
		function(_duration: number, _callback: () -> ()) end,
		function(_player: Player, snapshot)
			table.insert(snapshots, snapshot)
		end
	)
	return {
		Player = player,
		Service = service,
		ClockState = clockState,
		Snapshots = snapshots,
		SpawnCount = spawnCount,
		ClearCount = clearCount,
	}
end

local function startAwaiting(harness: Harness): RoundRecord
	local round = harness.Service:StartRound(harness.Player) :: RoundRecord
	expectEqual(round.State, "PresentingItem")
	expect(harness.Service:HandleCapturedTimer(
		harness.Player,
		round.RoundId,
		round.StateVersion,
		"PresentingItem"
	), "Presentation timer should advance")
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
		Name = "Preparing reaches PresentingItem",
		Run = function()
			local harness = newHarness()
			expectEqual((harness.Service:StartRound(harness.Player) :: RoundRecord).State, "PresentingItem")
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
		Name = "stale delayed callbacks do nothing",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			local version = round.StateVersion
			expect(not harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, version + 1, "PresentingItem"), "Stale timer must reject")
			expectEqual(round.State, "PresentingItem")
		end,
	},
	{
		Name = "StateVersion strictly increases",
		Run = function()
			local harness = newHarness()
			local round = harness.Service:StartRound(harness.Player) :: RoundRecord
			local before = round.StateVersion
			harness.Service:HandleCapturedTimer(harness.Player, round.RoundId, round.StateVersion, "PresentingItem")
			expect(round.StateVersion > before, "Version must increase")
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
			harness.Service:HandleCapturedTimer(harness.Player, later.RoundId, later.StateVersion, "PresentingItem")
			harness.Service:HandleCapturedTimer(harness.Player, later.RoundId, later.StateVersion, "AwaitingPlacement")
			expectEqual(later.SessionBank, bank)
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
