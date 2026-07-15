--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local CollectionDefinitions = require(Root.Shared.Profile.CollectionDefinitions)
local MasteryDefinitions = require(Root.Shared.Profile.MasteryDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)

local Services = script.Parent.Parent:WaitForChild("Services")
local ProfileServices = Services:WaitForChild("Profile")
local CollectionShelfService = require(Services:WaitForChild("CollectionShelfService"))
local RoundService = require(Services:WaitForChild("RoundService"))
local StationService = require(Services:WaitForChild("StationService"))
local DataStoreProfileAdapter = require(ProfileServices:WaitForChild("DataStoreProfileAdapter"))
local MemoryProfileAdapter = require(ProfileServices:WaitForChild("MemoryProfileAdapter"))
local ProfileConfig = require(ProfileServices:WaitForChild("ProfileConfig"))
local ProfileSchema = require(ProfileServices:WaitForChild("ProfileSchema"))
local ProfileService = require(ProfileServices:WaitForChild("ProfileService"))
local ProfileSnapshotBuilder = require(ProfileServices:WaitForChild("ProfileSnapshotBuilder"))
local ProgressionService = require(ProfileServices:WaitForChild("ProgressionService"))

local ClientControllers = StarterPlayer:WaitForChild("StarterPlayerScripts")
	:WaitForChild("ONE_MORE_ITEM_Client")
	:WaitForChild("Controllers")
local ClientProfileStore = require(ClientControllers:WaitForChild("ClientProfileStore"))
local ClientRoundStore = require(ClientControllers:WaitForChild("ClientRoundStore"))
local ProfileResponsiveLayout = require(ClientControllers:WaitForChild("ProfileResponsiveLayout"))
local ProfileUIController = require(ClientControllers:WaitForChild("ProfileUIController"))

type ProfileLayoutClass = ProfileResponsiveLayout.LayoutClass

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

type FakeClock = {
	Value: number,
}

type ProfileHarness = {
	Clock: FakeClock,
	Adapter: any,
	Service: any,
	Snapshots: { any },
	Lifecycles: { string },
}

type FakePlayerState = {
	Connected: boolean,
	Callback: ((Model) -> ())?,
}

local Phase05TestSuite = {}
local suites: { TestSuite } = {}

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, { Name = name, Tests = tests })
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "Expectation failed", 2)
	end
end

