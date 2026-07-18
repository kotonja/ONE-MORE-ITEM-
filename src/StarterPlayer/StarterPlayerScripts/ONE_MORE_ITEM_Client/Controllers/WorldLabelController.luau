--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local StationDefinitions = require(shared:WaitForChild("World"):WaitForChild("StationDefinitions"))
type StationDefinition = StationDefinitions.Definition

export type VisibilityTier = "Local" | "Adjacent" | "Distant"

type LabelRecord = {
	Index: number,
	StationId: string,
	Station: Model,
	OwnerGui: BillboardGui,
	PlayerName: TextLabel,
	RoundStatus: TextLabel,
	RiskValue: TextLabel,
	StationNumber: TextLabel,
	ShelfGui: BillboardGui,
	RankName: TextLabel,
	CollectionCount: TextLabel,
	OwnerEnabled: boolean,
	OwnerAlwaysOnTop: boolean,
	PlayerNameVisible: boolean,
	RoundStatusVisible: boolean,
	RiskValueVisible: boolean,
	StationNumberVisible: boolean,
	ShelfEnabled: boolean,
	ShelfAlwaysOnTop: boolean,
	RankNameVisible: boolean,
	CollectionCountVisible: boolean,
}

export type Controller = {
	SetAssignedStation: (self: Controller, stationId: string?) -> (),
	Refresh: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_records: { LabelRecord },
	_assignedStationId: string?,
	_assignedIndex: number?,
	_connections: { RBXScriptConnection },
	_cameraConnections: { RBXScriptConnection },
	_camera: Camera?,
	_lastCameraFrame: CFrame?,
	_lastViewport: Vector2?,
	_lastUpdateClock: number,
	_updateEpoch: number,
	_updatePending: boolean,
	_destroyed: boolean,
}

local WorldLabelController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local UPDATE_INTERVAL = 0.5
local POSITION_THRESHOLD = 0.35
local ANGLE_THRESHOLD_COSINE = math.cos(math.rad(1.5))

local DISTANCE_LIMITS: { [VisibilityTier]: number } = table.freeze({
	Local = 84,
	Adjacent = 78,
	Distant = 68,
})

local FACING_LIMITS: { [VisibilityTier]: number } = table.freeze({
	Local = -0.05,
	Adjacent = 0.05,
	Distant = 0.35,
})

local function requireDirect(parent: Instance, name: string, className: string): Instance
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA(className) then
		error(string.format("WorldLabelController requires %s %s.%s", className, parent:GetFullName(), name), 3)
	end
	return child
end

local function resolveRecord(stationsRoot: Instance, definition: StationDefinition): LabelRecord
	local station = StationDefinitions.Resolve(stationsRoot, definition.Id)
	if station == nil then
		error(string.format("WorldLabelController requires authored station %s", definition.ModelName), 3)
	end
	local ownerDisplay = requireDirect(station, "OwnerDisplay", "BasePart")
	local ownerGui = requireDirect(ownerDisplay, "BillboardGui", "BillboardGui") :: BillboardGui
	local collectionShelf = requireDirect(station, "CollectionShelf", "Model")
	local shelfLabel = requireDirect(collectionShelf, "ShelfLabel", "BasePart")
	local shelfGui = requireDirect(shelfLabel, "BillboardGui", "BillboardGui") :: BillboardGui
	local playerName = requireDirect(ownerGui, "PlayerName", "TextLabel") :: TextLabel
	local roundStatus = requireDirect(ownerGui, "RoundStatus", "TextLabel") :: TextLabel
	local riskValue = requireDirect(ownerGui, "RiskValue", "TextLabel") :: TextLabel
	local stationNumber = requireDirect(ownerGui, "StationNumber", "TextLabel") :: TextLabel
	local rankName = requireDirect(shelfGui, "RankName", "TextLabel") :: TextLabel
	local collectionCount = requireDirect(shelfGui, "CollectionCount", "TextLabel") :: TextLabel
	return {
		Index = definition.Index,
		StationId = definition.Id,
		Station = station,
		OwnerGui = ownerGui,
		PlayerName = playerName,
		RoundStatus = roundStatus,
		RiskValue = riskValue,
		StationNumber = stationNumber,
		ShelfGui = shelfGui,
		RankName = rankName,
		CollectionCount = collectionCount,
		OwnerEnabled = ownerGui.Enabled,
		OwnerAlwaysOnTop = ownerGui.AlwaysOnTop,
		PlayerNameVisible = playerName.Visible,
		RoundStatusVisible = roundStatus.Visible,
		RiskValueVisible = riskValue.Visible,
		StationNumberVisible = stationNumber.Visible,
		ShelfEnabled = shelfGui.Enabled,
		ShelfAlwaysOnTop = shelfGui.AlwaysOnTop,
		RankNameVisible = rankName.Visible,
		CollectionCountVisible = collectionCount.Visible,
	}
