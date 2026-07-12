--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)

type Snapshot = ClientRoundStore.Snapshot

export type Buttons = {
	Rotate: TextButton,
	Place: TextButton,
	Ship: TextButton,
	OneMore: TextButton,
	PackAgain: TextButton,
}

export type Controller = {
	GetButtons: (self: Controller) -> Buttons,
	ApplySnapshot: (self: Controller, snapshot: Snapshot) -> (),
	SetFitState: (self: Controller, valid: boolean?, x: number?, y: number?, z: number?) -> (),
	SetServerResponse: (self: Controller, message: string) -> (),
	PlayButtonPress: (self: Controller, action: string) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_gui: ScreenGui,
	_root: GuiObject,
	_currentItemCard: GuiObject,
	_shipmentCard: GuiObject,
	_placementControls: GuiObject,
	_decisionPanel: GuiObject,
	_resultsPanel: GuiObject,
	_statusBanner: TextLabel,
	_labels: { [string]: TextLabel },
	_buttons: Buttons,
	_originalPositions: { [GuiObject]: UDim2 },
	_originalButtonSizes: { [TextButton]: UDim2 },
	_connections: { RBXScriptConnection },
	_snapshot: Snapshot?,
	_lastPlacementSecond: number?,
	_lastDecisionSecond: number?,
	_resolveItemName: (itemId: string) -> string,
	_destroyed: boolean,
}

local RoundUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("RoundUIController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("RoundUIController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:FindFirstChild(name)
	if child == nil or not child:IsA("TextButton") then
		error(string.format("RoundUIController requires TextButton %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function offsetPosition(position: UDim2, pixelsY: number): UDim2
	return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + pixelsY)
end

local function scaledSize(size: UDim2, scale: number): UDim2
	return UDim2.new(size.X.Scale * scale, math.round(size.X.Offset * scale), size.Y.Scale * scale, math.round(size.Y.Offset * scale))
end

local function setPanelVisible(self: InternalController, panel: GuiObject, visible: boolean, entranceDuration: number?)
	local originalPosition = self._originalPositions[panel]
	if visible then
		panel.Visible = true
		panel.Position = offsetPosition(originalPosition, 16)
		TweenService:Create(
			panel,
			TweenInfo.new(entranceDuration or PresentationTokens.Timing.Panel, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = originalPosition }
		):Play()
	else
		panel.Visible = false
		panel.Position = originalPosition
	end
end

local function updateButtonState(button: GuiButton, active: boolean)
	button.Active = active
	button.AutoButtonColor = active
	button.Interactable = active
	button.BackgroundTransparency = if active then 0 else 0.45
	button.TextTransparency = if active then 0 else 0.35
end

local function formatMultiplier(multiplier: number): string
	return string.format("×%.2f", multiplier)
end

local function formatReason(reason: string?): string
	if reason == nil or reason == "" then
		return ""
	end
	if reason == "PLACEMENT_TIMEOUT" then
		return "THE LAST ITEM DID NOT FIT IN TIME"
	elseif reason == "BOX_FULL" then
		return "THE BOX IS FULL"
	elseif reason == "MAX_ITEMS" then
		return "MAXIMUM PACK REACHED"
	elseif reason == "DECISION_TIMEOUT" then
		return "TIME UP — SHIPPED SAFELY"
	end
	return string.gsub(reason, "_", " ")
end

function RoundUIController.new(gui: ScreenGui, resolveItemName: (itemId: string) -> string): Controller
	local root = requireGui(gui, "Root")
	local currentItemCard = requireGui(root, "CurrentItemCard")
	local shipmentCard = requireGui(root, "ShipmentCard")
	local placementControls = requireGui(root, "PlacementControls")
	local decisionPanel = requireGui(root, "DecisionPanel")
	local resultsPanel = requireGui(root, "ResultsPanel")
	local developmentDebug = requireGui(root, "DevelopmentDebug")

	local buttons: Buttons = {
		Rotate = requireButton(placementControls, "RotateButton"),
		Place = requireButton(placementControls, "PlaceButton"),
		Ship = requireButton(decisionPanel, "ShipButton"),
		OneMore = requireButton(decisionPanel, "OneMoreButton"),
		PackAgain = requireButton(resultsPanel, "PackAgainButton"),
	}

	local labels: { [string]: TextLabel } = {
		ItemName = requireLabel(currentItemCard, "ItemName"),
		FitState = requireLabel(currentItemCard, "FitState"),
		PlacementTimer = requireLabel(currentItemCard, "PlacementTimer"),
		UnshippedLabel = requireLabel(shipmentCard, "UnshippedLabel"),
		ShipmentValue = requireLabel(shipmentCard, "ShipmentValue"),
		ItemCount = requireLabel(shipmentCard, "ItemCount"),
		Multiplier = requireLabel(shipmentCard, "Multiplier"),
		SessionBank = requireLabel(shipmentCard, "SessionBank"),
		NextItemName = requireLabel(decisionPanel, "NextItemName"),
		NextDifficulty = requireLabel(decisionPanel, "NextDifficulty"),
		DecisionTimer = requireLabel(decisionPanel, "DecisionTimer"),
		GuaranteedValue = requireLabel(decisionPanel, "GuaranteedValue"),
		PossibleValue = requireLabel(decisionPanel, "PossibleValue"),
		ResultTitle = requireLabel(resultsPanel, "ResultTitle"),
		ResultReason = requireLabel(resultsPanel, "ResultReason"),
		ResultValue = requireLabel(resultsPanel, "ResultValue"),
		SessionTotal = requireLabel(resultsPanel, "SessionTotal"),
		DebugRoundState = requireLabel(developmentDebug, "RoundState"),
		DebugRoundId = requireLabel(developmentDebug, "RoundId"),
		DebugStateVersion = requireLabel(developmentDebug, "StateVersion"),
		DebugGridPosition = requireLabel(developmentDebug, "GridPosition"),
		DebugServerResponse = requireLabel(developmentDebug, "ServerResponse"),
	}

	local originalPositions: { [GuiObject]: UDim2 } = {}
	for _, panel in ipairs({ currentItemCard, shipmentCard, placementControls, decisionPanel, resultsPanel }) do
		originalPositions[panel] = panel.Position
	end
	local originalButtonSizes: { [TextButton]: UDim2 } = {}
	for _, button in pairs(buttons) do
		originalButtonSizes[button] = button.Size
	end

	local self: InternalController = setmetatable({
		_gui = gui,
		_root = root,
		_currentItemCard = currentItemCard,
		_shipmentCard = shipmentCard,
		_placementControls = placementControls,
		_decisionPanel = decisionPanel,
		_resultsPanel = resultsPanel,
		_statusBanner = requireLabel(root, "StatusBanner"),
		_labels = labels,
		_buttons = buttons,
		_originalPositions = originalPositions,
		_originalButtonSizes = originalButtonSizes,
		_connections = {},
		_snapshot = nil,
		_lastPlacementSecond = nil,
		_lastDecisionSecond = nil,
		_resolveItemName = resolveItemName,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	developmentDebug.Visible = RunService:IsStudio() and gui:GetAttribute("DevelopmentDebugEnabled") == true
	setPanelVisible(self, decisionPanel, false)
	setPanelVisible(self, resultsPanel, false)

	for _, button in pairs(buttons) do
		table.insert(self._connections, button.MouseEnter:Connect(function()
			if button.Interactable then
				TweenService:Create(button, TweenInfo.new(0.11, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = scaledSize(originalButtonSizes[button], 1.03),
				}):Play()
			end
		end))
		table.insert(self._connections, button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.11, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = originalButtonSizes[button],
			}):Play()
		end))
	end

	table.insert(self._connections, RunService.RenderStepped:Connect(function()
		if self._destroyed then
			return
		end
		local snapshot = self._snapshot
		if snapshot == nil then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if snapshot.State == "AwaitingPlacement" and snapshot.PlacementDeadline ~= nil then
			local seconds = math.max(0, math.ceil(snapshot.PlacementDeadline - now))
			if seconds ~= self._lastPlacementSecond then
				self._lastPlacementSecond = seconds
				labels.PlacementTimer.Text = string.format("%02d", seconds)
			end
		elseif snapshot.State == "Decision" and snapshot.DecisionDeadline ~= nil then
			local seconds = math.max(0, math.ceil(snapshot.DecisionDeadline - now))
			if seconds ~= self._lastDecisionSecond then
				self._lastDecisionSecond = seconds
				labels.DecisionTimer.Text = string.format("%02d", seconds)
			end
		end
	end))

	gui.Enabled = true
	return self
end

function ControllerMethods.GetButtons(self: InternalController): Buttons
	return self._buttons
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot)
	if self._destroyed then
		return
	end
	self._snapshot = snapshot
	local state = snapshot.State
	local hasStation = snapshot.StationId == "station_01"
	local awaiting = state == "AwaitingPlacement" and hasStation
	local deciding = state == "Decision" and hasStation
	local results = state == "Results" and hasStation
	local spectator = not hasStation

	setPanelVisible(self, self._currentItemCard, awaiting or state == "PresentingItem")
	setPanelVisible(self, self._shipmentCard, not results)
	setPanelVisible(self, self._placementControls, awaiting, PresentationTokens.Timing.Quick)
	setPanelVisible(self, self._decisionPanel, deciding)
	setPanelVisible(self, self._resultsPanel, results or spectator)

	updateButtonState(self._buttons.Rotate, awaiting)
	updateButtonState(self._buttons.Place, awaiting)
	updateButtonState(self._buttons.Ship, deciding)
	updateButtonState(self._buttons.OneMore, deciding)
	updateButtonState(self._buttons.PackAgain, results)

	self._labels.ItemName.Text = if snapshot.CurrentItemId ~= nil then self._resolveItemName(snapshot.CurrentItemId) else "WAITING FOR ITEM"
	self._labels.UnshippedLabel.Text = "UNSHIPPED"
	self._labels.ShipmentValue.Text = string.format("%d TAPE", snapshot.ShipmentValue)
	self._labels.ItemCount.Text = string.format("%d / 10 ITEMS", snapshot.ItemCount)
	self._labels.Multiplier.Text = formatMultiplier(snapshot.CurrentMultiplier)
	self._labels.SessionBank.Text = string.format("BANK %d TAPE", snapshot.SessionBank)
	self._labels.NextItemName.Text = if snapshot.NextItemId ~= nil then self._resolveItemName(snapshot.NextItemId) else "BOX FULL"
	self._labels.NextDifficulty.Text = snapshot.NextDifficulty or ""
	self._labels.GuaranteedValue.Text = string.format("Guaranteed: %d Tape", snapshot.ShipmentValue)
	self._labels.PossibleValue.Text = string.format("Possible: %d Tape", snapshot.PossibleNextShipmentValue)
	self._buttons.Ship.Text = string.format("SHIP NOW\nGuaranteed: %d Tape", snapshot.ShipmentValue)
	self._buttons.OneMore.Text = string.format("ONE MORE\nPossible: %d Tape\n%s", snapshot.PossibleNextShipmentValue, snapshot.NextDifficulty or "")

	if state == "Decision" then
		self._statusBanner.Text = "SHIP IT OR RISK ONE MORE"
		self._statusBanner.TextColor3 = PresentationTokens.Color.White
	elseif state == "Shipping" then
		self._statusBanner.Text = "SHIPMENT COMPLETE"
		self._statusBanner.TextColor3 = PresentationTokens.Color.Green
	elseif state == "Failing" then
		self._statusBanner.Text = "TOO MUCH!"
		self._statusBanner.TextColor3 = PresentationTokens.Color.Red
	elseif state == "PresentingItem" then
		self._statusBanner.Text = "ONE MORE ITEM"
		self._statusBanner.TextColor3 = PresentationTokens.Color.Amber
	elseif not awaiting then
		self._statusBanner.Text = ""
	end

	if spectator then
		self._statusBanner.Text = "STATION 01 IS IN USE"
		self._statusBanner.TextColor3 = PresentationTokens.Color.SecondaryText
		self._labels.ResultTitle.Text = "SPECTATING"
		self._labels.ResultTitle.TextColor3 = PresentationTokens.Color.Cyan
		self._labels.ResultReason.Text = "STATION 01 IS CURRENTLY ASSIGNED"
		self._labels.ResultValue.Text = ""
		self._labels.SessionTotal.Text = ""
	elseif results then
		local failed = snapshot.ResultLostValue > 0
		self._labels.ResultTitle.Text = if failed then "TOO MUCH!" else "SHIPMENT COMPLETE"
		self._labels.ResultTitle.TextColor3 = if failed then PresentationTokens.Color.Red else PresentationTokens.Color.Green
		self._labels.ResultReason.Text = formatReason(snapshot.ResultReason)
		self._labels.ResultValue.Text = if failed
			then string.format("LOST %d TAPE", snapshot.ResultLostValue)
			else string.format("+%d TAPE", snapshot.ResultValue)
		self._labels.SessionTotal.Text = string.format("SESSION %d TAPE", snapshot.SessionBank)
	end
	self._statusBanner.Visible = self._statusBanner.Text ~= ""

	self._labels.DebugRoundState.Text = string.format("State: %s", state)
	self._labels.DebugRoundId.Text = string.format("Round: %s", tostring(snapshot.RoundId))
	self._labels.DebugStateVersion.Text = string.format("Version: %d", snapshot.StateVersion)
