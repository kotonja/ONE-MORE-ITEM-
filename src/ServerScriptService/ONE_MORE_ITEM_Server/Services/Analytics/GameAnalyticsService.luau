--!strict

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local OnboardingDefinitions = require(Root.Shared.Profile.OnboardingDefinitions)
local StarterMissionDefinitions = require(Root.Shared.Profile.StarterMissionDefinitions)

local AnalyticsAdapter = require(script.Parent.AnalyticsAdapter)
local AnalyticsEventDefinitions = require(script.Parent.AnalyticsEventDefinitions)
local MemoryAnalyticsAdapter = require(script.Parent.MemoryAnalyticsAdapter)
local RobloxAnalyticsAdapter = require(script.Parent.RobloxAnalyticsAdapter)

type Adapter = AnalyticsAdapter.Adapter
type CustomFields = AnalyticsAdapter.CustomFields

type Options = {
	Adapter: Adapter?,
	IsStudio: boolean?,
}

export type Service = {
	GetEnvironment: (self: Service) -> AnalyticsAdapter.Environment,
	GetAdapter: (self: Service) -> Adapter,
	LogOnboardingStep: (self: Service, player: Player, step: number) -> boolean,
	LogCustom: (self: Service, player: Player, eventName: string, value: number, fields: { [string]: any }?) -> boolean,
	LogEconomySource: (self: Service, player: Player, source: string, amount: number, endingBalance: number, itemSku: string) -> boolean,
	LogProgressionStart: (self: Service, player: Player, missionId: string) -> boolean,
	LogProgressionComplete: (self: Service, player: Player, missionId: string) -> boolean,
	LogProgressionFail: (self: Service, player: Player, missionId: string) -> boolean,
	LogCoreLoopRound: (self: Service, player: Player, phase: string, duration: number, itemCount: number, reason: string?) -> boolean,
	LogOneMoreAccepted: (self: Service, player: Player, itemCount: number, difficulty: string?) -> boolean,
	LogStarterMission: (self: Service, player: Player, missionId: string, status: string) -> boolean,
	LogOnboardingSkipped: (self: Service, player: Player, highestStep: number) -> boolean,
	LogSessionDuration: (self: Service, player: Player, duration: number, profileReady: boolean, stationAssigned: boolean) -> boolean,
	Destroy: (self: Service) -> (),
}

type ServiceImpl = Service & {
	_adapter: Adapter,
	_destroyed: boolean,
}

local GameAnalyticsService = {}
GameAnalyticsService.__index = GameAnalyticsService

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sanitizeValue(value: any): AnalyticsAdapter.CustomFieldValue?
	if type(value) == "boolean" then
		return value
	elseif type(value) == "string" then
		return if #value <= 64 then value else string.sub(value, 1, 64)
	elseif isFiniteNumber(value) then
		return math.clamp(math.floor(value), -AnalyticsEventDefinitions.MaximumCustomValue, AnalyticsEventDefinitions.MaximumCustomValue)
	end
	return nil
end

local function sanitizeFields(eventName: string, raw: { [string]: any }?): CustomFields
	local sanitized: CustomFields = {}
	local order = AnalyticsEventDefinitions.GetCustomFieldOrder(eventName)
	if order == nil or raw == nil then
		return table.freeze(sanitized)
	end
	local count = 0
	for _, key in ipairs(order) do
		if count >= AnalyticsEventDefinitions.MaximumCustomFields then
			break
		end
		local value = sanitizeValue(raw[key])
		if value ~= nil then
			sanitized[key] = value
			count += 1
		end
	end
	return table.freeze(sanitized)
end

local function callAdapter(callback: () -> (boolean, string)): boolean
	local ok, accepted = pcall(callback)
	return ok and accepted == true
end

function GameAnalyticsService.Create(options: Options?): Service
	local resolved = options or {}
	local isStudio = if resolved.IsStudio == nil then RunService:IsStudio() else resolved.IsStudio
	local adapter = resolved.Adapter or (if isStudio then MemoryAnalyticsAdapter.Create() else RobloxAnalyticsAdapter.Create())
	return setmetatable({
		_adapter = adapter,
		_destroyed = false,
	}, GameAnalyticsService) :: any
end

function GameAnalyticsService.GetEnvironment(self: ServiceImpl): AnalyticsAdapter.Environment
	return self._adapter:GetEnvironment()
end

function GameAnalyticsService.GetAdapter(self: ServiceImpl): Adapter
	return self._adapter
end

function GameAnalyticsService.LogOnboardingStep(self: ServiceImpl, player: Player, step: number): boolean
	if self._destroyed then
		return false
	end
	local stepName = OnboardingDefinitions.GetStepName(step)
	if stepName == nil then
		return false
	end
	return callAdapter(function()
		return self._adapter:LogOnboardingStep(player, step, stepName, table.freeze({}))
	end)
end

function GameAnalyticsService.LogCustom(
	self: ServiceImpl,
	player: Player,
	eventName: string,
	value: number,
	fields: { [string]: any }?
): boolean
	if self._destroyed
		or not AnalyticsEventDefinitions.IsFixedCustomEvent(eventName)
		or not isFiniteNumber(value)
	then
		return false
	end
	local normalizedValue = math.clamp(math.floor(value), 0, AnalyticsEventDefinitions.MaximumCustomValue)
	local copiedFields = sanitizeFields(eventName, fields)
	return callAdapter(function()
		return self._adapter:LogCustom(player, eventName, normalizedValue, copiedFields)
	end)
