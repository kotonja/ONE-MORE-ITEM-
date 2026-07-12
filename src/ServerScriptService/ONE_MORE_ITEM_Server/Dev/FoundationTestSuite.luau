--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local Shared = Root:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ShapeDefinitions = require(Shared.Content.ShapeDefinitions)
local GridTypes = require(Shared.Grid.GridTypes)
local ShapeRotation = require(Shared.Grid.ShapeRotation)
local OccupancyGrid = require(Shared.Grid.OccupancyGrid)
local PlacementSolver = require(Shared.Grid.PlacementSolver)
local DifficultyClassifier = require(Shared.Grid.DifficultyClassifier)

type Cell = GridTypes.Cell
type Grid = GridTypes.Grid
type Placement = GridTypes.Placement
type ShapeDefinition = GridTypes.ShapeDefinition

type TestCase = {
	Name: string,
	Run: () -> (),
}

type TestSuite = {
	Name: string,
	Tests: { TestCase },
}

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	FuzzCases: number,
	FuzzSeed: number,
	BenchmarkIterations: number,
	BenchmarkSeconds: number,
}

local FoundationTestSuite = {}
local suites: { TestSuite } = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual: unknown, expected: unknown, message: string?)
	if actual ~= expected then
		error(message or string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local function expectNear(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(message or string.format("Expected %.8f, got %.8f", expected, actual), 2)
	end
end

local function expectError(callback: () -> (), expectedText: string)
	local ok, failure = pcall(callback)
	expect(not ok, "Expected callback to fail")
	expect(string.find(tostring(failure), expectedText, 1, true) ~= nil, string.format(
		"Expected error containing %q, got %q",
		expectedText,
		tostring(failure)
	))
end

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, { Name = name, Tests = tests })
end

local function newGrid(): Grid
	return OccupancyGrid.CreateGrid(GameConfig.BOX_WIDTH, GameConfig.BOX_HEIGHT, GameConfig.BOX_DEPTH)
end

local function makePlacement(cells: { Cell }, key: string?): Placement
	return {
		ShapeId = "test_fixture",
		RotationIndex = 1,
		QuarterTurns = 0,
		Origin = { X = 0, Y = 0, Z = 0 },
		Cells = cells,
		Key = key or "test_fixture",
	}
end

local function applyCells(grid: Grid, cells: { Cell })
	expect(grid:ApplyPlacement(makePlacement(cells)), "Test fixture placement should apply")
end

local function cellListKey(cells: { Cell }): string
	local parts: { string } = {}
	for _, cell in ipairs(cells) do
		table.insert(parts, string.format("%d:%d:%d", cell.X, cell.Y, cell.Z))
	end
	return table.concat(parts, "|")
end

local function fullGrid(): Grid
	local grid = newGrid()
	local cells: { Cell } = {}
	for x = 0, grid.Width - 1 do
		for y = 0, grid.Height - 1 do
			for z = 0, grid.Depth - 1 do
				table.insert(cells, { X = x, Y = y, Z = z })
			end
		end
	end
	applyCells(grid, cells)
	return grid
end

addSuite("Shape validation", {
	{
		Name = "duplicate input cells are rejected",
		Run = function()
			expectError(function()
				ShapeRotation.NormalizeShape({ { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 } })
			end, "duplicate cell")
		end,
	},
	{
		Name = "non-integer coordinates are rejected",
		Run = function()
			expectError(function()
				ShapeRotation.NormalizeShape({ { X = 0.5, Y = 0, Z = 0 } })
			end, "integer")
		end,
	},
	{
		Name = "empty shapes are rejected",
		Run = function()
			expectError(function()
				ShapeRotation.NormalizeShape({})
			end, "at least one cell")
		end,
	},
	{
		Name = "normalization moves all minima to zero",
		Run = function()
			local cells = ShapeRotation.NormalizeShape({ { X = 4, Y = 2, Z = 9 }, { X = 6, Y = 3, Z = 10 } })
			expectEqual(cells[1].X, 0)
			expectEqual(cells[1].Y, 0)
			expectEqual(cells[1].Z, 0)
			expectEqual(cells[2].X, 2)
			expectEqual(cells[2].Y, 1)
			expectEqual(cells[2].Z, 1)
		end,
	},
	{
		Name = "cell input order does not change canonical shape",
		Run = function()
			local a = { { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 } }
			local b = { a[3], a[1], a[2] }
			expectEqual(ShapeRotation.GetCanonicalKey(a), ShapeRotation.GetCanonicalKey(b))
		end,
	},
})

addSuite("Rotation", {
	{
		Name = "four quarter-turns return to original normalized shape",
		Run = function()
			local original = ShapeRotation.GetCanonicalKey(ShapeDefinitions.FlatL.Cells)
			local rotated = ShapeRotation.RotateShapeY(ShapeDefinitions.FlatL.Cells, 4)
			expectEqual(ShapeRotation.GetCanonicalKey(rotated), original)
		end,
	},
	{
		Name = "symmetrical shapes remove duplicate rotations",
		Run = function()
			expectEqual(#ShapeRotation.GetUniqueRotations(ShapeDefinitions.FlatSquare2x2), 1)
			expect(#ShapeRotation.GetUniqueRotations(ShapeDefinitions.FlatSquare2x2) < 4, "Square must have fewer than four rotations")
		end,
	},
	{
		Name = "asymmetrical shape has four rotations",
		Run = function()
			expectEqual(#ShapeRotation.GetUniqueRotations(ShapeDefinitions.FlatL), 4)
		end,
	},
	{
		Name = "rotated shapes remain integer-based",
		Run = function()
			for _, rotation in ipairs(ShapeRotation.GetUniqueRotations(ShapeDefinitions.Chair)) do
				for _, cell in ipairs(rotation.Cells) do
					expect(cell.X == math.floor(cell.X), "Rotated X must be integer")
					expect(cell.Y == math.floor(cell.Y), "Rotated Y must be integer")
					expect(cell.Z == math.floor(cell.Z), "Rotated Z must be integer")
				end
			end
		end,
	},
	{
		Name = "rotations preserve cell count",
		Run = function()
			for _, rotation in ipairs(ShapeRotation.GetUniqueRotations(ShapeDefinitions.LargeIrregular)) do
				expectEqual(#rotation.Cells, #ShapeDefinitions.LargeIrregular.Cells)
			end
		end,
	},
})

addSuite("Bounds", {
	{
		Name = "shape entirely inside passes",
		Run = function()
			expect(newGrid():CanOccupyCells({ { X = 0, Y = 0, Z = 0 }, { X = 4, Y = 3, Z = 4 } }), "Valid cells should pass")
		end,
	},
	{
		Name = "negative coordinates fail",
		Run = function()
			expect(not newGrid():CanOccupyCells({ { X = -1, Y = 0, Z = 0 } }), "Negative X must fail")
		end,
	},
	{
		Name = "X overflow fails",
		Run = function()
			expect(not newGrid():CanOccupyCells({ { X = 5, Y = 0, Z = 0 } }), "X overflow must fail")
		end,
	},
	{
		Name = "Y overflow fails",
		Run = function()
			expect(not newGrid():CanOccupyCells({ { X = 0, Y = 4, Z = 0 } }), "Y overflow must fail")
		end,
	},
	{
		Name = "Z overflow fails",
		Run = function()
			expect(not newGrid():CanOccupyCells({ { X = 0, Y = 0, Z = 5 } }), "Z overflow must fail")
		end,
	},
})

addSuite("Finite integer boundaries", {
	{
		Name = "NaN coordinates are rejected without crashing grid queries",
		Run = function()
			local nan = 0 / 0
			local cell = ({ X = nan, Y = 0, Z = 0 } :: any)
			expect(not newGrid():IsInsideBounds(cell), "NaN coordinate must be outside bounds")
			expect(not newGrid():CanOccupyCells({ cell }), "NaN coordinate must not be occupiable")
			expectError(function()
				ShapeRotation.NormalizeShape({ cell })
			end, "finite integer")
		end,
	},
	{
		Name = "positive infinity coordinates are rejected without crashing grid queries",
		Run = function()
			local cell = ({ X = math.huge, Y = 0, Z = 0 } :: any)
			expect(not newGrid():IsInsideBounds(cell), "Positive infinity must be outside bounds")
			expect(not newGrid():CanOccupyCells({ cell }), "Positive infinity must not be occupiable")
			expectError(function()
				ShapeRotation.NormalizeShape({ cell })
			end, "finite integer")
		end,
	},
	{
		Name = "negative infinity coordinates are rejected without crashing grid queries",
		Run = function()
			local cell = ({ X = -math.huge, Y = 0, Z = 0 } :: any)
			expect(not newGrid():IsInsideBounds(cell), "Negative infinity must be outside bounds")
			expect(not newGrid():CanOccupyCells({ cell }), "Negative infinity must not be occupiable")
			expectError(function()
				ShapeRotation.NormalizeShape({ cell })
			end, "finite integer")
		end,
	},
	{
		Name = "fractional coordinates are rejected by grid boundaries",
		Run = function()
			local cell = { X = 1.25, Y = 0, Z = 0 }
			expect(not newGrid():IsInsideBounds(cell), "Fractional coordinate must be outside bounds")
			expect(not newGrid():CanOccupyCells({ cell }), "Fractional coordinate must not be occupiable")
		end,
	},
	{
		Name = "malformed coordinate and collection values are rejected safely",
		Run = function()
			local grid = newGrid()
			expect(not grid:IsInsideBounds((nil :: any)), "Non-table cell must be outside bounds")
			expect(not grid:IsInsideBounds(({ X = "1", Y = 0, Z = 0 } :: any)), "String coordinate must be outside bounds")
			expect(not grid:CanOccupyCells(("not-cells" :: any)), "Non-table cell collection must be rejected")
			expect(not grid:CanOccupyCells(({ "not-a-cell" } :: any)), "Malformed cell member must be rejected")
			expectError(function()
				ShapeRotation.NormalizeShape(({ { X = "1", Y = 0, Z = 0 } } :: any))
			end, "finite integer")
		end,
	},
	{
		Name = "invalid grid dimensions fail with a clear finite-integer error",
		Run = function()
			local invalidValues: { any } = { 0 / 0, math.huge, -math.huge, 1.5, "5" }
			for _, value in ipairs(invalidValues) do
				expectError(function()
					OccupancyGrid.CreateGrid(value, 4, 5)
				end, "finite integer")
			end
			expectError(function()
				OccupancyGrid.CreateGrid(5, (nil :: any), 5)
			end, "finite integer")
			expectError(function()
				OccupancyGrid.CreateGrid(5, 4, 0)
			end, "positive finite integer")
		end,
	},
	{
		Name = "invalid solver X and Z values return no placement",
		Run = function()
			local grid = newGrid()
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.SingleCube)[1]
			local invalidValues: { any } = { 0 / 0, math.huge, -math.huge, 1.5, "1" }
			for _, value in ipairs(invalidValues) do
				expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, value, 0), nil)
				expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, value), nil)
			end
			expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, (nil :: any), 0), nil)
			expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, (nil :: any)), nil)
		end,
	},
	{
		Name = "invalid difficulty counts fail with a clear finite-integer error",
		Run = function()
			local invalidValues: { any } = { 0 / 0, math.huge, -math.huge, 1.5, -1, "10" }
			for _, value in ipairs(invalidValues) do
				expectError(function()
					DifficultyClassifier.ClassifyPlacementCount(value)
				end, "finite integer")
			end
			expectError(function()
				DifficultyClassifier.ClassifyPlacementCount((nil :: any))
			end, "finite integer")
		end,
	},
	{
		Name = "invalid quarter-turn values fail with a clear finite-integer error",
		Run = function()
			local invalidValues: { any } = { 0 / 0, math.huge, -math.huge, 0.5, "1" }
			for _, value in ipairs(invalidValues) do
				expectError(function()
					ShapeRotation.RotateShapeY(ShapeDefinitions.FlatL.Cells, value)
				end, "finite integer")
			end
			expectError(function()
				ShapeRotation.RotateShapeY(ShapeDefinitions.FlatL.Cells, (nil :: any))
			end, "finite integer")
		end,
	},
})

