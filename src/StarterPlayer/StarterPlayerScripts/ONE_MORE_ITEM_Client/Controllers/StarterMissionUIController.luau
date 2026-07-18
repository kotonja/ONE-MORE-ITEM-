--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientProfileStore = require(script.Parent.ClientProfileStore)
local ClientRoundStore = require(script.Parent.ClientRoundStore)
local InputModeStore = require(script.Parent.InputModeStore)
local PresentationTokens = require(script.Parent.PresentationTokens)
local ResponsiveLayout = require(script.Parent.ResponsiveLayout)

local sharedProfile = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared"):WaitForChild("Profile")
local StarterMissionDefinitions = require(sharedProfile:WaitForChild("StarterMissionDefinitions"))

type ProfileSnapshot = ClientProfileStore.Snapshot
type MissionReward = ClientProfileStore.MissionRewardPresentation
type RoundSnapshot = ClientRoundStore.Snapshot
type InputMode = InputModeStore.InputMode
type LayoutClass = ResponsiveLayout.LayoutClass

type MissionRow = {
	Root: TextButton,
	Status: TextLabel,
	MissionName: TextLabel,
	Description: TextLabel,
	ProgressText: TextLabel,
	RewardText: TextLabel,
	Fill: Frame,
	Stroke: UIStroke,
}

export type Callbacks = {
	MenuOpenChanged: (isOpen: boolean) -> (),
}

