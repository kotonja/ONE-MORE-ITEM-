--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local RoundMath = require(Root.Shared.Round.RoundMath)
local RoundTypes = require(Root.Shared.Round.RoundTypes)
local DisplayNameSanitizer = require(Root.Shared.World.DisplayNameSanitizer)
local ShipmentTypes = require(Root.Shared.World.ShipmentTypes)
local ProfileConfig = require(script.Parent.Profile.ProfileConfig)

type RoundRecord = RoundTypes.RoundRecord
type PlacedItemPresentation = RoundTypes.PlacedItemPresentation
export type ShipmentRecord = ShipmentTypes.ShipmentRecord

type Clock = () -> number

export type Service = {
	Capture: (self: Service, player: Player, round: RoundRecord) -> (ShipmentRecord?, string),
	GetSeenCount: (self: Service) -> number,
}

type ShipmentRecordServiceImpl = Service & {
	_clock: Clock,
	_seenIds: { [string]: boolean },
	_seenCount: number,
}

local ShipmentRecordService = {}
ShipmentRecordService.__index = ShipmentRecordService

local function defaultClock(): number
	return workspace:GetServerTimeNow()
end

local function copyPlacedItems(source: { PlacedItemPresentation }): { PlacedItemPresentation }
	local copied: { PlacedItemPresentation } = table.create(#source)
	for index, item in ipairs(source) do
		copied[index] = table.freeze({
			ItemId = item.ItemId,
			ShapeId = item.ShapeId,
			QuarterTurns = item.QuarterTurns,
			OriginX = item.OriginX,
			OriginY = item.OriginY,
			OriginZ = item.OriginZ,
			ColorR = item.ColorR,
			ColorG = item.ColorG,
			ColorB = item.ColorB,
		}) :: PlacedItemPresentation
	end
	table.freeze(copied)
	return copied
end

function ShipmentRecordService.Create(clock: Clock?): ShipmentRecordServiceImpl
	return setmetatable({
		_clock = clock or defaultClock,
		_seenIds = {},
		_seenCount = 0,
	}, ShipmentRecordService) :: ShipmentRecordServiceImpl
end

function ShipmentRecordService.Capture(
	self: ShipmentRecordServiceImpl,
	player: Player,
	round: RoundRecord
): (ShipmentRecord?, string)
	if player.UserId ~= round.PlayerUserId then
		return nil, "PLAYER_MISMATCH"
	end
	if round.StationId == "" then
		return nil, "MISSING_STATION"
	end
	if round.ItemCount ~= #round.PlacedItems then
		return nil, "PLACED_ITEM_COUNT_MISMATCH"
	end

	local outcomeId = round.OutcomeId
	if type(outcomeId) ~= "string" or outcomeId == "" or #outcomeId > ProfileConfig.MAXIMUM_OUTCOME_ID_LENGTH then
		return nil, "INVALID_OUTCOME_ID"
	end
	if self._seenIds[outcomeId] then
		return nil, "DUPLICATE_SHIPMENT"
	end

	local record = table.freeze({
		OutcomeId = outcomeId,
		-- ShipmentId remains as a compatibility alias for Phase 04 cosmetic consumers.
		ShipmentId = outcomeId,
		PlayerUserId = round.PlayerUserId,
		PlayerDisplayName = DisplayNameSanitizer.Sanitize(player.DisplayName),
		StationId = round.StationId,
		RoundId = round.RoundId,
		ItemCount = round.ItemCount,
		BaseValueSum = round.BaseValueSum,
		ShipmentValue = round.ShipmentValue,
		Multiplier = RoundMath.GetMultiplier(round.ItemCount),
		PlacedItems = copyPlacedItems(round.PlacedItems),
		CreatedAt = self._clock(),
		PerfectShipment = round.ItemCount == RoundConfig.MAXIMUM_ITEMS,
	}) :: ShipmentRecord

	self._seenIds[outcomeId] = true
	self._seenCount += 1
	return record, "CAPTURED"
end

function ShipmentRecordService.GetSeenCount(self: ShipmentRecordServiceImpl): number
	return self._seenCount
end

return table.freeze(ShipmentRecordService)
