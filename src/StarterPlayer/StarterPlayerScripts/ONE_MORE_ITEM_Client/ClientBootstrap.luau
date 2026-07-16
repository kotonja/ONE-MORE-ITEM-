--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controllers = script.Parent:WaitForChild("Controllers")
local CameraController = require(controllers:WaitForChild("CameraController"))
local CharacterController = require(controllers:WaitForChild("CharacterController"))
local ClientProfileStore = require(controllers:WaitForChild("ClientProfileStore"))
local ClientRoundStore = require(controllers:WaitForChild("ClientRoundStore"))
local InputController = require(controllers:WaitForChild("InputController"))
local InputModeStore = require(controllers:WaitForChild("InputModeStore"))
local OnboardingUIController = require(controllers:WaitForChild("OnboardingUIController"))
local PresentationTokens = require(controllers:WaitForChild("PresentationTokens"))
local ProfileUIController = require(controllers:WaitForChild("ProfileUIController"))
local ResponsiveLayout = require(controllers:WaitForChild("ResponsiveLayout"))
local ResponsiveUIController = require(controllers:WaitForChild("ResponsiveUIController"))
local RoundUIController = require(controllers:WaitForChild("RoundUIController"))
local StationContextController = require(controllers:WaitForChild("StationContextController"))
local StarterMissionUIController = require(controllers:WaitForChild("StarterMissionUIController"))
local ViewportPreviewController = require(controllers:WaitForChild("ViewportPreviewController"))

type Snapshot = ClientRoundStore.Snapshot
type PlacementResponse = ClientRoundStore.PlacementResponse
type Cell = ClientRoundStore.Cell
type ProfileSnapshot = ClientProfileStore.Snapshot
type InputMode = InputModeStore.InputMode
type LayoutClass = ResponsiveLayout.LayoutClass

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

local function requireViewport(parent: Instance, name: string): ViewportFrame
	local child = requireChild(parent, name)
	if not child:IsA("ViewportFrame") then
		error(string.format("ClientBootstrap requires ViewportFrame %s", child:GetFullName()), 2)
	end
	return child
end

local function requireFrame(parent: Instance, name: string): Frame
	local child = requireChild(parent, name)
	if not child:IsA("Frame") then
		error(string.format("ClientBootstrap requires Frame %s", child:GetFullName()), 2)
	end
	return child
end

local function waitForAuthoredChild(parent: Instance, name: string): Instance
	local resolved = parent:FindFirstChild(name)
	while resolved == nil do
		local added = parent.ChildAdded:Wait()
		if added.Name == name then
			resolved = added
		else
			resolved = parent:FindFirstChild(name)
		end
	end
	return resolved
end

local root = requireChild(ReplicatedStorage, "ONE_MORE_ITEM")
local net = requireChild(root, "Net")
local profileNet = requireChild(root, "ProfileNet")
local onboardingNet = requireChild(root, "OnboardingNet")
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
local profileSnapshotRemote = requireRemote(profileNet, "ProfileSnapshot")
local onboardingActionRequest = requireRemote(onboardingNet, "OnboardingActionRequest")

local worldRoot = requireChild(Workspace, "ONE_MORE_ITEM_WORLD")
local arena = requireChild(worldRoot, "PlaytestArena")
local stations = requireChild(arena, "Stations")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gameplayGuiInstance = waitForAuthoredChild(playerGui, "ONE_MORE_ITEM_Gameplay")
if not gameplayGuiInstance:IsA("ScreenGui") then
	error("ClientBootstrap requires ONE_MORE_ITEM_Gameplay to be a ScreenGui")
end
local gameplayGui: ScreenGui = gameplayGuiInstance
local guiRoot = requireChild(gameplayGui, "Root")
if not guiRoot:IsA("GuiObject") then
	error("ClientBootstrap requires ONE_MORE_ITEM_Gameplay.Root to be a GuiObject")
