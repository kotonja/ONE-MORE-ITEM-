--!strict

local GridTypes = require(script.Parent.Parent.Grid.GridTypes)

export type Cell = GridTypes.Cell

export type PlaceItemRequest = {
	RoundId: number,
	StateVersion: number,
	ItemId: string,
	QuarterTurns: number,
	OriginX: number,
	OriginZ: number,
	ClientSequence: number,
}

export type DecisionChoice = "SHIP" | "ONE_MORE"

export type DecisionRequest = {
	RoundId: number,
	StateVersion: number,
	Choice: DecisionChoice,
	ClientSequence: number,
}

export type RestartRequest = {
	RoundId: number,
	StateVersion: number,
	ClientSequence: number,
}

export type PlacementResponse = {
	Accepted: boolean,
	Reason: string,
	ClientSequence: number,
	RoundId: number,
	StateVersion: number,
}

export type RoundSnapshot = {
	RoundId: number,
	OutcomeId: string?,
	StateVersion: number,
	State: string,
	StationId: string,
	CurrentItemId: string?,
	CurrentShapeId: string?,
	NextItemId: string?,
	NextShapeId: string?,
	NextDifficulty: string?,
	OccupiedCells: { Cell },
	ItemCount: number,
	BaseValueSum: number,
	ShipmentValue: number,
	PossibleNextShipmentValue: number,
	CurrentMultiplier: number,
	SessionBank: number,
	PlacementDeadline: number?,
	DecisionDeadline: number?,
	ResultReason: string?,
	ResultValue: number,
	ResultLostValue: number,
	GuidedOnboarding: boolean,
}

return table.freeze({})
