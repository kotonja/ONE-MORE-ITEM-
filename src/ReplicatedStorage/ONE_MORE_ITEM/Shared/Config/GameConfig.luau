--!strict

local GameConfig = {
	BOX_WIDTH = 5,
	BOX_HEIGHT = 4,
	BOX_DEPTH = 5,
	BOX_CAPACITY = 100,
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
