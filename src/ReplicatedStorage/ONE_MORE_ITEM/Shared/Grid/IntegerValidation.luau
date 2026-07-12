--!strict

local IntegerValidation = {}

function IntegerValidation.IsFiniteInteger(value: unknown): boolean
	if type(value) ~= "number" then
		return false
	end

	return value == value
		and value > -math.huge
		and value < math.huge
		and value == math.floor(value)
end

return table.freeze(IntegerValidation)
