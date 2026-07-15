--!strict

local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileStoreAdapter = require(script.Parent.ProfileStoreAdapter)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type SessionClaim = ProfileTypes.SessionClaim
type StoreResult = ProfileTypes.StoreResult

type BackingStore = { [string]: any }
type FailureFixture = {
	Remaining: number,
	Code: ProfileTypes.StoreResultCode,
}
type Options = {
	BackingStore: BackingStore?,
	BudgetAvailable: boolean?,
}
type MemoryProfileAdapterImpl = ProfileStoreAdapter.Adapter & {
	_backing: BackingStore,
	_budgetAvailable: boolean,
	_failures: { [string]: FailureFixture },
	_requestCounts: { [string]: number },
	_requestCountsByFixture: { [string]: number },
	SetBudgetAvailable: (self: MemoryProfileAdapterImpl, available: boolean) -> (),
	SetFailure: (
		self: MemoryProfileAdapterImpl,
		operation: string,
		userId: number,
		count: number,
		code: ProfileTypes.StoreResultCode?
	) -> (),
	SetLoadFailure: (self: MemoryProfileAdapterImpl, userId: number, count: number?) -> (),
	SetSaveFailure: (self: MemoryProfileAdapterImpl, userId: number, count: number?) -> (),
	SetReleaseFailure: (self: MemoryProfileAdapterImpl, userId: number, count: number?) -> (),
	Seed: (self: MemoryProfileAdapterImpl, userId: number, rawProfile: any) -> (),
	ReadStored: (self: MemoryProfileAdapterImpl, userId: number) -> any,
	GetRequestCount: (self: MemoryProfileAdapterImpl, operation: string) -> number,
	GetRequestCountForUser: (self: MemoryProfileAdapterImpl, operation: string, userId: number) -> number,
	SimulateServerCrash: (self: MemoryProfileAdapterImpl, userId: number) -> (),
	ForceSession: (self: MemoryProfileAdapterImpl, userId: number, session: ProfileTypes.ProfileSession?) -> (),
}

local MemoryProfileAdapter = {}
MemoryProfileAdapter.__index = MemoryProfileAdapter