addSuite("Collision", {
	{
		Name = "non-overlapping placement passes",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 } })
			expect(grid:CanOccupyCells({ { X = 1, Y = 0, Z = 0 } }), "Non-overlap should pass")
		end,
	},
	{
		Name = "any overlapping cell fails",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 } })
			expect(not grid:CanOccupyCells({ { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 } }), "Overlap should fail")
		end,
	},
	{
		Name = "valid application marks exactly expected cells",
		Run = function()
			local grid = newGrid()
			local cells = { { X = 0, Y = 0, Z = 0 }, { X = 1, Y = 0, Z = 0 } }
			applyCells(grid, cells)
			expectEqual(grid:GetOccupiedCellCount(), 2)
			expect(grid:IsCellOccupied(cells[1]) and grid:IsCellOccupied(cells[2]), "Both cells should be marked")
		end,
	},
	{
		Name = "invalid application never partially mutates",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 } })
			local applied = grid:ApplyPlacement(makePlacement({ { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 } }))
			expect(not applied, "Invalid placement must fail")
			expectEqual(grid:GetOccupiedCellCount(), 1)
			expect(not grid:IsCellOccupied({ X = 1, Y = 0, Z = 0 }), "Non-colliding prefix must not be applied")
		end,
	},
})

addSuite("Grid clone independence", {
	{
		Name = "clone starts with identical dimensions occupancy and count",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 3, Y = 2, Z = 1 }, { X = 1, Y = 1, Z = 1 } })
			local clone = grid:Clone()
			expectEqual(clone.Width, grid.Width)
			expectEqual(clone.Height, grid.Height)
			expectEqual(clone.Depth, grid.Depth)
			expectEqual(clone:GetOccupiedCellCount(), grid:GetOccupiedCellCount())
			expectEqual(cellListKey(clone:GetOccupiedCells()), cellListKey(grid:GetOccupiedCells()))
		end,
	},
	{
		Name = "mutating clone does not mutate original",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 1, Y = 1, Z = 1 } })
			local clone = grid:Clone()
			applyCells(clone, { { X = 2, Y = 2, Z = 2 } })
			expectEqual(grid:GetOccupiedCellCount(), 1)
			expectEqual(clone:GetOccupiedCellCount(), 2)
			expect(not grid:IsCellOccupied({ X = 2, Y = 2, Z = 2 }), "Original must not see clone mutation")
		end,
	},
	{
		Name = "mutating original does not mutate clone",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 1, Y = 1, Z = 1 } })
			local clone = grid:Clone()
			applyCells(grid, { { X = 3, Y = 2, Z = 3 } })
			expectEqual(grid:GetOccupiedCellCount(), 2)
			expectEqual(clone:GetOccupiedCellCount(), 1)
			expect(not clone:IsCellOccupied({ X = 3, Y = 2, Z = 3 }), "Clone must not see original mutation")
		end,
	},
})

