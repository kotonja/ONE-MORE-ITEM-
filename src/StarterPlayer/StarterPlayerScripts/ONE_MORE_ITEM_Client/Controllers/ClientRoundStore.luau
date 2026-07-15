--!strict

export type RoundId = number

export type Cell = {
	X: number,
	Y: number,
	Z: number,
}

export type Snapshot = {
	RoundId: RoundId,
	OutcomeId: string?,
	StateVersion: number,
	State: string,
	StationId: string?,
	CurrentItemId: string?,
	CurrentShapeId: string?,
	NextItemId: string?,
	NextShapeId: string?,
	NextDifficulty: string?,
	OccupiedCells: { Cell },
	ItemCount: number,
	BaseValueSum: number,
	ShipmentValue: number,
	PossibleNextShipmentValue: number,
	CurrentMultiplier: number,
	SessionBank: number,
	PlacementDeadline: number?,
	DecisionDeadline: number?,
	ResultReason: string?,
	ResultValue: number,
	ResultLostValue: number,
}

export type PlacementResponse = {
	Accepted: boolean,
	Reason: string,
	ClientSequence: number,
	RoundId: RoundId,
	StateVersion: number,
}

type Listener = (snapshot: Snapshot) -> ()

export type Store = {
	ApplySnapshot: (self: Store, snapshot: Snapshot) -> boolean,
	GetSnapshot: (self: Store) -> Snapshot?,
	Subscribe: (self: Store, listener: Listener) -> (() -> ()),
	Destroy: (self: Store) -> (),
}

type InternalStore = Store & {
	_snapshot: Snapshot?,
	_listeners: { [number]: Listener },
	_nextListenerId: number,
	_destroyed: boolean,
}

local ClientRoundStore = {}
local StoreMethods = {}
StoreMethods.__index = StoreMethods

local function copyCells(cells: { Cell }): { Cell }
	local copied: { Cell } = {}
	for _, cell in ipairs(cells) do
		table.insert(copied, table.freeze({ X = cell.X, Y = cell.Y, Z = cell.Z }) :: Cell)
	end
	table.freeze(copied)
	return copied
end

local function copySnapshot(snapshot: Snapshot): Snapshot
	local copied: Snapshot = {
		RoundId = snapshot.RoundId,
		OutcomeId = snapshot.OutcomeId,
		StateVersion = snapshot.StateVersion,
		State = snapshot.State,
		StationId = snapshot.StationId,
		CurrentItemId = snapshot.CurrentItemId,
		CurrentShapeId = snapshot.CurrentShapeId,
		NextItemId = snapshot.NextItemId,
		NextShapeId = snapshot.NextShapeId,
		NextDifficulty = snapshot.NextDifficulty,
		OccupiedCells = copyCells(snapshot.OccupiedCells),
		ItemCount = snapshot.ItemCount,
		BaseValueSum = snapshot.BaseValueSum,
		ShipmentValue = snapshot.ShipmentValue,
		PossibleNextShipmentValue = snapshot.PossibleNextShipmentValue,
		CurrentMultiplier = snapshot.CurrentMultiplier,
		SessionBank = snapshot.SessionBank,
		PlacementDeadline = snapshot.PlacementDeadline,
		DecisionDeadline = snapshot.DecisionDeadline,
		ResultReason = snapshot.ResultReason,
		ResultValue = snapshot.ResultValue,
		ResultLostValue = snapshot.ResultLostValue,
	}
	return table.freeze(copied) :: Snapshot
end

function ClientRoundStore.new(): Store
	local self: InternalStore = setmetatable({
		_snapshot = nil,
		_listeners = {},
		_nextListenerId = 0,
		_destroyed = false,
	}, StoreMethods) :: InternalStore
	return self
end

function StoreMethods.ApplySnapshot(self: InternalStore, snapshot: Snapshot): boolean
	if self._destroyed then
		return false
	end

	local previous = self._snapshot
	if previous ~= nil then
		if snapshot.RoundId < previous.RoundId then
			return false
		end
		if snapshot.RoundId == previous.RoundId and snapshot.StateVersion <= previous.StateVersion then
			return false
		end
	end

	local copied = copySnapshot(snapshot)
	self._snapshot = copied
	for _, listener in pairs(self._listeners) do
		listener(copied)
	end
	return true
end

function StoreMethods.GetSnapshot(self: InternalStore): Snapshot?
	return self._snapshot
end

function StoreMethods.Subscribe(self: InternalStore, listener: Listener): () -> ()
	if self._destroyed then
		error("Cannot subscribe to a destroyed ClientRoundStore", 2)
	end
	self._nextListenerId += 1
	local listenerId = self._nextListenerId
	self._listeners[listenerId] = listener

	local connected = true
	return function()
		if connected then
			connected = false
			self._listeners[listenerId] = nil
		end
	end
end

function StoreMethods.Destroy(self: InternalStore)
	self._destroyed = true
	table.clear(self._listeners)
	self._snapshot = nil
end

return table.freeze(ClientRoundStore)
