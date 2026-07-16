--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local CollectionDefinitions = require(Root.Shared.Profile.CollectionDefinitions)
local MasteryDefinitions = require(Root.Shared.Profile.MasteryDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)
local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type ProgressionReward = ProgressionTypes.ProgressionReward
type Statistics = ProgressionTypes.Statistics
type MasteryChange = ProgressionTypes.MasteryChange

export type ShipmentRecord = {
	PlayerUserId: number,
	RoundId: number,
	OutcomeId: string,
	ItemCount: number,
	ShipmentValue: number,
	PlacedItems: { { ItemId: string } },
	PerfectShipment: boolean?,
}

type ProfileServiceContract = {
	ApplyMutation: (
		self: ProfileServiceContract,
		userId: number,
		mutation: (PersistedProfile) -> (boolean, any?, string?)
	) -> (any?, string),
}

export type Service = {
	ApplyShipment: (
		self: Service,
		userId: number,
		roundId: number,
		outcomeId: string,
		shipmentRecord: ShipmentRecord
	) -> (ProgressionReward?, string),
	ApplyFailure: (
		self: Service,
		userId: number,
		roundId: number,
		outcomeId: string,
		itemCount: number
	) -> (ProgressionReward?, string),
}

type ProgressionServiceImpl = Service & {
	_profileService: ProfileServiceContract,
}

local ProgressionService = {}
ProgressionService.__index = ProgressionService

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
	if not isFiniteInteger(total) or total > ProfileConfig.MAXIMUM_SAFE_INTEGER then
		return nil
	end
	return total
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

local function immutableStats(stats: Statistics): Statistics
	return table.freeze(copyStats(stats)) :: Statistics
end

local function rankPresentation(xp: number): ProgressionTypes.RankPresentation
	local rank = PackingRankDefinitions.GetRankForXP(xp)
	return table.freeze({
		Index = rank.Index,
		Name = rank.Name,
		Threshold = rank.Threshold,
	}) :: ProgressionTypes.RankPresentation
end

local function freezeReward(reward: ProgressionReward): ProgressionReward
	table.freeze(reward.NewDiscoveries)
	for _, change in ipairs(reward.MasteryChanges) do
		table.freeze(change)
	end
	table.freeze(reward.MasteryChanges)
	-- Rank and statistics presentation values are frozen by their focused
	-- constructors. Luau rejects freezing an already-frozen table.
	return table.freeze(reward)
end

local function hasReceipt(profile: PersistedProfile, outcomeId: string): boolean
	for _, existing in ipairs(profile.Receipts.ProcessedOutcomeIds) do
		if existing == outcomeId then
			return true
		end
	end
	return false
end

local function appendReceipt(receipts: { string }, outcomeId: string): { string }
	local updated = table.clone(receipts)
	table.insert(updated, outcomeId)
	while #updated > ProfileConfig.MAXIMUM_RECEIPT_COUNT do
		table.remove(updated, 1)
	end
	return updated
end

local function validIdentity(roundId: number, outcomeId: string): boolean
	return isFiniteInteger(roundId)
		and roundId >= 1
		and type(outcomeId) == "string"
		and outcomeId ~= ""
		and #outcomeId <= ProfileConfig.MAXIMUM_OUTCOME_ID_LENGTH
end

function ProgressionService.CalculateShipmentXP(itemCount: number, shipmentValue: number): number?
	if not isFiniteInteger(itemCount)
		or itemCount < 0
		or itemCount > RoundConfig.MAXIMUM_ITEMS
		or not isFiniteInteger(shipmentValue)
		or shipmentValue < 0
	then
		return nil
	end
	local perfectBonus = if itemCount == RoundConfig.MAXIMUM_ITEMS then 25 else 0
	return 10 + (4 * itemCount) + math.floor(shipmentValue / 100) + perfectBonus
end

function ProgressionService.CalculateFailureXP(itemCount: number): number?
	if not isFiniteInteger(itemCount) or itemCount < 0 or itemCount > RoundConfig.MAXIMUM_ITEMS then
		return nil
	end
	return math.min(itemCount * 2, 10)
end

local function duplicateReward(
	profile: PersistedProfile,
	outcomeId: string,
	roundId: number,
	outcomeType: ProgressionTypes.OutcomeType
): ProgressionReward
	return freezeReward({
		OutcomeId = outcomeId,
		RoundId = roundId,
		OutcomeType = outcomeType,
		TapeDelta = 0,
		NewTape = profile.Tape,
		XPDelta = 0,
		PreviousXP = profile.PackingXP,
		NewXP = profile.PackingXP,
		PreviousRank = rankPresentation(profile.PackingXP),
		NewRank = rankPresentation(profile.PackingXP),
		NewDiscoveries = {},
		MasteryChanges = {},
		UpdatedStats = immutableStats(profile.Stats),
		Duplicate = true,
	})
