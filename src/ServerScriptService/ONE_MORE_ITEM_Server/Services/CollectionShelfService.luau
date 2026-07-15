--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local CollectionDefinitions = require(Root.Shared.Profile.CollectionDefinitions)
local MasteryDefinitions = require(Root.Shared.Profile.MasteryDefinitions)
local PackingRankDefinitions = require(Root.Shared.Profile.PackingRankDefinitions)
local StationDefinitions = require(Root.Shared.World.StationDefinitions)

type ShelfRecord = {
	StationId: string,
	StationModel: Model,
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
	GetRebuildCount: (self: Service, stationId: string) -> number,
	GetRenderFingerprint: (self: Service, stationId: string) -> string?,
}

type RenderCacheRecord = {
	Fingerprint: string,
	OwnerUserId: number?,
}

type ServiceImpl = Service & {
	_template: BasePart,
	_shelves: { [string]: ShelfRecord },
	_shelfCount: number,
	_renderCache: { [string]: RenderCacheRecord },
	_rebuildCounts: { [string]: number },
}

type FeaturedItem = {
	ItemId: string,
	CatalogIndex: number,
	MasteryCount: number,
	MasteryTierPriority: number,
}

type ExpectedPresentation = {
	Featured: { FeaturedItem },
	RankLabel: string,
	CollectionLabel: string,
	Fingerprint: string,
}

local MAX_FEATURED_ITEMS = 6
local MAX_RECENT_ITEMS = 3
local MASTERY_TIER_PRIORITY: { [string]: number } = table.freeze({
	Locked = 0,
	Discovered = 1,
	Bronze = 2,
	Silver = 3,
	Gold = 4,
})

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
		StationModel = stationModel,
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
	record.CollectionCount.Text = string.format("0 / %d DISCOVERED", CollectionDefinitions.TotalCount)
	record.Model:SetAttribute("FeaturedItemCount", 0)
	record.Model:SetAttribute("ProfileRendered", false)
end

local function ownerUserId(record: ShelfRecord): number?
	local candidate = record.StationModel:GetAttribute("OwnerUserId")
	return if type(candidate) == "number" then candidate else nil
end

local function validCount(value: number?): number
	if type(value) ~= "number" or value ~= value or value < 0 or value % 1 ~= 0 then
		return 0
	end
	return value
end

local function masteryTierPriority(count: number): number
	local tierName = MasteryDefinitions.GetMasteryTier(count, true)
	local priority = MASTERY_TIER_PRIORITY[tierName]
	if priority == nil then
		error(string.format("Unknown canonical mastery tier: %s", tierName), 2)
	end
	return priority
end

