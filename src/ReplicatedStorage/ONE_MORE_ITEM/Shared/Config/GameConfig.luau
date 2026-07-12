--!strict

local BOX_WIDTH = 5
local BOX_HEIGHT = 4
local BOX_DEPTH = 5

local GameConfig = {
	BOX_WIDTH = BOX_WIDTH,
	BOX_HEIGHT = BOX_HEIGHT,
	BOX_DEPTH = BOX_DEPTH,
	BOX_CAPACITY = BOX_WIDTH * BOX_HEIGHT * BOX_DEPTH,
	MAX_SHIPMENT_ITEMS = 10,
	DIFFICULTY = table.freeze({
		EASY_MIN = 10,
		TIGHT_MIN = 4,
		BRUTAL_MIN = 1,
	}),
	DEVELOPMENT = table.freeze({
		RUN_FOUNDATION_TESTS = true,
		FUZZ_CASES = 1000,
		FUZZ_SEED = 24012026,
		BENCHMARK_ITERATIONS = 100,
	}),
}

return table.freeze(GameConfig)