addSuite("Occupied snapshot contract", {
	{
		Name = "occupied snapshot is canonically ordered by X then Y then Z",
		Run = function()
			local grid = newGrid()
			applyCells(grid, {
				{ X = 2, Y = 0, Z = 2 },
				{ X = 0, Y = 3, Z = 4 },
				{ X = 0, Y = 1, Z = 4 },
				{ X = 0, Y = 1, Z = 2 },
				{ X = 1, Y = 0, Z = 0 },
			})
			expectEqual(cellListKey(grid:GetOccupiedCells()), "0:1:2|0:1:4|0:3:4|1:0:0|2:0:2")
		end,
	},
	{
		Name = "mutating snapshot list does not mutate grid occupancy",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 }, { X = 1, Y = 0, Z = 0 } })
			local snapshot = grid:GetOccupiedCells()
			table.remove(snapshot, 1)
			table.insert(snapshot, { X = 4, Y = 3, Z = 4 })
			expectEqual(grid:GetOccupiedCellCount(), 2)
			expect(grid:IsCellOccupied({ X = 0, Y = 0, Z = 0 }), "Removed snapshot entry must remain occupied")
			expect(not grid:IsCellOccupied({ X = 4, Y = 3, Z = 4 }), "Inserted snapshot entry must not become occupied")
		end,
	},
	{
		Name = "mutating snapshot cells does not mutate grid occupancy",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 } })
			local snapshot = grid:GetOccupiedCells()
			snapshot[1].X = 4
			snapshot[1].Y = 3
			snapshot[1].Z = 4
			expect(grid:IsCellOccupied({ X = 0, Y = 0, Z = 0 }), "Original coordinate must remain occupied")
			expect(not grid:IsCellOccupied({ X = 4, Y = 3, Z = 4 }), "Mutated snapshot coordinate must remain empty")
		end,
	},
})

