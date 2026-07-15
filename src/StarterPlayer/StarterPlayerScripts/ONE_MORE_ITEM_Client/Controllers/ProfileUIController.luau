--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientProfileStore = require(script.Parent.ClientProfileStore)
local ClientRoundStore = require(script.Parent.ClientRoundStore)
local PresentationTokens = require(script.Parent.PresentationTokens)
local ProfileResponsiveLayout = require(script.Parent.ProfileResponsiveLayout)

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local content = shared:WaitForChild("Content")
local profile = shared:WaitForChild("Profile")
local DevelopmentItemDefinitions = require(content:WaitForChild("DevelopmentItemDefinitions"))
local MasteryDefinitions = require(profile:WaitForChild("MasteryDefinitions"))
local PackingRankDefinitions = require(profile:WaitForChild("PackingRankDefinitions"))

type ProfileSnapshot = ClientProfileStore.Snapshot
type ProgressionReward = ClientProfileStore.ProgressionReward
type RoundSnapshot = ClientRoundStore.Snapshot
type Cell = ClientRoundStore.Cell
type LayoutClass = ProfileResponsiveLayout.LayoutClass

type NumberAnimation = {
	From: number,
	Target: number,
	StartedAt: number,
	Duration: number,
}

type CollectionSlot = {
	Button: TextButton,
	Viewport: ViewportFrame,
	ItemName: TextLabel,
	LockOverlay: TextLabel,
	MasteryTier: TextLabel,
	MasteryCount: TextLabel,
	MasteryProgress: Frame,
	ProgressBaseSize: UDim2,
}

type RevealEvent = {
	Kind: "Rank" | "Discovery" | "Mastery",
	ItemId: string?,
	Label: string,
	MasteryCount: number?,
	RankName: string?,
	RankDelta: number?,
}

type UIReferences = {
	TapeLabel: TextLabel,
	TapeValue: TextLabel,
	RankName: TextLabel,
	RankProgressText: TextLabel,
	DataStatus: TextLabel,
	CollectionSummary: TextLabel,
	RankSummary: TextLabel,
	StatsSummary: TextLabel,
	DiscoveryViewport: ViewportFrame,
	DiscoveryItemName: TextLabel,
	DiscoveryLabel: TextLabel,
	DiscoveryMastery: TextLabel,
	RankLabel: TextLabel,
	RankUpName: TextLabel,
	XPReward: TextLabel,
	RankProgress: TextLabel,
	DiscoverySummary: TextLabel,
}

export type Callbacks = {
	MenuOpenChanged: (isOpen: boolean) -> (),
	AudioHook: (eventName: string) -> (),
}

export type Controller = {
	ApplyProfileSnapshot: (self: Controller, snapshot: ProfileSnapshot) -> (),
	ApplyRoundSnapshot: (self: Controller, snapshot: RoundSnapshot, assigned: boolean) -> (),
	SetLayoutClass: (self: Controller, layoutClass: LayoutClass) -> (),
	IsMenuOpen: (self: Controller) -> boolean,
	Destroy: (self: Controller) -> (),
}

type InternalController = Controller & {
	_root: GuiObject,
	_template: BasePart,
	_callbacks: Callbacks,
	_backgroundDimmer: Frame,
	_metaBar: Frame,
	_collectionPanel: Frame,
	_discoveryReveal: Frame,
	_rankUpBanner: Frame,
	_collectionButton: TextButton,
	_closeButton: TextButton,
	_rankFill: Frame,
	_labels: UIReferences,
	_slots: { CollectionSlot },
	_slotRenderKeys: { [number]: string },
	_connections: { RBXScriptConnection },
	_profileSnapshot: ProfileSnapshot?,
	_roundSnapshot: RoundSnapshot?,
	_roundAssigned: boolean,
	_layoutClass: LayoutClass,
	_panelOpen: boolean,
	_panelEpoch: number,
	_panelTween: Tween?,
	_numberAnimations: { [string]: NumberAnimation },
	_displayedNumbers: { [string]: number },
	_authoritativeNumbers: { [string]: number },
	_resultOutcomeIds: { [string]: boolean },
	_resultOutcomeOrder: { string },
	_resultRoundIds: { [number]: boolean },
	_resultRoundOrder: { number },
	_revealedOutcomeIds: { [string]: boolean },
	_revealedOutcomeOrder: { string },
	_revealQueue: { RevealEvent },
	_revealWorkerActive: boolean,
	_revealEpoch: number,
	_revealTween: Tween?,
	_rankTween: Tween?,
	_dimmerTween: Tween?,
	_destroyed: boolean,
}

local ProfileUIController = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

local RUNTIME_WORLD_NAME = "ONE_MORE_ITEM_ProfilePreviewWorld"
local RUNTIME_CAMERA_NAME = "ONE_MORE_ITEM_ProfilePreviewCamera"
local TAPE_DURATION = 0.68
local XP_DURATION = 0.55
local MASTERY_DURATION = 0.35
local CORRELATION_HISTORY_LIMIT = 256

