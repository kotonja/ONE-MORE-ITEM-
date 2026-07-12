--!strict

local GridTypes = require(script.Parent.GridTypes)

type Cell = GridTypes.Cell
type ShapeDefinition = GridTypes.ShapeDefinition
type ShapeRotation = GridTypes.ShapeRotation

local ShapeRotationModule = {}

local function isInteger(value: unknown): boolean
	return type(value) == "number" and value == math.floor(value :: number)
end

local function cellKey(cell: Cell): string
	return string.format("%d,%d,%d", cell.X, cell.Y, cell.Z)
end

local function copyCell(cell: Cell): Cell
	return { X = cell.X, Y = cell.Y, Z = cell.Z }
end

local function sortCells(cells: { Cell })
	table.sort(cells, function(a: Cell, b: Cell): boolean
		if a.X ~= b.X then
			return a.X < b.X
		end
		if a.Y ~= b.Y then
			return a.Y < b.Y
		end
		return a.Z < b.Z
	end)
end

function ShapeRotationModule.ValidateShapeCells(cells: { Cell }): ()
	if type(cells) ~= "table" or #cells == 0 then
		error("Shape must contain at least one cell", 2)
	end

	local seen: { [string]: boolean } = {}
	for index, cell in ipairs(cells) do
		if type(cell) ~= "table" then
			error(string.format("Shape cell %d must be a table", index), 2)
		end
		if not isInteger(cell.X) or not isInteger(cell.Y) or not isInteger(cell.Z) then
			error(string.format("Shape cell %d must use integer X, Y, and Z coordinates", index), 2)
		end
		local key = cellKey(cell)
		if seen[key] then
			error(string.format("Shape contains duplicate cell %s", key), 2)
		end
		seen[key] = true
	end
end

function ShapeRotationModule.NormalizeShape(cells: { Cell }): { Cell }
	ShapeRotationModule.ValidateShapeCells(cells)

	local minimumX = math.huge
	local minimumY = math.huge
	local minimumZ = math.huge
	for _, cell in ipairs(cells) do
		minimumX = math.min(minimumX, cell.X)
		minimumY = math.min(minimumY, cell.Y)
		minimumZ = math.min(minimumZ, cell.Z)
	end

	local normalized: { Cell } = {}
	for _, cell in ipairs(cells) do
		table.insert(normalized, {
			X = cell.X - minimumX,
			Y = cell.Y - minimumY,
			Z = cell.Z - minimumZ,
		})
	end
	sortCells(normalized)
	return normalized
end

function ShapeRotationModule.GetCanonicalKey(cells: { Cell }): string
	local normalized = ShapeRotationModule.NormalizeShape(cells)
	local parts: { string } = {}
	for _, cell in ipairs(normalized) do
		table.insert(parts, cellKey(cell))
	end
	return table.concat(parts, ";")
end

function ShapeRotationModule.RotateShapeY(cells: { Cell }, quarterTurns: number): { Cell }
	if not isInteger(quarterTurns) then
		error("quarterTurns must be an integer", 2)
	end
	ShapeRotationModule.ValidateShapeCells(cells)

	local turns = ((quarterTurns % 4) + 4) % 4
	local rotated: { Cell } = {}
	for _, cell in ipairs(cells) do
		local x = cell.X
		local z = cell.Z
		for _ = 1, turns do
			x, z = -z, x
		end
		table.insert(rotated, { X = x, Y = cell.Y, Z = z })
	end
	return ShapeRotationModule.NormalizeShape(rotated)
end

local function buildRotation(cells: { Cell }, quarterTurns: number): ShapeRotation
	local normalized = ShapeRotationModule.NormalizeShape(cells)
	local maximumX = 0
	local maximumY = 0
	local maximumZ = 0
	for _, cell in ipairs(normalized) do
		maximumX = math.max(maximumX, cell.X)
		maximumY = math.max(maximumY, cell.Y)
		maximumZ = math.max(maximumZ, cell.Z)
	end

	return {
		QuarterTurns = quarterTurns,
		Cells = normalized,
		Key = ShapeRotationModule.GetCanonicalKey(normalized),
		SizeX = maximumX + 1,
		SizeY = maximumY + 1,
		SizeZ = maximumZ + 1,
	}
end

function ShapeRotationModule.GetUniqueRotations(shape: ShapeDefinition): { ShapeRotation }
	if type(shape) ~= "table" or type(shape.Id) ~= "string" or shape.Id == "" then
		error("Shape must have a non-empty string Id", 2)
	end
	ShapeRotationModule.ValidateShapeCells(shape.Cells)

	local unique: { ShapeRotation } = {}
	local seen: { [string]: boolean } = {}
	for quarterTurns = 0, 3 do
		local cells = ShapeRotationModule.RotateShapeY(shape.Cells, quarterTurns)
		local rotation = buildRotation(cells, quarterTurns)
		if not seen[rotation.Key] then
			seen[rotation.Key] = true
			table.insert(unique, rotation)
		end
	end
	return unique
end

function ShapeRotationModule.CopyCells(cells: { Cell }): { Cell }
	local copied: { Cell } = {}
	for _, cell in ipairs(cells) do
		table.insert(copied, copyCell(cell))
	end
	return copied
end

return table.freeze(ShapeRotationModule)
