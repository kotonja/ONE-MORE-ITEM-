--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local StationDefinitions = require(Root.Shared.World.StationDefinitions)

type ShelfRecord = {
	StationId: string,
	Model: Model,
	RankName: TextLabel,
	CollectionCount: TextLabel,
	Slots: { BasePart },
	Runtime: Folder,
}

export type CollectionView = {
	Discovered: { [string]: boolean },
	MasteryCounts: { [string]: number },
	-- Phase 05 stores discoveries oldest-to-newest; presentation reads from the tail.
	RecentDiscoveries: { string },
}

export type ProfileView = {
	PackingXP: number,
	Collection: CollectionView,
}

export type Service = {
	Render: (self: Service, stationId: string, profile: ProfileView) -> (boolean, string),
	Clear: (self: Service, stationId: string) -> boolean,
	ClearAll: (self: Service) -> (),
	GetRuntimeCount: (self: Service, stationId: string) -> number,
	GetShelfCount: (self: Service) -> number,
}

type ServiceImpl = Service & {
	_template: BasePart,
	_shelves: { [string]: ShelfRecord },
	_shelfCount: number,
}

type FeaturedItem = {
	ItemId: string,
	CatalogIndex: number,
	MasteryCount: number,
	MasteryTier: number,
}

local MAX_FEATURED_ITEMS = 6
local MAX_RECENT_ITEMS = 3

local CollectionShelfService = {}
CollectionShelfService.__index = CollectionShelfService

