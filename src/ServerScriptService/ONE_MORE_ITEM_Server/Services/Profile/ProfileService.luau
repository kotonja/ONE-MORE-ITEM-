--!strict

local HttpService = game:GetService("HttpService")

local ProfileConfig = require(script.Parent.ProfileConfig)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileSnapshotBuilder = require(script.Parent.ProfileSnapshotBuilder)
local ProfileStoreAdapter = require(script.Parent.ProfileStoreAdapter)
local ProfileTypes = require(script.Parent.ProfileTypes)

type Adapter = ProfileStoreAdapter.Adapter
type PersistedProfile = ProfileTypes.PersistedProfile
type ProfileLifecycleState = ProfileTypes.ProfileLifecycleState
type ProfileSaveState = ProfileTypes.ProfileSaveState
type ProfileSnapshot = ProfileTypes.ProfileSnapshot
type ProgressionReward = ProfileTypes.ProgressionReward
type StarterMissionReward = ProfileTypes.StarterMissionReward

type Clock = () -> number
type Wait = (number) -> ()
type IdentifierFactory = () -> string
type Spawn = (() -> ()) -> ()
type SnapshotSink = (number, ProfileSnapshot) -> ()
type LifecycleSink = (number, ProfileLifecycleState) -> ()
type Scheduler = {
	Schedule: (number, () -> ()) -> any,
	Cancel: ((any) -> ())?,
}
type Options = {
	Clock: Clock?,
	Wait: Wait?,
	IdentifierFactory: IdentifierFactory?,
	PresentationIdentifierFactory: IdentifierFactory?,
	Spawn: Spawn?,
	Scheduler: Scheduler?,
	AutoSchedule: boolean?,
	ServerSessionId: string?,
	JobId: string?,
	PlaceId: number?,
	SnapshotSink: SnapshotSink?,
	LifecycleSink: LifecycleSink?,
}

type ProfileEntry = {
	UserId: number,
	State: ProfileLifecycleState,
	SaveState: ProfileSaveState,
	Profile: PersistedProfile?,
	Token: string,
	ProfileSessionId: string,
	SnapshotRevision: number,
	MutationRevision: number,
	Dirty: boolean,
	NextSaveAt: number,
	NextAutosaveAt: number,
	NextHeartbeatAt: number,
	ConsecutiveSaveFailures: number,
	LastReward: ProgressionReward?,
	LastMissionRewards: { StarterMissionReward },
	LoadInFlight: boolean,
	SaveInFlight: boolean,
	HeartbeatInFlight: boolean,
	ReleaseInProgress: boolean,
	LastReleaseSuccess: boolean?,
	LastReleaseCode: string?,
	LastNotifiedState: ProfileLifecycleState?,
}

type Mutation = (PersistedProfile) -> (boolean, any?, string?)
type MissionMutation = (PersistedProfile) -> (boolean, any?, { StarterMissionReward }?, string?)

export type Service = {
	LoadPlayer: (self: Service, userId: number) -> (boolean, string),
	GetServerSessionId: (self: Service) -> string,
	GetStoreEnvironment: (self: Service) -> ProfileTypes.StoreEnvironment,
	GetActiveSaveCount: (self: Service) -> number,
	CanEnterGameplay: (self: Service, userId: number) -> boolean,
	CanMutate: (self: Service, userId: number) -> boolean,
	ApplyMutation: (self: Service, userId: number, mutation: Mutation) -> (any?, string),
	ApplyMutationWithMissionRewards: (
		self: Service,
		userId: number,
		mutation: MissionMutation
	) -> (any?, string),
	GetTape: (self: Service, userId: number) -> number?,
	GetProfileCopy: (self: Service, userId: number) -> PersistedProfile?,
	GetState: (self: Service, userId: number) -> ProfileLifecycleState?,
	GetSnapshot: (self: Service, userId: number) -> ProfileSnapshot?,
	PublishSnapshot: (self: Service, userId: number) -> ProfileSnapshot?,
	SaveNow: (self: Service, userId: number) -> (boolean, string),
	ProcessDueSaves: (self: Service, now: number?) -> number,
	BeginRelease: (self: Service, userId: number) -> boolean,
	Release: (self: Service, userId: number) -> (boolean, string),
	BeginShutdown: (self: Service) -> (),
	Shutdown: (self: Service, deadlineSeconds: number?) -> { Successes: number, Failures: number, Skipped: number },
}

