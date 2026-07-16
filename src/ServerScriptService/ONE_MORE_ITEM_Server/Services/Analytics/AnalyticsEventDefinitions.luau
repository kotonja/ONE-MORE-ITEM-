--!strict

local CUSTOM_EVENT_NAMES = table.freeze({
	CoreLoopRound = "CoreLoopRound",
	OneMoreAccepted = "OneMoreAccepted",
	StarterMission = "StarterMission",
	OnboardingSkipped = "OnboardingSkipped",
	SessionDuration = "SessionDuration",
})

local allowedCustomEvents: { [string]: boolean } = {}
for _, eventName in pairs(CUSTOM_EVENT_NAMES) do
	allowedCustomEvents[eventName] = true
end
table.freeze(allowedCustomEvents)

local customFieldOrder: { [string]: { string } } = {
	CoreLoopRound = table.freeze({ "phase", "item_count_bucket", "reason" }),
	OneMoreAccepted = table.freeze({ "item_count_bucket", "difficulty" }),
	StarterMission = table.freeze({ "mission_id", "status" }),
	OnboardingSkipped = table.freeze({ "highest_step" }),
	SessionDuration = table.freeze({ "profile_ready", "station_assigned" }),
}
table.freeze(customFieldOrder)

local allowedRoundPhases = table.freeze({ start = true, ship = true, fail = true })
local allowedMissionStatuses = table.freeze({ started = true, completed = true, path_completed = true })
local allowedReasons = table.freeze({
	NONE = true,
	PLAYER_SHIPPED = true,
	DECISION_TIMEOUT = true,
	MAX_ITEMS = true,
	BOX_FULL = true,
	PLACEMENT_TIMEOUT = true,
	PROFILE_REWARD_FAILED = true,
})
local allowedDifficulties = table.freeze({
	UNKNOWN = true,
	["EASY FIT"] = true,
	["TIGHT FIT"] = true,
	["BRUTAL FIT"] = true,
})

local AnalyticsEventDefinitions = {
	CustomEventNames = CUSTOM_EVENT_NAMES,
	StarterPathName = "StarterPath",
	CurrencyType = "Tape",
	EconomySources = table.freeze({ Shipment = "Shipment", StarterMission = "StarterMission" }),
	MaximumDurationSeconds = 86_400,
	MaximumCustomValue = 9_007_199_254_740_991,
	MaximumCustomFields = 3,
}

function AnalyticsEventDefinitions.IsFixedCustomEvent(eventName: any): boolean
	return type(eventName) == "string" and allowedCustomEvents[eventName] == true
end

function AnalyticsEventDefinitions.GetCustomFieldOrder(eventName: string): { string }?
	return customFieldOrder[eventName]
end

function AnalyticsEventDefinitions.IsRoundPhase(value: any): boolean
	return type(value) == "string" and allowedRoundPhases[value] == true
end

function AnalyticsEventDefinitions.IsMissionStatus(value: any): boolean
	return type(value) == "string" and allowedMissionStatuses[value] == true
end

function AnalyticsEventDefinitions.NormalizeReason(value: any): string
	return if type(value) == "string" and allowedReasons[value] == true then value else "NONE"
end

function AnalyticsEventDefinitions.NormalizeDifficulty(value: any): string
	return if type(value) == "string" and allowedDifficulties[value] == true then value else "UNKNOWN"
end

function AnalyticsEventDefinitions.BucketItemCount(value: any): string
	local count = if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		then math.clamp(math.floor(value), 0, 10)
		else 0
	if count == 0 then
		return "0"
	elseif count == 1 then
		return "1"
	elseif count <= 3 then
		return "2-3"
	elseif count <= 5 then
		return "4-5"
	elseif count <= 7 then
		return "6-7"
	end
	return "8-10"
end

function AnalyticsEventDefinitions.ClampWholeSeconds(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, AnalyticsEventDefinitions.MaximumDurationSeconds)
end

return table.freeze(AnalyticsEventDefinitions)
