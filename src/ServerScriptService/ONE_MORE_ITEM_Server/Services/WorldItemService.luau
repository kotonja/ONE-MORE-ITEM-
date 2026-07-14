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
	ClearStation: (self: Service, stationId: string) -> (),
	GetRuntimeModelCount: (self: Service, player: Player) -> number,
	GetStationRuntimeModelCount: (self: Service, stationId: string) -> number,
}

type WorldItemServiceImpl = Service & {
	_template: BasePart,
	_stationService: StationServiceContract,
	_modelsByStation: { [string]: { Model } },
	_stationByPlayer: { [Player]: string },
}

local WorldItemService = {}
WorldItemService.__index = WorldItemService

local function validateTemplate(template: BasePart)
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			error("CellBlockTemplate may not contain scripts", 3)
		end
	end
end

function WorldItemService.Create(template: BasePart, stationService: StationServiceContract): WorldItemServiceImpl
	validateTemplate(template)
	return setmetatable({
		_template = template,
		_stationService = stationService,
		_modelsByStation = {},
		_stationByPlayer = {},
	}, WorldItemService) :: WorldItemServiceImpl
end

function WorldItemService.SpawnAcceptedPlacement(
	self: WorldItemServiceImpl,
	player: Player,
	itemId: string,
	placement: Placement
): Model?
	local stationId = self._stationService:GetStationId(player)
	local station = if stationId ~= nil then self._stationService:GetStationById(stationId) else nil
	local definition = DevelopmentItemDefinitions.Get(itemId)
	if stationId == nil or station == nil or definition == nil then
		return nil
	end

	local crate = station.Model:FindFirstChild("Crate")
	local gridOrigin = if crate ~= nil then crate:FindFirstChild("GridOrigin") else nil
	if gridOrigin == nil or not gridOrigin:IsA("BasePart") then
		error(string.format("Validated station %s lost its GridOrigin", stationId), 2)
	end

	local models = self._modelsByStation[stationId]
	if models == nil then
		models = {}
		self._modelsByStation[stationId] = models
	end
	self._stationByPlayer[player] = stationId

	local model = DevelopmentItemRenderer.RenderCells(
		self._template,
		station.PlacedItems,
		string.format("Placed_%s_%02d_%s", stationId, #models + 1, itemId),
		placement.Cells,
		gridOrigin.CFrame,
		RoundConfig.GRID_CELL_SIZE,
		definition.Color,
		0
	)
	table.insert(models, model)
	return model
end

function WorldItemService.ClearStation(self: WorldItemServiceImpl, stationId: string)
	local models = self._modelsByStation[stationId]
	if models ~= nil then
		for _, model in ipairs(models) do
			if model.Parent ~= nil then
				model:Destroy()
			end
		end
	end
	self._modelsByStation[stationId] = nil

	local station = self._stationService:GetStationById(stationId)
	if station ~= nil then
		DevelopmentItemRenderer.Clear(station.PlacedItems)
	end

	for player, trackedStationId in pairs(self._stationByPlayer) do
		if trackedStationId == stationId then
			self._stationByPlayer[player] = nil
		end
	end
end

function WorldItemService.ClearPlayer(self: WorldItemServiceImpl, player: Player)
	local currentStationId = self._stationService:GetStationId(player)
	local trackedStationId = self._stationByPlayer[player]
	if trackedStationId ~= nil then
		self:ClearStation(trackedStationId)
	end
	if currentStationId ~= nil and currentStationId ~= trackedStationId then
		self:ClearStation(currentStationId)
	end
	self._stationByPlayer[player] = nil
end

function WorldItemService.GetStationRuntimeModelCount(self: WorldItemServiceImpl, stationId: string): number
	local models = self._modelsByStation[stationId]
	if models == nil then
		return 0
	end
	local count = 0
	for _, model in ipairs(models) do
		if model.Parent ~= nil then
			count += 1
		end
	end
	return count
end

function WorldItemService.GetRuntimeModelCount(self: WorldItemServiceImpl, player: Player): number
	local stationId = self._stationService:GetStationId(player) or self._stationByPlayer[player]
	return if stationId ~= nil then self:GetStationRuntimeModelCount(stationId) else 0
end

return table.freeze(WorldItemService)
