--!strict

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClientProfileStore = require(script.Parent.ClientProfileStore)
local ClientRoundStore = require(script.Parent.ClientRoundStore)
local InputModeStore = require(script.Parent.InputModeStore)
local ResponsiveLayout = require(script.Parent.ResponsiveLayout)

type ProfileSnapshot = ClientProfileStore.Snapshot
type RoundSnapshot = ClientRoundStore.Snapshot
type InputMode = InputModeStore.InputMode
type LayoutClass = ResponsiveLayout.LayoutClass

export type Stage = "Move" | "ValidFit" | "Decision" | "Shipment" | "Failure"
export type Copy = {
	Prompt: string,
	Instruction: string,
	InputHint: string,
}

export type CompletionPresentationPhase = "Idle" | "Pending" | "Showing" | "Consumed"
export type CompletionPresentationState = {
	ProfileSessionId: string?,
	LastStatus: string?,
	Phase: CompletionPresentationPhase,
	RoundId: number?,
	Count: number,
}

export type Options = {
	CompletionPresentationChanged: ((active: boolean) -> ())?,
	Schedule: ((delaySeconds: number, callback: () -> ()) -> ())?,
}

export type Controller = {
	ApplyProfileSnapshot: (self: Controller, snapshot: ProfileSnapshot) -> (),
	ApplyRoundSnapshot: (self: Controller, snapshot: RoundSnapshot, assigned: boolean) -> (),
	SetFitState: (self: Controller, valid: boolean?) -> (),
	SetPlacementPending: (self: Controller, pending: boolean) -> (),
	SetInputMode: (self: Controller, mode: InputMode) -> (),
	SetLayoutClass: (self: Controller, layoutClass: LayoutClass) -> (),
	SetModalBlocked: (self: Controller, blocked: boolean) -> (),
	GetCompletionPresentationState: (self: Controller) -> CompletionPresentationState,
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_root: GuiObject,
	_overlay: Frame,
	_prompt: TextLabel,
	_instruction: TextLabel,
	_inputHint: TextLabel,
	_stepProgress: TextLabel,
	_pointer: TextLabel,
	_skipButton: TextButton,
	_skipProgress: Frame,
	_placeButton: TextButton,
	_shipButton: TextButton,
	_oneMoreButton: TextButton,
	_resultValue: GuiObject,
	_highlights: { [TextButton]: UIStroke },
	_remote: RemoteEvent,
	_connections: { RBXScriptConnection },
	_profileSnapshot: ProfileSnapshot?,
	_roundSnapshot: RoundSnapshot?,
	_inputMode: InputMode,
	_layoutClass: LayoutClass,
	_assigned: boolean,
	_fitValid: boolean?,
	_placementPending: boolean,
	_modalBlocked: boolean,
	_skipBound: boolean,
	_skipTween: Tween?,
	_skipSequence: number,
	_skipRequestSent: boolean,
	_completionState: CompletionPresentationState,
	_completionSequence: number,
	_completionPresentationChanged: (active: boolean) -> (),
	_schedule: (delaySeconds: number, callback: () -> ()) -> (),
	_destroyed: boolean,
}

local OnboardingUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local SKIP_ACTION = "ONE_MORE_ITEM_OnboardingSkip"
local SKIP_PRIORITY = Enum.ContextActionPriority.High.Value + 120
local SKIP_HOLD_SECONDS = 1.0
local COMPLETION_HOLD_SECONDS = 0.95
local GUIDANCE_ATTRIBUTE = "ONE_MORE_ITEM_OnboardingGuided"
local INPUT_FOCUS_ATTRIBUTE = "ONE_MORE_ITEM_InputFocused"
local SUCCESSFUL_COMPLETION_REASONS: { [string]: boolean } = table.freeze({
	PLAYER_SHIPPED = true,
	DECISION_TIMEOUT = true,
	MAX_ITEMS = true,
	BOX_FULL = true,
})
local FAILURE_RESULT_REASONS: { [string]: boolean } = table.freeze({
	DUPLICATE_OUTCOME = true,
	PLACEMENT_TIMEOUT = true,
	PROFILE_REWARD_FAILED = true,
	SHIPMENT_RECORD_FAILED = true,
})