end

function ProgressionService.ApplyShipmentToProfile(
	profile: PersistedProfile,
	userId: number,
	roundId: number,
	outcomeId: string,
	shipmentRecord: ShipmentRecord
): (boolean, ProgressionReward?, string)
	if not validIdentity(roundId, outcomeId) then
		return false, nil, "INVALID_OUTCOME_ID"
	end
	if shipmentRecord.PlayerUserId ~= userId
		or shipmentRecord.RoundId ~= roundId
		or shipmentRecord.OutcomeId ~= outcomeId
	then
		return false, nil, "OUTCOME_MISMATCH"
	end
	if not isFiniteInteger(shipmentRecord.ItemCount)
		or shipmentRecord.ItemCount < 0
		or shipmentRecord.ItemCount > RoundConfig.MAXIMUM_ITEMS
		or shipmentRecord.ItemCount ~= #shipmentRecord.PlacedItems
	then
		return false, nil, "INVALID_ITEM_COUNT"
	end
	if not isFiniteInteger(shipmentRecord.ShipmentValue)
		or shipmentRecord.ShipmentValue < 0
		or shipmentRecord.ShipmentValue > ProfileConfig.MAXIMUM_SAFE_INTEGER
	then
		return false, nil, "INVALID_SHIPMENT_VALUE"
	end
	for _, item in ipairs(shipmentRecord.PlacedItems) do
		if type(item.ItemId) ~= "string" or not CollectionDefinitions.IsValidItemId(item.ItemId) then
			return false, nil, "UNKNOWN_ITEM_ID"
		end
	end
	if hasReceipt(profile, outcomeId) then
		return false, duplicateReward(profile, outcomeId, roundId, "Shipment"), "DUPLICATE"
	end

	local xpDelta = ProgressionService.CalculateShipmentXP(shipmentRecord.ItemCount, shipmentRecord.ShipmentValue)
	if xpDelta == nil then
		return false, nil, "INVALID_REWARD"
	end
	local newTape = checkedAdd(profile.Tape, shipmentRecord.ShipmentValue)
	local newXP = checkedAdd(profile.PackingXP, xpDelta)
	if newTape == nil or newXP == nil then
		return false, nil, "REWARD_OVERFLOW"
	end

	local newDiscovered = table.clone(profile.Collection.Discovered)
	local newMastery = table.clone(profile.Collection.MasteryCounts)
	local newRecent = table.clone(profile.Collection.RecentDiscoveries)
	local discoveries: { string } = {}
	local occurrenceCounts: { [string]: number } = {}
	local masteryOrder: { string } = {}
	for _, item in ipairs(shipmentRecord.PlacedItems) do
		local itemId = item.ItemId
		if occurrenceCounts[itemId] == nil then
			occurrenceCounts[itemId] = 0
			table.insert(masteryOrder, itemId)
		end
		occurrenceCounts[itemId] += 1
		if newDiscovered[itemId] ~= true then
			newDiscovered[itemId] = true
			table.insert(discoveries, itemId)
			table.insert(newRecent, itemId)
		end
	end
	while #newRecent > ProfileConfig.MAXIMUM_RECENT_DISCOVERY_COUNT do
		table.remove(newRecent, 1)
	end

	local masteryChanges: { MasteryChange } = table.create(#masteryOrder)
	for _, itemId in ipairs(masteryOrder) do
		local previousCount = newMastery[itemId] or 0
		local newCount = checkedAdd(previousCount, occurrenceCounts[itemId])
		if newCount == nil then
			return false, nil, "MASTERY_OVERFLOW"
		end
		newMastery[itemId] = newCount
		table.insert(masteryChanges, {
			ItemId = itemId,
			PreviousCount = previousCount,
			NewCount = newCount,
			PreviousTier = MasteryDefinitions.GetMasteryTier(previousCount, profile.Collection.Discovered[itemId]),
			NewTier = MasteryDefinitions.GetMasteryTier(newCount, true),
		})
	end

	local previousStats = profile.Stats
	local totalSuccessful = checkedAdd(previousStats.TotalSuccessfulShipments, 1)
	local totalItems = checkedAdd(previousStats.TotalItemsShipped, shipmentRecord.ItemCount)
	local perfectShipments = checkedAdd(
		previousStats.PerfectShipments,
		if shipmentRecord.ItemCount == RoundConfig.MAXIMUM_ITEMS then 1 else 0
	)
	local totalTapeEarned = checkedAdd(previousStats.TotalTapeEarned, shipmentRecord.ShipmentValue)
	if totalSuccessful == nil or totalItems == nil or perfectShipments == nil or totalTapeEarned == nil then
		return false, nil, "STAT_OVERFLOW"
	end
	local updatedStats: Statistics = {
		TotalSuccessfulShipments = totalSuccessful,
		TotalItemsShipped = totalItems,
		HighestItemsInShipment = math.max(previousStats.HighestItemsInShipment, shipmentRecord.ItemCount),
		BestShipmentValue = math.max(previousStats.BestShipmentValue, shipmentRecord.ShipmentValue),
		PerfectShipments = perfectShipments,
		TotalFailedRounds = previousStats.TotalFailedRounds,
		TotalTapeEarned = totalTapeEarned,
		TotalMissionTapeEarned = previousStats.TotalMissionTapeEarned,
		TotalStarterMissionsCompleted = previousStats.TotalStarterMissionsCompleted,
	}

	local previousXP = profile.PackingXP
	profile.Tape = newTape
	profile.PackingXP = newXP
	profile.Stats = updatedStats
	profile.Collection.Discovered = newDiscovered
	profile.Collection.MasteryCounts = newMastery
	profile.Collection.RecentDiscoveries = newRecent
	profile.Receipts.ProcessedOutcomeIds = appendReceipt(profile.Receipts.ProcessedOutcomeIds, outcomeId)

	return true, freezeReward({
		OutcomeId = outcomeId,
		RoundId = roundId,
		OutcomeType = "Shipment",
		TapeDelta = shipmentRecord.ShipmentValue,
		NewTape = newTape,
		XPDelta = xpDelta,
		PreviousXP = previousXP,
		NewXP = newXP,
		PreviousRank = rankPresentation(previousXP),
		NewRank = rankPresentation(newXP),
		NewDiscoveries = discoveries,
		MasteryChanges = masteryChanges,
		UpdatedStats = immutableStats(updatedStats),
		Duplicate = false,
	}), "APPLIED"
end

function ProgressionService.ApplyFailureToProfile(
	profile: PersistedProfile,
	roundId: number,
	outcomeId: string,
	itemCount: number
): (boolean, ProgressionReward?, string)
	if not validIdentity(roundId, outcomeId) then
		return false, nil, "INVALID_OUTCOME_ID"
	end
	local xpDelta = ProgressionService.CalculateFailureXP(itemCount)
	if xpDelta == nil then
		return false, nil, "INVALID_ITEM_COUNT"
	end
	if hasReceipt(profile, outcomeId) then
		return false, duplicateReward(profile, outcomeId, roundId, "Failure"), "DUPLICATE"
	end
	local newXP = checkedAdd(profile.PackingXP, xpDelta)
	local totalFailed = checkedAdd(profile.Stats.TotalFailedRounds, 1)
	if newXP == nil or totalFailed == nil then
		return false, nil, "REWARD_OVERFLOW"
	end
	local previousXP = profile.PackingXP
	local updatedStats = copyStats(profile.Stats)
	updatedStats.TotalFailedRounds = totalFailed
	profile.PackingXP = newXP
	profile.Stats = updatedStats
	profile.Receipts.ProcessedOutcomeIds = appendReceipt(profile.Receipts.ProcessedOutcomeIds, outcomeId)
	return true, freezeReward({
		OutcomeId = outcomeId,
		RoundId = roundId,
		OutcomeType = "Failure",
		TapeDelta = 0,
		NewTape = profile.Tape,
		XPDelta = xpDelta,
		PreviousXP = previousXP,
		NewXP = newXP,
		PreviousRank = rankPresentation(previousXP),
		NewRank = rankPresentation(newXP),
		NewDiscoveries = {},
		MasteryChanges = {},
		UpdatedStats = immutableStats(updatedStats),
		Duplicate = false,
	}), "APPLIED"
end

function ProgressionService.Create(profileService: ProfileServiceContract): ProgressionServiceImpl
	return setmetatable({
		_profileService = profileService,
	}, ProgressionService) :: ProgressionServiceImpl
end

function ProgressionService.ApplyShipment(
	self: ProgressionServiceImpl,
	userId: number,
	roundId: number,
	outcomeId: string,
	shipmentRecord: ShipmentRecord
): (ProgressionReward?, string)
	local payload, code = self._profileService:ApplyMutation(userId, function(draft: PersistedProfile): (boolean, any?, string?)
		return ProgressionService.ApplyShipmentToProfile(draft, userId, roundId, outcomeId, shipmentRecord)
	end)
	return payload :: ProgressionReward?, code
end

function ProgressionService.ApplyFailure(
	self: ProgressionServiceImpl,
	userId: number,
	roundId: number,
	outcomeId: string,
	itemCount: number
): (ProgressionReward?, string)
	local payload, code = self._profileService:ApplyMutation(userId, function(draft: PersistedProfile): (boolean, any?, string?)
		return ProgressionService.ApplyFailureToProfile(draft, roundId, outcomeId, itemCount)
	end)
	return payload :: ProgressionReward?, code
end

return table.freeze(ProgressionService)
