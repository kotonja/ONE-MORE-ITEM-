--!strict

local AnalyticsAdapter = require(script.Parent.AnalyticsAdapter)

type CustomFields = AnalyticsAdapter.CustomFields

export type EventRecord = {
	Sequence: number,
	Kind: string,
	PlayerUserId: number,
	Name: string,
	Value: number,
	Fields: CustomFields,
	Details: { [string]: any },
}

type Options = {
	FailureCount: number?,
}

export type Adapter = AnalyticsAdapter.Adapter & {
	SetFailureCount: (self: Adapter, count: number) -> (),
	GetRecords: (self: Adapter) -> { EventRecord },
	GetRecordsForPlayer: (self: Adapter, userId: number) -> { EventRecord },
	Count: (self: Adapter, kind: string?, name: string?) -> number,
	Clear: (self: Adapter) -> (),
}

type AdapterImpl = Adapter & {
	_records: { EventRecord },
	_sequence: number,
	_failureCount: number,
	_destroyed: boolean,
	_record: (
		self: AdapterImpl,
		player: Player,
		kind: string,
		name: string,
		value: number,
		fields: CustomFields,
		details: { [string]: any }
	) -> (boolean, string),
}

local MemoryAnalyticsAdapter = {}
MemoryAnalyticsAdapter.__index = MemoryAnalyticsAdapter

local function copyValue(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copied = {}
	for key, child in pairs(value) do
		copied[copyValue(key)] = copyValue(child)
	end
	return copied
end

local function freezeRecord(record: EventRecord): EventRecord
	table.freeze(record.Fields)
	table.freeze(record.Details)
	return table.freeze(record)
end

local function copyRecord(record: EventRecord): EventRecord
	return freezeRecord({
		Sequence = record.Sequence,
		Kind = record.Kind,
		PlayerUserId = record.PlayerUserId,
		Name = record.Name,
		Value = record.Value,
		Fields = copyValue(record.Fields) :: CustomFields,
		Details = copyValue(record.Details),
	})
end

function MemoryAnalyticsAdapter.Create(options: Options?): Adapter
	local resolved = options or {}
	return setmetatable({
		_records = {},
		_sequence = 0,
		_failureCount = math.max(0, math.floor(resolved.FailureCount or 0)),
		_destroyed = false,
	}, MemoryAnalyticsAdapter) :: any
end

function MemoryAnalyticsAdapter.GetEnvironment(_self: AdapterImpl): AnalyticsAdapter.Environment
	return "Memory"
end

function MemoryAnalyticsAdapter.SetFailureCount(self: AdapterImpl, count: number)
	self._failureCount = math.max(0, math.floor(count))
end

function MemoryAnalyticsAdapter._record(
	self: AdapterImpl,
	player: Player,
	kind: string,
	name: string,
	value: number,
	fields: CustomFields,
	details: { [string]: any }
): (boolean, string)
	if self._destroyed then
		return false, "DESTROYED"
	end
	if self._failureCount > 0 then
		self._failureCount -= 1
		return false, "INJECTED_FAILURE"
	end
	self._sequence += 1
	local userId = if typeof(player) == "Instance" then player.UserId else (player :: any).UserId
	local record = freezeRecord({
		Sequence = self._sequence,
		Kind = kind,
		PlayerUserId = userId,
		Name = name,
		Value = value,
		Fields = copyValue(fields) :: CustomFields,
		Details = copyValue(details),
	})
	table.insert(self._records, record)
	return true, "RECORDED"
end

function MemoryAnalyticsAdapter.LogOnboardingStep(self: AdapterImpl, player: Player, step: number, stepName: string, fields: CustomFields): (boolean, string)
	return self:_record(player, "Onboarding", stepName, step, fields, { Step = step, StepName = stepName })
end

function MemoryAnalyticsAdapter.LogCustom(self: AdapterImpl, player: Player, eventName: string, value: number, fields: CustomFields): (boolean, string)
	return self:_record(player, "Custom", eventName, value, fields, {})
end

function MemoryAnalyticsAdapter.LogEconomySource(
	self: AdapterImpl,
	player: Player,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string,
	fields: CustomFields
): (boolean, string)
	return self:_record(player, "EconomySource", transactionType, amount, fields, {
		CurrencyType = currencyType,
		Amount = amount,
		EndingBalance = endingBalance,
		TransactionType = transactionType,
		ItemSku = itemSku,
	})
end

local function progression(
	self: AdapterImpl,
	player: Player,
	kind: string,
	pathName: string,
	level: number,
	levelName: string,
	fields: CustomFields
): (boolean, string)
	return self:_record(player, kind, pathName, level, fields, {
		PathName = pathName,
		Level = level,
		LevelName = levelName,
	})
end

function MemoryAnalyticsAdapter.LogProgressionStart(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return progression(self, player, "ProgressionStart", pathName, level, levelName, fields)
end

function MemoryAnalyticsAdapter.LogProgressionComplete(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return progression(self, player, "ProgressionComplete", pathName, level, levelName, fields)
end

function MemoryAnalyticsAdapter.LogProgressionFail(self: AdapterImpl, player: Player, pathName: string, level: number, levelName: string, fields: CustomFields): (boolean, string)
	return progression(self, player, "ProgressionFail", pathName, level, levelName, fields)
end

function MemoryAnalyticsAdapter.GetRecords(self: AdapterImpl): { EventRecord }
	local records: { EventRecord } = table.create(#self._records)
	for index, record in ipairs(self._records) do
		records[index] = copyRecord(record)
	end
	return table.freeze(records)
end

function MemoryAnalyticsAdapter.GetRecordsForPlayer(self: AdapterImpl, userId: number): { EventRecord }
	local records: { EventRecord } = {}
	for _, record in ipairs(self._records) do
		if record.PlayerUserId == userId then
			table.insert(records, copyRecord(record))
		end
	end
	return table.freeze(records)
end

function MemoryAnalyticsAdapter.Count(self: AdapterImpl, kind: string?, name: string?): number
	local count = 0
	for _, record in ipairs(self._records) do
		if (kind == nil or record.Kind == kind) and (name == nil or record.Name == name) then
			count += 1
		end
	end
	return count
end

function MemoryAnalyticsAdapter.Clear(self: AdapterImpl)
	table.clear(self._records)
	self._sequence = 0
end

function MemoryAnalyticsAdapter.Destroy(self: AdapterImpl)
	self._destroyed = true
	self:Clear()
end

return table.freeze(MemoryAnalyticsAdapter)
