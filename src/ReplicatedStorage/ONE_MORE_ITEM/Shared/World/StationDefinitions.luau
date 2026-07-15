--!strict

export type StationId =
	"station_01"
	| "station_02"
	| "station_03"
	| "station_04"
	| "station_05"
	| "station_06"
	| "station_07"
	| "station_08"

export type Definition = {
	Id: StationId,
	Index: number,
	ModelName: string,
}

local function definition(id: StationId, index: number, modelName: string): Definition
	return table.freeze({
		Id = id,
		Index = index,
		ModelName = modelName,
	}) :: Definition
end

local ordered: { Definition } = {
	definition("station_01", 1, "Station_01"),
	definition("station_02", 2, "Station_02"),
	definition("station_03", 3, "Station_03"),
	definition("station_04", 4, "Station_04"),
	definition("station_05", 5, "Station_05"),
	definition("station_06", 6, "Station_06"),
	definition("station_07", 7, "Station_07"),
	definition("station_08", 8, "Station_08"),
}
table.freeze(ordered)

local byId: { [string]: Definition } = {}
for _, station in ipairs(ordered) do
	byId[station.Id] = station
end
table.freeze(byId)

local StationDefinitions = {
	Ordered = ordered,
	Capacity = #ordered,
}

function StationDefinitions.Get(stationId: string?): Definition?
	if stationId == nil then
		return nil
	end
	return byId[stationId]
end

function StationDefinitions.IsValid(stationId: string?): boolean
	return StationDefinitions.Get(stationId) ~= nil
end

function StationDefinitions.Resolve(stationsRoot: Instance, stationId: string?): Model?
	local station = StationDefinitions.Get(stationId)
	if station == nil then
		return nil
	end

	local candidate = stationsRoot:FindFirstChild(station.ModelName)
	if candidate == nil or not candidate:IsA("Model") then
		return nil
	end
	if candidate:GetAttribute("StationId") ~= station.Id
		or candidate:GetAttribute("StationIndex") ~= station.Index
	then
		return nil
	end
	return candidate
end

return table.freeze(StationDefinitions)
