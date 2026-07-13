--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controllers = script.Parent:WaitForChild("Controllers")
local CameraController = require(controllers:WaitForChild("CameraController"))
local CharacterController = require(controllers:WaitForChild("CharacterController"))
local ClientRoundStore = require(controllers:WaitForChild("ClientRoundStore"))
local InputController = require(controllers:WaitForChild("InputController"))
local PlacementController = require(controllers:WaitForChild("PlacementController"))
local PresentationTokens = require(controllers:WaitForChild("PresentationTokens"))
local RoundUIController = require(controllers:WaitForChild("RoundUIController"))
local ViewportPreviewController = require(controllers:WaitForChild("ViewportPreviewController"))
local WorldMotionController = require(controllers:WaitForChild("WorldMotionController"))

type Snapshot = ClientRoundStore.Snapshot
type PlacementResponse = ClientRoundStore.PlacementResponse
type Cell = ClientRoundStore.Cell

local function requireChild(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, 10)
	if child == nil then
		error(string.format("ClientBootstrap requires %s.%s", parent:GetFullName(), name), 2)
	end
	return child
end

local function requireRemote(parent: Instance, name: string): RemoteEvent
	local child = requireChild(parent, name)
	if not child:IsA("RemoteEvent") then
		error(string.format("ClientBootstrap requires RemoteEvent %s", child:GetFullName()), 2)
	end
	return child
end

local function requireModel(parent: Instance, name: string): Model
	local child = requireChild(parent, name)
	if not child:IsA("Model") then
		error(string.format("ClientBootstrap requires Model %s", child:GetFullName()), 2)
	end
	return child
end

local function requireViewport(parent: Instance, name: string): ViewportFrame
	local child = requireChild(parent, name)
	if not child:IsA("ViewportFrame") then
		error(string.format("ClientBootstrap requires ViewportFrame %s", child:GetFullName()), 2)
	end
	return child
end

local root = requireChild(ReplicatedStorage, "ONE_MORE_ITEM")
local net = requireChild(root, "Net")
local shared = requireChild(root, "Shared")
local assets = requireChild(root, "Assets")
local developmentAssets = requireChild(assets, "Development")
local templateInstance = requireChild(developmentAssets, "CellBlockTemplate")
if not templateInstance:IsA("BasePart") then
	error("ClientBootstrap requires CellBlockTemplate to be a BasePart")
end
local cellBlockTemplate: BasePart = templateInstance

local DevelopmentItemDefinitions = require(requireChild(requireChild(shared, "Content"), "DevelopmentItemDefinitions"))
local ShapeDefinitions = require(requireChild(requireChild(shared, "Content"), "ShapeDefinitions"))

local clientReadyRequest = requireRemote(net, "ClientReadyRequest")
local placeItemRequest = requireRemote(net, "PlaceItemRequest")
local decisionRequest = requireRemote(net, "DecisionRequest")
local restartRequest = requireRemote(net, "RestartRequest")
local roundSnapshotRemote = requireRemote(net, "RoundSnapshot")
local placementResponseRemote = requireRemote(net, "PlacementResponse")

local worldRoot = requireChild(Workspace, "ONE_MORE_ITEM_WORLD")
local arena = requireChild(worldRoot, "PlaytestArena")
local stations = requireChild(arena, "Stations")
local station = requireModel(stations, "Station_01")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gameplayGuiInstance = playerGui:WaitForChild("ONE_MORE_ITEM_Gameplay", 10)
if gameplayGuiInstance == nil then
	error("ClientBootstrap requires ONE_MORE_ITEM_Gameplay to clone into PlayerGui within 10 seconds")
end
if not gameplayGuiInstance:IsA("ScreenGui") then
	error("ClientBootstrap requires ONE_MORE_ITEM_Gameplay to be a ScreenGui")
end
local gameplayGui: ScreenGui = gameplayGuiInstance
local guiRoot = requireChild(gameplayGui, "Root")
local currentItemCard = requireChild(guiRoot, "CurrentItemCard")
local decisionPanel = requireChild(guiRoot, "DecisionPanel")
local currentViewport = requireViewport(currentItemCard, "ItemViewport")
local nextViewport = requireViewport(decisionPanel, "NextItemViewport")

local function resolveItemName(itemId: string): string
	local definition = DevelopmentItemDefinitions.Get(itemId)
	return if definition ~= nil then definition.DisplayName else string.gsub(itemId, "_", " ")
end

local function getItemColor(itemId: string): Color3
	local definition = DevelopmentItemDefinitions.Get(itemId)
	return if definition ~= nil then definition.Color else PresentationTokens.Color.Amber
end

local function getShapeCells(shapeId: string): { Cell }?
	local shapes = {
		ShapeDefinitions.SingleCube,
		ShapeDefinitions.HorizontalBar2,
		ShapeDefinitions.HorizontalBar3,
		ShapeDefinitions.VerticalColumn3,
		ShapeDefinitions.FlatSquare2x2,
		ShapeDefinitions.FlatL,
		ShapeDefinitions.FlatT,
		ShapeDefinitions.FlatZ,
		ShapeDefinitions.Chair,
		ShapeDefinitions.MediumBlock,
		ShapeDefinitions.LargeIrregular,
	}
	for _, shape in ipairs(shapes) do
		if shape.Id == shapeId then
			return shape.Cells
		end
	end
	return nil
end

