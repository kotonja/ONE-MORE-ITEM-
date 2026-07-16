--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local DevelopmentItemDefinitions = require(Root.Shared.Content.DevelopmentItemDefinitions)
local OccupancyGrid = require(Root.Shared.Grid.OccupancyGrid)
local GridWorldTransform = require(Root.Shared.World.GridWorldTransform)
local StationDefinitions = require(Root.Shared.World.StationDefinitions)

local Services = script.Parent.Parent:WaitForChild("Services")
local ArenaAnnouncementService = require(Services:WaitForChild("ArenaAnnouncementService"))
local RoundService = require(Services:WaitForChild("RoundService"))
local ServerBestService = require(Services:WaitForChild("ServerBestService"))
local ShipmentRecordService = require(Services:WaitForChild("ShipmentRecordService"))
local ShowcaseService = require(Services:WaitForChild("ShowcaseService"))
local StationDisplayService = require(Services:WaitForChild("StationDisplayService"))
local StationService = require(Services:WaitForChild("StationService"))
local WorldItemService = require(Services:WaitForChild("WorldItemService"))

local ClientControllers = StarterPlayer:WaitForChild("StarterPlayerScripts")
	:WaitForChild("ONE_MORE_ITEM_Client")
	:WaitForChild("Controllers")
local StationContextController = require(ClientControllers:WaitForChild("StationContextController"))

type TestCase = {
	Name: string,
	Run: () -> (),
}

type TestSuite = {
	Name: string,
	Tests: { TestCase },
}

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	Seed: number,
}

type FakePlayerState = {
	Connected: boolean,
	DisconnectCount: number,
	CharacterCallback: ((Model) -> ())?,
}

type ClientHarness = {
	Controller: any,
	StationsRoot: Instance,
	Remote: RemoteEvent,
	Template: BasePart,
	Log: any,
	Destroy: (self: ClientHarness) -> (),
}

type ShowcaseHarness = {
	Service: any,
	Template: Model,
	Entry: BasePart,
	PathNodes: Instance,
	Runtime: Folder,
	Destroy: (self: ShowcaseHarness) -> (),
}

local Phase04TestSuite = {}
local suites: { TestSuite } = {}

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, {
		Name = name,
		Tests = tests,
	})
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "Expectation failed", 2)
	end
end

local function expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(string.format(
			"%s expected=%s actual=%s",
			message or "Values differ",
			tostring(expected),
			tostring(actual)
		), 2)
	end
end

local function expectNear(actual: number, expected: number, epsilon: number, message: string?)
	if math.abs(actual - expected) > epsilon then
		error(string.format(
			"%s expected=%.8f actual=%.8f epsilon=%.8f",
			message or "Numbers differ",
			expected,
			actual,
			epsilon
		), 2)
	end
end

local function expectVectorNear(actual: Vector3, expected: Vector3, epsilon: number, message: string?)
	if (actual - expected).Magnitude > epsilon then
		error(string.format(
			"%s expected=%s actual=%s epsilon=%.8f",
			message or "Vectors differ",
			tostring(expected),
			tostring(actual),
			epsilon
		), 2)
	end
end

local function expectColorNear(actual: Color3, expected: Color3, epsilon: number, message: string?)
	expectNear(actual.R, expected.R, epsilon, message)
	expectNear(actual.G, expected.G, epsilon, message)
	expectNear(actual.B, expected.B, epsilon, message)
end

local function expectError(callback: () -> (), fragment: string?)
	local ok, failure = pcall(callback)
	expect(not ok, "Expected callback to fail")
	if fragment ~= nil then
		expect(string.find(string.lower(tostring(failure)), string.lower(fragment), 1, true) ~= nil,
			string.format("Expected failure containing %q, got %s", fragment, tostring(failure)))
	end
end

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA(className) then
		error(string.format("Fixture requires %s.%s to be %s", parent:GetFullName(), name, className), 2)
	end
	return child
end

local function requireDescendant(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name, true)
	if child == nil or not child:IsA(className) then
		error(string.format("Fixture requires descendant %s %s", className, name), 2)
	end
	return child
end

local function authoredArena(): Folder
	local world = requireChild(Workspace, "ONE_MORE_ITEM_WORLD", "Folder")
	return requireChild(world, "PlaytestArena", "Folder") :: Folder
end

local function authoredStationsRoot(): Instance
	return requireChild(authoredArena(), "Stations", "Folder")
end

local function cloneStationsRoot(): Instance
	local clone = authoredStationsRoot():Clone()
	clone.Name = "Phase04TestStations"
	clone.Parent = nil
	return clone
end

local function fakePlayer(userId: number, displayName: string?): Player
	local state: FakePlayerState = {
		Connected = false,
		DisconnectCount = 0,
		CharacterCallback = nil,
	}
	local connection = {
		Disconnect = function()
			if state.Connected then
				state.Connected = false
				state.DisconnectCount += 1
			end
			state.CharacterCallback = nil
		end,
	}
	local signal = {
		Connect = function(_self: any, callback: (Model) -> ())
			state.Connected = true
			state.CharacterCallback = callback
			return connection
		end,
	}
	local player = {
		UserId = userId,
		Name = string.format("Player%d", userId),
		DisplayName = displayName or string.format("Player %d", userId),
		Character = nil,
		CharacterAdded = signal,
		_TestConnectionState = state,
		_FireCharacterAdded = function(_self: any, character: Model)
			local callback = state.CharacterCallback
			if callback ~= nil then
				callback(character)
			end
		end,
	}
	return (player :: any) :: Player
end

local function getFakePlayerState(player: Player): FakePlayerState
	return ((player :: any)._TestConnectionState :: any) :: FakePlayerState
end

local function stationModel(root: Instance, index: number): Model
	return requireChild(root, string.format("Station_%02d", index), "Model") :: Model
end

local function stationGridOrigin(model: Model): BasePart
	local crate = requireChild(model, "Crate", "Folder")
	return requireChild(crate, "GridOrigin", "BasePart") :: BasePart
end

local function stationLabel(model: Model, name: string): TextLabel
	local ownerDisplay = requireChild(model, "OwnerDisplay", "BasePart")
	return requireDescendant(ownerDisplay, name, "TextLabel") :: TextLabel
end

local function stationIndicator(model: Model): (BasePart, PointLight)
	local riskIndicator = requireChild(model, "RiskIndicator", "Folder")
	local indicator = requireChild(riskIndicator, "IndicatorPart", "BasePart") :: BasePart
	local light = requireChild(indicator, "Light", "PointLight") :: PointLight
	return indicator, light
end

local function placementAt(x: number, y: number, z: number): any
	local definition = DevelopmentItemDefinitions.Get("parcel")
	expect(definition ~= nil, "parcel development item must exist")
	return {
		ShapeId = (definition :: any).ShapeId,
		RotationIndex = 1,
		QuarterTurns = 0,
		Origin = { X = x, Y = y, Z = z },
		Cells = { { X = x, Y = y, Z = z } },
		Key = string.format("%d:%d:%d", x, y, z),
	}
end

local function placedItem(itemId: string?, quarterTurns: number?): any
	local resolvedId = itemId or "parcel"
	local definition = DevelopmentItemDefinitions.Get(resolvedId)
	expect(definition ~= nil, "Placed-item fixture requires a known item")
	return {
		ItemId = resolvedId,
		ShapeId = (definition :: any).ShapeId,
		QuarterTurns = quarterTurns or 0,
		OriginX = 0,
		OriginY = 0,
		OriginZ = 0,
		ColorR = (definition :: any).Color.R,
		ColorG = (definition :: any).Color.G,
		ColorB = (definition :: any).Color.B,
	}
end

local function roundRecord(userId: number, roundId: number, stationId: string, items: { any }?): any
	local resolvedItems = items or {}
	return {
		PlayerUserId = userId,
		RoundId = roundId,
		OutcomeId = string.format("%d:phase04-test:%d", userId, roundId),
		OutcomeProcessed = false,
		StateVersion = 0,
		State = "Shipping",
		StationId = stationId,
		CurrentItemId = nil,
		PreviewedNextItemId = nil,
		PreviewDifficulty = nil,
		Grid = OccupancyGrid.CreateGrid(5, 4, 5),
		PlacedItems = resolvedItems,
		ItemCount = #resolvedItems,
		BaseValueSum = #resolvedItems * 15,
		ShipmentValue = #resolvedItems * 25,
		SessionBank = 0,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		LastClientSequences = { Place = -1, Decision = -1, Restart = -1 },
		ResultReason = "PLAYER_SHIPPED",
		ResultValue = #resolvedItems * 25,
		ResultLostValue = 0,
		ShipmentBanked = true,
		GuidedOnboarding = false,
		StartedAt = 0,
	}
end

local function shipmentRecord(sequence: number, value: number?, itemCount: number?, itemId: string?, quarterTurns: number?): any
	local count = itemCount or 1
	local items: { any } = table.create(count)
	for index = 1, count do
		local item = placedItem(itemId, quarterTurns)
		item.OriginX = (index - 1) % 5
		item.OriginY = math.floor((index - 1) / 5)
		item.OriginZ = math.floor((index - 1) / 3) % 5
		items[index] = table.freeze(item)
	end
	table.freeze(items)
	return table.freeze({
		OutcomeId = string.format("test:%03d", sequence),
		ShipmentId = string.format("test:%03d", sequence),
		PlayerUserId = 1000 + sequence,
		PlayerDisplayName = string.format("Player %d", sequence),
		StationId = string.format("station_%02d", ((sequence - 1) % 8) + 1),
		RoundId = sequence,
		ItemCount = count,
		BaseValueSum = value or (count * 15),
		ShipmentValue = value or (count * 25),
		Multiplier = 1,
		PlacedItems = items,
		CreatedAt = 1000 + sequence,
		PerfectShipment = count == 10,
	})
end

local function clientSnapshot(stationId: string?, roundId: number?, stateVersion: number?, state: string?): any
	return {
		RoundId = roundId or 1,
		StateVersion = stateVersion or 1,
		State = state or "Preparing",
		StationId = stationId,
		CurrentItemId = "parcel",
		CurrentShapeId = "single_cube",
		NextItemId = nil,
		NextShapeId = nil,
		NextDifficulty = nil,
		OccupiedCells = {},
		ItemCount = 0,
		BaseValueSum = 0,
		ShipmentValue = 0,
		PossibleNextShipmentValue = 0,
		CurrentMultiplier = 1,
		SessionBank = 0,
		PlacementDeadline = nil,
		DecisionDeadline = nil,
		GuidedOnboarding = false,
		ResultReason = nil,
		ResultValue = 0,
		ResultLostValue = 0,
	}
end