type ProfileServiceImpl = Service & {
	_adapter: Adapter,
	_clock: Clock,
	_wait: Wait,
	_identifierFactory: IdentifierFactory,
	_presentationIdentifierFactory: IdentifierFactory,
	_spawn: Spawn,
	_scheduler: Scheduler?,
	_autoSchedule: boolean,
	_serverSessionId: string,
	_jobId: string,
	_placeId: number,
	_snapshotSink: SnapshotSink?,
	_lifecycleSink: LifecycleSink?,
	_entries: { [number]: ProfileEntry },
	_loadOrdinals: { [number]: number },
	_shuttingDown: boolean,
	_shutdownDeadlineAt: number?,
	_activeSaves: number,
	_scheduledHandle: any?,
	_scheduleGeneration: number,
	_notifyLifecycle: (self: ProfileServiceImpl, entry: ProfileEntry) -> (),
	_setState: (
		self: ProfileServiceImpl,
		entry: ProfileEntry,
		state: ProfileLifecycleState,
		saveState: ProfileSaveState
	) -> (),
	_cancelScheduled: (self: ProfileServiceImpl) -> (),
	_reschedule: (self: ProfileServiceImpl) -> (),
	_handleStoreConflict: (self: ProfileServiceImpl, entry: ProfileEntry) -> (boolean, string),
	_heartbeat: (self: ProfileServiceImpl, entry: ProfileEntry) -> (boolean, string),
}

local ProfileService = {}
ProfileService.__index = ProfileService

local function defaultClock(): number
	return os.time()
end

local function defaultWait(duration: number)
	task.wait(duration)
end

local function defaultIdentifier(): string
	return HttpService:GenerateGUID(false)
end

local function defaultSpawn(callback: () -> ())
	task.spawn(callback)
end

local function defaultScheduler(): Scheduler
	return {
		Schedule = function(duration: number, callback: () -> ()): thread
			return task.delay(duration, callback)
		end,
		Cancel = function(handle: any)
			if type(handle) == "thread" then
				task.cancel(handle)
			end
		end,
	}
end

local function backoffSeconds(attempt: number): number
	return math.min(ProfileConfig.RETRY_MAX_SECONDS, ProfileConfig.RETRY_BASE_SECONDS * (2 ^ math.max(0, attempt - 1)))
end

local function waitUntilInactive(
	self: ProfileServiceImpl,
	isActive: () -> boolean,
	maximumWaits: number
): boolean
	local shutdownDeadline = self._shutdownDeadlineAt
	if self._shuttingDown and shutdownDeadline ~= nil then
		local remaining = math.max(0, shutdownDeadline - self._clock())
		local remainingPolls = math.max(1, math.ceil(remaining / 0.05) + 1)
		while isActive() and self._clock() < shutdownDeadline and remainingPolls > 0 do
			remainingPolls -= 1
			self._wait(math.min(0.05, math.max(0, shutdownDeadline - self._clock())))
		end
		return not isActive()
	end
	for attempt = 1, maximumWaits do
		if not isActive() then
			return true
		end
		self._wait(backoffSeconds(attempt))
	end
	return not isActive()
end

local function waitForRetry(self: ProfileServiceImpl, duration: number): boolean
	local shutdownDeadline = self._shutdownDeadlineAt
	if not self._shuttingDown or shutdownDeadline == nil then
		self._wait(duration)
		return true
	end
	local remaining = shutdownDeadline - self._clock()
	if remaining <= 0 then
		return false
	end
	self._wait(math.min(duration, remaining))
	return self._clock() < shutdownDeadline
end

local function copySession(profile: PersistedProfile): ProfileTypes.ProfileSession?
	local session = profile.Session
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

local function sortedUserIds(entries: { [number]: ProfileEntry }): { number }
	local userIds: { number } = {}
	for userId in pairs(entries) do
		table.insert(userIds, userId)
	end
	table.sort(userIds)
	return userIds
end

function ProfileService.Create(adapter: Adapter, options: Options?): ProfileServiceImpl
	local resolved = options or {}
	local identifierFactory = resolved.IdentifierFactory or defaultIdentifier
	local serverSessionId = resolved.ServerSessionId
	if serverSessionId == nil or serverSessionId == "" then
		serverSessionId = if game.JobId ~= "" then game.JobId else identifierFactory()
	end
	local autoSchedule = if resolved.AutoSchedule == nil then true else resolved.AutoSchedule
	return setmetatable({
		_adapter = adapter,
		_clock = resolved.Clock or defaultClock,
		_wait = resolved.Wait or defaultWait,
		_identifierFactory = identifierFactory,
		_presentationIdentifierFactory = resolved.PresentationIdentifierFactory or defaultIdentifier,
		_spawn = resolved.Spawn or defaultSpawn,
		_scheduler = resolved.Scheduler or (if autoSchedule then defaultScheduler() else nil),
		_autoSchedule = autoSchedule,
		_serverSessionId = serverSessionId,
		_jobId = resolved.JobId or game.JobId,
		_placeId = resolved.PlaceId or game.PlaceId,
		_snapshotSink = resolved.SnapshotSink,
		_lifecycleSink = resolved.LifecycleSink,
		_entries = {},
		_loadOrdinals = {},
		_shuttingDown = false,
		_shutdownDeadlineAt = nil,
		_activeSaves = 0,
		_scheduledHandle = nil,
		_scheduleGeneration = 0,
	}, ProfileService) :: ProfileServiceImpl
