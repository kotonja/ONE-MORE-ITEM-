--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local DifficultyClassifier = require(Root.Shared.Grid.DifficultyClassifier)
local PlacementSolver = require(Root.Shared.Grid.PlacementSolver)
local GridTypes = require(Root.Shared.Grid.GridTypes)

type Grid = GridTypes.Grid
type DevelopmentItemDefinition = DevelopmentItemDefinitions.DevelopmentItemDefinition

export type Candidate = {
	Item: DevelopmentItemDefinition,
	ValidPlacementCount: number,
	Difficulty: string,
}

export type Service = {
	RecordOffer: (self: Service, itemId: string) -> (),
	EnumerateCandidates: (self: Service, grid: Grid) -> { Candidate },
	SelectNext: (self: Service, grid: Grid, lastItemId: string?) -> (Candidate?, string?),
}

type SequenceServiceImpl = Service & {
	_random: Random,
	_history: { string },
}

local SequenceService = {}
SequenceService.__index = SequenceService

local function difficultyLabel(count: number): string
	local difficulty = DifficultyClassifier.ClassifyPlacementCount(count)
	if difficulty == "Easy" then
		return "EASY FIT"
	elseif difficulty == "Tight" then
		return "TIGHT FIT"
	end
	return "BRUTAL FIT"
end

function SequenceService.StableRoundSeed(userId: number, roundId: number): number
	local mixed = (math.abs(userId) * 1103515245 + roundId * 12345 + 24022026) % 2147483647
	return math.max(1, math.floor(mixed))
end

function SequenceService.Create(seed: number): SequenceServiceImpl
	return setmetatable({
		_random = Random.new(seed),
		_history = {},
	}, SequenceService) :: SequenceServiceImpl
end

function SequenceService.RecordOffer(self: SequenceServiceImpl, itemId: string)
	table.insert(self._history, itemId)
end

function SequenceService.GetFirstItem(): DevelopmentItemDefinition
	local first = DevelopmentItemDefinitions.Get("parcel")
	if not first then
		error("Development item definitions must include Parcel", 2)
	end
	return first
end

function SequenceService.EnumerateCandidates(_self: SequenceServiceImpl, grid: Grid): { Candidate }
	local candidates: { Candidate } = {}
	for _, definition in ipairs(DevelopmentItemDefinitions.Ordered) do
		local count = #PlacementSolver.EnumerateLegalPlacements(grid, definition.Shape)
		if count > 0 then
			table.insert(candidates, {
				Item = definition,
				ValidPlacementCount = count,
				Difficulty = difficultyLabel(count),
			})
		end
	end
	return candidates
end

local function filterImmediateRepeat(candidates: { Candidate }, lastItemId: string?): { Candidate }
	if not lastItemId or #candidates <= 1 then
		return candidates
	end
	local filtered: { Candidate } = {}
	for _, candidate in ipairs(candidates) do
		if candidate.Item.Id ~= lastItemId then
			table.insert(filtered, candidate)
		end
	end
	return if #filtered > 0 then filtered else candidates
end

local function filterFamilyStreak(candidates: { Candidate }, history: { string }): { Candidate }
	if #history < 2 or #candidates <= 1 then
		return candidates
	end
	local previous = DevelopmentItemDefinitions.Get(history[#history])
	local beforePrevious = DevelopmentItemDefinitions.Get(history[#history - 1])
	if not previous or not beforePrevious or previous.ShapeFamily ~= beforePrevious.ShapeFamily then
		return candidates
	end

	local filtered: { Candidate } = {}
	for _, candidate in ipairs(candidates) do
		if candidate.Item.ShapeFamily ~= previous.ShapeFamily then
			table.insert(filtered, candidate)
		end
	end
	return if #filtered > 0 then filtered else candidates
end

function SequenceService.SelectNext(
	self: SequenceServiceImpl,
	grid: Grid,
	lastItemId: string?
): (Candidate?, string?)
	local candidates = self:EnumerateCandidates(grid)
	if #candidates == 0 then
		return nil, "BOX_FULL"
	end
	candidates = filterImmediateRepeat(candidates, lastItemId)
	candidates = filterFamilyStreak(candidates, self._history)
	local selected = candidates[self._random:NextInteger(1, #candidates)]
	if not selected then
		error("Candidate selection index was invalid", 2)
	end
	self:RecordOffer(selected.Item.Id)
	return selected, nil
end

return table.freeze(SequenceService)
