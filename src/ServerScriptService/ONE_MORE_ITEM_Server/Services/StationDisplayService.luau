--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DisplayNameSanitizer = require(Root.Shared.World.DisplayNameSanitizer)
local RoundServiceModule = require(script.Parent.RoundService)
local StationServiceModule = require(script.Parent.StationService)

type RoundStateEvent = RoundServiceModule.RoundStateEvent
type StationRecord = StationServiceModule.StationRecord
type StationServiceContract = StationServiceModule.Service

type DisplayRecord = {
	Station: StationRecord,
	PlayerName: TextLabel,
	RoundStatus: TextLabel,
	RiskValue: TextLabel,
	StationNumber: TextLabel,
	IndicatorPart: BasePart,
	Light: PointLight,
	OffColor: Color3,
}

export type Service = {
	SetOwner: (self: Service, player: Player, stationId: string) -> (),
	ApplyRoundState: (self: Service, event: RoundStateEvent) -> (),
	ReleaseStation: (self: Service, stationId: string) -> (),
	ResetAll: (self: Service) -> (),
}

type StationDisplayServiceImpl = Service & {
	_displays: { [string]: DisplayRecord },
}

local AMBER = Color3.fromRGB(255, 178, 26)
local RED = Color3.fromRGB(255, 75, 62)
local GOLD = Color3.fromRGB(255, 215, 72)

local StationDisplayService = {}
StationDisplayService.__index = StationDisplayService

local function requireDescendant(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name, true)
	if child == nil or not child:IsA(className) then
		error(string.format("Station display requires %s %s", className, name), 3)
	end
	return child
end

local function cacheDisplay(station: StationRecord): DisplayRecord
	local ownerDisplay = station.Model:FindFirstChild("OwnerDisplay")
	local riskIndicator = station.Model:FindFirstChild("RiskIndicator")
	if ownerDisplay == nil or riskIndicator == nil then
		error(string.format("Validated station %s lost display instances", station.Id), 3)
	end
	local indicatorPart = requireDescendant(riskIndicator, "IndicatorPart", "BasePart") :: BasePart
	return {
		Station = station,
		PlayerName = requireDescendant(ownerDisplay, "PlayerName", "TextLabel") :: TextLabel,
		RoundStatus = requireDescendant(ownerDisplay, "RoundStatus", "TextLabel") :: TextLabel,
		RiskValue = requireDescendant(ownerDisplay, "RiskValue", "TextLabel") :: TextLabel,
		StationNumber = requireDescendant(ownerDisplay, "StationNumber", "TextLabel") :: TextLabel,
		IndicatorPart = indicatorPart,
		Light = requireDescendant(indicatorPart, "Light", "PointLight") :: PointLight,
		OffColor = indicatorPart.Color,
	}
end

local function setRisk(display: DisplayRecord, itemCount: number)
	local color: Color3? = nil
	if itemCount >= 10 then
		color = GOLD
	elseif itemCount >= 8 then
		color = RED
	elseif itemCount >= 6 then
		color = AMBER
	end

	if color == nil then
		display.IndicatorPart.Color = display.OffColor
		display.Light.Enabled = false
		display.Light.Brightness = 0
	else
		display.IndicatorPart.Color = color
		display.Light.Color = color
		display.Light.Enabled = true
		display.Light.Brightness = 1.5
	end
end

local function resetDisplay(display: DisplayRecord)
	display.PlayerName.Text = string.format("STATION %02d", display.Station.Index)
	display.RoundStatus.Text = "AVAILABLE"
	display.RiskValue.Text = ""
	display.StationNumber.Text = string.format("%02d", display.Station.Index)
	display.Station.Model:SetAttribute("OwnerUserId", nil)
	display.Station.Model:SetAttribute("RoundDisplayState", "AVAILABLE")
	display.Station.Model:SetAttribute("DisplayedItemCount", 0)
	display.Station.Model:SetAttribute("DisplayedRiskValue", 0)
	setRisk(display, 0)
end

function StationDisplayService.Create(stationService: StationServiceContract): StationDisplayServiceImpl
	local displays: { [string]: DisplayRecord } = {}
	for _, station in ipairs(stationService:GetStations()) do
		if displays[station.Id] ~= nil then
			error(string.format("Duplicate cached station display %s", station.Id), 2)
		end
		displays[station.Id] = cacheDisplay(station)
	end
	local self: StationDisplayServiceImpl = setmetatable({
		_displays = displays,
	}, StationDisplayService) :: StationDisplayServiceImpl
	self:ResetAll()
	return self
end

function StationDisplayService.SetOwner(self: StationDisplayServiceImpl, player: Player, stationId: string)
	local display = self._displays[stationId]
	if display == nil then
		error(string.format("Unknown station display %s", stationId), 2)
	end
	display.PlayerName.Text = DisplayNameSanitizer.Sanitize(player.DisplayName)
	display.RoundStatus.Text = "PREPARING"
	display.RiskValue.Text = ""
	display.Station.Model:SetAttribute("OwnerUserId", player.UserId)
	display.Station.Model:SetAttribute("RoundDisplayState", "PREPARING")
	setRisk(display, 0)
end

local function isFailureEvent(event: RoundStateEvent): boolean
	return event.State == "Failing"
		or event.ResultLostValue > 0
		or event.ResultReason == "PLACEMENT_TIMEOUT"
end

local function statusFor(event: RoundStateEvent): string
	if event.ItemCount >= 10 and (event.State == "Decision" or event.State == "Shipping") then
		return "IMPOSSIBLE SHIPMENT"
	end
	if event.State == "Preparing" or event.State == "PresentingItem" then
		return "PREPARING"
	elseif event.State == "AwaitingPlacement" then
		return string.format("PACKING %d ITEMS", event.ItemCount)
	elseif event.State == "Decision" then
		if event.ItemCount >= 8 then
			return string.format("HIGH RISK - %d ITEMS", event.ItemCount)
		elseif event.ItemCount >= 6 then
			return string.format("RISKING %d ITEMS", event.ItemCount)
		end
		return "SHIP OR ONE MORE"
	elseif event.State == "Shipping" then
		return "SHIPPING"
	elseif event.State == "Failing" then
		return "TOO MUCH"
	elseif event.State == "Results" then
		return if isFailureEvent(event) then "ROUND FAILED" else "SHIPMENT COMPLETE"
	end
	return string.upper(event.State)
end

function StationDisplayService.ApplyRoundState(self: StationDisplayServiceImpl, event: RoundStateEvent)
	local display = self._displays[event.StationId]
	if display == nil then
		return
	end
	local status = statusFor(event)
	local displayedValue = if isFailureEvent(event)
		then event.ResultLostValue
		else math.max(event.ShipmentValue, event.ResultValue)
	display.RoundStatus.Text = status
	display.RiskValue.Text = if event.ItemCount >= 6
		then string.format("%d ITEMS / %d TAPE", event.ItemCount, displayedValue)
		else ""
	display.Station.Model:SetAttribute("RoundDisplayState", status)
	display.Station.Model:SetAttribute("DisplayedItemCount", event.ItemCount)
	display.Station.Model:SetAttribute("DisplayedRiskValue", displayedValue)
	setRisk(display, event.ItemCount)
end

function StationDisplayService.ReleaseStation(self: StationDisplayServiceImpl, stationId: string)
	local display = self._displays[stationId]
	if display ~= nil then
		resetDisplay(display)
	end
end

function StationDisplayService.ResetAll(self: StationDisplayServiceImpl)
	for _, display in pairs(self._displays) do
		resetDisplay(display)
	end
end

return table.freeze(StationDisplayService)