end

function ProfileService.GetServerSessionId(self: ProfileServiceImpl): string
	return self._serverSessionId
end

function ProfileService.GetStoreEnvironment(self: ProfileServiceImpl): ProfileTypes.StoreEnvironment
	return self._adapter:GetEnvironment()
end

function ProfileService.GetActiveSaveCount(self: ProfileServiceImpl): number
	return self._activeSaves
end

function ProfileService._notifyLifecycle(self: ProfileServiceImpl, entry: ProfileEntry)
	local callback = self._lifecycleSink
	if callback == nil or entry.LastNotifiedState == entry.State then
		return
	end
	entry.LastNotifiedState = entry.State
	local ok, failure = pcall(callback, entry.UserId, entry.State)
	if not ok then
		warn(string.format("[ONE_MORE_ITEM][Profile] lifecycle callback failed userId=%d reason=%s", entry.UserId, tostring(failure)))
	end
end

function ProfileService.PublishSnapshot(self: ProfileServiceImpl, userId: number): ProfileSnapshot?
	local entry = self._entries[userId]
	if entry == nil then
		return nil
	end
	entry.SnapshotRevision += 1
	local snapshot = ProfileSnapshotBuilder.Build(
		entry.Profile,
		entry.State,
		entry.SaveState,
		entry.SnapshotRevision,
		entry.ProfileSessionId,
		entry.LastReward,
		entry.LastMissionRewards
	)
	local callback = self._snapshotSink
	if callback ~= nil then
		local ok, failure = pcall(callback, userId, snapshot)
		if not ok then
			warn(string.format("[ONE_MORE_ITEM][Profile] snapshot callback failed userId=%d reason=%s", userId, tostring(failure)))
		end
	end
	self:_notifyLifecycle(entry)
	return snapshot
end

function ProfileService.GetSnapshot(self: ProfileServiceImpl, userId: number): ProfileSnapshot?
	local entry = self._entries[userId]
	if entry == nil then
		return nil
	end
	return ProfileSnapshotBuilder.Build(
		entry.Profile,
		entry.State,
		entry.SaveState,
		entry.SnapshotRevision,
		entry.ProfileSessionId,
		entry.LastReward,
		entry.LastMissionRewards
	)
end

function ProfileService._setState(
	self: ProfileServiceImpl,
	entry: ProfileEntry,
	state: ProfileLifecycleState,
	saveState: ProfileSaveState
)
	entry.State = state
	entry.SaveState = saveState
	self:PublishSnapshot(entry.UserId)
end

function ProfileService._cancelScheduled(self: ProfileServiceImpl)
	self._scheduleGeneration += 1
	if self._scheduledHandle ~= nil and self._scheduler ~= nil and self._scheduler.Cancel ~= nil then
		self._scheduler.Cancel(self._scheduledHandle)
	end
	self._scheduledHandle = nil
end

function ProfileService._reschedule(self: ProfileServiceImpl)
	if not self._autoSchedule or self._scheduler == nil or self._shuttingDown then
		return
	end
	local earliest: number? = nil
	for _, entry in pairs(self._entries) do
		if entry.Profile ~= nil
			and not entry.SaveInFlight
			and not entry.HeartbeatInFlight
			and self:CanEnterGameplay(entry.UserId)
		then
			local dueAt = entry.NextHeartbeatAt
			if entry.Dirty then
				dueAt = math.min(dueAt, entry.NextSaveAt, entry.NextAutosaveAt)
			end
			if earliest == nil or dueAt < earliest then
				earliest = dueAt
			end
		end
	end
	self:_cancelScheduled()
	if earliest == nil then
		return
	end
	local generation = self._scheduleGeneration
	local delaySeconds = math.max(0, earliest - self._clock())
	self._scheduledHandle = self._scheduler.Schedule(delaySeconds, function()
		if self._scheduleGeneration ~= generation then
			return
		end
		self._scheduledHandle = nil
		self:ProcessDueSaves()
	end)
end

