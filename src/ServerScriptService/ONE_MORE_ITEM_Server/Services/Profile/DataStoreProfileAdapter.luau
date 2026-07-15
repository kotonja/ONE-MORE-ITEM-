--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileStoreAdapter = require(script.Parent.ProfileStoreAdapter)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type SessionClaim = ProfileTypes.SessionClaim
type StoreEnvironment = ProfileTypes.StoreEnvironment
type StoreResult = ProfileTypes.StoreResult

type Options = {
	DataStore: any?,
	IsStudio: boolean?,
}

type DataStoreProfileAdapterImpl = ProfileStoreAdapter.Adapter & {
	_store: any,
	_environment: StoreEnvironment,
	_storeName: string,
	GetStoreName: (self: DataStoreProfileAdapterImpl) -> string,
}

local DataStoreProfileAdapter = {}
DataStoreProfileAdapter.__index = DataStoreProfileAdapter

local function result(
	success: boolean,
	code: ProfileTypes.StoreResultCode,
	profile: PersistedProfile?,
	message: string?
): StoreResult
	return {
		Success = success,
		Code = code,
		Profile = if profile then ProfileSchema.Clone(profile) else nil,
		Message = message,
	}
end

local function protectedUpdate(store: any, key: string, transform: (any) -> any): (boolean, any)
	return pcall(function()
		return store:UpdateAsync(key, transform)
	end)
end

function DataStoreProfileAdapter.Create(options: Options?): DataStoreProfileAdapterImpl
	local resolved = options or {}
	-- An override may force the isolated Studio-test environment, but Studio can never be forced to production.
	local isStudio = RunService:IsStudio() or resolved.IsStudio == true
	local environment: StoreEnvironment = if isStudio then "StudioTest" else "Production"
	local storeName = if isStudio then ProfileConfig.STUDIO_STORE_NAME else ProfileConfig.PRODUCTION_STORE_NAME
	local store = resolved.DataStore
	if store == nil then
		local ok, fetchedOrError = pcall(function()
			return DataStoreService:GetDataStore(storeName)
		end)
		if not ok then
			error(string.format("Profile store unavailable for %s", environment))
		end
		store = fetchedOrError
	end
	return setmetatable({
		_store = store,
		_environment = environment,
		_storeName = storeName,
	}, DataStoreProfileAdapter) :: DataStoreProfileAdapterImpl
end

function DataStoreProfileAdapter.GetEnvironment(self: DataStoreProfileAdapterImpl): StoreEnvironment
	return self._environment
end

function DataStoreProfileAdapter.GetStoreName(self: DataStoreProfileAdapterImpl): string
	return self._storeName
end

function DataStoreProfileAdapter.CanRequest(_self: DataStoreProfileAdapterImpl, requestKind: string): boolean
	local requestType = if requestKind == "Load"
		then Enum.DataStoreRequestType.UpdateAsync
		else Enum.DataStoreRequestType.UpdateAsync
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	return ok and type(budget) == "number" and budget > 0
end

function DataStoreProfileAdapter.LoadAndLock(
	self: DataStoreProfileAdapterImpl,
	userId: number,
	claim: SessionClaim
): StoreResult
	local transformCode: ProfileTypes.StoreResultCode = "Unavailable"
	local captured: PersistedProfile? = nil
	local ok, updatedOrError = protectedUpdate(self._store, ProfileSchema.MakeKey(userId), function(current: any): any
		local migrated, migrationCode = ProfileSchema.Migrate(current, claim.Now)
		if migrated == nil then
			transformCode = if migrationCode == "UNSUPPORTED_FUTURE_SCHEMA" then "UnsupportedSchema" else "InvalidProfile"
			return nil
		end
		local currentSession = migrated.Session
		if currentSession ~= nil
			and currentSession.Token ~= claim.Token
			and not ProfileSchema.IsSessionStale(currentSession, claim.Now)
		then
			transformCode = "Locked"
			return nil
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
		transformCode = "Loaded"
		captured = ProfileSchema.Clone(migrated)
		return migrated
	end)
	if not ok then
		return result(false, "Unavailable", nil, tostring(updatedOrError))
	end
	if transformCode ~= "Loaded" or captured == nil then
		return result(false, transformCode, nil, nil)
	end
	return result(true, "Loaded", captured, nil)
