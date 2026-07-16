--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local CollectionDefinitions = require(Root.Shared.Profile.CollectionDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local ProfileNetworkTypes = require(Root.Shared.Profile.ProfileNetworkTypes)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)
local StarterMissionDefinitions = require(Root.Shared.Profile.StarterMissionDefinitions)
local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type ProfileLifecycleState = ProfileTypes.ProfileLifecycleState
type ProfileSaveState = ProfileTypes.ProfileSaveState
type ProfileSnapshot = ProfileTypes.ProfileSnapshot
type ProgressionReward = ProgressionTypes.ProgressionReward
type Statistics = ProgressionTypes.Statistics
type StarterMissionReward = ProgressionTypes.StarterMissionReward

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
		TotalMissionTapeEarned = 0,
		TotalStarterMissionsCompleted = 0,
	}
	return table.freeze({
		TotalSuccessfulShipments = source.TotalSuccessfulShipments,
		TotalItemsShipped = source.TotalItemsShipped,
		HighestItemsInShipment = source.HighestItemsInShipment,
		BestShipmentValue = source.BestShipmentValue,
		PerfectShipments = source.PerfectShipments,
		TotalFailedRounds = source.TotalFailedRounds,
		TotalTapeEarned = source.TotalTapeEarned,
		TotalMissionTapeEarned = source.TotalMissionTapeEarned,
		TotalStarterMissionsCompleted = source.TotalStarterMissionsCompleted,
	}) :: Statistics
end

local function copyMissionReward(reward: StarterMissionReward): ProfileNetworkTypes.MissionRewardPresentation
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
	}) :: ProfileNetworkTypes.MissionRewardPresentation
end

local function copyMissionRewardBatch(rewards: { StarterMissionReward }?): { ProfileNetworkTypes.MissionRewardPresentation }
	local copied: { ProfileNetworkTypes.MissionRewardPresentation } = {}
	if rewards ~= nil then
		for index, reward in ipairs(rewards) do
			if index > ProfileConfig.MAXIMUM_MISSION_REWARD_BATCH then
				break
			end
			table.insert(copied, copyMissionReward(reward))
		end
	end
	return table.freeze(copied)
end

local function buildOnboarding(profile: PersistedProfile?): ProfileNetworkTypes.OnboardingPresentation
	local onboarding = if profile ~= nil then profile.Onboarding else nil
	local status = if onboarding ~= nil then onboarding.Status else "NotStarted"
	return table.freeze({
		Status = status,
		HighestStep = if onboarding ~= nil then onboarding.HighestStep else 0,
		Completed = status == "Completed",
	}) :: ProfileNetworkTypes.OnboardingPresentation
end

local function buildStarterMissions(profile: PersistedProfile?): ProfileNetworkTypes.StarterMissionsPresentation
	local progress: { [string]: number } = {}
	local completedIds: { string } = {}
	local rewardedIds: { string } = {}
	local currentMissionId: string? = nil
	local pathCompleted = false
	if profile ~= nil then
		local state = profile.StarterMissions
		pathCompleted = state.PathCompleted
		for _, definition in ipairs(StarterMissionDefinitions.Ordered) do
			local missionId = definition.Id
			progress[missionId] = math.clamp(state.Progress[missionId] or 0, 0, definition.Goal)
			if state.Completed[missionId] == true then
				table.insert(completedIds, missionId)
			elseif currentMissionId == nil then
				currentMissionId = missionId
			end
			if state.Rewarded[missionId] == true then
				table.insert(rewardedIds, missionId)
			end
		end
	else
		currentMissionId = StarterMissionDefinitions.Ordered[1].Id
		for _, definition in ipairs(StarterMissionDefinitions.Ordered) do
			progress[definition.Id] = 0
		end
	end
	table.freeze(progress)
	table.freeze(completedIds)
	table.freeze(rewardedIds)
	return table.freeze({
		Progress = progress,
		CompletedMissionIds = completedIds,
		RewardedMissionIds = rewardedIds,
		CurrentMissionId = currentMissionId,
		CompletedCount = #completedIds,
		TotalCount = StarterMissionDefinitions.TotalCount,
		PathCompleted = pathCompleted,
	}) :: ProfileNetworkTypes.StarterMissionsPresentation
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
	lastReward: ProgressionReward?,
	lastMissionRewards: { StarterMissionReward }?
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
		SchemaVersion = if profile ~= nil then profile.SchemaVersion else ProfileConfig.SCHEMA_VERSION,
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
		Onboarding = buildOnboarding(profile),
		StarterMissions = buildStarterMissions(profile),
		LastMissionRewards = copyMissionRewardBatch(lastMissionRewards),
	}) :: ProfileSnapshot
end

function ProfileSnapshotBuilder.CopyReward(reward: ProgressionReward?): ProgressionReward?
	return copyReward(reward)
end

function ProfileSnapshotBuilder.CopyMissionRewards(rewards: { StarterMissionReward }?): { StarterMissionReward }
	local copied: { StarterMissionReward } = {}
	if rewards == nil then
		return table.freeze(copied)
	end
	local seen: { [string]: boolean } = {}
	for index, reward in ipairs(rewards) do
		if index > ProfileConfig.MAXIMUM_MISSION_REWARD_BATCH then
			break
		end
		if type(reward.RewardId) == "string"
			and reward.RewardId ~= ""
			and #reward.RewardId <= ProfileConfig.MAXIMUM_MISSION_REWARD_ID_LENGTH
			and not seen[reward.RewardId]
		then
			seen[reward.RewardId] = true
			table.insert(copied, table.freeze({
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
				Duplicate = reward.Duplicate,
			}) :: StarterMissionReward)
		end
	end
	return table.freeze(copied)
end

return table.freeze(ProfileSnapshotBuilder)