addSuite("Auto-drop", {
	{
		Name = "single cube drops to floor",
		Run = function()
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.SingleCube)[1]
			local placement = PlacementSolver.GetAutoDropPlacement(newGrid(), rotation, 2, 3)
			expect(placement ~= nil, "Cube should fit")
			expectEqual((placement :: Placement).Origin.Y, 0)
		end,
	},
	{
		Name = "cube drops on occupied floor cube",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 } })
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.SingleCube)[1]
			local placement = PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, 0)
			expectEqual((placement :: Placement).Origin.Y, 1)
		end,
	},
	{
		Name = "bar rests on platform",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 }, { X = 1, Y = 0, Z = 0 } })
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.HorizontalBar2)[1]
			local placement = PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, 0)
			expectEqual((placement :: Placement).Origin.Y, 1)
		end,
	},
	{
		Name = "rigid bar bridges a gap",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 }, { X = 2, Y = 0, Z = 0 } })
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.HorizontalBar3)[1]
			local placement = PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, 0)
			expectEqual((placement :: Placement).Origin.Y, 1)
			expect(not grid:IsCellOccupied({ X = 1, Y = 0, Z = 0 }), "Bridge gap should remain empty")
		end,
	},
	{
		Name = "shape cannot pass upper obstruction",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 3, Z = 0 } })
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.SingleCube)[1]
			expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, 0), nil)
		end,
	},
	{
		Name = "irregular multi-cell shape cannot teleport past lower-part entry obstruction",
		Run = function()
			local grid = newGrid()
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.LargeIrregular)[1]
			local entryY = grid.Height - rotation.SizeY
			applyCells(grid, { { X = 2, Y = entryY, Z = 0 } })

			local lowerCells: { Cell } = {}
			for _, shapeCell in ipairs(rotation.Cells) do
				table.insert(lowerCells, { X = shapeCell.X, Y = shapeCell.Y, Z = shapeCell.Z })
			end
			expect(grid:CanOccupyCells(lowerCells), "Lower cavity should fit if entry collision were ignored")
			expectEqual(PlacementSolver.GetAutoDropPlacement(grid, rotation, 0, 0), nil)
		end,
	},
	{
		Name = "shape too tall returns no placement",
		Run = function()
			local oversized: ShapeDefinition = {
				Id = "oversized_height_fixture",
				Cells = {
					{ X = 0, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 }, { X = 0, Y = 2, Z = 0 },
					{ X = 0, Y = 3, Z = 0 }, { X = 0, Y = 4, Z = 0 },
				},
			}
			local rotation = ShapeRotation.GetUniqueRotations(oversized)[1]
			expectEqual(PlacementSolver.GetAutoDropPlacement(newGrid(), rotation, 0, 0), nil)
		end,
	},
	{
		Name = "identical calls return identical result",
		Run = function()
			local grid = newGrid()
			local rotation = ShapeRotation.GetUniqueRotations(ShapeDefinitions.Chair)[1]
			local a = PlacementSolver.GetAutoDropPlacement(grid, rotation, 1, 1, "chair", 1)
			local b = PlacementSolver.GetAutoDropPlacement(grid, rotation, 1, 1, "chair", 1)
			expectEqual((a :: Placement).Key, (b :: Placement).Key)
		end,
	},
})

