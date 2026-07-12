--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local DevelopmentItemRenderer = require(Root.Shared.World.DevelopmentItemRenderer)
local GridTypes = require(Root.Shared.Grid.GridTypes)
local StationServiceModule = require(script.Parent.StationService)

type Placement = GridTypes.Placement
type StationServiceContract = StationServiceModule.Service

export type Service = {
	SpawnAcceptedPlacement: (self: Service, player: Player, itemId: string, placement: Placement) -> Model?,
	ClearPlayer: (self: Service, player: Player) -> (),
	GetRuntimeModelCount: (self: Service, player: Player) -> number,
}

type WorldItemServiceImpl = Service & {
	_template: BasePart,
	_stationService: StationServiceContract,
	_modelsByPlayer: { [Player]: { Model } },
}

local WorldItemService = {}
WorldItemService.__index = WorldItemService

function WorldItemService.Create(template: BasePart, stationService: StationServiceContract): WorldItemServiceImpl
	return setmetatable({
		_template = template,
		_stationService = stationService,
		_modelsByPlayer = {},
	}, WorldItemService) :: WorldItemServiceImpl
end

function WorldItemService.SpawnAcceptedPlacement(
	self: WorldItemServiceImpl,
	player: Player,
	itemId: string,
	placement: Placement
): Model?
	local station = self._stationService:GetStationModel(player)
	local definition = DevelopmentItemDefinitions.Get(itemId)
	if not station or not definition then
		return nil
	end
	local placedItems = station:FindFirstChild("PlacedItems")
	local crate = station:FindFirstChild("Crate")
	local gridOrigin = if crate then crate:FindFirstChild("GridOrigin") else nil
	if not placedItems or not gridOrigin or not gridOrigin:IsA("BasePart") then
		return nil
	end

	local models = self._modelsByPlayer[player]
	if not models then
		models = {}
		self._modelsByPlayer[player] = models
	end
	local model = DevelopmentItemRenderer.RenderCells(
		self._template,
		placedItems,
		string.format("Placed_%02d_%s", #models + 1, itemId),
		placement.Cells,
		gridOrigin.CFrame,
		RoundConfig.GRID_CELL_SIZE,
		definition.Color,
		0
	)
	table.insert(models, model)
	return model
end

function WorldItemService.ClearPlayer(self: WorldItemServiceImpl, player: Player)
	local models = self._modelsByPlayer[player]
	if models then
		for _, model in ipairs(models) do
			model:Destroy()
		end
	end
	self._modelsByPlayer[player] = nil

	local station = self._stationService:GetStationModel(player)
	local placedItems = if station then station:FindFirstChild("PlacedItems") else nil
	if placedItems then
		DevelopmentItemRenderer.Clear(placedItems)
	end
end

function WorldItemService.GetRuntimeModelCount(self: WorldItemServiceImpl, player: Player): number
	local models = self._modelsByPlayer[player]
	return if models then #models else 0
end

return table.freeze(WorldItemService)