function ProfileService.LoadPlayer(self: ProfileServiceImpl, userId: number): (boolean, string)
	if self._shuttingDown then
		return false, "SHUTTING_DOWN"
	end
	local existing = self._entries[userId]
	if existing ~= nil and existing.State == "Releasing" then
		waitUntilInactive(self, function(): boolean
			return existing.State == "Releasing" or existing.ReleaseInProgress or existing.LoadInFlight
		end, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS)
		existing = self._entries[userId]
	end
	if existing ~= nil then
		if existing.State == "Released" or existing.State == "Unavailable" or existing.State == "Conflict" then
			self._entries[userId] = nil
		else
			return false, if existing.State == "Releasing" then "RELEASE_IN_PROGRESS" else "ALREADY_LOADED"
		end
	end
	local now = math.floor(self._clock())
	local loadOrdinal = (self._loadOrdinals[userId] or 0) + 1
	self._loadOrdinals[userId] = loadOrdinal
	local entry: ProfileEntry = {
		UserId = userId,
		State = "Loading",
		SaveState = "Loading",
		Profile = nil,
		Token = string.format("lock:%s:%d:%d:%s", self._serverSessionId, userId, loadOrdinal, self._identifierFactory()),
		ProfileSessionId = string.format("profile:%d:%s", loadOrdinal, self._presentationIdentifierFactory()),
		SnapshotRevision = 0,
		MutationRevision = 0,
		Dirty = false,
		NextSaveAt = now + ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS,
		NextAutosaveAt = now + ProfileConfig.AUTOSAVE_INTERVAL_SECONDS,
		NextHeartbeatAt = now + ProfileConfig.SESSION_HEARTBEAT_SECONDS,
		ConsecutiveSaveFailures = 0,
		LastReward = nil,
		LastMissionRewards = table.freeze({}),
		LoadInFlight = true,
		SaveInFlight = false,
		HeartbeatInFlight = false,
		ReleaseInProgress = false,
		LastReleaseSuccess = nil,
		LastReleaseCode = nil,
		LastNotifiedState = nil,
	}
	self._entries[userId] = entry
	self:PublishSnapshot(userId)

	local finalCode = "Unavailable"
	for attempt = 1, ProfileConfig.MAXIMUM_LOAD_ATTEMPTS do
		local requestNow = math.floor(self._clock())
		local storeResult: ProfileTypes.StoreResult
		if not self._adapter:CanRequest("Load") then
			storeResult = { Success = false, Code = "BudgetDelayed", Profile = nil, Message = nil }
		else
			local ok, responseOrFailure = pcall(function()
				return self._adapter:LoadAndLock(userId, {
					Token = entry.Token,
					JobId = self._jobId,
					PlaceId = self._placeId,
					Now = requestNow,
				})
			end)
			storeResult = if ok
				then responseOrFailure :: ProfileTypes.StoreResult
				else { Success = false, Code = "Unavailable", Profile = nil, Message = tostring(responseOrFailure) }
		end
		finalCode = storeResult.Code
		if storeResult.Success and storeResult.Profile ~= nil then
			entry.Profile = ProfileSchema.Clone(storeResult.Profile)
			entry.LoadInFlight = false
			if entry.State == "Releasing" or self._shuttingDown then
				entry.Dirty = false
				entry.ConsecutiveSaveFailures = 0
				self:PublishSnapshot(userId)
				local released, releaseCode = self:Release(userId)
				return false, if released then "RELEASED_DURING_LOAD" else releaseCode
			end
			entry.State = "Ready"
			entry.SaveState = "Saved"
			entry.Dirty = false
			entry.ConsecutiveSaveFailures = 0
			entry.NextSaveAt = requestNow + ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
			entry.NextAutosaveAt = requestNow + ProfileConfig.AUTOSAVE_INTERVAL_SECONDS
			entry.NextHeartbeatAt = requestNow + ProfileConfig.SESSION_HEARTBEAT_SECONDS
			self:PublishSnapshot(userId)
			self:_reschedule()
			return true, "READY"
		end
		if entry.State == "Releasing" or self._shuttingDown then
			entry.LoadInFlight = false
			entry.State = "Released"
			entry.SaveState = "Released"
			entry.LastReleaseSuccess = true
			entry.LastReleaseCode = "RELEASED_EMPTY"
			self:PublishSnapshot(userId)
			return false, "RELEASED_DURING_LOAD"
		end
		if storeResult.Code == "Locked" or storeResult.Code == "Conflict" then
			entry.LoadInFlight = false
			self:_setState(entry, "Conflict", "Conflict")
			return false, "CONFLICT"
		end
		if not ProfileStoreAdapter.IsRetryable(storeResult.Code) then
			break
		end
		if attempt < ProfileConfig.MAXIMUM_LOAD_ATTEMPTS then
			self._wait(backoffSeconds(attempt))
		end
	end
	entry.LoadInFlight = false
	self:_setState(entry, "Unavailable", "Unavailable")
	return false, string.upper(finalCode)
end

function ProfileService.GetState(self: ProfileServiceImpl, userId: number): ProfileLifecycleState?
	local entry = self._entries[userId]
	return if entry then entry.State else nil
end

function ProfileService.CanEnterGameplay(self: ProfileServiceImpl, userId: number): boolean
	local entry = self._entries[userId]
	if entry == nil or entry.Profile == nil then
		return false
	end
	return entry.State == "Ready" or entry.State == "Saving" or entry.State == "SaveDelayed"