addSuite("Enumeration", {
	{
		Name = "single cube has 25 empty-grid placements",
		Run = function()
			expectEqual(#PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.SingleCube), 25)
		end,
	},
	{
		Name = "two-cell bar has 40 empty-grid placements",
		Run = function()
			expectEqual(#PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.HorizontalBar2), 40)
		end,
	},
	{
		Name = "enumeration returns no duplicate keys",
		Run = function()
			local seen: { [string]: boolean } = {}
			for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.FlatT)) do
				expect(not seen[placement.Key], "Duplicate placement key: " .. placement.Key)
				seen[placement.Key] = true
			end
		end,
	},
	{
		Name = "every enumerated placement independently validates",
		Run = function()
			local grid = newGrid()
			for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(grid, ShapeDefinitions.LargeIrregular)) do
				expect(PlacementSolver.ValidatePlacement(grid, placement), "Invalid enumerated placement: " .. placement.Key)
			end
		end,
	},
	{
		Name = "fully blocked shape has zero placements",
		Run = function()
			expectEqual(#PlacementSolver.EnumerateLegalPlacements(fullGrid(), ShapeDefinitions.SingleCube), 0)
		end,
	},
	{
		Name = "partial grid includes only reachable placements",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 3, Z = 0 } })
			local placements = PlacementSolver.EnumerateLegalPlacements(grid, ShapeDefinitions.SingleCube)
			expectEqual(#placements, 24)
			for _, placement in ipairs(placements) do
				expect(not (placement.Origin.X == 0 and placement.Origin.Z == 0), "Blocked entry column must be excluded")
			end
		end,
	},
})

