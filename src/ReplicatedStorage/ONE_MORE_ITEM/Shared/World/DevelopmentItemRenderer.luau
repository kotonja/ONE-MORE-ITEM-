--!strict

local GridTypes = require(script.Parent.Parent.Grid.GridTypes)
local GridWorldTransform = require(script.Parent.GridWorldTransform)

type Cell = GridTypes.Cell

local DevelopmentItemRenderer = {}

function DevelopmentItemRenderer.Clear(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

function DevelopmentItemRenderer.RenderCells(
	template: BasePart,
	parent: Instance,
	modelName: string,
	cells: { Cell },
	gridOrigin: CFrame,
	cellSize: number,
	color: Color3,
	transparency: number?
): Model
	local model = Instance.new("Model")
	model.Name = modelName

	for index, cell in ipairs(cells) do
		local block = template:Clone()
		block.Name = string.format("Cell_%02d", index)
		block.Anchored = true
		block.CanCollide = false
		block.CanTouch = false
		block.CanQuery = false
		block.Color = color
		block.Transparency = transparency or 0
		block.CFrame = GridWorldTransform.CellToCFrame(gridOrigin, cell, cellSize)
		block.Parent = model
	end

	model.Parent = parent
	return model
end

return table.freeze(DevelopmentItemRenderer)
