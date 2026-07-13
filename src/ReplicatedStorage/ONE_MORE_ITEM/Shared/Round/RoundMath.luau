--!strict

local IntegerValidation = require(script.Parent.Parent.Grid.IntegerValidation)
local RoundConfig = require(script.Parent.Parent.Config.RoundConfig)

local RoundMath = {}

local function validateNonNegativeInteger(value: number, name: string)
	if not IntegerValidation.IsFiniteInteger(value) or value < 0 then
		error(name .. " must be a non-negative finite integer", 3)
	end
end

function RoundMath.GetMultiplier(itemCount: number): number
	validateNonNegativeInteger(itemCount, "itemCount")
	if itemCount > RoundConfig.MAXIMUM_ITEMS then
		error("itemCount exceeds the Phase 02 maximum", 2)
	end
	if itemCount == 0 then
		return 1
	end
	local multiplier = RoundConfig.MULTIPLIERS[itemCount]
	if multiplier == nil then
		error("Missing configured multiplier", 2)
	end
	return multiplier
end

function RoundMath.CalculateShipmentValue(baseValueSum: number, itemCount: number): number
	validateNonNegativeInteger(baseValueSum, "baseValueSum")
	local multiplierHundredths = math.floor((RoundMath.GetMultiplier(itemCount) * 100) + 0.5)
	return math.floor((baseValueSum * multiplierHundredths) / 100)
end

function RoundMath.CalculatePossibleShipmentValue(
	currentBaseValueSum: number,
	currentItemCount: number,
	nextItemBaseValue: number
): number
	validateNonNegativeInteger(nextItemBaseValue, "nextItemBaseValue")
	if currentItemCount >= RoundConfig.MAXIMUM_ITEMS then
		error("Cannot preview beyond the Phase 02 maximum item count", 2)
	end
	return RoundMath.CalculateShipmentValue(currentBaseValueSum + nextItemBaseValue, currentItemCount + 1)
end

function RoundMath.BankShipment(
	sessionBank: number,
	shipmentValue: number,
	alreadyBanked: boolean
): (number, boolean)
	validateNonNegativeInteger(sessionBank, "sessionBank")
	validateNonNegativeInteger(shipmentValue, "shipmentValue")
	if alreadyBanked then
		return sessionBank, true
	end
	return sessionBank + shipmentValue, true
end

function RoundMath.BankAfterFailure(sessionBank: number): number
	validateNonNegativeInteger(sessionBank, "sessionBank")
	return sessionBank
end

return table.freeze(RoundMath)