local store = ClientRoundStore.new()
local camera = CameraController.new()
local character = CharacterController.new()
local worldMotion = WorldMotionController.new(station)
local roundUI = RoundUIController.new(gameplayGui, resolveItemName)
local viewportPreview = ViewportPreviewController.new(
	currentViewport,
	nextViewport,
	cellBlockTemplate,
	getShapeCells,
	getItemColor
)

local placement = PlacementController.new(placeItemRequest, station, cellBlockTemplate, {
	FitChanged = function(valid: boolean?, x: number?, y: number?, z: number?)
		roundUI:SetFitState(valid, x, y, z)
	end,
	GridFeedback = function(cells: { Cell }, valid: boolean)
		worldMotion:SetGridFeedback(cells, valid)
	end,
	ClearGridFeedback = function()
		worldMotion:ClearGridFeedback()
	end,
	ButtonPressed = function(action: string)
		roundUI:PlayButtonPress(action)
		worldMotion:PressButton(action)
	end,
	PlacementImpact = function(position: Vector3, heavy: boolean)
		worldMotion:PlayPlacementImpact(position, heavy)
		camera:PlayImpulse(if heavy then "HEAVY" else "LIGHT")
	end,
	ServerResponse = function(reason: string, _accepted: boolean)
		roundUI:SetServerResponse(reason)
	end,
	Rejected = function()
		worldMotion:PlayRejected()
	end,
	Observability = function(valid: boolean?, x: number?, y: number?, z: number?)
		script:SetAttribute("GhostValid", valid)
		script:SetAttribute("GhostX", x)
		script:SetAttribute("GhostY", y)
		script:SetAttribute("GhostZ", z)
	end,
})

local decisionSequence = 0
local restartSequence = 0
local previousState: string? = nil
local assigned = false
local destroyed = false
local connections: { RBXScriptConnection } = {}

local function requestDecision(choice: string)
	local snapshot = store:GetSnapshot()
	if snapshot == nil or snapshot.State ~= "Decision" or (choice ~= "SHIP" and choice ~= "ONE_MORE") then
		return
	end
	decisionSequence += 1
	roundUI:PlayButtonPress(choice)
	worldMotion:PressButton(choice)
	decisionRequest:FireServer({
		RoundId = snapshot.RoundId,
		StateVersion = snapshot.StateVersion,
		Choice = choice,
		ClientSequence = decisionSequence,
	})
end

local function requestRestart()
	local snapshot = store:GetSnapshot()
	if snapshot == nil or snapshot.State ~= "Results" or snapshot.StationId ~= "station_01" then
		return
	end
	restartSequence += 1
	roundUI:PlayButtonPress("RESTART")
	restartRequest:FireServer({
		RoundId = snapshot.RoundId,
		StateVersion = snapshot.StateVersion,
		ClientSequence = restartSequence,
	})
end

local input = InputController.new({
	Move = function(deltaX: number, deltaZ: number)
		placement:Move(deltaX, deltaZ)
	end,
	Rotate = function()
		placement:RotateClockwise()
	end,
	Place = function()
		placement:RequestPlacement()
	end,
	Decision = requestDecision,
	Restart = requestRestart,
	PointerRay = function(ray: Ray)
		placement:UpdateFromPointerRay(ray)
	end,
}, roundUI:GetButtons())

local unsubscribe = store:Subscribe(function(snapshot: Snapshot)
	if destroyed then
		return
	end
	local nowAssigned = snapshot.StationId == "station_01"
	if nowAssigned ~= assigned then
		assigned = nowAssigned
		character:SetAssigned(assigned)
		if assigned then
			camera:Activate(station)
		else
			camera:Deactivate()
		end
	end

	if snapshot.State ~= previousState then
		worldMotion:SetState(snapshot.State, previousState)
		if snapshot.State == "Shipping" then
			camera:PlayImpulse("SHIPPING")
		elseif snapshot.State == "Failing" then
			camera:PlayImpulse("FAILURE")
		end
		print(string.format(
			"[ONE_MORE_ITEM][Client] STATE round=%s version=%d state=%s station=%s",
			tostring(snapshot.RoundId),
			snapshot.StateVersion,
			snapshot.State,
			snapshot.StationId
		))
		previousState = snapshot.State
	end
	roundUI:ApplySnapshot(snapshot)
	viewportPreview:ApplySnapshot(snapshot)
	placement:ApplySnapshot(snapshot)

	script:SetAttribute("RoundId", snapshot.RoundId)
	script:SetAttribute("StateVersion", snapshot.StateVersion)
	script:SetAttribute("RoundState", snapshot.State)
	script:SetAttribute("StationId", snapshot.StationId)
	input:RefreshPointer()
end)

table.insert(connections, roundSnapshotRemote.OnClientEvent:Connect(function(snapshot: Snapshot)
	store:ApplySnapshot(snapshot)
end))

table.insert(connections, placementResponseRemote.OnClientEvent:Connect(function(response: PlacementResponse)
	placement:HandleResponse(response)
end))

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	unsubscribe()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	input:Destroy()
	placement:Destroy()
	viewportPreview:Destroy()
	roundUI:Destroy()
	worldMotion:Destroy()
	camera:Destroy()
	character:Destroy()
	store:Destroy()
	script:SetAttribute("Initialized", false)
end

table.insert(connections, script.Destroying:Connect(cleanup))

script:SetAttribute("Initialized", true)
script:SetAttribute("ClientVersion", "phase02")
print("[ONE_MORE_ITEM][Client] READY controls=mouse+keyboard authority=server")
clientReadyRequest:FireServer()
