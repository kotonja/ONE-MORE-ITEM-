--!strict

export type MasteryTier = "Locked" | "Discovered" | "Bronze" | "Silver" | "Gold"

export type MasteryProgress = {
	Tier: MasteryTier,
	CurrentCount: number,
	TierStart: number,
	NextThreshold: number?,
	CountIntoTier: number,
	CountRequiredForNextTier: number,
	Fraction: number,
}

local thresholds = table.freeze({
	Bronze = 5,
	Silver = 20,
	Gold = 50,
})

local MasteryDefinitions = {
	Thresholds = thresholds,
}

local function normalizedCount(count: number): number
	if count ~= count or count == math.huge or count == -math.huge then
		return 0
	end
	return math.max(0, math.floor(count))
end

function MasteryDefinitions.GetMasteryTier(count: number, discovered: boolean?): MasteryTier
	local value = normalizedCount(count)
	if not discovered and value == 0 then
		return "Locked"
	elseif value >= thresholds.Gold then
		return "Gold"
	elseif value >= thresholds.Silver then
		return "Silver"
	elseif value >= thresholds.Bronze then
		return "Bronze"
	end
	return "Discovered"
end

function MasteryDefinitions.GetNextMasteryThreshold(count: number, discovered: boolean?): number?
	local tier = MasteryDefinitions.GetMasteryTier(count, discovered)
	if tier == "Locked" then
		return 1
	elseif tier == "Discovered" then
		return thresholds.Bronze
	elseif tier == "Bronze" then
		return thresholds.Silver
	elseif tier == "Silver" then
		return thresholds.Gold
	end
	return nil
end

function MasteryDefinitions.GetMasteryProgress(count: number, discovered: boolean?): MasteryProgress
	local value = normalizedCount(count)
	local tier = MasteryDefinitions.GetMasteryTier(value, discovered)
	local tierStart = 0
	if tier == "Discovered" then
		tierStart = 1
	elseif tier == "Bronze" then
		tierStart = thresholds.Bronze
	elseif tier == "Silver" then
		tierStart = thresholds.Silver
	elseif tier == "Gold" then
		tierStart = thresholds.Gold
	end
	local nextThreshold = MasteryDefinitions.GetNextMasteryThreshold(value, discovered)
	local required = if nextThreshold then nextThreshold - tierStart else 0
	local intoTier = math.max(0, value - tierStart)
	local fraction = if nextThreshold then math.clamp(intoTier / required, 0, 1) else 1
	return table.freeze({
		Tier = tier,
		CurrentCount = value,
		TierStart = tierStart,
		NextThreshold = nextThreshold,
		CountIntoTier = intoTier,
		CountRequiredForNextTier = required,
		Fraction = fraction,
	}) :: MasteryProgress
end

return table.freeze(MasteryDefinitions)