end

function ProfileService.CanMutate(self: ProfileServiceImpl, userId: number): boolean
	return not self._shuttingDown and self:CanEnterGameplay(userId)
end

function ProfileService.GetProfileCopy(self: ProfileServiceImpl, userId: number): PersistedProfile?
	local entry = self._entries[userId]
	if entry == nil or entry.Profile == nil then
		return nil
	end
	return ProfileSchema.Clone(entry.Profile)
end

function ProfileService.GetTape(self: ProfileServiceImpl, userId: number): number?
	local entry = self._entries[userId]
	return if entry and entry.Profile then entry.Profile.Tape else nil
end

function ProfileService.ApplyMutation(
	self: ProfileServiceImpl,
	userId: number,
	mutation: Mutation
): (any?, string)
	if not self:CanMutate(userId) then
		return nil, "PROFILE_NOT_MUTABLE"
	end
	local entry = self._entries[userId]
	local current = entry.Profile
	if current == nil then
		return nil, "PROFILE_NOT_LOADED"
	end
	local draft = ProfileSchema.Clone(current)
	local originalSession = copySession(current)
	local ok, acceptedOrFailure, payload, reason = pcall(mutation, draft)
	if not ok then
		return nil, "MUTATION_ERROR"
	end
	if acceptedOrFailure ~= true then
		return payload, reason or "REJECTED"
	end
	draft.Session = originalSession
	draft.UpdatedAt = math.max(draft.UpdatedAt, math.floor(self._clock()))
	local normalized = ProfileSchema.Normalize(draft, self._clock())
	if normalized == nil then
		return nil, "INVALID_MUTATION"
	end
	normalized.Session = originalSession
	entry.Profile = normalized
	entry.MutationRevision += 1
	local wasDirty = entry.Dirty
	entry.Dirty = true
	if entry.State ~= "SaveDelayed" then
		entry.State = "Saving"
		entry.SaveState = "Saving"
	end
	local debouncedSaveAt = self._clock() + ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
	entry.NextSaveAt = if wasDirty then math.min(entry.NextSaveAt, debouncedSaveAt) else debouncedSaveAt
	if type(payload) == "table" and type(payload.OutcomeId) == "string" then
		entry.LastReward = ProfileSnapshotBuilder.CopyReward(payload :: ProgressionReward)
	end
	self:PublishSnapshot(userId)
	self:_reschedule()
	return payload, reason or "APPLIED"
end

function ProfileService.ApplyMutationWithMissionRewards(
	self: ProfileServiceImpl,
	userId: number,
	mutation: MissionMutation
): (any?, string)
	if not self:CanMutate(userId) then
		return nil, "PROFILE_NOT_MUTABLE"
	end
	local entry = self._entries[userId]
	local current = entry.Profile
	if current == nil then
		return nil, "PROFILE_NOT_LOADED"
	end
	local draft = ProfileSchema.Clone(current)
	local originalSession = copySession(current)
	local ok, acceptedOrFailure, payload, missionRewards, reason = pcall(mutation, draft)
	if not ok then
		return nil, "MUTATION_ERROR"
	end
	if acceptedOrFailure ~= true then
		return payload, reason or "REJECTED"
	end

	local rewardsOk, copiedRewardsOrFailure = pcall(function(): { StarterMissionReward }
		return ProfileSnapshotBuilder.CopyMissionRewards(missionRewards)
	end)
	if not rewardsOk then
		return nil, "INVALID_MISSION_REWARD_BATCH"
	end
	local copiedRewards = copiedRewardsOrFailure :: { StarterMissionReward }
	draft.Session = originalSession
	draft.UpdatedAt = math.max(draft.UpdatedAt, math.floor(self._clock()))
	local normalized = ProfileSchema.Normalize(draft, self._clock())
	if normalized == nil then
		return nil, "INVALID_MUTATION"
	end
	normalized.Session = originalSession
	entry.Profile = normalized
	entry.MutationRevision += 1
	local wasDirty = entry.Dirty
	entry.Dirty = true
	if entry.State ~= "SaveDelayed" then
		entry.State = "Saving"
		entry.SaveState = "Saving"
	end
	local debouncedSaveAt = self._clock() + ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
	entry.NextSaveAt = if wasDirty then math.min(entry.NextSaveAt, debouncedSaveAt) else debouncedSaveAt
	entry.LastMissionRewards = copiedRewards
	self:PublishSnapshot(userId)
	self:_reschedule()
	return payload, reason or "APPLIED"
end

function ProfileService._handleStoreConflict(self: ProfileServiceImpl, entry: ProfileEntry): (boolean, string)
	entry.Dirty = true
	self:_setState(entry, "Conflict", "Conflict")
	self:_reschedule()
	return false, "CONFLICT"