end

function WorldLabelController.ClassifyStation(
	localIndex: number?,
	targetIndex: number,
	capacity: number
): VisibilityTier
	if localIndex == nil then
		return "Distant"
	end
	if targetIndex == localIndex then
		return "Local"
	end
	local direct = math.abs(targetIndex - localIndex)
	local wrapped = math.min(direct, capacity - direct)
	return if wrapped == 1 then "Adjacent" else "Distant"
end

function WorldLabelController.ShouldShowForView(
	tier: VisibilityTier,
	distance: number,
	facingDot: number,
	authoredMaxDistance: number
): boolean
	local maximumDistance = math.min(DISTANCE_LIMITS[tier], authoredMaxDistance)
	return distance <= maximumDistance and facingDot >= FACING_LIMITS[tier]
end

function WorldLabelController.IsMeaningfulCameraChange(
	previousFrame: CFrame?,
	nextFrame: CFrame,
	previousViewport: Vector2?,
	nextViewport: Vector2
): boolean
	if previousFrame == nil or previousViewport == nil or previousViewport ~= nextViewport then
		return true
	end
	if (previousFrame.Position - nextFrame.Position).Magnitude >= POSITION_THRESHOLD then
		return true
	end
	return previousFrame.LookVector:Dot(nextFrame.LookVector) <= ANGLE_THRESHOLD_COSINE
end

local function guiWorldPosition(gui: BillboardGui): Vector3?
	local adornee = gui.Adornee
	if adornee ~= nil and adornee:IsA("BasePart") then
		return adornee.Position + gui.StudsOffsetWorldSpace
	end
	local parent = gui.Parent
	if parent ~= nil and parent:IsA("BasePart") then
		return parent.Position + gui.StudsOffsetWorldSpace
	end
	return nil
end

local function viewMetrics(camera: Camera, gui: BillboardGui): (number, number)
	local position = guiWorldPosition(gui)
	if position == nil then
		return math.huge, -1
	end
	local offset = position - camera.CFrame.Position
	local distance = offset.Magnitude
	if distance <= 0.001 then
		return distance, 1
	end
	return distance, camera.CFrame.LookVector:Dot(offset.Unit)
end

local function applyRecord(record: LabelRecord, tier: VisibilityTier, camera: Camera?)
	local ownerVisible = false
	local shelfVisible = false
	if camera ~= nil then
		local ownerDistance, ownerFacing = viewMetrics(camera, record.OwnerGui)
		ownerVisible = WorldLabelController.ShouldShowForView(
			tier,
			ownerDistance,
			ownerFacing,
			record.OwnerGui.MaxDistance
		)
		if tier == "Local" then
			local shelfDistance, shelfFacing = viewMetrics(camera, record.ShelfGui)
			shelfVisible = shelfDistance <= math.min(56, record.ShelfGui.MaxDistance) and shelfFacing >= -0.05
		end
	end

	record.OwnerGui.AlwaysOnTop = false
	record.OwnerGui.Enabled = ownerVisible
	record.StationNumber.Visible = ownerVisible
	record.PlayerName.Visible = ownerVisible and tier ~= "Distant"
	record.RoundStatus.Visible = ownerVisible and tier == "Local"
	record.RiskValue.Visible = ownerVisible and tier == "Local" and record.RiskValue.Text ~= ""
	record.ShelfGui.AlwaysOnTop = false
	record.ShelfGui.Enabled = shelfVisible
	record.RankName.Visible = shelfVisible
	record.CollectionCount.Visible = shelfVisible
	record.Station:SetAttribute("WorldLabelTier", tier)
	record.Station:SetAttribute("WorldLabelVisible", ownerVisible)
end

local function cancelPendingUpdate(self: InternalController)
	self._updateEpoch += 1
	self._updatePending = false
end