addSuite("Enumeration ordering contract", {
	{
		Name = "repeated enumeration returns the exact same key sequence",
		Run = function()
			local grid = newGrid()
			local first = PlacementSolver.EnumerateLegalPlacements(grid, ShapeDefinitions.FlatL)
			local second = PlacementSolver.EnumerateLegalPlacements(grid, ShapeDefinitions.FlatL)
			expectEqual(#first, #second)
			for index, placement in ipairs(first) do
				expectEqual(placement.Key, second[index].Key, string.format("Enumeration differs at index %d", index))
			end
		end,
	},
	{
		Name = "rotation index is nondecreasing",
		Run = function()
			local previousRotation = 0
			for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.FlatL)) do
				expect(placement.RotationIndex >= previousRotation, "Rotation index moved backward")
				previousRotation = placement.RotationIndex
			end
		end,
	},
	{
		Name = "X is nondecreasing within each rotation",
		Run = function()
			local previousRotation = 0
			local previousX = -1
			for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.FlatL)) do
				if placement.RotationIndex ~= previousRotation then
					previousRotation = placement.RotationIndex
					previousX = -1
				end
				expect(placement.Origin.X >= previousX, "X moved backward within a rotation")
				previousX = placement.Origin.X
			end
		end,
	},
	{
		Name = "Z is strictly increasing within each rotation and X group",
		Run = function()
			local previousRotation = 0
			local previousX = -1
			local previousZ = -1
			for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.FlatL)) do
				if placement.RotationIndex ~= previousRotation or placement.Origin.X ~= previousX then
					previousRotation = placement.RotationIndex
					previousX = placement.Origin.X
					previousZ = -1
				end
				expect(placement.Origin.Z > previousZ, "Z did not strictly increase within an X group")
				previousZ = placement.Origin.Z
			end
		end,
	},
	{
		Name = "single-cube enumeration follows exact rotation X Z loop order",
		Run = function()
			local placements = PlacementSolver.EnumerateLegalPlacements(newGrid(), ShapeDefinitions.SingleCube)
			local index = 0
			for x = 0, GameConfig.BOX_WIDTH - 1 do
				for z = 0, GameConfig.BOX_DEPTH - 1 do
					index += 1
					local placement = placements[index]
					expectEqual(placement.RotationIndex, 1)
					expectEqual(placement.Origin.X, x)
					expectEqual(placement.Origin.Z, z)
				end
			end
			expectEqual(index, #placements)
		end,
	},
})