local function requireGui(parent: Instance, name: string): GuiObject
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("GuiObject") then
		error(string.format("ProfileUIController requires GuiObject %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireFrame(parent: Instance, name: string): Frame
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("Frame") then
		error(string.format("ProfileUIController requires Frame %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireLabel(parent: Instance, name: string): TextLabel
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextLabel") then
		error(string.format("ProfileUIController requires TextLabel %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireButton(parent: Instance, name: string): TextButton
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("TextButton") then
		error(string.format("ProfileUIController requires TextButton %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function requireViewport(parent: Instance, name: string): ViewportFrame
	local child = parent:WaitForChild(name, 10)
	if child == nil or not child:IsA("ViewportFrame") then
		error(string.format("ProfileUIController requires ViewportFrame %s.%s", parent:GetFullName(), name), 3)
	end
	return child
end

local function scaledSize(size: UDim2, scale: number): UDim2
	return UDim2.fromScale(size.X.Scale * scale, size.Y.Scale * scale)
end

local function clearPreview(viewport: ViewportFrame)
	local world = viewport:FindFirstChild(RUNTIME_WORLD_NAME)
	if world ~= nil then
		world:Destroy()
	end
	local camera = viewport:FindFirstChild(RUNTIME_CAMERA_NAME)
	if camera ~= nil then
		camera:Destroy()
	end
	viewport.CurrentCamera = nil
end

local function cellBounds(cells: { Cell }): (Vector3, Vector3)
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, cell in ipairs(cells) do
		local point = Vector3.new(cell.X, cell.Y, cell.Z)
		minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
		maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
	end
	return minimum, maximum
end

local function renderPreview(
	self: InternalController,
	viewport: ViewportFrame,
	itemId: string,
	discovered: boolean,
	rotate: boolean
)
	clearPreview(viewport)
	local definition = DevelopmentItemDefinitions.Get(itemId)
	if definition == nil or #definition.Shape.Cells == 0 then
		return
	end

	local world = Instance.new("WorldModel")
	world.Name = RUNTIME_WORLD_NAME
	world.Parent = viewport
	local model = Instance.new("Model")
	model.Name = "PreviewItem"
	model.Parent = world
	local minimum, maximum = cellBounds(definition.Shape.Cells)
	local center = (minimum + maximum) * 0.5
	local color = if discovered then definition.Color else Color3.fromRGB(28, 34, 43)
	for index, cell in ipairs(definition.Shape.Cells) do
		local block = self._template:Clone()
		block.Name = string.format("Cell_%02d", index)
		block.Anchored = true
		block.CanCollide = false
		block.CanTouch = false
		block.CanQuery = false
		block.Color = color
		block.Material = if discovered then Enum.Material.SmoothPlastic else Enum.Material.Slate
		block.Transparency = if discovered then 0 else 0.12
		block.CFrame = CFrame.new((Vector3.new(cell.X, cell.Y, cell.Z) - center) * 1.55)
		block.Parent = model
	end

	local camera = Instance.new("Camera")
	camera.Name = RUNTIME_CAMERA_NAME
	camera.FieldOfView = 35
	local span = maximum - minimum + Vector3.one
	local distance = math.max(6, span.Magnitude * 2.1)
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.72, distance * 0.56, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if rotate then
		local rotation = Instance.new("CFrameValue")
		rotation.Value = CFrame.Angles(0, math.rad(-24), 0)
		rotation.Parent = world
		model:PivotTo(rotation.Value)
		local connection = rotation:GetPropertyChangedSignal("Value"):Connect(function()
			if not self._destroyed and model.Parent ~= nil then
				model:PivotTo(rotation.Value)
			end
		end)
		local tween = TweenService:Create(
			rotation,
			TweenInfo.new(0.62, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Value = CFrame.Angles(0, math.rad(336), 0) }
		)
		tween.Completed:Once(function()
			connection:Disconnect()
			if rotation.Parent ~= nil then
				rotation:Destroy()
			end
		end)
		tween:Play()
	end
end

local function discoveredSet(snapshot: ProfileSnapshot): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, itemId in ipairs(snapshot.DiscoveredItemIds) do
		result[itemId] = true
	end
	return result
end

local function masteryText(count: number, discovered: boolean): (string, string, number)
	if not discovered then
		return "", "", 0
	end
	local progress = MasteryDefinitions.GetMasteryProgress(count, true)
	if progress.Tier == "Gold" then
		return "GOLD", "50+ SHIPMENTS", 1
	end
	local nextThreshold = progress.NextThreshold or count
	return string.upper(progress.Tier), string.format("%d / %d SHIPMENTS", count, nextThreshold), progress.Fraction
end

local function renderSlot(self: InternalController, index: number, countOverride: number?)
	local snapshot = self._profileSnapshot
	local definition = DevelopmentItemDefinitions.Ordered[index]
	local slot = self._slots[index]
	if snapshot == nil or definition == nil or slot == nil then
		return
	end
	local found = false
	for _, discoveredId in ipairs(snapshot.DiscoveredItemIds) do
		if discoveredId == definition.Id then
			found = true
			break
		end
	end
	local count = math.max(0, math.floor(countOverride or snapshot.MasteryCounts[definition.Id] or 0))
	local tierText, countText, fraction = masteryText(count, found)
	local tierColor = Color3.fromRGB(156, 92, 225)
	if tierText == "BRONZE" then
		tierColor = Color3.fromRGB(201, 146, 76)
	elseif tierText == "SILVER" then
		tierColor = Color3.fromRGB(190, 205, 220)
	elseif tierText == "GOLD" then
		tierColor = Color3.fromRGB(255, 213, 96)
	end
	slot.ItemName.Text = if found then string.upper(definition.DisplayName) else "???"
	slot.ItemName.TextColor3 = if found then Color3.fromRGB(245, 247, 250) else Color3.fromRGB(104, 116, 130)
	slot.LockOverlay.Visible = not found
	slot.MasteryTier.Text = tierText
	slot.MasteryTier.TextColor3 = tierColor
	slot.MasteryTier.Visible = found
	slot.MasteryCount.Text = countText
	slot.MasteryCount.Visible = found
	slot.MasteryProgress.Visible = found
	slot.MasteryProgress.BackgroundColor3 = tierColor
	slot.MasteryProgress.Size = UDim2.fromScale(slot.ProgressBaseSize.X.Scale * fraction, slot.ProgressBaseSize.Y.Scale)
	slot.Button.Selectable = found
	slot.Button.AutoButtonColor = found
	slot.Button.Interactable = found
	local renderKey = string.format("%s:%s", definition.Id, tostring(found))
	if self._slotRenderKeys[index] ~= renderKey then
		self._slotRenderKeys[index] = renderKey
		renderPreview(self, slot.Viewport, definition.Id, found, false)
	end
end

local function renderRank(self: InternalController, xp: number)
	local value = math.max(0, math.round(xp))
	local progress = PackingRankDefinitions.GetProgress(value)
	self._labels.RankName.Text = string.upper(progress.RankName)
	self._labels.RankName.TextColor3 = if progress.NextRankXP == nil
		then Color3.fromRGB(255, 213, 96)
		else PresentationTokens.Color.White
	self._rankFill.BackgroundColor3 = if progress.NextRankXP == nil
		then Color3.fromRGB(255, 213, 96)
		else PresentationTokens.Color.Cyan
	if progress.NextRankXP == nil then
		self._labels.RankProgressText.Text = string.format("MAX RANK  |  %d XP", value)
		self._rankFill.Size = UDim2.fromScale(1, 1)
	else
		self._labels.RankProgressText.Text = string.format(
			"%d / %d XP",
			progress.XPIntoRank,
			progress.XPRequiredForNextRank
		)
		self._rankFill.Size = UDim2.fromScale(progress.Fraction, 1)
	end
end

local function renderNumber(self: InternalController, key: string, value: number)
	local rounded = math.round(value)
	self._displayedNumbers[key] = value
	if key == "Tape" then
		self._labels.TapeValue.Text = tostring(rounded)
	elseif key == "PackingXP" then
		renderRank(self, rounded)
	else
		local itemId = string.match(key, "^Mastery:(.+)$")
		if itemId ~= nil then
			for index, definition in ipairs(DevelopmentItemDefinitions.Ordered) do
				if definition.Id == itemId then
					renderSlot(self, index, rounded)
					break
				end
			end
		end
	end
end

local function setNumberTarget(self: InternalController, key: string, target: number, duration: number)
	local normalized = math.max(0, math.floor(target))
	local previousTarget = self._authoritativeNumbers[key]
	self._authoritativeNumbers[key] = normalized
	if previousTarget == nil then
		self._numberAnimations[key] = nil
		renderNumber(self, key, normalized)
		return
	end
	if previousTarget == normalized then
		return
	end
	local from = self._displayedNumbers[key] or previousTarget
	self._numberAnimations[key] = {
		From = from,
		Target = normalized,
		StartedAt = os.clock(),
		Duration = duration,
	}
end

local function updateNumberAnimations(self: InternalController)
	local now = os.clock()
	for key, animation in pairs(self._numberAnimations) do
		local alpha = math.clamp((now - animation.StartedAt) / animation.Duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		renderNumber(self, key, animation.From + (animation.Target - animation.From) * eased)
		if alpha >= 1 then
			self._numberAnimations[key] = nil
			renderNumber(self, key, animation.Target)
		end
	end
end

local function dataUsable(snapshot: ProfileSnapshot?): boolean
	if snapshot == nil then
		return false
	end
	return snapshot.State == "Ready" or snapshot.State == "Saving" or snapshot.State == "SaveDelayed"
end

local function collectionAllowed(self: InternalController): boolean
	if not dataUsable(self._profileSnapshot) then
		return false
	end
	local snapshot = self._roundSnapshot
	return not self._roundAssigned or snapshot == nil or snapshot.State == "Results"
end

local function updateCollectionButton(self: InternalController)
	local enabled = collectionAllowed(self)
	self._collectionButton.Active = enabled
	self._collectionButton.Interactable = enabled
	self._collectionButton.AutoButtonColor = enabled
	self._collectionButton.TextTransparency = if enabled then 0 else 0.5
	self._collectionButton.BackgroundTransparency = if enabled then 0 else 0.45
	if not enabled and self._panelOpen then
		self._panelEpoch += 1
		self._panelOpen = false
		if self._panelTween ~= nil then
			self._panelTween:Cancel()
			self._panelTween = nil
		end
		self._callbacks.MenuOpenChanged(false)
		self._collectionPanel.Visible = false
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(self._collectionPanel) then
			GuiService.SelectedObject = nil
		end
	end
end

local function updateMetaBarGeometry(self: InternalController)
	local layout = ProfileResponsiveLayout.Resolve(self._layoutClass)
	local geometry = if self._roundSnapshot ~= nil and self._roundSnapshot.State == "Results"
		then layout.ResultsMetaBar
		else layout.MetaBar
	self._metaBar.Position = geometry.Position
	self._metaBar.Size = geometry.Size
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return string.find(inputType.Name, "Gamepad", 1, true) ~= nil
end

local function cancelPanelTween(self: InternalController)
	if self._panelTween ~= nil then
		self._panelTween:Cancel()
		self._panelTween = nil
	end
end

local function setPanelOpen(self: InternalController, open: boolean)
	if self._destroyed or (open and not collectionAllowed(self)) or self._panelOpen == open then
		return
	end
	self._panelOpen = open
	self._panelEpoch += 1
	local epoch = self._panelEpoch
	cancelPanelTween(self)
	local layout = ProfileResponsiveLayout.Resolve(self._layoutClass).CollectionPanel
	self._callbacks.MenuOpenChanged(open)
	if open then
		self._collectionPanel.Visible = true
		self._collectionPanel.Position = UDim2.fromScale(layout.Position.X.Scale, layout.Position.Y.Scale + 0.025)
		self._panelTween = TweenService:Create(
			self._collectionPanel,
			TweenInfo.new(PresentationTokens.Timing.Panel, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = layout.Position }
		)
		if isGamepadInput(UserInputService:GetLastInputType()) then
			local selection: GuiObject = self._closeButton
			for _, slot in ipairs(self._slots) do
				if slot.Button.Selectable then
					selection = slot.Button
					break
				end
			end
			GuiService.SelectedObject = selection
		end
	else
		local target = UDim2.fromScale(layout.Position.X.Scale, layout.Position.Y.Scale + 0.025)
		self._panelTween = TweenService:Create(
			self._collectionPanel,
			TweenInfo.new(PresentationTokens.Timing.Quick, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = target }
		)
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(self._collectionPanel) then
			GuiService.SelectedObject = nil
		end
	end
	local tween = self._panelTween :: Tween
	tween.Completed:Once(function(playbackState)
		if self._destroyed or epoch ~= self._panelEpoch or self._panelTween ~= tween then
			return
		end
		self._panelTween = nil
		if playbackState == Enum.PlaybackState.Completed and not open then
			self._collectionPanel.Visible = false
			self._collectionPanel.Position = layout.Position
		end
	end)
	tween:Play()
end

local function applyDataStatus(self: InternalController, snapshot: ProfileSnapshot?)
	local text = "LOADING PROFILE"
	local color = PresentationTokens.Color.Cyan
	if snapshot ~= nil then
		local state = snapshot.State
		local saveState = snapshot.SaveState
		if state == "Conflict" or saveState == "Conflict" then
			text = "PROFILE OPEN ELSEWHERE"
			color = PresentationTokens.Color.Red
		elseif state == "Unavailable" or saveState == "Unavailable" then
			text = "DATA UNAVAILABLE"
			color = PresentationTokens.Color.Red
		elseif state == "Releasing" or saveState == "Releasing" then
			text = "RELEASING"
			color = PresentationTokens.Color.Amber
		elseif state == "Released" or saveState == "Released" then
			text = "PROFILE RELEASED"
			color = PresentationTokens.Color.SecondaryText
		elseif state == "SaveDelayed" or saveState == "SaveDelayed" then
			text = "SAVE DELAYED"
			color = PresentationTokens.Color.Amber
		elseif state == "Saving" or saveState == "Saving" then
			text = "SAVING"
			color = PresentationTokens.Color.Cyan
		elseif state == "Ready" and saveState == "Saved" then
			text = "SAVED"
			color = Color3.fromRGB(93, 181, 116)
		end
	end
	self._labels.DataStatus.Text = text
	self._labels.DataStatus.TextColor3 = color
end

local function updateProfileCopy(self: InternalController, snapshot: ProfileSnapshot)
	self._labels.CollectionSummary.Text = string.format(
		"COLLECTION  %d / %d",
		snapshot.CollectionDiscoveredCount,
		snapshot.CollectionTotalCount
	)
	self._labels.RankSummary.Text = string.format(
		"RANK %d  |  %s\n%d PACKING XP",
		snapshot.RankIndex,
		string.upper(snapshot.RankName),
		snapshot.PackingXP
	)
	local stats = snapshot.Stats
	self._labels.StatsSummary.Text = string.format(
		"SHIP %d  |  ITEMS %d  |  HIGH %d\nBEST %d  |  PERFECT %d  |  FAIL %d\nTAPE EARNED %d",
		stats.TotalSuccessfulShipments,
		stats.TotalItemsShipped,
		stats.HighestItemsInShipment,
		stats.BestShipmentValue,
		stats.PerfectShipments,
		stats.TotalFailedRounds,
		stats.TotalTapeEarned
	)
end

local function resultMatchesReward(snapshot: RoundSnapshot, reward: ProgressionReward): boolean
	if snapshot.OutcomeId ~= nil and snapshot.OutcomeId ~= "" then
		return snapshot.OutcomeId == reward.OutcomeId
	end
	return snapshot.RoundId == reward.RoundId
end

local function rememberString(set: { [string]: boolean }, order: { string }, value: string)
	if set[value] then
		return
	end
	set[value] = true
	table.insert(order, value)
	if #order > CORRELATION_HISTORY_LIMIT then
		local removed = table.remove(order, 1)
		set[removed] = nil
	end
end

local function rememberNumber(set: { [number]: boolean }, order: { number }, value: number)
	if set[value] then
		return
	end
	set[value] = true
	table.insert(order, value)
	if #order > CORRELATION_HISTORY_LIMIT then
		local removed = table.remove(order, 1)
		set[removed] = nil
	end
end

local function renderResultReward(self: InternalController, reward: ProgressionReward)
	self._labels.XPReward.Text = string.format("+%d PACKING XP", reward.XPDelta)
	if reward.OutcomeType == "Failure" then
		self._labels.XPReward.Text = string.format("CONSOLATION  +%d PACKING XP", reward.XPDelta)
	end
	local rankProgress = PackingRankDefinitions.GetProgress(reward.NewXP)
	self._labels.RankProgress.Text = if rankProgress.NextRankXP == nil
		then string.format("%s  |  MAX RANK", string.upper(reward.NewRank.Name))
		else string.format(
			"%s  |  %d / %d XP",
			string.upper(reward.NewRank.Name),
			rankProgress.XPIntoRank,
			rankProgress.XPRequiredForNextRank
		)
	if #reward.NewDiscoveries > 0 then
		self._labels.DiscoverySummary.Text = string.format(
			"%d NEW ITEM%s DISCOVERED",
			#reward.NewDiscoveries,
			if #reward.NewDiscoveries == 1 then "" else "S"
		)
	else
		local masteryUps = 0
		for _, change in ipairs(reward.MasteryChanges) do
			if change.NewTier ~= change.PreviousTier and change.NewTier ~= "Discovered" then
				masteryUps += 1
			end
		end
		self._labels.DiscoverySummary.Text = if masteryUps > 0
			then string.format("%d MASTERY TIER%s EARNED", masteryUps, if masteryUps == 1 then "" else "S")
			else "COLLECTION UPDATED"
	end
end

local function enqueueRewardReveals(self: InternalController, reward: ProgressionReward)
	if reward.NewRank.Index > reward.PreviousRank.Index then
		table.insert(self._revealQueue, {
			Kind = "Rank",
			ItemId = nil,
			Label = "PACKING RANK UP",
			MasteryCount = nil,
			RankName = reward.NewRank.Name,
			RankDelta = reward.NewRank.Index - reward.PreviousRank.Index,
		})
	end
	for _, itemId in ipairs(reward.NewDiscoveries) do
		local count = if self._profileSnapshot ~= nil
			then self._profileSnapshot.MasteryCounts[itemId] or 0
			else 0
		for _, change in ipairs(reward.MasteryChanges) do
			if change.ItemId == itemId then
				count = change.NewCount
				break
			end
		end
		table.insert(self._revealQueue, {
			Kind = "Discovery",
			ItemId = itemId,
			Label = "NEW ITEM DISCOVERED",
			MasteryCount = count,
			RankName = nil,
			RankDelta = nil,
		})
	end
	for _, change in ipairs(reward.MasteryChanges) do
		if change.NewTier ~= change.PreviousTier
			and (change.NewTier == "Bronze" or change.NewTier == "Silver" or change.NewTier == "Gold")
		then
			table.insert(self._revealQueue, {
				Kind = "Mastery",
				ItemId = change.ItemId,
				Label = string.format("MASTERY %s", string.upper(change.NewTier)),
				MasteryCount = change.NewCount,
				RankName = nil,
				RankDelta = nil,
			})
		end
	end
end

local function cancelTween(tween: Tween?): Tween?
	if tween ~= nil then
		tween:Cancel()
	end
	return nil
end

local function resetSessionPresentation(self: InternalController)
	self._panelEpoch += 1
	cancelPanelTween(self)
	if self._panelOpen then
		self._panelOpen = false
		self._callbacks.MenuOpenChanged(false)
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected:IsDescendantOf(self._collectionPanel) then
		GuiService.SelectedObject = nil
	end
	self._collectionPanel.Visible = false
	self._revealEpoch += 1
	self._revealWorkerActive = false
	self._revealTween = cancelTween(self._revealTween)
	self._rankTween = cancelTween(self._rankTween)
	self._dimmerTween = cancelTween(self._dimmerTween)
	self._backgroundDimmer.BackgroundTransparency = 1
	self._discoveryReveal.Visible = false
	self._rankUpBanner.Visible = false
	clearPreview(self._labels.DiscoveryViewport)
	table.clear(self._slotRenderKeys)
	table.clear(self._numberAnimations)
	table.clear(self._displayedNumbers)
	table.clear(self._authoritativeNumbers)
	table.clear(self._resultOutcomeIds)
	table.clear(self._resultOutcomeOrder)
	table.clear(self._resultRoundIds)
	table.clear(self._resultRoundOrder)
	table.clear(self._revealedOutcomeIds)
	table.clear(self._revealedOutcomeOrder)
	table.clear(self._revealQueue)
	self._labels.XPReward.Text = ""
	self._labels.RankProgress.Text = ""
	self._labels.DiscoverySummary.Text = ""
end

local function playRankReveal(self: InternalController, event: RevealEvent, epoch: number)
	local layout = ProfileResponsiveLayout.Resolve(self._layoutClass).RankUpBanner
	self._rankTween = cancelTween(self._rankTween)
	self._dimmerTween = cancelTween(self._dimmerTween)
	self._backgroundDimmer.BackgroundTransparency = 1
	local dimTween = TweenService:Create(
		self._backgroundDimmer,
		TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.62 }
	)
	self._dimmerTween = dimTween
	dimTween:Play()
	local rankDelta = event.RankDelta or 1
	self._labels.RankLabel.Text = if rankDelta > 1
		then string.format("PACKING RANK UP  |  +%d RANKS", rankDelta)
		else "PACKING RANK UP"
	self._labels.RankUpName.Text = string.upper(event.RankName or "")
	self._rankUpBanner.Visible = true
	self._rankUpBanner.Position = UDim2.fromScale(layout.Position.X.Scale, layout.Position.Y.Scale - 0.04)
	local enterTween = TweenService:Create(
		self._rankUpBanner,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = layout.Position }
	)
	self._rankTween = enterTween
	enterTween:Play()
	self._callbacks.AudioHook("RankUp")
	local roundSnapshot = self._roundSnapshot
	local activeRound = self._roundAssigned and roundSnapshot ~= nil and roundSnapshot.State ~= "Results"
	task.wait(if activeRound then 0.65 else 1.20)
	if self._destroyed or epoch ~= self._revealEpoch then
		return
	end
	layout = ProfileResponsiveLayout.Resolve(self._layoutClass).RankUpBanner
	self._rankTween = cancelTween(self._rankTween)
	self._dimmerTween = cancelTween(self._dimmerTween)
	local exitTween = TweenService:Create(
		self._rankUpBanner,
		TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(layout.Position.X.Scale, layout.Position.Y.Scale - 0.04) }
	)
	self._rankTween = exitTween
	local undimTween = TweenService:Create(
		self._backgroundDimmer,
		TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	self._dimmerTween = undimTween
	exitTween:Play()
	undimTween:Play()
	task.wait(0.22)
	if not self._destroyed and epoch == self._revealEpoch then
		self._rankUpBanner.Visible = false
		self._rankUpBanner.Position = layout.Position
	end
end

local function playItemReveal(self: InternalController, event: RevealEvent, epoch: number)
	local itemId = event.ItemId
	if itemId == nil then
		return
	end
	local definition = DevelopmentItemDefinitions.Get(itemId)
	if definition == nil then
		return
	end
	local layout = ProfileResponsiveLayout.Resolve(self._layoutClass).DiscoveryReveal
	self._revealTween = cancelTween(self._revealTween)
	self._labels.DiscoveryLabel.Text = event.Label
	self._labels.DiscoveryItemName.Text = string.upper(definition.DisplayName)
	self._labels.DiscoveryMastery.Text = string.format("%d SHIPPED", event.MasteryCount or 0)
	local isDiscovery = event.Kind == "Discovery"
	renderPreview(self, self._labels.DiscoveryViewport, itemId, not isDiscovery, not isDiscovery)
	self._discoveryReveal.Visible = true
	self._discoveryReveal.Size = scaledSize(layout.Size, 0.92)
	local enterTween = TweenService:Create(
		self._discoveryReveal,
		TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = layout.Size }
	)
	self._revealTween = enterTween
	enterTween:Play()
	if isDiscovery then
		task.wait(0.10)
		if self._destroyed or epoch ~= self._revealEpoch then
			return
		end
		renderPreview(self, self._labels.DiscoveryViewport, itemId, true, true)
	end
	self._callbacks.AudioHook(if isDiscovery then "Discovery" else "MasteryTierUp")
	local roundSnapshot = self._roundSnapshot
	local activeRound = self._roundAssigned and roundSnapshot ~= nil and roundSnapshot.State ~= "Results"
	task.wait(if activeRound then 0.55 else 1.10)
	if self._destroyed or epoch ~= self._revealEpoch then
		return
	end
	layout = ProfileResponsiveLayout.Resolve(self._layoutClass).DiscoveryReveal
	self._revealTween = cancelTween(self._revealTween)
	local exitTween = TweenService:Create(
		self._discoveryReveal,
		TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Size = scaledSize(layout.Size, 0.92) }
	)
	self._revealTween = exitTween
	exitTween:Play()
	task.wait(0.20)
	if not self._destroyed and epoch == self._revealEpoch then
		self._discoveryReveal.Visible = false
		self._discoveryReveal.Size = layout.Size
		clearPreview(self._labels.DiscoveryViewport)
	end
end

local function startRevealWorker(self: InternalController)
	if self._revealWorkerActive or self._destroyed or #self._revealQueue == 0 then
		return
	end
	self._revealWorkerActive = true
	local epoch = self._revealEpoch
	task.spawn(function()
		while not self._destroyed and epoch == self._revealEpoch and #self._revealQueue > 0 do
			local event = table.remove(self._revealQueue, 1) :: RevealEvent
			if event.Kind == "Rank" then
				playRankReveal(self, event, epoch)
			else
				playItemReveal(self, event, epoch)
			end
		end
		if epoch == self._revealEpoch then
			self._revealWorkerActive = false
		end
	end)
end

local function tryAcceptLastReward(self: InternalController)
	local profileSnapshot = self._profileSnapshot
	if profileSnapshot == nil or profileSnapshot.LastReward == nil then
		return
	end
	local reward = profileSnapshot.LastReward
	if reward.Duplicate or self._revealedOutcomeIds[reward.OutcomeId] then
		return
	end
	local matched = self._resultOutcomeIds[reward.OutcomeId] == true or self._resultRoundIds[reward.RoundId] == true
	if not matched then
		return
	end
	rememberString(self._revealedOutcomeIds, self._revealedOutcomeOrder, reward.OutcomeId)
	local roundSnapshot = self._roundSnapshot
	if roundSnapshot ~= nil and roundSnapshot.State == "Results" and resultMatchesReward(roundSnapshot, reward) then
		renderResultReward(self, reward)
	end
	enqueueRewardReveals(self, reward)
	startRevealWorker(self)
end

function ProfileUIController.new(root: GuiObject, template: BasePart, callbacks: Callbacks): Controller
	local metaBar = requireFrame(root, "MetaBar")
	local collectionPanel = requireFrame(root, "CollectionPanel")
	local discoveryReveal = requireFrame(root, "DiscoveryReveal")
	local rankUpBanner = requireFrame(root, "RankUpBanner")
	local rankProgressBar = requireFrame(metaBar, "RankProgressBar")
	local _rankProgressBackground = requireFrame(rankProgressBar, "Background")
	local resultsPanel = requireGui(root, "ResultsPanel")
	local slotsContainer = requireFrame(collectionPanel, "Slots")

	local labels: UIReferences = {
		TapeLabel = requireLabel(metaBar, "TapeLabel"),
		TapeValue = requireLabel(metaBar, "TapeValue"),
		RankName = requireLabel(metaBar, "RankName"),
		RankProgressText = requireLabel(metaBar, "RankProgressText"),
		DataStatus = requireLabel(metaBar, "DataStatus"),
		CollectionSummary = requireLabel(collectionPanel, "CollectionSummary"),
		RankSummary = requireLabel(collectionPanel, "RankSummary"),
		StatsSummary = requireLabel(collectionPanel, "StatsSummary"),
		DiscoveryViewport = requireViewport(discoveryReveal, "ItemViewport"),
		DiscoveryItemName = requireLabel(discoveryReveal, "ItemName"),
		DiscoveryLabel = requireLabel(discoveryReveal, "DiscoveryLabel"),
		DiscoveryMastery = requireLabel(discoveryReveal, "MasteryLabel"),
		RankLabel = requireLabel(rankUpBanner, "RankLabel"),
		RankUpName = requireLabel(rankUpBanner, "RankName"),
		XPReward = requireLabel(resultsPanel, "XPReward"),
		RankProgress = requireLabel(resultsPanel, "RankProgress"),
		DiscoverySummary = requireLabel(resultsPanel, "DiscoverySummary"),
	}
	local slots: { CollectionSlot } = {}
	for index = 1, #DevelopmentItemDefinitions.Ordered do
		local button = requireButton(slotsContainer, string.format("Slot_%02d", index))
		local progress = requireFrame(button, "MasteryProgress")
		table.insert(slots, {
			Button = button,
			Viewport = requireViewport(button, "ItemViewport"),
			ItemName = requireLabel(button, "ItemName"),
			LockOverlay = requireLabel(button, "LockOverlay"),
			MasteryTier = requireLabel(button, "MasteryTier"),
			MasteryCount = requireLabel(button, "MasteryCount"),
			MasteryProgress = progress,
			ProgressBaseSize = UDim2.fromScale(0.84, progress.Size.Y.Scale),
		})
	end

	local self: InternalController = setmetatable({
		_root = root,
		_template = template,
		_callbacks = callbacks,
		_backgroundDimmer = requireFrame(root, "TouchDragSurface"),
		_metaBar = metaBar,
		_collectionPanel = collectionPanel,
		_discoveryReveal = discoveryReveal,
		_rankUpBanner = rankUpBanner,
		_collectionButton = requireButton(metaBar, "CollectionButton"),
		_closeButton = requireButton(collectionPanel, "CloseButton"),
		_rankFill = requireFrame(rankProgressBar, "Fill"),
		_labels = labels,
		_slots = slots,
		_slotRenderKeys = {},
		_connections = {},
		_profileSnapshot = nil,
		_roundSnapshot = nil,
		_roundAssigned = false,
		_layoutClass = "Wide",
		_panelOpen = false,
		_panelEpoch = 0,
		_panelTween = nil,
		_numberAnimations = {},
		_displayedNumbers = {},
		_authoritativeNumbers = {},
		_resultOutcomeIds = {},
		_resultOutcomeOrder = {},
		_resultRoundIds = {},
		_resultRoundOrder = {},
		_revealedOutcomeIds = {},
		_revealedOutcomeOrder = {},
		_revealQueue = {},
		_revealWorkerActive = false,
		_revealEpoch = 0,
		_revealTween = nil,
		_rankTween = nil,
		_dimmerTween = nil,
		_destroyed = false,
	}, ControllerMethods) :: InternalController

	labels.TapeLabel.Text = "TAPE"
	labels.TapeValue.Text = "--"
	labels.RankName.Text = "LOADING"
	labels.RankProgressText.Text = "-- XP"
	labels.XPReward.Text = ""
	labels.RankProgress.Text = ""
	labels.DiscoverySummary.Text = ""
	collectionPanel.Visible = false
	discoveryReveal.Visible = false
	rankUpBanner.Visible = false
	applyDataStatus(self, nil)
	updateCollectionButton(self)
	self:SetLayoutClass("Wide")

	table.insert(self._connections, self._collectionButton.Activated:Connect(function()
		setPanelOpen(self, not self._panelOpen)
	end))
	table.insert(self._connections, self._closeButton.Activated:Connect(function()
		setPanelOpen(self, false)
	end))
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if self._destroyed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local keyCode = input.KeyCode
		if self._panelOpen and (keyCode == Enum.KeyCode.Escape or keyCode == Enum.KeyCode.ButtonB) then
			setPanelOpen(self, false)
			return
		end
		if gameProcessed then
			return
		end
		if keyCode == Enum.KeyCode.C or keyCode == Enum.KeyCode.ButtonY then
			setPanelOpen(self, not self._panelOpen)
		end
	end))
	table.insert(self._connections, RunService.RenderStepped:Connect(function()
		if not self._destroyed then
			updateNumberAnimations(self)
		end
	end))
	return self
end

function ControllerMethods.ApplyProfileSnapshot(self: InternalController, snapshot: ProfileSnapshot)
	if self._destroyed then
		return
	end
	local previous = self._profileSnapshot
	if previous ~= nil and previous.ProfileSessionId ~= snapshot.ProfileSessionId then
		resetSessionPresentation(self)
		previous = nil
	end
	self._profileSnapshot = snapshot
	applyDataStatus(self, snapshot)
	setNumberTarget(self, "Tape", snapshot.Tape, TAPE_DURATION)
	setNumberTarget(self, "PackingXP", snapshot.PackingXP, XP_DURATION)
	updateProfileCopy(self, snapshot)
	local discovered = discoveredSet(snapshot)
	for index, definition in ipairs(DevelopmentItemDefinitions.Ordered) do
		local key = "Mastery:" .. definition.Id
		local count = snapshot.MasteryCounts[definition.Id] or 0
		local changed = previous ~= nil and (previous.MasteryCounts[definition.Id] or 0) ~= count
		if changed and discovered[definition.Id] then
			setNumberTarget(self, key, count, MASTERY_DURATION)
		else
			self._authoritativeNumbers[key] = count
			self._numberAnimations[key] = nil
			renderNumber(self, key, count)
		end
	end
	updateCollectionButton(self)
	tryAcceptLastReward(self)
end

function ControllerMethods.ApplyRoundSnapshot(self: InternalController, snapshot: RoundSnapshot, assigned: boolean)
	if self._destroyed then
		return
	end
	self._roundSnapshot = snapshot
	self._roundAssigned = assigned
	updateMetaBarGeometry(self)
	if snapshot.State == "Results" and assigned then
		if snapshot.OutcomeId ~= nil and snapshot.OutcomeId ~= "" then
			rememberString(self._resultOutcomeIds, self._resultOutcomeOrder, snapshot.OutcomeId)
		else
			-- RoundId-only correlation exists solely for inherited snapshots. Phase 05
			-- snapshots always prefer the globally unique server OutcomeId.
			rememberNumber(self._resultRoundIds, self._resultRoundOrder, snapshot.RoundId)
		end
	else
		self._labels.XPReward.Text = ""
		self._labels.RankProgress.Text = ""
		self._labels.DiscoverySummary.Text = ""
	end
	updateCollectionButton(self)
	tryAcceptLastReward(self)
end

function ControllerMethods.SetLayoutClass(self: InternalController, layoutClass: LayoutClass)
	if self._destroyed then
		return
	end
	self._layoutClass = layoutClass
	local layout = ProfileResponsiveLayout.Resolve(layoutClass)
	self._panelEpoch += 1
	cancelPanelTween(self)
	if not self._panelOpen then
		self._collectionPanel.Visible = false
	end
	self._revealTween = cancelTween(self._revealTween)
	self._rankTween = cancelTween(self._rankTween)
	self._dimmerTween = cancelTween(self._dimmerTween)
	self._backgroundDimmer.BackgroundTransparency = 1
	updateMetaBarGeometry(self)
	self._collectionPanel.Size = layout.CollectionPanel.Size
	self._collectionPanel.Position = layout.CollectionPanel.Position
	self._discoveryReveal.Position = layout.DiscoveryReveal.Position
	self._discoveryReveal.Size = layout.DiscoveryReveal.Size
	self._rankUpBanner.Position = layout.RankUpBanner.Position
	self._rankUpBanner.Size = layout.RankUpBanner.Size
end

function ControllerMethods.IsMenuOpen(self: InternalController): boolean
	return self._panelOpen
end

function ControllerMethods.Destroy(self: InternalController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._panelOpen = false
	self._callbacks.MenuOpenChanged(false)
	self._panelEpoch += 1
	self._revealEpoch += 1
	cancelPanelTween(self)
	self._revealTween = cancelTween(self._revealTween)
	self._rankTween = cancelTween(self._rankTween)
	self._dimmerTween = cancelTween(self._dimmerTween)
	self._backgroundDimmer.BackgroundTransparency = 1
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, slot in ipairs(self._slots) do
		clearPreview(slot.Viewport)
	end
	clearPreview(self._labels.DiscoveryViewport)
	table.clear(self._numberAnimations)
	table.clear(self._revealQueue)
	self._collectionPanel.Visible = false
	self._discoveryReveal.Visible = false
	self._rankUpBanner.Visible = false
end

return table.freeze(ProfileUIController)