local function collectFeatured(profile: ProfileView): ({ FeaturedItem }, number)
	local collection = profile.Collection
	local catalog = CollectionDefinitions.OrderedItemIds :: { string }
	local discoveredCount = CollectionDefinitions.GetDiscoveredCount(collection.Discovered)

	local featured: { FeaturedItem } = {}
	local included: { [string]: boolean } = {}
	for recentIndex = #collection.RecentDiscoveries, 1, -1 do
		local itemId = collection.RecentDiscoveries[recentIndex]
		local index = CollectionDefinitions.GetCatalogIndex(itemId)
		if #featured >= MAX_RECENT_ITEMS then
			break
		end
		if index ~= nil and collection.Discovered[itemId] == true and not included[itemId] then
			local masteryCount = validCount(collection.MasteryCounts[itemId])
			table.insert(featured, {
				ItemId = itemId,
				CatalogIndex = index,
				MasteryCount = masteryCount,
				MasteryTierPriority = masteryTierPriority(masteryCount),
			})
			included[itemId] = true
		end
	end

	local remaining: { FeaturedItem } = {}
	for _, itemId in ipairs(catalog) do
		if collection.Discovered[itemId] == true and not included[itemId] then
			local index = CollectionDefinitions.GetCatalogIndex(itemId)
			if index == nil then
				error(string.format("Canonical collection item has no catalog index: %s", itemId), 2)
			end
			local masteryCount = validCount(collection.MasteryCounts[itemId])
			table.insert(remaining, {
				ItemId = itemId,
				CatalogIndex = index,
				MasteryCount = masteryCount,
				MasteryTierPriority = masteryTierPriority(masteryCount),
			})
		end
	end
	table.sort(remaining, function(left: FeaturedItem, right: FeaturedItem): boolean
		if left.MasteryTierPriority ~= right.MasteryTierPriority then
			return left.MasteryTierPriority > right.MasteryTierPriority
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

local function appendFingerprintPart(parts: { string }, value: string)
	-- Length prefixes make catalog IDs and labels safe even if they later contain separators.
	table.insert(parts, string.format("%d:%s", #value, value))
end

local function presentationFingerprint(
	profile: ProfileView,
	rankLabel: string,
	collectionLabel: string,
	featured: { FeaturedItem }
): string
	local parts: { string } = {}
	appendFingerprintPart(parts, "collection-shelf-v1")
	appendFingerprintPart(parts, "rank")
	appendFingerprintPart(parts, rankLabel)
	appendFingerprintPart(parts, "collection-label")
	appendFingerprintPart(parts, collectionLabel)
	appendFingerprintPart(parts, "catalog")
	appendFingerprintPart(parts, tostring(CollectionDefinitions.TotalCount))
	for _, itemId in ipairs(CollectionDefinitions.OrderedItemIds) do
		appendFingerprintPart(parts, itemId)
		appendFingerprintPart(parts, if profile.Collection.Discovered[itemId] == true then "1" else "0")
		appendFingerprintPart(parts, tostring(validCount(profile.Collection.MasteryCounts[itemId])))
	end
	appendFingerprintPart(parts, "recent")
	local recentItemIds: { string } = {}
	for _, itemId in ipairs(profile.Collection.RecentDiscoveries) do
		if CollectionDefinitions.IsValidItemId(itemId) and profile.Collection.Discovered[itemId] == true then
			table.insert(recentItemIds, itemId)
		end
	end
	appendFingerprintPart(parts, tostring(#recentItemIds))
	for _, itemId in ipairs(recentItemIds) do
		appendFingerprintPart(parts, itemId)
	end
	appendFingerprintPart(parts, "featured")
	appendFingerprintPart(parts, tostring(#featured))
	for _, item in ipairs(featured) do
		appendFingerprintPart(parts, item.ItemId)
		appendFingerprintPart(parts, tostring(item.MasteryCount))
		appendFingerprintPart(parts, tostring(item.MasteryTierPriority))
	end
	return table.concat(parts, "|")
end

local function expectedPresentation(profile: ProfileView): ExpectedPresentation
	local featured, discoveredCount = collectFeatured(profile)
	local rankLabel = string.upper(rankNameForXP(profile.PackingXP))
	local collectionLabel = string.format(
		"%d / %d DISCOVERED",
		discoveredCount,
		CollectionDefinitions.TotalCount
	)
	return {
		Featured = featured,
		RankLabel = rankLabel,
		CollectionLabel = collectionLabel,
		Fingerprint = presentationFingerprint(profile, rankLabel, collectionLabel, featured),
	}
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

local function renderedStructureMatches(
	record: ShelfRecord,
	expected: ExpectedPresentation,
	template: BasePart
): boolean
	if record.RankName.Text ~= expected.RankLabel
		or record.CollectionCount.Text ~= expected.CollectionLabel
		or record.Model:GetAttribute("ProfileRendered") ~= true
		or record.Model:GetAttribute("FeaturedItemCount") ~= #expected.Featured
	then
		return false
	end

	local runtimeChildren = record.Runtime:GetChildren()
	if #runtimeChildren ~= #expected.Featured then
		return false
	end
	for index, featuredItem in ipairs(expected.Featured) do
		local proxy = record.Runtime:FindFirstChild(string.format("Featured_%02d", index))
		local definition = DevelopmentItemDefinitions.Get(featuredItem.ItemId)
		if proxy == nil
			or not proxy:IsA("BasePart")
			or proxy.ClassName ~= template.ClassName
			or definition == nil
		then
			return false
		end
		local slot = record.Slots[index]
		local expectedSize = proxySizeForDefinition(definition)
		local expectedCFrame = slot.CFrame * CFrame.new(0, (slot.Size.Y + expectedSize.Y) * 0.5, 0)
		if proxy:GetAttribute("ItemId") ~= featuredItem.ItemId
			or proxy:GetAttribute("MasteryCount") ~= featuredItem.MasteryCount
			or proxy.Size ~= expectedSize
			or proxy.Color ~= definition.Color
			or proxy.Material ~= Enum.Material.SmoothPlastic
			or proxy.Transparency ~= 0
			or proxy.Reflectance ~= template.Reflectance
			or proxy.CastShadow ~= template.CastShadow
			or proxy.Massless ~= template.Massless
			or proxy.CFrame ~= expectedCFrame
			or not proxy.Anchored
			or proxy.CanCollide
			or proxy.CanTouch
			or proxy.CanQuery
		then
			return false
		end
	end
	return true
end

local function validateCanonicalCatalog()
	if #CollectionDefinitions.OrderedItemIds ~= CollectionDefinitions.TotalCount then
		error("Collection catalog total must match its ordered item IDs", 3)
	end
	local seen: { [string]: boolean } = {}
	for expectedIndex, itemId in ipairs(CollectionDefinitions.OrderedItemIds) do
		if seen[itemId] then
			error(string.format("Duplicate canonical collection item id: %s", itemId), 3)
		end
		if CollectionDefinitions.GetCatalogIndex(itemId) ~= expectedIndex
			or DevelopmentItemDefinitions.Get(itemId) == nil
		then
			error(string.format("Invalid canonical collection item at index %d: %s", expectedIndex, itemId), 3)
		end
		seen[itemId] = true
	end
end

function CollectionShelfService.Create(stationsRoot: Instance, template: BasePart): ServiceImpl
	validateTemplate(template)
	validateCanonicalCatalog()
	local shelves: { [string]: ShelfRecord } = {}
	local rebuildCounts: { [string]: number } = {}
	local ordered = StationDefinitions.Ordered :: { any }
	for _, definition in ipairs(ordered) do
		local station = requireDirect(stationsRoot, definition.ModelName, "Model") :: Model
		local record = resolveShelf(station, definition.Id)
		if #record.Runtime:GetChildren() ~= 0 then
			error(string.format("%s.Runtime must be empty before server startup", record.Model:GetFullName()), 2)
		end
		shelves[definition.Id] = record
		rebuildCounts[definition.Id] = 0
		clearRecord(record)
	end
	if #ordered ~= 8 then
		error("CollectionShelfService requires exactly eight station definitions", 2)
	end
	return setmetatable({
		_template = template,
		_shelves = shelves,
		_shelfCount = #ordered,
		_renderCache = {},
		_rebuildCounts = rebuildCounts,
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
	local expected = expectedPresentation(profile)
	for _, featuredItem in ipairs(expected.Featured) do
		if DevelopmentItemDefinitions.Get(featuredItem.ItemId) == nil then
			return false, "UNKNOWN_ITEM"
		end
	end
	local cached = self._renderCache[stationId]
	local currentOwnerUserId = ownerUserId(record)
	if cached ~= nil
		and cached.Fingerprint == expected.Fingerprint
		and cached.OwnerUserId == currentOwnerUserId
		and renderedStructureMatches(record, expected, self._template)
	then
		return true, "UNCHANGED"
	end

	-- Cache ownership is scoped to the station's assignment lifecycle. Clear invalidates it,
	-- so a visually identical next owner still receives fresh proxy instances.
	self._renderCache[stationId] = nil
	clearRecord(record)
	record.RankName.Text = expected.RankLabel
	record.CollectionCount.Text = expected.CollectionLabel
	for index, featuredItem in ipairs(expected.Featured) do
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
	record.Model:SetAttribute("FeaturedItemCount", #expected.Featured)
	record.Model:SetAttribute("ProfileRendered", true)
	self._renderCache[stationId] = {
		Fingerprint = expected.Fingerprint,
		OwnerUserId = currentOwnerUserId,
	}
	self._rebuildCounts[stationId] = (self._rebuildCounts[stationId] or 0) + 1
	return true, "RENDERED"
end

function CollectionShelfService.Clear(self: ServiceImpl, stationId: string): boolean
	local record = self._shelves[stationId]
	if record == nil then
		return false
	end
	self._renderCache[stationId] = nil
	clearRecord(record)
	return true
end

function CollectionShelfService.ClearAll(self: ServiceImpl)
	for stationId, record in pairs(self._shelves) do
		self._renderCache[stationId] = nil
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

function CollectionShelfService.GetRebuildCount(self: ServiceImpl, stationId: string): number
	return self._rebuildCounts[stationId] or 0
end

function CollectionShelfService.GetRenderFingerprint(self: ServiceImpl, stationId: string): string?
	local cached = self._renderCache[stationId]
	return if cached ~= nil then cached.Fingerprint else nil
end

return table.freeze(CollectionShelfService)
