--!strict

export type Cell = {
	X: number,
	Y: number,
	Z: number,
}

export type ShapeDefinition = {
	Id: string,
	Cells: { Cell },
}

export type ShapeRotation = {
	QuarterTurns: number,
	Cells: { Cell },
	Key: string,
	SizeX: number,
	SizeY: number,
	SizeZ: number,
}

export type Placement = {
	ShapeId: string,
	RotationIndex: number,
	QuarterTurns: number,
	Origin: Cell,
	Cells: { Cell },
	Key: string,
}

export type Grid = {
	Width: number,
	Height: number,
	Depth: number,
	IsInsideBounds: (self: Grid, cell: Cell) -> boolean,
	IsCellOccupied: (self: Grid, cell: Cell) -> boolean,
	CanOccupyCells: (self: Grid, cells: { Cell }) -> boolean,
	ApplyPlacement: (self: Grid, placement: Placement) -> boolean,
	Clone: (self: Grid) -> Grid,
	GetOccupiedCells: (self: Grid) -> { Cell },
	GetOccupiedCellCount: (self: Grid) -> number,
	GetFillRatio: (self: Grid) -> number,
}

export type Difficulty = "Easy" | "Tight" | "Brutal" | "Impossible"

return table.freeze({})