end

function GameAnalyticsService.LogEconomySource(
	self: ServiceImpl,
	player: Player,
	source: string,
	amount: number,
	endingBalance: number,
	itemSku: string
): boolean
	if self._destroyed
		or (source ~= AnalyticsEventDefinitions.EconomySources.Shipment
			and source ~= AnalyticsEventDefinitions.EconomySources.StarterMission)
		or not isFiniteNumber(amount)
		or not isFiniteNumber(endingBalance)
		or amount < 0
		or endingBalance < 0
		or type(itemSku) ~= "string"
		or itemSku == ""
		or #itemSku > 96
	then
		return false
	end
	return callAdapter(function()
		return self._adapter:LogEconomySource(
			player,
			AnalyticsEventDefinitions.CurrencyType,
			math.floor(amount),
			math.floor(endingBalance),
			source,
			itemSku,
			table.freeze({})
		)
	end)
end

local function progression(self: ServiceImpl, player: Player, missionId: string, methodName: string): boolean
	if self._destroyed then
		return false
	end
	local definition = StarterMissionDefinitions.Get(missionId)
	if definition == nil then
		return false
	end
	local callback = if methodName == "start"
		then self._adapter.LogProgressionStart
		elseif methodName == "complete" then self._adapter.LogProgressionComplete
		else self._adapter.LogProgressionFail
	return callAdapter(function()
		return callback(
			self._adapter,
			player,
			AnalyticsEventDefinitions.StarterPathName,
			definition.Index,
			definition.Name,
			table.freeze({})
		)
	end)
end

function GameAnalyticsService.LogProgressionStart(self: ServiceImpl, player: Player, missionId: string): boolean
	return progression(self, player, missionId, "start")
end

function GameAnalyticsService.LogProgressionComplete(self: ServiceImpl, player: Player, missionId: string): boolean
	return progression(self, player, missionId, "complete")
end

function GameAnalyticsService.LogProgressionFail(self: ServiceImpl, player: Player, missionId: string): boolean
	return progression(self, player, missionId, "fail")
end

function GameAnalyticsService.LogCoreLoopRound(
	self: ServiceImpl,
	player: Player,
	phase: string,
	duration: number,
	itemCount: number,
	reason: string?
): boolean
	if not AnalyticsEventDefinitions.IsRoundPhase(phase) then
		return false
	end
	local value = if phase == "start" then 1 else AnalyticsEventDefinitions.ClampWholeSeconds(duration)
	return self:LogCustom(player, AnalyticsEventDefinitions.CustomEventNames.CoreLoopRound, value, {
		phase = phase,
		item_count_bucket = AnalyticsEventDefinitions.BucketItemCount(itemCount),
		reason = AnalyticsEventDefinitions.NormalizeReason(reason),
	})
end

function GameAnalyticsService.LogOneMoreAccepted(self: ServiceImpl, player: Player, itemCount: number, difficulty: string?): boolean
	if not isFiniteNumber(itemCount) then
		return false
	end
	return self:LogCustom(player, AnalyticsEventDefinitions.CustomEventNames.OneMoreAccepted, math.max(0, math.floor(itemCount)), {
		item_count_bucket = AnalyticsEventDefinitions.BucketItemCount(itemCount),
		difficulty = AnalyticsEventDefinitions.NormalizeDifficulty(difficulty),
	})
end

function GameAnalyticsService.LogStarterMission(self: ServiceImpl, player: Player, missionId: string, status: string): boolean
	local index = StarterMissionDefinitions.GetIndex(missionId)
	if index == nil or not AnalyticsEventDefinitions.IsMissionStatus(status) then
		return false
	end
	return self:LogCustom(player, AnalyticsEventDefinitions.CustomEventNames.StarterMission, index, {
		mission_id = missionId,
		status = status,
	})
end

function GameAnalyticsService.LogOnboardingSkipped(self: ServiceImpl, player: Player, highestStep: number): boolean
	if not isFiniteNumber(highestStep) then
		return false
	end
	local normalized = math.clamp(math.floor(highestStep), 0, OnboardingDefinitions.MaximumStep)
	return self:LogCustom(player, AnalyticsEventDefinitions.CustomEventNames.OnboardingSkipped, normalized, {
		highest_step = normalized,
	})
end

function GameAnalyticsService.LogSessionDuration(
	self: ServiceImpl,
	player: Player,
	duration: number,
	profileReady: boolean,
	stationAssigned: boolean
): boolean
	local seconds = AnalyticsEventDefinitions.ClampWholeSeconds(duration)
	return self:LogCustom(player, AnalyticsEventDefinitions.CustomEventNames.SessionDuration, seconds, {
		profile_ready = profileReady,
		station_assigned = stationAssigned,
	})
end

function GameAnalyticsService.Destroy(self: ServiceImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	pcall(function()
		self._adapter:Destroy()
	end)
end

return table.freeze(GameAnalyticsService)
