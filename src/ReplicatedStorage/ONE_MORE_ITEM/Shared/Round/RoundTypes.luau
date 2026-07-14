--!strict

local GridTypes = require(script.Parent.Parent.Grid.GridTypes)

export type Grid = GridTypes.Grid
export type Placement = GridTypes.Placement

export type RoundState =
	"Preparing"
	| "PresentingItem"
	| "AwaitingPlacement"
	| "Decision"
	| "Shipping"
	| "Failing"
	| "Results"

export type LastClientSequences = {
	Place: number,
	Decision: number,
	Restart: number,
}

export type PlacedItemPresentation = {
	ItemId: string,
	ShapeId: string,
	QuarterTurns: number,
	OriginX: number,
	OriginY: number,
	OriginZ: number,
	ColorR: number,
	ColorG: number,
	ColorB: number,
}

export type RoundRecord = {
	PlayerUserId: number,
	RoundId: number,
	StateVersion: number,
	State: RoundState,
	StationId: string,
	CurrentItemId: string?,
	PreviewedNextItemId: string?,
	PreviewDifficulty: string?,
	Grid: Grid,
	PlacedItems: { PlacedItemPresentation },
	ItemCount: number,
	BaseValueSum: number,
	ShipmentValue: number,
	SessionBank: number,
	PlacementDeadline: number?,
	DecisionDeadline: number?,
	LastClientSequences: LastClientSequences,
	ResultReason: string?,
	ResultValue: number,
	ResultLostValue: number,
	ShipmentBanked: boolean,
}

return table.freeze({})
