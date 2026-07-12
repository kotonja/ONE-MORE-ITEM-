--!strict

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local GridTypes = require(script.Parent.GridTypes)

type Difficulty = GridTypes.Difficulty

local DifficultyClassifier = {}

function DifficultyClassifier.ClassifyPlacementCount(count: number): Difficulty
	if count < 0 or count ~= math.floor(count) then
		error("Placement count must be a non-negative integer", 2)
	end
	if count >= GameConfig.DIFFICULTY.EASY_MIN then
		return "Easy"
	elseif count >= GameConfig.DIFFICULTY.TIGHT_MIN then
		return "Tight"
	elseif count >= GameConfig.DIFFICULTY.BRUTAL_MIN then
		return "Brutal"
	end
	return "Impossible"
end

return table.freeze(DifficultyClassifier)