local function newClientHarness(): ClientHarness
	local stationsRoot = cloneStationsRoot()
	local remote = Instance.new("RemoteEvent")
	local template = Instance.new("Part")
	local log = {
		ActivatedStations = {},
		ActivatedCameraFrames = {},
		DeactivateCount = 0,
		Impulses = {},
		AssignedStates = {},
		Assignments = {},
		FitCount = 0,
		PendingStates = {},
		ObservabilityCount = 0,
		PlacementCreates = {},
		PlacementDestroys = 0,
		PlacementApplies = 0,
		PlacementMoves = 0,
		PlacementRotates = 0,
		PlacementRequests = 0,
		PlacementRays = 0,
		PlacementResponses = 0,
		WorldCreates = {},
		WorldDestroys = 0,
		WorldStates = {},
		WorldButtons = {},
	}
	local camera = {
		Activate = function(_self: any, station: Model)
			table.insert(log.ActivatedStations, station.Name)
			local anchor = requireChild(station, "CameraAnchor", "BasePart") :: BasePart
			table.insert(log.ActivatedCameraFrames, anchor.CFrame)
		end,
		Deactivate = function(_self: any)
			log.DeactivateCount += 1
		end,
		PlayImpulse = function(_self: any, impulse: string)
			table.insert(log.Impulses, impulse)
		end,
	}
	local character = {
		SetAssigned = function(_self: any, assigned: boolean)
			table.insert(log.AssignedStates, assigned)
		end,
	}
	local factories = {
		CreatePlacement = function(_remote: RemoteEvent, station: Model, _template: BasePart, callbacks: any)
			local placement = {
				Station = station,
				Callbacks = callbacks,
				Pending = false,
				Destroyed = false,
			}
			function placement:ApplySnapshot(_snapshot: any)
				log.PlacementApplies += 1
			end
			function placement:Move(_x: number, _z: number)
				log.PlacementMoves += 1
			end
			function placement:RotateClockwise()
				log.PlacementRotates += 1
			end
			function placement:RequestPlacement()
				log.PlacementRequests += 1
			end
			function placement:UpdateFromPointerRay(_ray: Ray)
				log.PlacementRays += 1
			end
			function placement:IsPlacementPending(): boolean
				return self.Pending
			end
			function placement:HandleResponse(_response: any)
				log.PlacementResponses += 1
			end
			function placement:Destroy()
				if not self.Destroyed then
					self.Destroyed = true
					log.PlacementDestroys += 1
				end
			end
			table.insert(log.PlacementCreates, placement)
			return placement
		end,
		CreateWorldMotion = function(station: Model)
			local motion = { Station = station, Destroyed = false }
			function motion:SetState(current: string, previous: string?)
				table.insert(log.WorldStates, string.format("%s>%s", previous or "nil", current))
			end
			function motion:SetGridFeedback(_cells: { any }, _valid: boolean)
			end
			function motion:ClearGridFeedback()
			end
			function motion:PressButton(action: string)
				table.insert(log.WorldButtons, action)
			end
			function motion:PlayPlacementImpact(_position: Vector3, _heavy: boolean)
			end
			function motion:PlayRejected()
			end
			function motion:Destroy()
				if not self.Destroyed then
					self.Destroyed = true
					log.WorldDestroys += 1
				end
			end
			table.insert(log.WorldCreates, motion)
			return motion
		end,
	}
	local callbacks = {
		FitChanged = function(_valid: boolean?, _x: number?, _y: number?, _z: number?)
			log.FitCount += 1
		end,
		ButtonPressed = function(action: string)
			table.insert(log.WorldButtons, "callback:" .. action)
		end,
		ServerResponse = function(_reason: string, _accepted: boolean)
		end,
		PendingChanged = function(pending: boolean)
			table.insert(log.PendingStates, pending)
		end,
		Observability = function(_valid: boolean?, _x: number?, _y: number?, _z: number?)
			log.ObservabilityCount += 1
		end,
		AssignmentChanged = function(assigned: boolean, stationId: string?)
			table.insert(log.Assignments, if assigned then stationId else "NONE")
		end,
	}
	local controller = StationContextController.new(({
		StationsRoot = stationsRoot,
		PlaceItemRequest = remote,
		CellBlockTemplate = template,
		Camera = camera,
		Character = character,
		Callbacks = callbacks,
		Factories = factories,
	} :: any))
	local harness: ClientHarness = {
		Controller = controller,
		StationsRoot = stationsRoot,
		Remote = remote,
		Template = template,
		Log = log,
		Destroy = function(self: ClientHarness)
			self.Controller:Destroy()
			self.Remote:Destroy()
			self.Template:Destroy()
			self.StationsRoot:Destroy()
		end,
	}
	return harness
end

local function authoredShowcaseParts(): (Model, BasePart, Instance)
	local development = requireChild(requireChild(Root, "Assets", "Folder"), "Development", "Folder")
	local template = requireChild(development, "ShowcaseCrateTemplate", "Model") :: Model
	local arena = authoredArena()
	local dispatch = requireChild(arena, "CenterDispatch", "Model")
	local entry = requireChild(dispatch, "ShowcaseEntry", "BasePart") :: BasePart
	local loop = requireChild(arena, "ShowcaseLoop", "Folder")
	local pathNodes = requireChild(loop, "PathNodes", "Folder")
	return template, entry, pathNodes
end

local function newShowcaseHarness(
	autoConnect: boolean?,
	warningSink: ((message: string) -> ())?
): ShowcaseHarness
	local authoredTemplate, authoredEntry, authoredPath = authoredShowcaseParts()
	local template = authoredTemplate:Clone()
	local entry = authoredEntry:Clone() :: BasePart
	local pathNodes = authoredPath:Clone()
	local runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	local resolvedWarningSink = warningSink or function(_message: string)
		-- Expected overflow cases stay out of Studio Output unless the test supplies a recorder.
	end
	local service = ShowcaseService.Create(template, entry, pathNodes, runtime, {
		AutoConnect = autoConnect == true,
		WarningSink = resolvedWarningSink,
	})
	local harness: ShowcaseHarness = {
		Service = service,
		Template = template,
		Entry = entry,
		PathNodes = pathNodes,
		Runtime = runtime,
		Destroy = function(self: ShowcaseHarness)
			self.Service:Destroy()
			self.Template:Destroy()
			self.Entry:Destroy()
			self.PathNodes:Destroy()
			self.Runtime:Destroy()
		end,
	}
	return harness
end