end
local touchDragSurface = requireFrame(guiRoot, "TouchDragSurface")
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
local profileStore = ClientProfileStore.new()
local camera = CameraController.new()
local character = CharacterController.new()
local roundUI = RoundUIController.new(gameplayGui, resolveItemName)
local inputMode: InputMode = "KeyboardMouse"
local layoutClass: LayoutClass = "Wide"
local profileUIForLayout: ProfileUIController.Controller? = nil
local onboardingUIForLayout: OnboardingUIController.Controller? = nil
local starterMissionUIForLayout: StarterMissionUIController.Controller? = nil
local responsiveUI = ResponsiveUIController.new(guiRoot, {
	BeforeApply = function(panelPositions, buttonSizes)
		roundUI:SetResponsiveTargets(panelPositions, buttonSizes)
	end,
	LayoutChanged = function(newLayoutClass: LayoutClass)
		layoutClass = newLayoutClass
		camera:SetPresentation(layoutClass, inputMode)
		local activeProfileUI = profileUIForLayout
		if activeProfileUI ~= nil then
			activeProfileUI:SetLayoutClass(layoutClass)
		end
		local activeOnboardingUI = onboardingUIForLayout
		if activeOnboardingUI ~= nil then
			activeOnboardingUI:SetLayoutClass(layoutClass)
		end
		local activeStarterMissionUI = starterMissionUIForLayout
		if activeStarterMissionUI ~= nil then
			activeStarterMissionUI:SetLayoutClass(layoutClass)
		end
		script:SetAttribute("LayoutClass", layoutClass)
	end,
	Observability = function(currentLayoutClass: LayoutClass, activeTweens: number)
		script:SetAttribute("LayoutClass", currentLayoutClass)
		script:SetAttribute("LayoutTweens", activeTweens)
	end,
})
local viewportPreview = ViewportPreviewController.new(
	currentViewport,
	nextViewport,
	cellBlockTemplate,
	getShapeCells,
	getItemColor
)

local stationContext: StationContextController.Controller? = nil

local decisionSequence = 0
local restartSequence = 0
local previousLoggedState: string? = nil
local previousLoggedStation: string? = nil
local destroyed = false
local connections: { RBXScriptConnection } = {}
local onboardingUIForInput: OnboardingUIController.Controller? = nil
local starterMissionUIForInput: StarterMissionUIController.Controller? = nil

local function requestDecision(choice: string)
	local snapshot = store:GetSnapshot()
	local context = stationContext
	if snapshot == nil
		or context == nil
		or not context:IsAssignedFor(snapshot.StationId)
		or snapshot.State ~= "Decision"
		or (choice ~= "SHIP" and choice ~= "ONE_MORE")
	then
		return
	end
	decisionSequence += 1
	roundUI:PlayButtonPress(choice)
	context:PressButton(choice)
	decisionRequest:FireServer({
		RoundId = snapshot.RoundId,
		StateVersion = snapshot.StateVersion,
		Choice = choice,
		ClientSequence = decisionSequence,
	})
end

local function requestRestart()
	local snapshot = store:GetSnapshot()
	local context = stationContext
	if snapshot == nil
		or context == nil
		or not context:IsAssignedFor(snapshot.StationId)
		or snapshot.State ~= "Results"
	then
		return
	end
	restartSequence += 1
	roundUI:PlayButtonPress("RESTART")
	context:PressButton("RESTART")
	restartRequest:FireServer({
		RoundId = snapshot.RoundId,
		StateVersion = snapshot.StateVersion,
		ClientSequence = restartSequence,
	})
end

local input = InputController.new({
	Move = function(deltaX: number, deltaZ: number)
		local context = stationContext
		if context ~= nil then
			context:Move(deltaX, deltaZ)
		end
	end,
	Rotate = function()
		local context = stationContext
		if context ~= nil then
			context:RotateClockwise()
		end
	end,
	Place = function()
		local context = stationContext
		if context ~= nil then
			context:RequestPlacement()
		end
	end,
	Decision = requestDecision,
	Restart = requestRestart,
	PointerRay = function(ray: Ray)
		local context = stationContext
		if context ~= nil then
			context:UpdateFromPointerRay(ray)
		end
	end,
	IsPlacementPending = function(): boolean
		local context = stationContext
		return context ~= nil and context:IsPlacementPending()
	end,
	ModeChanged = function(newMode: InputMode)
		inputMode = newMode
		camera:SetPresentation(layoutClass, inputMode)
		local activeOnboardingUI = onboardingUIForInput
		if activeOnboardingUI ~= nil then
			activeOnboardingUI:SetInputMode(inputMode)
		end
		local activeStarterMissionUI = starterMissionUIForInput
		if activeStarterMissionUI ~= nil then
			activeStarterMissionUI:SetInputMode(inputMode)
		end
		script:SetAttribute("InputMode", inputMode)
	end,
	Observability = function(
		currentMode: InputMode,
		touchActive: boolean,
		boundGamepadActions: number,
		repeatActive: boolean,
		selectedAction: string?
	)
		script:SetAttribute("InputMode", currentMode)
		script:SetAttribute("ActivePlacementTouch", touchActive)
		script:SetAttribute("BoundGamepadActions", boundGamepadActions)
		script:SetAttribute("GamepadRepeatActive", repeatActive)
		script:SetAttribute("SelectedGamepadAction", selectedAction)
	end,
}, roundUI:GetButtons(), guiRoot, touchDragSurface)

