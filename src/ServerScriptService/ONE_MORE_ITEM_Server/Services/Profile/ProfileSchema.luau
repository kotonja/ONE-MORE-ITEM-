--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:FindFirstChild("ONE_MORE_ITEM")
assert(Root ~= nil, "ProfileSchema requires ReplicatedStorage.ONE_MORE_ITEM")
local Shared = Root:FindFirstChild("Shared")
assert(Shared ~= nil, "ProfileSchema requires Shared")
local Profile = Shared:FindFirstChild("Profile")
assert(Profile ~= nil, "ProfileSchema requires Shared.Profile")
local CollectionDefinitionsModule = Profile:FindFirstChild("CollectionDefinitions")
assert(CollectionDefinitionsModule ~= nil and CollectionDefinitionsModule:IsA("ModuleScript"), "ProfileSchema requires CollectionDefinitions")
local CollectionDefinitions = require(CollectionDefinitionsModule)
local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileTypes = require(script.Parent.ProfileTypes)

type PersistedProfile = ProfileTypes.PersistedProfile
type Statistics = ProfileTypes.Statistics
type ProfileSession = ProfileTypes.ProfileSession

local ProfileSchema = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeNow(value: number): number
	if not isFiniteNumber(value) then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function nonNegativeInteger(value: any, fallback: number): number
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(math.floor(value), 0, ProfileConfig.MAXIMUM_SAFE_INTEGER)
end

local function defaultStats(): Statistics
	return {
		TotalSuccessfulShipments = 0,
		TotalItemsShipped = 0,
		HighestItemsInShipment = 0,
		BestShipmentValue = 0,
		PerfectShipments = 0,
		TotalFailedRounds = 0,
		TotalTapeEarned = 0,
	}
end

function ProfileSchema.CreateDefault(now: number): PersistedProfile
	local timestamp = safeNow(now)
	return {
		SchemaVersion = ProfileConfig.SCHEMA_VERSION,
		Tape = 0,
		PackingXP = 0,
		Stats = defaultStats(),
		Collection = {
			Discovered = {},
			MasteryCounts = {},
			RecentDiscoveries = {},
		},
		Receipts = {
			ProcessedOutcomeIds = {},
		},
		CreatedAt = timestamp,
		UpdatedAt = timestamp,
		Session = nil,
	}
end

local function copyStats(stats: Statistics): Statistics
	return {
		TotalSuccessfulShipments = stats.TotalSuccessfulShipments,
		TotalItemsShipped = stats.TotalItemsShipped,
		HighestItemsInShipment = stats.HighestItemsInShipment,
		BestShipmentValue = stats.BestShipmentValue,
		PerfectShipments = stats.PerfectShipments,
		TotalFailedRounds = stats.TotalFailedRounds,
		TotalTapeEarned = stats.TotalTapeEarned,
	}
end

local function copySession(session: ProfileSession?): ProfileSession?
	if session == nil then
		return nil
	end
	return {
		Token = session.Token,
		JobId = session.JobId,
		PlaceId = session.PlaceId,
		AcquiredAt = session.AcquiredAt,
		HeartbeatAt = session.HeartbeatAt,
	}
end

function ProfileSchema.Clone(profile: PersistedProfile): PersistedProfile
	local discovered: { [string]: boolean } = {}
	for itemId, isDiscovered in pairs(profile.Collection.Discovered) do
		if isDiscovered then
			discovered[itemId] = true
		end
	end
	local masteryCounts: { [string]: number } = {}
	for itemId, count in pairs(profile.Collection.MasteryCounts) do
		masteryCounts[itemId] = count
	end
	return {
		SchemaVersion = profile.SchemaVersion,
		Tape = profile.Tape,
		PackingXP = profile.PackingXP,
		Stats = copyStats(profile.Stats),
		Collection = {
			Discovered = discovered,
			MasteryCounts = masteryCounts,
			RecentDiscoveries = table.clone(profile.Collection.RecentDiscoveries),
		},
		Receipts = {
			ProcessedOutcomeIds = table.clone(profile.Receipts.ProcessedOutcomeIds),
		},
		CreatedAt = profile.CreatedAt,
		UpdatedAt = profile.UpdatedAt,
		Session = copySession(profile.Session),
	}
end

local function normalizeStats(raw: any): Statistics
	local source = if type(raw) == "table" then raw else {}
	return {
		TotalSuccessfulShipments = nonNegativeInteger(source.TotalSuccessfulShipments, 0),
		TotalItemsShipped = nonNegativeInteger(source.TotalItemsShipped, 0),
		HighestItemsInShipment = nonNegativeInteger(source.HighestItemsInShipment, 0),
		BestShipmentValue = nonNegativeInteger(source.BestShipmentValue, 0),
		PerfectShipments = nonNegativeInteger(source.PerfectShipments, 0),
		TotalFailedRounds = nonNegativeInteger(source.TotalFailedRounds, 0),
		TotalTapeEarned = nonNegativeInteger(source.TotalTapeEarned, 0),
	}
end

local function normalizeSession(raw: any, now: number): ProfileSession?
	if type(raw) ~= "table" or type(raw.Token) ~= "string" or raw.Token == "" then
		return nil
	end
	if type(raw.JobId) ~= "string" or not isFiniteNumber(raw.PlaceId) then
		return nil
	end
	local acquiredAt = math.min(now, nonNegativeInteger(raw.AcquiredAt, now))
	local heartbeatAt = math.clamp(nonNegativeInteger(raw.HeartbeatAt, acquiredAt), acquiredAt, now)
	return {
		Token = raw.Token,
		JobId = raw.JobId,
		PlaceId = nonNegativeInteger(raw.PlaceId, 0),
		AcquiredAt = acquiredAt,
		HeartbeatAt = heartbeatAt,
	}