addSuite("Grid accounting", {
	{
		Name = "empty grid reports zero cells and zero fill",
		Run = function()
			local grid = newGrid()
			expectEqual(grid:GetOccupiedCellCount(), 0)
			expectEqual(grid:GetFillRatio(), 0)
		end,
	},
	{
		Name = "filled-cell count updates",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 0, Y = 0, Z = 0 }, { X = 1, Y = 0, Z = 0 }, { X = 2, Y = 0, Z = 0 } })
			expectEqual(grid:GetOccupiedCellCount(), 3)
			expectNear(grid:GetFillRatio(), 0.03, 0.000001)
		end,
	},
	{
		Name = "full grid reports 100 cells and full fill",
		Run = function()
			local grid = fullGrid()
			expectEqual(grid:GetOccupiedCellCount(), 100)
			expectEqual(grid:GetFillRatio(), 1)
		end,
	},
	{
		Name = "fill ratio remains within zero and one",
		Run = function()
			local empty = newGrid():GetFillRatio()
			local full = fullGrid():GetFillRatio()
			expect(empty >= 0 and empty <= 1 and full >= 0 and full <= 1, "Fill ratios must be bounded")
		end,
	},
})

addSuite("Capacity product contract", {
	{
		Name = "configured capacity equals width times height times depth",
		Run = function()
			expectEqual(
				GameConfig.BOX_CAPACITY,
				GameConfig.BOX_WIDTH * GameConfig.BOX_HEIGHT * GameConfig.BOX_DEPTH
			)
		end,
	},
	{
		Name = "Phase 01 box dimensions retain the 100-cell capacity contract",
		Run = function()
			expectEqual(GameConfig.BOX_CAPACITY, 100)
			expectEqual(newGrid().Width * newGrid().Height * newGrid().Depth, GameConfig.BOX_CAPACITY)
		end,
	},
})

addSuite("Difficulty", {
	{ Name = "10 is Easy", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(10), "Easy") end },
	{ Name = "9 is Tight", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(9), "Tight") end },
	{ Name = "4 is Tight", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(4), "Tight") end },
	{ Name = "3 is Brutal", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(3), "Brutal") end },
	{ Name = "1 is Brutal", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(1), "Brutal") end },
	{ Name = "0 is Impossible", Run = function() expectEqual(DifficultyClassifier.ClassifyPlacementCount(0), "Impossible") end },
})

addSuite("Fairness", {
	{
		Name = "shape with placement is offerable",
		Run = function()
			expect(PlacementSolver.HasLegalPlacement(newGrid(), ShapeDefinitions.SingleCube), "Single cube should be offerable")
		end,
	},
	{
		Name = "shape with zero placements is excluded",
		Run = function()
			expect(not PlacementSolver.HasLegalPlacement(fullGrid(), ShapeDefinitions.SingleCube), "Blocked shape must be excluded")
		end,
	},
	{
		Name = "candidate checks do not mutate grid",
		Run = function()
			local grid = newGrid()
			applyCells(grid, { { X = 1, Y = 0, Z = 1 } })
			local before = grid:GetOccupiedCellCount()
			PlacementSolver.HasLegalPlacement(grid, ShapeDefinitions.FlatL)
			expectEqual(grid:GetOccupiedCellCount(), before)
		end,
	},
})