end

function ProfileService.SaveNow(self: ProfileServiceImpl, userId: number): (boolean, string)
	local entry = self._entries[userId]
	if entry == nil or entry.Profile == nil then
		return false, "PROFILE_NOT_LOADED"
	end
	if entry.State == "Conflict" or entry.State == "Releasing" or entry.State == "Released" then
		return false, "PROFILE_NOT_SAVEABLE"
	end
	if self._activeSaves >= ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES then
		entry.NextSaveAt = self._clock() + ProfileConfig.RETRY_BASE_SECONDS
		return false, "SAVE_LIMIT"
	end
	if entry.SaveInFlight then
		return false, "SAVE_IN_FLIGHT"
	end
	if entry.HeartbeatInFlight then
		entry.NextSaveAt = self._clock() + ProfileConfig.RETRY_BASE_SECONDS
		return false, "HEARTBEAT_IN_FLIGHT"
	end
	if not entry.Dirty then
		return true, "CLEAN"
	end

	self._activeSaves += 1
	entry.SaveInFlight = true
	entry.State = "Saving"
	entry.SaveState = "Saving"
	self:PublishSnapshot(userId)
	local capturedRevision = entry.MutationRevision
	local saveCopy = ProfileSchema.Clone(entry.Profile)
	local now = math.floor(self._clock())
	local storeResult: ProfileTypes.StoreResult
	if not self._adapter:CanRequest("Save") then
		storeResult = { Success = false, Code = "BudgetDelayed", Profile = nil, Message = nil }
	else
		local ok, responseOrFailure = pcall(function()
			return self._adapter:Save(userId, saveCopy, entry.Token, now)
		end)
		storeResult = if ok
			then responseOrFailure :: ProfileTypes.StoreResult
			else { Success = false, Code = "Unavailable", Profile = nil, Message = tostring(responseOrFailure) }
	end
	self._activeSaves -= 1
	entry.SaveInFlight = false

	if storeResult.Success and storeResult.Profile ~= nil then
		if entry.MutationRevision == capturedRevision then
			entry.Profile = ProfileSchema.Clone(storeResult.Profile)
			entry.Dirty = false
		else
			entry.Profile.Session = copySession(storeResult.Profile)
			entry.Dirty = true
		end
		if entry.State ~= "Releasing" then
			if entry.Dirty then
				entry.State = "Saving"
				entry.SaveState = "Saving"
			else
				entry.State = "Ready"
				entry.SaveState = "Saved"
			end
		end
		entry.ConsecutiveSaveFailures = 0
		entry.NextAutosaveAt = now + ProfileConfig.AUTOSAVE_INTERVAL_SECONDS
		entry.NextHeartbeatAt = now + ProfileConfig.SESSION_HEARTBEAT_SECONDS
		entry.NextSaveAt = now + ProfileConfig.DIRTY_SAVE_DEBOUNCE_SECONDS
		self:PublishSnapshot(userId)
		self:_reschedule()
		return true, "SAVED"
	end
	if storeResult.Code == "Conflict" or storeResult.Code == "Locked" then
		return self:_handleStoreConflict(entry)
	end
	entry.ConsecutiveSaveFailures = math.min(ProfileConfig.MAXIMUM_SAVE_ATTEMPTS, entry.ConsecutiveSaveFailures + 1)
	entry.Dirty = true
	if entry.State ~= "Releasing" then
		entry.State = "SaveDelayed"
		entry.SaveState = "SaveDelayed"
	end
	local retryDelay = if entry.ConsecutiveSaveFailures >= ProfileConfig.MAXIMUM_SAVE_ATTEMPTS
		then ProfileConfig.AUTOSAVE_INTERVAL_SECONDS
		else backoffSeconds(entry.ConsecutiveSaveFailures)
	entry.NextSaveAt = self._clock() + retryDelay
	entry.NextAutosaveAt = math.max(entry.NextAutosaveAt, entry.NextSaveAt)
	self:PublishSnapshot(userId)
	self:_reschedule()
	return false, storeResult.Code
end