local function requireDirect(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA(className) then
		error(string.format("Collection shelf requires %s.%s to be %s", parent:GetFullName(), name, className), 3)
	end
	return child
end

local function validateTemplate(template: BasePart)
	if not template.Anchored or template.CanCollide or template.CanTouch or template.CanQuery then
		error("CollectionShelfItemTemplate must be anchored and non-interactive", 3)
	end
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			error("CollectionShelfItemTemplate must be script-free", 3)
		end
	end
end

local function resolveShelf(stationModel: Model, stationId: string): ShelfRecord
	local shelf = requireDirect(stationModel, "CollectionShelf", "Model") :: Model
	requireDirect(shelf, "ShelfBase", "BasePart")
	local shelfLabel = requireDirect(shelf, "ShelfLabel", "BasePart")
	local billboard = requireDirect(shelfLabel, "BillboardGui", "BillboardGui")
	local rankName = requireDirect(billboard, "RankName", "TextLabel") :: TextLabel
	local collectionCount = requireDirect(billboard, "CollectionCount", "TextLabel") :: TextLabel
	local slots: { BasePart } = table.create(MAX_FEATURED_ITEMS)
	for index = 1, MAX_FEATURED_ITEMS do
		slots[index] = requireDirect(shelf, string.format("Slot_%02d", index), "BasePart") :: BasePart
	end
	local runtime = requireDirect(shelf, "Runtime", "Folder") :: Folder
	return {
		StationId = stationId,
		Model = shelf,
		RankName = rankName,
		CollectionCount = collectionCount,
		Slots = slots,
		Runtime = runtime,
	}
end

local function clearRecord(record: ShelfRecord)
	for _, child in ipairs(record.Runtime:GetChildren()) do
		child:Destroy()
	end
	record.RankName.Text = "UNASSIGNED"
	record.CollectionCount.Text = "0 / 8 DISCOVERED"
	record.Model:SetAttribute("FeaturedItemCount", 0)
	record.Model:SetAttribute("ProfileRendered", false)
end

local function tierIndex(count: number): number
	if count >= 50 then
		return 4
	elseif count >= 20 then
		return 3
	elseif count >= 5 then
		return 2
	elseif count >= 1 then
		return 1
	end
	return 0
end

local function validCount(value: number?): number
	if type(value) ~= "number" or value ~= value or value < 0 or value % 1 ~= 0 then
		return 0
	end
	return value
end

local function collectFeatured(profile: ProfileView): ({ FeaturedItem }, number)
	local collection = profile.Collection
	local catalog = DevelopmentItemDefinitions.Ordered :: { any }
	local catalogIndex: { [string]: number } = {}
	local discoveredCount = 0
	for index, definition in ipairs(catalog) do
		catalogIndex[definition.Id] = index
		if collection.Discovered[definition.Id] == true then
			discoveredCount += 1
		end
	end

	local featured: { FeaturedItem } = {}
	local included: { [string]: boolean } = {}
	for recentIndex = #collection.RecentDiscoveries, 1, -1 do
		local itemId = collection.RecentDiscoveries[recentIndex]
		local index = catalogIndex[itemId]
		if #featured >= MAX_RECENT_ITEMS then
			break
		end
		if index ~= nil and collection.Discovered[itemId] == true and not included[itemId] then
			local masteryCount = validCount(collection.MasteryCounts[itemId])
			table.insert(featured, {
				ItemId = itemId,
				CatalogIndex = index,
				MasteryCount = masteryCount,
				MasteryTier = tierIndex(masteryCount),
			})
			included[itemId] = true
		end
	end

	local remaining: { FeaturedItem } = {}
	for index, definition in ipairs(catalog) do
		local itemId = definition.Id :: string
		if collection.Discovered[itemId] == true and not included[itemId] then
			local masteryCount = validCount(collection.MasteryCounts[itemId])
			table.insert(remaining, {
				ItemId = itemId,
				CatalogIndex = index,
				MasteryCount = masteryCount,
				MasteryTier = tierIndex(masteryCount),
			})
		end
	end
	table.sort(remaining, function(left: FeaturedItem, right: FeaturedItem): boolean
		if left.MasteryTier ~= right.MasteryTier then
			return left.MasteryTier > right.MasteryTier
		elseif left.MasteryCount ~= right.MasteryCount then
			return left.MasteryCount > right.MasteryCount
		end
		return left.CatalogIndex < right.CatalogIndex
	end)
	for _, item in ipairs(remaining) do
		if #featured >= MAX_FEATURED_ITEMS then
			break
		end
		table.insert(featured, item)
		included[item.ItemId] = true
	end
	return featured, discoveredCount
end

local function rankNameForXP(packingXP: number): string
	local definition = PackingRankDefinitions.GetRankForXP(validCount(packingXP))
	return definition.Name
end

local function proxySizeForDefinition(definition: any): Vector3
	local minimumX = math.huge
	local minimumY = math.huge
	local minimumZ = math.huge
	local maximumX = -math.huge
	local maximumY = -math.huge
	local maximumZ = -math.huge
	for _, cell in ipairs(definition.Shape.Cells) do
		minimumX = math.min(minimumX, cell.X)
		minimumY = math.min(minimumY, cell.Y)
		minimumZ = math.min(minimumZ, cell.Z)
		maximumX = math.max(maximumX, cell.X)
		maximumY = math.max(maximumY, cell.Y)
		maximumZ = math.max(maximumZ, cell.Z)
	end
	if minimumX == math.huge then
		return Vector3.new(0.7, 0.7, 0.7)
	end
	local cellExtents = Vector3.new(
		maximumX - minimumX + 1,
		maximumY - minimumY + 1,
		maximumZ - minimumZ + 1
	)
	local scale = 1.3 / math.max(cellExtents.X, cellExtents.Y, cellExtents.Z)
	return Vector3.new(
		math.max(0.35, cellExtents.X * scale),
		math.max(0.35, cellExtents.Y * scale),
		math.max(0.35, cellExtents.Z * scale)
	)
end

function CollectionShelfService.Create(stationsRoot: Instance, template: BasePart): ServiceImpl
	validateTemplate(template)
	local shelves: { [string]: ShelfRecord } = {}
	local ordered = StationDefinitions.Ordered :: { any }
	for _, definition in ipairs(ordered) do
		local station = requireDirect(stationsRoot, definition.ModelName, "Model") :: Model
		local record = resolveShelf(station, definition.Id)
		if #record.Runtime:GetChildren() ~= 0 then
			error(string.format("%s.Runtime must be empty before server startup", record.Model:GetFullName()), 2)
		end
		shelves[definition.Id] = record
		clearRecord(record)
	end
	if #ordered ~= 8 then
		error("CollectionShelfService requires exactly eight station definitions", 2)
	end
	return setmetatable({
		_template = template,
		_shelves = shelves,
		_shelfCount = #ordered,
	}, CollectionShelfService) :: ServiceImpl
end

function CollectionShelfService.Render(
	self: ServiceImpl,
	stationId: string,
	profile: ProfileView
): (boolean, string)
	local record = self._shelves[stationId]
	if record == nil then
		return false, "UNKNOWN_STATION"
	end
	clearRecord(record)
	local featured, discoveredCount = collectFeatured(profile)
	record.RankName.Text = string.upper(rankNameForXP(profile.PackingXP))
	record.CollectionCount.Text = string.format("%d / 8 DISCOVERED", discoveredCount)
	for index, featuredItem in ipairs(featured) do
		local definition = DevelopmentItemDefinitions.Get(featuredItem.ItemId)
		if definition == nil then
			clearRecord(record)
			return false, "UNKNOWN_ITEM"
		end
		local proxy = self._template:Clone() :: BasePart
		for _, child in ipairs(proxy:GetChildren()) do
			if child:IsA("LuaSourceContainer") then
				child:Destroy()
			end
		end
		proxy.Name = string.format("Featured_%02d", index)
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanTouch = false
		proxy.CanQuery = false
		proxy.Massless = true
		proxy.Color = definition.Color
		proxy.Size = proxySizeForDefinition(definition)
		local slot = record.Slots[index]
		proxy.CFrame = slot.CFrame * CFrame.new(0, (slot.Size.Y + proxy.Size.Y) * 0.5, 0)
		proxy:SetAttribute("ItemId", featuredItem.ItemId)
		proxy:SetAttribute("MasteryCount", featuredItem.MasteryCount)
		proxy.Parent = record.Runtime
	end
	record.Model:SetAttribute("FeaturedItemCount", #featured)
	record.Model:SetAttribute("ProfileRendered", true)
	return true, "RENDERED"
end

function CollectionShelfService.Clear(self: ServiceImpl, stationId: string): boolean
	local record = self._shelves[stationId]
	if record == nil then
		return false
	end
	clearRecord(record)
	return true
end

function CollectionShelfService.ClearAll(self: ServiceImpl)
	for _, record in pairs(self._shelves) do
		clearRecord(record)
	end
end

function CollectionShelfService.GetRuntimeCount(self: ServiceImpl, stationId: string): number
	local record = self._shelves[stationId]
	return if record ~= nil then #record.Runtime:GetChildren() else 0
end

function CollectionShelfService.GetShelfCount(self: ServiceImpl): number
	return self._shelfCount
end

return table.freeze(CollectionShelfService)
