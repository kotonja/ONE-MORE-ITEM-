--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local ProfileNetworkTypes = require(shared:WaitForChild("Profile"):WaitForChild("ProfileNetworkTypes"))

export type Snapshot = ProfileNetworkTypes.ProfileSnapshot
export type Statistics = ProfileNetworkTypes.Statistics
export type ProgressionReward = ProfileNetworkTypes.ProgressionReward
export type OnboardingPresentation = ProfileNetworkTypes.OnboardingPresentation
export type StarterMissionsPresentation = ProfileNetworkTypes.StarterMissionsPresentation
export type MissionRewardPresentation = ProfileNetworkTypes.MissionRewardPresentation

type Listener = (snapshot: Snapshot) -> ()

export type Store = {
	ApplySnapshot: (self: Store, snapshot: Snapshot) -> boolean,
	GetSnapshot: (self: Store) -> Snapshot?,
	Subscribe: (self: Store, listener: Listener) -> (() -> ()),
	Destroy: (self: Store) -> (),
}

type InternalStore = Store & {
	_snapshot: Snapshot?,
	_listeners: { [number]: Listener },
	_nextListenerId: number,
	_destroyed: boolean,
}

local ClientProfileStore = {}
local StoreMethods = {}
StoreMethods.__index = StoreMethods

local function copyStringArray(values: { string }): { string }
	local copied: { string } = {}
	for _, value in ipairs(values) do
		table.insert(copied, value)
	end
	return table.freeze(copied)
end

local function copyNumberMap(values: { [string]: number }): { [string]: number }
	local copied: { [string]: number } = {}
	for key, value in pairs(values) do
		copied[key] = value
	end
	return table.freeze(copied)
end

local function copyStatistics(stats: Statistics): Statistics
	return table.freeze({
		TotalSuccessfulShipments = stats.TotalSuccessfulShipments,
		TotalItemsShipped = stats.TotalItemsShipped,
		HighestItemsInShipment = stats.HighestItemsInShipment,
		BestShipmentValue = stats.BestShipmentValue,
		PerfectShipments = stats.PerfectShipments,
		TotalFailedRounds = stats.TotalFailedRounds,
		TotalTapeEarned = stats.TotalTapeEarned,
		TotalMissionTapeEarned = stats.TotalMissionTapeEarned,
		TotalStarterMissionsCompleted = stats.TotalStarterMissionsCompleted,
	}) :: Statistics
end

local function copyOnboarding(onboarding: OnboardingPresentation): OnboardingPresentation
	return table.freeze({
		Status = onboarding.Status,
		HighestStep = onboarding.HighestStep,
		Completed = onboarding.Completed,
	}) :: OnboardingPresentation
end

local function copyStarterMissions(missions: StarterMissionsPresentation): StarterMissionsPresentation
	return table.freeze({
		Progress = copyNumberMap(missions.Progress),
		CompletedMissionIds = copyStringArray(missions.CompletedMissionIds),
		RewardedMissionIds = copyStringArray(missions.RewardedMissionIds),
		CurrentMissionId = missions.CurrentMissionId,
		CompletedCount = missions.CompletedCount,
		TotalCount = missions.TotalCount,
		PathCompleted = missions.PathCompleted,
	}) :: StarterMissionsPresentation
end

local function copyMissionReward(reward: MissionRewardPresentation): MissionRewardPresentation
	return table.freeze({
		RewardId = reward.RewardId,
		MissionId = reward.MissionId,
		MissionIndex = reward.MissionIndex,
		TapeDelta = reward.TapeDelta,
		XPDelta = reward.XPDelta,
		PreviousTape = reward.PreviousTape,
		NewTape = reward.NewTape,
		PreviousXP = reward.PreviousXP,
		NewXP = reward.NewXP,
		PreviousRank = table.freeze({
			Index = reward.PreviousRank.Index,
			Name = reward.PreviousRank.Name,
			Threshold = reward.PreviousRank.Threshold,
		}),
		NewRank = table.freeze({
			Index = reward.NewRank.Index,
			Name = reward.NewRank.Name,
			Threshold = reward.NewRank.Threshold,
		}),
		PathCompleted = reward.PathCompleted,
	}) :: MissionRewardPresentation
end

local function copyMissionRewards(rewards: { MissionRewardPresentation }): { MissionRewardPresentation }
	local copied: { MissionRewardPresentation } = {}
	for _, reward in ipairs(rewards) do
		table.insert(copied, copyMissionReward(reward))
	end
	return table.freeze(copied)
