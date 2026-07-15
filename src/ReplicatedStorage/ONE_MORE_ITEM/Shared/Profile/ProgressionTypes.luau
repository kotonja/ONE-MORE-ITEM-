--!strict

export type Statistics = {
	TotalSuccessfulShipments: number,
	TotalItemsShipped: number,
	HighestItemsInShipment: number,
	BestShipmentValue: number,
	PerfectShipments: number,
	TotalFailedRounds: number,
	TotalTapeEarned: number,
}

export type CollectionState = {
	Discovered: { [string]: boolean },
	MasteryCounts: { [string]: number },
	RecentDiscoveries: { string },
}

export type RankPresentation = {
	Index: number,
	Name: string,
	Threshold: number,
}

export type MasteryChange = {
	ItemId: string,
	PreviousCount: number,
	NewCount: number,
	PreviousTier: string,
	NewTier: string,
}

export type OutcomeType = "Shipment" | "Failure"

export type ProgressionReward = {
	OutcomeId: string,
	RoundId: number,
	OutcomeType: OutcomeType,
	TapeDelta: number,
	NewTape: number,
	XPDelta: number,
	PreviousXP: number,
	NewXP: number,
	PreviousRank: RankPresentation,
	NewRank: RankPresentation,
	NewDiscoveries: { string },
	MasteryChanges: { MasteryChange },
	UpdatedStats: Statistics,
	Duplicate: boolean,
}

return table.freeze({})