function ProfileService._heartbeat(self: ProfileServiceImpl, entry: ProfileEntry): (boolean, string)
	if entry.Profile == nil or not self:CanEnterGameplay(entry.UserId) then
		return false, "PROFILE_NOT_AVAILABLE"
	end
	if entry.SaveInFlight or entry.HeartbeatInFlight then
		return false, "WRITE_IN_FLIGHT"
	end
	local now = math.floor(self._clock())
	if not self._adapter:CanRequest("Heartbeat") then
		entry.NextHeartbeatAt = self._clock() + ProfileConfig.RETRY_BASE_SECONDS
		entry.State = "SaveDelayed"
		entry.SaveState = "SaveDelayed"
		self:PublishSnapshot(entry.UserId)
		return false, "BUDGET_DELAYED"
	end
	if self._activeSaves >= ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES then
		entry.NextHeartbeatAt = self._clock() + ProfileConfig.RETRY_BASE_SECONDS
		entry.State = "SaveDelayed"
		entry.SaveState = "SaveDelayed"
		self:PublishSnapshot(entry.UserId)
		return false, "SAVE_LIMIT"
	end
	self._activeSaves += 1
	entry.HeartbeatInFlight = true
	local ok, responseOrFailure = pcall(function()
		return self._adapter:Heartbeat(entry.UserId, entry.Token, now)
	end)
	entry.HeartbeatInFlight = false
	self._activeSaves -= 1
	local storeResult: ProfileTypes.StoreResult = if ok
		then responseOrFailure :: ProfileTypes.StoreResult
		else { Success = false, Code = "Unavailable", Profile = nil, Message = tostring(responseOrFailure) }
	if entry.Profile == nil or entry.State == "Releasing" or entry.State == "Released" then
		return false, "PROFILE_RELEASING"
	end
	if storeResult.Success and storeResult.Profile ~= nil then
		entry.Profile.Session = copySession(storeResult.Profile)
		entry.NextHeartbeatAt = now + ProfileConfig.SESSION_HEARTBEAT_SECONDS
		if entry.State == "SaveDelayed" and not entry.Dirty then
			entry.State = "Ready"
			entry.SaveState = "Saved"
			self:PublishSnapshot(entry.UserId)
		end
		return true, "HEARTBEATED"
	end
	if storeResult.Code == "Conflict" or storeResult.Code == "Locked" then
		return self:_handleStoreConflict(entry)
	end
	entry.NextHeartbeatAt = self._clock() + ProfileConfig.RETRY_BASE_SECONDS
	entry.State = "SaveDelayed"
	entry.SaveState = "SaveDelayed"
	self:PublishSnapshot(entry.UserId)
	return false, storeResult.Code
end

function ProfileService.ProcessDueSaves(self: ProfileServiceImpl, nowOverride: number?): number
	if self._shuttingDown then
		return 0
	end
	local now = nowOverride or self._clock()
	local processed = 0
	for _, userId in ipairs(sortedUserIds(self._entries)) do
		if processed >= ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES then
			break
		end
		local entry = self._entries[userId]
		if entry ~= nil and not entry.SaveInFlight and not entry.HeartbeatInFlight and self:CanEnterGameplay(userId) then
			local autosaveDue = entry.Dirty and now >= entry.NextAutosaveAt
			local dirtySaveDue = entry.Dirty and now >= entry.NextSaveAt
			local heartbeatDue = now >= entry.NextHeartbeatAt
			if autosaveDue or dirtySaveDue then
				self:SaveNow(userId)
				processed += 1
			elseif heartbeatDue then
				self:_heartbeat(entry)
				processed += 1
			end
		end
	end
	self:_reschedule()
	return processed
end

function ProfileService.BeginRelease(self: ProfileServiceImpl, userId: number): boolean
	local entry = self._entries[userId]
	if entry == nil or entry.State == "Released" then
		return false
	end
	entry.State = "Releasing"
	entry.SaveState = "Releasing"
	self:PublishSnapshot(userId)
	self:_reschedule()
	return true
end