end

local function normalizeCollection(raw: any): ({ [string]: boolean }, { [string]: number }, { string })
	local source = if type(raw) == "table" then raw else {}
	local rawDiscovered = if type(source.Discovered) == "table" then source.Discovered else {}
	local rawMastery = if type(source.MasteryCounts) == "table" then source.MasteryCounts else {}
	local discovered: { [string]: boolean } = {}
	local mastery: { [string]: number } = {}

	for _, itemId in ipairs(CollectionDefinitions.OrderedItemIds) do
		local count = nonNegativeInteger(rawMastery[itemId], 0)
		local isDiscovered = rawDiscovered[itemId] == true or count > 0
		if isDiscovered then
			discovered[itemId] = true
			mastery[itemId] = math.max(1, count)
		end
	end

	local recent: { string } = {}
	local seenRecent: { [string]: boolean } = {}
	local rawRecent = if type(source.RecentDiscoveries) == "table" then source.RecentDiscoveries else {}
	for _, candidate in ipairs(rawRecent) do
		if type(candidate) == "string"
			and discovered[candidate] == true
			and not seenRecent[candidate]
		then
			seenRecent[candidate] = true
			table.insert(recent, candidate)
		end
	end
	while #recent > ProfileConfig.MAXIMUM_RECENT_DISCOVERY_COUNT do
		table.remove(recent, 1)
	end
	return discovered, mastery, recent
end

local function normalizeReceipts(raw: any): { string }
	local source = if type(raw) == "table" and type(raw.ProcessedOutcomeIds) == "table"
		then raw.ProcessedOutcomeIds
		else {}
	local receipts: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, candidate in ipairs(source) do
		if type(candidate) == "string"
			and candidate ~= ""
			and #candidate <= ProfileConfig.MAXIMUM_OUTCOME_ID_LENGTH
			and not seen[candidate]
		then
			seen[candidate] = true
			table.insert(receipts, candidate)
		end
	end
	while #receipts > ProfileConfig.MAXIMUM_RECEIPT_COUNT do
		table.remove(receipts, 1)
	end
	return receipts
end

local function normalizeV1(raw: any, now: number): PersistedProfile
	local timestamp = safeNow(now)
	local discovered, mastery, recent = normalizeCollection(raw.Collection)
	local createdAt = math.min(timestamp, nonNegativeInteger(raw.CreatedAt, timestamp))
	local updatedAt = math.clamp(nonNegativeInteger(raw.UpdatedAt, createdAt), createdAt, timestamp)
	return {
		SchemaVersion = ProfileConfig.SCHEMA_VERSION,
		Tape = nonNegativeInteger(raw.Tape, 0),
		PackingXP = nonNegativeInteger(raw.PackingXP, 0),
		Stats = normalizeStats(raw.Stats),
		Collection = {
			Discovered = discovered,
			MasteryCounts = mastery,
			RecentDiscoveries = recent,
		},
		Receipts = {
			ProcessedOutcomeIds = normalizeReceipts(raw.Receipts),
		},
		CreatedAt = createdAt,
		UpdatedAt = updatedAt,
		Session = normalizeSession(raw.Session, timestamp),
	}
end

local function migrateV0(raw: any, now: number): PersistedProfile
	local discovered: { [string]: boolean } = {}
	local legacyDiscovered = if type(raw.DiscoveredItems) == "table" then raw.DiscoveredItems else {}
	for key, value in pairs(legacyDiscovered) do
		local candidate = if type(key) == "number" then value else key
		local enabled = if type(key) == "number" then true else value == true
		if enabled and type(candidate) == "string" and CollectionDefinitions.IsValidItemId(candidate) then
			discovered[candidate] = true
		end
	end
	local fixture = {
		SchemaVersion = 1,
		Tape = raw.Tape,
		PackingXP = raw.PackingXP,
		Stats = raw.Stats,
		Collection = {
			Discovered = discovered,
			MasteryCounts = if type(raw.Mastery) == "table" then raw.Mastery else {},
			RecentDiscoveries = if type(raw.RecentDiscoveries) == "table" then raw.RecentDiscoveries else {},
		},
		Receipts = {
			ProcessedOutcomeIds = {},
		},
		CreatedAt = raw.CreatedAt,
		UpdatedAt = raw.UpdatedAt,
		Session = nil,
	}
	return normalizeV1(fixture, now)
end

function ProfileSchema.Migrate(raw: any, now: number): (PersistedProfile?, string)
	if raw == nil then
		return ProfileSchema.CreateDefault(now), "CREATED_V1"
	end
	if type(raw) ~= "table" then
		return nil, "INVALID_PROFILE"
	end

	local version = raw.SchemaVersion
	if isFiniteNumber(version) and version > ProfileConfig.SCHEMA_VERSION then
		return nil, "UNSUPPORTED_FUTURE_SCHEMA"
	end
	if version == ProfileConfig.SCHEMA_VERSION then
		return normalizeV1(raw, now), "NORMALIZED_V1"
	end
	if version == 0 or version == nil then
		return migrateV0(raw, now), "MIGRATED_V0_TO_V1"
	end
	return nil, "INVALID_SCHEMA_VERSION"
end

function ProfileSchema.Normalize(profile: PersistedProfile, now: number): (PersistedProfile?, string)
	return ProfileSchema.Migrate(profile, now)
end

function ProfileSchema.IsSessionStale(session: ProfileSession, now: number): boolean
	return safeNow(now) - session.HeartbeatAt >= ProfileConfig.STALE_LOCK_SECONDS
end

function ProfileSchema.MakeKey(userId: number): string
	return ProfileConfig.KEY_PREFIX .. tostring(math.floor(userId))
end

return table.freeze(ProfileSchema)
