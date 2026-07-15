--!strict

export type PackingRankDefinition = {
	Index: number,
	Name: string,
	Threshold: number,
}

export type RankProgress = {
	RankIndex: number,
	RankName: string,
	RankStartXP: number,
	NextRankXP: number?,
	XPIntoRank: number,
	XPRequiredForNextRank: number,
	Fraction: number,
}

local function definition(index: number, name: string, threshold: number): PackingRankDefinition
	return table.freeze({
		Index = index,
		Name = name,
		Threshold = threshold,
	}) :: PackingRankDefinition
end

local ordered: { PackingRankDefinition } = {
	definition(1, "Rookie Packer", 0),
	definition(2, "Box Handler", 300),
	definition(3, "Space Saver", 1_000),
	definition(4, "Packing Optimizer", 2_500),
	definition(5, "Master Packer", 5_000),
	definition(6, "Legendary Shipper", 9_000),
	definition(7, "Impossible Shipper", 15_000),
}
local seenNames: { [string]: boolean } = {}
local previousThreshold = -1
for expectedIndex, candidate in ipairs(ordered) do
	assert(candidate.Index == expectedIndex, "Packing rank indexes must be contiguous")
	assert(not seenNames[candidate.Name], string.format("Duplicate packing rank name: %s", candidate.Name))
	assert(candidate.Threshold > previousThreshold, "Packing rank thresholds must increase strictly")
	seenNames[candidate.Name] = true
	previousThreshold = candidate.Threshold
end
table.freeze(ordered)
table.freeze(seenNames)

local function normalizedXP(xp: number): number
	if xp ~= xp or xp == math.huge or xp == -math.huge then
		return 0
	end
	return math.max(0, math.floor(xp))
end

local PackingRankDefinitions = {
	Ordered = ordered,
}

function PackingRankDefinitions.GetRankIndexForXP(xp: number): number
	local value = normalizedXP(xp)
	local index = 1
	for candidateIndex, candidate in ipairs(ordered) do
		if value < candidate.Threshold then
			break
		end
		index = candidateIndex
	end
	return index
end

function PackingRankDefinitions.GetRankForXP(xp: number): PackingRankDefinition
	return ordered[PackingRankDefinitions.GetRankIndexForXP(xp)]
end

function PackingRankDefinitions.GetNextRank(xp: number): PackingRankDefinition?
	return ordered[PackingRankDefinitions.GetRankIndexForXP(xp) + 1]
end

function PackingRankDefinitions.GetThreshold(rankIndex: number): number?
	local candidate = ordered[rankIndex]
	return if candidate then candidate.Threshold else nil
end

function PackingRankDefinitions.GetProgress(xp: number): RankProgress
	local value = normalizedXP(xp)
	local current = PackingRankDefinitions.GetRankForXP(value)
	local nextRank = ordered[current.Index + 1]
	local xpIntoRank = value - current.Threshold
	local required = if nextRank then nextRank.Threshold - current.Threshold else 0
	local fraction = if nextRank then math.clamp(xpIntoRank / required, 0, 1) else 1
	return table.freeze({
		RankIndex = current.Index,
		RankName = current.Name,
		RankStartXP = current.Threshold,
		NextRankXP = if nextRank then nextRank.Threshold else nil,
		XPIntoRank = xpIntoRank,
		XPRequiredForNextRank = required,
		Fraction = fraction,
	}) :: RankProgress
end

return table.freeze(PackingRankDefinitions)