local function refreshNow(self: InternalController)
	if self._destroyed then
		return
	end
	cancelPendingUpdate(self)
	local camera = Workspace.CurrentCamera
	self._camera = camera
	for _, record in ipairs(self._records) do
		local tier = WorldLabelController.ClassifyStation(
			self._assignedIndex,
			record.Index,
			StationDefinitions.Capacity
		)
		applyRecord(record, tier, camera)
	end
	if camera ~= nil then
		self._lastCameraFrame = camera.CFrame
		self._lastViewport = camera.ViewportSize
	else
		self._lastCameraFrame = nil
		self._lastViewport = nil
	end
	self._lastUpdateClock = os.clock()
end

local function scheduleMeaningfulRefresh(self: InternalController)
	if self._destroyed or self._updatePending then
		return
	end
	local camera = self._camera
	if camera == nil or not WorldLabelController.IsMeaningfulCameraChange(
		self._lastCameraFrame,
		camera.CFrame,
		self._lastViewport,
		camera.ViewportSize
	) then
		return
	end
	self._updatePending = true
	self._updateEpoch += 1
	local epoch = self._updateEpoch
	local remaining = math.max(0, UPDATE_INTERVAL - (os.clock() - self._lastUpdateClock))
	task.delay(remaining, function()
		if self._destroyed or self._updateEpoch ~= epoch then
			return
		end
		self._updatePending = false
		refreshNow(self)
	end)
end

local function disconnectCamera(self: InternalController)
	for _, connection in ipairs(self._cameraConnections) do
		connection:Disconnect()
	end
	table.clear(self._cameraConnections)
	self._camera = nil
end

local function bindCamera(self: InternalController)
	disconnectCamera(self)
	local camera = Workspace.CurrentCamera
	self._camera = camera
	if camera ~= nil then
		table.insert(self._cameraConnections, camera:GetPropertyChangedSignal("CFrame"):Connect(function()
			scheduleMeaningfulRefresh(self)
		end))
		table.insert(self._cameraConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			scheduleMeaningfulRefresh(self)
		end))
	end
	refreshNow(self)
end

function WorldLabelController.new(stationsRoot: Instance): Controller
	local records: { LabelRecord } = {}
	for _, definition in ipairs(StationDefinitions.Ordered) do
		table.insert(records, resolveRecord(stationsRoot, definition))
	end
	local self: InternalController = setmetatable({
		_records = records,
		_assignedStationId = nil,
		_assignedIndex = nil,
		_connections = {},
		_cameraConnections = {},
		_camera = nil,
		_lastCameraFrame = nil,
		_lastViewport = nil,
		_lastUpdateClock = -math.huge,
		_updateEpoch = 0,
		_updatePending = false,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	table.insert(self._connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(self)
	end))
	for _, record in ipairs(records) do
		table.insert(self._connections, record.RiskValue:GetPropertyChangedSignal("Text"):Connect(function()
			if not self._destroyed and record.StationId == self._assignedStationId then
				refreshNow(self)
			end
		end))
	end
	bindCamera(self)
	return self
end

function ControllerMethods.SetAssignedStation(self: InternalController, stationId: string?)
	if self._destroyed then
		return
	end
	local definition = StationDefinitions.Get(stationId)
	local nextStationId = if definition ~= nil then definition.Id else nil
	local nextIndex = if definition ~= nil then definition.Index else nil
	if self._assignedStationId == nextStationId and self._assignedIndex == nextIndex then
		return
	end
	self._assignedStationId = nextStationId
	self._assignedIndex = nextIndex
	refreshNow(self)
end

function ControllerMethods.Refresh(self: InternalController)
	refreshNow(self)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	cancelPendingUpdate(self)
	disconnectCamera(self)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, record in ipairs(self._records) do
		record.OwnerGui.Enabled = record.OwnerEnabled
		record.OwnerGui.AlwaysOnTop = record.OwnerAlwaysOnTop
		record.PlayerName.Visible = record.PlayerNameVisible
		record.RoundStatus.Visible = record.RoundStatusVisible
		record.RiskValue.Visible = record.RiskValueVisible
		record.StationNumber.Visible = record.StationNumberVisible
		record.ShelfGui.Enabled = record.ShelfEnabled
		record.ShelfGui.AlwaysOnTop = record.ShelfAlwaysOnTop
		record.RankName.Visible = record.RankNameVisible
		record.CollectionCount.Visible = record.CollectionCountVisible
		record.Station:SetAttribute("WorldLabelTier", nil)
		record.Station:SetAttribute("WorldLabelVisible", nil)
	end
	table.clear(self._records)
end

return table.freeze(WorldLabelController)
