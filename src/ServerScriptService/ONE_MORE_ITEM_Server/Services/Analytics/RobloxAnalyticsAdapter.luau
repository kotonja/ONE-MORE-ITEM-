--!strict

local RobloxAnalyticsService = game:GetService("AnalyticsService")

local AnalyticsAdapter = require(script.Parent.AnalyticsAdapter)

type CustomFields = AnalyticsAdapter.CustomFields
type Clock = () -> number
type WarningSink = (string) -> ()

type Options = {
	Clock: Clock?,
	WarningSink: WarningSink?,
}

type AdapterImpl = AnalyticsAdapter.Adapter & {
	_clock: Clock,
	_warningSink: WarningSink,
	_lastWarningAt: number,
	_destroyed: boolean,
	_call: (self: AdapterImpl, label: string, callback: () -> ()) -> (boolean, string),
}

local RobloxAnalyticsAdapter = {}
RobloxAnalyticsAdapter.__index = RobloxAnalyticsAdapter

local function defaultClock(): number
	return os.clock()
end

local function defaultWarning(message: string)
	warn(message)
end

function RobloxAnalyticsAdapter.Create(options: Options?): AnalyticsAdapter.Adapter
	local resolved = options or {}
	return setmetatable({
		_clock = resolved.Clock or defaultClock,
		_warningSink = resolved.WarningSink or defaultWarning,
		_lastWarningAt = -math.huge,
		_destroyed = false,
	}, RobloxAnalyticsAdapter) :: any
end

function RobloxAnalyticsAdapter.GetEnvironment(_self: AdapterImpl): AnalyticsAdapter.Environment
	return "Roblox"
end

function RobloxAnalyticsAdapter._call(self: AdapterImpl, label: string, callback: () -> ()): (boolean, string)
	if self._destroyed then
		return false, "DESTROYED"
	end
	local ok = pcall(callback)
	if ok then
		return true, "LOGGED"
	end
	local now = self._clock()
	if now - self._lastWarningAt >= 30 then
		self._lastWarningAt = now
		self._warningSink(string.format("[ONE_MORE_ITEM][Analytics] %s failed", label))
	end
	return false, "ANALYTICS_FAILURE"
end

function RobloxAnalyticsAdapter.LogOnboardingStep(self: AdapterImpl, player: Player, step: number, stepName: string, fields: CustomFields): (boolean, string)
	return self:_call("Onboarding", function()
		RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, fields)
	end)
end

function RobloxAnalyticsAdapter.LogCustom(self: AdapterImpl, player: Player, eventName: string, value: number, fields: CustomFields): (boolean, string)
	return self:_call("Custom", function()
		RobloxAnalyticsService:LogCustomEvent(player, eventName, value, fields)
	end)
end

function RobloxAnalyticsAdapter.LogEconomySource(
	self: AdapterImpl,
	player: Player,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string,
	fields: CustomFields
): (boolean, string)
	return self:_call("Economy", function()
		RobloxAnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			currencyType,
			amount,
			endingBalance,
			transactionType,
			itemSku,
			fields
		)
	end)
end

function RobloxAnalyticsAdapter.LogProgressionStart(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return self:_call("ProgressionStart", function()
		RobloxAnalyticsService:LogProgressionStartEvent(player, pathName, level, levelName, fields)
	end)
end

function RobloxAnalyticsAdapter.LogProgressionComplete(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return self:_call("ProgressionComplete", function()
		RobloxAnalyticsService:LogProgressionCompleteEvent(player, pathName, level, levelName, fields)
	end)
end

function RobloxAnalyticsAdapter.LogProgressionFail(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return self:_call("ProgressionFail", function()
		RobloxAnalyticsService:LogProgressionFailEvent(player, pathName, level, levelName, fields)
	end)
end

function RobloxAnalyticsAdapter.Destroy(self: AdapterImpl)
	self._destroyed = true
end

return table.freeze(RobloxAnalyticsAdapter)