end

local function copyReward(reward: ProgressionReward?): ProgressionReward?
	if reward == nil then
		return nil
	end
	local discoveries = copyStringArray(reward.NewDiscoveries)
	local masteryChanges = {}
	for _, change in ipairs(reward.MasteryChanges) do
		table.insert(masteryChanges, table.freeze({
			ItemId = change.ItemId,
			PreviousCount = change.PreviousCount,
			NewCount = change.NewCount,
			PreviousTier = change.PreviousTier,
			NewTier = change.NewTier,
		}))
	end
	table.freeze(masteryChanges)
	return table.freeze({
		OutcomeId = reward.OutcomeId,
		RoundId = reward.RoundId,
		OutcomeType = reward.OutcomeType,
		TapeDelta = reward.TapeDelta,
		NewTape = reward.NewTape,
		XPDelta = reward.XPDelta,
		PreviousXP = reward.PreviousXP,
		NewXP = reward.NewXP,
		PreviousRank = table.freeze({
			Index = reward.PreviousRank.Index,
			Name = reward.PreviousRank.Name,
			Threshold = reward.PreviousRank.Threshold,
		}),
		NewRank = table.freeze({
			Index = reward.NewRank.Index,
			Name = reward.NewRank.Name,
			Threshold = reward.NewRank.Threshold,
		}),
		NewDiscoveries = discoveries,
		MasteryChanges = masteryChanges,
		UpdatedStats = copyStatistics(reward.UpdatedStats),
		Duplicate = reward.Duplicate,
	}) :: ProgressionReward
end

local function copySnapshot(snapshot: Snapshot): Snapshot
	return table.freeze({
		SchemaVersion = snapshot.SchemaVersion,
		ProfileSessionId = snapshot.ProfileSessionId,
		Revision = snapshot.Revision,
		State = snapshot.State,
		SaveState = snapshot.SaveState,
		Tape = snapshot.Tape,
		PackingXP = snapshot.PackingXP,
		RankIndex = snapshot.RankIndex,
		RankName = snapshot.RankName,
		RankStartXP = snapshot.RankStartXP,
		NextRankXP = snapshot.NextRankXP,
		XPIntoRank = snapshot.XPIntoRank,
		XPRequiredForNextRank = snapshot.XPRequiredForNextRank,
		DiscoveredItemIds = copyStringArray(snapshot.DiscoveredItemIds),
		MasteryCounts = copyNumberMap(snapshot.MasteryCounts),
		CollectionDiscoveredCount = snapshot.CollectionDiscoveredCount,
		CollectionTotalCount = snapshot.CollectionTotalCount,
		Stats = copyStatistics(snapshot.Stats),
		LastReward = copyReward(snapshot.LastReward),
		Onboarding = copyOnboarding(snapshot.Onboarding),
		StarterMissions = copyStarterMissions(snapshot.StarterMissions),
		LastMissionRewards = copyMissionRewards(snapshot.LastMissionRewards),
	}) :: Snapshot
end

function ClientProfileStore.new(): Store
	return setmetatable({
		_snapshot = nil,
		_listeners = {},
		_nextListenerId = 0,
		_destroyed = false,
	}, StoreMethods) :: InternalStore
end

function StoreMethods.ApplySnapshot(self: InternalStore, snapshot: Snapshot): boolean
	if self._destroyed then
		return false
	end
	local previous = self._snapshot
	if previous ~= nil
		and previous.ProfileSessionId == snapshot.ProfileSessionId
		and snapshot.Revision <= previous.Revision
	then
		return false
	end

	local copied = copySnapshot(snapshot)
	self._snapshot = copied
	for _, listener in pairs(self._listeners) do
		listener(copied)
	end
	return true
end

function StoreMethods.GetSnapshot(self: InternalStore): Snapshot?
	return self._snapshot
end

function StoreMethods.Subscribe(self: InternalStore, listener: Listener): () -> ()
	if self._destroyed then
		error("Cannot subscribe to a destroyed ClientProfileStore", 2)
	end
	self._nextListenerId += 1
	local listenerId = self._nextListenerId
	self._listeners[listenerId] = listener
	local connected = true
	return function()
		if connected then
			connected = false
			self._listeners[listenerId] = nil
		end
	end
end

function StoreMethods.Destroy(self: InternalStore)
	self._destroyed = true
	self._snapshot = nil
	table.clear(self._listeners)
end

return table.freeze(ClientProfileStore)
