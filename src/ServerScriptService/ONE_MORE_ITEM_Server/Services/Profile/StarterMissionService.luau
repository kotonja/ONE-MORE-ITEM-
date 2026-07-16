--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)
local StarterMissionDefinitions = require(Root.Shared.Profile.StarterMissionDefinitions)

local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type Statistics = ProfileTypes.Statistics
type StarterMissionReward = ProgressionTypes.StarterMissionReward

export type MissionEventName = "AcceptedPlacement" | "SuccessfulShipment" | "OneMoreAccepted" | "ProfileReconcile"

export type MissionEventData = {
	ItemCount: number?,
}

export type MissionMutationResult = {
	Changed: boolean,
	Rewards: { StarterMissionReward },
	StartedMissionIds: { string },
	PathJustCompleted: boolean,
}

type ProfileServiceContract = {
	ApplyMutationWithMissionRewards: (
		self: ProfileServiceContract,
		userId: number,
		mutation: (PersistedProfile) -> (boolean, any?, { StarterMissionReward }?, string?)
	) -> (any?, string),
	GetProfileCopy: (self: ProfileServiceContract, userId: number) -> PersistedProfile?,
}

type AnalyticsContract = {
	LogEconomySource: (self: AnalyticsContract, player: Player, source: string, amount: number, endingBalance: number, itemSku: string) -> boolean,
	LogProgressionStart: (self: AnalyticsContract, player: Player, missionId: string) -> boolean,
	LogProgressionComplete: (self: AnalyticsContract, player: Player, missionId: string) -> boolean,
	LogStarterMission: (self: AnalyticsContract, player: Player, missionId: string, status: string) -> boolean,
}

type Options = {
	Clock: (() -> number)?,
}

export type Service = {
	ApplyEvent: (self: Service, player: Player, eventName: MissionEventName, eventData: MissionEventData?) -> (MissionMutationResult?, string),
	Reconcile: (self: Service, player: Player) -> (MissionMutationResult?, string),
	StartCurrentSpotlight: (self: Service, player: Player) -> boolean,
}

type ServiceImpl = Service & {
	_profileService: ProfileServiceContract,
	_analytics: AnalyticsContract,
	_clock: () -> number,
}

local StarterMissionService = {}
StarterMissionService.__index = StarterMissionService

local function defaultClock(): number
	return os.time()
end

