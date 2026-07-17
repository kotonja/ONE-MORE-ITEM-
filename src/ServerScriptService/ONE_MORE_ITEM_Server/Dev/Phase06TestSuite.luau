--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local OnboardingDefinitions = require(Root.Shared.Profile.OnboardingDefinitions)
local StarterMissionDefinitions = require(Root.Shared.Profile.StarterMissionDefinitions)

local Services = script.Parent.Parent:WaitForChild("Services")
local ProfileServices = Services:WaitForChild("Profile")
local AnalyticsServices = Services:WaitForChild("Analytics")
local MemoryProfileAdapter = require(ProfileServices:WaitForChild("MemoryProfileAdapter"))
local OnboardingService = require(ProfileServices:WaitForChild("OnboardingService"))
local ProfileConfig = require(ProfileServices:WaitForChild("ProfileConfig"))
local ProfileSchema = require(ProfileServices:WaitForChild("ProfileSchema"))
local ProfileService = require(ProfileServices:WaitForChild("ProfileService"))
local ProfileSnapshotBuilder = require(ProfileServices:WaitForChild("ProfileSnapshotBuilder"))
local StarterMissionService = require(ProfileServices:WaitForChild("StarterMissionService"))
local OnboardingRequestValidator = require(Services:WaitForChild("OnboardingRequestValidator"))
local RoundService = require(Services:WaitForChild("RoundService"))
local AnalyticsEventDefinitions = require(AnalyticsServices:WaitForChild("AnalyticsEventDefinitions"))
local GameAnalyticsService = require(AnalyticsServices:WaitForChild("GameAnalyticsService"))
local MemoryAnalyticsAdapter = require(AnalyticsServices:WaitForChild("MemoryAnalyticsAdapter"))

local ClientControllers = StarterPlayer:WaitForChild("StarterPlayerScripts")
	:WaitForChild("ONE_MORE_ITEM_Client")
	:WaitForChild("Controllers")
local ClientProfileStore = require(ClientControllers:WaitForChild("ClientProfileStore"))
local OnboardingUIController = require(ClientControllers:WaitForChild("OnboardingUIController"))
local StarterMissionUIController = require(ClientControllers:WaitForChild("StarterMissionUIController"))

type TestCase = { Name: string, Run: () -> () }
type TestSuite = { Name: string, Tests: { TestCase } }

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	Seed: number,
}

type Harness = {
	Clock: { Value: number },
	Adapter: any,
	Service: any,
	Snapshots: { any },
	AnalyticsAdapter: any,
	Analytics: any,
}

local Phase06TestSuite = {}
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

local function fakePlayer(userId: number): Player
	return ({
		UserId = userId,
		Name = string.format("Player%d", userId),
		DisplayName = string.format("Player %d", userId),
	} :: any) :: Player
end

local function defaultProfile(now: number?): any
	return ProfileSchema.CreateDefault(now or 10_000)
end

local function makeHarness(userId: number?): Harness
	local clock = { Value = 10_000 }
	local snapshots: { any } = {}
	local identifier = 0
	local presentation = 0
	local adapter = MemoryProfileAdapter.Create()
	local service = ProfileService.Create(adapter, {
		Clock = function(): number return clock.Value end,
		Wait = function(duration: number) clock.Value += duration end,
		IdentifierFactory = function(): string
			identifier += 1
			return string.format("phase06-lock-%d", identifier)
		end,
		PresentationIdentifierFactory = function(): string
			presentation += 1
			return string.format("phase06-presentation-%d", presentation)
		end,
		Spawn = function(callback: () -> ()) callback() end,
		ServerSessionId = "phase06-test-server",
		JobId = "phase06-test-job",
		PlaceId = 134193642444044,
		AutoSchedule = false,
		SnapshotSink = function(_snapshotUserId: number, snapshot: any)
			table.insert(snapshots, snapshot)
		end,
	})
	if userId ~= nil then
		local loaded, code = service:LoadPlayer(userId)
		expect(loaded and code == "READY", "Profile harness must load")
	end
	local analyticsAdapter = MemoryAnalyticsAdapter.Create()
	local analytics = GameAnalyticsService.Create({ Adapter = analyticsAdapter, IsStudio = true })
	return {
		Clock = clock,
		Adapter = adapter,
		Service = service,
		Snapshots = snapshots,
		AnalyticsAdapter = analyticsAdapter,
		Analytics = analytics,
	}
end