local onboardingUI = OnboardingUIController.new(guiRoot, onboardingActionRequest)
onboardingUIForInput = onboardingUI
onboardingUIForLayout = onboardingUI
onboardingUI:SetInputMode(inputMode)
onboardingUI:SetLayoutClass(layoutClass)

local modalStates = {
	Collection = false,
	StarterPath = false,
}
local profileUIForModal: ProfileUIController.Controller? = nil
local starterMissionUIForModal: StarterMissionUIController.Controller? = nil

local function refreshModalState()
	input:SetModalBlocked("Collection", modalStates.Collection)
	input:SetModalBlocked("StarterPath", modalStates.StarterPath)
	local blocked = modalStates.Collection or modalStates.StarterPath
	onboardingUI:SetModalBlocked(blocked)
	script:SetAttribute("ProfileMenuOpen", modalStates.Collection)
	script:SetAttribute("StarterPathOpen", modalStates.StarterPath)
end

local function setModalState(name: "Collection" | "StarterPath", isOpen: boolean)
	modalStates[name] = isOpen
	if isOpen and name == "Collection" then
		local missionUI = starterMissionUIForModal
		if missionUI ~= nil and missionUI:IsPanelOpen() then
			missionUI:SetPanelOpen(false)
		end
	elseif isOpen then
		local activeProfileUI = profileUIForModal
		if activeProfileUI ~= nil and activeProfileUI:IsMenuOpen() then
			activeProfileUI:SetMenuOpen(false)
		end
	end
	refreshModalState()
end

local starterMissionUI = StarterMissionUIController.new(guiRoot, {
	MenuOpenChanged = function(isOpen: boolean)
		setModalState("StarterPath", isOpen)
	end,
})
starterMissionUIForInput = starterMissionUI
starterMissionUIForLayout = starterMissionUI
starterMissionUIForModal = starterMissionUI
starterMissionUI:SetInputMode(inputMode)
starterMissionUI:SetLayoutClass(layoutClass)

local profileUI = ProfileUIController.new(guiRoot, cellBlockTemplate, {
	MenuOpenChanged = function(isOpen: boolean)
		setModalState("Collection", isOpen)
	end,
	AudioHook = function(eventName: string)
		-- Phase 05 intentionally has no audio assets. This observable hook is the
		-- single future integration seam for discovery, mastery, and rank audio.
		script:SetAttribute("LastProfileAudioHook", eventName)
	end,
})
profileUIForLayout = profileUI
profileUIForModal = profileUI
profileUI:SetLayoutClass(layoutClass)
refreshModalState()

stationContext = StationContextController.new({
	StationsRoot = stations,
	PlaceItemRequest = placeItemRequest,
	CellBlockTemplate = cellBlockTemplate,
	Camera = camera,
	Character = character,
	Callbacks = {
		FitChanged = function(valid: boolean?, x: number?, y: number?, z: number?)
			roundUI:SetFitState(valid, x, y, z)
			onboardingUI:SetFitState(valid)
		end,
		ButtonPressed = function(action: string)
			roundUI:PlayButtonPress(action)
		end,
		ServerResponse = function(reason: string, _accepted: boolean)
			roundUI:SetServerResponse(reason)
		end,
		PendingChanged = function(pending: boolean)
			script:SetAttribute("PlacementPending", pending)
			onboardingUI:SetPlacementPending(pending)
			input:RefreshContext()
		end,
		Observability = function(valid: boolean?, x: number?, y: number?, z: number?)
			script:SetAttribute("GhostValid", valid)
			script:SetAttribute("GhostX", x)
			script:SetAttribute("GhostY", y)
			script:SetAttribute("GhostZ", z)
		end,
		AssignmentChanged = function(isAssigned: boolean, stationId: string?)
			input:SetAssigned(isAssigned)
			script:SetAttribute("StationId", stationId)
			if not isAssigned then
				viewportPreview:Clear()
			end
		end,
	},
})