addSuite("Fixed-seed fuzz properties", {
	{
		Name = "1,000 randomized placements preserve bounds collision and accounting invariants",
		Run = function()
			local random = Random.new(GameConfig.DEVELOPMENT.FUZZ_SEED)
			local shapes = { ShapeDefinitions.SingleCube, ShapeDefinitions.HorizontalBar2, ShapeDefinitions.FlatL, ShapeDefinitions.Chair }

			for caseIndex = 1, GameConfig.DEVELOPMENT.FUZZ_CASES do
				local grid = newGrid()
				local occupiedKeys: { [string]: boolean } = {}
				local fixtureCells: { Cell } = {}
				for _ = 1, random:NextInteger(0, 10) do
					local candidate = {
						X = random:NextInteger(0, grid.Width - 1),
						Y = random:NextInteger(0, grid.Height - 1),
						Z = random:NextInteger(0, grid.Depth - 1),
					}
					local key = string.format("%d:%d:%d", candidate.X, candidate.Y, candidate.Z)
					if not occupiedKeys[key] then
						occupiedKeys[key] = true
						table.insert(fixtureCells, candidate)
					end
				end
				if #fixtureCells > 0 then
					applyCells(grid, fixtureCells)
				end

				local shape = shapes[random:NextInteger(1, #shapes)]
				local rotations = ShapeRotation.GetUniqueRotations(shape)
				local rotation = rotations[random:NextInteger(1, #rotations)]
				local originX = random:NextInteger(-1, grid.Width)
				local originY = random:NextInteger(-1, grid.Height)
				local originZ = random:NextInteger(-1, grid.Depth)
				local candidateCells: { Cell } = {}
				local expectedValid = true
				for _, shapeCell in ipairs(rotation.Cells) do
					local candidate = {
						X = shapeCell.X + originX,
						Y = shapeCell.Y + originY,
						Z = shapeCell.Z + originZ,
					}
					table.insert(candidateCells, candidate)
					local key = string.format("%d:%d:%d", candidate.X, candidate.Y, candidate.Z)
					if candidate.X < 0 or candidate.X >= grid.Width
						or candidate.Y < 0 or candidate.Y >= grid.Height
						or candidate.Z < 0 or candidate.Z >= grid.Depth
						or occupiedKeys[key]
					then
						expectedValid = false
					end
				end

				local accepted = grid:CanOccupyCells(candidateCells)
				expectEqual(accepted, expectedValid, string.format("Fuzz case %d validation mismatch", caseIndex))
				local before = grid:GetOccupiedCellCount()
				local applied = grid:ApplyPlacement(makePlacement(candidateCells, "fuzz" .. caseIndex))
				if expectedValid then
					expect(applied, string.format("Fuzz case %d valid placement did not apply", caseIndex))
					expectEqual(grid:GetOccupiedCellCount(), before + #candidateCells)
				else
					expect(not applied, string.format("Fuzz case %d invalid placement applied", caseIndex))
					expectEqual(grid:GetOccupiedCellCount(), before)
				end

				if caseIndex % 25 == 0 then
					local enumerationGrid = newGrid()
					for _, placement in ipairs(PlacementSolver.EnumerateLegalPlacements(enumerationGrid, shape)) do
						expect(PlacementSolver.ValidatePlacement(enumerationGrid, placement), "Fuzz enumeration returned invalid placement")
					end
				end
			end
		end,
	},
})

function FoundationTestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}

	print(string.format("[ONE_MORE_ITEM][FoundationTests] Starting %d suites", #suites))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][FoundationTests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][FoundationTests] FAIL " .. message)
			end
		end
	end

	local benchmarkGrid = newGrid()
	local benchmarkStartedAt = os.clock()
	local benchmarkPlacementCount = 0
	for _ = 1, GameConfig.DEVELOPMENT.BENCHMARK_ITERATIONS do
		benchmarkPlacementCount += #PlacementSolver.EnumerateLegalPlacements(benchmarkGrid, ShapeDefinitions.FlatL)
	end
	local benchmarkSeconds = os.clock() - benchmarkStartedAt
	print(string.format(
		"[ONE_MORE_ITEM][FoundationTests] BENCHMARK %d FlatL enumerations, %d total placements, %.6f seconds",
		GameConfig.DEVELOPMENT.BENCHMARK_ITERATIONS,
		benchmarkPlacementCount,
		benchmarkSeconds
	))

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][FoundationTests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs fuzzCases=%d fuzzSeed=%d",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		GameConfig.DEVELOPMENT.FUZZ_CASES,
		GameConfig.DEVELOPMENT.FUZZ_SEED
	))

	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][FoundationTests] FAILURE %d: %s", index, failure))
		end
	end

	return {
		Suites = #suites,
		Tests = totalTests,
		Passed = passed,
		Failed = failed,
		Failures = failures,
		DurationSeconds = duration,
		FuzzCases = GameConfig.DEVELOPMENT.FUZZ_CASES,
		FuzzSeed = GameConfig.DEVELOPMENT.FUZZ_SEED,
		BenchmarkIterations = GameConfig.DEVELOPMENT.BENCHMARK_ITERATIONS,
		BenchmarkSeconds = benchmarkSeconds,
	}
end

return table.freeze(FoundationTestSuite)