local function completeMission(profile: any, eventName: any, itemCount: number?): any
	local changed, result, rewards, code = StarterMissionService.ApplyEventToProfile(
		profile,
		eventName,
		if itemCount ~= nil then { ItemCount = itemCount } else nil,
		10_000
	)
	expect(changed and code == "APPLIED")
	expect(result.Changed)
	expect(#rewards > 0)
	return result
end

local function makeTimingHarness(): (any, any, { any }, { Value: number }, { Value: boolean })
	local player = fakePlayer(199)
	local scheduled: { any } = {}
	local clock = { Value = 1_000 }
	local guided = { Value = true }
	local service = RoundService.Create({
		GetStationId = function(): string return "station_01" end,
	} :: any, {
		SpawnAcceptedPlacement = function() end,
		ClearPlayer = function() end,
	} :: any, {
		Clock = function(): number return clock.Value end,
		Scheduler = function(duration: number, callback: () -> ())
			table.insert(scheduled, { Duration = duration, Callback = callback })
		end,
		ProfileService = {
			CanEnterGameplay = function(): boolean return true end,
			CanMutate = function(): boolean return true end,
			GetTape = function(): number return 0 end,
		},
		ProgressionService = {
			ApplyShipment = function(): (any?, string) return nil, "UNUSED" end,
			ApplyFailure = function(): (any?, string) return nil, "UNUSED" end,
		},
		ServerSessionId = "phase06-timing",
		IsGuidedOnboarding = function(): boolean return guided.Value end,
	})
	return service, player, scheduled, clock, guided
end

addSuite("Schema Version 2", {
	{
		Name = "nil creates exact Version 2 independent defaults",
		Run = function()
			local left, code = ProfileSchema.Migrate(nil, 123)
			local right = ProfileSchema.CreateDefault(123)
			expect(left ~= nil and code == "CREATED_V2")
			expectEqual(left.SchemaVersion, 2)
			expectEqual(left.Onboarding.Status, "NotStarted")
			expectEqual(left.Onboarding.HighestStep, 0)
			expectEqual(left.StarterMissions.PathCompleted, false)
			expectEqual(left.Stats.TotalMissionTapeEarned, 0)
			expectEqual(left.Stats.TotalStarterMissionsCompleted, 0)
			left.Onboarding.HighestStep = 3
			left.StarterMissions.Progress.first_fit = 1
			expectEqual(right.Onboarding.HighestStep, 0)
			expectEqual(right.StarterMissions.Progress.first_fit, nil)
		end,
	},
	{
		Name = "Version 0 migrates through Version 1 into Version 2",
		Run = function()
			local profile, code = ProfileSchema.Migrate({
				SchemaVersion = 0,
				Tape = 44,
				PackingXP = 305,
				DiscoveredItems = { "parcel" },
				Mastery = { parcel = 3 },
			}, 500)
			expect(profile ~= nil and code == "MIGRATED_V0_TO_V2")
			expectEqual(profile.SchemaVersion, 2)
			expectEqual(profile.Tape, 44)
			expectEqual(profile.PackingXP, 305)
			expectEqual(profile.Collection.MasteryCounts.parcel, 3)
		end,
	},
	{
		Name = "Version 1 preserves every Phase 05 field and session ownership",
		Run = function()
			local raw = {
				SchemaVersion = 1,
				Tape = 501,
				PackingXP = 2_600,
				Stats = { TotalSuccessfulShipments = 7, TotalItemsShipped = 19, HighestItemsInShipment = 6,
					BestShipmentValue = 800, PerfectShipments = 1, TotalFailedRounds = 2, TotalTapeEarned = 501,
					TotalMissionTapeEarned = 9_999, TotalStarterMissionsCompleted = 9_999 },
				Collection = { Discovered = { parcel = true }, MasteryCounts = { parcel = 7 }, RecentDiscoveries = { "parcel" } },
				Receipts = { ProcessedOutcomeIds = { "receipt-a" } },
				CreatedAt = 100,
				UpdatedAt = 200,
				Session = { Token = "owned", JobId = "job", PlaceId = 134193642444044, AcquiredAt = 100, HeartbeatAt = 200 },
			}
			local profile, code = ProfileSchema.Migrate(raw, 300)
			expect(profile ~= nil and code == "MIGRATED_V1_TO_V2")
			expectEqual(profile.Tape, 501)
			expectEqual(profile.PackingXP, 2_600)
			expectEqual(profile.Stats.TotalSuccessfulShipments, 7)
			expectEqual(profile.Stats.TotalMissionTapeEarned, 0)
			expectEqual(profile.Stats.TotalStarterMissionsCompleted, 0)
			expectEqual(profile.Collection.MasteryCounts.parcel, 7)
			expectArray(profile.Receipts.ProcessedOutcomeIds, { "receipt-a" })
			expectEqual(profile.CreatedAt, 100)
			expectEqual(profile.UpdatedAt, 200)
			expectEqual(profile.Session.Token, "owned")
			expectEqual(profile.Onboarding.Status, "NotStarted")
			expectEqual(profile.StarterMissions.PathCompleted, false)
		end,
	},
	{
		Name = "malformed Version 2 normalizes bounded onboarding and missions",
		Run = function()
			local profile, code = ProfileSchema.Migrate({
				SchemaVersion = 2,
				Onboarding = { Status = "Exploit", HighestStep = 99, CompletedAt = -1 },
				StarterMissions = {
					Progress = { first_fit = 99, exploit = 99 },
					Completed = { exploit = true },
					Rewarded = { first_shipment = true, exploit = true },
				},
			}, 900)
			expect(profile ~= nil and code == "NORMALIZED_V2")
			expectEqual(profile.Onboarding.Status, "NotStarted")
			expectEqual(profile.Onboarding.HighestStep, 0)
			expectEqual(profile.StarterMissions.Progress.first_fit, 1)
			expectEqual(profile.StarterMissions.Progress.exploit, nil)
			expectEqual(profile.StarterMissions.Rewarded.first_shipment, true)
			expectEqual(profile.StarterMissions.Completed.first_shipment, true)
			expectEqual(profile.StarterMissions.PathCompleted, false)
		end,
	},
	{
		Name = "Version 2 onboarding normalization preserves reachable status invariants",
		Run = function()
			local fixtures = {
				{ InputStatus = "NotStarted", InputStep = 1, ExpectedStatus = "InProgress", ExpectedStep = 1 },
				{ InputStatus = "InProgress", InputStep = 4, ExpectedStatus = "InProgress", ExpectedStep = 4 },
				{ InputStatus = "NotStarted", InputStep = 5, ExpectedStatus = "Completed", ExpectedStep = 5 },
				{ InputStatus = "InProgress", InputStep = 5, ExpectedStatus = "Completed", ExpectedStep = 5 },
				{ InputStatus = "InProgress", InputStep = 0, ExpectedStatus = "NotStarted", ExpectedStep = 0 },
			}
			for _, fixture in ipairs(fixtures) do
				local profile, code = ProfileSchema.Migrate({
					SchemaVersion = 2,
					Onboarding = { Status = fixture.InputStatus, HighestStep = fixture.InputStep },
				}, 901)
				expect(profile ~= nil and code == "NORMALIZED_V2")
				expectEqual(profile.Onboarding.Status, fixture.ExpectedStatus)
				expectEqual(profile.Onboarding.HighestStep, fixture.ExpectedStep)
			end
		end,
	},
	{
		Name = "completed onboarding and fully rewarded path derive terminal bounds",
		Run = function()
			local rewarded = {}
			for _, id in ipairs(StarterMissionDefinitions.OrderedMissionIds) do rewarded[id] = true end
			local profile = ProfileSchema.Migrate({
				SchemaVersion = 2,
				Onboarding = { Status = "Completed", HighestStep = 2, CompletedAt = 55 },
				StarterMissions = { Rewarded = rewarded, CompletedAt = 77 },
			}, 100)
			expectEqual(profile.Onboarding.HighestStep, 5)
			expectEqual(profile.Onboarding.CompletedAt, 55)
			expectEqual(profile.StarterMissions.PathCompleted, true)
			expectEqual(profile.StarterMissions.CompletedAt, 77)
		end,
	},
	{
		Name = "migration is deterministic nonmutating and future-safe",
		Run = function()
			local raw = { SchemaVersion = 2, Tape = -4, Onboarding = { Status = "Skipped", HighestStep = 3 } }
			local left = ProfileSchema.Migrate(raw, 500)
			local right = ProfileSchema.Migrate(raw, 500)
			expectEqual(left.Tape, right.Tape)
			expectEqual(left.Onboarding.Status, right.Onboarding.Status)
			expectEqual(raw.Tape, -4)
			expectEqual(raw.Onboarding.HighestStep, 3)
			local future, code = ProfileSchema.Migrate({ SchemaVersion = 3 }, 500)
			expectEqual(future, nil)
			expectEqual(code, "UNSUPPORTED_FUTURE_SCHEMA")
		end,
	},
})

addSuite("Onboarding definitions", {
	{
		Name = "five immutable stable steps use unique consecutive numbers and names",
		Run = function()
			expectEqual(OnboardingDefinitions.TotalCount, 5)
			expectFrozen(OnboardingDefinitions.Ordered)
			local expected = { "PROFILE READY", "STATION ASSIGNED", "FIRST ITEM PLACED", "FIRST DECISION SHOWN", "FIRST SHIPMENT COMPLETED" }
			for index, name in ipairs(expected) do
				local step = OnboardingDefinitions.GetStep(index)
				expectEqual(step.Number, index)
				expectEqual(step.Name, name)
				expectEqual(OnboardingDefinitions.GetStepName(index), name)
			end
		end,
	},
	{
		Name = "next-step bounds and terminal states are exact",
		Run = function()
			expectEqual(OnboardingDefinitions.GetNextStep(0), 1)
			expectEqual(OnboardingDefinitions.GetNextStep(4), 5)
			expectEqual(OnboardingDefinitions.GetNextStep(5), nil)
			expectEqual(OnboardingDefinitions.GetStep(0), nil)
			expectEqual(OnboardingDefinitions.GetStep(6), nil)
			expect(OnboardingDefinitions.IsTerminal("Completed"))
			expect(OnboardingDefinitions.IsTerminal("Skipped"))
			expect(not OnboardingDefinitions.IsTerminal("InProgress"))
			expectEqual(OnboardingDefinitions.NormalizeStatus("unknown"), "NotStarted")
		end,
	},
})

addSuite("Onboarding service", {
	{
		Name = "progression is monotonic duplicate-safe and Step 5 completes",
		Run = function()
			local profile = defaultProfile()
			local changed, first = OnboardingService.ApplyStepToProfile(profile, 1, 10)
			expect(changed and first.Changed)
			expectEqual(first.PreviousStatus, "NotStarted")
			expectEqual(first.NewStatus, "InProgress")
			local duplicate, duplicateResult = OnboardingService.ApplyStepToProfile(profile, 1, 11)
			expect(not duplicate and not duplicateResult.Changed)
			local lower = OnboardingService.ApplyStepToProfile(profile, 0, 11)
			expect(not lower)
			local completed, result = OnboardingService.ApplyStepToProfile(profile, 5, 25)
			expect(completed and result.Completed)
			expectEqual(profile.Onboarding.CompletedAt, 25)
		end,
	},
	{
		Name = "skip is terminal distinct and grants no reward",
		Run = function()
			local profile = defaultProfile()
			profile.Tape = 80
			profile.PackingXP = 90
			OnboardingService.ApplyStepToProfile(profile, 3, 10)
			local changed, result = OnboardingService.ApplySkipToProfile(profile)
			expect(changed and result.Skipped)
			expectEqual(profile.Tape, 80)
			expectEqual(profile.PackingXP, 90)
			local completeAfterSkip = OnboardingService.ApplyStepToProfile(profile, 5, 20)
			expect(not completeAfterSkip)
			local skipAgain = OnboardingService.ApplySkipToProfile(profile)
			expect(not skipAgain)
		end,
	},
	{
		Name = "snapshot publishes before analytics and duplicate steps log nothing",
		Run = function()
			local harness = makeHarness(201)
			local order: { string } = {}
			harness.Service._snapshotSink = function(_userId: number, _snapshot: any) table.insert(order, "snapshot") end
			local analytics = {
				LogOnboardingStep = function(_self: any, _player: Player, _step: number): boolean table.insert(order, "analytics"); return true end,
				LogOnboardingSkipped = function(): boolean return true end,
			}
			local service = OnboardingService.Create(harness.Service, analytics :: any, { Clock = function() return 50 end })
			local result = service:Advance(fakePlayer(201), 1)
			expect(result ~= nil and result.Changed)
			expectArray(order, { "snapshot", "analytics" })
			table.clear(order)
			local duplicate = service:Advance(fakePlayer(201), 1)
			expect(duplicate ~= nil and not duplicate.Changed)
			expectEqual(#order, 0)
		end,
	},
	{
		Name = "analytics failure never undoes onboarding and conflict blocks mutation",
		Run = function()
			local harness = makeHarness(202)
			local brokenAnalytics = {
				LogOnboardingStep = function() error("injected analytics failure") end,
				LogOnboardingSkipped = function() error("injected analytics failure") end,
			}
			local service = OnboardingService.Create(harness.Service, brokenAnalytics :: any, { Clock = function() return 60 end })
			local applied = service:Advance(fakePlayer(202), 2)
			expect(applied ~= nil and applied.Changed)
			expectEqual(harness.Service:GetProfileCopy(202).Onboarding.HighestStep, 2)
			harness.Adapter:ForceSession(202, { Token = "other", JobId = "other", PlaceId = 1, AcquiredAt = 1, HeartbeatAt = 9_999 })
			harness.Service:SaveNow(202)
			local blocked, code = service:Advance(fakePlayer(202), 3)
			expectEqual(blocked, nil)
			expectEqual(code, "PROFILE_NOT_MUTABLE")
		end,
	},
})

addSuite("Guided timing", {
	{
		Name = "guided and normal durations are exact",
		Run = function()
			expectEqual(RoundConfig.GUIDED_PLACEMENT_DURATION, 45)
			expectEqual(RoundConfig.GUIDED_DECISION_DURATION, 12)
			expect(RoundConfig.PLACEMENT_DURATION ~= RoundConfig.GUIDED_PLACEMENT_DURATION)
			expect(RoundConfig.DECISION_DURATION ~= RoundConfig.GUIDED_DECISION_DURATION)
		end,
	},
	{
		Name = "current round retains its guided decision while subsequent rounds use normal timing",
		Run = function()
			local service, player, scheduled, clock, guided = makeTimingHarness()
			local first = service:StartRound(player)
			expect(first ~= nil and first.GuidedOnboarding)
			guided.Value = false
			service:_enterAwaitingPlacement(player)
			expectEqual(scheduled[#scheduled].Duration, 45)
			expectEqual(service:GetRound(player).PlacementDeadline, clock.Value + 45)
			expectEqual(service:GetSnapshot(player).GuidedOnboarding, true)
			service:RemovePlayer(player)
			local second = service:StartRound(player)
			expect(second ~= nil and not second.GuidedOnboarding)
			service:_enterAwaitingPlacement(player)
			expectEqual(scheduled[#scheduled].Duration, RoundConfig.PLACEMENT_DURATION)
			expectEqual(service:GetSnapshot(player).GuidedOnboarding, false)
		end,
	},
	{
		Name = "only incomplete non-skipped profiles are guided",
		Run = function()
			local harness = makeHarness(203)
			local service = OnboardingService.Create(harness.Service, harness.Analytics)
			local player = fakePlayer(203)
			expect(service:IsGuided(player))
			service:Advance(player, 5)
			expect(not service:IsGuided(player))
			local skippedHarness = makeHarness(204)
			local skipped = OnboardingService.Create(skippedHarness.Service, skippedHarness.Analytics)
			skipped:Skip(fakePlayer(204))
			expect(not skipped:IsGuided(fakePlayer(204)))
		end,
	},
})

addSuite("Mission definitions", {
	{
		Name = "exactly five frozen missions have stable IDs goals and rewards",
		Run = function()
			expectEqual(StarterMissionDefinitions.TotalCount, 5)
			expectFrozen(StarterMissionDefinitions.Ordered)
			local ids = { "first_fit", "first_shipment", "one_more", "collector_three", "five_item_box" }
			local goals = { 1, 1, 1, 3, 5 }
			local tape = { 10, 25, 35, 75, 150 }
			local xp = { 10, 20, 30, 50, 100 }
			for index, id in ipairs(ids) do
				local definition = StarterMissionDefinitions.Get(id)
				expectEqual(definition.Index, index)
				expectEqual(definition.Goal, goals[index])
				expectEqual(definition.Reward.Tape, tape[index])
				expectEqual(definition.Reward.PackingXP, xp[index])
				expectFrozen(definition)
			end
			expectEqual(StarterMissionDefinitions.TotalTapeReward, 295)
			expectEqual(StarterMissionDefinitions.TotalXPReward, 210)
		end,
	},
	{
		Name = "pure lookup and first-incomplete APIs reject invalid IDs",
		Run = function()
			expectEqual(StarterMissionDefinitions.GetIndex("one_more"), 3)
			expectEqual(StarterMissionDefinitions.GetGoal("collector_three"), 3)
			expectEqual(StarterMissionDefinitions.GetTotalCount(), 5)
			expectEqual(StarterMissionDefinitions.Get("exploit"), nil)
			expect(not StarterMissionDefinitions.IsValidMissionId("exploit"))
			expectEqual(StarterMissionDefinitions.GetFirstIncomplete({ first_fit = true }).Id, "first_shipment")
		end,
	},
})

addSuite("Mission progress", {
	{
		Name = "authoritative placement shipment and One More events update only relevant missions",
		Run = function()
			local profile = defaultProfile()
			completeMission(profile, "AcceptedPlacement", nil)
			expectEqual(profile.StarterMissions.Progress.first_fit, 1)
			expectEqual(profile.StarterMissions.Progress.one_more, nil)
			completeMission(profile, "OneMoreAccepted", nil)
			expectEqual(profile.StarterMissions.Progress.one_more, 1)
			profile.Stats.TotalSuccessfulShipments = 1
			completeMission(profile, "SuccessfulShipment", 1)
			expectEqual(profile.StarterMissions.Progress.first_shipment, 1)
		end,
	},
	{
		Name = "collector and five-item missions reconcile from canonical statistics",
		Run = function()
			local profile = defaultProfile()
			profile.Stats.TotalSuccessfulShipments = 2
			profile.Stats.HighestItemsInShipment = 5
			profile.Collection.Discovered.parcel = true
			profile.Collection.Discovered.long_package = true
			profile.Collection.Discovered.chair_blockout = true
			local changed, result = StarterMissionService.ApplyEventToProfile(profile, "ProfileReconcile", nil, 100)
			expect(changed and result.Changed)
			expectEqual(profile.StarterMissions.Progress.first_shipment, 1)
			expectEqual(profile.StarterMissions.Progress.collector_three, 3)
			expectEqual(profile.StarterMissions.Progress.five_item_box, 5)
			expectEqual(profile.StarterMissions.Progress.one_more, nil)
		end,
	},
	{
		Name = "progress caps at goals and duplicate callbacks no-op",
		Run = function()
			local profile = defaultProfile()
			completeMission(profile, "AcceptedPlacement", nil)
			local tape = profile.Tape
			local changed, result, rewards, code = StarterMissionService.ApplyEventToProfile(profile, "AcceptedPlacement", nil, 101)
			expect(not changed and not result.Changed and code == "NO_CHANGE")
			expectEqual(#rewards, 0)
			expectEqual(profile.StarterMissions.Progress.first_fit, 1)
			expectEqual(profile.Tape, tape)
		end,
	},
	{
		Name = "invalid event data is rejected atomically",
		Run = function()
			local profile = defaultProfile()
			local changed, _, _, code = StarterMissionService.ApplyEventToProfile(profile, "SuccessfulShipment", { ItemCount = math.huge }, 100)
			expect(not changed)
			expectEqual(code, "INVALID_EVENT_DATA")
			expectEqual(profile.Tape, 0)
		end,
	},
})

addSuite("Mission rewards", {
	{
		Name = "each exact reward is automatic deterministic and exact-once",
		Run = function()
			local profile = defaultProfile()
			local result = completeMission(profile, "AcceptedPlacement", nil)
			local reward = result.Rewards[1]
			expectEqual(reward.RewardId, "starter:v1:first_fit")
			expectEqual(reward.TapeDelta, 10)
			expectEqual(reward.XPDelta, 10)
			expectEqual(profile.Tape, 10)
			expectEqual(profile.PackingXP, 10)
			expectEqual(profile.Stats.TotalTapeEarned, 10)
			expectEqual(profile.Stats.TotalMissionTapeEarned, 10)
			expectEqual(profile.Stats.TotalStarterMissionsCompleted, 1)
		end,
	},
	{
		Name = "multiple completions reward in definition order",
		Run = function()
			local profile = defaultProfile()
			profile.Stats.TotalSuccessfulShipments = 1
			profile.Stats.HighestItemsInShipment = 5
			for _, id in ipairs({ "parcel", "long_package", "chair_blockout" }) do profile.Collection.Discovered[id] = true end
			local result = completeMission(profile, "SuccessfulShipment", 5)
			local ids = {}
			for _, reward in ipairs(result.Rewards) do table.insert(ids, reward.MissionId) end
			expectArray(ids, { "first_shipment", "collector_three", "five_item_box" })
			expectEqual(profile.Tape, 250)
			expectEqual(profile.PackingXP, 170)
		end,
	},
	{
		Name = "full starter path totals are 295 Tape 210 XP with no extra reward",
		Run = function()
			local profile = defaultProfile()
			completeMission(profile, "AcceptedPlacement", nil)
			completeMission(profile, "OneMoreAccepted", nil)
			profile.Stats.TotalSuccessfulShipments = 1
			profile.Stats.HighestItemsInShipment = 5
			for _, id in ipairs({ "parcel", "long_package", "chair_blockout" }) do profile.Collection.Discovered[id] = true end
			local final = completeMission(profile, "SuccessfulShipment", 5)
			expect(final.PathJustCompleted)
			expectEqual(profile.Tape, 295)
			expectEqual(profile.PackingXP, 210)
			expectEqual(profile.Stats.TotalMissionTapeEarned, 295)
			expectEqual(profile.Stats.TotalStarterMissionsCompleted, 5)
			expectEqual(profile.StarterMissions.PathCompleted, true)
			expectEqual(profile.StarterMissions.CompletedAt, 10_000)
		end,
	},
	{
		Name = "rank transition is derived and reward overflow is atomic",
		Run = function()
			local profile = defaultProfile()
			profile.PackingXP = 295
			local result = completeMission(profile, "AcceptedPlacement", nil)
			expectEqual(result.Rewards[1].PreviousRank.Index, 1)
			expectEqual(result.Rewards[1].NewRank.Index, 2)
			local overflow = defaultProfile()
			overflow.Tape = ProfileConfig.MAXIMUM_SAFE_INTEGER
			local changed, _, rewards, code = StarterMissionService.ApplyEventToProfile(overflow, "AcceptedPlacement", nil, 100)
			expect(not changed and code == "REWARD_OVERFLOW")
			expectEqual(#rewards, 0)
			expectEqual(overflow.Tape, ProfileConfig.MAXIMUM_SAFE_INTEGER)
			expectEqual(overflow.StarterMissions.Rewarded.first_fit, nil)
		end,
	},
})

addSuite("Profile snapshot", {
	{
		Name = "snapshot copies safe onboarding mission and reward fields",
		Run = function()
			local profile = defaultProfile()
			profile.Onboarding.Status = "InProgress"
			profile.Onboarding.HighestStep = 3
			local result = completeMission(profile, "AcceptedPlacement", nil)
			local snapshot = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 4, "profile:phase06", nil, result.Rewards)
			expectEqual(snapshot.SchemaVersion, 2)
			expectEqual(snapshot.Onboarding.Status, "InProgress")
			expectEqual(snapshot.Onboarding.HighestStep, 3)
			expectEqual(snapshot.StarterMissions.CurrentMissionId, "first_shipment")
			expectArray(snapshot.StarterMissions.CompletedMissionIds, { "first_fit" })
			expectArray(snapshot.StarterMissions.RewardedMissionIds, { "first_fit" })
			expectEqual(snapshot.LastMissionRewards[1].RewardId, "starter:v1:first_fit")
			expectFrozen(snapshot)
		end,
	},
	{
		Name = "snapshot has no lock receipts analytics or mutable profile reference",
		Run = function()
			local profile = defaultProfile()
			profile.Session = { Token = "secret", JobId = "job", PlaceId = 1, AcquiredAt = 1, HeartbeatAt = 1 }
			table.insert(profile.Receipts.ProcessedOutcomeIds, "secret-receipt")
			local snapshot = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 1, "safe", nil, nil)
			expectEqual((snapshot :: any).Session, nil)
			expectEqual((snapshot :: any).Receipts, nil)
			expectEqual((snapshot :: any).Analytics, nil)
			profile.Onboarding.HighestStep = 5
			expectEqual(snapshot.Onboarding.HighestStep, 0)
		end,
	},
	{
		Name = "save snapshots may repeat a copied batch and new sessions start empty",
		Run = function()
			local profile = defaultProfile()
			local result = completeMission(profile, "AcceptedPlacement", nil)
			local first = ProfileSnapshotBuilder.Build(profile, "Saving", "Saving", 1, "one", nil, result.Rewards)
			local second = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 2, "one", nil, result.Rewards)
			local rejoin = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 1, "two", nil, nil)
			expectEqual(first.LastMissionRewards[1].RewardId, second.LastMissionRewards[1].RewardId)
			expectEqual(#rejoin.LastMissionRewards, 0)
		end,
	},
})

addSuite("Client mission presentation", {
	{
		Name = "onboarding copy adapts without cross-device labels and terminal states hide",
		Run = function()
			local keyboard = OnboardingUIController.CopyForMode("KeyboardMouse", "ValidFit")
			local touch = OnboardingUIController.CopyForMode("Touch", "Move")
			local gamepad = OnboardingUIController.CopyForMode("Gamepad", "Decision")
			expectEqual(keyboard.InputHint, "PRESS SPACE")
			expect(string.find(touch.InputHint, "WASD", 1, true) == nil)
			expect(string.find(gamepad.InputHint, "TAP", 1, true) == nil)
			expectFrozen(keyboard)
			expect(OnboardingUIController.ShouldShow("NotStarted"))
			expect(not OnboardingUIController.ShouldShow("Completed"))
			expect(not OnboardingUIController.ShouldShow("Skipped"))
		end,
	},
	{
		Name = "failed Results preserve failure guidance while successful Results show shipment guidance",
		Run = function()
			expectEqual(OnboardingUIController.ResolveStage("Failing", true, 0, "PLACEMENT_TIMEOUT", nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "PLACEMENT_TIMEOUT", nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 25, nil, nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "PROFILE_REWARD_FAILED", nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "SHIPMENT_RECORD_FAILED", nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "DUPLICATE_OUTCOME", nil, false), "Failure")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "PLAYER_SHIPPED", nil, false), "Shipment")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "DECISION_TIMEOUT", nil, false), "Shipment")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "BOX_FULL", nil, false), "Shipment")
			expectEqual(OnboardingUIController.ResolveStage("Results", true, 0, "MAX_ITEMS", nil, false), "Shipment")
			expectEqual(OnboardingUIController.ResolveStage("Shipping", true, 0, "PLAYER_SHIPPED", nil, false), "Shipment")
			expectEqual(OnboardingUIController.ResolveStage("AwaitingPlacement", true, 0, nil, true, false), "ValidFit")
			expectEqual(OnboardingUIController.ResolveStage("AwaitingPlacement", true, 0, nil, true, true), "Move")
			expectEqual(OnboardingUIController.ResolveStage("Results", false, 0, "PLACEMENT_TIMEOUT", nil, false), "Move")
		end,
	},
	{
		Name = "starter panel is allowed only in safe profile and round states",
		Run = function()
			expect(StarterMissionUIController.PanelAllowed("Ready", false, nil))
			expect(StarterMissionUIController.PanelAllowed("Saving", true, "Results"))
			expect(not StarterMissionUIController.PanelAllowed("Ready", true, "AwaitingPlacement"))
			expect(not StarterMissionUIController.PanelAllowed("Conflict", false, nil))
			expect(not StarterMissionUIController.PanelAllowed("Loading", false, nil))
		end,
	},
	{
		Name = "new mission rewards deduplicate and queue in definition order",
		Run = function()
			local profile = defaultProfile()
			profile.Stats.TotalSuccessfulShipments = 1
			profile.Stats.HighestItemsInShipment = 5
			for _, id in ipairs({ "parcel", "long_package", "chair_blockout" }) do profile.Collection.Discovered[id] = true end
			local result = completeMission(profile, "SuccessfulShipment", 5)
			local reversed = { result.Rewards[3], result.Rewards[1], result.Rewards[2] }
			local sorted = StarterMissionUIController.SortedNewRewards(reversed, {
				["starter:v1:collector_three"] = true,
			})
			expectArray({ sorted[1].MissionId, sorted[2].MissionId }, { "first_shipment", "five_item_box" })
		end,
	},
	{
		Name = "path progress uses authoritative completed and rewarded counts rather than mission index",
		Run = function()
			local completed, total = StarterMissionUIController.PathProgress(1, 4, 5)
			expectEqual(completed, 4)
			expectEqual(total, 5)
			local capped = StarterMissionUIController.PathProgress(99, 2, 5)
			expectEqual(capped, 5)
		end,
	},
	{
		Name = "client store rejects stale revisions and resets on new profile session",
		Run = function()
			local store = ClientProfileStore.new()
			local profile = defaultProfile()
			local first = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 2, "session-a", nil, nil)
			local stale = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 1, "session-a", nil, nil)
			local rejoin = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 1, "session-b", nil, nil)
			expect(store:ApplySnapshot(first))
			expect(not store:ApplySnapshot(stale))
			expect(store:ApplySnapshot(rejoin))
			expectEqual(store:GetSnapshot().ProfileSessionId, "session-b")
			store:Destroy()
		end,
	},
	{
		Name = "client store deep copies onboarding missions and reward batches",
		Run = function()
			local store = ClientProfileStore.new()
			local profile = defaultProfile()
			local result = completeMission(profile, "AcceptedPlacement", nil)
			local snapshot = ProfileSnapshotBuilder.Build(profile, "Ready", "Saved", 1, "copy", nil, result.Rewards)
			expect(store:ApplySnapshot(snapshot))
			local copied = store:GetSnapshot()
			expectEqual(copied.LastMissionRewards[1].RewardId, "starter:v1:first_fit")
			expectFrozen(copied.LastMissionRewards)
			expectFrozen(copied.StarterMissions.Progress)
			store:Destroy()
		end,
	},
	{
		Name = "permanent UI exists before Play with five authored mission rows",
		Run = function()
			local root = StarterGui:WaitForChild("ONE_MORE_ITEM_Gameplay"):WaitForChild("Root")
			expect(root:FindFirstChild("OnboardingOverlay") ~= nil)
			expect(root:FindFirstChild("StarterMissionCard") ~= nil)
			local panel = root:FindFirstChild("StarterPathPanel")
			expect(panel ~= nil)
			local missions = (panel :: Instance):FindFirstChild("Missions")
			expect(missions ~= nil)
			for index = 1, 5 do expect((missions :: Instance):FindFirstChild(string.format("Mission_%02d", index)) ~= nil) end
			expect(root:FindFirstChild("MissionCompleteBanner") ~= nil)
		end,
	},
})

