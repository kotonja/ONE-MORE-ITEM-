--!strict

local GridTypes = require(script.Parent.GridTypes)
local ShapeRotation = require(script.Parent.ShapeRotation)

type Cell = GridTypes.Cell
type Grid = GridTypes.Grid
type Placement = GridTypes.Placement
type ShapeDefinition = GridTypes.ShapeDefinition
type Rotation = GridTypes.ShapeRotation

local PlacementSolver = {}

local function isInteger(value: number): boolean
	return value == math.floor(value)
end

local function translatedCells(rotation: Rotation, x: number, y: number, z: number): { Cell }
	local cells: { Cell } = {}
	for _, cell in ipairs(rotation.Cells) do
		table.insert(cells, {
			X = cell.X + x,
			Y = cell.Y + y,
			Z = cell.Z + z,
		})
	end
	return cells
end

local function placementKey(shapeId: string, rotation: Rotation, x: number, y: number, z: number): string
	return string.format("%s|%s|%d,%d,%d", shapeId, rotation.Key, x, y, z)
end

function PlacementSolver.ValidatePlacement(grid: Grid, placement: Placement): boolean
	return grid:CanOccupyCells(placement.Cells)
end

function PlacementSolver.GetAutoDropPlacement(
	grid: Grid,
	rotation: Rotation,
	x: number,
	z: number,
	shapeId: string?,
	rotationIndex: number?
): Placement?
	if not isInteger(x) or not isInteger(z) then
		return nil
	end
	if x < 0 or z < 0 or x + rotation.SizeX > grid.Width or z + rotation.SizeZ > grid.Depth then
		return nil
	end

	local highestY = grid.Height - rotation.SizeY
	if highestY < 0 then
		return nil
	end

	local currentY = highestY
	local currentCells = translatedCells(rotation, x, currentY, z)
	-- Entry must be clear. This prevents teleporting through an upper obstruction.
	if not grid:CanOccupyCells(currentCells) then
		return nil
	end

	while currentY > 0 do
		local nextCells = translatedCells(rotation, x, currentY - 1, z)
		if not grid:CanOccupyCells(nextCells) then
			break
		end
		currentY -= 1
		currentCells = nextCells
	end

	local resolvedShapeId = shapeId or "UNSPECIFIED"
	return {
		ShapeId = resolvedShapeId,
		RotationIndex = rotationIndex or 1,
		QuarterTurns = rotation.QuarterTurns,
		Origin = { X = x, Y = currentY, Z = z },
		Cells = currentCells,
		Key = placementKey(resolvedShapeId, rotation, x, currentY, z),
	}
end

function PlacementSolver.EnumerateLegalPlacements(grid: Grid, shape: ShapeDefinition): { Placement }
	local placements: { Placement } = {}
	local seen: { [string]: boolean } = {}
	local rotations = ShapeRotation.GetUniqueRotations(shape)

	for rotationIndex, rotation in ipairs(rotations) do
		for x = 0, grid.Width - rotation.SizeX do
			for z = 0, grid.Depth - rotation.SizeZ do
				local placement = PlacementSolver.GetAutoDropPlacement(
					grid,
					rotation,
					x,
					z,
					shape.Id,
					rotationIndex
				)
				if placement and not seen[placement.Key] then
					seen[placement.Key] = true
					table.insert(placements, placement)
				end
			end
		end
	end

	return placements
end

function PlacementSolver.HasLegalPlacement(grid: Grid, shape: ShapeDefinition): boolean
	return #PlacementSolver.EnumerateLegalPlacements(grid, shape) > 0
end

return table.freeze(PlacementSolver)
