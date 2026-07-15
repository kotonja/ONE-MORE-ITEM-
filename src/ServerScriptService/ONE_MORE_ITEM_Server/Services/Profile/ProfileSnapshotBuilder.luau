--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local CollectionDefinitions = require(Root.Shared.Profile.CollectionDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type ProfileLifecycleState = ProfileTypes.ProfileLifecycleState
type ProfileSaveState = ProfileTypes.ProfileSaveState
type ProfileSnapshot = ProfileTypes.ProfileSnapshot
type ProgressionReward = ProgressionTypes.ProgressionReward
type Statistics = ProgressionTypes.Statistics

local ProfileSnapshotBuilder = {}

local function copyStats(stats: Statistics?): Statistics
	local source = stats or {
		TotalSuccessfulShipments = 0,
		TotalItemsShipped = 0,
		HighestItemsInShipment = 0,
		BestShipmentValue = 0,
		PerfectShipments = 0,
		TotalFailedRounds = 0,
		TotalTapeEarned = 0,
	}
	return table.freeze({
		TotalSuccessfulShipments = source.TotalSuccessfulShipments,
		TotalItemsShipped = source.TotalItemsShipped,
		HighestItemsInShipment = source.HighestItemsInShipment,
		BestShipmentValue = source.BestShipmentValue,
		PerfectShipments = source.PerfectShipments,
		TotalFailedRounds = source.TotalFailedRounds,
		TotalTapeEarned = source.TotalTapeEarned,
	}) :: Statistics
end

local function copyReward(reward: ProgressionReward?): ProgressionReward?
	if reward == nil then
		return nil
	end
	local discoveries = table.clone(reward.NewDiscoveries)
	table.freeze(discoveries)
	local masteryChanges: { ProgressionTypes.MasteryChange } = table.create(#reward.MasteryChanges)
	for index, change in ipairs(reward.MasteryChanges) do
		masteryChanges[index] = table.freeze({
			ItemId = change.ItemId,
			PreviousCount = change.PreviousCount,
			NewCount = change.NewCount,
			PreviousTier = change.PreviousTier,
			NewTier = change.NewTier,
		}) :: ProgressionTypes.MasteryChange
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
		UpdatedStats = copyStats(reward.UpdatedStats),
		Duplicate = reward.Duplicate,
	}) :: ProgressionReward
end

function ProfileSnapshotBuilder.Build(
	profile: PersistedProfile?,
	state: ProfileLifecycleState,
	saveState: ProfileSaveState,
	revision: number,
	profileSessionId: string,
	lastReward: ProgressionReward?
): ProfileSnapshot
	local tape = if profile then profile.Tape else 0
	local packingXP = if profile then profile.PackingXP else 0
	local rankProgress = PackingRankDefinitions.GetProgress(packingXP)
	local discoveredIds: { string } = {}
	local masteryCounts: { [string]: number } = {}
	if profile then
		for _, itemId in ipairs(CollectionDefinitions.OrderedItemIds) do
			if profile.Collection.Discovered[itemId] == true then
				table.insert(discoveredIds, itemId)
				masteryCounts[itemId] = profile.Collection.MasteryCounts[itemId] or 0
			end
		end
	end
	table.freeze(discoveredIds)
	table.freeze(masteryCounts)

	return table.freeze({
		ProfileSessionId = profileSessionId,
		Revision = revision,
		State = state,
		SaveState = saveState,
		Tape = tape,
		PackingXP = packingXP,
		RankIndex = rankProgress.RankIndex,
		RankName = rankProgress.RankName,
		RankStartXP = rankProgress.RankStartXP,
		NextRankXP = rankProgress.NextRankXP,
		XPIntoRank = rankProgress.XPIntoRank,
		XPRequiredForNextRank = rankProgress.XPRequiredForNextRank,
		DiscoveredItemIds = discoveredIds,
		MasteryCounts = masteryCounts,
		CollectionDiscoveredCount = #discoveredIds,
		CollectionTotalCount = CollectionDefinitions.TotalCount,
		Stats = copyStats(if profile then profile.Stats else nil),
		LastReward = copyReward(lastReward),
	}) :: ProfileSnapshot
end

function ProfileSnapshotBuilder.CopyReward(reward: ProgressionReward?): ProgressionReward?
	return copyReward(reward)
end

return table.freeze(ProfileSnapshotBuilder)
