--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)

type Buckets = { [string]: { number } }

type RequestRateLimiterImpl = {
	_buckets: Buckets,
}

local RequestRateLimiter = {}
RequestRateLimiter.__index = RequestRateLimiter

function RequestRateLimiter.Create(): RequestRateLimiterImpl
	return setmetatable({
		_buckets = {},
	}, RequestRateLimiter) :: RequestRateLimiterImpl
end

function RequestRateLimiter.Check(
	self: RequestRateLimiterImpl,
	userId: number,
	actionName: string,
	now: number
): boolean
	local limit = RoundConfig.RATE_LIMITS_PER_SECOND[actionName]
	if limit == nil then
		return false
	end

	local key = string.format("%d:%s", userId, actionName)
	local existing = self._buckets[key]
	local recent: { number } = {}
	if existing then
		for _, timestamp in ipairs(existing) do
			if timestamp > now - 1 then
				table.insert(recent, timestamp)
			end
		end
	end

	if #recent >= limit then
		self._buckets[key] = recent
		return false
	end

	table.insert(recent, now)
	self._buckets[key] = recent
	return true
end

function RequestRateLimiter.RemoveUser(self: RequestRateLimiterImpl, userId: number)
	local prefix = tostring(userId) .. ":"
	for key in pairs(self._buckets) do
		if string.sub(key, 1, #prefix) == prefix then
			self._buckets[key] = nil
		end
	end
end

return table.freeze(RequestRateLimiter)
