--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local ProfileNetworkTypes = require(Root.Shared.Profile.ProfileNetworkTypes)
local ProgressionTypes = require(Root.Shared.Profile.ProgressionTypes)

export type Statistics = ProgressionTypes.Statistics
export type CollectionState = ProgressionTypes.CollectionState
export type ProgressionReward = ProgressionTypes.ProgressionReward
export type ProfileLifecycleState = ProfileNetworkTypes.ProfileLifecycleState
export type ProfileSaveState = ProfileNetworkTypes.ProfileSaveState
export type ProfileSnapshot = ProfileNetworkTypes.ProfileSnapshot

export type ProfileSession = {
	Token: string,
	JobId: string,
	PlaceId: number,
	AcquiredAt: number,
	HeartbeatAt: number,
}

export type ReceiptState = {
	ProcessedOutcomeIds: { string },
}

export type PersistedProfile = {
	SchemaVersion: number,
	Tape: number,
	PackingXP: number,
	Stats: Statistics,
	Collection: CollectionState,
	Receipts: ReceiptState,
	CreatedAt: number,
	UpdatedAt: number,
	Session: ProfileSession?,
}

export type SessionClaim = {
	Token: string,
	JobId: string,
	PlaceId: number,
	Now: number,
}

export type StoreEnvironment = "StudioTest" | "Production" | "Memory"

export type StoreResultCode =
	"Loaded"
	| "Saved"
	| "Heartbeated"
	| "Released"
	| "Locked"
	| "Conflict"
	| "Unavailable"
	| "BudgetDelayed"
	| "UnsupportedSchema"
	| "InvalidProfile"

export type StoreResult = {
	Success: boolean,
	Code: StoreResultCode,
	Profile: PersistedProfile?,
	Message: string?,
}

return table.freeze({})