export type Controller = {
	ApplyProfileSnapshot: (self: Controller, snapshot: ProfileSnapshot) -> (),
	ApplyRoundSnapshot: (self: Controller, snapshot: RoundSnapshot, assigned: boolean) -> (),
	SetInputMode: (self: Controller, mode: InputMode) -> (),
	SetLayoutClass: (self: Controller, layoutClass: LayoutClass) -> (),
	SetPanelOpen: (self: Controller, isOpen: boolean) -> (),
	IsPanelOpen: (self: Controller) -> boolean,
	SetPresentationBlocked: (self: Controller, blocked: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_callbacks: Callbacks,
	_card: Frame,
	_cardMissionName: TextLabel,
	_cardDescription: TextLabel,
	_cardProgressText: TextLabel,
	_cardProgressBar: Frame,
	_cardFill: Frame,
	_cardRewardText: TextLabel,
	_openButton: TextButton,
	_panel: Frame,
	_panelSummary: TextLabel,
	_closeButton: TextButton,
	_rows: { MissionRow },
	_banner: Frame,
	_bannerHeader: TextLabel,
	_bannerMissionName: TextLabel,
	_bannerRewardText: TextLabel,
	_bannerPathProgress: TextLabel,
	_connections: { RBXScriptConnection },
	_profileSnapshot: ProfileSnapshot?,
	_roundSnapshot: RoundSnapshot?,
	_assigned: boolean,
	_inputMode: InputMode,
	_layoutClass: LayoutClass,
	_panelOpen: boolean,
	_cardProgressTween: Tween?,
	_seenRewardIds: { [string]: boolean },
	_seenRewardOrder: { string },
	_rewardQueue: { MissionReward },
	_rewardWorkerActive: boolean,
	_rewardEpoch: number,
	_bannerTween: Tween?,
	_bannerRestPosition: UDim2,
	_presentationBlocked: boolean,
	_profileSessionId: string?,
	_roundGeneration: number,
	_destroyed: boolean,
}

local StarterMissionUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local MAX_SEEN_REWARDS = 64

local function requireFrame(parent: Instance, name: string): Frame
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("Frame") then
		error(string.format("StarterMissionUIController requires Frame %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("StarterMissionUIController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextButton") then
		error(string.format("StarterMissionUIController requires TextButton %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireStroke(parent: Instance, name: string): UIStroke
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("UIStroke") then
		error(string.format("StarterMissionUIController requires UIStroke %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

function StarterMissionUIController.PanelAllowed(profileState: string, assigned: boolean, roundState: string?): boolean
	local profileUsable = profileState == "Ready" or profileState == "Saving" or profileState == "SaveDelayed"
	if not profileUsable then
		return false
	end
	if not assigned then
		return true
	end
	return roundState == "Results"
end

function StarterMissionUIController.SortedNewRewards(
	rewards: { MissionReward },
	seenRewardIds: { [string]: boolean }
): { MissionReward }
	local sorted: { MissionReward } = {}
	local queuedRewardIds: { [string]: boolean } = {}
	for _, reward in ipairs(rewards) do
		if reward.RewardId ~= ""
			and seenRewardIds[reward.RewardId] ~= true
			and queuedRewardIds[reward.RewardId] ~= true
		then
			queuedRewardIds[reward.RewardId] = true
			table.insert(sorted, reward)
		end
	end
	table.sort(sorted, function(left: MissionReward, right: MissionReward): boolean
		if left.MissionIndex ~= right.MissionIndex then
			return left.MissionIndex < right.MissionIndex
		end
		return left.RewardId < right.RewardId
	end)
	return sorted
end

function StarterMissionUIController.PathProgress(
	completedCount: number,
	rewardedCount: number,
	totalCount: number
): (number, number)
	local total = math.max(0, math.floor(totalCount))
	local completed = math.clamp(math.max(math.floor(completedCount), math.floor(rewardedCount)), 0, total)
	return completed, total
end

function StarterMissionUIController.ShouldDeferRewardPresentation(
	missionId: string,
	onboardingStatus: string?,
	presentationBlocked: boolean
): boolean
	return presentationBlocked
		or (missionId == "first_shipment"
			and (onboardingStatus == "NotStarted" or onboardingStatus == "InProgress"))
end

local function profileUsable(snapshot: ProfileSnapshot?): boolean
	return snapshot ~= nil
		and StarterMissionUIController.PanelAllowed(snapshot.State, false, nil)
end

local function panelAllowed(self: InternalController): boolean
	local profile = self._profileSnapshot
	if profile == nil then
		return false
	end
	return StarterMissionUIController.PanelAllowed(
		profile.State,
		self._assigned,
		if self._roundSnapshot ~= nil then self._roundSnapshot.State else nil
	)
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Interactable = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.5
	button.BackgroundTransparency = if enabled then 0.12 else 0.45
end

local function cancelTween(tween: Tween?): Tween?
	if tween ~= nil then
		tween:Cancel()
	end
	return nil
end

local function updateCardSize(self: InternalController, completed: boolean)
	if self._layoutClass == "Portrait" then
		self._card.Size = UDim2.fromScale(0.90, if completed then 0.06 else 0.11)
	elseif self._layoutClass == "CompactLandscape" then
		self._card.Size = UDim2.fromScale(0.235, if completed then 0.12 else 0.30)
	else
		self._card.Size = UDim2.fromScale(0.19, if completed then 0.07 else 0.18)
	end
end

local function completedSet(snapshot: ProfileSnapshot): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, missionId in ipairs(snapshot.StarterMissions.CompletedMissionIds) do
		result[missionId] = true
	end
	return result
end

local function rewardedSet(snapshot: ProfileSnapshot): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, missionId in ipairs(snapshot.StarterMissions.RewardedMissionIds) do
		result[missionId] = true
	end
	return result
end

local function setCardProgress(self: InternalController, ratio: number, animate: boolean)
	self._cardProgressTween = cancelTween(self._cardProgressTween)
	local target = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	if animate then
		local tween = TweenService:Create(
			self._cardFill,
			TweenInfo.new(0.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = target }
		)
		self._cardProgressTween = tween
		tween.Completed:Once(function()
			if self._cardProgressTween == tween then
				self._cardProgressTween = nil
			end
		end)
		tween:Play()
	else
		self._cardFill.Size = target
	end
end

local function renderRows(self: InternalController, snapshot: ProfileSnapshot)
	local completed = completedSet(snapshot)
	local rewarded = rewardedSet(snapshot)
	for index, definition in ipairs(StarterMissionDefinitions.Ordered) do
		local row = self._rows[index]
		local progress = math.clamp(snapshot.StarterMissions.Progress[definition.Id] or 0, 0, definition.Goal)
		local isRewarded = rewarded[definition.Id] == true
		local isCompleted = completed[definition.Id] == true
		local isCurrent = snapshot.StarterMissions.CurrentMissionId == definition.Id
		row.Status.Text = if isRewarded then "DONE" elseif isCompleted then "READY" elseif isCurrent then "NOW" else tostring(index)
		row.Status.TextColor3 = if isRewarded
			then PresentationTokens.Color.Green
			elseif isCurrent then PresentationTokens.Color.Cyan else PresentationTokens.Color.SecondaryText
		row.MissionName.Text = definition.Name
		row.Description.Text = definition.Description
		row.ProgressText.Text = string.format("%d / %d", progress, definition.Goal)
		row.RewardText.Text = string.format("+%d TAPE  +%d XP", definition.Reward.Tape, definition.Reward.PackingXP)
		row.Fill.Size = UDim2.fromScale(progress / definition.Goal, 1)
		row.Stroke.Color = if isCurrent then PresentationTokens.Color.Cyan else Color3.fromRGB(77, 91, 107)
		row.Stroke.Transparency = if isCurrent then 0 else 0.3
		row.Root.Selectable = self._panelOpen
	end
end

local function cardShouldShow(snapshot: ProfileSnapshot): boolean
	local onboarding = snapshot.Onboarding
	return profileUsable(snapshot)
		and (onboarding.HighestStep >= 3 or onboarding.Status == "Completed" or onboarding.Status == "Skipped")
end

local function renderCard(self: InternalController, snapshot: ProfileSnapshot, previous: ProfileSnapshot?)
	local visible = cardShouldShow(snapshot)
	self._card.Visible = visible
	if not visible then
		return
	end
	local missions = snapshot.StarterMissions
	local pathCompleted = missions.PathCompleted
	updateCardSize(self, pathCompleted)
	self._cardDescription.Visible = not pathCompleted
	self._cardProgressText.Visible = not pathCompleted
	self._cardProgressBar.Visible = not pathCompleted
	self._cardRewardText.Visible = not pathCompleted
	if pathCompleted then
		self._cardMissionName.Text = "STARTER PATH COMPLETE"
		self._cardDescription.Text = ""
		self._cardProgressText.Text = "5 / 5"
		self._cardRewardText.Text = ""
	else
		local missionId = missions.CurrentMissionId
		local definition = if missionId ~= nil then StarterMissionDefinitions.Get(missionId) else nil
		if definition == nil then
			self._cardMissionName.Text = "STARTER PATH"
			self._cardDescription.Text = "Progress is updating."
			self._cardProgressText.Text = string.format("%d / %d", missions.CompletedCount, missions.TotalCount)
			self._cardRewardText.Text = ""
			setCardProgress(self, 0, false)
		else
			local progress = math.clamp(missions.Progress[definition.Id] or 0, 0, definition.Goal)
			self._cardMissionName.Text = definition.Name
			self._cardDescription.Text = definition.Description
			self._cardProgressText.Text = string.format("%d / %d", progress, definition.Goal)
			self._cardRewardText.Text = string.format(
				"+%d TAPE  +%d XP  •  %d / 5",
				definition.Reward.Tape,
				definition.Reward.PackingXP,
				missions.CompletedCount
			)
			local previousProgress = if previous ~= nil then previous.StarterMissions.Progress[definition.Id] else nil
			setCardProgress(self, progress / definition.Goal, previousProgress ~= nil and previousProgress ~= progress)
		end
	end
	setButtonEnabled(self._openButton, panelAllowed(self))
end

local function render(self: InternalController, previous: ProfileSnapshot?)
	local snapshot = self._profileSnapshot
	if snapshot == nil then
		self._card.Visible = false
		return
	end
	self._panelSummary.Text = string.format("%d / %d COMPLETE", snapshot.StarterMissions.CompletedCount, snapshot.StarterMissions.TotalCount)
	renderRows(self, snapshot)
	renderCard(self, snapshot, previous)
end

local function rememberReward(self: InternalController, rewardId: string)
	if self._seenRewardIds[rewardId] then
		return
	end
	self._seenRewardIds[rewardId] = true
	table.insert(self._seenRewardOrder, rewardId)
	while #self._seenRewardOrder > MAX_SEEN_REWARDS do
		local removed = table.remove(self._seenRewardOrder, 1)
		self._seenRewardIds[removed] = nil
	end
end

local function cancelBanner(self: InternalController)
	self._rewardEpoch += 1
	self._bannerTween = cancelTween(self._bannerTween)
	self._banner.Visible = false
	self._banner.Position = self._bannerRestPosition
	self._rewardWorkerActive = false
	table.clear(self._rewardQueue)
end

local function pauseBanner(self: InternalController)
	self._rewardEpoch += 1
	self._bannerTween = cancelTween(self._bannerTween)
	self._banner.Visible = false
	self._banner.Position = self._bannerRestPosition
	self._rewardWorkerActive = false
end

local function rewardWaitsForOnboarding(self: InternalController, reward: MissionReward): boolean
	local profile = self._profileSnapshot
	return StarterMissionUIController.ShouldDeferRewardPresentation(
		reward.MissionId,
		if profile ~= nil then profile.Onboarding.Status else nil,
		self._presentationBlocked
	)
end

local function playBanner(self: InternalController, reward: MissionReward, epoch: number): boolean
	local definition = StarterMissionDefinitions.Get(reward.MissionId)
	if definition == nil or self._destroyed or epoch ~= self._rewardEpoch then
		return false
	end
	self._bannerHeader.Text = if reward.PathCompleted then "STARTER PATH COMPLETE" else "MISSION COMPLETE"
	self._bannerMissionName.Text = definition.Name
	self._bannerRewardText.Text = string.format("+%d TAPE  +%d PACKING XP", reward.TapeDelta, reward.XPDelta)
	local profile = self._profileSnapshot
	local completedCount = 0
	local totalCount = StarterMissionDefinitions.TotalCount
	if profile ~= nil then
		completedCount, totalCount = StarterMissionUIController.PathProgress(
			profile.StarterMissions.CompletedCount,
			#profile.StarterMissions.RewardedMissionIds,
			profile.StarterMissions.TotalCount
		)
	end
	self._bannerPathProgress.Text = string.format("%d / %d", completedCount, totalCount)
	local target = self._banner.Position
	self._bannerRestPosition = target
	self._banner.Position = UDim2.fromScale(target.X.Scale, math.max(0.01, target.Y.Scale - 0.04))
	self._banner.Visible = true
	local enter = TweenService:Create(
		self._banner,
		TweenInfo.new(PresentationTokens.Timing.Quick, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = target }
	)
	self._bannerTween = enter
	enter:Play()
	enter.Completed:Wait()
	if self._destroyed or epoch ~= self._rewardEpoch then
		return false
	end
	self._bannerTween = nil
	local hold = if self._roundSnapshot ~= nil and self._roundSnapshot.State == "Results" then 1.2 else 0.9
	local roundGeneration = self._roundGeneration
	local started = os.clock()
	while not self._destroyed and epoch == self._rewardEpoch do
		local currentLimit = if self._roundGeneration ~= roundGeneration then math.min(hold, 0.25) else hold
		if os.clock() - started >= currentLimit then
			break
		end
		task.wait(0.05)
	end
	if self._destroyed or epoch ~= self._rewardEpoch then
		return false
	end
	local exit = TweenService:Create(
		self._banner,
		TweenInfo.new(PresentationTokens.Timing.Quick, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(target.X.Scale, math.max(0.01, target.Y.Scale - 0.04)) }
	)
	self._bannerTween = exit
	exit:Play()
	exit.Completed:Wait()
	if self._destroyed or epoch ~= self._rewardEpoch then
		return false
	end
	self._bannerTween = nil
	self._banner.Visible = false
	self._banner.Position = target
	return true
end

local function startRewardWorker(self: InternalController)
	if self._rewardWorkerActive
		or self._presentationBlocked
		or not profileUsable(self._profileSnapshot)
		or #self._rewardQueue == 0
	then
		return
	end
	if rewardWaitsForOnboarding(self, self._rewardQueue[1]) then
		return
	end
	self._rewardWorkerActive = true
	self._rewardEpoch += 1
	local epoch = self._rewardEpoch
	task.spawn(function()
		while not self._destroyed and epoch == self._rewardEpoch and #self._rewardQueue > 0 do
			if self._presentationBlocked then
				break
			end
			local reward = self._rewardQueue[1]
			if rewardWaitsForOnboarding(self, reward) then
				break
			end
			if not playBanner(self, reward, epoch) then
				break
			end
			table.remove(self._rewardQueue, 1)
		end
		if not self._destroyed and epoch == self._rewardEpoch then
			self._rewardWorkerActive = false
		end
	end)
end

local function baselineSession(self: InternalController, snapshot: ProfileSnapshot)
	cancelBanner(self)
	table.clear(self._seenRewardIds)
	table.clear(self._seenRewardOrder)
	self._profileSessionId = snapshot.ProfileSessionId
	for _, reward in ipairs(snapshot.LastMissionRewards) do
		rememberReward(self, reward.RewardId)
	end
end

local function acceptRewards(self: InternalController, snapshot: ProfileSnapshot)
	if self._profileSessionId ~= snapshot.ProfileSessionId then
		baselineSession(self, snapshot)
		return
	end
	local newRewards = StarterMissionUIController.SortedNewRewards(snapshot.LastMissionRewards, self._seenRewardIds)
	for _, reward in ipairs(newRewards) do
		rememberReward(self, reward.RewardId)
		table.insert(self._rewardQueue, reward)
	end
	startRewardWorker(self)
end

local function clearSelectionInside(self: InternalController)
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected:IsDescendantOf(self._panel) then
		GuiService.SelectedObject = nil
	end
end

local function setPanelOpen(self: InternalController, open: boolean)
	if self._destroyed or (open and not panelAllowed(self)) or self._panelOpen == open then
		return
	end
	self._panelOpen = open
	self._callbacks.MenuOpenChanged(open)
	for _, row in ipairs(self._rows) do
		row.Root.Selectable = open
	end
	if open then
		self._panel.Visible = true
		if self._inputMode == "Gamepad" then
			GuiService.SelectedObject = self._rows[1].Root
		end
	else
		clearSelectionInside(self)
		self._panel.Visible = false
	end
end

function StarterMissionUIController.new(root: GuiObject, callbacks: Callbacks): Controller
	local card = requireFrame(root, "StarterMissionCard")
	local cardProgress = requireFrame(card, "ProgressBar")
	local panel = requireFrame(root, "StarterPathPanel")
	local missions = requireFrame(panel, "Missions")
	local banner = requireFrame(root, "MissionCompleteBanner")
	local rows: { MissionRow } = {}
	for index = 1, StarterMissionDefinitions.TotalCount do
		local row = requireButton(missions, string.format("Mission_%02d", index))
		local progressBar = requireFrame(row, "ProgressBar")
		local stroke = requireStroke(row, "Stroke")
		table.insert(rows, {
			Root = row,
			Status = requireLabel(row, "Status"),
			MissionName = requireLabel(row, "MissionName"),
			Description = requireLabel(row, "Description"),
			ProgressText = requireLabel(row, "ProgressText"),
			RewardText = requireLabel(row, "RewardText"),
			Fill = requireFrame(progressBar, "Fill"),
			Stroke = stroke,
		})
	end
	local self: InternalController = setmetatable({
		_callbacks = callbacks,
		_card = card,
		_cardMissionName = requireLabel(card, "MissionName"),
		_cardDescription = requireLabel(card, "Description"),
		_cardProgressText = requireLabel(card, "ProgressText"),
		_cardProgressBar = cardProgress,
		_cardFill = requireFrame(cardProgress, "Fill"),
		_cardRewardText = requireLabel(card, "RewardText"),
		_openButton = requireButton(card, "OpenPathButton"),
		_panel = panel,
		_panelSummary = requireLabel(panel, "Summary"),
		_closeButton = requireButton(panel, "CloseButton"),
		_rows = rows,
		_banner = banner,
		_bannerHeader = requireLabel(banner, "Header"),
		_bannerMissionName = requireLabel(banner, "MissionName"),
		_bannerRewardText = requireLabel(banner, "RewardText"),
		_bannerPathProgress = requireLabel(banner, "PathProgress"),
		_connections = {},
		_profileSnapshot = nil,
		_roundSnapshot = nil,
		_assigned = false,
		_inputMode = "KeyboardMouse",
		_layoutClass = "Wide",
		_panelOpen = false,
		_cardProgressTween = nil,
		_seenRewardIds = {},
		_seenRewardOrder = {},
		_rewardQueue = {},
		_rewardWorkerActive = false,
		_rewardEpoch = 0,
		_bannerTween = nil,
		_bannerRestPosition = banner.Position,
		_presentationBlocked = false,
		_profileSessionId = nil,
		_roundGeneration = 0,
		_destroyed = false,
	}, ControllerMethods) :: InternalController
	card.Visible = false
	panel.Visible = false
	banner.Visible = false
	for _, row in ipairs(rows) do
		row.Root.Selectable = false
	end
	table.insert(self._connections, self._openButton.Activated:Connect(function()
		setPanelOpen(self, true)
	end))
	table.insert(self._connections, self._closeButton.Activated:Connect(function()
		setPanelOpen(self, false)
	end))
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if self._destroyed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local key = input.KeyCode
		if self._panelOpen and (key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB) then
			setPanelOpen(self, false)
			return
		end
		if gameProcessed then
			return
		end
		if (self._inputMode == "KeyboardMouse" and key == Enum.KeyCode.M)
			or (self._inputMode == "Gamepad" and key == Enum.KeyCode.ButtonL1)
		then
			setPanelOpen(self, not self._panelOpen)
		end
	end))
	return self
end

function ControllerMethods.ApplyProfileSnapshot(self: InternalController, snapshot: ProfileSnapshot)
	if self._destroyed then
		return
	end
	local previous = self._profileSnapshot
	self._profileSnapshot = snapshot
	acceptRewards(self, snapshot)
	if self._panelOpen and not panelAllowed(self) then
		setPanelOpen(self, false)
	end
	render(self, previous)
end

function ControllerMethods.ApplyRoundSnapshot(self: InternalController, snapshot: RoundSnapshot, assigned: boolean)
	if self._destroyed then
		return
	end
	local previous = self._roundSnapshot
	local wasAssigned = self._assigned
	if assigned and (not wasAssigned or previous == nil or previous.RoundId ~= snapshot.RoundId) then
		self._roundGeneration += 1
	end
	self._roundSnapshot = snapshot
	self._assigned = assigned
	if self._panelOpen and not panelAllowed(self) then
		setPanelOpen(self, false)
	end
	local profile = self._profileSnapshot
	if profile ~= nil then
		renderCard(self, profile, profile)
	end
end

function ControllerMethods.SetInputMode(self: InternalController, mode: InputMode)
	if self._destroyed then
		return
	end
	self._inputMode = mode
	self._openButton.Text = if mode == "KeyboardMouse"
		then "OPEN  [M]"
		elseif mode == "Touch" then "OPEN PATH" else "OPEN  [L1]"
	self._closeButton.Text = if mode == "Gamepad" then "CLOSE  [B]" else "CLOSE"
	if self._panelOpen and mode == "Gamepad" then
		GuiService.SelectedObject = self._rows[1].Root
	elseif mode ~= "Gamepad" then
		clearSelectionInside(self)
	end
end

function ControllerMethods.SetLayoutClass(self: InternalController, layoutClass: LayoutClass)
	if self._destroyed then
		return
	end
	self._layoutClass = layoutClass
	local profile = self._profileSnapshot
	if profile ~= nil then
		updateCardSize(self, profile.StarterMissions.PathCompleted)
	end
end

function ControllerMethods.SetPanelOpen(self: InternalController, isOpen: boolean)
	setPanelOpen(self, isOpen)
end

function ControllerMethods.IsPanelOpen(self: InternalController): boolean
	return self._panelOpen
end

function ControllerMethods.SetPresentationBlocked(self: InternalController, blocked: boolean)
	if self._destroyed or self._presentationBlocked == blocked then
		return
	end
	self._presentationBlocked = blocked
	if blocked then
		-- The active reward remains at the head of the queue. Pausing invalidates
		-- the worker without consuming it, so completion guidance can take visual
		-- priority and the reward resumes exactly once afterward.
		pauseBanner(self)
	else
		startRewardWorker(self)
	end
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._callbacks.MenuOpenChanged(false)
	self._panelOpen = false
	self._cardProgressTween = cancelTween(self._cardProgressTween)
	cancelBanner(self)
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	clearSelectionInside(self)
	self._card.Visible = false
	self._panel.Visible = false
	self._banner.Visible = false
end

return table.freeze(StarterMissionUIController)