local function deepCopy(value: any, seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local visited = seen or {}
	if visited[value] ~= nil then
		return visited[value]
	end
	local copied = {}
	visited[value] = copied
	for key, child in pairs(value) do
		copied[deepCopy(key, visited)] = deepCopy(child, visited)
	end
	return copied
end

local function result(
	success: boolean,
	code: ProfileTypes.StoreResultCode,
	profile: PersistedProfile?
): StoreResult
	return {
		Success = success,
		Code = code,
		Profile = if profile then ProfileSchema.Clone(profile) else nil,
		Message = nil,
	}
end

local function fixtureKey(operation: string, userId: number): string
	return string.format("%s:%d", operation, userId)
end

function MemoryProfileAdapter.Create(options: Options?): MemoryProfileAdapterImpl
	local resolved = options or {}
	return setmetatable({
		_backing = resolved.BackingStore or {},
		_budgetAvailable = if resolved.BudgetAvailable == nil then true else resolved.BudgetAvailable,
		_failures = {},
		_requestCounts = {},
		_requestCountsByFixture = {},
	}, MemoryProfileAdapter) :: MemoryProfileAdapterImpl
end

function MemoryProfileAdapter.GetEnvironment(_self: MemoryProfileAdapterImpl): ProfileTypes.StoreEnvironment
	return "Memory"
end

function MemoryProfileAdapter.CanRequest(self: MemoryProfileAdapterImpl, _requestKind: string): boolean
	return self._budgetAvailable
end

function MemoryProfileAdapter.SetBudgetAvailable(self: MemoryProfileAdapterImpl, available: boolean)
	self._budgetAvailable = available
end

function MemoryProfileAdapter.SetFailure(
	self: MemoryProfileAdapterImpl,
	operation: string,
	userId: number,
	count: number,
	code: ProfileTypes.StoreResultCode?
)
	self._failures[fixtureKey(operation, userId)] = {
		Remaining = math.max(0, math.floor(count)),
		Code = code or "Unavailable",
	}
end

function MemoryProfileAdapter.SetLoadFailure(self: MemoryProfileAdapterImpl, userId: number, count: number?)
	self:SetFailure("Load", userId, count or 1, "Unavailable")
end

function MemoryProfileAdapter.SetSaveFailure(self: MemoryProfileAdapterImpl, userId: number, count: number?)
	self:SetFailure("Save", userId, count or 1, "Unavailable")
end

function MemoryProfileAdapter.SetReleaseFailure(self: MemoryProfileAdapterImpl, userId: number, count: number?)
	self:SetFailure("Release", userId, count or 1, "Unavailable")
end

function MemoryProfileAdapter.Seed(self: MemoryProfileAdapterImpl, userId: number, rawProfile: any)
	self._backing[ProfileSchema.MakeKey(userId)] = deepCopy(rawProfile)
end

function MemoryProfileAdapter.ReadStored(self: MemoryProfileAdapterImpl, userId: number): any
	return deepCopy(self._backing[ProfileSchema.MakeKey(userId)])
end

function MemoryProfileAdapter.GetRequestCount(self: MemoryProfileAdapterImpl, operation: string): number
	return self._requestCounts[operation] or 0
end

function MemoryProfileAdapter.GetRequestCountForUser(
	self: MemoryProfileAdapterImpl,
	operation: string,
	userId: number
): number
	return self._requestCountsByFixture[fixtureKey(operation, userId)] or 0
end

local function consumeFailure(
	self: MemoryProfileAdapterImpl,
	operation: string,
	userId: number
): ProfileTypes.StoreResultCode?
	self._requestCounts[operation] = (self._requestCounts[operation] or 0) + 1
	local requestKey = fixtureKey(operation, userId)
	self._requestCountsByFixture[requestKey] = (self._requestCountsByFixture[requestKey] or 0) + 1
	if not self._budgetAvailable then
		return "BudgetDelayed"
	end
	local key = fixtureKey(operation, userId)
	local fixture = self._failures[key]
	if fixture == nil or fixture.Remaining <= 0 then
		return nil
	end
	fixture.Remaining -= 1
	return fixture.Code
end

function MemoryProfileAdapter.LoadAndLock(
	self: MemoryProfileAdapterImpl,
	userId: number,
	claim: SessionClaim
): StoreResult
	local failure = consumeFailure(self, "Load", userId)
	if failure then
		return result(false, failure, nil)
	end
	local key = ProfileSchema.MakeKey(userId)
	local migrated, migrationCode = ProfileSchema.Migrate(deepCopy(self._backing[key]), claim.Now)
	if migrated == nil then
		return result(false, if migrationCode == "UNSUPPORTED_FUTURE_SCHEMA" then "UnsupportedSchema" else "InvalidProfile", nil)
	end
	local currentSession = migrated.Session
	if currentSession ~= nil
		and currentSession.Token ~= claim.Token
		and not ProfileSchema.IsSessionStale(currentSession, claim.Now)
	then
		return result(false, "Locked", nil)
	end
	local acquiredAt = if currentSession ~= nil and currentSession.Token == claim.Token
		then currentSession.AcquiredAt
		else claim.Now
	migrated.Session = {
		Token = claim.Token,
		JobId = claim.JobId,
		PlaceId = claim.PlaceId,
		AcquiredAt = acquiredAt,
		HeartbeatAt = claim.Now,
	}
	self._backing[key] = ProfileSchema.Clone(migrated)
	return result(true, "Loaded", migrated)
end

function MemoryProfileAdapter.Save(
	self: MemoryProfileAdapterImpl,
	userId: number,
	profile: PersistedProfile,
	token: string,
	now: number
): StoreResult
	local failure = consumeFailure(self, "Save", userId)
	if failure then
		return result(false, failure, nil)
	end
	local key = ProfileSchema.MakeKey(userId)
	local stored = ProfileSchema.Migrate(deepCopy(self._backing[key]), now)
	if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
		return result(false, "Conflict", nil)
	end
	local normalized = ProfileSchema.Normalize(ProfileSchema.Clone(profile), now)
	if normalized == nil then
		return result(false, "InvalidProfile", nil)
	end
	normalized.CreatedAt = stored.CreatedAt
	normalized.UpdatedAt = math.max(stored.UpdatedAt, normalized.UpdatedAt, math.floor(now))
	normalized.Session = {
		Token = token,
		JobId = stored.Session.JobId,
		PlaceId = stored.Session.PlaceId,
		AcquiredAt = stored.Session.AcquiredAt,
		HeartbeatAt = math.floor(now),
	}
	self._backing[key] = ProfileSchema.Clone(normalized)
	return result(true, "Saved", normalized)
end

function MemoryProfileAdapter.Heartbeat(
	self: MemoryProfileAdapterImpl,
	userId: number,
	token: string,
	now: number
): StoreResult
	local failure = consumeFailure(self, "Heartbeat", userId)
	if failure then
		return result(false, failure, nil)
	end
	local key = ProfileSchema.MakeKey(userId)
	local stored = ProfileSchema.Migrate(deepCopy(self._backing[key]), now)
	if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
		return result(false, "Conflict", nil)
	end
	stored.Session.HeartbeatAt = math.floor(now)
	self._backing[key] = ProfileSchema.Clone(stored)
	return result(true, "Heartbeated", stored)
end

function MemoryProfileAdapter.Release(
	self: MemoryProfileAdapterImpl,
	userId: number,
	profile: PersistedProfile,
	token: string,
	now: number
): StoreResult
	local failure = consumeFailure(self, "Release", userId)
	if failure then
		return result(false, failure, nil)
	end
	local key = ProfileSchema.MakeKey(userId)
	local stored = ProfileSchema.Migrate(deepCopy(self._backing[key]), now)
	if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
		return result(false, "Conflict", nil)
	end
	local normalized = ProfileSchema.Normalize(ProfileSchema.Clone(profile), now)
	if normalized == nil then
		return result(false, "InvalidProfile", nil)
	end
	normalized.CreatedAt = stored.CreatedAt
	normalized.UpdatedAt = math.max(stored.UpdatedAt, normalized.UpdatedAt, math.floor(now))
	normalized.Session = nil
	self._backing[key] = ProfileSchema.Clone(normalized)
	return result(true, "Released", normalized)
end

function MemoryProfileAdapter.SimulateServerCrash(_self: MemoryProfileAdapterImpl, _userId: number)
	-- Intentionally leaves the persisted lock untouched for a new adapter/server fixture.
end

function MemoryProfileAdapter.ForceSession(self: MemoryProfileAdapterImpl, userId: number, session: ProfileTypes.ProfileSession?)
	local key = ProfileSchema.MakeKey(userId)
	local profile = ProfileSchema.Migrate(deepCopy(self._backing[key]), 0)
	if profile == nil then
		return
	end
	profile.Session = if session then deepCopy(session) else nil
	self._backing[key] = ProfileSchema.Clone(profile)
end

return table.freeze(MemoryProfileAdapter)
