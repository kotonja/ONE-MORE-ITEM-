--!strict

local GridTypes = require(script.Parent.GridTypes)
local IntegerValidation = require(script.Parent.IntegerValidation)

type Cell = GridTypes.Cell
type Placement = GridTypes.Placement
type Grid = GridTypes.Grid

type InternalGrid = Grid & {
	_occupied: { [string]: boolean },
	_occupiedCount: number,
}

local OccupancyGrid = {}
local GridMethods = {}
GridMethods.__index = GridMethods

local function isPositiveInteger(value: unknown): boolean
	return IntegerValidation.IsFiniteInteger(value) and (value :: number) > 0
end

local function cellKey(cell: Cell): string
	return string.format("%d:%d:%d", cell.X, cell.Y, cell.Z)
end

function OccupancyGrid.CreateGrid(width: number, height: number, depth: number): Grid
	if not isPositiveInteger(width) or not isPositiveInteger(height) or not isPositiveInteger(depth) then
		error("Grid dimensions must be positive finite integers", 2)
	end

	local grid: InternalGrid = setmetatable({
		Width = width,
		Height = height,
		Depth = depth,
		_occupied = {},
		_occupiedCount = 0,
	}, GridMethods) :: any
	return grid
end

function GridMethods.IsInsideBounds(self: InternalGrid, cell: Cell): boolean
	if type(cell) ~= "table" then
		return false
	end

	return IntegerValidation.IsFiniteInteger(cell.X)
		and IntegerValidation.IsFiniteInteger(cell.Y)
		and IntegerValidation.IsFiniteInteger(cell.Z)
		and cell.X >= 0
		and cell.X < self.Width
		and cell.Y >= 0
		and cell.Y < self.Height
		and cell.Z >= 0
		and cell.Z < self.Depth
end

function GridMethods.IsCellOccupied(self: InternalGrid, cell: Cell): boolean
	if not self:IsInsideBounds(cell) then
		return false
	end
	return self._occupied[cellKey(cell)] == true
end

function GridMethods.CanOccupyCells(self: InternalGrid, cells: { Cell }): boolean
	if type(cells) ~= "table" or #cells == 0 then
		return false
	end
	local seen: { [string]: boolean } = {}
	for _, cell in ipairs(cells) do
		if not self:IsInsideBounds(cell) then
			return false
		end
		local key = cellKey(cell)
		if seen[key] or self._occupied[key] then
			return false
		end
		seen[key] = true
	end
	return true
end

function GridMethods.ApplyPlacement(self: InternalGrid, placement: Placement): boolean
	if not self:CanOccupyCells(placement.Cells) then
		return false
	end
	for _, cell in ipairs(placement.Cells) do
		self._occupied[cellKey(cell)] = true
	end
	self._occupiedCount += #placement.Cells
	return true
end

function GridMethods.Clone(self: InternalGrid): Grid
	local clone = OccupancyGrid.CreateGrid(self.Width, self.Height, self.Depth) :: InternalGrid
	for key in pairs(self._occupied) do
		clone._occupied[key] = true
	end
	clone._occupiedCount = self._occupiedCount
	return clone
end

function GridMethods.GetOccupiedCells(self: InternalGrid): { Cell }
	local cells: { Cell } = {}
	for key in pairs(self._occupied) do
		local x, y, z = string.match(key, "^(-?%d+):(-?%d+):(-?%d+)$")
		table.insert(cells, {
			X = tonumber(x) :: number,
			Y = tonumber(y) :: number,
			Z = tonumber(z) :: number,
		})
	end
	table.sort(cells, function(a: Cell, b: Cell): boolean
		if a.X ~= b.X then
			return a.X < b.X
		end
		if a.Y ~= b.Y then
			return a.Y < b.Y
		end
		return a.Z < b.Z
	end)
	return cells
end

function GridMethods.GetOccupiedCellCount(self: InternalGrid): number
	return self._occupiedCount
end

function GridMethods.GetFillRatio(self: InternalGrid): number
	local capacity = self.Width * self.Height * self.Depth
	return self._occupiedCount / capacity
end

return table.freeze(OccupancyGrid)
