--!strict

local ProgressionTypes = require(script.Parent.ProgressionTypes)

export type Statistics = ProgressionTypes.Statistics
export type ProgressionReward = ProgressionTypes.ProgressionReward

export type OnboardingPresentation = {
	Status: "NotStarted" | "InProgress" | "Completed" | "Skipped",
	HighestStep: number,
	Completed: boolean,
}

export type StarterMissionsPresentation = {
	Progress: { [string]: number },
	CompletedMissionIds: { string },
	RewardedMissionIds: { string },
	CurrentMissionId: string?,
	CompletedCount: number,
	TotalCount: number,
	PathCompleted: boolean,
}

export type MissionRewardPresentation = {
	RewardId: string,
	MissionId: string,
	MissionIndex: number,
	TapeDelta: number,
	XPDelta: number,
	PreviousTape: number,
	NewTape: number,
	PreviousXP: number,
	NewXP: number,
	PreviousRank: ProgressionTypes.RankPresentation,
	NewRank: ProgressionTypes.RankPresentation,
	PathCompleted: boolean,
}

export type ProfileLifecycleState =
	"Loading"
	| "Ready"
	| "Saving"
	| "SaveDelayed"
	| "Unavailable"
	| "Conflict"
	| "Releasing"
	| "Released"

export type ProfileSaveState =
	"Loading"
	| "Saved"
	| "Saving"
	| "SaveDelayed"
	| "Unavailable"
	| "Conflict"
	| "Releasing"
	| "Released"

export type ProfileSnapshot = {
	SchemaVersion: number,
	ProfileSessionId: string,
	Revision: number,
	State: ProfileLifecycleState,
	SaveState: ProfileSaveState,
	Tape: number,
	PackingXP: number,
	RankIndex: number,
	RankName: string,
	RankStartXP: number,
	NextRankXP: number?,
	XPIntoRank: number,
	XPRequiredForNextRank: number,
	DiscoveredItemIds: { string },
	MasteryCounts: { [string]: number },
	CollectionDiscoveredCount: number,
	CollectionTotalCount: number,
	Stats: Statistics,
	LastReward: ProgressionReward?,
	Onboarding: OnboardingPresentation,
	StarterMissions: StarterMissionsPresentation,
	LastMissionRewards: { MissionRewardPresentation },
}

return table.freeze({})