local function noCompletionPresentationChanged(_active: boolean)
	-- Optional integration seam used to coordinate other local presentation queues.
end

local function schedule(delaySeconds: number, callback: () -> ())
	task.delay(delaySeconds, callback)
end

local function completionState(
	profileSessionId: string?,
	lastStatus: string?,
	phase: CompletionPresentationPhase,
	roundId: number?,
	count: number
): CompletionPresentationState
	return table.freeze({
		ProfileSessionId = profileSessionId,
		LastStatus = lastStatus,
		Phase = phase,
		RoundId = roundId,
		Count = count,
	}) :: CompletionPresentationState
end

local function requireFrame(parent: Instance, name: string): Frame
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("Frame") then
		error(string.format("OnboardingUIController requires Frame %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("OnboardingUIController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextButton") then
		error(string.format("OnboardingUIController requires TextButton %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("OnboardingUIController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireStroke(button: TextButton): UIStroke
	local child = button:WaitForChild("FocusStroke", 10)
	if child == nil or not child:IsA("UIStroke") then
		error(string.format("OnboardingUIController requires UIStroke %s.FocusStroke", button:GetFullName()), 3)
	end
	return child
end

function OnboardingUIController.ShouldShow(status: string): boolean
	return status ~= "Completed" and status ~= "Skipped"
end

function OnboardingUIController.ProfileStateUsable(state: string): boolean
	return state == "Ready" or state == "Saving" or state == "SaveDelayed"
end

function OnboardingUIController.NewCompletionPresentationState(): CompletionPresentationState
	return completionState(nil, nil, "Idle", nil, 0)
end

function OnboardingUIController.IsCompletionPresentationActive(state: CompletionPresentationState): boolean
	return state.Phase == "Pending" or state.Phase == "Showing"
end

function OnboardingUIController.IsSuccessfulCompletionRound(
	state: string?,
	resultLostValue: number,
	resultReason: string?
): boolean
	if resultLostValue > 0 or resultReason == nil or SUCCESSFUL_COMPLETION_REASONS[resultReason] ~= true then
		return false
	end
	return state == "Shipping" or state == "Results"
end

function OnboardingUIController.ShouldShowOverlay(
	profileState: string,
	onboardingStatus: string,
	assigned: boolean,
	completionActive: boolean
): boolean
	return OnboardingUIController.ProfileStateUsable(profileState)
		and assigned
		and (OnboardingUIController.ShouldShow(onboardingStatus) or completionActive)
end

function OnboardingUIController.ShouldOfferSkip(
	profileState: string,
	onboardingStatus: string,
	assigned: boolean
): boolean
	return OnboardingUIController.ProfileStateUsable(profileState)
		and assigned
		and OnboardingUIController.ShouldShow(onboardingStatus)
end

function OnboardingUIController.ReduceCompletionProfile(
	state: CompletionPresentationState,
	profileSessionId: string,
	profileState: string,
	onboardingStatus: string,
	assigned: boolean,
	roundId: number?,
	roundState: string?,
	resultLostValue: number,
	resultReason: string?
): CompletionPresentationState
	if state.ProfileSessionId ~= profileSessionId then
		local baselinePhase: CompletionPresentationPhase = if OnboardingUIController.ShouldShow(onboardingStatus)
			then "Idle"
			else "Consumed"
		return completionState(profileSessionId, onboardingStatus, baselinePhase, nil, 0)
	end

	if onboardingStatus == "Skipped" then
		return completionState(profileSessionId, onboardingStatus, "Consumed", nil, state.Count)
	end
	if not OnboardingUIController.ProfileStateUsable(profileState) then
		local phase: CompletionPresentationPhase = if OnboardingUIController.IsCompletionPresentationActive(state)
			then "Consumed"
			else state.Phase
		return completionState(profileSessionId, onboardingStatus, phase, if phase == "Consumed" then nil else state.RoundId, state.Count)
	end

	local previousWasNonterminal = state.LastStatus ~= nil and OnboardingUIController.ShouldShow(state.LastStatus)
	if previousWasNonterminal and onboardingStatus == "Completed" then
		if not assigned then
			return completionState(profileSessionId, onboardingStatus, "Consumed", nil, state.Count)
		end
		if roundState == "Failing"
			or (roundState == "Results"
				and not OnboardingUIController.IsSuccessfulCompletionRound(roundState, resultLostValue, resultReason))
		then
			return completionState(profileSessionId, onboardingStatus, "Consumed", nil, state.Count)
		end
		if roundId ~= nil
			and OnboardingUIController.IsSuccessfulCompletionRound(roundState, resultLostValue, resultReason)
		then
			return completionState(profileSessionId, onboardingStatus, "Showing", roundId, state.Count + 1)
		end
		return completionState(profileSessionId, onboardingStatus, "Pending", roundId, state.Count)
	end

	return completionState(profileSessionId, onboardingStatus, state.Phase, state.RoundId, state.Count)
end

function OnboardingUIController.ReduceCompletionRound(
	state: CompletionPresentationState,
	profileState: string,
	onboardingStatus: string,
	assigned: boolean,
	roundId: number,
	roundState: string,
	resultLostValue: number,
	resultReason: string?
): CompletionPresentationState
	if not OnboardingUIController.IsCompletionPresentationActive(state) then
		return state
	end
	if not assigned
		or not OnboardingUIController.ProfileStateUsable(profileState)
		or onboardingStatus ~= "Completed"
	then
		return completionState(state.ProfileSessionId, onboardingStatus, "Consumed", nil, state.Count)
	end

	local targetRoundId = state.RoundId or roundId
	if targetRoundId ~= roundId then
		return completionState(state.ProfileSessionId, onboardingStatus, "Consumed", nil, state.Count)
	end
	if roundState == "Failing"
		or (roundState == "Results"
			and not OnboardingUIController.IsSuccessfulCompletionRound(roundState, resultLostValue, resultReason))
	then
		return completionState(state.ProfileSessionId, onboardingStatus, "Consumed", nil, state.Count)
	end
	if state.Phase == "Pending"
		and OnboardingUIController.IsSuccessfulCompletionRound(roundState, resultLostValue, resultReason)
	then
		return completionState(state.ProfileSessionId, onboardingStatus, "Showing", roundId, state.Count + 1)
	end
	return completionState(state.ProfileSessionId, onboardingStatus, state.Phase, targetRoundId, state.Count)
end

function OnboardingUIController.FinishCompletionPresentation(
	state: CompletionPresentationState,
	roundId: number
): CompletionPresentationState
	if state.Phase ~= "Showing" or state.RoundId ~= roundId then
		return state
	end
	return completionState(state.ProfileSessionId, state.LastStatus, "Consumed", nil, state.Count)
end

function OnboardingUIController.ResolveStage(
	state: string?,
	assigned: boolean,
	resultLostValue: number,
	resultReason: string?,
	fitValid: boolean?,
	placementPending: boolean
): Stage
	if state == nil or not assigned then
		return "Move"
	end
	if state == "Failing" then
		return "Failure"
	elseif state == "Results" then
		if resultLostValue > 0 or (resultReason ~= nil and FAILURE_RESULT_REASONS[resultReason] == true) then
			return "Failure"
		end
		return "Shipment"
	elseif state == "Shipping" then
		return "Shipment"
	elseif state == "Decision" then
		return "Decision"
	elseif state == "AwaitingPlacement" and fitValid == true and not placementPending then
		return "ValidFit"
	end
	return "Move"
end

function OnboardingUIController.CopyForMode(mode: InputMode, stage: Stage): Copy
	if stage == "ValidFit" then
		return table.freeze({
			Prompt = "GREEN MEANS IT FITS",
			Instruction = "PLACE IT IN THE BOX",
			InputHint = if mode == "KeyboardMouse" then "PRESS SPACE" elseif mode == "Touch" then "TAP PLACE" else "PRESS [A]",
		}) :: Copy
	elseif stage == "Decision" then
		return table.freeze({
			Prompt = "SHIP IT OR RISK ONE MORE",
			Instruction = "SHIP BANKS THE REWARD  •  ONE MORE INCREASES THE VALUE",
			InputHint = if mode == "KeyboardMouse"
				then "[Q] SHIP  •  [E] ONE MORE"
				elseif mode == "Touch" then "TAP SHIP OR ONE MORE" else "SELECT ◀  ▶  THEN PRESS [A]",
		}) :: Copy
	elseif stage == "Shipment" then
		return table.freeze({
			Prompt = "SHIPMENT COMPLETE",
			Instruction = "TAPE IS SAVED  •  SHIPPED ITEMS JOIN YOUR COLLECTION",
			InputHint = "",
		}) :: Copy
	elseif stage == "Failure" then
		return table.freeze({
			Prompt = "TOO MUCH — TRY AGAIN",
			Instruction = "SHIP BEFORE THE BOX GETS TOO FULL",
			InputHint = "",
		}) :: Copy
	end
	return table.freeze({
		Prompt = "PACK YOUR FIRST BOX",
		Instruction = "MOVE THE PARCEL OVER THE BOX",
		InputHint = if mode == "KeyboardMouse"
			then "MOVE WITH WASD OR DRAG WITH THE MOUSE"
			elseif mode == "Touch" then "DRAG THE ITEM OVER THE BOX" else "USE LEFT STICK OR D-PAD TO MOVE",
	}) :: Copy
end

local function currentStage(self: InternalController): Stage
	local snapshot = self._roundSnapshot
	if snapshot == nil then
		return OnboardingUIController.ResolveStage(nil, self._assigned, 0, nil, self._fitValid, self._placementPending)
	end
	return OnboardingUIController.ResolveStage(
		snapshot.State,
		self._assigned,
		snapshot.ResultLostValue,
		snapshot.ResultReason,
		self._fitValid,
		self._placementPending
	)
end

local function overlayShouldShow(self: InternalController): boolean
	local snapshot = self._profileSnapshot
	return snapshot ~= nil and OnboardingUIController.ShouldShowOverlay(
		snapshot.State,
		snapshot.Onboarding.Status,
		self._assigned,
		OnboardingUIController.IsCompletionPresentationActive(self._completionState)
	)
end

local function ordinaryGuidanceShouldShow(self: InternalController): boolean
	local snapshot = self._profileSnapshot
	return snapshot ~= nil and OnboardingUIController.ShouldOfferSkip(
		snapshot.State,
		snapshot.Onboarding.Status,
		self._assigned
	)
end

local function cancelSkipTween(self: InternalController)
	local tween = self._skipTween
	self._skipTween = nil
	if tween ~= nil then
		tween:Cancel()
	end
	self._skipProgress.Visible = false
	self._skipProgress.Size = UDim2.fromScale(0, 0.006)
end

local function unbindSkip(self: InternalController)
	if self._skipBound then
		ContextActionService:UnbindAction(SKIP_ACTION)
		self._skipBound = false
	end
	cancelSkipTween(self)
end

local function sendSkip(self: InternalController)
	if self._destroyed or self._skipRequestSent or not ordinaryGuidanceShouldShow(self) or self._modalBlocked then
		return
	end
	self._skipRequestSent = true
	self._skipSequence += 1
	local sequence = self._skipSequence
	cancelSkipTween(self)
	self._remote:FireServer({
		Action = "SKIP",
		ClientSequence = sequence,
	})
	task.delay(1.1, function()
		if self._destroyed or self._skipSequence ~= sequence then
			return
		end
		local snapshot = self._profileSnapshot
		if snapshot ~= nil and OnboardingUIController.ShouldShow(snapshot.Onboarding.Status) then
			self._skipRequestSent = false
		end
	end)
end

local function startSkipHold(self: InternalController)
	if self._skipTween ~= nil or self._skipRequestSent then
		return
	end
	self._skipProgress.Visible = true
	self._skipProgress.Size = UDim2.fromScale(0, 0.006)
	local targetWidth = if self._layoutClass == "Portrait"
		then 0.30
		elseif self._layoutClass == "CompactLandscape" then 0.18 else 0.13
	local tween = TweenService:Create(
		self._skipProgress,
		TweenInfo.new(SKIP_HOLD_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(targetWidth, 0.006) }
	)
	self._skipTween = tween
	tween.Completed:Once(function(playbackState)
		if self._destroyed or self._skipTween ~= tween then
			return
		end
		self._skipTween = nil
		if playbackState == Enum.PlaybackState.Completed then
			sendSkip(self)
		else
			cancelSkipTween(self)
		end
	end)
	tween:Play()
end

local function bindSkip(self: InternalController)
	if self._skipBound then
		return
	end
	ContextActionService:BindActionAtPriority(
		SKIP_ACTION,
		function(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if self._destroyed or not ordinaryGuidanceShouldShow(self) or self._modalBlocked then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				startSkipHold(self)
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				cancelSkipTween(self)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		SKIP_PRIORITY,
		Enum.KeyCode.ButtonB
	)
	self._skipBound = true
end

local function refreshSkipBinding(self: InternalController)
	if ordinaryGuidanceShouldShow(self) and self._inputMode == "Gamepad" and not self._modalBlocked then
		bindSkip(self)
	else
		unbindSkip(self)
	end
end

local function setHighlight(self: InternalController, button: TextButton, enabled: boolean)
	local stroke = self._highlights[button]
	stroke:SetAttribute(GUIDANCE_ATTRIBUTE, enabled)
	stroke.Enabled = true
	stroke.Transparency = if enabled or stroke:GetAttribute(INPUT_FOCUS_ATTRIBUTE) == true then 0 else 1
end

local function updateHighlights(self: InternalController, stage: Stage)
	if self._modalBlocked then
		setHighlight(self, self._placeButton, false)
		setHighlight(self, self._shipButton, false)
		setHighlight(self, self._oneMoreButton, false)
		return
	end
	setHighlight(self, self._placeButton, stage == "ValidFit")
	setHighlight(self, self._shipButton, stage == "Decision")
	setHighlight(self, self._oneMoreButton, stage == "Decision")
end

local function pointerTarget(self: InternalController, stage: Stage): GuiObject?
	if stage == "ValidFit" then
		return self._placeButton
	elseif stage == "Decision" then
		return self._shipButton
	elseif stage == "Shipment" then
		return self._resultValue
	end
	return nil
end

local function updatePointer(self: InternalController, stage: Stage)
	if not self._overlay.Visible or self._modalBlocked then
		self._pointer.Visible = false
		return
	end
	local target = pointerTarget(self, stage)
	if target == nil then
		local snapshot = self._roundSnapshot
		local stableCrateTarget = self._assigned
			and snapshot ~= nil
			and snapshot.State == "AwaitingPlacement"
			and (stage == "Move" or stage == "ValidFit")
		if stableCrateTarget then
			self._pointer.Position = UDim2.fromScale(0.5, 0.54)
		end
		self._pointer.Visible = stableCrateTarget
		return
	end
	if not target.Visible or self._root.AbsoluteSize.X <= 0 or self._root.AbsoluteSize.Y <= 0 then
		self._pointer.Visible = false
		return
	end
	local center = target.AbsolutePosition + target.AbsoluteSize * 0.5 - self._root.AbsolutePosition
	local x = math.clamp(center.X / self._root.AbsoluteSize.X, 0.04, 0.96)
	local y = math.clamp((center.Y / self._root.AbsoluteSize.Y) - 0.055, 0.04, 0.94)
	self._pointer.Position = UDim2.fromScale(x, y)
	self._pointer.Visible = true
end

local function applyInternalLayout(self: InternalController)
	if self._layoutClass == "Portrait" then
		self._stepProgress.Position = UDim2.fromScale(0.5, 0.265)
		self._prompt.Position = UDim2.fromScale(0.5, 0.30)
		self._prompt.Size = UDim2.fromScale(0.72, 0.052)
		self._instruction.Position = UDim2.fromScale(0.5, 0.354)
		self._instruction.Size = UDim2.fromScale(0.82, 0.044)
		self._inputHint.Position = UDim2.fromScale(0.5, 0.40)
		self._inputHint.Size = UDim2.fromScale(0.80, 0.038)
		self._skipButton.Position = UDim2.fromScale(0.97, 0.20)
		self._skipButton.Size = UDim2.fromScale(0.30, 0.052)
		self._skipProgress.Position = UDim2.fromScale(0.67, 0.254)
	elseif self._layoutClass == "CompactLandscape" then
		self._stepProgress.Position = UDim2.fromScale(0.5, 0.015)
		self._prompt.Position = UDim2.fromScale(0.5, 0.045)
		self._prompt.Size = UDim2.fromScale(0.42, 0.09)
		self._instruction.Position = UDim2.fromScale(0.5, 0.14)
		self._instruction.Size = UDim2.fromScale(0.50, 0.07)
		self._inputHint.Position = UDim2.fromScale(0.5, 0.212)
		self._inputHint.Size = UDim2.fromScale(0.48, 0.055)
		self._skipButton.Position = UDim2.fromScale(0.98, 0.03)
		self._skipButton.Size = UDim2.fromScale(0.18, 0.09)
		self._skipProgress.Position = UDim2.fromScale(0.80, 0.122)
	else
		self._stepProgress.Position = UDim2.fromScale(0.5, 0.175)
		self._prompt.Position = UDim2.fromScale(0.5, 0.205)
		self._prompt.Size = UDim2.fromScale(0.38, 0.052)
		self._instruction.Position = UDim2.fromScale(0.5, 0.259)
		self._instruction.Size = UDim2.fromScale(0.42, 0.044)
		self._inputHint.Position = UDim2.fromScale(0.5, 0.305)
		self._inputHint.Size = UDim2.fromScale(0.40, 0.038)
		self._skipButton.Position = UDim2.fromScale(0.97, 0.12)
		self._skipButton.Size = UDim2.fromScale(0.13, 0.052)
		self._skipProgress.Position = UDim2.fromScale(0.84, 0.174)
	end
end

local function publishCompletionObservability(self: InternalController)
	if not RunService:IsStudio() then
		return
	end
	local state = self._completionState
	self._overlay:SetAttribute("CompletionPresentationPending", state.Phase == "Pending")
	self._overlay:SetAttribute("CompletionPresentationShown", state.Phase == "Showing")
	self._overlay:SetAttribute("CompletionPresentationCount", state.Count)
end

local function render(self: InternalController)
	if self._destroyed then
		return
	end
	local visible = overlayShouldShow(self)
	local ordinaryGuidance = ordinaryGuidanceShouldShow(self)
	local completionActive = OnboardingUIController.IsCompletionPresentationActive(self._completionState)
	local completionShowing = self._completionState.Phase == "Showing"
	self._overlay.Visible = visible
	self._skipButton.Visible = visible and ordinaryGuidance
	if not visible then
		self._pointer.Visible = false
		updateHighlights(self, "Move")
		refreshSkipBinding(self)
		return
	end
	local stage: Stage = if completionShowing then "Shipment" else currentStage(self)
	if stage == "Shipment" and not completionShowing then
		-- A Shipping RoundSnapshot may beat the Completed ProfileSnapshot. The
		-- approved terminal copy belongs to the local completion presentation,
		-- never to an arrival-order-dependent ordinary render.
		stage = "Decision"
	end
	local copy = OnboardingUIController.CopyForMode(self._inputMode, stage)
	self._prompt.Text = copy.Prompt
	self._instruction.Text = copy.Instruction
	self._inputHint.Text = copy.InputHint
	local snapshot = self._profileSnapshot :: ProfileSnapshot
	self._stepProgress.Text = string.format("STEP %d / 5", math.clamp(snapshot.Onboarding.HighestStep + 1, 1, 5))
	self._skipButton.Text = if self._inputMode == "Gamepad" then "HOLD [B] TO SKIP" else "SKIP TUTORIAL"
	if completionActive then
		updateHighlights(self, "Move")
		self._pointer.Visible = false
	else
		updateHighlights(self, stage)
		updatePointer(self, stage)
	end
	refreshSkipBinding(self)
end

local applyCompletionTransition: (self: InternalController, nextState: CompletionPresentationState) -> ()

local function scheduleCompletionHold(self: InternalController)
	self._completionSequence += 1
	local sequence = self._completionSequence
	local roundId = self._completionState.RoundId
	if roundId == nil then
		return
	end
	self._schedule(COMPLETION_HOLD_SECONDS, function()
		if self._destroyed or self._completionSequence ~= sequence then
			return
		end
		applyCompletionTransition(
			self,
			OnboardingUIController.FinishCompletionPresentation(self._completionState, roundId)
		)
	end)
end

applyCompletionTransition = function(self: InternalController, nextState: CompletionPresentationState)
	local previous = self._completionState
	local wasActive = OnboardingUIController.IsCompletionPresentationActive(previous)
	local isActive = OnboardingUIController.IsCompletionPresentationActive(nextState)
	local enteredShowing = nextState.Phase == "Showing"
		and (previous.Phase ~= "Showing" or previous.RoundId ~= nextState.RoundId)
	if wasActive and (not isActive or previous.RoundId ~= nextState.RoundId) then
		self._completionSequence += 1
	end
	self._completionState = nextState
	publishCompletionObservability(self)
	if isActive and not wasActive then
		self._completionPresentationChanged(true)
	end
	render(self)
	if wasActive and not isActive then
		self._completionPresentationChanged(false)
	end
	if enteredShowing then
		scheduleCompletionHold(self)
	end
end

function OnboardingUIController.new(root: GuiObject, onboardingActionRequest: RemoteEvent, options: Options?): Controller
	local overlay = requireFrame(root, "OnboardingOverlay")
	local placementControls = requireFrame(root, "PlacementControls")
	local decisionPanel = requireFrame(root, "DecisionPanel")
	local resultsPanel = requireFrame(root, "ResultsPanel")
	local placeButton = requireButton(placementControls, "PlaceButton")
	local shipButton = requireButton(decisionPanel, "ShipButton")
	local oneMoreButton = requireButton(decisionPanel, "OneMoreButton")
	local completionPresentationChanged: (active: boolean) -> () = noCompletionPresentationChanged
	local scheduleCallback: (delaySeconds: number, callback: () -> ()) -> () = schedule
	if options ~= nil then
		local configuredPresentationChanged = options.CompletionPresentationChanged
		if configuredPresentationChanged ~= nil then
			completionPresentationChanged = configuredPresentationChanged
		end
		local configuredSchedule = options.Schedule
		if configuredSchedule ~= nil then
			scheduleCallback = configuredSchedule
		end
	end
	local self: InternalController = setmetatable({
		_root = root,
		_overlay = overlay,
		_prompt = requireLabel(overlay, "Prompt"),
		_instruction = requireLabel(overlay, "Instruction"),
		_inputHint = requireLabel(overlay, "InputHint"),
		_stepProgress = requireLabel(overlay, "StepProgress"),
		_pointer = requireLabel(overlay, "TutorialPointer"),
		_skipButton = requireButton(overlay, "SkipButton"),
		_skipProgress = requireFrame(overlay, "SkipHoldProgress"),
		_placeButton = placeButton,
		_shipButton = shipButton,
		_oneMoreButton = oneMoreButton,
		_resultValue = requireGui(resultsPanel, "ResultValue"),
		_highlights = {
			[placeButton] = requireStroke(placeButton),
			[shipButton] = requireStroke(shipButton),
			[oneMoreButton] = requireStroke(oneMoreButton),
		},
		_remote = onboardingActionRequest,
		_connections = {},
		_profileSnapshot = nil,
		_roundSnapshot = nil,
		_inputMode = "KeyboardMouse",
		_layoutClass = "Wide",
		_assigned = false,
		_fitValid = nil,
		_placementPending = false,
		_modalBlocked = false,
		_skipBound = false,
		_skipTween = nil,
		_skipSequence = 0,
		_skipRequestSent = false,
		_completionState = OnboardingUIController.NewCompletionPresentationState(),
		_completionSequence = 0,
		_completionPresentationChanged = completionPresentationChanged,
		_schedule = scheduleCallback,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	overlay.Visible = false
	self._pointer.Visible = false
	self._skipProgress.Visible = false
	publishCompletionObservability(self)
	applyInternalLayout(self)
	table.insert(self._connections, self._skipButton.Activated:Connect(function()
		if self._inputMode ~= "Gamepad" then
			sendSkip(self)
		end
	end))
	for _, target in { placeButton, shipButton, oneMoreButton, self._resultValue } do
		table.insert(self._connections, target:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			updatePointer(self, currentStage(self))
		end))
		table.insert(self._connections, target:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			updatePointer(self, currentStage(self))
		end))
	end
	return self
end

function ControllerMethods.ApplyProfileSnapshot(self: InternalController, snapshot: ProfileSnapshot)
	if self._destroyed then
		return
	end
	local previousSessionId = if self._profileSnapshot ~= nil then self._profileSnapshot.ProfileSessionId else nil
	self._profileSnapshot = snapshot
	if previousSessionId ~= snapshot.ProfileSessionId and OnboardingUIController.ShouldShow(snapshot.Onboarding.Status) then
		self._skipRequestSent = false
	end
	if not OnboardingUIController.ShouldShow(snapshot.Onboarding.Status) then
		self._skipRequestSent = true
	end
	local round = self._roundSnapshot
	applyCompletionTransition(
		self,
		OnboardingUIController.ReduceCompletionProfile(
			self._completionState,
			snapshot.ProfileSessionId,
			snapshot.State,
			snapshot.Onboarding.Status,
			self._assigned,
			if round ~= nil then round.RoundId else nil,
			if round ~= nil then round.State else nil,
			if round ~= nil then round.ResultLostValue else 0,
			if round ~= nil then round.ResultReason else nil
		)
	)
end

function ControllerMethods.ApplyRoundSnapshot(self: InternalController, snapshot: RoundSnapshot, assigned: boolean)
	if self._destroyed then
		return
	end
	self._roundSnapshot = snapshot
	self._assigned = assigned
	if snapshot.State ~= "AwaitingPlacement" then
		self._fitValid = nil
		self._placementPending = false
	end
	local profile = self._profileSnapshot
	applyCompletionTransition(
		self,
		OnboardingUIController.ReduceCompletionRound(
			self._completionState,
			if profile ~= nil then profile.State else "",
			if profile ~= nil then profile.Onboarding.Status else "",
			assigned,
			snapshot.RoundId,
			snapshot.State,
			snapshot.ResultLostValue,
			snapshot.ResultReason
		)
	)
end

function ControllerMethods.SetFitState(self: InternalController, valid: boolean?)
	if not self._destroyed then
		self._fitValid = valid
		render(self)
	end
end

function ControllerMethods.SetPlacementPending(self: InternalController, pending: boolean)
	if not self._destroyed then
		self._placementPending = pending
		render(self)
	end
end

function ControllerMethods.SetInputMode(self: InternalController, mode: InputMode)
	if not self._destroyed and self._inputMode ~= mode then
		self._inputMode = mode
		render(self)
	end
end

function ControllerMethods.SetLayoutClass(self: InternalController, layoutClass: LayoutClass)
	if not self._destroyed then
		self._layoutClass = layoutClass
		applyInternalLayout(self)
		updatePointer(self, currentStage(self))
	end
end

function ControllerMethods.SetModalBlocked(self: InternalController, blocked: boolean)
	if not self._destroyed and self._modalBlocked ~= blocked then
		self._modalBlocked = blocked
		render(self)
	end
end

function ControllerMethods.GetCompletionPresentationState(self: InternalController): CompletionPresentationState
	return self._completionState
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._completionSequence += 1
	unbindSkip(self)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for button in pairs(self._highlights) do
		setHighlight(self, button, false)
	end
	self._overlay.Visible = false
	self._pointer.Visible = false
	if OnboardingUIController.IsCompletionPresentationActive(self._completionState) then
		self._completionPresentationChanged(false)
	end
end

return table.freeze(OnboardingUIController)