end

function DataStoreProfileAdapter.Save(
	self: DataStoreProfileAdapterImpl,
	userId: number,
	profile: PersistedProfile,
	token: string,
	now: number
): StoreResult
	local saveCopy = ProfileSchema.Clone(profile)
	local transformCode: ProfileTypes.StoreResultCode = "Unavailable"
	local captured: PersistedProfile? = nil
	local ok, updatedOrError = protectedUpdate(self._store, ProfileSchema.MakeKey(userId), function(current: any): any
		local stored = ProfileSchema.Migrate(current, now)
		if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
			transformCode = "Conflict"
			return nil
		end
		local normalized = ProfileSchema.Normalize(saveCopy, now)
		if normalized == nil then
			transformCode = "InvalidProfile"
			return nil
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
		transformCode = "Saved"
		captured = ProfileSchema.Clone(normalized)
		return normalized
	end)
	if not ok then
		return result(false, "Unavailable", nil, tostring(updatedOrError))
	end
	if transformCode ~= "Saved" or captured == nil then
		return result(false, transformCode, nil, nil)
	end
	return result(true, "Saved", captured, nil)
end

function DataStoreProfileAdapter.Heartbeat(
	self: DataStoreProfileAdapterImpl,
	userId: number,
	token: string,
	now: number
): StoreResult
	local transformCode: ProfileTypes.StoreResultCode = "Unavailable"
	local captured: PersistedProfile? = nil
	local ok, updatedOrError = protectedUpdate(self._store, ProfileSchema.MakeKey(userId), function(current: any): any
		local stored = ProfileSchema.Migrate(current, now)
		if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
			transformCode = "Conflict"
			return nil
		end
		stored.Session.HeartbeatAt = math.floor(now)
		transformCode = "Heartbeated"
		captured = ProfileSchema.Clone(stored)
		return stored
	end)
	if not ok then
		return result(false, "Unavailable", nil, tostring(updatedOrError))
	end
	if transformCode ~= "Heartbeated" or captured == nil then
		return result(false, transformCode, nil, nil)
	end
	return result(true, "Heartbeated", captured, nil)
end

function DataStoreProfileAdapter.Release(
	self: DataStoreProfileAdapterImpl,
	userId: number,
	profile: PersistedProfile,
	token: string,
	now: number
): StoreResult
	local releaseCopy = ProfileSchema.Clone(profile)
	local transformCode: ProfileTypes.StoreResultCode = "Unavailable"
	local captured: PersistedProfile? = nil
	local ok, updatedOrError = protectedUpdate(self._store, ProfileSchema.MakeKey(userId), function(current: any): any
		local stored = ProfileSchema.Migrate(current, now)
		if stored == nil or stored.Session == nil or stored.Session.Token ~= token then
			transformCode = "Conflict"
			return nil
		end
		local normalized = ProfileSchema.Normalize(releaseCopy, now)
		if normalized == nil then
			transformCode = "InvalidProfile"
			return nil
		end
		normalized.CreatedAt = stored.CreatedAt
		normalized.UpdatedAt = math.max(stored.UpdatedAt, normalized.UpdatedAt, math.floor(now))
		normalized.Session = nil
		transformCode = "Released"
		captured = ProfileSchema.Clone(normalized)
		return normalized
	end)
	if not ok then
		return result(false, "Unavailable", nil, tostring(updatedOrError))
	end
	if transformCode ~= "Released" or captured == nil then
		return result(false, transformCode, nil, nil)
	end
	return result(true, "Released", captured, nil)
end

return table.freeze(DataStoreProfileAdapter)
