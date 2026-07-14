--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local ShipmentTypes = require(Root.Shared.World.ShipmentTypes)

type ShipmentRecord = ShipmentTypes.ShipmentRecord

export type Service = {
	Consider: (self: Service, record: ShipmentRecord) -> (boolean, boolean),
	GetBest: (self: Service) -> ShipmentRecord?,
	GetSeenCount: (self: Service) -> number,
	Reset: (self: Service) -> (),
}

type ServerBestServiceImpl = Service & {
	_display: Instance,
	_playerName: TextLabel,
	_shipmentValue: TextLabel,
	_itemCount: TextLabel,
	_seenIds: { [string]: boolean },
	_seenCount: number,
	_best: ShipmentRecord?,
}

local ServerBestService = {}
ServerBestService.__index = ServerBestService

local function requireLabel(parent: Instance, name: string): TextLabel
	local label = parent:FindFirstChild(name, true)
	if label == nil or not label:IsA("TextLabel") then
		error(string.format("ServerBest display requires TextLabel %s", name), 3)
	end
	return label
end

local function renderFallback(self: ServerBestServiceImpl)
	self._playerName.Text = "NO SHIPMENT YET"
	self._shipmentValue.Text = "0 TAPE"
	self._itemCount.Text = "SERVER BEST"
	self._display:SetAttribute("BestShipmentId", nil)
	self._display:SetAttribute("BestShipmentValue", 0)
	self._display:SetAttribute("BestItemCount", 0)
	self._display:SetAttribute("SeenShipments", self._seenCount)
end

local function renderBest(self: ServerBestServiceImpl, record: ShipmentRecord)
	self._playerName.Text = record.PlayerDisplayName
	self._shipmentValue.Text = string.format("%d TAPE", record.ShipmentValue)
	self._itemCount.Text = string.format("%d ITEMS", record.ItemCount)
	self._display:SetAttribute("BestShipmentId", record.ShipmentId)
	self._display:SetAttribute("BestShipmentValue", record.ShipmentValue)
	self._display:SetAttribute("BestItemCount", record.ItemCount)
end

local function outranks(candidate: ShipmentRecord, current: ShipmentRecord): boolean
	if candidate.ShipmentValue ~= current.ShipmentValue then
		return candidate.ShipmentValue > current.ShipmentValue
	end
	if candidate.ItemCount ~= current.ItemCount then
		return candidate.ItemCount > current.ItemCount
	end
	return false
end

function ServerBestService.Create(display: Instance): ServerBestServiceImpl
	local self: ServerBestServiceImpl = setmetatable({
		_display = display,
		_playerName = requireLabel(display, "PlayerName"),
		_shipmentValue = requireLabel(display, "ShipmentValue"),
		_itemCount = requireLabel(display, "ItemCount"),
		_seenIds = {},
		_seenCount = 0,
		_best = nil,
	}, ServerBestService) :: ServerBestServiceImpl
	renderFallback(self)
	return self
end

function ServerBestService.Consider(
	self: ServerBestServiceImpl,
	record: ShipmentRecord
): (boolean, boolean)
	if self._seenIds[record.ShipmentId] then
		return false, false
	end
	self._seenIds[record.ShipmentId] = true
	self._seenCount += 1
	self._display:SetAttribute("SeenShipments", self._seenCount)

	local current = self._best
	if current == nil or outranks(record, current) then
		self._best = record
		renderBest(self, record)
		return true, true
	end
	return true, false
end

function ServerBestService.GetBest(self: ServerBestServiceImpl): ShipmentRecord?
	return self._best
end

function ServerBestService.GetSeenCount(self: ServerBestServiceImpl): number
	return self._seenCount
end

function ServerBestService.Reset(self: ServerBestServiceImpl)
	table.clear(self._seenIds)
	self._seenCount = 0
	self._best = nil
	self._display:SetAttribute("SeenShipments", 0)
	renderFallback(self)
end

return table.freeze(ServerBestService)
