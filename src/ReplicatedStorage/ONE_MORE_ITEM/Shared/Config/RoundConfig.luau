--!strict

local multipliers: { [number]: number } = {
	[1] = 1.00,
	[2] = 1.15,
	[3] = 1.35,
	[4] = 1.60,
	[5] = 1.90,
	[6] = 2.25,
	[7] = 2.65,
	[8] = 3.20,
	[9] = 3.90,
	[10] = 5.00,
}
table.freeze(multipliers)

local rateLimits: { [string]: number } = {
	ClientReadyRequest = 2,
	PlaceItemRequest = 10,
	DecisionRequest = 4,
	RestartRequest = 2,
}
table.freeze(rateLimits)

local RoundConfig = {
	INITIAL_PREPARING_DURATION = 0.12,
	RESTART_PREPARING_DURATION = 0.72,
	PRESENTATION_DURATION = 0.45,
	PLACEMENT_DURATION = 30,
	DECISION_DURATION = 8,
	SHIPPING_PRESENTATION_DURATION = 1.35,
	FAILURE_PRESENTATION_DURATION = 1.0,
	MAXIMUM_ITEMS = 10,
	FIRST_ITEM_ID = "parcel",
	DECISION_TIMEOUT_CHOICE = "SHIP",
	NO_LEGAL_CANDIDATE_REASON = "BOX_FULL",
	MAXIMUM_ITEMS_REASON = "MAX_ITEMS",
	GRID_CELL_SIZE = 2,
	MULTIPLIERS = multipliers,
	RATE_LIMITS_PER_SECOND = rateLimits,
	DEVELOPMENT = table.freeze({
		RUN_PHASE02_TESTS = true,
		RUN_PHASE03_TESTS = true,
		RUN_PHASE04_TESTS = true,
		RUN_PHASE05_TESTS = true,
		TEST_SEED = 24022026,
		PHASE03_TEST_SEED = 13072026,
		PHASE04_TEST_SEED = 14072026,
		PHASE05_TEST_SEED = 15072026,
	}),
}

return table.freeze(RoundConfig)
