--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local ShipmentTypes = require(Root.Shared.World.ShipmentTypes)
local RoundServiceModule = require(script.Parent.RoundService)

type ShipmentRecord = ShipmentTypes.ShipmentRecord
type HighRiskMilestoneEvent = RoundServiceModule.HighRiskMilestoneEvent
type RoundFailureEvent = RoundServiceModule.RoundFailureEvent

export type Service = {
	AnnounceHighRisk: (self: Service, event: HighRiskMilestoneEvent) -> boolean,
	AnnounceShipment: (self: Service, record: ShipmentRecord, isServerBest: boolean) -> boolean,
	AnnounceFailure: (self: Service, event: RoundFailureEvent) -> boolean,
	Reset: (self: Service) -> (),
	Destroy: (self: Service) -> (),
}

type ArenaAnnouncementServiceImpl = Service & {
	_display: Instance,
	_headline: TextLabel,
	_detail: TextLabel,
	_epoch: number,
	_priority: number,
	_destroyed: boolean,
}

local ArenaAnnouncementService = {}
ArenaAnnouncementService.__index = ArenaAnnouncementService

local function requireLabel(parent: Instance, name: string): TextLabel
	local label = parent:FindFirstChild(name, true)
	if label == nil or not label:IsA("TextLabel") then
		error(string.format("ArenaAnnouncement requires TextLabel %s", name), 3)
	end
	return label
end

local function neutral(self: ArenaAnnouncementServiceImpl)
	self._headline.Text = "PACK. SHIP. RISK ONE MORE."
	self._detail.Text = ""
	self._priority = 0
	self._display:SetAttribute("AnnouncementPriority", 0)
end

local function publish(
	self: ArenaAnnouncementServiceImpl,
	priority: number,
	headline: string,
	detail: string,
	duration: number
): boolean
	if self._destroyed or priority < self._priority then
		return false
	end
	self._epoch += 1
	local epoch = self._epoch
	self._priority = priority
	self._headline.Text = headline
	self._detail.Text = detail
	self._display:SetAttribute("AnnouncementPriority", priority)
	self._display:SetAttribute("AnnouncementEpoch", epoch)
	task.delay(duration, function()
		if not self._destroyed and self._epoch == epoch then
			neutral(self)
		end
	end)
	return true
end

function ArenaAnnouncementService.Create(display: Instance): ArenaAnnouncementServiceImpl
	local self: ArenaAnnouncementServiceImpl = setmetatable({
		_display = display,
		_headline = requireLabel(display, "Headline"),
		_detail = requireLabel(display, "Detail"),
		_epoch = 0,
		_priority = 0,
		_destroyed = false,
	}, ArenaAnnouncementService) :: ArenaAnnouncementServiceImpl
	neutral(self)
	return self
end

function ArenaAnnouncementService.AnnounceHighRisk(
	self: ArenaAnnouncementServiceImpl,
	event: HighRiskMilestoneEvent
): boolean
	local priority = if event.ItemCount >= 10 then 3 else 2
	return publish(
		self,
		priority,
		string.format("%s IS RISKING %d ITEMS", string.upper(event.PlayerDisplayName), event.ItemCount),
		string.format("%d TAPE ON THE LINE", event.ShipmentValue),
		if event.ItemCount >= 10 then 3.0 else 2.2
	)
end

function ArenaAnnouncementService.AnnounceShipment(
	self: ArenaAnnouncementServiceImpl,
	record: ShipmentRecord,
	isServerBest: boolean
): boolean
	local headline = if isServerBest
		then "NEW SERVER BEST"
		else string.format("%s SHIPPED %d ITEMS", string.upper(record.PlayerDisplayName), record.ItemCount)
	local detail = if isServerBest
		then string.format("%s - %d TAPE", string.upper(record.PlayerDisplayName), record.ShipmentValue)
		else string.format("%d TAPE", record.ShipmentValue)
	return publish(self, if isServerBest or record.PerfectShipment then 3 else 1, headline, detail, if isServerBest or record.PerfectShipment then 3.0 else 2.2)
end

function ArenaAnnouncementService.AnnounceFailure(
	self: ArenaAnnouncementServiceImpl,
	event: RoundFailureEvent
): boolean
	if event.ItemCount < 6 then
		return false
	end
	return publish(
		self,
		2,
		string.format("%s PUSHED TOO FAR", string.upper(event.PlayerDisplayName)),
		string.format("%d ITEMS - %d TAPE LOST", event.ItemCount, event.LostValue),
		2.2
	)
end

function ArenaAnnouncementService.Reset(self: ArenaAnnouncementServiceImpl)
	self._epoch += 1
	neutral(self)
end

function ArenaAnnouncementService.Destroy(self: ArenaAnnouncementServiceImpl)
	if self._destroyed then
		return
	end
	self:Reset()
	self._destroyed = true
end

return table.freeze(ArenaAnnouncementService)
