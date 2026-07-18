--!strict

export type MissionGoalType =
	"AcceptedPlacement"
	| "SuccessfulShipment"
	| "OneMoreAccepted"
	| "DiscoveredCount"
	| "ShipmentItemCount"

export type MissionReward = {
	Tape: number,
	PackingXP: number,
}

export type MissionDefinition = {
	Id: string,
	Index: number,
	Name: string,
	Description: string,
	GoalType: MissionGoalType,
	Goal: number,
	Reward: MissionReward,
}

local function mission(
	index: number,
	id: string,
	name: string,
	description: string,
	goalType: MissionGoalType,
	goal: number,
	tape: number,
	packingXP: number
): MissionDefinition
	return table.freeze({
		Id = id,
		Index = index,
		Name = name,
		Description = description,
		GoalType = goalType,
		Goal = goal,
		Reward = table.freeze({ Tape = tape, PackingXP = packingXP }),
	}) :: MissionDefinition
end

local ordered: { MissionDefinition } = {
	mission(1, "first_fit", "FIRST FIT", "Place one item.", "AcceptedPlacement", 1, 10, 10),
	mission(2, "first_shipment", "SAFE SHIPMENT", "Ship one box successfully.", "SuccessfulShipment", 1, 25, 20),
	mission(3, "one_more", "ONE MORE!", "Choose One More once.", "OneMoreAccepted", 1, 35, 30),
	mission(4, "collector_three", "START A COLLECTION", "Discover three different items.", "DiscoveredCount", 3, 75, 50),
	mission(5, "five_item_box", "PACK IT TIGHT", "Ship at least five items together.", "ShipmentItemCount", 5, 150, 100),
}
table.freeze(ordered)

local byId: { [string]: MissionDefinition } = {}
local indexes: { [string]: number } = {}
local orderedMissionIds: { string } = {}
local totalTapeReward = 0
local totalXPReward = 0
for index, definition in ipairs(ordered) do
	byId[definition.Id] = definition
	indexes[definition.Id] = index
	table.insert(orderedMissionIds, definition.Id)
	totalTapeReward += definition.Reward.Tape
	totalXPReward += definition.Reward.PackingXP
end
table.freeze(byId)
table.freeze(indexes)
table.freeze(orderedMissionIds)

local StarterMissionDefinitions = {
	Ordered = ordered,
	OrderedMissionIds = orderedMissionIds,
	TotalCount = #ordered,
	TotalTapeReward = totalTapeReward,
	TotalXPReward = totalXPReward,
}

function StarterMissionDefinitions.Get(missionId: string): MissionDefinition?
	return if type(missionId) == "string" then byId[missionId] else nil
end

function StarterMissionDefinitions.GetIndex(missionId: string): number?
	return if type(missionId) == "string" then indexes[missionId] else nil
end

function StarterMissionDefinitions.GetGoal(missionId: string): number?
	local definition = StarterMissionDefinitions.Get(missionId)
	return if definition ~= nil then definition.Goal else nil
end

function StarterMissionDefinitions.GetReward(missionId: string): MissionReward?
	local definition = StarterMissionDefinitions.Get(missionId)
	return if definition ~= nil then definition.Reward else nil
end

function StarterMissionDefinitions.GetFirstIncomplete(completed: { [string]: boolean }): MissionDefinition?
	for _, definition in ipairs(ordered) do
		if completed[definition.Id] ~= true then
			return definition
		end
	end
	return nil
end

function StarterMissionDefinitions.GetTotalCount(): number
	return #ordered
end

function StarterMissionDefinitions.IsValidMissionId(missionId: any): boolean
	return type(missionId) == "string" and byId[missionId] ~= nil
end

return table.freeze(StarterMissionDefinitions)