local function isFiniteInteger(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
end

local function checkedAdd(left: number, right: number): number?
	if not isFiniteInteger(left) or not isFiniteInteger(right) or left < 0 or right < 0 then
		return nil
	end
	local total = left + right
	return if isFiniteInteger(total) and total <= ProfileConfig.MAXIMUM_SAFE_INTEGER then total else nil
end

local function copyStats(stats: Statistics): Statistics
	return {
		TotalSuccessfulShipments = stats.TotalSuccessfulShipments,
		TotalItemsShipped = stats.TotalItemsShipped,
		HighestItemsInShipment = stats.HighestItemsInShipment,
		BestShipmentValue = stats.BestShipmentValue,
		PerfectShipments = stats.PerfectShipments,
		TotalFailedRounds = stats.TotalFailedRounds,
		TotalTapeEarned = stats.TotalTapeEarned,
		TotalMissionTapeEarned = stats.TotalMissionTapeEarned,
		TotalStarterMissionsCompleted = stats.TotalStarterMissionsCompleted,
	}
end

local function rankPresentation(xp: number): ProgressionTypes.RankPresentation
	local rank = PackingRankDefinitions.GetRankForXP(xp)
	return table.freeze({ Index = rank.Index, Name = rank.Name, Threshold = rank.Threshold })
end

local function countDiscoveries(profile: PersistedProfile): number
	local count = 0
	for _, discovered in pairs(profile.Collection.Discovered) do
		if discovered then
			count += 1
		end
	end
	return count
end

local function freezeResult(
	changed: boolean,
	rewards: { StarterMissionReward },
	startedMissionIds: { string },
	pathJustCompleted: boolean
): MissionMutationResult
	table.freeze(rewards)
	table.freeze(startedMissionIds)
	return table.freeze({
		Changed = changed,
		Rewards = rewards,
		StartedMissionIds = startedMissionIds,
		PathJustCompleted = pathJustCompleted,
	})
end

local function targetProgress(
	profile: PersistedProfile,
	eventName: MissionEventName,
	eventData: MissionEventData,
	missionId: string,
	previous: number
): number?
	if eventName == "AcceptedPlacement" and missionId == "first_fit" then
		return previous + 1
	elseif eventName == "OneMoreAccepted" and missionId == "one_more" then
		return previous + 1
	elseif eventName == "SuccessfulShipment" then
		if missionId == "first_shipment" then
			return math.max(previous, profile.Stats.TotalSuccessfulShipments)
		elseif missionId == "collector_three" then
			return math.max(previous, countDiscoveries(profile))
		elseif missionId == "five_item_box" then
			local itemCount = eventData.ItemCount or profile.Stats.HighestItemsInShipment
			return math.max(previous, profile.Stats.HighestItemsInShipment, itemCount)
		end
	elseif eventName == "ProfileReconcile" then
		if missionId == "first_shipment" then
			return math.max(previous, profile.Stats.TotalSuccessfulShipments)
		elseif missionId == "collector_three" then
			return math.max(previous, countDiscoveries(profile))
		elseif missionId == "five_item_box" then
			return math.max(previous, profile.Stats.HighestItemsInShipment)
		end
	end
	return nil
end

function StarterMissionService.ApplyEventToProfile(
	profile: PersistedProfile,
	eventName: MissionEventName,
	eventData: MissionEventData?,
	now: number
): (boolean, MissionMutationResult, { StarterMissionReward }, string)
	if eventName ~= "AcceptedPlacement"
		and eventName ~= "SuccessfulShipment"
		and eventName ~= "OneMoreAccepted"
		and eventName ~= "ProfileReconcile"
	then
		local empty: { StarterMissionReward } = {}
		return false, freezeResult(false, empty, {}, false), empty, "INVALID_EVENT"
	end
	local data = eventData or {}
	if data.ItemCount ~= nil and (not isFiniteInteger(data.ItemCount) or (data.ItemCount :: number) < 0) then
		local empty: { StarterMissionReward } = {}
		return false, freezeResult(false, empty, {}, false), empty, "INVALID_EVENT_DATA"
	end

	local state = profile.StarterMissions
	local previousSpotlight = StarterMissionDefinitions.GetFirstIncomplete(state.Completed)
	local progress = table.clone(state.Progress)
	local completed = table.clone(state.Completed)
	local rewarded = table.clone(state.Rewarded)
	local startedMissionIds: { string } = {}
	local newlyCompletedIds: { string } = {}
	local changed = false

	for _, definition in ipairs(StarterMissionDefinitions.Ordered) do
		local previous = math.clamp(progress[definition.Id] or 0, 0, definition.Goal)
		local target = targetProgress(profile, eventName, data, definition.Id, previous)
		if target ~= nil then
			local nextProgress = math.clamp(math.floor(target), 0, definition.Goal)
			if nextProgress > previous then
				progress[definition.Id] = nextProgress
				changed = true
			end
			if nextProgress >= definition.Goal and completed[definition.Id] ~= true then
				completed[definition.Id] = true
				changed = true
			end
		end
		if completed[definition.Id] == true and rewarded[definition.Id] ~= true then
			table.insert(newlyCompletedIds, definition.Id)
		end
	end

	local newSpotlight = StarterMissionDefinitions.GetFirstIncomplete(completed)
	if newSpotlight ~= nil and (previousSpotlight == nil or newSpotlight.Id ~= previousSpotlight.Id) then
		table.insert(startedMissionIds, newSpotlight.Id)
	end

	local nextTape = profile.Tape
	local nextXP = profile.PackingXP
	local nextStats = copyStats(profile.Stats)
	local rewards: { StarterMissionReward } = {}
	local previousPathCompleted = state.PathCompleted

	for _, missionId in ipairs(newlyCompletedIds) do
		local definition = StarterMissionDefinitions.Get(missionId)
		if definition == nil then
			local empty: { StarterMissionReward } = {}
			return false, freezeResult(false, empty, {}, false), empty, "UNKNOWN_MISSION"
		end
		local previousTape = nextTape
		local previousXP = nextXP
		nextTape = checkedAdd(nextTape, definition.Reward.Tape) or -1
		nextXP = checkedAdd(nextXP, definition.Reward.PackingXP) or -1
		nextStats.TotalTapeEarned = checkedAdd(nextStats.TotalTapeEarned, definition.Reward.Tape) or -1
		nextStats.TotalMissionTapeEarned = checkedAdd(nextStats.TotalMissionTapeEarned, definition.Reward.Tape) or -1
		nextStats.TotalStarterMissionsCompleted = checkedAdd(nextStats.TotalStarterMissionsCompleted, 1) or -1
		if nextTape < 0
			or nextXP < 0
			or nextStats.TotalTapeEarned < 0
			or nextStats.TotalMissionTapeEarned < 0
			or nextStats.TotalStarterMissionsCompleted < 0
		then
			local empty: { StarterMissionReward } = {}
			return false, freezeResult(false, empty, {}, false), empty, "REWARD_OVERFLOW"
		end
		rewarded[missionId] = true
		local pathAfterReward = true
		for _, candidate in ipairs(StarterMissionDefinitions.Ordered) do
			if rewarded[candidate.Id] ~= true then
				pathAfterReward = false
				break
			end
		end
		table.insert(rewards, table.freeze({
			RewardId = "starter:v1:" .. missionId,
			MissionId = missionId,
			MissionIndex = definition.Index,
			TapeDelta = definition.Reward.Tape,
			XPDelta = definition.Reward.PackingXP,
			PreviousTape = previousTape,
			NewTape = nextTape,
			PreviousXP = previousXP,
			NewXP = nextXP,
			PreviousRank = rankPresentation(previousXP),
			NewRank = rankPresentation(nextXP),
			PathCompleted = pathAfterReward,
			Duplicate = false,
		}) :: StarterMissionReward)
		changed = true
	end

	local pathCompleted = true
	for _, definition in ipairs(StarterMissionDefinitions.Ordered) do
		if rewarded[definition.Id] ~= true then
			pathCompleted = false
			break
		end
	end
	local pathJustCompleted = pathCompleted and not previousPathCompleted
	if pathCompleted ~= previousPathCompleted then
		changed = true
	end

	if not changed then
		return false, freezeResult(false, rewards, startedMissionIds, false), rewards, "NO_CHANGE"
	end
	profile.Tape = nextTape
	profile.PackingXP = nextXP
	profile.Stats = nextStats
	profile.StarterMissions = {
		Version = 1,
		Progress = progress,
		Completed = completed,
		Rewarded = rewarded,
		PathCompleted = pathCompleted,
		CompletedAt = if pathCompleted then math.max(0, math.floor(now)) else 0,
	}
	local mutationResult = freezeResult(true, rewards, startedMissionIds, pathJustCompleted)
	return true, mutationResult, rewards, "APPLIED"
end

function StarterMissionService.Create(
	profileService: ProfileServiceContract,
	analytics: AnalyticsContract,
	options: Options?
): Service
	local resolved = options or {}
	return setmetatable({
		_profileService = profileService,
		_analytics = analytics,
		_clock = resolved.Clock or defaultClock,
	}, StarterMissionService) :: any
end

function StarterMissionService.ApplyEvent(
	self: ServiceImpl,
	player: Player,
	eventName: MissionEventName,
	eventData: MissionEventData?
): (MissionMutationResult?, string)
	local payload, code = self._profileService:ApplyMutationWithMissionRewards(
		player.UserId,
		function(draft: PersistedProfile): (boolean, any?, { StarterMissionReward }?, string?)
			return StarterMissionService.ApplyEventToProfile(draft, eventName, eventData, self._clock())
		end
	)
	local mutationResult = payload :: MissionMutationResult?
	if mutationResult == nil or not mutationResult.Changed then
		return mutationResult, code
	end

	for _, reward in ipairs(mutationResult.Rewards) do
		pcall(function()
			if reward.TapeDelta > 0 then
				self._analytics:LogEconomySource(
					player,
					"StarterMission",
					reward.TapeDelta,
					reward.NewTape,
					"starter:" .. reward.MissionId
				)
			end
			self._analytics:LogProgressionComplete(player, reward.MissionId)
			self._analytics:LogStarterMission(player, reward.MissionId, "completed")
		end)
	end
	if mutationResult.PathJustCompleted then
		local completingMissionId = "five_item_box"
		for _, reward in ipairs(mutationResult.Rewards) do
			if reward.PathCompleted then
				completingMissionId = reward.MissionId
			end
		end
		pcall(function()
			self._analytics:LogStarterMission(player, completingMissionId, "path_completed")
		end)
	end
	for _, missionId in ipairs(mutationResult.StartedMissionIds) do
		pcall(function()
			self._analytics:LogProgressionStart(player, missionId)
			self._analytics:LogStarterMission(player, missionId, "started")
		end)
	end
	return mutationResult, code
end

function StarterMissionService.Reconcile(self: ServiceImpl, player: Player): (MissionMutationResult?, string)
	return self:ApplyEvent(player, "ProfileReconcile", nil)
end

function StarterMissionService.StartCurrentSpotlight(self: ServiceImpl, player: Player): boolean
	local profile = self._profileService:GetProfileCopy(player.UserId)
	if profile == nil then
		return false
	end
	local spotlight = StarterMissionDefinitions.GetFirstIncomplete(profile.StarterMissions.Completed)
	if spotlight == nil then
		return false
	end
	local logged = false
	pcall(function()
		logged = self._analytics:LogProgressionStart(player, spotlight.Id)
		self._analytics:LogStarterMission(player, spotlight.Id, "started")
	end)
	return logged
end

return table.freeze(StarterMissionService)
