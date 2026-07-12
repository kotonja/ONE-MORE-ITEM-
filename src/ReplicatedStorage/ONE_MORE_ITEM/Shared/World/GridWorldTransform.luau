--!strict

local GridTypes = require(script.Parent.Parent.Grid.GridTypes)
local IntegerValidation = require(script.Parent.Parent.Grid.IntegerValidation)

type Cell = GridTypes.Cell

local GridWorldTransform = {}

local function validateCell(cell: Cell)
	if not IntegerValidation.IsFiniteInteger(cell.X)
		or not IntegerValidation.IsFiniteInteger(cell.Y)
		or not IntegerValidation.IsFiniteInteger(cell.Z)
	then
		error("Grid cell coordinates must be finite integers", 3)
	end
end

local function validateCellSize(cellSize: number)
	if type(cellSize) ~= "number" or cellSize ~= cellSize or cellSize <= 0 or cellSize >= math.huge then
		error("cellSize must be a positive finite number", 3)
	end
end

function GridWorldTransform.CellToCFrame(gridOrigin: CFrame, cell: Cell, cellSize: number): CFrame
	validateCell(cell)
	validateCellSize(cellSize)
	return gridOrigin * CFrame.new(cell.X * cellSize, cell.Y * cellSize, cell.Z * cellSize)
end

function GridWorldTransform.CellToWorldPosition(gridOrigin: CFrame, cell: Cell, cellSize: number): Vector3
	return GridWorldTransform.CellToCFrame(gridOrigin, cell, cellSize).Position
end

function GridWorldTransform.WorldPositionToGridXZ(
	gridOrigin: CFrame,
	worldPosition: Vector3,
	cellSize: number
): (number, number)
	validateCellSize(cellSize)
	local localPosition = gridOrigin:PointToObjectSpace(worldPosition)
	return math.floor((localPosition.X / cellSize) + 0.5), math.floor((localPosition.Z / cellSize) + 0.5)
end

return table.freeze(GridWorldTransform)