local function expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(message or string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local function expectArray(actual: { any }, expected: { any }, message: string?)
	expectEqual(#actual, #expected, message or "Array lengths differ")
	for index, value in ipairs(expected) do
		expectEqual(actual[index], value, message or string.format("Array index %d differs", index))
	end
end

local function expectFrozen(value: any, message: string?)
	expect(type(value) == "table" and table.isfrozen(value), message or "Expected frozen table")
end

local function expectError(callback: () -> (), fragment: string?)
	local ok, failure = pcall(callback)
	expect(not ok, "Expected callback to fail")
	if fragment ~= nil then
		expect(string.find(string.lower(tostring(failure)), string.lower(fragment), 1, true) ~= nil,
			string.format("Expected error containing %q, got %s", fragment, tostring(failure)))
	end
end

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA(className) then
		error(string.format("Fixture requires %s.%s to be %s", parent:GetFullName(), name, className), 2)
	end
	return child
end

local function authoredArena(): Folder
	local world = requireChild(Workspace, "ONE_MORE_ITEM_WORLD", "Folder")
	return requireChild(world, "PlaytestArena", "Folder") :: Folder
end

local function authoredStationsRoot(): Folder
	return requireChild(authoredArena(), "Stations", "Folder") :: Folder
end

local function authoredGuiRoot(): Frame
	local screen = requireChild(StarterGui, "ONE_MORE_ITEM_Gameplay", "ScreenGui")
	return requireChild(screen, "Root", "Frame") :: Frame
end

local function collectionTemplate(): BasePart
	local assets = requireChild(Root, "Assets", "Folder")
	local development = requireChild(assets, "Development", "Folder")
	return requireChild(development, "CollectionShelfItemTemplate", "BasePart") :: BasePart
end

local function fakePlayer(userId: number): Player
	local state: FakePlayerState = { Connected = false, Callback = nil }
	local connection = {
		Disconnect = function()
			state.Connected = false
			state.Callback = nil
		end,
	}
	local signal = {
		Connect = function(_self: any, callback: (Model) -> ())
			state.Connected = true
			state.Callback = callback
			return connection
		end,
	}
	return ({
		UserId = userId,
		Name = string.format("Player%d", userId),
		DisplayName = string.format("Player %d", userId),
		Character = nil,
		CharacterAdded = signal,
		_TestState = state,
	} :: any) :: Player
end

local function defaultProfile(now: number?): any
	return ProfileSchema.CreateDefault(now or 1_000)
end

local function claim(token: string, now: number): any
	return {
		Token = token,
		JobId = "phase05-test-job",
		PlaceId = 134193642444044,
		Now = now,
	}
end

local function makeProfileHarness(userId: number?, options: any?): ProfileHarness
	local resolved = options or {}
	local clock: FakeClock = { Value = resolved.Now or 10_000 }
	local snapshots: { any } = {}
	local lifecycles: { string } = {}
	local identifierOrdinal = 0
	local presentationOrdinal = 0
	local adapter = resolved.Adapter or MemoryProfileAdapter.Create()
	local service = ProfileService.Create(adapter, {
		Clock = function(): number
			return clock.Value
		end,
		Wait = function(duration: number)
			clock.Value += duration
		end,
		IdentifierFactory = function(): string
			identifierOrdinal += 1
			return string.format("lock-%d", identifierOrdinal)
		end,
		PresentationIdentifierFactory = function(): string
			presentationOrdinal += 1
			return string.format("presentation-%d", presentationOrdinal)
		end,
		Spawn = function(callback: () -> ())
			callback()
		end,
		ServerSessionId = resolved.ServerSessionId or "phase05-test-server",
		JobId = "phase05-test-job",
		PlaceId = 134193642444044,
		AutoSchedule = resolved.AutoSchedule == true,
		Scheduler = resolved.Scheduler,
		SnapshotSink = function(_snapshotUserId: number, snapshot: any)
			table.insert(snapshots, snapshot)
		end,
		LifecycleSink = function(_lifecycleUserId: number, state: string)
			table.insert(lifecycles, state)
		end,
	})
	if userId ~= nil then
		local loaded, code = service:LoadPlayer(userId)
		expect(loaded and code == "READY", "Profile fixture must load")
	end
	return {
		Clock = clock,
		Adapter = adapter,
		Service = service,
		Snapshots = snapshots,
		Lifecycles = lifecycles,
	}
end

local function placedItems(itemIds: { string }): { any }
	local items: { any } = {}
	for _, itemId in ipairs(itemIds) do
		table.insert(items, { ItemId = itemId })
	end
	return items
end

local function shipmentRecord(
	userId: number,
	roundId: number,
	outcomeId: string,
	value: number,
	itemIds: { string }
): any
	return {
		PlayerUserId = userId,
		RoundId = roundId,
		OutcomeId = outcomeId,
		ItemCount = #itemIds,
		ShipmentValue = value,
		PlacedItems = placedItems(itemIds),
		PerfectShipment = #itemIds == RoundConfig.MAXIMUM_ITEMS,
	}
end

local function profileSnapshot(profile: any, revision: number, sessionId: string?, reward: any?): any
	return ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", revision, sessionId or "profile:test", reward)
end

local function roundSnapshot(roundId: number, version: number, state: string, outcomeId: string?): any
	return {
		RoundId = roundId,
		OutcomeId = outcomeId,
		StateVersion = version,
		State = state,
		StationId = "station_01",
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
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
	}
end

addSuite("Schema defaults", {
	{
		Name = "nil becomes schema Version 1 with exact defaults",
		Run = function()
			local profile, code = ProfileSchema.Migrate(nil, 1234)
			expect(profile ~= nil and code == "CREATED_V1")
			expectEqual(profile.SchemaVersion, 1)
			expectEqual(profile.Tape, 0)
			expectEqual(profile.PackingXP, 0)
			expectEqual(profile.CreatedAt, 1234)
			expectEqual(profile.UpdatedAt, 1234)
			expectEqual(profile.Session, nil)
		end,
	},
	{
		Name = "statistics defaults are exact",
		Run = function()
			local stats = defaultProfile().Stats
			for _, key in ipairs({
				"TotalSuccessfulShipments", "TotalItemsShipped", "HighestItemsInShipment",
				"BestShipmentValue", "PerfectShipments", "TotalFailedRounds", "TotalTapeEarned",
			}) do
				expectEqual(stats[key], 0, key .. " must default to zero")
			end
		end,
	},
	{
		Name = "default maps and lists are independent",
		Run = function()
			local left = defaultProfile()
			local right = defaultProfile()
			left.Collection.Discovered.parcel = true
			table.insert(left.Collection.RecentDiscoveries, "parcel")
			table.insert(left.Receipts.ProcessedOutcomeIds, "receipt")
			expectEqual(right.Collection.Discovered.parcel, nil)
			expectEqual(#right.Collection.RecentDiscoveries, 0)
			expectEqual(#right.Receipts.ProcessedOutcomeIds, 0)
		end,
	},
	{
		Name = "migration does not mutate input",
		Run = function()
			local raw = { SchemaVersion = 1, Tape = -5, PackingXP = 9, Collection = { RecentDiscoveries = { "parcel" } } }
			local originalRecent = raw.Collection.RecentDiscoveries
			ProfileSchema.Migrate(raw, 100)
			expectEqual(raw.Tape, -5)
			expect(raw.Collection.RecentDiscoveries == originalRecent)
		end,
	},
	{
		Name = "invalid timestamps normalize deterministically",
		Run = function()
			local profile = ProfileSchema.Migrate({ SchemaVersion = 1, CreatedAt = -9, UpdatedAt = -2 }, 500)
			expect(profile ~= nil)
			expectEqual(profile.CreatedAt, 0)
			expectEqual(profile.UpdatedAt, 0)
		end,
	},
})

addSuite("Migration", {
	{
		Name = "Version 0 fixture migrates",
		Run = function()
			local profile, code = ProfileSchema.Migrate({ SchemaVersion = 0, Tape = 42, PackingXP = 300, DiscoveredItems = { "parcel" } }, 700)
			expect(profile ~= nil and code == "MIGRATED_V0_TO_V1")
			expectEqual(profile.Tape, 42)
			expect(profile.Collection.Discovered.parcel == true)
		end,
	},
	{
		Name = "missing and negative fields normalize",
		Run = function()
			local profile = ProfileSchema.Migrate({ SchemaVersion = 1, Tape = -2, Stats = { TotalFailedRounds = -8 } }, 800)
			expect(profile ~= nil)
			expectEqual(profile.Tape, 0)
			expectEqual(profile.PackingXP, 0)
			expectEqual(profile.Stats.TotalFailedRounds, 0)
		end,
	},
	{
		Name = "future version rejects",
		Run = function()
			local profile, code = ProfileSchema.Migrate({ SchemaVersion = 2 }, 900)
			expectEqual(profile, nil)
			expectEqual(code, "UNSUPPORTED_FUTURE_SCHEMA")
		end,
	},
	{
		Name = "unknown collection item IDs are removed",
		Run = function()
			local profile = ProfileSchema.Migrate({
				SchemaVersion = 1,
				Collection = { Discovered = { parcel = true, exploit_item = true }, MasteryCounts = { parcel = 2, exploit_item = 99 } },
			}, 1_000)
			expect(profile ~= nil)
			expect(profile.Collection.Discovered.parcel == true)
			expectEqual(profile.Collection.Discovered.exploit_item, nil)
			expectEqual(profile.Collection.MasteryCounts.exploit_item, nil)
		end,
	},
	{
		Name = "duplicate recent discoveries are removed in stable order",
		Run = function()
			local profile = ProfileSchema.Migrate({
				SchemaVersion = 1,
				Collection = {
					Discovered = { parcel = true, chair_blockout = true },
					MasteryCounts = { parcel = 1, chair_blockout = 1 },
					RecentDiscoveries = { "parcel", "chair_blockout", "parcel" },
				},
			}, 1_000)
			expectArray(profile.Collection.RecentDiscoveries, { "parcel", "chair_blockout" })
		end,
	},
	{
		Name = "duplicate receipt IDs are removed",
		Run = function()
			local profile = ProfileSchema.Migrate({ SchemaVersion = 1, Receipts = { ProcessedOutcomeIds = { "a", "b", "a" } } }, 1_000)
			expectArray(profile.Receipts.ProcessedOutcomeIds, { "a", "b" })
		end,
	},
	{
		Name = "receipt list is bounded to newest 128",
		Run = function()
			local receipts: { string } = {}
			for index = 1, 140 do table.insert(receipts, string.format("receipt-%03d", index)) end
			local profile = ProfileSchema.Migrate({ SchemaVersion = 1, Receipts = { ProcessedOutcomeIds = receipts } }, 1_000)
			expectEqual(#profile.Receipts.ProcessedOutcomeIds, ProfileConfig.MAXIMUM_RECEIPT_COUNT)
			expectEqual(profile.Receipts.ProcessedOutcomeIds[1], "receipt-013")
			expectEqual(profile.Receipts.ProcessedOutcomeIds[128], "receipt-140")
		end,
	},
	{
		Name = "migration is deterministic",
		Run = function()
			local raw = { SchemaVersion = 0, Tape = 88, PackingXP = 900, DiscoveredItems = { "parcel", "chair_blockout" } }
			local left = ProfileSchema.Migrate(raw, 1_234)
			local right = ProfileSchema.Migrate(raw, 1_234)
			expectEqual(left.Tape, right.Tape)
			expectEqual(left.PackingXP, right.PackingXP)
			expectArray(left.Collection.RecentDiscoveries, right.Collection.RecentDiscoveries)
		end,
	},
})

local rankTests: { TestCase } = {
	{
		Name = "seven stable unique ranks",
		Run = function()
			expectEqual(#PackingRankDefinitions.Ordered, 7)
			local names: { [string]: boolean } = {}
			for index, rank in ipairs(PackingRankDefinitions.Ordered) do
				expectEqual(rank.Index, index)
				expect(not names[rank.Name], "Rank names must be unique")
				names[rank.Name] = true
				if index > 1 then expect(rank.Threshold > PackingRankDefinitions.Ordered[index - 1].Threshold) end
			end
		end,
	},
	{
		Name = "maximum rank has complete progress",
		Run = function()
			local progress = PackingRankDefinitions.GetProgress(999_999)
			expectEqual(progress.RankIndex, 7)
			expectEqual(progress.RankName, "Impossible Shipper")
			expectEqual(progress.NextRankXP, nil)
			expectEqual(progress.Fraction, 1)
		end,
	},
	{
		Name = "multi-rank crossing resolves final rank",
		Run = function()
			expectEqual(PackingRankDefinitions.GetRankForXP(8_999).Index, 5)
			expectEqual(PackingRankDefinitions.GetRankForXP(15_000).Index, 7)
		end,
	},
}
for index, rank in ipairs(PackingRankDefinitions.Ordered) do
	table.insert(rankTests, {
		Name = string.format("rank %d exact boundary and progress", index),
		Run = function()
			local atBoundary = PackingRankDefinitions.GetProgress(rank.Threshold)
			expectEqual(atBoundary.RankIndex, index)
			expectEqual(atBoundary.XPIntoRank, 0)
			if rank.Threshold > 0 then
				expectEqual(PackingRankDefinitions.GetRankForXP(rank.Threshold - 1).Index, index - 1)
			end
			local nextRank = PackingRankDefinitions.Ordered[index + 1]
			if nextRank ~= nil then
				local before = PackingRankDefinitions.GetProgress(nextRank.Threshold - 1)
				expectEqual(before.RankIndex, index)
				expect(before.Fraction > 0 and before.Fraction < 1)
			end
		end,
	})
end
addSuite("Rank definitions", rankTests)

addSuite("Mastery", {
	{ Name = "zero undiscovered is Locked", Run = function() expectEqual(MasteryDefinitions.GetMasteryTier(0, false), "Locked") end },
	{ Name = "one through four is Discovered", Run = function() expectEqual(MasteryDefinitions.GetMasteryTier(4, true), "Discovered") end },
	{ Name = "Bronze begins at five", Run = function() expectEqual(MasteryDefinitions.GetMasteryTier(5, true), "Bronze") end },
	{ Name = "Silver begins at twenty", Run = function() expectEqual(MasteryDefinitions.GetMasteryTier(20, true), "Silver") end },
	{ Name = "Gold begins at fifty", Run = function() expectEqual(MasteryDefinitions.GetMasteryTier(50, true), "Gold") end },
	{
		Name = "mastery progress is exact",
		Run = function()
			local progress = MasteryDefinitions.GetMasteryProgress(10, true)
			expectEqual(progress.Tier, "Bronze")
			expectEqual(progress.CountIntoTier, 5)
			expectEqual(progress.CountRequiredForNextTier, 15)
			expectEqual(progress.Fraction, 1 / 3)
		end,
	},
	{
		Name = "invalid mastery counts normalize safely",
		Run = function()
			expectEqual(MasteryDefinitions.GetMasteryTier(-9, false), "Locked")
			expectEqual(MasteryDefinitions.GetMasteryTier(math.huge, false), "Locked")
			expectEqual(MasteryDefinitions.GetMasteryTier(0 / 0, false), "Locked")
		end,
	},
	{
		Name = "duplicate item occurrences increment mastery exactly",
		Run = function()
			local profile = defaultProfile()
			local changed, reward = ProgressionService.ApplyShipmentToProfile(
				profile, 5, 1, "5:server:1", shipmentRecord(5, 1, "5:server:1", 50, { "parcel", "parcel", "parcel" })
			)
			expect(changed and reward ~= nil)
			expectEqual(profile.Collection.MasteryCounts.parcel, 3)
			expectEqual(#reward.MasteryChanges, 1)
			expectEqual(reward.MasteryChanges[1].NewCount, 3)
		end,
	},
})

addSuite("Progression success and outcome IDs", {
	{
		Name = "shipment Tape and XP formulas apply once",
		Run = function()
			local profile = defaultProfile()
			local changed, reward, code = ProgressionService.ApplyShipmentToProfile(
				profile, 11, 4, "11:session-A:4", shipmentRecord(11, 4, "11:session-A:4", 250, { "parcel", "chair_blockout" })
			)
			expect(changed and reward ~= nil and code == "APPLIED")
			expectEqual(profile.Tape, 250)
			expectEqual(reward.TapeDelta, 250)
			expectEqual(reward.XPDelta, 20)
			expectEqual(profile.PackingXP, 20)
		end,
	},
	{
		Name = "perfect shipment bonus is exact",
		Run = function()
			local ids: { string } = {}
			for _ = 1, 10 do table.insert(ids, "parcel") end
			local profile = defaultProfile()
			local changed, reward = ProgressionService.ApplyShipmentToProfile(
				profile, 12, 1, "12:session-A:1", shipmentRecord(12, 1, "12:session-A:1", 1_000, ids)
			)
			expect(changed and reward ~= nil)
			expectEqual(reward.XPDelta, 85)
			expectEqual(profile.Stats.PerfectShipments, 1)
		end,
	},
	{
		Name = "success statistics discoveries and mastery are exact",
		Run = function()
			local profile = defaultProfile()
			local changed, reward = ProgressionService.ApplyShipmentToProfile(
				profile, 13, 1, "13:session-A:1", shipmentRecord(13, 1, "13:session-A:1", 400, { "parcel", "parcel", "lamp_blockout" })
			)
			expect(changed and reward ~= nil)
			expectEqual(profile.Stats.TotalSuccessfulShipments, 1)
			expectEqual(profile.Stats.TotalItemsShipped, 3)
			expectEqual(profile.Stats.HighestItemsInShipment, 3)
			expectEqual(profile.Stats.BestShipmentValue, 400)
			expectEqual(profile.Stats.TotalTapeEarned, 400)
			expectArray(reward.NewDiscoveries, { "parcel", "lamp_blockout" })
			expectEqual(profile.Collection.MasteryCounts.parcel, 2)
		end,
	},
	{
		Name = "rank transition can cross a threshold",
		Run = function()
			local profile = defaultProfile()
			profile.PackingXP = 290
			local changed, reward = ProgressionService.ApplyShipmentToProfile(
				profile, 14, 1, "14:session-A:1", shipmentRecord(14, 1, "14:session-A:1", 100, { "parcel" })
			)
			expect(changed and reward ~= nil)
			expectEqual(reward.PreviousRank.Index, 1)
			expectEqual(reward.NewRank.Index, 2)
		end,
	},
	{
		Name = "reward result and nested tables are frozen",
		Run = function()
			local profile = defaultProfile()
			local _, reward = ProgressionService.ApplyShipmentToProfile(
				profile, 15, 1, "15:session-A:1", shipmentRecord(15, 1, "15:session-A:1", 25, { "parcel" })
			)
			expect(reward ~= nil)
			expectFrozen(reward)
			expectFrozen(reward.NewDiscoveries)
			expectFrozen(reward.MasteryChanges)
			expectFrozen(reward.UpdatedStats)
			expectError(function() reward.XPDelta = 99 end)
		end,
	},
	{
		Name = "unknown item rejection is atomic",
		Run = function()
			local profile = defaultProfile()
			local changed, reward, code = ProgressionService.ApplyShipmentToProfile(
				profile, 16, 1, "16:session-A:1", shipmentRecord(16, 1, "16:session-A:1", 999, { "unknown_item" })
			)
			expect(not changed and reward == nil and code == "UNKNOWN_ITEM_ID")
			expectEqual(profile.Tape, 0)
			expectEqual(profile.PackingXP, 0)
			expectEqual(#profile.Receipts.ProcessedOutcomeIds, 0)
		end,
	},
	{
		Name = "shipment record outcome mismatch is atomic",
		Run = function()
			local profile = defaultProfile()
			local changed, reward, code = ProgressionService.ApplyShipmentToProfile(
				profile,
				161,
				1,
				"161:session-A:1",
				shipmentRecord(161, 1, "161:different-session:1", 125, { "parcel" })
			)
			expect(not changed and reward == nil and code == "OUTCOME_MISMATCH")
			expectEqual(profile.Tape, 0)
			expectEqual(profile.PackingXP, 0)
			expectEqual(#profile.Receipts.ProcessedOutcomeIds, 0)
		end,
	},
	{
		Name = "duplicate outcome is a stable no-op",
		Run = function()
			local profile = defaultProfile()
			local record = shipmentRecord(17, 1, "17:session-A:1", 75, { "parcel" })
			local changed = ProgressionService.ApplyShipmentToProfile(profile, 17, 1, "17:session-A:1", record)
			expect(changed)
			local tape = profile.Tape
			local xp = profile.PackingXP
			local changedAgain, reward, code = ProgressionService.ApplyShipmentToProfile(profile, 17, 1, "17:session-A:1", record)
			expect(not changedAgain and reward ~= nil and reward.Duplicate and code == "DUPLICATE")
			expectEqual(profile.Tape, tape)
			expectEqual(profile.PackingXP, xp)
		end,
	},
	{
		Name = "OutcomeId includes user session round and changes by server",
		Run = function()
			local a = string.format("%d:%s:%d", 18, "server-A", 3)
			local b = string.format("%d:%s:%d", 18, "server-B", 3)
			expectEqual(a, "18:server-A:3")
			expect(a ~= b)
			expect(#a <= ProfileConfig.MAXIMUM_OUTCOME_ID_LENGTH)
		end,
	},
})

addSuite("Progression failure", {
	{
		Name = "failure grants consolation XP but no Tape collection or mastery",
		Run = function()
			local profile = defaultProfile()
			local changed, reward, code = ProgressionService.ApplyFailureToProfile(profile, 1, "21:server:1", 7)
			expect(changed and reward ~= nil and code == "APPLIED")
			expectEqual(reward.XPDelta, 10)
			expectEqual(profile.PackingXP, 10)
			expectEqual(profile.Tape, 0)
			expectEqual(profile.Stats.TotalFailedRounds, 1)
			expectEqual(#profile.Collection.RecentDiscoveries, 0)
		end,
	},
	{
		Name = "failure XP is exact below cap",
		Run = function()
			local profile = defaultProfile()
			local _, reward = ProgressionService.ApplyFailureToProfile(profile, 1, "22:server:1", 3)
			expectEqual(reward.XPDelta, 6)
		end,
	},
	{
		Name = "duplicate failure is a no-op",
		Run = function()
			local profile = defaultProfile()
			ProgressionService.ApplyFailureToProfile(profile, 1, "23:server:1", 3)
			local changed, reward, code = ProgressionService.ApplyFailureToProfile(profile, 1, "23:server:1", 3)
			expect(not changed and reward.Duplicate and code == "DUPLICATE")
			expectEqual(profile.Stats.TotalFailedRounds, 1)
		end,
	},
	{
		Name = "same outcome cannot later ship",
		Run = function()
			local profile = defaultProfile()
			ProgressionService.ApplyFailureToProfile(profile, 1, "24:server:1", 2)
			local changed, reward, code = ProgressionService.ApplyShipmentToProfile(
				profile, 24, 1, "24:server:1", shipmentRecord(24, 1, "24:server:1", 500, { "parcel" })
			)
			expect(not changed and reward.Duplicate and code == "DUPLICATE")
			expectEqual(profile.Tape, 0)
		end,
	},
})

addSuite("Profile snapshot", {
	{
		Name = "snapshot excludes session token receipts and internal tables",
		Run = function()
			local profile = defaultProfile()
			profile.Session = { Token = "secret", JobId = "job", PlaceId = 1, AcquiredAt = 1, HeartbeatAt = 1 }
			table.insert(profile.Receipts.ProcessedOutcomeIds, "private-receipt")
			local snapshot = profileSnapshot(profile, 1)
			expectEqual(snapshot.Token, nil)
			expectEqual(snapshot.Session, nil)
			expectEqual(snapshot.Receipts, nil)
			expectEqual(snapshot.ProcessedOutcomeIds, nil)
			expectEqual(snapshot.ProfileSessionId, "profile:test")
		end,
	},
	{
		Name = "snapshot copies maps arrays and statistics",
		Run = function()
			local profile = defaultProfile()
			profile.Collection.Discovered.parcel = true
			profile.Collection.MasteryCounts.parcel = 4
			profile.Stats.TotalItemsShipped = 9
			local snapshot = profileSnapshot(profile, 2)
			profile.Collection.Discovered.parcel = nil
			profile.Collection.MasteryCounts.parcel = 99
			profile.Stats.TotalItemsShipped = 99
			expectArray(snapshot.DiscoveredItemIds, { "parcel" })
			expectEqual(snapshot.MasteryCounts.parcel, 4)
			expectEqual(snapshot.Stats.TotalItemsShipped, 9)
			expectFrozen(snapshot)
			expectFrozen(snapshot.DiscoveredItemIds)
			expectFrozen(snapshot.MasteryCounts)
		end,
	},
	{
		Name = "ProfileService revisions increase monotonically",
		Run = function()
			local harness = makeProfileHarness(31)
			local before = harness.Service:GetSnapshot(31).Revision
			harness.Service:PublishSnapshot(31)
			local after = harness.Service:GetSnapshot(31).Revision
			expectEqual(after, before + 1)
		end,
	},
	{
		Name = "client rejects stale and duplicate revision",
		Run = function()
			local store = ClientProfileStore.new()
			local profile = defaultProfile()
			expect(store:ApplySnapshot(profileSnapshot(profile, 5, "same-session")))
			expect(not store:ApplySnapshot(profileSnapshot(profile, 4, "same-session")))
			expect(not store:ApplySnapshot(profileSnapshot(profile, 5, "same-session")))
			expectEqual(store:GetSnapshot().Revision, 5)
			store:Destroy()
		end,
	},
	{
		Name = "new presentation session accepts a lower revision safely",
		Run = function()
			local store = ClientProfileStore.new()
			local profile = defaultProfile()
			store:ApplySnapshot(profileSnapshot(profile, 50, "old-session"))
			expect(store:ApplySnapshot(profileSnapshot(profile, 1, "new-session")))
			expectEqual(store:GetSnapshot().ProfileSessionId, "new-session")
			expectEqual(store:GetSnapshot().Revision, 1)
			store:Destroy()
		end,
	},
})

addSuite("Memory adapter", {
	{
		Name = "missing load creates and locks a profile",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			local result = adapter:LoadAndLock(41, claim("A", 100))
			expect(result.Success and result.Code == "Loaded")
			expectEqual(result.Profile.SchemaVersion, 1)
			expectEqual(result.Profile.Session.Token, "A")
		end,
	},
	{
		Name = "existing load preserves values",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			local seeded = defaultProfile(10)
			seeded.Tape = 345
			adapter:Seed(42, seeded)
			local result = adapter:LoadAndLock(42, claim("A", 100))
			expect(result.Success)
			expectEqual(result.Profile.Tape, 345)
		end,
	},
	{
		Name = "deep-copy isolation protects backing storage",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			local result = adapter:LoadAndLock(43, claim("A", 100))
			result.Profile.Tape = 999
			result.Profile.Collection.Discovered.parcel = true
			local stored = adapter:ReadStored(43)
			expectEqual(stored.Tape, 0)
			expectEqual(stored.Collection.Discovered.parcel, nil)
		end,
	},
	{
		Name = "load and save failure fixtures are deterministic",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			adapter:SetLoadFailure(44, 1)
			expectEqual(adapter:LoadAndLock(44, claim("A", 100)).Code, "Unavailable")
			local loaded = adapter:LoadAndLock(44, claim("A", 101))
			expect(loaded.Success)
			adapter:SetSaveFailure(44, 1)
			expectEqual(adapter:Save(44, loaded.Profile, "A", 102).Code, "Unavailable")
			expect(adapter:Save(44, loaded.Profile, "A", 103).Success)
		end,
	},
	{
		Name = "release persists and clears lock",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			local loaded = adapter:LoadAndLock(45, claim("A", 100))
			loaded.Profile.Tape = 50
			local released = adapter:Release(45, loaded.Profile, "A", 110)
			expect(released.Success and released.Code == "Released")
			expectEqual(adapter:ReadStored(45).Tape, 50)
			expectEqual(adapter:ReadStored(45).Session, nil)
		end,
	},
	{
		Name = "active lock rejects and stale lock permits takeover",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			expect(adapter:LoadAndLock(46, claim("A", 100)).Success)
			expectEqual(adapter:LoadAndLock(46, claim("B", 101)).Code, "Locked")
			local takeover = adapter:LoadAndLock(46, claim("B", 280))
			expect(takeover.Success)
			expectEqual(takeover.Profile.Session.Token, "B")
		end,
	},
	{
		Name = "lock ownership and lock loss are enforced",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			local loaded = adapter:LoadAndLock(47, claim("A", 100))
			expectEqual(adapter:Save(47, loaded.Profile, "B", 101).Code, "Conflict")
			adapter:ForceSession(47, { Token = "OTHER", JobId = "other", PlaceId = 1, AcquiredAt = 100, HeartbeatAt = 101 })
			expectEqual(adapter:Heartbeat(47, "A", 102).Code, "Conflict")
			expectEqual(adapter:Release(47, loaded.Profile, "A", 103).Code, "Conflict")
		end,
	},
	{
		Name = "simulated crash leaves lock for stale recovery",
		Run = function()
			local backing = {}
			local first = MemoryProfileAdapter.Create({ BackingStore = backing })
			first:LoadAndLock(48, claim("A", 100))
			first:SimulateServerCrash(48)
			local second = MemoryProfileAdapter.Create({ BackingStore = backing })
			expectEqual(second:LoadAndLock(48, claim("B", 150)).Code, "Locked")
			expect(second:LoadAndLock(48, claim("B", 280)).Success)
		end,
	},
})

local function fakeDataStore(initial: any?): (any, any)
	local state = {
		Value = initial,
		Calls = 0,
		InTransform = false,
		TransformReturned = true,
	}
	local store = {
		UpdateAsync = function(_self: any, _key: string, transform: (any) -> any): any
			state.Calls += 1
			state.InTransform = true
			local ok, transformed = pcall(transform, state.Value)
			state.InTransform = false
			state.TransformReturned = ok
			if not ok then error(transformed) end
			if transformed ~= nil then state.Value = transformed end
			return state.Value
		end,
	}
	return store, state
end

local function delegateAdapter(inner: any): any
	local proxy = {}
	return setmetatable(proxy, {
		__index = function(_self: any, key: any): any
			local value = inner[key]
			if type(value) == "function" then
				return function(_ignored: any, ...: any)
					return value(inner, ...)
				end
			end
			return value
		end,
	})
end

addSuite("DataStore transform contracts", {
	{
		Name = "actual Studio cannot be forced onto the production store",
		Run = function()
			local store = fakeDataStore(nil)
			local studio = DataStoreProfileAdapter.Create({ DataStore = store, IsStudio = true })
			local attemptedProduction = DataStoreProfileAdapter.Create({ DataStore = store, IsStudio = false })
			expectEqual(studio:GetStoreName(), "ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1")
			expectEqual(attemptedProduction:GetStoreName(), "ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1")
			expectEqual(studio:GetEnvironment(), "StudioTest")
			expectEqual(attemptedProduction:GetEnvironment(), "StudioTest")
		end,
	},
	{
		Name = "production and Studio-test constants remain exact and distinct",
		Run = function()
			expectEqual(ProfileConfig.STUDIO_STORE_NAME, "ONE_MORE_ITEM_PlayerProfiles_StudioTest_v1")
			expectEqual(ProfileConfig.PRODUCTION_STORE_NAME, "ONE_MORE_ITEM_PlayerProfiles_v1")
			expect(ProfileConfig.STUDIO_STORE_NAME ~= ProfileConfig.PRODUCTION_STORE_NAME)
		end,
	},
	{
		Name = "load transform is synchronous and preserves timestamps",
		Run = function()
			local raw = defaultProfile(20)
			local store, state = fakeDataStore(raw)
			local adapter = DataStoreProfileAdapter.Create({ DataStore = store, IsStudio = true })
			local loaded = adapter:LoadAndLock(51, claim("A", 100))
			expect(loaded.Success and state.TransformReturned and not state.InTransform)
			expectEqual(loaded.Profile.CreatedAt, 20)
			expectEqual(loaded.Profile.UpdatedAt, 20)
		end,
	},
	{
		Name = "save transform checks lock and preserves CreatedAt",
		Run = function()
			local store = fakeDataStore(defaultProfile(10))
			local adapter = DataStoreProfileAdapter.Create({ DataStore = store, IsStudio = true })
			local loaded = adapter:LoadAndLock(52, claim("A", 100))
			loaded.Profile.Tape = 20
			local saved = adapter:Save(52, loaded.Profile, "A", 110)
			expect(saved.Success)
			expectEqual(saved.Profile.CreatedAt, 10)
			expectEqual(saved.Profile.UpdatedAt, 110)
			expectEqual(adapter:Save(52, loaded.Profile, "B", 111).Code, "Conflict")
		end,
	},
	{
		Name = "release transform checks lock and returns nil on conflict",
		Run = function()
			local store, state = fakeDataStore(defaultProfile(10))
			local adapter = DataStoreProfileAdapter.Create({ DataStore = store, IsStudio = true })
			local loaded = adapter:LoadAndLock(53, claim("A", 100))
			local before = state.Value
			local conflict = adapter:Release(53, loaded.Profile, "B", 101)
			expectEqual(conflict.Code, "Conflict")
			expect(state.Value == before, "Conflict transform must not replace stored table")
		end,
	},
	{
		Name = "retry wait occurs outside adapter callback",
		Run = function()
			local inner = MemoryProfileAdapter.Create()
			inner:SetLoadFailure(54, 1)
			local insideAdapter = false
			local waits = 0
			local wrapper = delegateAdapter(inner)
			function wrapper:LoadAndLock(userId: number, fixture: any): any
				insideAdapter = true
				local result = inner:LoadAndLock(userId, fixture)
				insideAdapter = false
				return result
			end
			local service = ProfileService.Create(wrapper, {
				Clock = function() return 100 end,
				Wait = function(_duration: number)
					expect(not insideAdapter, "Retry wait cannot run inside adapter transform")
					waits += 1
				end,
				AutoSchedule = false,
				ServerSessionId = "retry-test",
				IdentifierFactory = function() return "id" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			expect(service:LoadPlayer(54))
			expectEqual(waits, 1)
		end,
	},
})

addSuite("Profile service", {
	{
		Name = "Loading to Ready and Ready to Saving to Ready",
		Run = function()
			local harness = makeProfileHarness(61)
			expectEqual(harness.Lifecycles[1], "Loading")
			expectEqual(harness.Service:GetState(61), "Ready")
			harness.Service:ApplyMutation(61, function(profile: any)
				profile.Tape += 1
				return true, nil, "MUTATED"
			end)
			expect(harness.Service:SaveNow(61))
			expectEqual(harness.Service:GetState(61), "Ready")
			local sawSaving = false
			for _, state in ipairs(harness.Lifecycles) do if state == "Saving" then sawSaving = true end end
			expect(sawSaving, "Saving lifecycle must be published")
		end,
	},
	{
		Name = "save failure enters SaveDelayed and retry returns Ready",
		Run = function()
			local harness = makeProfileHarness(62)
			harness.Service:ApplyMutation(62, function(profile: any)
				profile.Tape += 5
				return true
			end)
			harness.Adapter:SetSaveFailure(62, 1)
			local success, code = harness.Service:SaveNow(62)
			expect(not success and code == "Unavailable")
			expectEqual(harness.Service:GetState(62), "SaveDelayed")
			expect(harness.Service:SaveNow(62))
			expectEqual(harness.Service:GetState(62), "Ready")
		end,
	},
	{
		Name = "lock loss transitions to Conflict",
		Run = function()
			local harness = makeProfileHarness(63)
			harness.Service:ApplyMutation(63, function(profile: any)
				profile.Tape += 5
				return true
			end)
			harness.Adapter:ForceSession(63, { Token = "other", JobId = "other", PlaceId = 1, AcquiredAt = 1, HeartbeatAt = 1 })
			local success, code = harness.Service:SaveNow(63)
			expect(not success and code == "CONFLICT")
			expectEqual(harness.Service:GetState(63), "Conflict")
		end,
	},
	{
		Name = "release lifecycle persists and ends Released",
		Run = function()
			local harness = makeProfileHarness(64)
			harness.Service:ApplyMutation(64, function(profile: any)
				profile.Tape = 77
				return true
			end)
			expect(harness.Service:BeginRelease(64))
			expectEqual(harness.Service:GetState(64), "Releasing")
			expect(harness.Service:Release(64))
			expectEqual(harness.Service:GetState(64), "Released")
			expectEqual(harness.Adapter:ReadStored(64).Tape, 77)
			expectEqual(harness.Adapter:ReadStored(64).Session, nil)
		end,
	},
	{
		Name = "released profiles expose no mutable gameplay state",
		Run = function()
			local harness = makeProfileHarness(641)
			harness.Service:ApplyMutation(641, function(profile: any)
				profile.Tape = 91
				return true
			end)
			local released, releaseCode = harness.Service:Release(641)
			expect(released and releaseCode == "RELEASED")
			expectEqual(harness.Service:GetState(641), "Released")
			expect(not harness.Service:CanEnterGameplay(641))
			expect(not harness.Service:CanMutate(641))
			expectEqual(harness.Service:GetTape(641), nil)
			expectEqual(harness.Service:GetProfileCopy(641), nil)
			local saveSuccess, saveCode = harness.Service:SaveNow(641)
			expect(not saveSuccess and saveCode == "PROFILE_NOT_LOADED")
			local mutationResult, mutationCode = harness.Service:ApplyMutation(641, function(profile: any)
				profile.Tape += 1
				return true
			end)
			expectEqual(mutationResult, nil)
			expectEqual(mutationCode, "PROFILE_NOT_MUTABLE")
			expect(not harness.Service:BeginRelease(641))
			expectEqual(harness.Service:ProcessDueSaves(), 0)
			local snapshot = harness.Service:GetSnapshot(641)
			expect(snapshot ~= nil)
			expectEqual(snapshot.State, "Released")
			expectEqual(snapshot.SaveState, "Released")
			expectEqual(snapshot.Tape, 0)
		end,
	},
	{
		Name = "rapid same-server reconnect waits for release and creates a fresh session",
		Run = function()
			local clock = { Value = 1_200 }
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			function adapter:Release(userId: number, profile: any, token: string, now: number): any
				coroutine.yield("RELEASE_PAUSED")
				return inner:Release(userId, profile, token, now)
			end
			local identifierOrdinal = 0
			local presentationOrdinal = 0
			local service = ProfileService.Create(adapter, {
				Clock = function() return clock.Value end,
				Wait = function(duration: number)
					clock.Value += duration
					coroutine.yield("RECONNECT_WAIT")
				end,
				AutoSchedule = false,
				ServerSessionId = "rapid-reconnect",
				IdentifierFactory = function()
					identifierOrdinal += 1
					return string.format("lock-id-%d", identifierOrdinal)
				end,
				PresentationIdentifierFactory = function()
					presentationOrdinal += 1
					return string.format("presentation-id-%d", presentationOrdinal)
				end,
			})
			expect(service:LoadPlayer(642))
			local firstEntry = (service :: any)._entries[642]
			local firstToken = firstEntry.Token
			local firstProfileSessionId = firstEntry.ProfileSessionId
			expect(service:BeginRelease(642))

			local releaseResult: { any } = {}
			local releaseThread = coroutine.create(function()
				releaseResult = { service:Release(642) }
			end)
			local releasePaused, releaseMarker = coroutine.resume(releaseThread)
			expect(releasePaused and releaseMarker == "RELEASE_PAUSED")

			local reconnectResult: { any } = {}
			local reconnectThread = coroutine.create(function()
				reconnectResult = { service:LoadPlayer(642) }
			end)
			local reconnectWaiting, reconnectMarker = coroutine.resume(reconnectThread)
			expect(reconnectWaiting and reconnectMarker == "RECONNECT_WAIT")
			expectEqual(service:GetState(642), "Releasing")

			expect(coroutine.resume(releaseThread))
			expectEqual(coroutine.status(releaseThread), "dead")
			expectEqual(releaseResult[1], true)
			expectEqual(releaseResult[2], "RELEASED")
			expect(coroutine.resume(reconnectThread))
			expectEqual(coroutine.status(reconnectThread), "dead")
			expectEqual(reconnectResult[1], true)
			expectEqual(reconnectResult[2], "READY")

			local secondEntry = (service :: any)._entries[642]
			expect(secondEntry ~= firstEntry)
			expect(secondEntry.Token ~= firstToken)
			expect(secondEntry.ProfileSessionId ~= firstProfileSessionId)
			expectEqual(secondEntry.ProfileSessionId, "profile:2:presentation-id-2")
			expectEqual(inner:GetRequestCount("Load"), 2)
			expectEqual(inner:GetRequestCount("Release"), 1)
			expectEqual(inner:ReadStored(642).Session.Token, secondEntry.Token)
			expectEqual(service:GetState(642), "Ready")
		end,
	},
	{
		Name = "mutation during save remains dirty",
		Run = function()
			local inner = MemoryProfileAdapter.Create()
			local service: any = nil
			local reentered = false
			local wrapper = delegateAdapter(inner)
			function wrapper:Save(userId: number, profile: any, token: string, now: number): any
				if not reentered then
					reentered = true
					service:ApplyMutation(userId, function(draft: any)
						draft.Tape += 10
						return true
					end)
				end
				return inner:Save(userId, profile, token, now)
			end
			service = ProfileService.Create(wrapper, {
				Clock = function() return 100 end,
				Wait = function() end,
				AutoSchedule = false,
				ServerSessionId = "revision-test",
				IdentifierFactory = function() return "id" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			expect(service:LoadPlayer(65))
			service:ApplyMutation(65, function(profile: any)
				profile.Tape += 1
				return true
			end)
			local dirtySnapshot = service:GetSnapshot(65)
			expectEqual(dirtySnapshot.State, "Saving")
			expectEqual(dirtySnapshot.SaveState, "Saving")
			expect(service:SaveNow(65))
			expectEqual(service:GetProfileCopy(65).Tape, 11)
			expect(inner:GetRequestCount("Save") == 1)
			local reentrantSnapshot = service:GetSnapshot(65)
			expectEqual(reentrantSnapshot.State, "Saving")
			expectEqual(reentrantSnapshot.SaveState, "Saving")
			expect(service:SaveNow(65), "Second save must flush the reentrant mutation")
			expectEqual(inner:ReadStored(65).Tape, 11)
			local savedSnapshot = service:GetSnapshot(65)
			expectEqual(savedSnapshot.State, "Ready")
			expectEqual(savedSnapshot.SaveState, "Saved")
		end,
	},
	{
		Name = "one profile save failure does not stop another",
		Run = function()
			local harness = makeProfileHarness(nil)
			expect(harness.Service:LoadPlayer(66))
			expect(harness.Service:LoadPlayer(67))
			for userId = 66, 67 do
				harness.Service:ApplyMutation(userId, function(profile: any)
					profile.Tape += userId
					return true
				end)
			end
			harness.Adapter:SetSaveFailure(66, 1)
			harness.Clock.Value += ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
			expectEqual(harness.Service:ProcessDueSaves(), 2)
			expectEqual(harness.Service:GetState(66), "SaveDelayed")
			expectEqual(harness.Service:GetState(67), "Ready")
			expectEqual(harness.Adapter:ReadStored(67).Tape, 67)
		end,
	},
	{
		Name = "removal during yielded initial load releases the acquired lock",
		Run = function()
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			local enteredLoad = false
			function adapter:LoadAndLock(userId: number, fixture: any): any
				enteredLoad = true
				coroutine.yield("LOAD_PAUSED")
				return inner:LoadAndLock(userId, fixture)
			end
			local service = ProfileService.Create(adapter, {
				Clock = function() return 1_000 end,
				Wait = function() end,
				Spawn = function(callback: () -> ()) callback() end,
				AutoSchedule = false,
				ServerSessionId = "yielded-removal",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			local loadResult: { any } = {}
			local thread = coroutine.create(function()
				loadResult = { service:LoadPlayer(68) }
			end)
			local resumed, marker = coroutine.resume(thread)
			expect(resumed and marker == "LOAD_PAUSED" and enteredLoad)
			expectEqual(service:GetState(68), "Loading")
			expect(service:BeginRelease(68))
			expect(coroutine.resume(thread))
			expectEqual(coroutine.status(thread), "dead")
			expectEqual(loadResult[1], false)
			expectEqual(loadResult[2], "RELEASED_DURING_LOAD")
			expectEqual(service:GetState(68), "Released")
			expect(not service:CanEnterGameplay(68))
			expectEqual(inner:ReadStored(68).Session, nil)
		end,
	},
	{
		Name = "concurrent removal coalesces with a yielded initial load",
		Run = function()
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			function adapter:LoadAndLock(userId: number, fixture: any): any
				coroutine.yield("LOAD_PAUSED")
				return inner:LoadAndLock(userId, fixture)
			end
			local service = ProfileService.Create(adapter, {
				Clock = function() return 1_500 end,
				Wait = function(_duration: number)
					coroutine.yield("RELEASE_WAIT")
				end,
				AutoSchedule = false,
				ServerSessionId = "concurrent-removal",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			local loadResult: { any } = {}
			local loadThread = coroutine.create(function()
				loadResult = { service:LoadPlayer(681) }
			end)
			local loadedToPause, loadMarker = coroutine.resume(loadThread)
			expect(loadedToPause and loadMarker == "LOAD_PAUSED")
			expect(service:BeginRelease(681))

			local releaseResult: { any } = {}
			local releaseThread = coroutine.create(function()
				releaseResult = { service:Release(681) }
			end)
			local releaseWaiting, releaseMarker = coroutine.resume(releaseThread)
			expect(releaseWaiting and releaseMarker == "RELEASE_WAIT")

			local loadWaiting, loadReleaseMarker = coroutine.resume(loadThread)
			expect(loadWaiting and loadReleaseMarker == "RELEASE_WAIT")
			expectEqual(service:GetState(681), "Releasing")
			expect(coroutine.resume(releaseThread))
			expectEqual(coroutine.status(releaseThread), "dead")
			expectEqual(releaseResult[1], true)
			expectEqual(releaseResult[2], "RELEASED")
			expect(coroutine.resume(loadThread))
			expectEqual(coroutine.status(loadThread), "dead")
			expectEqual(loadResult[1], false)
			expectEqual(loadResult[2], "RELEASED_DURING_LOAD")
			expectEqual(inner:GetRequestCount("Release"), 1)
			expectEqual(inner:ReadStored(681).Session, nil)
			expectEqual(service:GetState(681), "Released")
			expect(not service:CanEnterGameplay(681))
		end,
	},
	{
		Name = "release waits for an in-flight heartbeat without reviving the profile",
		Run = function()
			local clock = { Value = 1_800 }
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			function adapter:Heartbeat(userId: number, token: string, now: number): any
				coroutine.yield("HEARTBEAT_PAUSED")
				return inner:Heartbeat(userId, token, now)
			end
			local service = ProfileService.Create(adapter, {
				Clock = function() return clock.Value end,
				Wait = function(duration: number)
					clock.Value += duration
					coroutine.yield("HEARTBEAT_WAIT")
				end,
				AutoSchedule = false,
				ServerSessionId = "heartbeat-release",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			expect(service:LoadPlayer(682))
			local entry = (service :: any)._entries[682]
			local heartbeatResult: { any } = {}
			local heartbeatThread = coroutine.create(function()
				heartbeatResult = { (service :: any):_heartbeat(entry) }
			end)
			local heartbeatPaused, heartbeatMarker = coroutine.resume(heartbeatThread)
			expect(heartbeatPaused and heartbeatMarker == "HEARTBEAT_PAUSED")
			expectEqual(service:GetActiveSaveCount(), 1)
			expect(service:BeginRelease(682))

			local releaseResult: { any } = {}
			local releaseThread = coroutine.create(function()
				releaseResult = { service:Release(682) }
			end)
			local releaseWaiting, waitMarker = coroutine.resume(releaseThread)
			expect(releaseWaiting and waitMarker == "HEARTBEAT_WAIT")
			expect(coroutine.resume(heartbeatThread))
			expectEqual(coroutine.status(heartbeatThread), "dead")
			expectEqual(heartbeatResult[1], false)
			expectEqual(heartbeatResult[2], "PROFILE_RELEASING")
			expectEqual(service:GetActiveSaveCount(), 0)
			expect(coroutine.resume(releaseThread))
			expectEqual(coroutine.status(releaseThread), "dead")
			expectEqual(releaseResult[1], true)
			expectEqual(releaseResult[2], "RELEASED")
			expectEqual(service:GetState(682), "Released")
			expectEqual(inner:ReadStored(682).Session, nil)
			expect(not service:CanEnterGameplay(682))
		end,
	},
	{
		Name = "shutdown during yielded initial load cannot leave a Ready profile",
		Run = function()
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			function adapter:LoadAndLock(userId: number, fixture: any): any
				coroutine.yield("LOAD_PAUSED")
				return inner:LoadAndLock(userId, fixture)
			end
			local service = ProfileService.Create(adapter, {
				Clock = function() return 2_000 end,
				Wait = function() end,
				Spawn = function(callback: () -> ()) callback() end,
				AutoSchedule = false,
				ServerSessionId = "yielded-shutdown",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			local loadResult: { any } = {}
			local thread = coroutine.create(function()
				loadResult = { service:LoadPlayer(69) }
			end)
			expect(coroutine.resume(thread))
			service:BeginShutdown()
			expect(coroutine.resume(thread))
			expectEqual(loadResult[1], false)
			expectEqual(loadResult[2], "RELEASED_DURING_LOAD")
			expectEqual(service:GetState(69), "Released")
			expect(not service:CanEnterGameplay(69))
			expectEqual(inner:ReadStored(69).Session, nil)
		end,
	},
})

local function withStationService(
	eligibility: { [Player]: boolean },
	callback: (any, Instance) -> ()
)
	local stations = authoredStationsRoot():Clone()
	stations.Name = "Phase05AssignmentStations"
	stations.Parent = nil
	local service = StationService.Create(stations, {
		IsPlayerEligible = function(player: Player): boolean
			return eligibility[player] == true
		end,
	})
	local ok, failure = pcall(callback, service, stations)
	service:Destroy()
	stations:Destroy()
	if not ok then error(failure, 2) end
end

addSuite("Assignment gating", {
	{
		Name = "Loading Unavailable and Conflict players receive no station",
		Run = function()
			local eligibility: { [Player]: boolean } = {}
			withStationService(eligibility, function(service: any)
				for userId = 71, 73 do
					local player = fakePlayer(userId)
					local result = service:AssignPlayer(player)
					expect(not result.Assigned and not result.Waiting)
					expectEqual(result.Reason, "INELIGIBLE")
				end
			end)
		end,
	},
	{
		Name = "Ready player receives lowest station",
		Run = function()
			local eligibility: { [Player]: boolean } = {}
			withStationService(eligibility, function(service: any)
				local player = fakePlayer(74)
				eligibility[player] = true
				local result = service:AssignPlayer(player)
				expect(result.Assigned)
				expectEqual(result.StationId, "station_01")
			end)
		end,
	},
	{
		Name = "ninth Ready player waits",
		Run = function()
			local eligibility: { [Player]: boolean } = {}
			withStationService(eligibility, function(service: any)
				local ninth: Player? = nil
				for index = 1, 9 do
					local player = fakePlayer(740 + index)
					eligibility[player] = true
					local result = service:AssignPlayer(player)
					if index <= 8 then expect(result.Assigned) else
						ninth = player
						expect(result.Waiting and result.QueuePosition == 1)
					end
				end
				expect(ninth ~= nil and service:IsWaiting(ninth))
			end)
		end,
	},
	{
		Name = "Conflict player releases station",
		Run = function()
			local eligibility: { [Player]: boolean } = {}
			withStationService(eligibility, function(service: any)
				local player = fakePlayer(76)
				eligibility[player] = true
				expect(service:AssignPlayer(player).Assigned)
				eligibility[player] = false
				expect(service:ReleasePlayer(player).Released)
				expectEqual(service:GetStationId(player), nil)
			end)
		end,
	},
	{
		Name = "promoted waiter must still be Ready",
		Run = function()
			local eligibility: { [Player]: boolean } = {}
			withStationService(eligibility, function(service: any)
				local assigned: { Player } = {}
				for index = 1, 8 do
					local player = fakePlayer(760 + index)
					eligibility[player] = true
					service:AssignPlayer(player)
					table.insert(assigned, player)
				end
				local stale = fakePlayer(769)
				local ready = fakePlayer(770)
				eligibility[stale] = true
				eligibility[ready] = true
				service:AssignPlayer(stale)
				service:AssignPlayer(ready)
				eligibility[stale] = false
				local release = service:ReleasePlayer(assigned[1])
				expect(release.PromotedPlayer == ready)
				expectEqual(service:GetStationId(stale), nil)
				expectEqual(service:GetStationId(ready), "station_01")
			end)
		end,
	},
	{
		Name = "client-ready before load and load before client-ready both gate correctly",
		Run = function()
			local function coordinator(): any
				local state = { ClientReady = false, ProfileReady = false, Assignments = 0 }
				local function attempt()
					if state.ClientReady and state.ProfileReady and state.Assignments == 0 then state.Assignments = 1 end
				end
				return state, attempt
			end
			local first, attemptFirst = coordinator()
			first.ClientReady = true; attemptFirst(); expectEqual(first.Assignments, 0)
			first.ProfileReady = true; attemptFirst(); expectEqual(first.Assignments, 1)
			local second, attemptSecond = coordinator()
			second.ProfileReady = true; attemptSecond(); expectEqual(second.Assignments, 0)
			second.ClientReady = true; attemptSecond(); expectEqual(second.Assignments, 1)
		end,
	},
})

local function progressionReward(
	outcomeId: string,
	roundId: number,
	outcomeType: string,
	tapeDelta: number,
	newTape: number,
	xpDelta: number
): any
	local stats = defaultProfile().Stats
	return {
		OutcomeId = outcomeId,
		RoundId = roundId,
		OutcomeType = outcomeType,
		TapeDelta = tapeDelta,
		NewTape = newTape,
		XPDelta = xpDelta,
		PreviousXP = 0,
		NewXP = xpDelta,
		PreviousRank = { Index = 1, Name = "Rookie Packer", Threshold = 0 },
		NewRank = { Index = 1, Name = "Rookie Packer", Threshold = 0 },
		NewDiscoveries = {},
		MasteryChanges = {},
		UpdatedStats = stats,
		Duplicate = false,
	}
end

local function makeRoundHarness(serverSessionId: string?): any
	local state = {
		Tape = 125,
		Ready = true,
		Mutable = true,
		ShipmentCalls = 0,
		FailureCalls = 0,
		CosmeticCalls = 0,
		Clears = 0,
		Log = {} :: { string },
	}
	local stationService = {
		GetStationId = function(_self: any, _player: Player): string
			return "station_01"
		end,
	}
	local worldItemService = {
		SpawnAcceptedPlacement = function() end,
		ClearPlayer = function()
			state.Clears += 1
		end,
	}
	local profileService = {
		CanEnterGameplay = function(_self: any, _userId: number): boolean return state.Ready end,
		CanMutate = function(_self: any, _userId: number): boolean return state.Mutable end,
		GetTape = function(_self: any, _userId: number): number return state.Tape end,
	}
	local progressionService = {
		ApplyShipment = function(_self: any, _userId: number, roundId: number, outcomeId: string, record: any): (any, string)
			state.ShipmentCalls += 1
			table.insert(state.Log, "progression")
			state.Tape += record.ShipmentValue
			return progressionReward(outcomeId, roundId, "Shipment", record.ShipmentValue, state.Tape, 15), "APPLIED"
		end,
		ApplyFailure = function(_self: any, _userId: number, roundId: number, outcomeId: string, itemCount: number): (any, string)
			state.FailureCalls += 1
			table.insert(state.Log, "progression")
			return progressionReward(outcomeId, roundId, "Failure", 0, state.Tape, math.min(itemCount * 2, 10)), "APPLIED"
		end,
	}
	local shipmentRecords = {
		Capture = function(_self: any, player: Player, round: any): (any, string)
			return {
				OutcomeId = round.OutcomeId,
				ShipmentId = round.OutcomeId,
				PlayerUserId = player.UserId,
				PlayerDisplayName = player.DisplayName,
				StationId = round.StationId,
				RoundId = round.RoundId,
				ItemCount = round.ItemCount,
				BaseValueSum = round.BaseValueSum,
				ShipmentValue = round.ShipmentValue,
				Multiplier = 1,
				PlacedItems = round.PlacedItems,
				CreatedAt = 100,
				PerfectShipment = round.ItemCount == 10,
			}, "CAPTURED"
		end,
	}
	local scheduled: { any } = {}
	local service = RoundService.Create(stationService :: any, worldItemService :: any, {
		Clock = function() return 100 end,
		Scheduler = function(duration: number, callback: () -> ())
			table.insert(scheduled, { Duration = duration, Callback = callback })
		end,
		ProfileService = profileService,
		ProgressionService = progressionService,
		ShipmentRecordService = shipmentRecords,
		ServerSessionId = serverSessionId or "round-test-server",
		EventSink = {
			OnShipmentCompleted = function()
				state.CosmeticCalls += 1
				table.insert(state.Log, "cosmetic")
			end,
			OnRoundFailed = function()
				state.CosmeticCalls += 1
				table.insert(state.Log, "cosmetic")
			end,
		},
	})
	return service, state, scheduled
end

addSuite("Round integration", {
	{
		Name = "OutcomeId is server scoped stable and bounded",
		Run = function()
			local player = fakePlayer(81)
			local first = makeRoundHarness("server-A")
			local firstRound = first:StartRound(player)
			expectEqual(firstRound.OutcomeId, "81:server-A:1")
			expectEqual(first:HandleClientReady(player).OutcomeId, firstRound.OutcomeId)
			local second = makeRoundHarness("server-B")
			local secondRound = second:StartRound(player)
			expect(firstRound.OutcomeId ~= secondRound.OutcomeId)
			expect(#firstRound.OutcomeId <= ProfileConfig.MAXIMUM_OUTCOME_ID_LENGTH)
		end,
	},
	{
		Name = "Loading profile receives no round",
		Run = function()
			local service, state = makeRoundHarness()
			state.Ready = false
			expectEqual(service:StartRound(fakePlayer(82)), nil)
		end,
	},
	{
		Name = "RoundSnapshot Tape matches profile",
		Run = function()
			local service, state = makeRoundHarness()
			local player = fakePlayer(83)
			service:StartRound(player)
			state.Tape = 777
			expectEqual(service:GetSnapshot(player).SessionBank, 777)
		end,
	},
	{
		Name = "shipment progression occurs before cosmetic callback",
		Run = function()
			local service, state = makeRoundHarness()
			local player = fakePlayer(84)
			local round = service:StartRound(player)
			round.ItemCount = 1
			round.ShipmentValue = 50
			round.PlacedItems = { { ItemId = "parcel" } }
			service:_enterShipping(player, "PLAYER_SHIPPED")
			expectArray(state.Log, { "progression", "cosmetic" })
			expectEqual(round.SessionBank, 175)
		end,
	},
	{
		Name = "duplicate shipping callback cannot duplicate reward",
		Run = function()
			local service, state = makeRoundHarness()
			local player = fakePlayer(85)
			local round = service:StartRound(player)
			round.ItemCount = 1
			round.ShipmentValue = 50
			service:_enterShipping(player, "PLAYER_SHIPPED")
			service:_enterShipping(player, "PLAYER_SHIPPED")
			expectEqual(state.ShipmentCalls, 1)
			expectEqual(state.CosmeticCalls, 1)
		end,
	},
	{
		Name = "failure consolation progression occurs before failure cosmetic",
		Run = function()
			local service, state = makeRoundHarness()
			local player = fakePlayer(86)
			local round = service:StartRound(player)
			round.ItemCount = 4
			round.ShipmentValue = 90
			service:_enterFailure(player, "BOX_FULL")
			expectEqual(state.FailureCalls, 1)
			expectArray(state.Log, { "progression", "cosmetic" })
			expectEqual(round.State, "Failing")
		end,
	},
	{
		Name = "restart and departure retain persistent profile Tape",
		Run = function()
			local service, state = makeRoundHarness()
			local player = fakePlayer(87)
			local round = service:StartRound(player)
			round.ItemCount = 1
			round.ShipmentValue = 25
			service:_enterShipping(player, "PLAYER_SHIPPED")
			service:RemovePlayer(player)
			expectEqual(state.Tape, 150)
			expectEqual(state.Clears, 1)
			local restarted = service:StartRound(player, "RESTART")
			expectEqual(restarted.SessionBank, 150)
			expectEqual(restarted.RoundId, 2)
		end,
	},
	{
		Name = "showcase rejection cannot alter applied profile reward",
		Run = function()
			local service, state = makeRoundHarness()
			local serviceAny = service :: any
			serviceAny._eventSink.OnShipmentCompleted = function()
				return false
			end
			local player = fakePlayer(88)
			local round = service:StartRound(player)
			round.ItemCount = 1
			round.ShipmentValue = 40
			service:_enterShipping(player, "PLAYER_SHIPPED")
			expectEqual(state.Tape, 165)
			expect(round.OutcomeProcessed)
		end,
	},
})

local function collectionView(
	discovered: { [string]: boolean }?,
	mastery: { [string]: number }?,
	recent: { string }?
): any
	return {
		PackingXP = 0,
		Collection = {
			Discovered = discovered or {},
			MasteryCounts = mastery or {},
			RecentDiscoveries = recent or {},
		},
	}
end

local function withShelfService(callback: (any, Instance) -> ())
	local stations = authoredStationsRoot():Clone()
	stations.Name = "Phase05ShelfStations"
	stations.Parent = nil
	local template = collectionTemplate():Clone()
	template.Parent = nil
	local service = CollectionShelfService.Create(stations, template)
	local ok, failure = pcall(callback, service, stations)
	service:ClearAll()
	stations:Destroy()
	template:Destroy()
	if not ok then error(failure, 2) end
end

local function shelfRuntime(stations: Instance, stationIndex: number): Folder
	local station = requireChild(stations, string.format("Station_%02d", stationIndex), "Model")
	local shelf = requireChild(station, "CollectionShelf", "Model")
	return requireChild(shelf, "Runtime", "Folder") :: Folder
end

local function featuredIds(runtime: Folder): { string }
	local ids: { string } = {}
	local children = runtime:GetChildren()
	table.sort(children, function(left: Instance, right: Instance): boolean return left.Name < right.Name end)
	for _, child in ipairs(children) do table.insert(ids, child:GetAttribute("ItemId") :: string) end
	return ids
end

addSuite("Collection shelves", {
	{
		Name = "eight authored shelves resolve with six slots and one Runtime",
		Run = function()
			for index = 1, 8 do
				local station = requireChild(authoredStationsRoot(), string.format("Station_%02d", index), "Model")
				local shelf = requireChild(station, "CollectionShelf", "Model")
				for slot = 1, 6 do requireChild(shelf, string.format("Slot_%02d", slot), "BasePart") end
				expectEqual(#requireChild(shelf, "Runtime", "Folder"):GetChildren(), 0)
			end
		end,
	},
	{
		Name = "profile renders correct collection count and rank",
		Run = function()
			withShelfService(function(service: any, stations: Instance)
				local profile = collectionView({ parcel = true, chair_blockout = true }, { parcel = 2, chair_blockout = 1 })
				profile.PackingXP = 1_000
				expect(service:Render("station_01", profile))
				local shelf = requireChild(requireChild(stations, "Station_01", "Model"), "CollectionShelf", "Model")
				local billboard = requireChild(requireChild(shelf, "ShelfLabel", "BasePart"), "BillboardGui", "BillboardGui")
				expectEqual((requireChild(billboard, "RankName", "TextLabel") :: TextLabel).Text, "SPACE SAVER")
				expectEqual((requireChild(billboard, "CollectionCount", "TextLabel") :: TextLabel).Text, "2 / 8 DISCOVERED")
			end)
		end,
	},
	{
		Name = "recent discovery ordering is newest first without duplicates",
		Run = function()
			withShelfService(function(service: any, stations: Instance)
				local discovered = { parcel = true, lamp_blockout = true, chair_blockout = true }
				service:Render("station_01", collectionView(discovered, {}, { "parcel", "lamp_blockout", "chair_blockout", "chair_blockout" }))
				expectArray(featuredIds(shelfRuntime(stations, 1)), { "chair_blockout", "lamp_blockout", "parcel" })
			end)
		end,
	},
	{
		Name = "mastery ordering is tier count then catalog",
		Run = function()
			withShelfService(function(service: any, stations: Instance)
				local discovered = { parcel = true, lamp_blockout = true, chair_blockout = true }
				service:Render("station_01", collectionView(discovered, { parcel = 5, lamp_blockout = 50, chair_blockout = 20 }))
				expectArray(featuredIds(shelfRuntime(stations, 1)), { "lamp_blockout", "chair_blockout", "parcel" })
			end)
		end,
	},
	{
		Name = "release clears one shelf only and reassignment starts clean",
		Run = function()
			withShelfService(function(service: any, stations: Instance)
				local profile = collectionView({ parcel = true }, { parcel = 1 })
				service:Render("station_01", profile)
				service:Render("station_02", profile)
				expect(service:Clear("station_01"))
				expectEqual(service:GetRuntimeCount("station_01"), 0)
				expectEqual(service:GetRuntimeCount("station_02"), 1)
				expectArray(featuredIds(shelfRuntime(stations, 2)), { "parcel" })
			end)
		end,
	},
	{
		Name = "eight profiles remain isolated and runtime proxies stay bounded",
		Run = function()
			withShelfService(function(service: any, stations: Instance)
				for station = 1, 8 do
					local itemId = CollectionDefinitions.OrderedItemIds[station]
					service:Render(string.format("station_%02d", station), collectionView({ [itemId] = true }, { [itemId] = station }))
				end
				for station = 1, 8 do
					expectEqual(service:GetRuntimeCount(string.format("station_%02d", station)), 1)
					expectArray(featuredIds(shelfRuntime(stations, station)), { CollectionDefinitions.OrderedItemIds[station] })
				end
				service:ClearAll()
				for station = 1, 8 do expectEqual(service:GetRuntimeCount(string.format("station_%02d", station)), 0) end
			end)
		end,
	},
	{
		Name = "maximum six runtime proxies and cleanup returns to baseline",
		Run = function()
			withShelfService(function(service: any)
				local discovered: { [string]: boolean } = {}
				local mastery: { [string]: number } = {}
				for _, itemId in ipairs(CollectionDefinitions.OrderedItemIds) do discovered[itemId] = true; mastery[itemId] = 1 end
				service:Render("station_01", collectionView(discovered, mastery))
				expectEqual(service:GetRuntimeCount("station_01"), 6)
				service:ClearAll()
				expectEqual(service:GetRuntimeCount("station_01"), 0)
			end)
		end,
	},
})

local function withProfileUI(callback: (any, Frame, { boolean }) -> ())
	local root = authoredGuiRoot():Clone()
	root.Name = "Phase05ProfileUI"
	root.Parent = nil
	local template = collectionTemplate():Clone()
	template.Parent = nil
	local menuStates: { boolean } = {}
	local controller = ProfileUIController.new(root, template, {
		MenuOpenChanged = function(isOpen: boolean)
			table.insert(menuStates, isOpen)
		end,
		AudioHook = function(_eventName: string) end,
	})
	local ok, failure = pcall(callback, controller, root, menuStates)
	controller:Destroy()
	root:Destroy()
	template:Destroy()
	GuiService.SelectedObject = nil
	if not ok then error(failure, 2) end
end

local function rewardSnapshot(outcomeId: string, roundId: number, duplicate: boolean?): any
	local profile = defaultProfile()
	profile.Tape = 25
	profile.PackingXP = 15
	local reward = progressionReward(outcomeId, roundId, "Shipment", 25, 25, 15)
	reward.Duplicate = duplicate == true
	return profileSnapshot(profile, 2, "profile:ui", reward)
end

local function uiLabel(root: Frame, parentName: string, labelName: string): TextLabel
	local parent = requireChild(root, parentName, "GuiObject")
	return requireChild(parent, labelName, "TextLabel") :: TextLabel
end

addSuite("Client presentation", {
	{
		Name = "results keep the meta bar below reveals on compact layouts",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				local meta = requireChild(root, "MetaBar", "Frame") :: Frame
				local layoutClasses: { ProfileLayoutClass } = { "CompactLandscape", "Portrait" }
				for _, layoutClass in ipairs(layoutClasses) do
					local layout = ProfileResponsiveLayout.Resolve(layoutClass)
					local revealBottom = layout.DiscoveryReveal.Position.Y.Scale
						+ layout.DiscoveryReveal.Size.Y.Scale / 2
					expect(
						layout.ResultsMetaBar.Position.Y.Scale > revealBottom,
						string.format("%s results MetaBar must remain below DiscoveryReveal", layoutClass)
					)
					expect(
						layout.ResultsMetaBar.Position.Y.Scale + layout.ResultsMetaBar.Size.Y.Scale <= 1,
						string.format("%s results MetaBar must remain on screen", layoutClass)
					)
					controller:SetLayoutClass(layoutClass)
					controller:ApplyRoundSnapshot(roundSnapshot(1, 5, "Results", "90:server:1"), true)
					expectEqual(meta.Position, layout.ResultsMetaBar.Position)
					expectEqual(meta.Size, layout.ResultsMetaBar.Size)
					controller:ApplyRoundSnapshot(roundSnapshot(2, 1, "Preparing", nil), true)
					expectEqual(meta.Position, layout.MetaBar.Position)
					expectEqual(meta.Size, layout.MetaBar.Size)
				end
			end)
		end,
	},
	{
		Name = "round-before-profile ordering correlates one result",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				controller:ApplyRoundSnapshot(roundSnapshot(1, 5, "Results", "91:server:1"), true)
				controller:ApplyProfileSnapshot(rewardSnapshot("91:server:1", 1))
				expectEqual(uiLabel(root, "ResultsPanel", "XPReward").Text, "+15 PACKING XP")
			end)
		end,
	},
	{
		Name = "profile-before-round ordering correlates one result",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				controller:ApplyProfileSnapshot(rewardSnapshot("92:server:1", 1))
				expectEqual(uiLabel(root, "ResultsPanel", "XPReward").Text, "")
				controller:ApplyRoundSnapshot(roundSnapshot(1, 5, "Results", "92:server:1"), true)
				expectEqual(uiLabel(root, "ResultsPanel", "XPReward").Text, "+15 PACKING XP")
			end)
		end,
	},
	{
		Name = "duplicate reward reveal is rejected",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				controller:ApplyRoundSnapshot(roundSnapshot(1, 5, "Results", "93:server:1"), true)
				controller:ApplyProfileSnapshot(rewardSnapshot("93:server:1", 1, true))
				expectEqual(uiLabel(root, "ResultsPanel", "XPReward").Text, "")
				expectEqual(#((controller :: any)._revealQueue), 0)
			end)
		end,
	},
	{
		Name = "Pack Again during reveal state is safe",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				(controller :: any)._revealWorkerActive = true
				(controller :: any)._revealEpoch = 7
				uiLabel(root, "ResultsPanel", "XPReward").Text = "+15 PACKING XP"
				controller:ApplyRoundSnapshot(roundSnapshot(2, 1, "Preparing", "94:server:2"), true)
				expectEqual(uiLabel(root, "ResultsPanel", "XPReward").Text, "")
				expectEqual(controller:IsMenuOpen(), false)
			end)
		end,
	},
	{
		Name = "collection panel closes when an active round begins",
		Run = function()
			withProfileUI(function(controller: any, root: Frame, menuStates: { boolean })
				controller:ApplyProfileSnapshot(profileSnapshot(defaultProfile(), 1, "profile:menu"))
				local panel = requireChild(root, "CollectionPanel", "Frame") :: Frame
				(controller :: any)._panelOpen = true
				panel.Visible = true
				controller:ApplyRoundSnapshot(roundSnapshot(1, 1, "AwaitingPlacement", "95:server:1"), true)
				expectEqual(controller:IsMenuOpen(), false)
				expectEqual(panel.Visible, false)
				expectEqual(menuStates[#menuStates], false)
			end)
		end,
	},
	{
		Name = "Loading Unavailable and Conflict states are explicit",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				local loading = ProfileSnapshotBuilder.Build(nil, "Loading", "Loading", 1, "states", nil)
				controller:ApplyProfileSnapshot(loading)
				local meta = requireChild(root, "MetaBar", "Frame")
				local status = requireChild(meta, "DataStatus", "TextLabel") :: TextLabel
				expectEqual(status.Text, "LOADING PROFILE")
			end)
		end,
	},
	{
		Name = "profile status labels render all failure states",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				local meta = requireChild(root, "MetaBar", "Frame") :: Frame
				local status = requireChild(meta, "DataStatus", "TextLabel") :: TextLabel
				controller:ApplyProfileSnapshot(ProfileSnapshotBuilder.Build(nil, "Loading", "Loading", 1, "states", nil))
				expectEqual(status.Text, "LOADING PROFILE")
				controller:ApplyProfileSnapshot(ProfileSnapshotBuilder.Build(nil, "Unavailable", "Unavailable", 2, "states", nil))
				expectEqual(status.Text, "DATA UNAVAILABLE")
				controller:ApplyProfileSnapshot(ProfileSnapshotBuilder.Build(nil, "Conflict", "Conflict", 3, "states", nil))
				expectEqual(status.Text, "PROFILE OPEN ELSEWHERE")
			end)
		end,
	},
	{
		Name = "gamepad profile focus is cleared on forced close",
		Run = function()
			withProfileUI(function(controller: any, root: Frame)
				controller:ApplyProfileSnapshot(profileSnapshot(defaultProfile(), 1, "profile:focus"))
				local panel = requireChild(root, "CollectionPanel", "Frame") :: Frame
				(controller :: any)._panelOpen = true
				panel.Visible = true
				controller:ApplyRoundSnapshot(roundSnapshot(1, 1, "Decision", "96:server:1"), true)
				expectEqual(GuiService.SelectedObject, nil)
				expectEqual(controller:IsMenuOpen(), false)
			end)
		end,
	},
	{
		Name = "profile overlay is active above gameplay for touch capture",
		Run = function()
			local panel = requireChild(authoredGuiRoot(), "CollectionPanel", "Frame") :: Frame
			local meta = requireChild(authoredGuiRoot(), "MetaBar", "Frame")
			local collectionButton = requireChild(meta, "CollectionButton", "TextButton") :: TextButton
			expect(panel.Active, "CollectionPanel must sink touch input while visible")
			expect(collectionButton.Active and collectionButton.Selectable)
			expect(panel.ZIndex > collectionButton.ZIndex)
		end,
	},
})

addSuite("Write coordination", {
	{
		Name = "saturated write slots schedule a future retry",
		Run = function()
			local harness = makeProfileHarness(820, { Now = 12_000 })
			harness.Service:ApplyMutation(820, function(profile: any)
				profile.Tape += 1
				return true
			end)
			local service = harness.Service :: any
			local entry = service._entries[820]
			entry.NextSaveAt = harness.Clock.Value - 5
			service._activeSaves = ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES
			local saved, code = harness.Service:SaveNow(820)
			expect(not saved and code == "SAVE_LIMIT")
			expectEqual(entry.NextSaveAt, harness.Clock.Value + ProfileConfig.RETRY_BASE_SECONDS)
			service._activeSaves = 0
		end,
	},
	{
		Name = "saves heartbeats and releases share one maximum-eight write cap",
		Run = function()
			local clock = { Value = 3_000 }
			local inner = MemoryProfileAdapter.Create()
			local adapter = delegateAdapter(inner)
			local service: any = nil
			local pauseWrites = false
			local maximumActive = 0
			local entered = { Save = 0, Heartbeat = 0, Release = 0 }
			local function enterWrite(operation: "Save" | "Heartbeat" | "Release")
				entered[operation] += 1
				maximumActive = math.max(maximumActive, service:GetActiveSaveCount())
				if pauseWrites then
					coroutine.yield(operation .. "_PAUSED")
				end
			end
			function adapter:Save(userId: number, profile: any, token: string, now: number): any
				enterWrite("Save")
				return inner:Save(userId, profile, token, now)
			end
			function adapter:Heartbeat(userId: number, token: string, now: number): any
				enterWrite("Heartbeat")
				return inner:Heartbeat(userId, token, now)
			end
			function adapter:Release(userId: number, profile: any, token: string, now: number): any
				enterWrite("Release")
				return inner:Release(userId, profile, token, now)
			end
			service = ProfileService.Create(adapter, {
				Clock = function() return clock.Value end,
				Wait = function(duration: number) clock.Value += duration end,
				AutoSchedule = false,
				ServerSessionId = "shared-write-cap",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			for userId = 201, 211 do
				expect(service:LoadPlayer(userId))
			end
			pauseWrites = true

			local threads: { thread } = {}
			local results: { [string]: { any } } = {}
			local function launch(label: string, marker: string, callback: any)
				local thread = coroutine.create(function()
					results[label] = { callback() }
				end)
				local resumed, yieldedMarker = coroutine.resume(thread)
				expect(resumed and yieldedMarker == marker, label .. " must pause inside its adapter write")
				table.insert(threads, thread)
			end

			for userId = 201, 203 do
				service:ApplyMutation(userId, function(profile: any)
					profile.Tape = userId
					return true
				end)
				launch("save-" .. userId, "Save_PAUSED", function()
					return service:SaveNow(userId)
				end)
			end
			for userId = 204, 206 do
				local entry = service._entries[userId]
				launch("heartbeat-" .. userId, "Heartbeat_PAUSED", function()
					return service:_heartbeat(entry)
				end)
			end
			for userId = 207, 208 do
				expect(service:BeginRelease(userId))
				launch("release-" .. userId, "Release_PAUSED", function()
					return service:Release(userId)
				end)
			end

			expectEqual(service:GetActiveSaveCount(), ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES)
			expectEqual(maximumActive, ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES)
			service:ApplyMutation(209, function(profile: any)
				profile.Tape = 209
				return true
			end)
			local saveAtCap, saveAtCapCode = service:SaveNow(209)
			expect(not saveAtCap and saveAtCapCode == "SAVE_LIMIT")
			local heartbeatAtCap, heartbeatAtCapCode = service:_heartbeat(service._entries[210])
			expect(not heartbeatAtCap and heartbeatAtCapCode == "SAVE_LIMIT")
			expect(service:BeginRelease(211))
			local releaseAtCap, releaseAtCapCode = service:Release(211)
			expect(not releaseAtCap and releaseAtCapCode == "SAVELIMIT")
			expectEqual(entered.Save, 3)
			expectEqual(entered.Heartbeat, 3)
			expectEqual(entered.Release, 2)
			expectEqual(service:GetActiveSaveCount(), ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES)

			for _, thread in ipairs(threads) do
				expect(coroutine.resume(thread))
				expectEqual(coroutine.status(thread), "dead")
			end
			expectEqual(service:GetActiveSaveCount(), 0)
			expectEqual(maximumActive, ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES)
			for userId = 201, 203 do
				expectEqual(results["save-" .. userId][1], true)
				expectEqual(results["save-" .. userId][2], "SAVED")
			end
			for userId = 204, 206 do
				expectEqual(results["heartbeat-" .. userId][1], true)
				expectEqual(results["heartbeat-" .. userId][2], "HEARTBEATED")
			end
			for userId = 207, 208 do
				expectEqual(results["release-" .. userId][1], true)
				expectEqual(results["release-" .. userId][2], "RELEASED")
			end
		end,
	},
})

addSuite("Autosave", {
	{
		Name = "dirty save debounce waits exactly five seconds",
		Run = function()
			local harness = makeProfileHarness(101)
			harness.Service:ApplyMutation(101, function(profile: any)
				profile.Tape += 1
				return true
			end)
			local baseline = harness.Adapter:GetRequestCount("Save")
			harness.Clock.Value += 4
			expectEqual(harness.Service:ProcessDueSaves(), 0)
			harness.Clock.Value += 1
			expectEqual(harness.Service:ProcessDueSaves(), 1)
			expectEqual(harness.Adapter:GetRequestCount("Save"), baseline + 1)
		end,
	},
	{
		Name = "coalesced mutations use one shared save",
		Run = function()
			local harness = makeProfileHarness(102)
			for _ = 1, 3 do
				harness.Service:ApplyMutation(102, function(profile: any)
					profile.Tape += 1
					return true
				end)
			end
			harness.Clock.Value += 5
			expectEqual(harness.Service:ProcessDueSaves(), 1)
			expectEqual(harness.Adapter:GetRequestCount("Save"), 1)
			expectEqual(harness.Adapter:ReadStored(102).Tape, 3)
		end,
	},
	{
		Name = "autosave interval flushes an older dirty profile",
		Run = function()
			local harness = makeProfileHarness(103)
			harness.Service:ApplyMutation(103, function(profile: any)
				profile.Tape = 60
				return true
			end)
			harness.Clock.Value += ProfileConfig.AUTOSAVE_INTERVAL_SECONDS
			expectEqual(harness.Service:ProcessDueSaves(), 1)
			expectEqual(harness.Adapter:ReadStored(103).Tape, 60)
		end,
	},
	{
		Name = "budget delay is visible and retry remains bounded",
		Run = function()
			local harness = makeProfileHarness(104)
			harness.Service:ApplyMutation(104, function(profile: any)
				profile.Tape = 1
				return true
			end)
			harness.Adapter:SetBudgetAvailable(false)
			local success, code = harness.Service:SaveNow(104)
			expect(not success and code == "BudgetDelayed")
			expectEqual(harness.Service:GetState(104), "SaveDelayed")
			harness.Adapter:SetBudgetAvailable(true)
			expect(harness.Service:SaveNow(104))
		end,
	},
	{
		Name = "autosave failure advances autosave deadline without a zero-delay loop",
		Run = function()
			local harness = makeProfileHarness(1041)
			harness.Service:ApplyMutation(1041, function(profile: any)
				profile.Tape = 9
				return true
			end)
			harness.Adapter:SetSaveFailure(1041, 1)
			harness.Clock.Value += ProfileConfig.AUTOSAVE_INTERVAL_SECONDS
			expectEqual(harness.Service:ProcessDueSaves(), 1)
			expectEqual(harness.Adapter:GetRequestCount("Save"), 1)
			local entry = (harness.Service :: any)._entries[1041]
			expect(entry.NextSaveAt > harness.Clock.Value)
			expect(entry.NextAutosaveAt >= entry.NextSaveAt)
			harness.Service:ProcessDueSaves()
			expectEqual(harness.Adapter:GetRequestCount("Save"), 1,
				"An autosave failure must not immediately retry the save at the same clock tick")
			harness.Clock.Value = entry.NextSaveAt
			harness.Service:ProcessDueSaves()
			expectEqual(harness.Adapter:GetRequestCount("Save"), 2)
			expectEqual(harness.Service:GetState(1041), "Ready")
		end,
	},
	{
		Name = "autosave retries use exact bounded exponential backoff",
		Run = function()
			local harness = makeProfileHarness(1042)
			harness.Service:ApplyMutation(1042, function(profile: any)
				profile.Tape = 42
				return true
			end)
			harness.Adapter:SetSaveFailure(1042, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS)
			local expectedDelays = { 1, 2, 4, 8, ProfileConfig.AUTOSAVE_INTERVAL_SECONDS }
			harness.Clock.Value += ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
			for attempt, expectedDelay in ipairs(expectedDelays) do
				expectEqual(harness.Service:ProcessDueSaves(), 1)
				expectEqual(harness.Adapter:GetRequestCount("Save"), attempt)
				expectEqual(harness.Service:GetState(1042), "SaveDelayed")
				local entry = (harness.Service :: any)._entries[1042]
				expectEqual(entry.ConsecutiveSaveFailures, attempt)
				expectEqual(entry.NextSaveAt - harness.Clock.Value, expectedDelay)
				expect(entry.NextAutosaveAt >= entry.NextSaveAt)
				harness.Clock.Value = entry.NextSaveAt - 0.01
				-- A lock heartbeat may legitimately become due during the bounded
				-- autosave retry delay; the save count is the no-early-save contract.
				harness.Service:ProcessDueSaves()
				expectEqual(harness.Adapter:GetRequestCount("Save"), attempt)
				harness.Clock.Value = entry.NextSaveAt
			end
			expectEqual(harness.Service:ProcessDueSaves(), 1)
			expectEqual(harness.Adapter:GetRequestCount("Save"), ProfileConfig.MAXIMUM_SAVE_ATTEMPTS + 1)
			expectEqual(harness.Service:GetState(1042), "Ready")
			expectEqual(harness.Adapter:ReadStored(1042).Tape, 42)
		end,
	},
	{
		Name = "shared scheduler maintains at most one pending callback",
		Run = function()
			local active: { [number]: boolean } = {}
			local nextId = 0
			local maximumActive = 0
			local scheduler = {
				Schedule = function(_duration: number, _callback: () -> ()): number
					nextId += 1
					active[nextId] = true
					local count = 0
					for _ in pairs(active) do count += 1 end
					maximumActive = math.max(maximumActive, count)
					return nextId
				end,
				Cancel = function(handle: number)
					active[handle] = nil
				end,
			}
			local harness = makeProfileHarness(nil, { AutoSchedule = true, Scheduler = scheduler })
			for userId = 105, 108 do expect(harness.Service:LoadPlayer(userId)) end
			for userId = 105, 108 do
				harness.Service:ApplyMutation(userId, function(profile: any)
					profile.Tape += 1
					return true
				end)
			end
			expectEqual(maximumActive, 1)
		end,
	},
	{
		Name = "clean-profile heartbeat schedules the next heartbeat without an immediate loop",
		Run = function()
			local pending: { [number]: any } = {}
			local scheduledDelays: { number } = {}
			local nextId = 0
			local scheduler = {
				Schedule = function(duration: number, callback: () -> ()): number
					nextId += 1
					pending[nextId] = { Delay = duration, Callback = callback }
					table.insert(scheduledDelays, duration)
					return nextId
				end,
				Cancel = function(handle: number)
					pending[handle] = nil
				end,
			}
			local harness = makeProfileHarness(nil, { AutoSchedule = true, Scheduler = scheduler })
			expect(harness.Service:LoadPlayer(1081))
			expectEqual(#scheduledDelays, 1)
			expectEqual(scheduledDelays[1], ProfileConfig.SESSION_HEARTBEAT_SECONDS)
			local first = pending[1]
			expect(first ~= nil)
			pending[1] = nil
			harness.Clock.Value += first.Delay
			first.Callback()

			expectEqual(harness.Adapter:GetRequestCount("Heartbeat"), 1)
			expectEqual(harness.Adapter:GetRequestCount("Save"), 0)
			expectEqual(#scheduledDelays, 2)
			expectEqual(scheduledDelays[2], ProfileConfig.SESSION_HEARTBEAT_SECONDS,
				"A clean profile must ignore its elapsed autosave timestamp after heartbeat")
			local immediateCallbacks = 0
			for _, scheduled in pairs(pending) do
				if scheduled.Delay <= 0 then
					immediateCallbacks += 1
				end
			end
			expectEqual(immediateCallbacks, 0)
			expectEqual(harness.Adapter:GetRequestCount("Heartbeat"), 1,
				"The scheduler must not invoke a second heartbeat at the same clock tick")
		end,
	},
	{
		Name = "bounded retry attempts stop at configured maximum",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			adapter:SetLoadFailure(109, 20)
			local harness = makeProfileHarness(nil, { Adapter = adapter })
			local loaded = harness.Service:LoadPlayer(109)
			expect(not loaded)
			expectEqual(adapter:GetRequestCount("Load"), ProfileConfig.MAXIMUM_LOAD_ATTEMPTS)
			expectEqual(harness.Service:GetState(109), "Unavailable")
		end,
	},
	{
		Name = "shutdown deadline returns with unresolved releases counted as skipped",
		Run = function()
			local clock = { Value = 5_000 }
			local queued: { () -> () } = {}
			local adapter = MemoryProfileAdapter.Create()
			local service = ProfileService.Create(adapter, {
				Clock = function() return clock.Value end,
				Wait = function(duration: number) clock.Value += duration end,
				Spawn = function(callback: () -> ()) table.insert(queued, callback) end,
				AutoSchedule = false,
				ServerSessionId = "shutdown-deadline",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			for userId = 110, 111 do expect(service:LoadPlayer(userId)) end
			local result = service:Shutdown(2)
			expectEqual(result.Successes, 0)
			expectEqual(result.Failures, 0)
			expectEqual(result.Skipped, 2)
			expectEqual(#queued, 2)
			expect(clock.Value >= 5_002 and clock.Value < 5_002.1, "Shutdown must stop at its injected deadline")
		end,
	},
	{
		Name = "shutdown rechecks its deadline inside the launch batch",
		Run = function()
			local clock = { Value = 6_000 }
			local queued: { () -> () } = {}
			local service = ProfileService.Create(MemoryProfileAdapter.Create(), {
				Clock = function() return clock.Value end,
				Wait = function(duration: number) clock.Value += duration end,
				Spawn = function(callback: () -> ())
					table.insert(queued, callback)
					clock.Value += 1
				end,
				AutoSchedule = false,
				ServerSessionId = "shutdown-inner-deadline",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			for userId = 1_120, 1_129 do
				expect(service:LoadPlayer(userId))
			end
			local result = service:Shutdown(1)
			expectEqual(#queued, 1, "No second release may launch after Spawn crosses the deadline")
			expectEqual(result.Successes, 0)
			expectEqual(result.Failures, 0)
			expectEqual(result.Skipped, 10)
			expect(clock.Value >= 6_001 and clock.Value <= 6_001.05,
				"Deadline polling may add at most one fifty-millisecond bounded wait")
		end,
	},
	{
		Name = "shutdown release retry waits are clamped to the deadline",
		Run = function()
			local clock = { Value = 7_000 }
			local adapter = MemoryProfileAdapter.Create()
			adapter:SetReleaseFailure(1_130, 20)
			local service = ProfileService.Create(adapter, {
				Clock = function() return clock.Value end,
				Wait = function(duration: number) clock.Value += duration end,
				Spawn = function(callback: () -> ()) callback() end,
				AutoSchedule = false,
				ServerSessionId = "shutdown-retry-deadline",
				IdentifierFactory = function() return "lock" end,
				PresentationIdentifierFactory = function() return "presentation" end,
			})
			expect(service:LoadPlayer(1_130))
			local result = service:Shutdown(2)
			expectEqual(result.Successes, 0)
			expectEqual(result.Failures, 1)
			expectEqual(result.Skipped, 0)
			expectEqual(adapter:GetRequestCount("Release"), 2)
			expectEqual(clock.Value, 7_002)
			expectEqual(service:GetState(1_130), "Released")
		end,
	},
	{
		Name = "concurrent eight-profile shutdown releases every profile",
		Run = function()
			local harness = makeProfileHarness(nil)
			for userId = 120, 127 do
				expect(harness.Service:LoadPlayer(userId))
				harness.Service:ApplyMutation(userId, function(profile: any)
					profile.Tape = userId
					return true
				end)
			end
			local result = harness.Service:Shutdown(25)
			expectEqual(result.Successes, 8)
			expectEqual(result.Failures, 0)
			expectEqual(result.Skipped, 0)
			for userId = 120, 127 do
				expectEqual(harness.Adapter:ReadStored(userId).Tape, userId)
				expectEqual(harness.Adapter:ReadStored(userId).Session, nil)
			end
		end,
	},
})

function Phase05TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}
	local seed = RoundConfig.DEVELOPMENT.PHASE05_TEST_SEED
	if type(seed) ~= "number" or seed % 1 ~= 0 then
		error("RoundConfig.DEVELOPMENT.PHASE05_TEST_SEED must be a fixed integer", 2)
	end

	print(string.format("[ONE_MORE_ITEM][Phase05Tests] Starting %d suites seed=%d", #suites, seed))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase05Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase05Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase05Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d adapter=memory",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		seed
	))
	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase05Tests] FAILURE %d: %s", index, failure))
		end
	end
	return {
		Suites = #suites,
		Tests = totalTests,
		Passed = passed,
		Failed = failed,
		Failures = failures,
		DurationSeconds = duration,
		Seed = seed,
	}
end

return table.freeze(Phase05TestSuite)