end

function ControllerMethods.SetFitState(self: InternalController, valid: boolean?, x: number?, y: number?, z: number?)
	if valid == nil then
		self._labels.FitState.Text = ""
	elseif valid then
		self._labels.FitState.Text = "✓  GREEN MEANS IT FITS"
		self._labels.FitState.TextColor3 = PresentationTokens.Color.Green
		self._statusBanner.Text = "GREEN MEANS IT FITS"
		self._statusBanner.TextColor3 = PresentationTokens.Color.Green
	else
		self._labels.FitState.Text = "×  NO ROOM THERE"
		self._labels.FitState.TextColor3 = PresentationTokens.Color.Red
		self._statusBanner.Text = "NO ROOM THERE"
		self._statusBanner.TextColor3 = PresentationTokens.Color.Red
	end
	self._statusBanner.Visible = self._statusBanner.Text ~= ""
	if x ~= nil and z ~= nil then
		self._labels.DebugGridPosition.Text = string.format("Grid: %d,%s,%d", x, if y ~= nil then tostring(y) else "-", z)
	end
end

function ControllerMethods.SetServerResponse(self: InternalController, message: string)
	self._labels.DebugServerResponse.Text = string.format("Server: %s", message)
end

function ControllerMethods.PlayButtonPress(self: InternalController, action: string)
	local button: TextButton?
	if action == "ROTATE" then
		button = self._buttons.Rotate
	elseif action == "PLACE" then
		button = self._buttons.Place
	elseif action == "SHIP" then
		button = self._buttons.Ship
	elseif action == "ONE_MORE" then
		button = self._buttons.OneMore
	elseif action == "RESTART" then
		button = self._buttons.PackAgain
	end
	if button == nil or not button.Interactable then
		return
	end
	local original = self._originalButtonSizes[button]
	local down = TweenService:Create(button, TweenInfo.new(PresentationTokens.Timing.ButtonDown, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = scaledSize(original, 0.94),
	})
	down:Play()
	down.Completed:Once(function()
		if self._destroyed then
			return
		end
		local up = TweenService:Create(button, TweenInfo.new(PresentationTokens.Timing.ButtonReturn, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = original,
		})
		up:Play()
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._gui.Enabled = false
end

return table.freeze(RoundUIController)
