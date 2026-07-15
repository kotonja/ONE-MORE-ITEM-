--!strict

local ProfileTypes = require(script.Parent.ProfileTypes)

export type PersistedProfile = ProfileTypes.PersistedProfile
export type SessionClaim = ProfileTypes.SessionClaim
export type StoreResult = ProfileTypes.StoreResult
export type StoreEnvironment = ProfileTypes.StoreEnvironment

export type Adapter = {
	LoadAndLock: (self: any, userId: number, claim: SessionClaim) -> StoreResult,
	Save: (self: any, userId: number, profile: PersistedProfile, token: string, now: number) -> StoreResult,
	Heartbeat: (self: any, userId: number, token: string, now: number) -> StoreResult,
	Release: (self: any, userId: number, profile: PersistedProfile, token: string, now: number) -> StoreResult,
	CanRequest: (self: any, requestKind: string) -> boolean,
	GetEnvironment: (self: any) -> StoreEnvironment,
}

local retryableCodes: { [string]: boolean } = table.freeze({
	Unavailable = true,
	BudgetDelayed = true,
})

local ProfileStoreAdapter = {}

function ProfileStoreAdapter.IsRetryable(code: string): boolean
	return retryableCodes[code] == true
end

return table.freeze(ProfileStoreAdapter)
