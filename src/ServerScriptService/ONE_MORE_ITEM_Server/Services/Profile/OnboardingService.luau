--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local OnboardingDefinitions = require(Root.Shared.Profile.OnboardingDefinitions)

local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type OnboardingStatus = OnboardingDefinitions.OnboardingStatus

export type OnboardingResult = {
	PreviousStatus: OnboardingStatus,
	NewStatus: OnboardingStatus,
	PreviousStep: number,
	NewStep: number,
	Completed: boolean,
	Skipped: boolean,
	Changed: boolean,
}

type ProfileServiceContract = {
	ApplyMutation: (
		self: ProfileServiceContract,
		userId: number,
		mutation: (PersistedProfile) -> (boolean, any?, string?)
	) -> (any?, string),
	GetProfileCopy: (self: ProfileServiceContract, userId: number) -> PersistedProfile?,
}

type AnalyticsContract = {
	LogOnboardingStep: (self: AnalyticsContract, player: Player, step: number) -> boolean,
	LogOnboardingSkipped: (self: AnalyticsContract, player: Player, highestStep: number) -> boolean,
}

type Options = {
	Clock: (() -> number)?,
}

export type Service = {
	Advance: (self: Service, player: Player, step: number) -> (OnboardingResult?, string),
	Skip: (self: Service, player: Player) -> (OnboardingResult?, string),
	IsGuided: (self: Service, player: Player) -> boolean,
}

type ServiceImpl = Service & {
	_profileService: ProfileServiceContract,
	_analytics: AnalyticsContract,
	_clock: () -> number,
}

local OnboardingService = {}
OnboardingService.__index = OnboardingService

local function defaultClock(): number
	return os.time()
end

local function result(
	previousStatus: OnboardingStatus,
	newStatus: OnboardingStatus,
	previousStep: number,
	newStep: number,
	changed: boolean
): OnboardingResult
	return table.freeze({
		PreviousStatus = previousStatus,
		NewStatus = newStatus,
		PreviousStep = previousStep,
		NewStep = newStep,
		Completed = newStatus == "Completed",
		Skipped = newStatus == "Skipped",
		Changed = changed,
	})
end

function OnboardingService.ApplyStepToProfile(
	profile: PersistedProfile,
	step: number,
	now: number
): (boolean, OnboardingResult, string)
	local onboarding = profile.Onboarding
	local previousStatus = onboarding.Status
	local previousStep = onboarding.HighestStep
	if OnboardingDefinitions.GetStep(step) == nil then
		return false, result(previousStatus, previousStatus, previousStep, previousStep, false), "INVALID_STEP"
	end
	if OnboardingDefinitions.IsTerminal(previousStatus) or step <= previousStep then
		return false, result(previousStatus, previousStatus, previousStep, previousStep, false), "NO_CHANGE"
	end

	local newStatus: OnboardingStatus = if step == OnboardingDefinitions.MaximumStep then "Completed" else "InProgress"
	onboarding.Version = 1
	onboarding.Status = newStatus
	onboarding.HighestStep = step
	onboarding.CompletedAt = if newStatus == "Completed" then math.max(0, math.floor(now)) else 0
	return true, result(previousStatus, newStatus, previousStep, step, true), "APPLIED"
end

function OnboardingService.ApplySkipToProfile(profile: PersistedProfile): (boolean, OnboardingResult, string)
	local onboarding = profile.Onboarding
	local previousStatus = onboarding.Status
	local previousStep = onboarding.HighestStep
	if OnboardingDefinitions.IsTerminal(previousStatus) then
		return false, result(previousStatus, previousStatus, previousStep, previousStep, false), "NO_CHANGE"
	end
	onboarding.Version = 1
	onboarding.Status = "Skipped"
	onboarding.CompletedAt = 0
	return true, result(previousStatus, "Skipped", previousStep, previousStep, true), "APPLIED"
end

function OnboardingService.Create(
	profileService: ProfileServiceContract,
	analytics: AnalyticsContract,
	options: Options?
): Service
	local resolved = options or {}
	return setmetatable({
		_profileService = profileService,
		_analytics = analytics,
		_clock = resolved.Clock or defaultClock,
	}, OnboardingService) :: any
end

function OnboardingService.Advance(self: ServiceImpl, player: Player, step: number): (OnboardingResult?, string)
	if OnboardingDefinitions.GetStep(step) == nil then
		return nil, "INVALID_STEP"
	end
	local payload, code = self._profileService:ApplyMutation(player.UserId, function(draft: PersistedProfile): (boolean, any?, string?)
		return OnboardingService.ApplyStepToProfile(draft, step, self._clock())
	end)
	local applied = payload :: OnboardingResult?
	if applied ~= nil and applied.Changed then
		pcall(function()
			self._analytics:LogOnboardingStep(player, applied.NewStep)
		end)
	end
	return applied, code
end

function OnboardingService.Skip(self: ServiceImpl, player: Player): (OnboardingResult?, string)
	local payload, code = self._profileService:ApplyMutation(player.UserId, function(draft: PersistedProfile): (boolean, any?, string?)
		return OnboardingService.ApplySkipToProfile(draft)
	end)
	local applied = payload :: OnboardingResult?
	if applied ~= nil and applied.Changed then
		pcall(function()
			self._analytics:LogOnboardingSkipped(player, applied.NewStep)
		end)
	end
	return applied, code
end

function OnboardingService.IsGuided(self: ServiceImpl, player: Player): boolean
	local profile = self._profileService:GetProfileCopy(player.UserId)
	return profile ~= nil and not OnboardingDefinitions.IsTerminal(profile.Onboarding.Status)
end

return table.freeze(OnboardingService)
