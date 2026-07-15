--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)

type Snapshot = ClientRoundStore.Snapshot

type PanelMotionState = {
	TargetVisible: boolean,
	Epoch: number,
	Tween: Tween?,
	CompletionConnection: RBXScriptConnection?,
}

type CountAnimation = {
	From: number,
	Target: number,
	StartedAt: number,
	Duration: number,
	Epoch: number,
}

export type Buttons = {
	Rotate: TextButton,
	Place: TextButton,
	Ship: TextButton,
	OneMore: TextButton,
	PackAgain: TextButton,
}

export type PanelPositions = { [GuiObject]: UDim2 }
export type ButtonSizes = { [TextButton]: UDim2 }

export type Controller = {
	GetButtons: (self: Controller) -> Buttons,
	SetResponsiveTargets: (self: Controller, panelPositions: PanelPositions, buttonSizes: ButtonSizes) -> (),
	ApplySnapshot: (self: Controller, snapshot: Snapshot, assigned: boolean) -> (),
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
	_buttonTweens: { [TextButton]: Tween },
	_buttonEpochs: { [TextButton]: number },
	_panelMotion: { [GuiObject]: PanelMotionState },
	_countAnimations: { [string]: CountAnimation },
	_countEpochs: { [string]: number },
	_displayedNumbers: { [string]: number },
	_authoritativeNumbers: { [string]: number },
	_resultCountKey: string?,
	_connections: { RBXScriptConnection },
	_snapshot: Snapshot?,
	_assigned: boolean,
	_lastPlacementSecond: number?,
	_lastDecisionSecond: number?,
	_resolveItemName: (itemId: string) -> string,
	_destroyed: boolean,
}

local RoundUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local PANEL_ENTRANCE_OFFSET = 16
local SHIPMENT_COUNT_MIN_DURATION = 0.25
local SHIPMENT_COUNT_MAX_DURATION = 0.40
local SESSION_COUNT_MIN_DURATION = 0.55
local SESSION_COUNT_MAX_DURATION = 0.80
local RESULT_COUNT_DURATION = 0.30
local SHIPMENT_FULL_DURATION_DIFFERENCE = 100
local SESSION_FULL_DURATION_DIFFERENCE = 250
local FAILURE_RESULT_REASONS: { [string]: boolean } = table.freeze({
	PLACEMENT_TIMEOUT = true,
})

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("RoundUIController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("RoundUIController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:WaitForChild(name, 10)
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

local function stopButtonMotion(self: InternalController, button: TextButton)
	self._buttonEpochs[button] = (self._buttonEpochs[button] or 0) + 1
	local tween = self._buttonTweens[button]
	if tween ~= nil then
		self._buttonTweens[button] = nil
		tween:Cancel()
	end
end

local function tweenButtonSize(
	self: InternalController,
	button: TextButton,
	targetSize: UDim2,
	duration: number,
	onCompleted: (() -> ())?
)
	stopButtonMotion(self, button)
	local epoch = self._buttonEpochs[button]
	local tween = TweenService:Create(
		button,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	self._buttonTweens[button] = tween
	tween.Completed:Once(function(playbackState: Enum.PlaybackState)
		if self._destroyed or self._buttonEpochs[button] ~= epoch or self._buttonTweens[button] ~= tween then
			return
		end
		self._buttonTweens[button] = nil
		if playbackState == Enum.PlaybackState.Completed and onCompleted ~= nil then
			onCompleted()
		end
	end)
	tween:Play()
end

local function stopPanelMotion(state: PanelMotionState)
	local completionConnection = state.CompletionConnection
	if completionConnection ~= nil then
		completionConnection:Disconnect()
		state.CompletionConnection = nil
	end
	local tween = state.Tween
	if tween ~= nil then
		tween:Cancel()
		state.Tween = nil
	end
end

local function setPanelVisible(self: InternalController, panel: GuiObject, visible: boolean)
	local originalPosition = self._originalPositions[panel]
	local state = self._panelMotion[panel]
	if state.TargetVisible == visible then
		return
	end

	state.TargetVisible = visible
	state.Epoch += 1
	local epoch = state.Epoch
	stopPanelMotion(state)

	local targetPosition: UDim2
	local duration: number
	if visible then
		panel.Visible = true
		panel.Position = offsetPosition(originalPosition, PANEL_ENTRANCE_OFFSET)
		targetPosition = originalPosition
		duration = PresentationTokens.Timing.Panel
	else
		if not panel.Visible then
			panel.Position = originalPosition
			return
		end
		targetPosition = offsetPosition(originalPosition, PANEL_ENTRANCE_OFFSET)
		duration = PresentationTokens.Timing.Quick
	end

	local tween = TweenService:Create(
		panel,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, if visible then Enum.EasingDirection.Out else Enum.EasingDirection.In),
		{ Position = targetPosition }
	)
	state.Tween = tween
	state.CompletionConnection = tween.Completed:Once(function(playbackState)
		if self._destroyed or state.Epoch ~= epoch or state.TargetVisible ~= visible then
			return
		end
		state.Tween = nil
		state.CompletionConnection = nil
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		panel.Position = originalPosition
		if not visible then
			panel.Visible = false
		end
	end)
	tween:Play()
end

local function hidePanelImmediately(self: InternalController, panel: GuiObject)
	local state = self._panelMotion[panel]
	state.TargetVisible = false
	state.Epoch += 1
	stopPanelMotion(state)
	panel.Position = self._originalPositions[panel]
	panel.Visible = false
end

local function countDuration(minimum: number, maximum: number, difference: number, fullDurationDifference: number): number
	local alpha = math.clamp(math.abs(difference) / fullDurationDifference, 0, 1)
	return minimum + (maximum - minimum) * alpha
end

local function renderCountValue(self: InternalController, key: string, value: number)
	local rounded = math.round(value)
	if key == "ShipmentValue" then
		self._labels.ShipmentValue.Text = string.format("%d TAPE", rounded)
	elseif key == "SessionBank" then
		self._labels.SessionBank.Text = string.format("BANK %d TAPE", rounded)
		local snapshot = self._snapshot
		if snapshot ~= nil and self._assigned and snapshot.State == "Results" then
			self._labels.SessionTotal.Text = string.format("SESSION %d TAPE", rounded)
		end
	elseif key == "ResultValue" then
		local snapshot = self._snapshot
		if snapshot ~= nil
			and self._assigned
			and snapshot.State == "Results"
			and snapshot.ResultLostValue == 0
		then
			self._labels.ResultValue.Text = string.format("+%d TAPE", rounded)
		end
	end
end

local function setDisplayedNumber(self: InternalController, key: string, value: number)
	self._displayedNumbers[key] = value
	renderCountValue(self, key, value)
end

local function cancelCountAnimation(self: InternalController, key: string)
	self._countEpochs[key] = (self._countEpochs[key] or 0) + 1
	self._countAnimations[key] = nil
end

local function setCountTarget(
	self: InternalController,
	key: string,
	target: number,
	animateIncrease: boolean,
	forceExact: boolean,
	minimumDuration: number,
	maximumDuration: number,
	fullDurationDifference: number
)
	local previousTarget = self._authoritativeNumbers[key]
	if previousTarget == nil then
		self._authoritativeNumbers[key] = target
		cancelCountAnimation(self, key)
		setDisplayedNumber(self, key, target)
		return
	end

	if target == previousTarget then
		if forceExact then
			cancelCountAnimation(self, key)
			setDisplayedNumber(self, key, target)
		else
			renderCountValue(self, key, self._displayedNumbers[key] or target)
		end
		return
	end

	self._authoritativeNumbers[key] = target
	local displayed = self._displayedNumbers[key] or previousTarget
	if animateIncrease and target > previousTarget and target > displayed then
		cancelCountAnimation(self, key)
		local epoch = self._countEpochs[key]
		self._countAnimations[key] = {
			From = displayed,
			Target = target,
			StartedAt = os.clock(),
			Duration = countDuration(minimumDuration, maximumDuration, target - displayed, fullDurationDifference),
			Epoch = epoch,
		}
	else
		cancelCountAnimation(self, key)
		setDisplayedNumber(self, key, target)
	end
end

local function beginResultCount(self: InternalController, snapshot: Snapshot)
	local resultKey = string.format("%d:%d", snapshot.RoundId, snapshot.ResultValue)
	if self._resultCountKey == resultKey then
		renderCountValue(self, "ResultValue", self._displayedNumbers.ResultValue or snapshot.ResultValue)
		return
	end

	self._resultCountKey = resultKey
	cancelCountAnimation(self, "ResultValue")
	self._authoritativeNumbers.ResultValue = 0
	setDisplayedNumber(self, "ResultValue", 0)
	setCountTarget(
		self,
		"ResultValue",
		snapshot.ResultValue,
		true,
		false,
		RESULT_COUNT_DURATION,
		RESULT_COUNT_DURATION,
		math.max(1, snapshot.ResultValue)
	)
end

local function clearResultCount(self: InternalController, authoritativeValue: number)
	self._resultCountKey = nil
	self._authoritativeNumbers.ResultValue = authoritativeValue
	cancelCountAnimation(self, "ResultValue")
	self._displayedNumbers.ResultValue = authoritativeValue
end

local function updateCountAnimations(self: InternalController)
	local now = os.clock()
	for key, animation in pairs(self._countAnimations) do
		if self._countEpochs[key] ~= animation.Epoch then
			self._countAnimations[key] = nil
			continue
		end

		local alpha = math.clamp((now - animation.StartedAt) / animation.Duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		setDisplayedNumber(self, key, animation.From + (animation.Target - animation.From) * eased)
		if alpha >= 1 then
			self._countAnimations[key] = nil
			setDisplayedNumber(self, key, animation.Target)
		end
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

local function isFailureResult(snapshot: Snapshot): boolean
	if snapshot.State == "Failing" or snapshot.ResultLostValue > 0 then
		return true
	end
	local reason = snapshot.ResultReason
	return reason ~= nil and FAILURE_RESULT_REASONS[reason] == true
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

	local managedPanels: { GuiObject } = { currentItemCard, shipmentCard, placementControls, decisionPanel, resultsPanel }
	local originalPositions: { [GuiObject]: UDim2 } = {}
	local panelMotion: { [GuiObject]: PanelMotionState } = {}
	for _, panel in ipairs(managedPanels) do
		originalPositions[panel] = panel.Position
		panelMotion[panel] = {
			TargetVisible = panel.Visible,
			Epoch = 0,
			Tween = nil,
			CompletionConnection = nil,
		}
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
		_buttonTweens = {},
		_buttonEpochs = {},
		_panelMotion = panelMotion,
		_countAnimations = {},
		_countEpochs = {},
		_displayedNumbers = {},
		_authoritativeNumbers = {},
		_resultCountKey = nil,
		_connections = {},
		_snapshot = nil,
		_assigned = false,
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
				tweenButtonSize(self, button, scaledSize(originalButtonSizes[button], 1.03), 0.11, nil)
			end
		end))
		table.insert(self._connections, button.MouseLeave:Connect(function()
			tweenButtonSize(self, button, originalButtonSizes[button], 0.11, nil)
		end))
	end

	table.insert(self._connections, RunService.RenderStepped:Connect(function()
		if self._destroyed then
			return
		end
		updateCountAnimations(self)
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

function ControllerMethods.SetResponsiveTargets(
	self: InternalController,
	panelPositions: PanelPositions,
	buttonSizes: ButtonSizes
)
	if self._destroyed then
		return
	end
	for panel, position in pairs(panelPositions) do
		local state = self._panelMotion[panel]
		if state ~= nil then
			state.Epoch += 1
			stopPanelMotion(state)
			panel.Visible = state.TargetVisible
			self._originalPositions[panel] = position
		end
	end
	for button, size in pairs(buttonSizes) do
		if self._originalButtonSizes[button] ~= nil then
			stopButtonMotion(self, button)
			self._originalButtonSizes[button] = size
		end
	end
end

function ControllerMethods.ApplySnapshot(self: InternalController, snapshot: Snapshot, assigned: boolean)
	if self._destroyed then
		return
	end
	self._snapshot = snapshot
	self._assigned = assigned
	local state = snapshot.State
	local hasStation = assigned
	local awaiting = state == "AwaitingPlacement" and hasStation
	local deciding = state == "Decision" and hasStation
	local results = state == "Results" and hasStation
	local waiting = not hasStation
	local failedResult = isFailureResult(snapshot)
	local successfulShipping = state == "Shipping" and hasStation and not failedResult and snapshot.ResultValue > 0
	local shipmentDisplayTarget = if successfulShipping then snapshot.ResultValue else snapshot.ShipmentValue

	setCountTarget(
		self,
		"ShipmentValue",
		shipmentDisplayTarget,
		deciding or successfulShipping,
		waiting or state == "Preparing" or state == "Failing" or failedResult,
		SHIPMENT_COUNT_MIN_DURATION,
		SHIPMENT_COUNT_MAX_DURATION,
		SHIPMENT_FULL_DURATION_DIFFERENCE
	)
	setCountTarget(
		self,
		"SessionBank",
		snapshot.SessionBank,
		hasStation and (state == "Shipping" or results) and not failedResult,
		waiting or state == "Preparing" or state == "Failing" or failedResult,
		SESSION_COUNT_MIN_DURATION,
		SESSION_COUNT_MAX_DURATION,
		SESSION_FULL_DURATION_DIFFERENCE
	)
	if results and not failedResult and snapshot.ResultValue > 0 then
		beginResultCount(self, snapshot)
	else
		clearResultCount(self, snapshot.ResultValue)
	end

	if waiting then
		hidePanelImmediately(self, self._currentItemCard)
		hidePanelImmediately(self, self._shipmentCard)
		hidePanelImmediately(self, self._placementControls)
		hidePanelImmediately(self, self._decisionPanel)
	else
		setPanelVisible(self, self._currentItemCard, awaiting or state == "PresentingItem")
		setPanelVisible(self, self._shipmentCard, not results)
		setPanelVisible(self, self._placementControls, awaiting)
		setPanelVisible(self, self._decisionPanel, deciding)
	end
	setPanelVisible(self, self._resultsPanel, results or waiting)

	updateButtonState(self._buttons.Rotate, awaiting)
	updateButtonState(self._buttons.Place, awaiting)
	updateButtonState(self._buttons.Ship, deciding)
	updateButtonState(self._buttons.OneMore, deciding)
	updateButtonState(self._buttons.PackAgain, results)
	self._buttons.PackAgain.Visible = results
	self._buttons.PackAgain.Selectable = results

	self._labels.ItemName.Text = if snapshot.CurrentItemId ~= nil then self._resolveItemName(snapshot.CurrentItemId) else "WAITING FOR ITEM"
	self._labels.UnshippedLabel.Text = "UNSHIPPED"
	self._labels.ItemCount.Text = string.format("%d / 10 ITEMS", snapshot.ItemCount)
	self._labels.Multiplier.Text = formatMultiplier(snapshot.CurrentMultiplier)
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

	if waiting then
		self._statusBanner.Text = "WAITING FOR A PACKING STATION"
		self._statusBanner.TextColor3 = PresentationTokens.Color.SecondaryText
		self._labels.ResultTitle.Text = "WAITING FOR A PACKING STATION"
		self._labels.ResultTitle.TextColor3 = PresentationTokens.Color.Cyan
		self._labels.ResultReason.Text = "YOU WILL BE ASSIGNED AUTOMATICALLY"
		self._labels.ResultValue.Text = ""
		self._labels.SessionTotal.Text = ""
	elseif results then
		self._labels.ResultTitle.Text = if failedResult then "TOO MUCH!" else "SHIPMENT COMPLETE"
		self._labels.ResultTitle.TextColor3 = if failedResult then PresentationTokens.Color.Red else PresentationTokens.Color.Green
		self._labels.ResultReason.Text = formatReason(snapshot.ResultReason)
		if failedResult then
			self._labels.ResultValue.Text = string.format("LOST %d TAPE", snapshot.ResultLostValue)
			self._labels.SessionTotal.Text = string.format("SESSION %d TAPE", snapshot.SessionBank)
		end
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
	tweenButtonSize(self, button, scaledSize(original, 0.94), PresentationTokens.Timing.ButtonDown, function()
		local latestOriginal = self._originalButtonSizes[button :: TextButton]
		tweenButtonSize(self, button :: TextButton, latestOriginal, PresentationTokens.Timing.ButtonReturn, nil)
	end)
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._assigned = false
	for _, state in pairs(self._panelMotion) do
		state.Epoch += 1
		stopPanelMotion(state)
	end
	local activeButtons: { TextButton } = {}
	for button in pairs(self._buttonTweens) do
		table.insert(activeButtons, button)
	end
	for _, button in ipairs(activeButtons) do
		stopButtonMotion(self, button)
	end
	for key in pairs(self._countAnimations) do
		cancelCountAnimation(self, key)
	end
	table.clear(self._countAnimations)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._gui.Enabled = false
end

return table.freeze(RoundUIController)