local unsubscribe = store:Subscribe(function(snapshot: Snapshot)
	if destroyed then
		return
	end
	local context = stationContext
	if context == nil then
		return
	end
	local nowAssigned = context:ApplySnapshot(snapshot)
	local activeStationId = context:GetStationId()
	if snapshot.State ~= previousLoggedState or activeStationId ~= previousLoggedStation then
		print(string.format(
			"[ONE_MORE_ITEM][Client] STATE round=%s version=%d state=%s station=%s",
			tostring(snapshot.RoundId),
			snapshot.StateVersion,
			snapshot.State,
			tostring(activeStationId)
		))
		previousLoggedState = snapshot.State
		previousLoggedStation = activeStationId
	end
	roundUI:ApplySnapshot(snapshot, nowAssigned)
	profileUI:ApplyRoundSnapshot(snapshot, nowAssigned)
	onboardingUI:ApplyRoundSnapshot(snapshot, nowAssigned)
	starterMissionUI:ApplyRoundSnapshot(snapshot, nowAssigned)
	if nowAssigned then
		viewportPreview:ApplySnapshot(snapshot)
	else
		viewportPreview:Clear()
	end
	input:ApplySnapshot(snapshot, nowAssigned)

	script:SetAttribute("RoundId", snapshot.RoundId)
	script:SetAttribute("StateVersion", snapshot.StateVersion)
	script:SetAttribute("RoundState", snapshot.State)
	script:SetAttribute("StationId", activeStationId)
	input:RefreshPointer()
end)

local unsubscribeProfile = profileStore:Subscribe(function(snapshot: ProfileSnapshot)
	if destroyed then
		return
	end
	profileUI:ApplyProfileSnapshot(snapshot)
	onboardingUI:ApplyProfileSnapshot(snapshot)
	starterMissionUI:ApplyProfileSnapshot(snapshot)
	script:SetAttribute("ProfileSessionId", snapshot.ProfileSessionId)
	script:SetAttribute("ProfileRevision", snapshot.Revision)
	script:SetAttribute("ProfileState", snapshot.State)
	script:SetAttribute("ProfileSaveState", snapshot.SaveState)
	script:SetAttribute("ProfileTape", snapshot.Tape)
	script:SetAttribute("ProfilePackingXP", snapshot.PackingXP)
end)

table.insert(connections, roundSnapshotRemote.OnClientEvent:Connect(function(snapshot: Snapshot)
	store:ApplySnapshot(snapshot)
end))

table.insert(connections, placementResponseRemote.OnClientEvent:Connect(function(response: PlacementResponse)
	local context = stationContext
	if context ~= nil then
		context:HandleResponse(response)
	end
end))

table.insert(connections, profileSnapshotRemote.OnClientEvent:Connect(function(snapshot: ProfileSnapshot)
	profileStore:ApplySnapshot(snapshot)
end))

local function cleanup()
	if destroyed then
		return
	end
	destroyed = true
	unsubscribe()
	unsubscribeProfile()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	local context = stationContext
	stationContext = nil
	if context ~= nil then
		context:Destroy()
	end
	profileUIForLayout = nil
	profileUIForModal = nil
	profileUI:Destroy()
	starterMissionUIForInput = nil
	starterMissionUIForLayout = nil
	starterMissionUIForModal = nil
	starterMissionUI:Destroy()
	onboardingUIForInput = nil
	onboardingUIForLayout = nil
	onboardingUI:Destroy()
	input:Destroy()
	responsiveUI:Destroy()
	viewportPreview:Destroy()
	roundUI:Destroy()
	camera:Destroy()
	character:Destroy()
	store:Destroy()
	profileStore:Destroy()
	script:SetAttribute("Initialized", false)
end

table.insert(connections, script.Destroying:Connect(cleanup))

script:SetAttribute("Initialized", true)
script:SetAttribute("ClientVersion", "phase06")
script:SetAttribute("ProfileMenuOpen", false)
script:SetAttribute("StarterPathOpen", false)
script:SetAttribute("InputMode", inputMode)
script:SetAttribute("LayoutClass", layoutClass)
print("[ONE_MORE_ITEM][Client] READY controls=keyboard+mouse+touch+gamepad authority=server")
clientReadyRequest:FireServer()
