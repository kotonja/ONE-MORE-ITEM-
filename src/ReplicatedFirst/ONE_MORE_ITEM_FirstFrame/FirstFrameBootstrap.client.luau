--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MINIMUM_FIRST_FRAME_HOLD = 0.65

local packageRoot = script.Parent
local template = packageRoot:WaitForChild("FirstFrameCurtain", 10)
if template == nil or not template:IsA("ScreenGui") then
	error("FirstFrameBootstrap requires authored ReplicatedFirst.ONE_MORE_ITEM_FirstFrame.FirstFrameCurtain ScreenGui")
end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
if playerGui == nil or not playerGui:IsA("PlayerGui") then
	error("FirstFrameBootstrap requires LocalPlayer.PlayerGui")
end

local overlay = template:Clone()
overlay.Name = "ONE_MORE_ITEM_FirstFrame"
overlay.ResetOnSpawn = false
overlay.Enabled = true
overlay.Parent = playerGui
local overlayMountedAt = os.clock()
packageRoot:SetAttribute("OverlayMounted", true)
packageRoot:SetAttribute("HandoffComplete", false)

-- Mount the authored opaque overlay before dismissing Roblox's default loader,
-- so there is never an uncovered frame between the two presentation layers.
ReplicatedFirst:RemoveDefaultLoadingScreen()

local shared = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM"):WaitForChild("Shared")
local presentation = shared:WaitForChild("Presentation")
local FirstFrameHandoffPolicy = require(presentation:WaitForChild("FirstFrameHandoffPolicy"))

local connections: { RBXScriptConnection } = {}
local completed = false
local handoffScheduled = false

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local gameplayGui = playerGui:WaitForChild("ONE_MORE_ITEM_Gameplay", 30)
if gameplayGui == nil or not gameplayGui:IsA("ScreenGui") then
	warn("[ONE_MORE_ITEM][FirstFrame] Canonical gameplay ScreenGui was not available; retaining safe overlay")
	return
end

local curtain = gameplayGui:WaitForChild("ArrivalCurtain", 30)
if curtain == nil or not curtain:IsA("GuiObject") then
	warn("[ONE_MORE_ITEM][FirstFrame] Canonical ArrivalCurtain was not available; retaining safe overlay")
	return
end

local tryHandoff: () -> ()
tryHandoff = function()
	local presentationState = curtain:GetAttribute("PresentationState")
	if completed
		or curtain.Parent == nil
		or not FirstFrameHandoffPolicy.ShouldHandoff(
			curtain.Visible,
			curtain:GetAttribute("CameraSafe") == true,
			if type(presentationState) == "string" then presentationState else nil
		)
	then
		return
	end
	local remainingHold = MINIMUM_FIRST_FRAME_HOLD - (os.clock() - overlayMountedAt)
	if remainingHold > 0 then
		if not handoffScheduled then
			handoffScheduled = true
			task.delay(remainingHold, function()
				handoffScheduled = false
				tryHandoff()
			end)
		end
		return
	end
	completed = true
	disconnectAll()
	overlay:Destroy()
	packageRoot:SetAttribute("OverlayMounted", false)
	packageRoot:SetAttribute("HandoffComplete", true)
end

table.insert(connections, curtain:GetPropertyChangedSignal("Visible"):Connect(tryHandoff))
table.insert(connections, curtain:GetAttributeChangedSignal("CameraSafe"):Connect(tryHandoff))
table.insert(connections, curtain:GetAttributeChangedSignal("PresentationState"):Connect(tryHandoff))
table.insert(connections, curtain.Destroying:Connect(function()
	disconnectAll()
end))
tryHandoff()
