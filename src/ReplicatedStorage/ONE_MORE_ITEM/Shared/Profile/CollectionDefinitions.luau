--!strict

local DevelopmentItemDefinitions = require(script.Parent.Parent.Content.DevelopmentItemDefinitions)

local orderedItemIds: { string } = table.create(#DevelopmentItemDefinitions.Ordered)
local itemOrder: { [string]: number } = {}
for index, itemDefinition in ipairs(DevelopmentItemDefinitions.Ordered) do
	assert(itemOrder[itemDefinition.Id] == nil, string.format("Duplicate collection item id: %s", itemDefinition.Id))
	orderedItemIds[index] = itemDefinition.Id
	itemOrder[itemDefinition.Id] = index
end
table.freeze(orderedItemIds)
table.freeze(itemOrder)

local CollectionDefinitions = {
	OrderedItemIds = orderedItemIds,
	ItemOrder = itemOrder,
	TotalCount = #orderedItemIds,
}

function CollectionDefinitions.IsValidItemId(itemId: string): boolean
	return itemOrder[itemId] ~= nil and DevelopmentItemDefinitions.Get(itemId) ~= nil
end

function CollectionDefinitions.GetCatalogIndex(itemId: string): number?
	return itemOrder[itemId]
end

function CollectionDefinitions.GetDiscoveredCount(discovered: { [string]: boolean }): number
	local count = 0
	for _, itemId in ipairs(orderedItemIds) do
		if discovered[itemId] == true then
			count += 1
		end
	end
	return count
end

return table.freeze(CollectionDefinitions)