function ProfileService.Release(self: ProfileServiceImpl, userId: number): (boolean, string)
	local entry = self._entries[userId]
	if entry == nil then
		return false, "PROFILE_NOT_LOADED"
	end
	if entry.State == "Released" then
		if entry.LastReleaseSuccess == false then
			return false, entry.LastReleaseCode or "RELEASE_FAILED"
		end
		return true, entry.LastReleaseCode or "ALREADY_RELEASED"
	end
	if entry.ReleaseInProgress then
		local completed = waitUntilInactive(self, function(): boolean
			return entry.ReleaseInProgress
		end, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS - 1)
		if not completed then
			return false, "RELEASE_IN_PROGRESS"
		end
		return entry.LastReleaseSuccess == true, entry.LastReleaseCode or "RELEASE_FAILED"
	end
	entry.ReleaseInProgress = true
	entry.LastReleaseSuccess = nil
	entry.LastReleaseCode = nil
	if entry.State ~= "Releasing" then
		self:BeginRelease(userId)
	end
	local loadCompleted = waitUntilInactive(self, function(): boolean
		return entry.LoadInFlight
	end, ProfileConfig.MAXIMUM_LOAD_ATTEMPTS - 1)
	if not loadCompleted then
		entry.ReleaseInProgress = false
		entry.LastReleaseSuccess = false
		entry.LastReleaseCode = "LOAD_IN_FLIGHT"
		return false, "LOAD_IN_FLIGHT"
	end
	local writeCompleted = waitUntilInactive(self, function(): boolean
		return entry.SaveInFlight or entry.HeartbeatInFlight
	end, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS - 1)
	if not writeCompleted then
		entry.ReleaseInProgress = false
		entry.LastReleaseSuccess = false
		entry.LastReleaseCode = "WRITE_IN_FLIGHT"
		return false, "WRITE_IN_FLIGHT"
	end
	if entry.Profile == nil then
		entry.State = "Released"
		entry.SaveState = "Released"
		entry.ReleaseInProgress = false
		entry.LastReleaseSuccess = true
		entry.LastReleaseCode = "RELEASED_EMPTY"
		self:PublishSnapshot(userId)
		return true, "RELEASED_EMPTY"
	end

	local finalCode = "Unavailable"
	for attempt = 1, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS do
		local capacityAvailable = waitUntilInactive(self, function(): boolean
			return self._activeSaves >= ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES
		end, ProfileConfig.MAXIMUM_SAVE_ATTEMPTS - 1)
		if not capacityAvailable then
			finalCode = "SaveLimit"
			break
		end
		if self._adapter:CanRequest("Release") then
			local now = math.floor(self._clock())
			self._activeSaves += 1
			local ok, responseOrFailure = pcall(function()
				return self._adapter:Release(userId, entry.Profile :: PersistedProfile, entry.Token, now)
			end)
			self._activeSaves -= 1
			local storeResult: ProfileTypes.StoreResult = if ok
				then responseOrFailure :: ProfileTypes.StoreResult
				else { Success = false, Code = "Unavailable", Profile = nil, Message = tostring(responseOrFailure) }
			finalCode = storeResult.Code
			if storeResult.Success then
				entry.Profile = nil
				entry.Dirty = false
				entry.State = "Released"
				entry.SaveState = "Released"
				entry.ReleaseInProgress = false
				entry.LastReleaseSuccess = true
				entry.LastReleaseCode = "RELEASED"
				self:PublishSnapshot(userId)
				self:_reschedule()
				return true, "RELEASED"
			end
			if storeResult.Code == "Conflict" or storeResult.Code == "Locked" then
				entry.ReleaseInProgress = false
				entry.LastReleaseSuccess = false
				entry.LastReleaseCode = "CONFLICT"
				self:_handleStoreConflict(entry)
				return false, "CONFLICT"
			end
		else
			finalCode = "BudgetDelayed"
		end
		if attempt < ProfileConfig.MAXIMUM_SAVE_ATTEMPTS then
			if not waitForRetry(self, backoffSeconds(attempt)) then
				break
			end
		end
	end
	entry.Profile = nil
	entry.Dirty = false
	entry.State = "Released"
	entry.SaveState = "Released"
	entry.ReleaseInProgress = false
	entry.LastReleaseSuccess = false
	entry.LastReleaseCode = string.upper(finalCode)
	self:PublishSnapshot(userId)
	self:_reschedule()
	return false, string.upper(finalCode)
end

function ProfileService.BeginShutdown(self: ProfileServiceImpl)
	if self._shuttingDown then
		return
	end
	self._shuttingDown = true
	self:_cancelScheduled()
	for _, userId in ipairs(sortedUserIds(self._entries)) do
		local entry = self._entries[userId]
		if entry ~= nil and entry.State ~= "Released" then
			entry.State = "Releasing"
			entry.SaveState = "Releasing"
			self:PublishSnapshot(userId)
		end
	end
end

function ProfileService.Shutdown(
	self: ProfileServiceImpl,
	deadlineSeconds: number?
): { Successes: number, Failures: number, Skipped: number }
	local deadline = self._clock() + (deadlineSeconds or ProfileConfig.SHUTDOWN_DEADLINE_SECONDS)
	self._shutdownDeadlineAt = deadline
	self:BeginShutdown()
	local successes = 0
	local failures = 0
	local active = 0
	local nextIndex = 1
	local pending: { number } = {}
	for _, userId in ipairs(sortedUserIds(self._entries)) do
		local entry = self._entries[userId]
		if entry ~= nil and entry.State ~= "Released" then
			table.insert(pending, userId)
		end
	end
	while self._clock() < deadline and (nextIndex <= #pending or active > 0) do
		while active < ProfileConfig.MAXIMUM_SIMULTANEOUS_SAVES
			and nextIndex <= #pending
			and self._clock() < deadline
		do
			local userId = pending[nextIndex]
			nextIndex += 1
			active += 1
			self._spawn(function()
				local success = self:Release(userId)
				if success then
					successes += 1
				else
					failures += 1
				end
				active -= 1
			end)
		end
		if active > 0 then
			self._wait(0.05)
		end
	end
	local skipped = (#pending - nextIndex + 1) + active
	return table.freeze({
		Successes = successes,
		Failures = failures,
		Skipped = skipped,
	})
end

return table.freeze(ProfileService)
