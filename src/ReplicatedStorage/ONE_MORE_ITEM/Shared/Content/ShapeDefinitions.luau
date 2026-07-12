--!strict

local GridTypes = require(script.Parent.Parent.Grid.GridTypes)

type Cell = GridTypes.Cell
type ShapeDefinition = GridTypes.ShapeDefinition

local function cell(x: number, y: number, z: number): Cell
	return table.freeze({ X = x, Y = y, Z = z }) :: Cell
end

local function shape(id: string, cells: { Cell }): ShapeDefinition
	table.freeze(cells)
	return table.freeze({ Id = id, Cells = cells }) :: ShapeDefinition
end

local Shapes = {
	SingleCube = shape("single_cube", { cell(0, 0, 0) }),
	HorizontalBar2 = shape("horizontal_bar_2", { cell(0, 0, 0), cell(1, 0, 0) }),
	HorizontalBar3 = shape("horizontal_bar_3", { cell(0, 0, 0), cell(1, 0, 0), cell(2, 0, 0) }),
	VerticalColumn3 = shape("vertical_column_3", { cell(0, 0, 0), cell(0, 1, 0), cell(0, 2, 0) }),
	FlatSquare2x2 = shape("flat_square_2x2", {
		cell(0, 0, 0), cell(1, 0, 0), cell(0, 0, 1), cell(1, 0, 1),
	}),
	FlatL = shape("flat_l", { cell(0, 0, 0), cell(0, 0, 1), cell(0, 0, 2), cell(1, 0, 2) }),
	FlatT = shape("flat_t", { cell(0, 0, 0), cell(1, 0, 0), cell(2, 0, 0), cell(1, 0, 1) }),
	FlatZ = shape("flat_z", { cell(0, 0, 0), cell(1, 0, 0), cell(1, 0, 1), cell(2, 0, 1) }),
	Chair = shape("chair", { cell(0, 0, 0), cell(1, 0, 0), cell(0, 0, 1), cell(0, 1, 1) }),
	MediumBlock = shape("medium_block", {
		cell(0, 0, 0), cell(1, 0, 0), cell(0, 0, 1), cell(1, 0, 1),
		cell(0, 1, 0), cell(1, 1, 0), cell(0, 1, 1), cell(1, 1, 1),
	}),
	LargeIrregular = shape("large_irregular", {
		cell(0, 0, 0), cell(1, 0, 0), cell(2, 0, 0),
		cell(0, 0, 1), cell(1, 0, 1),
		cell(0, 1, 0), cell(1, 1, 0),
		cell(0, 1, 1), cell(0, 2, 0),
	}),
}

return table.freeze(Shapes)
