--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local IntegerValidation = require(Root.Shared.Grid.IntegerValidation)
local PlacementSolver = require(Root.Shared.Grid.PlacementSolver)
local ShapeRotation = require(Root.Shared.Grid.ShapeRotation)
local GridTypes = require(Root.Shared.Grid.GridTypes)
local NetworkTypes = require(Root.Shared.Net.NetworkTypes)
local RoundTypes = require(Root.Shared.Round.RoundTypes)

type Placement = GridTypes.Placement
type PlacementResponse = NetworkTypes.PlacementResponse
type RoundRecord = RoundTypes.RoundRecord

export type PlacementResult = {
	Accepted: boolean,
	Reason: string,
	ClientSequence: number,
	Placement: Placement?,
}

local PlacementService = {}

function PlacementService.GetClientSequence(payload: unknown): number
	if type(payload) ~= "table" then
		return -1
	end
	local request = payload :: { [string]: unknown }
	local value = request.ClientSequence
	return if IntegerValidation.IsFiniteInteger(value) then value :: number else -1
end

function PlacementService.CreateResponse(
	round: RoundRecord?,
	accepted: boolean,
	reason: string,
	clientSequence: number
): PlacementResponse
	return {
		Accepted = accepted,
		Reason = reason,
		ClientSequence = clientSequence,
		RoundId = if round then round.RoundId else 0,
		StateVersion = if round then round.StateVersion else 0,
	}
end

local function reject(reason: string, sequence: number): PlacementResult
	return { Accepted = false, Reason = reason, ClientSequence = sequence, Placement = nil }
end

function PlacementService.ValidateAndApply(
	round: RoundRecord,
	senderUserId: number,
	assignedStationId: string?,
	payload: unknown,
	now: number
): PlacementResult
	if type(payload) ~= "table" then
		return reject("MALFORMED_REQUEST", -1)
	end
	local request = payload :: { [string]: unknown }
	local sequence = PlacementService.GetClientSequence(payload)

	if senderUserId ~= round.PlayerUserId or assignedStationId ~= round.StationId then
		return reject("WRONG_PLAYER_OR_STATION", sequence)
	end
	if request.RoundId ~= round.RoundId then
		return reject("ROUND_MISMATCH", sequence)
	end
	if request.StateVersion ~= round.StateVersion then
		return reject("STATE_VERSION_MISMATCH", sequence)
	end
	if round.State ~= "AwaitingPlacement" then
		return reject("WRONG_STATE", sequence)
	end
	if request.ItemId ~= round.CurrentItemId then
		return reject("ITEM_MISMATCH", sequence)
	end
	if sequence < 0 or sequence <= round.LastClientSequences.Place then
		return reject("DUPLICATE_SEQUENCE", sequence)
	end

	if round.PlacementDeadline == nil or now > round.PlacementDeadline then
		return reject("PLACEMENT_EXPIRED", sequence)
	end

	local quarterTurnsValue = request.QuarterTurns
	local xValue = request.OriginX
	local zValue = request.OriginZ
	if not IntegerValidation.IsFiniteInteger(quarterTurnsValue) then
		return reject("INVALID_ROTATION", sequence)
	end
	if not IntegerValidation.IsFiniteInteger(xValue) or not IntegerValidation.IsFiniteInteger(zValue) then
		return reject("INVALID_ORIGIN", sequence)
	end
	local quarterTurns = quarterTurnsValue :: number
	local originX = xValue :: number
	local originZ = zValue :: number

	local itemId = round.CurrentItemId
	local definition = if itemId then DevelopmentItemDefinitions.Get(itemId) else nil
	if not definition then
		return reject("UNKNOWN_ITEM", sequence)
	end

	local selectedRotation: GridTypes.ShapeRotation? = nil
	local selectedRotationIndex = 0
	for rotationIndex, rotation in ipairs(ShapeRotation.GetUniqueRotations(definition.Shape)) do
		if rotation.QuarterTurns == quarterTurns then
			selectedRotation = rotation
			selectedRotationIndex = rotationIndex
			break
		end
	end
	if not selectedRotation then
		return reject("INVALID_ROTATION", sequence)
	end

	local placement = PlacementSolver.GetAutoDropPlacement(
		round.Grid,
		selectedRotation,
		originX,
		originZ,
		definition.ShapeId,
		selectedRotationIndex
	)
	if not placement then
		return reject("NO_LEGAL_PLACEMENT", sequence)
	end
	round.LastClientSequences.Place = sequence
	if not round.Grid:ApplyPlacement(placement) then
		return reject("PLACEMENT_CONFLICT", sequence)
	end

	return {
		Accepted = true,
		Reason = "ACCEPTED",
		ClientSequence = sequence,
		Placement = placement,
	}
end

return table.freeze(PlacementService)
