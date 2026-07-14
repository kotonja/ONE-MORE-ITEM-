--!strict

local RoundTypes = require(script.Parent.Parent.Round.RoundTypes)

export type PlacedItemPresentation = RoundTypes.PlacedItemPresentation

export type ShipmentRecord = {
	ShipmentId: string,
	PlayerUserId: number,
	PlayerDisplayName: string,
	StationId: string,
	RoundId: number,
	ItemCount: number,
	BaseValueSum: number,
	ShipmentValue: number,
	Multiplier: number,
	PlacedItems: { PlacedItemPresentation },
	CreatedAt: number,
	PerfectShipment: boolean,
}

return table.freeze({})