local function runtimeModels(runtime: Folder): { Model }
	local models: { Model } = {}
	for _, child in ipairs(runtime:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	table.sort(models, function(a: Model, b: Model): boolean
		return (a:GetAttribute("ReceiptSequence") :: number) < (b:GetAttribute("ReceiptSequence") :: number)
	end)
	return models
end

local function newBestDisplay(): Folder
	local display = Instance.new("Folder")
	for _, name in ipairs({ "PlayerName", "ShipmentValue", "ItemCount" }) do
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Parent = display
	end
	return display
end

local function newAnnouncementDisplay(): Folder
	local display = Instance.new("Folder")
	for _, name in ipairs({ "Headline", "Detail" }) do
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Parent = display
	end
	return display
end

local function roundStateEvent(stationId: string, state: string, itemCount: number, value: number, lost: number?): any
	return table.freeze({
		PlayerUserId = 1,
		StationId = stationId,
		RoundId = 1,
		StateVersion = 1,
		State = state,
		ItemCount = itemCount,
		ShipmentValue = value,
		ResultReason = nil,
		ResultValue = if state == "Results" and (lost or 0) == 0 then value else 0,
		ResultLostValue = lost or 0,
	})
end

addSuite("Station definitions", {
	{
		Name = "exact deterministic eight-station order",
		Run = function()
			expectEqual(StationDefinitions.Capacity, 8)
			expectEqual(#StationDefinitions.Ordered, 8)
			for index, definition in ipairs(StationDefinitions.Ordered) do
				expectEqual(definition.Id, string.format("station_%02d", index))
				expectEqual(definition.Index, index)
				expectEqual(definition.ModelName, string.format("Station_%02d", index))
			end
		end,
	},
	{
		Name = "definitions and order are immutable",
		Run = function()
			expect(table.isfrozen(StationDefinitions), "StationDefinitions module must be frozen")
			expect(table.isfrozen(StationDefinitions.Ordered), "Station order must be frozen")
			for _, definition in ipairs(StationDefinitions.Ordered) do
				expect(table.isfrozen(definition), "Each definition must be frozen")
			end
		end,
	},
	{
		Name = "allowlist accepts only authored ids",
		Run = function()
			for index = 1, 8 do
				expect(StationDefinitions.IsValid(string.format("station_%02d", index)), "Expected station id")
			end
			expect(not StationDefinitions.IsValid(nil), "nil must not be valid")
			expect(not StationDefinitions.IsValid(""), "empty id must not be valid")
			expect(not StationDefinitions.IsValid("station_09"), "station_09 must not be valid")
		end,
	},
	{
		Name = "resolver validates model name id and index",
		Run = function()
			local root = cloneStationsRoot()
			for index = 1, 8 do
				expectEqual(StationDefinitions.Resolve(root, string.format("station_%02d", index)), stationModel(root, index))
			end
			stationModel(root, 4):SetAttribute("StationIndex", 99)
			expectEqual(StationDefinitions.Resolve(root, "station_04"), nil)
			root:Destroy()
		end,
	},
})

addSuite("Authored station registry", {
	{
		Name = "authored tree validates as exactly eight stations",
		Run = function()
			local service = StationService.Create(authoredStationsRoot())
			expectEqual(service:GetStationCount(), 8)
			expectEqual(#service:GetStations(), 8)
			service:Destroy()
		end,
	},
	{
		Name = "registry records are sorted and immutable",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local records = service:GetStations()
			expect(table.isfrozen(records), "Registry station array must be frozen")
			for index, record in ipairs(records) do
				expectEqual(record.Index, index)
				expectEqual(record.Id, string.format("station_%02d", index))
				expect(table.isfrozen(record), "Registry records must be frozen")
			end
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "missing active station fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			stationModel(root, 8):Destroy()
			expectError(function() StationService.Create(root) end, "exactly 8 active")
			root:Destroy()
		end,
	},
	{
		Name = "unexpected active station fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			local extra = stationModel(root, 8):Clone()
			extra.Name = "Station_Extra"
			extra:SetAttribute("StationId", "station_extra")
			extra.Parent = root
			expectError(function() StationService.Create(root) end, "exactly 8 active")
			root:Destroy()
		end,
	},
	{
		Name = "duplicate station id fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			stationModel(root, 8):SetAttribute("StationId", "station_07")
			expectError(function() StationService.Create(root) end, "StationId")
			root:Destroy()
		end,
	},
	{
		Name = "duplicate station index fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			stationModel(root, 8):SetAttribute("StationIndex", 7)
			expectError(function() StationService.Create(root) end, "StationIndex")
			root:Destroy()
		end,
	},
	{
		Name = "missing GridOrigin fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			local crate = requireChild(stationModel(root, 4), "Crate", "Folder")
			requireChild(crate, "GridOrigin", "BasePart"):Destroy()
			expectError(function() StationService.Create(root) end, "GridOrigin")
			expectEqual(crate:FindFirstChild("GridTiles") ~= nil, true, "Validation must not damage sibling content")
			root:Destroy()
		end,
	},
	{
		Name = "missing PlayerStand fails visibly",
		Run = function()
			local root = cloneStationsRoot()
			local station = stationModel(root, 6)
			requireChild(station, "PlayerStand", "BasePart"):Destroy()
			expectError(function() StationService.Create(root) end, "PlayerStand")
			expectEqual(station:FindFirstChild("StationRoot") ~= nil, true, "Validation must not damage sibling content")
			root:Destroy()
		end,
	},
	{
		Name = "wrong-class required child fails visibly and non-destructively",
		Run = function()
			local root = cloneStationsRoot()
			local station = stationModel(root, 3)
			requireChild(station, "CameraAnchor", "BasePart"):Destroy()
			local wrongClass = Instance.new("Folder")
			wrongClass.Name = "CameraAnchor"
			wrongClass.Parent = station
			expectError(function() StationService.Create(root) end, "CameraAnchor")
			expectEqual(station:FindFirstChild("CameraAnchor"), wrongClass, "Validation must not delete conflict")
			root:Destroy()
		end,
	},
	{
		Name = "grid tile count and exact names are enforced",
		Run = function()
			local root = cloneStationsRoot()
			local tiles = requireChild(requireChild(stationModel(root, 2), "Crate", "Folder"), "GridTiles", "Folder")
			requireChild(tiles, "Cell_4_4", "BasePart"):Destroy()
			expectError(function() StationService.Create(root) end, "25")
			root:Destroy()
		end,
	},
})

local transformTests: { TestCase } = {}
local TRANSFORM_GROUPS: { { number } } = {
	{ 1, 2, 3 },
	{ 4, 5, 6 },
	{ 7, 8 },
}
for _, stationIndexes in ipairs(TRANSFORM_GROUPS) do
	local capturedIndexes = stationIndexes
	table.insert(transformTests, {
		Name = string.format(
			"Stations %02d-%02d grid axes pointer mapping and cameras",
			capturedIndexes[1],
			capturedIndexes[#capturedIndexes]
		),
		Run = function()
			for _, capturedIndex in ipairs(capturedIndexes) do
				local model = stationModel(authoredStationsRoot(), capturedIndex)
				local origin = stationGridOrigin(model)
				local cellZero = GridWorldTransform.CellToWorldPosition(origin.CFrame, { X = 0, Y = 0, Z = 0 }, 2)
				expectVectorNear(cellZero, origin.Position, 0.00001, "Cell zero must equal GridOrigin")
				local xStep = GridWorldTransform.CellToWorldPosition(origin.CFrame, { X = 1, Y = 0, Z = 0 }, 2) - cellZero
				local yStep = GridWorldTransform.CellToWorldPosition(origin.CFrame, { X = 0, Y = 1, Z = 0 }, 2) - cellZero
				local zStep = GridWorldTransform.CellToWorldPosition(origin.CFrame, { X = 0, Y = 0, Z = 1 }, 2) - cellZero
				expectVectorNear(xStep, origin.CFrame.RightVector * 2, 0.00001, "Logical X must follow local X")
				expectVectorNear(yStep, Vector3.yAxis * 2, 0.00001, "Logical Y must remain vertical")
				expectVectorNear(zStep, -origin.CFrame.LookVector * 2, 0.00001, "Logical Z must follow local Z")
				for _, logical in ipairs({ { X = 0, Z = 0 }, { X = 2, Z = 2 }, { X = 4, Z = 0 }, { X = 0, Z = 4 }, { X = 4, Z = 4 } }) do
					local world = GridWorldTransform.CellToWorldPosition(origin.CFrame, { X = logical.X, Y = 0, Z = logical.Z }, 2)
					local x, z = GridWorldTransform.WorldPositionToGridXZ(origin.CFrame, world, 2)
					expectEqual(x, logical.X, "Pointer X round-trip")
					expectEqual(z, logical.Z, "Pointer Z round-trip")
				end
				local focus = requireChild(model, "CameraFocus", "BasePart") :: BasePart
				for _, anchorName in ipairs({ "CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait" }) do
					local anchor = requireChild(model, anchorName, "BasePart") :: BasePart
					local towardFocus = (focus.Position - anchor.Position).Unit
					expect(anchor.CFrame.LookVector:Dot(towardFocus) > 0.97, anchorName .. " must face the crate focus")
				end
			end
		end,
	})
end
table.insert(transformTests, {
	Name = "Station 05 explicitly opposes Station 01",
	Run = function()
		local north = requireChild(stationModel(authoredStationsRoot(), 1), "StationRoot", "BasePart") :: BasePart
		local south = requireChild(stationModel(authoredStationsRoot(), 5), "StationRoot", "BasePart") :: BasePart
		expect(north.CFrame.LookVector:Dot(south.CFrame.LookVector) < -0.999, "Opposite station forwards must oppose")
		expect(north.Position:Dot(south.Position) < 0, "Opposite stations must lie on opposite sides")
	end,
})
table.insert(transformTests, {
	Name = "all station roots face arena center",
	Run = function()
		for index = 1, 8 do
			local rootPart = requireChild(stationModel(authoredStationsRoot(), index), "StationRoot", "BasePart") :: BasePart
			local towardCenter = (Vector3.new(0, rootPart.Position.Y, 0) - rootPart.Position).Unit
			expect(rootPart.CFrame.LookVector:Dot(towardCenter) > 0.99, string.format("Station %02d must face center", index))
		end
	end,
})
addSuite("Rotated grid and camera transforms", transformTests)

addSuite("Station assignment and waiting queue", {
	{
		Name = "first eight players receive lowest unique indexes",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			for index = 1, 8 do
				local result = service:AssignPlayer(fakePlayer(index))
				expect(result.Assigned, "Expected assignment")
				expectEqual(result.StationId, string.format("station_%02d", index))
				expectEqual(result.StationIndex, index)
			end
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "ninth player enters explicit queue",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			for index = 1, 8 do service:AssignPlayer(fakePlayer(index)) end
			local ninth = fakePlayer(9)
			local result = service:AssignPlayer(ninth)
			expect(not result.Assigned and result.Waiting, "Ninth player must wait")
			expectEqual(result.StationId, nil)
			expectEqual(result.QueuePosition, 1)
			expect(service:IsWaiting(ninth), "Ninth player must be tracked")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "assignment is idempotent per player",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local player = fakePlayer(1)
			expectEqual(service:AssignPlayer(player).StationId, "station_01")
			local again = service:AssignPlayer(player)
			expectEqual(again.StationId, "station_01")
			expectEqual(again.Reason, "ALREADY_ASSIGNED")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "release promotes oldest waiting player",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local owners: { Player } = {}
			for index = 1, 8 do owners[index] = fakePlayer(index); service:AssignPlayer(owners[index]) end
			local ninth = fakePlayer(9)
			local tenth = fakePlayer(10)
			service:AssignPlayer(ninth)
			service:AssignPlayer(tenth)
			local released = service:ReleasePlayer(owners[3])
			expectEqual(released.ReleasedStationId, "station_03")
			expectEqual(released.PromotedPlayer, ninth)
			expectEqual(service:GetStationId(ninth), "station_03")
			expectEqual(service:GetQueuePosition(tenth), 1)
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "invalid oldest waiter is skipped",
		Run = function()
			local root = cloneStationsRoot()
			local eligible: { [Player]: boolean } = {}
			local service = StationService.Create(root, { IsPlayerEligible = function(player: Player): boolean return eligible[player] ~= false end })
			local owners: { Player } = {}
			for index = 1, 8 do owners[index] = fakePlayer(index); service:AssignPlayer(owners[index]) end
			local invalid = fakePlayer(9)
			local valid = fakePlayer(10)
			service:AssignPlayer(invalid)
			service:AssignPlayer(valid)
			eligible[invalid] = false
			local released = service:ReleasePlayer(owners[1])
			expectEqual(released.PromotedPlayer, valid)
			expectEqual(service:GetStationId(valid), "station_01")
			expect(not service:IsWaiting(invalid), "Skipped waiter must leave the queue")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "waiting player removal preserves queue order",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local owners: { Player } = {}
			for index = 1, 8 do owners[index] = fakePlayer(index); service:AssignPlayer(owners[index]) end
			local ninth = fakePlayer(9)
			local tenth = fakePlayer(10)
			service:AssignPlayer(ninth)
			service:AssignPlayer(tenth)
			service:ReleasePlayer(ninth)
			expectEqual(service:GetQueuePosition(tenth), 1)
			expectEqual(service:ReleasePlayer(owners[8]).PromotedPlayer, tenth)
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "owner lookup is one-to-one",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local player = fakePlayer(1)
			service:AssignPlayer(player)
			local model = service:GetStationModel(player)
			expect(model ~= nil, "Assigned model expected")
			expectEqual(service:GetOwner(model :: Model), player)
			service:ReleasePlayer(player)
			expectEqual(service:GetOwner(model :: Model), nil)
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "character respawn rebinds to owned stand",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local player = fakePlayer(1)
			service:AssignPlayer(player)
			local character = Instance.new("Model")
			local part = Instance.new("Part")
			part.Parent = character
			local testPlayer = player :: any
			testPlayer:_FireCharacterAdded(character)
			local station = service:GetStationById("station_01")
			expect(station ~= nil, "Station record expected")
			expectVectorNear(part.Position, (station :: any).PlayerStand.Position, 0.00001)
			service:Destroy()
			character:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "callbacks report assignment release and promotion",
		Run = function()
			local root = cloneStationsRoot()
			local log: { string } = {}
			local service = StationService.Create(root, { Callbacks = {
				OnAssigned = function(player: Player, station: any, reason: string)
					table.insert(log, string.format("A:%d:%s:%s", player.UserId, station.Id, reason))
				end,
				OnReleased = function(player: Player, station: any)
					table.insert(log, string.format("R:%d:%s", player.UserId, station.Id))
				end,
			} })
			local owners: { Player } = {}
			for index = 1, 8 do owners[index] = fakePlayer(index); service:AssignPlayer(owners[index]) end
			local waiter = fakePlayer(9)
			service:AssignPlayer(waiter)
			service:ReleasePlayer(owners[1])
			expectEqual(log[#log - 1], "R:1:station_01")
			expectEqual(log[#log], "A:9:station_01:PROMOTED")
			service:Destroy()
			root:Destroy()
		end,
	},
	{
		Name = "destroy disconnects all character listeners",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			local players: { Player } = {}
			for index = 1, 8 do players[index] = fakePlayer(index); service:AssignPlayer(players[index]) end
			service:Destroy()
			for _, player in ipairs(players) do
				local state = getFakePlayerState(player)
				expect(not state.Connected, "Listener must disconnect")
				expectEqual(state.DisconnectCount, 1)
			end
			root:Destroy()
		end,
	},
})

addSuite("Client station binding lifecycle", {
	{
		Name = "valid snapshot binds authored station camera and character",
		Run = function()
			local harness = newClientHarness()
			expect(harness.Controller:ApplySnapshot(clientSnapshot("station_03")), "Snapshot must bind")
			expectEqual(harness.Controller:GetStationId(), "station_03")
			expectEqual(harness.Log.ActivatedStations[1], "Station_03")
			expectEqual(harness.Log.AssignedStates[1], true)
			harness:Destroy()
		end,
	},
	{
		Name = "all eight stations bind through one lifecycle",
		Run = function()
			local harness = newClientHarness()
			for index = 1, 8 do
				local id = string.format("station_%02d", index)
				expect(harness.Controller:ApplySnapshot(clientSnapshot(id, index, 1)), "Every id must bind")
				expectEqual(harness.Controller:GetStationId(), id)
			end
			expectEqual(#harness.Log.PlacementCreates, 8)
			expectEqual(#harness.Log.WorldCreates, 8)
			expectEqual(harness.Log.PlacementDestroys, 7)
			expectEqual(harness.Log.WorldDestroys, 7)
			harness:Destroy()
		end,
	},
	{
		Name = "waiting snapshot unbinds and restores normal character",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_01"))
			expect(not harness.Controller:ApplySnapshot(clientSnapshot(nil, 0, 1, "Waiting")), "Waiting is unassigned")
			expectEqual(harness.Controller:GetStationId(), nil)
			expectEqual(harness.Log.DeactivateCount, 1)
			expectEqual(harness.Log.AssignedStates[#harness.Log.AssignedStates], false)
			expectEqual(harness.Log.PlacementDestroys, 1)
			expectEqual(harness.Log.WorldDestroys, 1)
			harness:Destroy()
		end,
	},
	{
		Name = "reassignment destroys old station context exactly once",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_02", 1, 1))
			harness.Controller:ApplySnapshot(clientSnapshot("station_07", 2, 1))
			expectEqual(harness.Controller:GetStationId(), "station_07")
			expectEqual(harness.Log.PlacementDestroys, 1)
			expectEqual(harness.Log.WorldDestroys, 1)
			expectEqual(harness.Log.DeactivateCount, 1)
			harness:Destroy()
		end,
	},
	{
		Name = "Station 01 and Station 05 rebind distinct grid and camera transforms",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_01", 1, 1))
			local firstPlacement = harness.Log.PlacementCreates[1]
			local firstGrid = stationGridOrigin(firstPlacement.Station)
			local firstAnchor = requireChild(firstPlacement.Station, "CameraAnchor", "BasePart") :: BasePart

			harness.Controller:ApplySnapshot(clientSnapshot("station_05", 2, 1))
			local fifthPlacement = harness.Log.PlacementCreates[2]
			local fifthGrid = stationGridOrigin(fifthPlacement.Station)
			local fifthAnchor = requireChild(fifthPlacement.Station, "CameraAnchor", "BasePart") :: BasePart

			expect(firstGrid.CFrame.LookVector:Dot(fifthGrid.CFrame.LookVector) < -0.999,
				"Opposite station grids must use opposite local transforms")
			local firstHorizontalLook = Vector3.new(
				firstAnchor.CFrame.LookVector.X,
				0,
				firstAnchor.CFrame.LookVector.Z
			).Unit
			local fifthHorizontalLook = Vector3.new(
				fifthAnchor.CFrame.LookVector.X,
				0,
				fifthAnchor.CFrame.LookVector.Z
			).Unit
			expect(firstHorizontalLook:Dot(fifthHorizontalLook) < -0.999,
				"Opposite station cameras must face opposite horizontal directions")
			expectNear(firstAnchor.CFrame.LookVector.Y, fifthAnchor.CFrame.LookVector.Y, 0.00001,
				"Opposite station cameras must preserve the same downward pitch")
			expectVectorNear(harness.Log.ActivatedCameraFrames[1].Position, firstAnchor.Position, 0.00001)
			expectVectorNear(harness.Log.ActivatedCameraFrames[2].Position, fifthAnchor.Position, 0.00001)
			expectEqual(table.concat(harness.Log.ActivatedStations, ","), "Station_01,Station_05")
			expect(firstPlacement.Destroyed, "Station 01 placement context must be destroyed on rebind")
			expect(not fifthPlacement.Destroyed, "Station 05 placement context must remain current")
			harness:Destroy()
		end,
	},
	{
		Name = "one persistent input instance routes across station reassignment",
		Run = function()
			local harness = newClientHarness()
			local inputInstanceCount = 0
			local function createPersistentInput(): any
				inputInstanceCount += 1
				return table.freeze({
					Move = function(deltaX: number, deltaZ: number)
						harness.Controller:Move(deltaX, deltaZ)
					end,
					Rotate = function()
						harness.Controller:RotateClockwise()
					end,
				})
			end

			local input = createPersistentInput()
			local inputIdentity = input
			harness.Controller:ApplySnapshot(clientSnapshot("station_01", 1, 1))
			input.Move(1, 0)
			harness.Controller:ApplySnapshot(clientSnapshot("station_05", 2, 1))
			input.Move(0, 1)
			input.Rotate()

			expectEqual(input, inputIdentity, "Reassignment must preserve the input router identity")
			expectEqual(inputInstanceCount, 1, "Exactly one input instance may serve all station bindings")
			expectEqual(#harness.Log.PlacementCreates, 2)
			expectEqual(harness.Log.PlacementMoves, 2)
			expectEqual(harness.Log.PlacementRotates, 1)
			harness:Destroy()
		end,
	},
	{
		Name = "stale callbacks cannot affect new station",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_01", 1, 1))
			local oldPlacement = harness.Log.PlacementCreates[1]
			oldPlacement.Callbacks.FitChanged(true, 1, 0, 1)
			expectEqual(harness.Log.FitCount, 1)
			harness.Controller:ApplySnapshot(clientSnapshot("station_05", 2, 1))
			local reboundFitCount = harness.Log.FitCount
			oldPlacement.Callbacks.FitChanged(false, 4, 0, 4)
			expectEqual(harness.Log.FitCount, reboundFitCount, "Old binding callback must be ignored")
			harness:Destroy()
		end,
	},
	{
		Name = "placement responses are round correlated",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_04", 12, 1))
			harness.Controller:HandleResponse({ Accepted = true, Reason = "OK", ClientSequence = 1, RoundId = 11, StateVersion = 1 })
			expectEqual(harness.Log.PlacementResponses, 0)
			harness.Controller:HandleResponse({ Accepted = true, Reason = "OK", ClientSequence = 1, RoundId = 12, StateVersion = 1 })
			expectEqual(harness.Log.PlacementResponses, 1)
			harness:Destroy()
		end,
	},
	{
		Name = "unassigned actions remain inert",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:Move(1, 0)
			harness.Controller:RotateClockwise()
			harness.Controller:RequestPlacement()
			harness.Controller:UpdateFromPointerRay(Ray.new(Vector3.zero, Vector3.zAxis))
			harness.Controller:PressButton("SHIP")
			expectEqual(harness.Log.PlacementMoves, 0)
			expectEqual(harness.Log.PlacementRotates, 0)
			expectEqual(harness.Log.PlacementRequests, 0)
			expectEqual(harness.Log.PlacementRays, 0)
			expectEqual(#harness.Log.WorldButtons, 0)
			harness:Destroy()
		end,
	},
	{
		Name = "state changes drive only current station motion and impulses",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_06", 1, 1, "Preparing"))
			harness.Controller:ApplySnapshot(clientSnapshot("station_06", 1, 2, "Shipping"))
			harness.Controller:ApplySnapshot(clientSnapshot("station_06", 1, 3, "Shipping"))
			harness.Controller:ApplySnapshot(clientSnapshot("station_06", 1, 4, "Failing"))
			expectEqual(#harness.Log.WorldStates, 3)
			expectEqual(table.concat(harness.Log.Impulses, ","), "SHIPPING,FAILURE")
			harness:Destroy()
		end,
	},
	{
		Name = "destroy is idempotent and clears exactly one binding",
		Run = function()
			local harness = newClientHarness()
			harness.Controller:ApplySnapshot(clientSnapshot("station_08"))
			harness.Controller:Destroy()
			harness.Controller:Destroy()
			expectEqual(harness.Log.PlacementDestroys, 1)
			expectEqual(harness.Log.WorldDestroys, 1)
			expect(not harness.Controller:ApplySnapshot(clientSnapshot("station_01")), "Destroyed controller must reject snapshots")
			harness.Remote:Destroy()
			harness.Template:Destroy()
			harness.StationsRoot:Destroy()
		end,
	},
})

local function newEightRoundHarness(): any
	local players: { Player } = {}
	local stationByPlayer: { [Player]: string } = {}
	for index = 1, 8 do
		local player = fakePlayer(100 + index)
		players[index] = player
		stationByPlayer[player] = string.format("station_%02d", index)
	end
	local clockState = { Now = 500 }
	local timers: { any } = {}
	local snapshots: { any } = {}
	local clears: { [Player]: number } = {}
	local spawns: { [Player]: number } = {}
	local shipmentEvents: { any } = {}
	local failureEvents: { any } = {}
	local stateEvents: { any } = {}
	local playerByUserId: { [number]: Player } = {}
	local persistentTape: { [number]: number } = {}
	for _, player in ipairs(players) do
		playerByUserId[player.UserId] = player
		persistentTape[player.UserId] = 0
	end
	local stationContract = {
		GetStationId = function(_self: any, player: Player): string?
			return stationByPlayer[player]
		end,
	}
	local worldContract = {
		SpawnAcceptedPlacement = function(_self: any, player: Player, _itemId: string, _placement: any): Model?
			spawns[player] = (spawns[player] or 0) + 1
			return nil
		end,
		ClearPlayer = function(_self: any, player: Player)
			clears[player] = (clears[player] or 0) + 1
		end,
	}
	local service: any = nil
	local profileContract = {
		CanEnterGameplay = function(_self: any, _userId: number): boolean return true end,
		CanMutate = function(_self: any, _userId: number): boolean return true end,
		GetTape = function(_self: any, userId: number): number return persistentTape[userId] or 0 end,
	}
	local progressionContract = {
		ApplyShipment = function(_self: any, userId: number, roundId: number, outcomeId: string, record: any): (any, string)
			local player = playerByUserId[userId]
			local round = service:GetRound(player)
			local newTape = round.SessionBank + record.ShipmentValue
			persistentTape[userId] = newTape
			return { OutcomeId = outcomeId, RoundId = roundId, Duplicate = false, NewTape = newTape, TapeDelta = record.ShipmentValue }, "APPLIED"
		end,
		ApplyFailure = function(_self: any, userId: number, roundId: number, outcomeId: string, _itemCount: number): (any, string)
			local player = playerByUserId[userId]
			local round = service:GetRound(player)
			persistentTape[userId] = round.SessionBank
			return { OutcomeId = outcomeId, RoundId = roundId, Duplicate = false, NewTape = round.SessionBank, TapeDelta = 0 }, "APPLIED"
		end,
	}
	service = RoundService.Create(
		stationContract :: any,
		worldContract :: any,
		{
			Clock = function(): number return clockState.Now end,
			Scheduler = function(duration: number, callback: () -> ()) table.insert(timers, { Duration = duration, Callback = callback }) end,
			SnapshotSink = function(player: Player, snapshot: any) table.insert(snapshots, { Player = player, Snapshot = snapshot }) end,
			EventSink = {
				OnRoundStateChanged = function(player: Player, event: any) table.insert(stateEvents, { Player = player, Event = event }) end,
				OnShipmentCompleted = function(record: any) table.insert(shipmentEvents, record) end,
				OnRoundFailed = function(event: any) table.insert(failureEvents, event) end,
			},
			ShipmentRecordService = ShipmentRecordService.Create(function(): number return clockState.Now end),
			ProfileService = profileContract,
			ProgressionService = progressionContract,
			ServerSessionId = "phase04-test-session",
		}
	)
	return {
		Players = players,
		StationByPlayer = stationByPlayer,
		Clock = clockState,
		Timers = timers,
		Snapshots = snapshots,
		Clears = clears,
		Spawns = spawns,
		ShipmentEvents = shipmentEvents,
		FailureEvents = failureEvents,
		StateEvents = stateEvents,
		Service = service,
	}
end

addSuite("Eight-session round isolation", {
	{
		Name = "eight players start eight station-scoped rounds",
		Run = function()
			local harness = newEightRoundHarness()
			for index, player in ipairs(harness.Players) do
				local round = harness.Service:StartRound(player)
				expect(round ~= nil, "Round expected")
				expectEqual(round.StationId, string.format("station_%02d", index))
				expectEqual(round.PlayerUserId, player.UserId)
			end
			expectEqual(#harness.Timers, 8)
			expectEqual(#harness.Snapshots, 8)
		end,
	},
	{
		Name = "every round owns an independent integer grid",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local first = harness.Service:GetRound(harness.Players[1])
			expect(first ~= nil, "First round expected")
			expect((first :: any).Grid:ApplyPlacement(placementAt(0, 0, 0)), "Fixture placement must apply")
			for index, player in ipairs(harness.Players) do
				local round = harness.Service:GetRound(player)
				expectEqual(round.Grid:GetOccupiedCellCount(), if index == 1 then 1 else 0)
			end
		end,
	},
	{
		Name = "Tape and item fields remain isolated",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local first = harness.Service:GetRound(harness.Players[1])
			first.ItemCount = 6
			first.ShipmentValue = 450
			first.SessionBank = 900
			for index = 2, 8 do
				local other = harness.Service:GetRound(harness.Players[index])
				expectEqual(other.ItemCount, 0)
				expectEqual(other.ShipmentValue, 0)
				expectEqual(other.SessionBank, 0)
			end
		end,
	},
	{
		Name = "captured timer advances only its owning session",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			harness.Timers[5].Callback()
			for index, player in ipairs(harness.Players) do
				expectEqual(harness.Service:GetRound(player).State, if index == 5 then "PresentingItem" else "Preparing")
			end
		end,
	},
	{
		Name = "failure affects only selected player",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local failed = harness.Service:GetRound(harness.Players[3])
			failed.ItemCount = 6
			failed.ShipmentValue = 300
			harness.Service:_enterFailure(harness.Players[3], "TEST_FAILURE")
			expectEqual(harness.Service:GetRound(harness.Players[3]).State, "Failing")
			expectEqual(harness.Service:GetRound(harness.Players[3]).ResultLostValue, 300)
			expectEqual(#harness.FailureEvents, 1)
			for index, player in ipairs(harness.Players) do
				if index ~= 3 then expectEqual(harness.Service:GetRound(player).State, "Preparing") end
			end
		end,
	},
	{
		Name = "shipping banks only selected player and emits one record",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local shipped = harness.Service:GetRound(harness.Players[4])
			shipped.ShipmentValue = 275
			shipped.BaseValueSum = 275
			harness.Service:_enterShipping(harness.Players[4], "TEST_SHIP")
			expectEqual(shipped.SessionBank, 275)
			expectEqual(#harness.ShipmentEvents, 1)
			expectEqual(harness.ShipmentEvents[1].StationId, "station_04")
			for index, player in ipairs(harness.Players) do
				if index ~= 4 then expectEqual(harness.Service:GetRound(player).SessionBank, 0) end
			end
		end,
	},
	{
		Name = "one-player restart resets only its owning round",
		Run = function()
			local harness = newEightRoundHarness()
			local originalRounds: { any } = {}
			for index, player in ipairs(harness.Players) do
				originalRounds[index] = harness.Service:StartRound(player)
			end
			originalRounds[2].SessionBank = 77

			local firstPlayer = harness.Players[1]
			harness.Service:_enterFailure(firstPlayer, "TEST_RESTART")
			local finished = harness.Service:GetRound(firstPlayer)
			expect(harness.Service:HandleCapturedTimer(
				firstPlayer,
				finished.RoundId,
				finished.StateVersion,
				"Failing"
			), "Failure presentation must reach Results")
			local accepted, reason = harness.Service:HandleRestart(firstPlayer, {
				RoundId = finished.RoundId,
				StateVersion = finished.StateVersion,
				ClientSequence = 1,
			})

			expect(accepted, "Owning player restart must be accepted")
			expectEqual(reason, "RESTARTED")
			expectEqual(harness.Service:GetRound(firstPlayer).RoundId, 2)
			expectEqual(harness.Service:GetRound(firstPlayer).State, "Preparing")
			expectEqual(harness.Clears[firstPlayer], 1)
			for index = 2, 8 do
				local player = harness.Players[index]
				expectEqual(harness.Service:GetRound(player), originalRounds[index], "Neighbor round identity must persist")
				expectEqual(harness.Service:GetRound(player).State, "Preparing")
				expectEqual(harness.Clears[player], nil)
			end
			expectEqual(harness.Service:GetRound(harness.Players[2]).SessionBank, 77)
		end,
	},
	{
		Name = "same-frame two shipments remain independent",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local first = harness.Service:GetRound(harness.Players[1])
			first.PlacedItems = { placedItem("parcel", 0) }
			first.ItemCount = 1
			first.BaseValueSum = 15
			first.ShipmentValue = 25
			local fourth = harness.Service:GetRound(harness.Players[4])
			fourth.PlacedItems = { placedItem("parcel", 0), placedItem("long_package", 1) }
			fourth.ItemCount = 2
			fourth.BaseValueSum = 45
			fourth.ShipmentValue = 70

			harness.Service:_enterShipping(harness.Players[1], "SAME_FRAME_A")
			harness.Service:_enterShipping(harness.Players[4], "SAME_FRAME_B")

			expectEqual(#harness.ShipmentEvents, 2)
			expectEqual(harness.ShipmentEvents[1].PlayerUserId, harness.Players[1].UserId)
			expectEqual(harness.ShipmentEvents[1].StationId, "station_01")
			expectEqual(harness.ShipmentEvents[1].ShipmentValue, 25)
			expectEqual(harness.ShipmentEvents[2].PlayerUserId, harness.Players[4].UserId)
			expectEqual(harness.ShipmentEvents[2].StationId, "station_04")
			expectEqual(harness.ShipmentEvents[2].ShipmentValue, 70)
			expectEqual(harness.ShipmentEvents[1].CreatedAt, harness.ShipmentEvents[2].CreatedAt,
				"Same-frame records must share the deterministic clock")
			expectEqual(first.SessionBank, 25)
			expectEqual(fourth.SessionBank, 70)
			for index, player in ipairs(harness.Players) do
				if index ~= 1 and index ~= 4 then
					expectEqual(harness.Service:GetRound(player).State, "Preparing")
					expectEqual(harness.Service:GetRound(player).SessionBank, 0)
				end
			end
		end,
	},
	{
		Name = "same-frame two failures remain independent",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local third = harness.Service:GetRound(harness.Players[3])
			third.ItemCount = 7
			third.ShipmentValue = 700
			third.SessionBank = 40
			local sixth = harness.Service:GetRound(harness.Players[6])
			sixth.ItemCount = 8
			sixth.ShipmentValue = 900
			sixth.SessionBank = 55

			harness.Service:_enterFailure(harness.Players[3], "SAME_FRAME_A")
			harness.Service:_enterFailure(harness.Players[6], "SAME_FRAME_B")

			expectEqual(#harness.FailureEvents, 2)
			expectEqual(harness.FailureEvents[1].PlayerUserId, harness.Players[3].UserId)
			expectEqual(harness.FailureEvents[1].LostValue, 700)
			expectEqual(harness.FailureEvents[2].PlayerUserId, harness.Players[6].UserId)
			expectEqual(harness.FailureEvents[2].LostValue, 900)
			expectEqual(third.State, "Failing")
			expectEqual(third.SessionBank, 40)
			expectEqual(sixth.State, "Failing")
			expectEqual(sixth.SessionBank, 55)
			for index, player in ipairs(harness.Players) do
				if index ~= 3 and index ~= 6 then
					expectEqual(harness.Service:GetRound(player).State, "Preparing")
					expectEqual(harness.Service:GetRound(player).ShipmentValue, 0)
				end
			end
		end,
	},
	{
		Name = "stale timer is rejected while neighboring rounds persist",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			local firstPlayer = harness.Players[1]
			local staleRound = harness.Service:GetRound(firstPlayer)
			local neighborRounds: { any } = {}
			for index = 2, 8 do neighborRounds[index] = harness.Service:GetRound(harness.Players[index]) end
			local replacement = harness.Service:StartRound(firstPlayer)
			expectEqual(replacement.RoundId, staleRound.RoundId + 1)

			expect(not harness.Service:HandleCapturedTimer(
				firstPlayer,
				staleRound.RoundId,
				staleRound.StateVersion,
				staleRound.State
			), "Superseded round callback must be rejected")
			expectEqual(harness.Service:GetRound(firstPlayer), replacement)
			expectEqual(replacement.State, "Preparing")
			for index = 2, 8 do
				local neighbor = harness.Service:GetRound(harness.Players[index])
				expectEqual(neighbor, neighborRounds[index], "Neighbor round identity must persist")
				expectEqual(neighbor.State, "Preparing")
			end
		end,
	},
	{
		Name = "player removal clears only its round and world content",
		Run = function()
			local harness = newEightRoundHarness()
			for _, player in ipairs(harness.Players) do harness.Service:StartRound(player) end
			harness.Service:RemovePlayer(harness.Players[2])
			expectEqual(harness.Service:GetRound(harness.Players[2]), nil)
			expectEqual(harness.Clears[harness.Players[2]], 1)
			for index, player in ipairs(harness.Players) do
				if index ~= 2 then expect(harness.Service:GetRound(player) ~= nil, "Other round must remain") end
			end
		end,
	},
	{
		Name = "unassigned player cannot start round",
		Run = function()
			local harness = newEightRoundHarness()
			local player = fakePlayer(999)
			expectEqual(harness.Service:StartRound(player), nil)
			expectEqual(harness.Service:GetRound(player), nil)
		end,
	},
	{
		Name = "round ordinals advance independently per user",
		Run = function()
			local harness = newEightRoundHarness()
			local firstPlayer = harness.Players[1]
			local secondPlayer = harness.Players[2]
			expectEqual(harness.Service:StartRound(firstPlayer).RoundId, 1)
			expectEqual(harness.Service:StartRound(firstPlayer).RoundId, 2)
			expectEqual(harness.Service:StartRound(secondPlayer).RoundId, 1)
		end,
	},
})

addSuite("World-item station isolation", {
	{
		Name = "placements render under the owning station only",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local first, second = fakePlayer(1), fakePlayer(2)
			stations:AssignPlayer(first)
			stations:AssignPlayer(second)
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			expect(world:SpawnAcceptedPlacement(first, "parcel", placementAt(0, 0, 0)) ~= nil, "First proxy expected")
			expect(world:SpawnAcceptedPlacement(second, "parcel", placementAt(1, 0, 0)) ~= nil, "Second proxy expected")
			expectEqual(world:GetStationRuntimeModelCount("station_01"), 1)
			expectEqual(world:GetStationRuntimeModelCount("station_02"), 1)
			expectEqual(#stations:GetStationById("station_03").PlacedItems:GetChildren(), 0)
			world:ClearPlayer(first); world:ClearPlayer(second)
			stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "clearing one player preserves neighbor content",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local first, second = fakePlayer(1), fakePlayer(2)
			stations:AssignPlayer(first); stations:AssignPlayer(second)
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			world:SpawnAcceptedPlacement(first, "parcel", placementAt(0, 0, 0))
			world:SpawnAcceptedPlacement(second, "parcel", placementAt(0, 0, 0))
			world:ClearPlayer(first)
			expectEqual(world:GetStationRuntimeModelCount("station_01"), 0)
			expectEqual(world:GetStationRuntimeModelCount("station_02"), 1)
			world:ClearPlayer(second); stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "released player still clears its tracked station",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local player = fakePlayer(1)
			stations:AssignPlayer(player)
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			world:SpawnAcceptedPlacement(player, "parcel", placementAt(0, 0, 0))
			stations:ReleasePlayer(player)
			world:ClearPlayer(player)
			expectEqual(world:GetStationRuntimeModelCount("station_01"), 0)
			expectEqual(#stations:GetStationById("station_01").PlacedItems:GetChildren(), 0)
			stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "promoted owner receives clean PlacedItems after release",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local assigned: { Player } = {}
			for index = 1, 8 do
				assigned[index] = fakePlayer(index)
				stations:AssignPlayer(assigned[index])
			end
			local waiting = fakePlayer(9)
			expect(stations:AssignPlayer(waiting).Waiting, "Ninth player must wait")
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			world:SpawnAcceptedPlacement(assigned[1], "parcel", placementAt(0, 0, 0))
			expectEqual(#stations:GetStationById("station_01").PlacedItems:GetChildren(), 1)

			stations:SetCallbacks({
				OnReleased = function(_player: Player, station: any)
					world:ClearStation(station.Id)
				end,
			})
			local released = stations:ReleasePlayer(assigned[1])
			expectEqual(released.PromotedPlayer, waiting)
			expectEqual(stations:GetStationId(waiting), "station_01")
			expectEqual(world:GetStationRuntimeModelCount("station_01"), 0)
			expectEqual(#stations:GetStationById("station_01").PlacedItems:GetChildren(), 0,
				"Promoted owner must inherit an empty authored runtime folder")

			expect(world:SpawnAcceptedPlacement(waiting, "parcel", placementAt(1, 0, 0)) ~= nil,
				"Promoted owner must be able to create a fresh first proxy")
			expectEqual(world:GetStationRuntimeModelCount("station_01"), 1)
			expectEqual(#stations:GetStationById("station_01").PlacedItems:GetChildren(), 1)
			world:ClearPlayer(waiting)
			stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "unassigned player cannot create world item",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			expectEqual(world:SpawnAcceptedPlacement(fakePlayer(9), "parcel", placementAt(0, 0, 0)), nil)
			for index = 1, 8 do expectEqual(world:GetStationRuntimeModelCount(string.format("station_%02d", index)), 0) end
			stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "station clear removes externally stale descendants",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local stale = Instance.new("Model")
			stale.Name = "StaleRuntime"
			stale.Parent = stations:GetStationById("station_05").PlacedItems
			local template = Instance.new("Part")
			local world = WorldItemService.Create(template, stations)
			world:ClearStation("station_05")
			expectEqual(#stations:GetStationById("station_05").PlacedItems:GetChildren(), 0)
			stations:Destroy(); template:Destroy(); root:Destroy()
		end,
	},
})

addSuite("Immutable shipment records", {
	{
		Name = "capture copies all authoritative values and deterministic clock",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1234.5 end)
			local player = fakePlayer(51, "  Test   Player  ")
			local round = roundRecord(51, 7, "station_05", { placedItem() })
			local record, reason = service:Capture(player, round)
			expectEqual(reason, "CAPTURED")
			expect(record ~= nil, "Record expected")
			expectEqual(record.OutcomeId, "51:phase04-test:7")
			expectEqual(record.ShipmentId, record.OutcomeId)
			expectEqual(record.PlayerDisplayName, "Test Player")
			expectEqual(record.StationId, "station_05")
			expectEqual(record.CreatedAt, 1234.5)
		end,
	},
	{
		Name = "server values and every placed-item field copy exactly",
		Run = function()
			local firstItem = placedItem("long_package", 1)
			firstItem.OriginX = 4
			firstItem.OriginY = 2
			firstItem.OriginZ = 3
			local secondItem = placedItem("parcel", 0)
			secondItem.OriginX = 1
			secondItem.OriginY = 0
			secondItem.OriginZ = 2
			local sourceItems = { firstItem, secondItem }
			local round = roundRecord(72, 9, "station_07", sourceItems)
			round.BaseValueSum = 321
			round.ShipmentValue = 654
			local service = ShipmentRecordService.Create(function(): number return 987.25 end)
			local record, reason = service:Capture(fakePlayer(72, "  Exact   Player  "), round)

			expectEqual(reason, "CAPTURED")
			expectEqual(record.OutcomeId, "72:phase04-test:9")
			expectEqual(record.ShipmentId, record.OutcomeId)
			expectEqual(record.PlayerUserId, 72)
			expectEqual(record.PlayerDisplayName, "Exact Player")
			expectEqual(record.StationId, "station_07")
			expectEqual(record.RoundId, 9)
			expectEqual(record.ItemCount, 2)
			expectEqual(record.BaseValueSum, 321)
			expectEqual(record.ShipmentValue, 654)
			expectEqual(record.Multiplier, RoundConfig.MULTIPLIERS[2])
			expectEqual(record.CreatedAt, 987.25)
			expect(not record.PerfectShipment, "Two items cannot be a perfect shipment")
			expectEqual(#record.PlacedItems, #sourceItems)
			for index, source in ipairs(sourceItems) do
				local copied = record.PlacedItems[index]
				for _, field in ipairs({
					"ItemId", "ShapeId", "QuarterTurns",
					"OriginX", "OriginY", "OriginZ",
					"ColorR", "ColorG", "ColorB",
				}) do
					expectEqual(copied[field], source[field], string.format("Placed item %d field %s", index, field))
				end
			end
		end,
	},
	{
		Name = "record and placed-item graph are immutable",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record = service:Capture(fakePlayer(1), roundRecord(1, 1, "station_01", { placedItem() }))
			expect(table.isfrozen(record), "Record must be frozen")
			expect(table.isfrozen(record.PlacedItems), "Placed array must be frozen")
			expect(table.isfrozen(record.PlacedItems[1]), "Placed item must be frozen")
			expectError(function() (record :: any).ShipmentValue = 999 end)
			expectError(function() (record.PlacedItems[1] :: any).OriginX = 4 end)
		end,
	},
	{
		Name = "source mutation cannot change captured presentation",
		Run = function()
			local sourceItem = placedItem()
			local sourceItems = { sourceItem }
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record = service:Capture(fakePlayer(1), roundRecord(1, 1, "station_01", sourceItems))
			sourceItem.OriginX = 4
			table.clear(sourceItems)
			expectEqual(record.PlacedItems[1].OriginX, 0)
			expectEqual(#record.PlacedItems, 1)
		end,
	},
	{
		Name = "record contains no Player reference and survives actual round restart",
		Run = function()
			local harness = newEightRoundHarness()
			local player = harness.Players[1]
			local round = harness.Service:StartRound(player)
			local sourceItem = placedItem("long_package", 1)
			sourceItem.OriginX = 3
			sourceItem.OriginY = 1
			sourceItem.OriginZ = 4
			round.PlacedItems = { sourceItem }
			round.ItemCount = 1
			round.BaseValueSum = 35
			round.ShipmentValue = 50
			harness.Service:_enterShipping(player, "DETACHED_RECORD")
			expectEqual(#harness.ShipmentEvents, 1)
			local record = harness.ShipmentEvents[1]

			expect(harness.Service:HandleCapturedTimer(
				player,
				round.RoundId,
				round.StateVersion,
				"Shipping"
			), "Shipping presentation must reach Results")
			local restarted, reason = harness.Service:HandleRestart(player, {
				RoundId = round.RoundId,
				StateVersion = round.StateVersion,
				ClientSequence = 1,
			})
			expect(restarted, "Round restart expected")
			expectEqual(reason, "RESTARTED")
			table.clear(round.PlacedItems)
			round.ItemCount = 0
			round.BaseValueSum = 0
			round.ShipmentValue = 0

			local seen: { [any]: boolean } = {}
			local function expectNoPlayerReference(value: any)
				expect(value ~= player, "ShipmentRecord must not retain a Player reference")
				if type(value) ~= "table" or seen[value] then
					return
				end
				seen[value] = true
				for key, nested in pairs(value) do
					expectNoPlayerReference(key)
					expectNoPlayerReference(nested)
				end
			end
			expectNoPlayerReference(record)
			expectEqual(harness.Service:GetRound(player).RoundId, 2)
			expectEqual(record.OutcomeId, string.format("%d:phase04-test-session:1", player.UserId))
			expectEqual(record.ShipmentId, record.OutcomeId)
			expectEqual(record.StationId, "station_01")
			expectEqual(record.ItemCount, 1)
			expectEqual(record.BaseValueSum, 35)
			expectEqual(record.ShipmentValue, 50)
			expectEqual(#record.PlacedItems, 1)
			expectEqual(record.PlacedItems[1].OriginX, 3)
			expectEqual(record.PlacedItems[1].OriginY, 1)
			expectEqual(record.PlacedItems[1].OriginZ, 4)
		end,
	},
	{
		Name = "duplicate capture is idempotently rejected",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local player = fakePlayer(1)
			local round = roundRecord(1, 1, "station_01", {})
			expect(service:Capture(player, round) ~= nil, "First capture expected")
			local duplicate, reason = service:Capture(player, round)
			expectEqual(duplicate, nil)
			expectEqual(reason, "DUPLICATE_SHIPMENT")
			expectEqual(service:GetSeenCount(), 1)
		end,
	},
	{
		Name = "same player may capture a later round",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local player = fakePlayer(1)
			expect(service:Capture(player, roundRecord(1, 1, "station_01", {})) ~= nil, "Round one expected")
			expect(service:Capture(player, roundRecord(1, 2, "station_01", {})) ~= nil, "Round two expected")
			expectEqual(service:GetSeenCount(), 2)
		end,
	},
	{
		Name = "player mismatch is rejected",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record, reason = service:Capture(fakePlayer(2), roundRecord(1, 1, "station_01", {}))
			expectEqual(record, nil)
			expectEqual(reason, "PLAYER_MISMATCH")
		end,
	},
	{
		Name = "missing station is rejected",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record, reason = service:Capture(fakePlayer(1), roundRecord(1, 1, "", {}))
			expectEqual(record, nil)
			expectEqual(reason, "MISSING_STATION")
		end,
	},
	{
		Name = "placed-item count mismatch is rejected",
		Run = function()
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local round = roundRecord(1, 1, "station_01", {})
			round.ItemCount = 1
			local record, reason = service:Capture(fakePlayer(1), round)
			expectEqual(record, nil)
			expectEqual(reason, "PLACED_ITEM_COUNT_MISMATCH")
		end,
	},
	{
		Name = "perfect shipment is derived from maximum item count",
		Run = function()
			local items: { any } = {}
			for _ = 1, RoundConfig.MAXIMUM_ITEMS do table.insert(items, placedItem()) end
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record = service:Capture(fakePlayer(1), roundRecord(1, 1, "station_01", items))
			expect(record.PerfectShipment, "Maximum item shipment must be perfect")
		end,
	},
	{
		Name = "multiplier is derived rather than trusted from caller",
		Run = function()
			local items = { placedItem(), placedItem(), placedItem(), placedItem(), placedItem(), placedItem() }
			local service = ShipmentRecordService.Create(function(): number return 1 end)
			local record = service:Capture(fakePlayer(1), roundRecord(1, 1, "station_01", items))
			expect(record.Multiplier > 1, "Six-item shipment must use risk multiplier")
		end,
	},
})

addSuite("Shared showcase queue and rendering", {
	{
		Name = "service starts empty with deterministic observability",
		Run = function()
			local harness = newShowcaseHarness(false)
			expectEqual(harness.Service:GetActiveCount(), 0)
			expectEqual(harness.Service:GetPendingCount(), 0)
			expectEqual(harness.Runtime:GetAttribute("ActiveShowcases"), 0)
			expectEqual(harness.Runtime:GetAttribute("PendingShowcases"), 0)
			expect(not harness.Service:IsUpdateLoopActive(), "Manual-clock harness must not connect")
			harness:Destroy()
		end,
	},
	{
		Name = "launch spacing fills three active and leaves fourth queued",
		Run = function()
			local harness = newShowcaseHarness(false)
			for index = 1, 4 do expect(harness.Service:Submit(shipmentRecord(index)), "Submission expected") end
			expectEqual(harness.Service:GetActiveCount(), 1)
			expectEqual(harness.Service:GetPendingCount(), 3)
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			expectEqual(harness.Service:GetActiveCount(), 3)
			expectEqual(harness.Service:GetPendingCount(), 1)
			expectEqual(#runtimeModels(harness.Runtime), 3)
			harness:Destroy()
		end,
	},
	{
		Name = "same-frame receipt order is stable FIFO",
		Run = function()
			local harness = newShowcaseHarness(false)
			for index = 1, 5 do harness.Service:Submit(shipmentRecord(index)) end
			expectEqual(runtimeModels(harness.Runtime)[1]:GetAttribute("ShipmentId"), "test:001")
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			local firstWave = runtimeModels(harness.Runtime)
			for index = 1, 3 do expectEqual(firstWave[index]:GetAttribute("ShipmentId"), string.format("test:%03d", index)) end
			harness.Service:Step(7.5)
			local advanced = runtimeModels(harness.Runtime)
			for index, expected in ipairs({ "test:002", "test:003", "test:004" }) do
				expectEqual(advanced[index]:GetAttribute("ShipmentId"), expected)
			end
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			local finalWave = runtimeModels(harness.Runtime)
			for index, expected in ipairs({ "test:003", "test:004", "test:005" }) do
				expectEqual(finalWave[index]:GetAttribute("ShipmentId"), expected)
			end
			harness:Destroy()
		end,
	},
	{
		Name = "duplicate shipment is ignored without queue mutation",
		Run = function()
			local harness = newShowcaseHarness(false)
			local record = shipmentRecord(1)
			expect(harness.Service:Submit(record), "First submit expected")
			local accepted, reason = harness.Service:Submit(record)
			expect(not accepted, "Duplicate must fail")
			expectEqual(reason, "DUPLICATE_SHIPMENT")
			expectEqual(harness.Service:GetSeenCount(), 1)
			expectEqual(harness.Service:GetActiveCount(), 1)
			harness:Destroy()
		end,
	},
	{
		Name = "completion removes active model and advances queue",
		Run = function()
			local harness = newShowcaseHarness(false)
			for index = 1, 2 do harness.Service:Submit(shipmentRecord(index)) end
			harness.Service:Step(10)
			expectEqual(harness.Service:GetActiveCount(), 1)
			expectEqual(harness.Service:GetPendingCount(), 0)
			expectEqual(runtimeModels(harness.Runtime)[1]:GetAttribute("ShipmentId"), "test:002")
			harness:Destroy()
		end,
	},
	{
		Name = "record remains active without player lifetime dependency",
		Run = function()
			local harness = newShowcaseHarness(false)
			local record = shipmentRecord(1)
			harness.Service:Submit(record)
			record = nil :: any
			expectEqual(harness.Service:GetActiveCount(), 1)
			expectEqual(runtimeModels(harness.Runtime)[1]:GetAttribute("ShipmentId"), "test:001")
			harness:Destroy()
		end,
	},
	{
		Name = "visual overflow discards only newest cosmetic request",
		Run = function()
			local harness = newShowcaseHarness(false)
			local capacity = ShowcaseService.MAX_ACTIVE + ShowcaseService.MAX_PENDING
			expect(harness.Service:Submit(shipmentRecord(1)), "First active submit expected")
			expect(harness.Service:Submit(shipmentRecord(2)), "Second pending submit expected")
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			expect(harness.Service:Submit(shipmentRecord(3)), "Third pending submit expected")
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			for index = 4, capacity do expect(harness.Service:Submit(shipmentRecord(index)), "Within-capacity submit expected") end
			expectEqual(harness.Service:GetActiveCount(), ShowcaseService.MAX_ACTIVE)
			expectEqual(harness.Service:GetPendingCount(), ShowcaseService.MAX_PENDING)
			local overflowRecord = shipmentRecord(capacity + 1, 9999, 10)
			local accepted, reason = harness.Service:Submit(overflowRecord)
			expect(not accepted, "Overflow cosmetic request must be rejected")
			expectEqual(reason, "QUEUE_FULL")
			expectEqual(overflowRecord.ShipmentValue, 9999, "Gameplay record must remain unchanged")
			expectEqual(harness.Service:GetSeenCount(), capacity + 1)
			expectEqual(harness.Runtime:GetAttribute("OverflowCount"), 1)
			harness:Destroy()
		end,
	},
	{
		Name = "repeated overflow rejects emit exactly one concise warning",
		Run = function()
			local warnings: { string } = {}
			local harness = newShowcaseHarness(false, function(message: string)
				table.insert(warnings, message)
			end)
			local capacity = ShowcaseService.MAX_ACTIVE + ShowcaseService.MAX_PENDING
			expect(harness.Service:Submit(shipmentRecord(1)), "First active submit expected")
			expect(harness.Service:Submit(shipmentRecord(2)), "Second pending submit expected")
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			expect(harness.Service:Submit(shipmentRecord(3)), "Third pending submit expected")
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			for index = 4, capacity do
				expect(harness.Service:Submit(shipmentRecord(index)), "Within-capacity submit expected")
			end

			for index = capacity + 1, capacity + 3 do
				local accepted, reason = harness.Service:Submit(shipmentRecord(index))
				expect(not accepted, "Every over-capacity cosmetic request must be rejected")
				expectEqual(reason, "QUEUE_FULL")
			end
			expectEqual(#warnings, 1, "Overflow warning must be one-shot")
			expectEqual(warnings[1],
				"[ONE_MORE_ITEM][Showcase] visual queue full; newest cosmetic shipment discarded")
			expectEqual(harness.Runtime:GetAttribute("OverflowCount"), 3)
			expectEqual(harness.Service:GetSeenCount(), capacity + 3)
			harness:Destroy()
		end,
	},
	{
		Name = "rendering caps item proxies at ten",
		Run = function()
			local harness = newShowcaseHarness(false)
			harness.Service:Submit(shipmentRecord(1, 1000, 12))
			local model = runtimeModels(harness.Runtime)[1]
			local proxies = 0
			for _, child in ipairs(model:GetChildren()) do
				if string.match(child.Name, "^ItemProxy_") then proxies += 1 end
			end
			expectEqual(proxies, 10)
			harness:Destroy()
		end,
	},
	{
		Name = "rendered proxy preserves color and rotated bounds",
		Run = function()
			local harness = newShowcaseHarness(false)
			local record = shipmentRecord(1, 100, 1, "long_package", 1)
			harness.Service:Submit(record)
			local proxy = requireChild(runtimeModels(harness.Runtime)[1], "ItemProxy_01", "BasePart") :: BasePart
			expectColorNear(proxy.Color, Color3.new(record.PlacedItems[1].ColorR, record.PlacedItems[1].ColorG, record.PlacedItems[1].ColorB), 0.00001)
			expect(proxy.Size.Z > proxy.Size.X, "Quarter-turn long package must rotate its X/Z bounds")
			harness:Destroy()
		end,
	},
	{
		Name = "temporary model has no scripts and safe physical properties",
		Run = function()
			local harness = newShowcaseHarness(false)
			harness.Service:Submit(shipmentRecord(1, 100, 3))
			local model = runtimeModels(harness.Runtime)[1]
			for _, descendant in ipairs(model:GetDescendants()) do
				expect(not descendant:IsA("LuaSourceContainer"), "Runtime showcase may not contain scripts")
				if descendant:IsA("BasePart") then
					expect(descendant.Anchored, "Runtime part must be anchored")
					expect(not descendant.CanCollide and not descendant.CanTouch and not descendant.CanQuery, "Runtime part must be non-interactive")
				end
			end
			harness:Destroy()
		end,
	},
	{
		Name = "labels render immutable shipment fields",
		Run = function()
			local harness = newShowcaseHarness(false)
			local record = shipmentRecord(1, 725, 8)
			harness.Service:Submit(record)
			local model = runtimeModels(harness.Runtime)[1]
			expectEqual((requireDescendant(model, "PlayerName", "TextLabel") :: TextLabel).Text, record.PlayerDisplayName)
			expectEqual((requireDescendant(model, "ShipmentValue", "TextLabel") :: TextLabel).Text, "725 TAPE")
			expectEqual((requireDescendant(model, "ItemCount", "TextLabel") :: TextLabel).Text, "8 ITEMS")
			harness:Destroy()
		end,
	},
	{
		Name = "manual step moves model along authored path",
		Run = function()
			local harness = newShowcaseHarness(false)
			harness.Service:Submit(shipmentRecord(1))
			local model = runtimeModels(harness.Runtime)[1]
			local start = model:GetPivot().Position
			harness.Service:Step(0.6)
			local lifted = model:GetPivot().Position
			harness.Service:Step(4.5)
			local looped = model:GetPivot().Position
			expect((lifted - start).Magnitude > 0.1, "Lift must move showcase")
			expect((looped - lifted).Magnitude > 0.1, "Loop must move showcase")
			harness:Destroy()
		end,
	},
	{
		Name = "invalid manual delta fails visibly",
		Run = function()
			local harness = newShowcaseHarness(false)
			expectError(function() harness.Service:Step(-1) end, "deltaTime")
			expectError(function() harness.Service:Step(0 / 0) end, "deltaTime")
			harness:Destroy()
		end,
	},
	{
		Name = "automatic loop starts on demand and stops when empty",
		Run = function()
			local harness = newShowcaseHarness(true)
			harness.Service:Submit(shipmentRecord(1))
			expect(harness.Service:IsUpdateLoopActive(), "Heartbeat loop must start")
			harness.Service:Step(10)
			expect(not harness.Service:IsUpdateLoopActive(), "Heartbeat loop must stop")
			expectEqual(#harness.Runtime:GetChildren(), 0)
			harness:Destroy()
		end,
	},
	{
		Name = "twelve-shipment stress remains bounded and drains FIFO",
		Run = function()
			local harness = newShowcaseHarness(false)
			for index = 1, 12 do harness.Service:Submit(shipmentRecord(index, index * 100, (index % 10) + 1)) end
			expectEqual(harness.Service:GetActiveCount(), 1)
			expectEqual(harness.Service:GetPendingCount(), 11)
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
			expectEqual(harness.Service:GetActiveCount(), 3)
			expectEqual(harness.Service:GetPendingCount(), 9)
			local expectedStart = 1
			for _ = 1, 4 do
				local active = runtimeModels(harness.Runtime)
				for offset, model in ipairs(active) do
					expectEqual(model:GetAttribute("ShipmentId"), string.format("test:%03d", expectedStart + offset - 1))
				end
				harness.Service:Step(10)
				expectedStart += #active
				expect(harness.Service:GetActiveCount() <= 3, "Active count must remain bounded")
				if harness.Service:GetPendingCount() > 0 then
					harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
					harness.Service:Step(ShowcaseService.LAUNCH_SPACING)
				end
			end
			expectEqual(harness.Service:GetActiveCount(), 0)
			expectEqual(harness.Service:GetPendingCount(), 0)
			expectEqual(#harness.Runtime:GetChildren(), 0)
			harness:Destroy()
		end,
	},
	{
		Name = "destroy removes active pending and runtime descendants",
		Run = function()
			local harness = newShowcaseHarness(false)
			for index = 1, 8 do harness.Service:Submit(shipmentRecord(index)) end
			harness.Service:Destroy()
			expectEqual(harness.Service:GetActiveCount(), 0)
			expectEqual(harness.Service:GetPendingCount(), 0)
			expectEqual(#harness.Runtime:GetChildren(), 0)
			harness.Template:Destroy(); harness.Entry:Destroy(); harness.PathNodes:Destroy(); harness.Runtime:Destroy()
		end,
	},
})

addSuite("Server-best board", {
	{
		Name = "empty board renders fallback",
		Run = function()
			local display = newBestDisplay()
			local service = ServerBestService.Create(display)
			expectEqual((requireChild(display, "PlayerName", "TextLabel") :: TextLabel).Text, "NO SHIPMENT YET")
			expectEqual((requireChild(display, "ShipmentValue", "TextLabel") :: TextLabel).Text, "0 TAPE")
			expectEqual(service:GetBest(), nil)
			display:Destroy()
		end,
	},
	{
		Name = "first unique shipment becomes best",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			local unique, best = service:Consider(shipmentRecord(1, 100, 2))
			expect(unique and best, "First record must become best")
			expectEqual(service:GetBest().ShipmentId, "test:001")
			display:Destroy()
		end,
	},
	{
		Name = "lower value does not replace",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			service:Consider(shipmentRecord(1, 200, 2))
			local _, best = service:Consider(shipmentRecord(2, 199, 10))
			expect(not best, "Lower value must not replace")
			expectEqual(service:GetBest().ShipmentId, "test:001")
			display:Destroy()
		end,
	},
	{
		Name = "higher value replaces",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			service:Consider(shipmentRecord(1, 200, 8))
			local _, best = service:Consider(shipmentRecord(2, 201, 1))
			expect(best, "Higher value must replace")
			expectEqual(service:GetBest().ShipmentId, "test:002")
			display:Destroy()
		end,
	},
	{
		Name = "value tie uses item count",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			service:Consider(shipmentRecord(1, 200, 4))
			local _, best = service:Consider(shipmentRecord(2, 200, 5))
			expect(best, "Higher item count must break value tie")
			expectEqual(service:GetBest().ShipmentId, "test:002")
			display:Destroy()
		end,
	},
	{
		Name = "complete tie preserves earlier shipment",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			service:Consider(shipmentRecord(1, 200, 5))
			local _, best = service:Consider(shipmentRecord(2, 200, 5))
			expect(not best, "Complete tie must preserve earlier")
			expectEqual(service:GetBest().ShipmentId, "test:001")
			display:Destroy()
		end,
	},
	{
		Name = "duplicate cannot update twice",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			local record = shipmentRecord(1, 200, 5)
			service:Consider(record)
			local unique, best = service:Consider(record)
			expect(not unique and not best, "Duplicate must be ignored")
			expectEqual(service:GetSeenCount(), 1)
			display:Destroy()
		end,
	},
	{
		Name = "best shipment persists after its player leaves",
		Run = function()
			local root = cloneStationsRoot()
			local stations = StationService.Create(root)
			local departing = fakePlayer(81, "Arena Champion")
			stations:AssignPlayer(departing)
			local source = roundRecord(81, 4, "station_01", { placedItem(), placedItem() })
			source.BaseValueSum = 80
			source.ShipmentValue = 125
			local captureService = ShipmentRecordService.Create(function(): number return 200 end)
			local record = captureService:Capture(departing, source)
			local display = newBestDisplay()
			local service = ServerBestService.Create(display)
			local unique, best = service:Consider(record)
			expect(unique and best, "Departing player's shipment must first become best")

			expect(stations:ReleasePlayer(departing).Released, "Player release expected")
			expectEqual(stations:GetStationId(departing), nil)
			expectEqual(service:GetBest(), record, "Player lifetime must not erase immutable best record")
			expectEqual((requireChild(display, "PlayerName", "TextLabel") :: TextLabel).Text, "Arena Champion")
			expectEqual((requireChild(display, "ShipmentValue", "TextLabel") :: TextLabel).Text, "125 TAPE")
			expectEqual(service:GetSeenCount(), 1)
			stations:Destroy(); display:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "reset clears best and board attributes",
		Run = function()
			local display = newBestDisplay(); local service = ServerBestService.Create(display)
			service:Consider(shipmentRecord(1, 200, 5))
			service:Reset()
			expectEqual(service:GetBest(), nil)
			expectEqual(service:GetSeenCount(), 0)
			expectEqual(display:GetAttribute("BestShipmentId"), nil)
			expectEqual((requireChild(display, "PlayerName", "TextLabel") :: TextLabel).Text, "NO SHIPMENT YET")
			display:Destroy()
		end,
	},
})

local function withDisplayService(callback: (any, any, Instance) -> ())
	local root = cloneStationsRoot()
	local stations = StationService.Create(root)
	local displays = StationDisplayService.Create(stations)
	callback(displays, stations, root)
	stations:Destroy()
	root:Destroy()
end

addSuite("Station owner and risk displays", {
	{
		Name = "all stations initialize AVAILABLE",
		Run = function()
			withDisplayService(function(_displays: any, _stations: any, root: Instance)
				for index = 1, 8 do
					local model = stationModel(root, index)
					expectEqual(stationLabel(model, "RoundStatus").Text, "AVAILABLE")
					expectEqual(stationLabel(model, "StationNumber").Text, string.format("%02d", index))
					expectEqual(model:GetAttribute("RoundDisplayState"), "AVAILABLE")
				end
			end)
		end,
	},
	{
		Name = "owner state sanitizes name and records authority",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				local player = fakePlayer(44, "  <Owner>  ")
				displays:SetOwner(player, "station_04")
				local model = stationModel(root, 4)
				expectEqual(stationLabel(model, "PlayerName").Text, "Owner")
				expectEqual(stationLabel(model, "RoundStatus").Text, "PREPARING")
				expectEqual(model:GetAttribute("OwnerUserId"), 44)
			end)
		end,
	},
	{
		Name = "packing state remains neutral below six items",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_01", "AwaitingPlacement", 5, 125))
				local model = stationModel(root, 1)
				local _, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "PACKING 5 ITEMS")
				expectEqual(stationLabel(model, "RiskValue").Text, "")
				expect(not light.Enabled, "Low-risk light must be off")
			end)
		end,
	},
	{
		Name = "ordinary shipping state is explicit and neutral",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_04", "Shipping", 4, 125))
				local model = stationModel(root, 4)
				local _, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "SHIPPING")
				expectEqual(stationLabel(model, "RiskValue").Text, "")
				expectEqual(model:GetAttribute("RoundDisplayState"), "SHIPPING")
				expectEqual(model:GetAttribute("DisplayedItemCount"), 4)
				expectEqual(model:GetAttribute("DisplayedRiskValue"), 125)
				expect(not light.Enabled, "Ordinary shipment must not light a high-risk indicator")
			end)
		end,
	},
	{
		Name = "six-item state is amber",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_02", "Decision", 6, 300))
				local model = stationModel(root, 2); local part, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "RISKING 6 ITEMS")
				expectColorNear(part.Color, Color3.fromRGB(255, 178, 26), 0.00001)
				expect(light.Enabled, "Amber light expected")
			end)
		end,
	},
	{
		Name = "eight-item state is red",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_03", "Decision", 8, 700))
				local model = stationModel(root, 3); local part, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "HIGH RISK - 8 ITEMS")
				expectColorNear(part.Color, Color3.fromRGB(255, 75, 62), 0.00001)
				expect(light.Enabled, "Red light expected")
			end)
		end,
	},
	{
		Name = "ten-item state is gold",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_05", "Shipping", 10, 1500))
				local model = stationModel(root, 5); local part, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "IMPOSSIBLE SHIPMENT")
				expectColorNear(part.Color, Color3.fromRGB(255, 215, 72), 0.00001)
				expect(light.Enabled, "Gold light expected")
			end)
		end,
	},
	{
		Name = "failing state is explicit",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_06", "Failing", 8, 0, 800))
				expectEqual(stationLabel(stationModel(root, 6), "RoundStatus").Text, "TOO MUCH")
			end)
		end,
	},
	{
		Name = "results distinguish success and failure",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_07", "Results", 7, 600, 0))
				expectEqual(stationLabel(stationModel(root, 7), "RoundStatus").Text, "SHIPMENT COMPLETE")
				displays:ApplyRoundState(roundStateEvent("station_08", "Results", 7, 0, 600))
				expectEqual(stationLabel(stationModel(root, 8), "RoundStatus").Text, "ROUND FAILED")
			end)
		end,
	},
	{
		Name = "release resets owner status risk and attributes",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				local model = stationModel(root, 1)
				displays:SetOwner(fakePlayer(1), "station_01")
				displays:ApplyRoundState(roundStateEvent("station_01", "Decision", 8, 700))
				displays:ReleaseStation("station_01")
				local _, light = stationIndicator(model)
				expectEqual(stationLabel(model, "RoundStatus").Text, "AVAILABLE")
				expectEqual(stationLabel(model, "RiskValue").Text, "")
				expectEqual(model:GetAttribute("OwnerUserId"), nil)
				expectEqual(model:GetAttribute("RoundDisplayState"), "AVAILABLE")
				expect(not light.Enabled, "Release must disable light")
			end)
		end,
	},
	{
		Name = "unknown station event cannot mutate authored displays",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				displays:ApplyRoundState(roundStateEvent("station_99", "Failing", 10, 0, 1000))
				for index = 1, 8 do expectEqual(stationLabel(stationModel(root, index), "RoundStatus").Text, "AVAILABLE") end
			end)
		end,
	},
})

addSuite("Arena announcements", {
	{
		Name = "display starts neutral",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "PACK. SHIP. RISK ONE MORE.")
			expectEqual(display:GetAttribute("AnnouncementPriority"), 0)
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "six-item milestone announces risk",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			expect(service:AnnounceHighRisk({ PlayerUserId = 1, PlayerDisplayName = "Player One", StationId = "station_01", RoundId = 1, ItemCount = 6, ShipmentValue = 300 }), "Announcement expected")
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "PLAYER ONE IS RISKING 6 ITEMS")
			expectEqual(display:GetAttribute("AnnouncementPriority"), 2)
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "server best shipment receives maximum priority",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			expect(service:AnnounceShipment(shipmentRecord(1, 900, 8), true), "Announcement expected")
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "NEW SERVER BEST")
			expectEqual(display:GetAttribute("AnnouncementPriority"), 3)
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "ordinary shipment announces owner count and value",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			local record = shipmentRecord(1, 500, 5)
			expect(service:AnnounceShipment(record, false), "Announcement expected")
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "PLAYER 1 SHIPPED 5 ITEMS")
			expectEqual((requireChild(display, "Detail", "TextLabel") :: TextLabel).Text, "500 TAPE")
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "low-item failure remains quiet",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			expect(not service:AnnounceFailure({ PlayerUserId = 1, PlayerDisplayName = "Player", StationId = "station_01", RoundId = 1, ItemCount = 5, LostValue = 100, Reason = "FAIL" }), "Low-risk failure must stay quiet")
			expectEqual(display:GetAttribute("AnnouncementPriority"), 0)
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "high-risk failure announces loss",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			expect(service:AnnounceFailure({ PlayerUserId = 1, PlayerDisplayName = "Player", StationId = "station_01", RoundId = 1, ItemCount = 8, LostValue = 700, Reason = "FAIL" }), "Failure announcement expected")
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "PLAYER PUSHED TOO FAR")
			expectEqual((requireChild(display, "Detail", "TextLabel") :: TextLabel).Text, "8 ITEMS - 700 TAPE LOST")
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "lower priority cannot overwrite active headline",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			service:AnnounceShipment(shipmentRecord(1, 1000, 10), true)
			expect(not service:AnnounceShipment(shipmentRecord(2, 100, 2), false), "Lower priority must be rejected")
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "NEW SERVER BEST")
			service:Destroy(); display:Destroy()
		end,
	},
	{
		Name = "reset invalidates delayed announcement and restores neutral",
		Run = function()
			local display = newAnnouncementDisplay(); local service = ArenaAnnouncementService.Create(display)
			service:AnnounceShipment(shipmentRecord(1, 1000, 10), true)
			service:Reset()
			expectEqual((requireChild(display, "Headline", "TextLabel") :: TextLabel).Text, "PACK. SHIP. RISK ONE MORE.")
			expectEqual(display:GetAttribute("AnnouncementPriority"), 0)
			service:Destroy(); display:Destroy()
		end,
	},
})

addSuite("Bounded cleanup cycles", {
	{
		Name = "ten station release and reassignment cycles return baseline",
		Run = function()
			local root = cloneStationsRoot()
			local service = StationService.Create(root)
			for cycle = 1, 10 do
				local player = fakePlayer(500 + cycle)
				expectEqual(service:AssignPlayer(player).StationId, "station_01")
				expect(service:ReleasePlayer(player).Released, "Cycle release expected")
				expectEqual(service:GetStationId(player), nil)
				expect(not getFakePlayerState(player).Connected, "Cycle connection must be gone")
			end
			for _, station in ipairs(service:GetStations()) do expectEqual(service:GetOwner(station.Model), nil) end
			service:Destroy(); root:Destroy()
		end,
	},
	{
		Name = "ten showcase cycles return runtime folder to baseline",
		Run = function()
			local harness = newShowcaseHarness(false)
			for cycle = 1, 10 do
				harness.Service:Submit(shipmentRecord(cycle))
				expectEqual(harness.Service:GetActiveCount(), 1)
				harness.Service:Step(10)
				expectEqual(harness.Service:GetActiveCount(), 0)
				expectEqual(#harness.Runtime:GetChildren(), 0)
			end
			expectEqual(harness.Service:GetSeenCount(), 10)
			expect(not harness.Service:IsUpdateLoopActive(), "Manual loop must remain disconnected")
			harness:Destroy()
		end,
	},
	{
		Name = "ten display resets leave every runtime station neutral",
		Run = function()
			withDisplayService(function(displays: any, _stations: any, root: Instance)
				for cycle = 1, 10 do
					local index = ((cycle - 1) % 8) + 1
					local stationId = string.format("station_%02d", index)
					displays:SetOwner(fakePlayer(cycle), stationId)
					displays:ApplyRoundState(roundStateEvent(stationId, "Decision", 8, 700))
					displays:ResetAll()
				end
				for index = 1, 8 do
					local model = stationModel(root, index); local _, light = stationIndicator(model)
					expectEqual(stationLabel(model, "RoundStatus").Text, "AVAILABLE")
					expectEqual(model:GetAttribute("OwnerUserId"), nil)
					expect(not light.Enabled, "Reset light must be off")
				end
			end)
		end,
	},
})

function Phase04TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}
	local seed = RoundConfig.DEVELOPMENT.PHASE04_TEST_SEED
	if type(seed) ~= "number" or seed % 1 ~= 0 then
		error("RoundConfig.DEVELOPMENT.PHASE04_TEST_SEED must be a fixed integer", 2)
	end

	print(string.format("[ONE_MORE_ITEM][Phase04Tests] Starting %d suites seed=%d", #suites, seed))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase04Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase04Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase04Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		seed
	))
	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase04Tests] FAILURE %d: %s", index, failure))
		end
	end
	return {
		Suites = #suites,
		Tests = totalTests,
		Passed = passed,
		Failed = failed,
		Failures = failures,
		DurationSeconds = duration,
		Seed = seed,
	}
end

return table.freeze(Phase04TestSuite)
