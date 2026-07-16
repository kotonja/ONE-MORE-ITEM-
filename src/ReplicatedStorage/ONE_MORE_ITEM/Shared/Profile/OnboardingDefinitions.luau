--!strict

export type OnboardingStatus = "NotStarted" | "InProgress" | "Completed" | "Skipped"

export type OnboardingStep = {
	Number: number,
	Name: string,
}

local ordered: { OnboardingStep } = {
	table.freeze({ Number = 1, Name = "PROFILE READY" }),
	table.freeze({ Number = 2, Name = "STATION ASSIGNED" }),
	table.freeze({ Number = 3, Name = "FIRST ITEM PLACED" }),
	table.freeze({ Number = 4, Name = "FIRST DECISION SHOWN" }),
	table.freeze({ Number = 5, Name = "FIRST SHIPMENT COMPLETED" }),
}
table.freeze(ordered)

local byNumber: { [number]: OnboardingStep } = {}
for _, definition in ipairs(ordered) do
	byNumber[definition.Number] = definition
end
table.freeze(byNumber)

local validStatuses: { [string]: boolean } = table.freeze({
	NotStarted = true,
	InProgress = true,
	Completed = true,
	Skipped = true,
})

local OnboardingDefinitions = {
	Ordered = ordered,
	TotalCount = #ordered,
	MaximumStep = #ordered,
}

function OnboardingDefinitions.GetStep(stepNumber: number): OnboardingStep?
	if type(stepNumber) ~= "number" or stepNumber % 1 ~= 0 then
		return nil
	end
	return byNumber[stepNumber]
end

function OnboardingDefinitions.GetStepName(stepNumber: number): string?
	local definition = OnboardingDefinitions.GetStep(stepNumber)
	return if definition ~= nil then definition.Name else nil
end

function OnboardingDefinitions.GetNextStep(highestStep: number): number?
	if type(highestStep) ~= "number"
		or highestStep ~= highestStep
		or highestStep == math.huge
		or highestStep == -math.huge
	then
		return 1
	end
	local normalized = math.clamp(math.floor(highestStep), 0, #ordered)
	return if normalized < #ordered then normalized + 1 else nil
end

function OnboardingDefinitions.IsTerminal(status: any): boolean
	return status == "Completed" or status == "Skipped"
end

function OnboardingDefinitions.NormalizeStatus(status: any): OnboardingStatus
	if type(status) == "string" and validStatuses[status] == true then
		return status :: OnboardingStatus
	end
	return "NotStarted"
end

return table.freeze(OnboardingDefinitions)
