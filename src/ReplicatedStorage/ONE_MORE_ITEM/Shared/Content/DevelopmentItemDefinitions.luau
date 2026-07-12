--!strict

local ShapeDefinitions = require(script.Parent.ShapeDefinitions)
local GridTypes = require(script.Parent.Parent.Grid.GridTypes)

type ShapeDefinition = GridTypes.ShapeDefinition

export type ShapeFamily = "Single" | "Bar" | "Vertical" | "Planar" | "Furniture" | "Irregular"

export type DevelopmentItemDefinition = {
	Id: string,
	DisplayName: string,
	ShapeId: string,
	Shape: ShapeDefinition,
	ShapeFamily: ShapeFamily,
	BaseValue: number,
	Color: Color3,
}

local function item(
	id: string,
	displayName: string,
	shape: ShapeDefinition,
	family: ShapeFamily,
	baseValue: number,
	color: Color3
): DevelopmentItemDefinition
	return table.freeze({
		Id = id,
		DisplayName = displayName,
		ShapeId = shape.Id,
		Shape = shape,
		ShapeFamily = family,
		BaseValue = baseValue,
		Color = color,
	}) :: DevelopmentItemDefinition
end

local ordered: { DevelopmentItemDefinition } = {
	item("parcel", "Parcel", ShapeDefinitions.SingleCube, "Single", 15, Color3.fromRGB(201, 146, 76)),
	item("long_package", "Long Package", ShapeDefinitions.HorizontalBar2, "Bar", 25, Color3.fromRGB(34, 211, 230)),
	item("lamp_blockout", "Lamp Blockout", ShapeDefinitions.VerticalColumn3, "Vertical", 35, Color3.fromRGB(255, 211, 102)),
	item("table_blockout", "Table Blockout", ShapeDefinitions.FlatSquare2x2, "Planar", 40, Color3.fromRGB(75, 134, 255)),
	item("chair_blockout", "Chair Blockout", ShapeDefinitions.Chair, "Furniture", 50, Color3.fromRGB(99, 232, 92)),
	item("l_package", "L Package", ShapeDefinitions.FlatL, "Planar", 45, Color3.fromRGB(157, 103, 255)),
	item("t_package", "T Package", ShapeDefinitions.FlatT, "Planar", 55, Color3.fromRGB(255, 146, 43)),
	item("heavy_cargo", "Heavy Cargo", ShapeDefinitions.LargeIrregular, "Irregular", 95, Color3.fromRGB(255, 91, 51)),
}
table.freeze(ordered)

local byId: { [string]: DevelopmentItemDefinition } = {}
for _, definition in ipairs(ordered) do
	byId[definition.Id] = definition
end
table.freeze(byId)

local DevelopmentItemDefinitions = {
	Ordered = ordered,
	ById = byId,
}

function DevelopmentItemDefinitions.Get(itemId: string): DevelopmentItemDefinition?
	return byId[itemId]
end

return table.freeze(DevelopmentItemDefinitions)
