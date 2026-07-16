--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local IntegerValidation = require(Root.Shared.Grid.IntegerValidation)
local OnboardingDefinitions = require(Root.Shared.Profile.OnboardingDefinitions)

export type ValidatedRequest = {
	Action: "SKIP",
	ClientSequence: number,
}

export type ValidationResult = {
	Accepted: boolean,
	Code: string,
	Request: ValidatedRequest?,
	ShouldWarn: boolean,
	RequestCount: number,
}

type Options = {
	RateLimitPerSecond: number?,
	WarningThreshold: number?,
}

export type Validator = {
	Validate: (
		self: Validator,
		userId: number,
		payload: unknown,
		canMutate: boolean,
		onboardingStatus: any,
		now: number
	) -> ValidationResult,
	MarkAccepted: (self: Validator, userId: number, clientSequence: number) -> (),
	RemoveUser: (self: Validator, userId: number) -> (),
}

type ValidatorImpl = Validator & {
	_rateLimit: number,
	_warningThreshold: number,
	_recent: { [number]: { number } },
	_counts: { [number]: number },
	_lastAccepted: { [number]: number },
	_warned: { [number]: boolean },
}

local OnboardingRequestValidator = {
	DEFAULT_RATE_LIMIT_PER_SECOND = 2,
	DEFAULT_WARNING_THRESHOLD = 10,
}
OnboardingRequestValidator.__index = OnboardingRequestValidator

local function makeResult(
	accepted: boolean,
	code: string,
	request: ValidatedRequest?,
	shouldWarn: boolean,
	requestCount: number
): ValidationResult
	return table.freeze({
		Accepted = accepted,
		Code = code,
		Request = request,
		ShouldWarn = shouldWarn,
		RequestCount = requestCount,
	})
end

function OnboardingRequestValidator.Create(options: Options?): Validator
	local resolved = options or {}
	return setmetatable({
		_rateLimit = math.max(1, math.floor(resolved.RateLimitPerSecond or 2)),
		_warningThreshold = math.max(1, math.floor(resolved.WarningThreshold or 10)),
		_recent = {},
		_counts = {},
		_lastAccepted = {},
		_warned = {},
	}, OnboardingRequestValidator) :: any
end

function OnboardingRequestValidator.Validate(
	self: ValidatorImpl,
	userId: number,
	payload: unknown,
	canMutate: boolean,
	onboardingStatus: any,
	now: number
): ValidationResult
	local count = (self._counts[userId] or 0) + 1
	self._counts[userId] = count
	local shouldWarn = count > self._warningThreshold and self._warned[userId] ~= true
	if shouldWarn then
		self._warned[userId] = true
	end

	local timestamps: { number } = {}
	for _, timestamp in ipairs(self._recent[userId] or {}) do
		if timestamp > now - 1 then
			table.insert(timestamps, timestamp)
		end
	end
	if #timestamps >= self._rateLimit then
		self._recent[userId] = timestamps
		return makeResult(false, "RATE_LIMITED", nil, shouldWarn, count)
	end
	table.insert(timestamps, now)
	self._recent[userId] = timestamps

	if not canMutate then
		return makeResult(false, "PROFILE_NOT_MUTABLE", nil, shouldWarn, count)
	end
	if OnboardingDefinitions.IsTerminal(onboardingStatus) then
		return makeResult(false, "ONBOARDING_TERMINAL", nil, shouldWarn, count)
	end
	if type(payload) ~= "table" then
		return makeResult(false, "MALFORMED_REQUEST", nil, shouldWarn, count)
	end
	local request = payload :: { [string]: unknown }
	if request.Action ~= "SKIP" then
		return makeResult(false, "INVALID_ACTION", nil, shouldWarn, count)
	end
	local sequence = request.ClientSequence
	if not IntegerValidation.IsFiniteInteger(sequence) or (sequence :: number) <= 0 then
		return makeResult(false, "INVALID_SEQUENCE", nil, shouldWarn, count)
	end
	if (sequence :: number) <= (self._lastAccepted[userId] or 0) then
		return makeResult(false, "DUPLICATE_SEQUENCE", nil, shouldWarn, count)
	end
	return makeResult(true, "VALID", table.freeze({
		Action = "SKIP",
		ClientSequence = sequence :: number,
	}), shouldWarn, count)
end

function OnboardingRequestValidator.MarkAccepted(self: ValidatorImpl, userId: number, clientSequence: number)
	if IntegerValidation.IsFiniteInteger(clientSequence) and clientSequence > (self._lastAccepted[userId] or 0) then
		self._lastAccepted[userId] = clientSequence
	end
end

function OnboardingRequestValidator.RemoveUser(self: ValidatorImpl, userId: number)
	self._recent[userId] = nil
	self._counts[userId] = nil
	self._lastAccepted[userId] = nil
	self._warned[userId] = nil
end

return table.freeze(OnboardingRequestValidator)