addSuite("Analytics adapter", {
	{
		Name = "Studio selects deterministic memory and non-Studio fixture selects Roblox",
		Run = function()
			local studio = GameAnalyticsService.Create({ IsStudio = true })
			local published = GameAnalyticsService.Create({ IsStudio = false })
			expectEqual(studio:GetEnvironment(), "Memory")
			expectEqual(published:GetEnvironment(), "Roblox")
			studio:Destroy()
			published:Destroy()
		end,
	},
	{
		Name = "memory records deep copied immutable data and per-player filters",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local fields: any = { phase = "start" }
			adapter:LogCustom(fakePlayer(301), "CoreLoopRound", 1, fields)
			fields.phase = "fail"
			adapter:LogCustom(fakePlayer(302), "CoreLoopRound", 1, {})
			local records = adapter:GetRecords()
			expectEqual(records[1].Fields.phase, "start")
			expectFrozen(records[1])
			expectEqual(#adapter:GetRecordsForPlayer(301), 1)
			expectEqual(adapter:Count("Custom", "CoreLoopRound"), 2)
		end,
	},
	{
		Name = "failure injection returns safely and destroy clears records",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create({ FailureCount = 1 })
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			expect(not analytics:LogCoreLoopRound(fakePlayer(303), "start", 0, 0, nil))
			expect(analytics:LogCoreLoopRound(fakePlayer(303), "start", 0, 0, nil))
			expectEqual(adapter:Count(), 1)
			analytics:Destroy()
			expectEqual(adapter:Count(), 0)
		end,
	},
	{
		Name = "fixed fields are allowlisted and PII fields are discarded",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			expect(analytics:LogCustom(fakePlayer(304), "StarterMission", 1, {
				mission_id = "first_fit", status = "completed", UserId = 304, DisplayName = "secret", OutcomeId = "secret",
			}))
			local fields = adapter:GetRecords()[1].Fields
			expectEqual(fields.mission_id, "first_fit")
			expectEqual(fields.status, "completed")
			expectEqual((fields :: any).UserId, nil)
			expectEqual((fields :: any).DisplayName, nil)
			expectEqual((fields :: any).OutcomeId, nil)
			expect(not analytics:LogCustom(fakePlayer(304), "Dynamic304", 1, {}))
		end,
	},
	{
		Name = "economy sources retain approved source identity and authoritative ending balance",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			local player = fakePlayer(311)
			expect(analytics:LogEconomySource(player, "Shipment", 15, 115, "shipment"))
			expect(analytics:LogEconomySource(player, "StarterMission", 10, 125, "starter:first_fit"))
			local records = adapter:GetRecords()
			expectEqual(records[1].Name, "Shipment")
			expectEqual(records[1].Details.EndingBalance, 115)
			expectEqual(records[2].Name, "StarterMission")
			expectEqual(records[2].Details.ItemSku, "starter:first_fit")
			expect(not analytics:LogEconomySource(player, "ClientInvented", 999, 999, "bad"))
		end,
	},
})

addSuite("Onboarding analytics", {
	{
		Name = "durable steps log once in exact order with definition labels",
		Run = function()
			local harness = makeHarness(305)
			local onboarding = OnboardingService.Create(harness.Service, harness.Analytics, { Clock = function() return 100 end })
			local player = fakePlayer(305)
			for step = 1, 5 do onboarding:Advance(player, step) end
			onboarding:Advance(player, 5)
			local records = harness.AnalyticsAdapter:GetRecords()
			expectEqual(#records, 5)
			for index, record in ipairs(records) do
				expectEqual(record.Sequence, index)
				expectEqual(record.Kind, "Onboarding")
				expectEqual(record.Value, index)
				expectEqual(record.Name, OnboardingDefinitions.GetStepName(index))
			end
		end,
	},
	{
		Name = "skip logs once and completed profile does not replay",
		Run = function()
			local harness = makeHarness(306)
			local onboarding = OnboardingService.Create(harness.Service, harness.Analytics)
			local player = fakePlayer(306)
			onboarding:Advance(player, 1)
			onboarding:Skip(player)
			onboarding:Skip(player)
			expectEqual(harness.AnalyticsAdapter:Count("Custom", "OnboardingSkipped"), 1)
			expectEqual(harness.AnalyticsAdapter:Count("Onboarding"), 1)
		end,
	},
})

addSuite("Mission analytics", {
	{
		Name = "mission mutation snapshots before economy complete custom and next spotlight start",
		Run = function()
			local harness = makeHarness(307)
			local order: { string } = {}
			harness.Service._snapshotSink = function() table.insert(order, "snapshot") end
			local analytics = {
				LogProgressionStart = function() table.insert(order, "start"); return true end,
				LogStarterMission = function(_self: any, _player: Player, _id: string, status: string) table.insert(order, status); return true end,
				LogEconomySource = function() table.insert(order, "economy"); return true end,
				LogProgressionComplete = function() table.insert(order, "complete"); return true end,
			}
			local service = StarterMissionService.Create(harness.Service, analytics :: any)
			local result = service:ApplyEvent(fakePlayer(307), "AcceptedPlacement", nil)
			expect(result ~= nil and result.Changed)
			expectArray(order, { "snapshot", "economy", "complete", "completed", "start", "started" })
		end,
	},
	{
		Name = "duplicate mission event logs nothing and analytics failure changes no reward",
		Run = function()
			local harness = makeHarness(308)
			local service = StarterMissionService.Create(harness.Service, harness.Analytics)
			harness.AnalyticsAdapter:SetFailureCount(10)
			local applied = service:ApplyEvent(fakePlayer(308), "AcceptedPlacement", nil)
			expect(applied ~= nil and applied.Changed)
			expectEqual(harness.Service:GetProfileCopy(308).Tape, 10)
			local count = harness.AnalyticsAdapter:Count()
			local duplicate = service:ApplyEvent(fakePlayer(308), "AcceptedPlacement", nil)
			expect(duplicate ~= nil and not duplicate.Changed)
			expectEqual(harness.AnalyticsAdapter:Count(), count)
		end,
	},
})

addSuite("Core loop analytics", {
	{
		Name = "round start ship fail and One More use fixed values buckets and reasons",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			local player = fakePlayer(309)
			analytics:LogCoreLoopRound(player, "start", 99, 0, nil)
			analytics:LogCoreLoopRound(player, "ship", 12.9, 5, "PLAYER_SHIPPED")
			analytics:LogCoreLoopRound(player, "fail", math.huge, 10, "client text")
			analytics:LogOneMoreAccepted(player, 3, "TIGHT FIT")
			local records = adapter:GetRecords()
			expectEqual(records[1].Value, 1)
			expectEqual(records[2].Value, 12)
			expectEqual(records[2].Fields.item_count_bucket, "4-5")
			expectEqual(records[3].Value, 0)
			expectEqual(records[3].Fields.reason, "NONE")
			expectEqual(records[4].Name, "OneMoreAccepted")
			expectEqual(records[4].Fields.item_count_bucket, "2-3")
		end,
	},
	{
		Name = "session duration clamps and no per-move event is emitted",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			analytics:LogSessionDuration(fakePlayer(310), 999_999, true, false)
			local record = adapter:GetRecords()[1]
			expectEqual(record.Name, "SessionDuration")
			expectEqual(record.Value, AnalyticsEventDefinitions.MaximumDurationSeconds)
			expectEqual(record.Fields.profile_ready, true)
			expectEqual(record.Fields.station_assigned, false)
			expectEqual(adapter:Count(), 1)
		end,
	},
})

addSuite("Onboarding request security", {
	{
		Name = "only the one permanent onboarding request remote exists",
		Run = function()
			local folder = Root:FindFirstChild("OnboardingNet")
			expect(folder ~= nil and folder:IsA("Folder"))
			local children = (folder :: Folder):GetChildren()
			expectEqual(#children, 1)
			expect(children[1]:IsA("RemoteEvent"))
			expectEqual(children[1].Name, "OnboardingActionRequest")
		end,
	},
	{
		Name = "only exact SKIP with finite positive sequence is accepted",
		Run = function()
			expectEqual(RoundConfig.RATE_LIMITS_PER_SECOND.OnboardingActionRequest, 2)
			local validator = OnboardingRequestValidator.Create()
			expectEqual(validator:Validate(601, nil, true, "NotStarted", 1).Code, "MALFORMED_REQUEST")
			expectEqual(validator:Validate(602, { Action = "CLAIM", ClientSequence = 1 }, true, "NotStarted", 1).Code, "INVALID_ACTION")
			expectEqual(validator:Validate(603, { Action = "SKIP" }, true, "NotStarted", 1).Code, "INVALID_SEQUENCE")
			local accepted = validator:Validate(604, {
				Action = "SKIP", ClientSequence = 1, Tape = 9_999, XP = 9_999, MissionId = "exploit",
			}, true, "NotStarted", 1)
			expect(accepted.Accepted)
			expectEqual(accepted.Request.Action, "SKIP")
			expectEqual(accepted.Request.ClientSequence, 1)
			expectEqual((accepted.Request :: any).Tape, nil)
			expectEqual((accepted.Request :: any).XP, nil)
			expectEqual((accepted.Request :: any).MissionId, nil)
		end,
	},
	{
		Name = "accepted sequence is monotonic and profile terminal states block requests",
		Run = function()
			local validator = OnboardingRequestValidator.Create({ RateLimitPerSecond = 20 })
			local accepted = validator:Validate(605, { Action = "SKIP", ClientSequence = 4 }, true, "InProgress", 1)
			expect(accepted.Accepted)
			validator:MarkAccepted(605, 4)
			expectEqual(validator:Validate(605, { Action = "SKIP", ClientSequence = 4 }, true, "InProgress", 1.1).Code, "DUPLICATE_SEQUENCE")
			expectEqual(validator:Validate(605, { Action = "SKIP", ClientSequence = 3 }, true, "InProgress", 1.2).Code, "DUPLICATE_SEQUENCE")
			expectEqual(validator:Validate(606, { Action = "SKIP", ClientSequence = 1 }, false, "InProgress", 1).Code, "PROFILE_NOT_MUTABLE")
			expectEqual(validator:Validate(607, { Action = "SKIP", ClientSequence = 1 }, true, "Completed", 1).Code, "ONBOARDING_TERMINAL")
			expectEqual(validator:Validate(608, { Action = "SKIP", ClientSequence = 1 }, true, "Skipped", 1).Code, "ONBOARDING_TERMINAL")
		end,
	},
	{
		Name = "rate and warning limits are bounded and cleanup resets session state",
		Run = function()
			local validator = OnboardingRequestValidator.Create({ RateLimitPerSecond = 2, WarningThreshold = 10 })
			expect(validator:Validate(609, { Action = "SKIP", ClientSequence = 1 }, true, "NotStarted", 10).Accepted)
			expect(validator:Validate(609, { Action = "SKIP", ClientSequence = 2 }, true, "NotStarted", 10.1).Accepted)
			expectEqual(validator:Validate(609, { Action = "SKIP", ClientSequence = 3 }, true, "NotStarted", 10.2).Code, "RATE_LIMITED")
			local warningCount = 0
			for index = 4, 12 do
				local result = validator:Validate(609, { Action = "SKIP", ClientSequence = index }, true, "NotStarted", 20 + index)
				if result.ShouldWarn then warningCount += 1 end
			end
			expectEqual(warningCount, 1)
			validator:RemoveUser(609)
			local reset = validator:Validate(609, { Action = "SKIP", ClientSequence = 1 }, true, "NotStarted", 100)
			expect(reset.Accepted)
			expectEqual(reset.RequestCount, 1)
		end,
	},
	{
		Name = "skip mutation trusts no reward payload",
		Run = function()
			local profile = defaultProfile()
			profile.Tape = 45
			profile.PackingXP = 99
			local changed = OnboardingService.ApplySkipToProfile(profile)
			expect(changed)
			expectEqual(profile.Tape, 45)
			expectEqual(profile.PackingXP, 99)
			expectEqual(profile.StarterMissions.PathCompleted, false)
		end,
	},
})

addSuite("Multiplayer isolation", {
	{
		Name = "eight profile defaults and starter paths are independent",
		Run = function()
			local profiles = {}
			for index = 1, 8 do profiles[index] = defaultProfile(index) end
			completeMission(profiles[1], "AcceptedPlacement", nil)
			OnboardingService.ApplySkipToProfile(profiles[2])
			for index = 2, 8 do expectEqual(profiles[index].StarterMissions.Rewarded.first_fit, nil) end
			for index = 1, 8 do
				if index ~= 2 then expectEqual(profiles[index].Onboarding.Status, "NotStarted") end
			end
		end,
	},
	{
		Name = "analytics records and rewards remain player scoped",
		Run = function()
			local adapter = MemoryAnalyticsAdapter.Create()
			local analytics = GameAnalyticsService.Create({ Adapter = adapter, IsStudio = true })
			analytics:LogOnboardingStep(fakePlayer(401), 1)
			analytics:LogOneMoreAccepted(fakePlayer(402), 2, "EASY FIT")
			expectEqual(#adapter:GetRecordsForPlayer(401), 1)
			expectEqual(#adapter:GetRecordsForPlayer(402), 1)
			expectEqual(adapter:GetRecordsForPlayer(401)[1].Kind, "Onboarding")
			expectEqual(adapter:GetRecordsForPlayer(402)[1].Name, "OneMoreAccepted")
		end,
	},
	{
		Name = "one conflict cannot clear another mission state",
		Run = function()
			local left = makeHarness(403)
			local right = makeHarness(404)
			local leftMission = StarterMissionService.Create(left.Service, left.Analytics)
			local rightMission = StarterMissionService.Create(right.Service, right.Analytics)
			local leftPrepared = leftMission:ApplyEvent(fakePlayer(403), "AcceptedPlacement", nil)
			local rightApplied = rightMission:ApplyEvent(fakePlayer(404), "OneMoreAccepted", nil)
			expect(leftPrepared ~= nil and leftPrepared.Changed)
			expect(rightApplied ~= nil and rightApplied.Changed)
			left.Adapter:ForceSession(403, { Token = "other", JobId = "other", PlaceId = 1, AcquiredAt = 1, HeartbeatAt = 9_999 })
			local saved, saveCode = left.Service:SaveNow(403)
			expect(not saved and saveCode == "CONFLICT")
			expectEqual(left.Service:GetState(403), "Conflict")
			local blocked, blockedCode = leftMission:ApplyEvent(fakePlayer(403), "OneMoreAccepted", nil)
			expectEqual(blocked, nil)
			expectEqual(blockedCode, "PROFILE_NOT_MUTABLE")
			expectEqual(right.Service:GetProfileCopy(404).StarterMissions.Rewarded.one_more, true)
		end,
	},
})

addSuite("Persistence", {
	{
		Name = "Version 1 onboarding and mission changes persist through release reload",
		Run = function()
			local adapter = MemoryProfileAdapter.Create()
			adapter:Seed(501, { SchemaVersion = 1, Tape = 20, PackingXP = 30 })
			local clock = { Value = 1_000 }
			local function service(serverId: string): any
				return ProfileService.Create(adapter, {
					Clock = function() return clock.Value end,
					Wait = function(duration: number) clock.Value += duration end,
					IdentifierFactory = function() return serverId .. "-lock" end,
					PresentationIdentifierFactory = function() return serverId .. "-presentation" end,
					Spawn = function(callback: () -> ()) callback() end,
					ServerSessionId = serverId,
					JobId = serverId,
					PlaceId = 134193642444044,
					AutoSchedule = false,
				})
			end
			local first = service("session-e")
			expect(first:LoadPlayer(501))
			local analytics = GameAnalyticsService.Create({ IsStudio = true })
			OnboardingService.Create(first, analytics):Advance(fakePlayer(501), 1)
			StarterMissionService.Create(first, analytics):ApplyEvent(fakePlayer(501), "AcceptedPlacement", nil)
			expect(first:Release(501))
			local second = service("session-f")
			expect(second:LoadPlayer(501))
			local profile = second:GetProfileCopy(501)
			expectEqual(profile.SchemaVersion, 2)
			expectEqual(profile.Tape, 30)
			expectEqual(profile.PackingXP, 40)
			expectEqual(profile.Onboarding.HighestStep, 1)
			expectEqual(profile.StarterMissions.Rewarded.first_fit, true)
		end,
	},
	{
		Name = "reconciliation and duplicate events do not replay persisted rewards or analytics",
		Run = function()
			local harness = makeHarness(502)
			local missions = StarterMissionService.Create(harness.Service, harness.Analytics)
			missions:ApplyEvent(fakePlayer(502), "AcceptedPlacement", nil)
			local tape = harness.Service:GetProfileCopy(502).Tape
			local analyticsCount = harness.AnalyticsAdapter:Count()
			local reconciled = missions:Reconcile(fakePlayer(502))
			expect(reconciled ~= nil and not reconciled.Changed)
			expectEqual(harness.Service:GetProfileCopy(502).Tape, tape)
			expectEqual(harness.AnalyticsAdapter:Count(), analyticsCount)
		end,
	},
	{
		Name = "SaveDelayed keeps in-memory mission state and shutdown persists Version 2",
		Run = function()
			local harness = makeHarness(503)
			local missions = StarterMissionService.Create(harness.Service, harness.Analytics)
			missions:ApplyEvent(fakePlayer(503), "AcceptedPlacement", nil)
			harness.Adapter:SetSaveFailure(503, 1)
			local saved = harness.Service:SaveNow(503)
			expect(not saved)
			expectEqual(harness.Service:GetProfileCopy(503).StarterMissions.Rewarded.first_fit, true)
			expect(harness.Service:SaveNow(503))
			expect(harness.Service:Release(503))
			expectEqual(harness.Adapter:ReadStored(503).SchemaVersion, 2)
			expectEqual(harness.Adapter:ReadStored(503).StarterMissions.Rewarded.first_fit, true)
		end,
	},
})

function Phase06TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}
	local seed = RoundConfig.DEVELOPMENT.PHASE06_TEST_SEED
	if type(seed) ~= "number" or seed % 1 ~= 0 then
		error("RoundConfig.DEVELOPMENT.PHASE06_TEST_SEED must be a fixed integer", 2)
	end

	print(string.format("[ONE_MORE_ITEM][Phase06Tests] Starting %d suites seed=%d adapters=memory/memory", #suites, seed))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase06Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase06Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase06Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d profileAdapter=memory analyticsAdapter=memory",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		seed
	))
	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase06Tests] FAILURE %d: %s", index, failure))
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

return table.freeze(Phase06TestSuite)
