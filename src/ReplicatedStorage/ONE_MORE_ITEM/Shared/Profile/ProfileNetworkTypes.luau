--!strict

local ProgressionTypes = require(script.Parent.ProgressionTypes)

export type Statistics = ProgressionTypes.Statistics
export type ProgressionReward = ProgressionTypes.ProgressionReward

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
}

return table.freeze({})
