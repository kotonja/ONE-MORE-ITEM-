--!strict

export type CustomFieldValue = string | number | boolean
export type CustomFields = { [string]: CustomFieldValue }
export type Environment = "Memory" | "Roblox"

export type Adapter = {
	LogOnboardingStep: (self: any, player: Player, step: number, stepName: string, customFields: CustomFields) -> (boolean, string),
	LogCustom: (self: any, player: Player, eventName: string, value: number, customFields: CustomFields) -> (boolean, string),
	LogEconomySource: (
		self: any,
		player: Player,
		currencyType: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string,
		customFields: CustomFields
	) -> (boolean, string),
	LogProgressionStart: (self: any, player: Player, pathName: string, level: number, levelName: string, customFields: CustomFields) -> (boolean, string),
	LogProgressionComplete: (self: any, player: Player, pathName: string, level: number, levelName: string, customFields: CustomFields) -> (boolean, string),
	LogProgressionFail: (self: any, player: Player, pathName: string, level: number, levelName: string, customFields: CustomFields) -> (boolean, string),
	GetEnvironment: (self: any) -> Environment,
	Destroy: (self: any) -> (),
}

return table.freeze({})
