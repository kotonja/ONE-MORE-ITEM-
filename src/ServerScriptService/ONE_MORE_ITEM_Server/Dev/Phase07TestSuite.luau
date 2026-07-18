--!strict

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
local Presentation = Root.Shared:WaitForChild("Presentation")
local VisualFraming = require(Presentation:WaitForChild("VisualFraming"))
local VisualThemeDefinitions = require(Presentation:WaitForChild("VisualThemeDefinitions"))
local FirstFrameHandoffPolicy = require(Presentation:WaitForChild("FirstFrameHandoffPolicy"))
local ClientControllers = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("ONE_MORE_ITEM_Client"):WaitForChild("Controllers")
local PresentationTokens = require(ClientControllers:WaitForChild("PresentationTokens"))
local ResponsiveLayout = require(ClientControllers:WaitForChild("ResponsiveLayout"))
local ProfileResponsiveLayout = require(ClientControllers:WaitForChild("ProfileResponsiveLayout"))
local ArrivalCurtainController = require(ClientControllers:WaitForChild("ArrivalCurtainController"))
local WorldLabelController = require(ClientControllers:WaitForChild("WorldLabelController"))
local FIELD_OF_VIEW = PresentationTokens.Camera.FieldOfView

local World = Workspace:WaitForChild("ONE_MORE_ITEM_WORLD")
local Arena = World:WaitForChild("PlaytestArena")
local Stations = Arena:WaitForChild("Stations")

type TestCase = { Name: string, Run: () -> () }
type TestSuite = { Name: string, Tests: { TestCase } }

export type TestReport = {
	Suites: number,
	Tests: number,
	Passed: number,
	Failed: number,
	Failures: { string },
	DurationSeconds: number,
	Seed: number,
	LineOfSightRays: number,
}

local Phase07TestSuite = {}
local suites: { TestSuite } = {}
local lineOfSightRays = 0

local function addSuite(name: string, tests: { TestCase })
	table.insert(suites, { Name = name, Tests = tests })
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "Expectation failed", 2)
	end
end

local function expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(message or string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

local function expectNear(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(message or string.format("Expected %.6f +/- %.6f, got %.6f", expected, tolerance, actual), 2)
	end
end

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	expect(child ~= nil, string.format("Missing %s.%s", parent:GetFullName(), name))
	expect((child :: Instance).ClassName == className, string.format(
		"%s.%s must be %s, got %s",
		parent:GetFullName(),
		name,
		className,
		(child :: Instance).ClassName
	))
	return child :: Instance
end

local function requirePart(parent: Instance, name: string): BasePart
	local child = parent:FindFirstChild(name)
	expect(child ~= nil and child:IsA("BasePart"), string.format("Missing BasePart %s.%s", parent:GetFullName(), name))
	return child :: BasePart
end

local function requirePath(parent: Instance, relativePath: string): Instance
	local current = parent
	for name in string.gmatch(relativePath, "[^.]+") do
		local child = current:FindFirstChild(name)
		expect(child ~= nil, string.format("Missing %s.%s", current:GetFullName(), name))
		current = child :: Instance
	end
	return current
end

local function stationAt(index: number): Model
	local name = string.format("Station_%02d", index)
	local station = Stations:FindFirstChild(name)
	expect(station ~= nil and station:IsA("Model"), string.format("Missing station Model %s", name))
	return station :: Model
end

local function allStations(): { Model }
	local result: { Model } = {}
	for index = 1, 8 do
		table.insert(result, stationAt(index))
	end
	return result
end

local function allBaseParts(parent: Instance): { BasePart }
	local result: { BasePart } = {}
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(result, descendant)
		end
	end
	table.sort(result, function(first: BasePart, second: BasePart): boolean
		return first:GetFullName() < second:GetFullName()
	end)
	return result
end

local function cornersForParts(parts: { BasePart }): { any }
	local points: { any } = {}
	for _, part in ipairs(parts) do
		for _, corner in ipairs(VisualFraming.GetObbCorners(part.CFrame, part.Size)) do
			table.insert(points, corner)
		end
	end
	return points
end

local function logicalInterior(station: Model): (CFrame, Vector3)
	local crate = requirePath(station, "Crate")
	local gridOrigin = requirePart(crate, "GridOrigin")
	-- Framing measures the readable layer-zero interior. Upper-layer readability is
	-- covered independently by the deterministic line-of-sight fixtures below.
	return gridOrigin.CFrame * CFrame.new(4, 0, 4), Vector3.new(10, 0.1, 10)
end

local function cameraFor(station: Model, anchorName: string): any
	local anchor = requirePart(station, anchorName)
	local focus = requirePart(station, "CameraFocus")
	return VisualFraming.NumericCameraFromLookAt(anchor.Position, focus.Position, anchor.CFrame.UpVector)
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function pointInsidePart(point: Vector3, part: BasePart, padding: number): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5 + Vector3.new(padding, padding, padding)
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function segmentIntersectsPart(origin: Vector3, target: Vector3, part: BasePart): boolean
	local localOrigin = part.CFrame:PointToObjectSpace(origin)
	local localTarget = part.CFrame:PointToObjectSpace(target)
	local direction = localTarget - localOrigin
	local half = part.Size * 0.5
	local minimumT = 0
	local maximumT = 0.995

	local function clip(axisOrigin: number, axisDirection: number, axisHalf: number): boolean
		if math.abs(axisDirection) < 1e-8 then
			return math.abs(axisOrigin) <= axisHalf
		end
		local first = (-axisHalf - axisOrigin) / axisDirection
		local second = (axisHalf - axisOrigin) / axisDirection
		if first > second then
			first, second = second, first
		end
		minimumT = math.max(minimumT, first)
		maximumT = math.min(maximumT, second)
		return minimumT <= maximumT
	end

	return clip(localOrigin.X, direction.X, half.X)
		and clip(localOrigin.Y, direction.Y, half.Y)
		and clip(localOrigin.Z, direction.Z, half.Z)
		and maximumT >= 0
		and minimumT <= 0.995
end

local function isApprovedPane(part: BasePart, station: Model): boolean
	local crate = station:FindFirstChild("Crate")
	if crate == nil or not part:IsDescendantOf(crate) then
		return false
	end
	return part.Name == "WallBack" or part.Name == "WallLeft" or part.Name == "WallRight"
end

local function ignoredLineOfSightPart(part: BasePart, station: Model, target: Vector3): boolean
	if part.Transparency >= 0.99 then
		return true
	end
	if isApprovedPane(part, station) then
		return true
	end
	if pointInsidePart(target, part, 0.03) then
		return true
	end
	return false
end

local function isTemporaryPresentationPart(part: BasePart): boolean
	local current = part.Parent
	while current ~= nil and current ~= Arena do
		if current.Name == "RuntimePresentation" then
			return true
		end
		if current.Name == "Runtime" and current.Parent ~= nil and current.Parent.Name == "ShowcaseLoop" then
			return true
		end
		current = current.Parent
	end
	return false
end

local function guiScaleArea(gui: GuiObject): number
	return gui.Size.X.Scale * gui.Size.Y.Scale
end

local function boundsOverlapArea(first: any, second: any): number
	local width = math.max(0, math.min(first.Right, second.Right) - math.max(first.Left, second.Left))
	local height = math.max(0, math.min(first.Bottom, second.Bottom) - math.max(first.Top, second.Top))
	return width * height
end

addSuite("Visual theme", {
	{
		Name = "semantic colors are exact and stable",
		Run = function()
			local expected = {
				Background = Color3.fromRGB(10, 15, 22),
				StructuralGraphite = Color3.fromRGB(21, 30, 40),
				SecondarySteel = Color3.fromRGB(34, 48, 61),
				Concrete = Color3.fromRGB(42, 48, 56),
				RubberDark = Color3.fromRGB(16, 22, 29),
				CrateWarm = Color3.fromRGB(139, 106, 66),
				CrateFloor = Color3.fromRGB(110, 92, 70),
				TextPrimary = Color3.fromRGB(245, 247, 250),
				TextSecondary = Color3.fromRGB(167, 181, 196),
				Cyan = Color3.fromRGB(34, 211, 230),
				Amber = Color3.fromRGB(255, 178, 26),
				Green = Color3.fromRGB(99, 232, 92),
				Red = Color3.fromRGB(255, 75, 62),
				Purple = Color3.fromRGB(155, 108, 255),
			}
			for name, color in pairs(expected) do
				expectEqual(VisualThemeDefinitions.Color[name], color, string.format("Color token %s drifted", name))
			end
		end,
	},
	{
		Name = "semantic definitions and nested tables are frozen",
		Run = function()
			expect(table.isfrozen(VisualThemeDefinitions))
			expect(table.isfrozen(VisualThemeDefinitions.Color))
			expect(table.isfrozen(VisualThemeDefinitions.Material))
			expect(table.isfrozen(VisualThemeDefinitions.Timing))
		end,
	},
	{
		Name = "environment material roles are non-refractive and non-semantic",
		Run = function()
			expectEqual(VisualThemeDefinitions.Material.Pane, Enum.Material.SmoothPlastic)
			expect(VisualThemeDefinitions.Material.CrateFloor ~= Enum.Material.Neon)
			expect(VisualThemeDefinitions.Material.CrateFloor ~= Enum.Material.Glass)
		end,
	},
	{
		Name = "arrival fade retains the accepted range",
		Run = function()
			expect(VisualThemeDefinitions.Timing.ArrivalCurtainFade >= 0.22)
			expect(VisualThemeDefinitions.Timing.ArrivalCurtainFade <= 0.28)
		end,
	},
})

local cameraTests: { TestCase } = {}
for _, stationIndex in ipairs({ 1, 3, 5, 7 }) do
	table.insert(cameraTests, {
		Name = string.format("Station_%02d anchors have accepted pitch and finite projection", stationIndex),
		Run = function()
			local station = stationAt(stationIndex)
			for _, anchorName in ipairs({ "CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait" }) do
				local camera = cameraFor(station, anchorName)
				local evaluation = VisualFraming.EvaluateCamera(FIELD_OF_VIEW, camera)
				expect(evaluation.Pass, string.format(
					"%s.%s failed pitch/FOV pitch=%.3f",
					station.Name,
					anchorName,
					evaluation.DownwardPitchDegrees
				))
				local projected = VisualFraming.ProjectPoint(camera, requirePart(station, "CameraFocus").Position, {
					Width = 1920,
					Height = 1080,
				}, FIELD_OF_VIEW)
				expect(projected ~= nil and isFinite(projected.X) and isFinite(projected.Y))
			end
		end,
	})
end

table.insert(cameraTests, {
	Name = "responsive anchor definitions remain distinct and stable",
	Run = function()
		local station = stationAt(1)
		local names = { "CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait" }
		local positions = {}
		for _, name in ipairs(names) do
			positions[requirePart(station, name).Position] = true
		end
		local count = 0
		for _ in pairs(positions) do
			count += 1
		end
		expectEqual(count, 3, "Responsive camera anchors must remain three distinct authored positions")
	end,
})

table.insert(cameraTests, {
	Name = "line-of-sight sample fixture is fixed at 32 deterministic targets",
	Run = function()
		local station = stationAt(1)
		local gridOrigin = requirePart(requirePath(station, "Crate"), "GridOrigin")
		local samples = VisualFraming.GenerateLineOfSightSamples({
			GridOrigin = gridOrigin.CFrame,
			CellSize = 2,
			CrateFocus = requirePart(station, "CameraFocus").Position,
			GhostFixtureCenter = gridOrigin.CFrame:PointToWorldSpace(Vector3.new(4, 2, 4)),
		})
		expectEqual(#samples, 32)
		for index, sample in ipairs(samples) do
			expectEqual(sample.Index, index)
		end
		expectEqual(samples[1].Name, "LayerZero_0_0")
		expectEqual(samples[25].Name, "LayerZero_4_4")
		expectEqual(samples[32].Name, "GhostFixture")
	end,
})

addSuite("Camera definitions", cameraTests)

local viewportProfiles = {
	{ Name = "desktop-1920x1080", Width = 1920, Height = 1080, Anchor = "CameraAnchor", Profile = "Desktop" },
	{ Name = "desktop-1366x768", Width = 1366, Height = 768, Anchor = "CameraAnchor", Profile = "Desktop" },
	{ Name = "compact-1100x700", Width = 1100, Height = 700, Anchor = "CameraAnchor", Profile = "Compact" },
	{ Name = "touch-portrait-360x640", Width = 360, Height = 640, Anchor = "CameraAnchorTouchPortrait", Profile = "TouchPortrait" },
	{ Name = "touch-portrait-430x932", Width = 430, Height = 932, Anchor = "CameraAnchorTouchPortrait", Profile = "TouchPortrait" },
	{ Name = "touch-landscape-640x360", Width = 640, Height = 360, Anchor = "CameraAnchorTouchLandscape", Profile = "TouchLandscape" },
	{ Name = "touch-landscape-932x430", Width = 932, Height = 430, Anchor = "CameraAnchorTouchLandscape", Profile = "TouchLandscape" },
}

local uiViewportProfiles = {
	{ Name = "desktop-1920x1080", Width = 1920, Height = 1080, Anchor = "CameraAnchor" },
	{ Name = "desktop-1366x768", Width = 1366, Height = 768, Anchor = "CameraAnchor" },
	{ Name = "desktop-2560x1440", Width = 2560, Height = 1440, Anchor = "CameraAnchor" },
	{ Name = "desktop-1100x700", Width = 1100, Height = 700, Anchor = "CameraAnchor" },
	{ Name = "phone-portrait-360x640", Width = 360, Height = 640, Anchor = "CameraAnchorTouchPortrait" },
	{ Name = "phone-portrait-390x844", Width = 390, Height = 844, Anchor = "CameraAnchorTouchPortrait" },
	{ Name = "phone-portrait-393x852", Width = 393, Height = 852, Anchor = "CameraAnchorTouchPortrait" },
	{ Name = "phone-portrait-430x932", Width = 430, Height = 932, Anchor = "CameraAnchorTouchPortrait" },
	{ Name = "phone-landscape-640x360", Width = 640, Height = 360, Anchor = "CameraAnchorTouchLandscape" },
	{ Name = "phone-landscape-844x390", Width = 844, Height = 390, Anchor = "CameraAnchorTouchLandscape" },
	{ Name = "phone-landscape-932x430", Width = 932, Height = 430, Anchor = "CameraAnchorTouchLandscape" },
	{ Name = "tablet-portrait-768x1024", Width = 768, Height = 1024, Anchor = "CameraAnchorTouchPortrait" },
	{ Name = "tablet-landscape-1024x768", Width = 1024, Height = 768, Anchor = "CameraAnchorTouchLandscape" },
}

local projectionTests: { TestCase } = {}
for _, stationIndex in ipairs({ 1, 5 }) do
	for _, viewportProfile in ipairs(viewportProfiles) do
		local currentProfile = viewportProfile
		table.insert(projectionTests, {
			Name = string.format("Station_%02d %s crate projection passes", stationIndex, currentProfile.Name),
			Run = function()
				local station = stationAt(stationIndex)
				local camera = cameraFor(station, currentProfile.Anchor)
				local transform, size = logicalInterior(station)
				local viewport = { Width = currentProfile.Width, Height = currentProfile.Height }
				local bounds = VisualFraming.ProjectObb(camera, transform, size, viewport, FIELD_OF_VIEW)
				expect(bounds ~= nil, "Logical crate bounds must project in front of the camera")
				local safeRect = VisualFraming.GetSafeRect(viewport)
				local thresholds = VisualFraming.AcceptanceProfiles[currentProfile.Profile]
				local evaluation = VisualFraming.EvaluateFraming(bounds :: any, safeRect, thresholds)
				expect(evaluation.Pass, string.format(
					"%s %s projection failed width=%.4f height=%.4f center=(%.4f,%.4f) contained=%s",
					station.Name,
					currentProfile.Name,
					evaluation.Occupancy.WidthRatio,
					evaluation.Occupancy.HeightRatio,
					evaluation.Occupancy.CenterXRatio,
					evaluation.Occupancy.CenterYRatio,
					tostring(evaluation.Occupancy.FullyContained)
				))
			end,
		})
	end
end

table.insert(projectionTests, {
	Name = "console rectangles do not overlap logical crate interiors",
	Run = function()
		for _, station in ipairs(allStations()) do
			local console = requirePath(station, "ControlConsole")
			local consoleParts = {
				requirePart(console, "ConsoleBase"),
				requirePart(console, "ConsoleDeck"),
				requirePart(console, "ConsoleFace"),
			}
			local camera = cameraFor(station, "CameraAnchor")
			local transform, size = logicalInterior(station)
			local viewport = { Width = 1920, Height = 1080 }
			local crateBounds = VisualFraming.ProjectObb(camera, transform, size, viewport, FIELD_OF_VIEW)
			local consoleBounds = VisualFraming.ProjectWorldBounds(camera, cornersForParts(consoleParts), viewport, FIELD_OF_VIEW)
			expect(crateBounds ~= nil and consoleBounds ~= nil)
			local overlap = VisualFraming.GetOverlap(crateBounds :: any, consoleBounds :: any)
			expect(not overlap.Intersects, string.format("%s console overlaps projected crate by %.3f px2", station.Name, overlap.Area))
		end
	end,
})

table.insert(projectionTests, {
	Name = "front-rim projected overlap remains below eight percent",
	Run = function()
		for _, station in ipairs(allStations()) do
			local crate = requirePath(station, "Crate")
			local floor = requirePart(crate, "InteriorFloor")
			local front = requirePart(crate, "WallFront")
			local camera = cameraFor(station, "CameraAnchor")
			local viewport = { Width = 1920, Height = 1080 }
			local floorBounds = VisualFraming.ProjectObb(camera, floor.CFrame, floor.Size, viewport, FIELD_OF_VIEW)
			local frontBounds = VisualFraming.ProjectObb(camera, front.CFrame, front.Size, viewport, FIELD_OF_VIEW)
			expect(floorBounds ~= nil and frontBounds ~= nil)
			local overlap = VisualFraming.GetOverlap(floorBounds :: any, frontBounds :: any)
			expect(overlap.VerticalRatioOfFirst < VisualFraming.MaximumFrontRimOverlapRatio, string.format(
				"%s front rim overlap %.4f exceeds %.4f",
				station.Name,
				overlap.VerticalRatioOfFirst,
				VisualFraming.MaximumFrontRimOverlapRatio
			))
		end
	end,
})

table.insert(projectionTests, {
	Name = "four-cell vertical-capacity corner centers remain inside every required viewport",
	Run = function()
		for _, stationIndex in ipairs({ 1, 3, 5, 7 }) do
			local station = stationAt(stationIndex)
			local gridOrigin = requirePart(requirePath(station, "Crate"), "GridOrigin")
			for _, currentProfile in ipairs(uiViewportProfiles) do
				local viewport = { Width = currentProfile.Width, Height = currentProfile.Height }
				local safeRect = VisualFraming.GetSafeRect(viewport)
				local camera = cameraFor(station, currentProfile.Anchor)
				for _, corner in ipairs({
					Vector3.new(0, 6, 0),
					Vector3.new(8, 6, 0),
					Vector3.new(0, 6, 8),
					Vector3.new(8, 6, 8),
				}) do
					local point = VisualFraming.ProjectPoint(
						camera,
						gridOrigin.CFrame:PointToWorldSpace(corner),
						viewport,
						FIELD_OF_VIEW
					)
					expect(point ~= nil, string.format("%s %s upper corner is behind the camera", station.Name, currentProfile.Name))
					local projected = point :: any
					expect(
						projected.X >= safeRect.Left and projected.X <= safeRect.Right
							and projected.Y >= safeRect.Top and projected.Y <= safeRect.Bottom,
						string.format(
							"%s %s upper corner projects outside viewport at %.3f,%.3f",
							station.Name,
							currentProfile.Name,
							projected.X,
							projected.Y
						)
					)
				end
			end
		end
	end,
})

addSuite("Camera projection", projectionTests)

addSuite("Deterministic line of sight", {
	{
		Name = "all 32 samples clear all permanent blockers from all three anchors at all eight stations",
		Run = function()
			local permanentParts: { BasePart } = {}
			for _, part in ipairs(allBaseParts(Arena)) do
				if not isTemporaryPresentationPart(part) then
					table.insert(permanentParts, part)
				end
			end
			local blockers: { string } = {}
			local rayCount = 0
			for _, station in ipairs(allStations()) do
				local crate = requirePath(station, "Crate")
				local gridOrigin = requirePart(crate, "GridOrigin")
				local samples = VisualFraming.GenerateLineOfSightSamples({
					GridOrigin = gridOrigin.CFrame,
					CellSize = 2,
					CrateFocus = requirePart(station, "CameraFocus").Position,
					GhostFixtureCenter = gridOrigin.CFrame:PointToWorldSpace(Vector3.new(4, 2, 4)),
				})
				for _, anchorName in ipairs({ "CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait" }) do
					local origin = requirePart(station, anchorName).Position
					for _, sample in ipairs(samples) do
						rayCount += 1
						local target = Vector3.new(sample.Position.X, sample.Position.Y, sample.Position.Z)
						for _, part in ipairs(permanentParts) do
							if not ignoredLineOfSightPart(part, station, target)
								and segmentIntersectsPart(origin, target, part)
							then
								table.insert(blockers, string.format(
									"%s/%s/%s blocked by %s",
									station.Name,
									anchorName,
									sample.Name,
									part:GetFullName()
								))
								break
							end
						end
					end
				end
			end
			lineOfSightRays = rayCount
			expectEqual(rayCount, 32 * 8 * 3, "Phase 07 must exercise the complete 768-ray matrix")
			expectEqual(#blockers, 0, if #blockers > 0 then table.concat(blockers, "\n") else nil)
		end,
	},
})

local crateTests: { TestCase } = {}
for stationIndex = 1, 8 do
	table.insert(crateTests, {
		Name = string.format("Station_%02d crate hierarchy and geometry satisfy the visual contract", stationIndex),
		Run = function()
			local station = stationAt(stationIndex)
			local crate = requirePath(station, "Crate")
			for _, name in ipairs({
				"Base", "InteriorFloor", "GridOrigin", "GridTiles", "WallFront", "WallBack", "WallLeft", "WallRight",
				"Lid", "CrateFocus", "Frame", "TaskLight",
			}) do
				expect(crate:FindFirstChild(name) ~= nil, string.format("%s.Crate missing %s", station.Name, name))
			end
			local stationRoot = requirePart(station, "StationRoot")
			local gridOrigin = requirePart(crate, "GridOrigin")
			local localGridFrame = stationRoot.CFrame:ToObjectSpace(gridOrigin.CFrame)
			expectNear(localGridFrame.Position.X, -4, 0.001, string.format("%s GridOrigin X", station.Name))
			expectNear(localGridFrame.Position.Y, 4, 0.001, string.format("%s GridOrigin Y", station.Name))
			expectNear(localGridFrame.Position.Z, -4, 0.001, string.format("%s GridOrigin Z", station.Name))
			expectNear(localGridFrame.RightVector:Dot(Vector3.xAxis), 1, 0.001, string.format("%s GridOrigin right axis", station.Name))
			expectNear(localGridFrame.UpVector:Dot(Vector3.yAxis), 1, 0.001, string.format("%s GridOrigin up axis", station.Name))

			local tiles = requirePath(crate, "GridTiles")
			local tileCount = 0
			for _, child in ipairs(tiles:GetChildren()) do
				if child:IsA("BasePart") and string.match(child.Name, "^Cell_%d_%d$") then
					tileCount += 1
					expect(child.Size.X >= 1.82 and child.Size.X <= 1.86)
					expect(child.Size.Z >= 1.82 and child.Size.Z <= 1.86)
					expect(child.Transparency == 0)
					expect(child.Material ~= Enum.Material.Neon)
				end
			end
			expectEqual(tileCount, 25, string.format("%s must have 25 grid tiles", station.Name))

			for _, descendant in ipairs(crate:GetDescendants()) do
				if descendant:IsA("BasePart") then
					expect(descendant.Material ~= Enum.Material.Glass, string.format("Glass rejected at %s", descendant:GetFullName()))
				end
			end

			local front = requirePart(crate, "WallFront")
			expect(front.Size.Y <= 0.55, string.format("%s WallFront is too tall", station.Name))
			expect(math.min(front.Size.X, front.Size.Z) <= 0.24, string.format("%s WallFront is too thick", station.Name))

			for _, paneName in ipairs({ "WallBack", "WallLeft", "WallRight" }) do
				local pane = requirePart(crate, paneName)
				expectEqual(pane.Material, Enum.Material.SmoothPlastic)
				expect(pane.Transparency >= 0.55 and pane.Transparency <= 0.72)
				expect(not pane.CastShadow and not pane.CanCollide and not pane.CanTouch and not pane.CanQuery)
			end

			local interiorFloor = requirePart(crate, "InteriorFloor")
			expectEqual(interiorFloor.Transparency, 0)
			expect(interiorFloor.Material ~= Enum.Material.Glass and interiorFloor.Material ~= Enum.Material.Neon)
			expectNear(interiorFloor.Size.X, 10.5, 0.001)
			expectNear(interiorFloor.Size.Z, 10.5, 0.001)

			local frame = requirePath(crate, "Frame")
			for _, postName in ipairs({ "FrontLeftPost", "FrontRightPost", "BackLeftPost", "BackRightPost" }) do
				local post = requirePart(frame, postName)
				local thickness = math.min(post.Size.X, post.Size.Z)
				expect(thickness >= 0.18 and thickness <= 0.28, string.format("%s.%s frame thickness %.3f", station.Name, postName, thickness))
			end

			local taskLightPart = requirePart(crate, "TaskLight")
			local pointLight = requireChild(taskLightPart, "Light", "PointLight") :: PointLight
			expect(pointLight.Brightness >= 1.3 and pointLight.Brightness <= 1.7)
			expect(pointLight.Range >= 16 and pointLight.Range <= 20)
			expect(not pointLight.Shadows)
		end,
	})
end

addSuite("Crate", crateTests)

addSuite("Control console", {
	{
		Name = "all consoles remain compact, matte, below the crate, and retain four controls",
		Run = function()
			for _, station in ipairs(allStations()) do
				local console = requirePath(station, "ControlConsole")
				local consoleBase = requirePart(console, "ConsoleBase")
				local consoleDeck = requirePart(console, "ConsoleDeck")
				local consoleFace = requirePart(console, "ConsoleFace")
				for _, part in ipairs({ consoleBase, consoleDeck, consoleFace }) do
					expect(part.Size.X <= 8.5, string.format("%s is wider than the console budget", part:GetFullName()))
					expect(part.Size.Z <= 3.2, string.format("%s is deeper than the console budget", part:GetFullName()))
					expect(part.Material ~= Enum.Material.Neon)
				end
				local floor = requirePart(requirePath(station, "Crate"), "InteriorFloor")
				local consoleTop = math.max(
					consoleBase.Position.Y + consoleBase.Size.Y * 0.5,
					consoleDeck.Position.Y + consoleDeck.Size.Y * 0.5,
					consoleFace.Position.Y + consoleFace.Size.Y * 0.5
				)
				local floorBottom = floor.Position.Y - floor.Size.Y * 0.5
				expect(consoleTop <= floorBottom - 0.35, string.format("%s console is not below the crate floor", station.Name))
				for _, controlName in ipairs({ "RotateButton", "PlaceButton", "ShipButton", "OneMoreButton" }) do
					local control = requirePart(console, controlName)
					expect(control.Material ~= Enum.Material.Glass)
				end
			end
		end,
	},
})

addSuite("Arena", {
	{
		Name = "eight deterministic stations occupy the wider non-overlapping ring",
		Run = function()
			local previousPosition: Vector3? = nil
			local firstPosition: Vector3? = nil
			for index, station in ipairs(allStations()) do
				local root = requirePart(station, "StationRoot")
				expectNear(Vector2.new(root.Position.X, root.Position.Z).Magnitude, 50, 0.05, string.format("%s ring radius", station.Name))
				expectEqual(station:GetAttribute("StationIndex"), index)
				expectEqual(station:GetAttribute("StationId"), string.format("station_%02d", index))
				if firstPosition == nil then
					firstPosition = root.Position
				end
				if previousPosition ~= nil then
					local clearance = (root.Position - (previousPosition :: Vector3)).Magnitude
						- 0.5 * Vector2.new(root.Size.X, root.Size.Z).Magnitude
						- 0.5 * Vector2.new(requirePart(stationAt(index - 1), "StationRoot").Size.X, requirePart(stationAt(index - 1), "StationRoot").Size.Z).Magnitude
					expect(clearance >= 4, string.format("%s adjacent clearance %.3f", station.Name, clearance))
				end
				previousPosition = root.Position
			end
			local last = requirePart(stationAt(8), "StationRoot")
			local first = requirePart(stationAt(1), "StationRoot")
			local wrapClearance = (last.Position - (firstPosition :: Vector3)).Magnitude
				- 0.5 * Vector2.new(last.Size.X, last.Size.Z).Magnitude
				- 0.5 * Vector2.new(first.Size.X, first.Size.Z).Magnitude
			expect(wrapClearance >= 4, string.format("Station_08/Station_01 clearance %.3f", wrapClearance))
		end,
	},
	{
		Name = "arena shell, dispatch landmark, and showcase loop are permanently authored",
		Run = function()
			local shell = requirePath(Arena, "ArenaShell")
			for _, pathName in ipairs({
				"OuterFloor", "WallSegments", "SupportPillars", "CeilingRing", "LightRig", "Entry", "Branding",
			}) do
				expect(shell:FindFirstChild(pathName) ~= nil, string.format("ArenaShell missing %s", pathName))
			end
			local dispatch = requirePath(Arena, "CenterDispatch")
			for _, pathName in ipairs({ "Base", "Lift", "LiftTop", "ShowcaseEntry", "ArenaAnnouncement", "ServerBest" }) do
				expect(dispatch:FindFirstChild(pathName) ~= nil, string.format("CenterDispatch missing %s", pathName))
			end
			local nodes = requirePath(Arena, "ShowcaseLoop.PathNodes")
			local nodeCount = 0
			for _, child in ipairs(nodes:GetChildren()) do
				if child:IsA("BasePart") and string.match(child.Name, "^Node_%d%d$") then
					nodeCount += 1
				end
			end
			expectEqual(nodeCount, 16)
		end,
	},
	{
		Name = "arena floor is no longer a visible square Baseplate presentation",
		Run = function()
			local arenaFloor = requirePart(Arena, "ArenaFloor")
			local arenaFloorIsLegacyBlock = arenaFloor:IsA("Part") and arenaFloor.Shape == Enum.PartType.Block
			expect(arenaFloor.Transparency >= 0.99 or math.abs(arenaFloor.Size.X - arenaFloor.Size.Z) > 0.01 or not arenaFloorIsLegacyBlock,
				"Legacy square ArenaFloor must be hidden or replaced")
			local shellFloor = requirePath(Arena, "ArenaShell.OuterFloor")
			expect(shellFloor:IsA("Part"), "OuterFloor must be an authored Part")
			local outerFloor = shellFloor :: Part
			expectEqual(outerFloor.Shape, Enum.PartType.Cylinder)
			expect(math.max(outerFloor.Size.X, outerFloor.Size.Y, outerFloor.Size.Z) >= 140)
			expect(outerFloor.Material ~= Enum.Material.Neon and outerFloor.Material ~= Enum.Material.Glass)
		end,
	},
	{
		Name = "showcase route remains camera-clear",
		Run = function()
			local nodes = requirePath(Arena, "ShowcaseLoop.PathNodes")
			for _, station in ipairs(allStations()) do
				for _, anchorName in ipairs({ "CameraAnchor", "CameraAnchorTouchLandscape", "CameraAnchorTouchPortrait" }) do
					local anchor = requirePart(station, anchorName)
					for _, node in ipairs(nodes:GetChildren()) do
						if node:IsA("BasePart") then
							expect((node.Position - anchor.Position).Magnitude >= 4, string.format("%s intersects %s camera clearance", node.Name, station.Name))
						end
					end
				end
			end
		end,
	},
})

addSuite("Lighting", {
	{
		Name = "Lighting service properties remain within the controlled Phase 07 range",
		Run = function()
			expectEqual(Lighting.Technology, Enum.Technology.Future)
			expect(Lighting.Brightness >= 1.8 and Lighting.Brightness <= 2.2)
			expect(Lighting.ExposureCompensation >= -0.4 and Lighting.ExposureCompensation <= -0.1)
			expect(Lighting.EnvironmentDiffuseScale >= 0.25 and Lighting.EnvironmentDiffuseScale <= 0.45)
			expect(Lighting.EnvironmentSpecularScale >= 0.45 and Lighting.EnvironmentSpecularScale <= 0.65)
			expect(Lighting.GlobalShadows)
			expect(Lighting.ShadowSoftness >= 0.25 and Lighting.ShadowSoftness <= 0.45)
		end,
	},
	{
		Name = "one restrained BloomEffect and one restrained ColorCorrectionEffect are authored",
		Run = function()
			local blooms = {}
			local corrections = {}
			for _, child in ipairs(Lighting:GetChildren()) do
				if child:IsA("BloomEffect") then table.insert(blooms, child) end
				if child:IsA("ColorCorrectionEffect") then table.insert(corrections, child) end
			end
			expectEqual(#blooms, 1)
			expectEqual(#corrections, 1)
			local bloom = blooms[1]
			expect(bloom.Enabled and bloom.Intensity >= 0.10 and bloom.Intensity <= 0.18)
			expect(bloom.Size >= 12 and bloom.Size <= 18)
			expect(bloom.Threshold >= 1.35 and bloom.Threshold <= 1.55)
			local correction = corrections[1]
			expect(correction.Enabled and correction.Contrast >= 0.06 and correction.Contrast <= 0.12)
			expect(correction.Saturation >= -0.10 and correction.Saturation <= -0.04)
			expect(correction.Brightness >= -0.03 and correction.Brightness <= 0)
		end,
	},
	{
		Name = "gameplay has no enabled depth-of-field blur",
		Run = function()
			for _, descendant in ipairs(Lighting:GetDescendants()) do
				if descendant:IsA("DepthOfFieldEffect") then
					expect(not descendant.Enabled, string.format("DepthOfFieldEffect must be disabled: %s", descendant:GetFullName()))
				end
			end
		end,
	},
	{
		Name = "dynamic lights and shadow-casting lights remain bounded",
		Run = function()
			local dynamicCount = 0
			local shadowCount = 0
			for _, descendant in ipairs(World:GetDescendants()) do
				if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
					dynamicCount += 1
					if descendant.Shadows then shadowCount += 1 end
				end
			end
			expect(dynamicCount <= 20, string.format("Dynamic light count %d exceeds 20", dynamicCount))
			expect(shadowCount <= 4, string.format("Shadow-casting dynamic light count %d is not restrained", shadowCount))
		end,
	},
	{
		Name = "Neon remains a bounded accent and giant spheres are absent",
		Run = function()
			for _, part in ipairs(allBaseParts(World)) do
				if part.Material == Enum.Material.Neon then
					local sorted = { part.Size.X, part.Size.Y, part.Size.Z }
					table.sort(sorted)
					expect(sorted[2] <= 1.25 or part:GetAttribute("Phase07NeonAllowlisted") == true, string.format("Oversized Neon surface: %s", part:GetFullName()))
				end
				if part:IsA("Part") and part.Shape == Enum.PartType.Ball and part:IsDescendantOf(Stations) then
					expect(math.max(part.Size.X, part.Size.Y, part.Size.Z) <= 1.2, string.format("Giant station sphere: %s", part:GetFullName()))
				end
			end
		end,
	},
})

addSuite("World labels", {
	{
		Name = "owner and shelf BillboardGuis are finite-distance and world-occluded",
		Run = function()
			for _, station in ipairs(allStations()) do
				local owner = requirePath(station, "OwnerDisplay.BillboardGui")
				expect(owner:IsA("BillboardGui"))
				local ownerGui = owner :: BillboardGui
				expect(ownerGui.MaxDistance > 0 and ownerGui.MaxDistance <= 70)
				expect(not ownerGui.AlwaysOnTop)
				local shelf = requirePath(station, "CollectionShelf")
				for _, descendant in ipairs(shelf:GetDescendants()) do
					if descendant:IsA("BillboardGui") then
					expect(descendant.MaxDistance > 0 and descendant.MaxDistance <= 60)
						expect(not descendant.AlwaysOnTop)
					end
				end
			end
		end,
	},
	{
		Name = "central announcement and server-best boards remain singular",
		Run = function()
			local announcementCount = 0
			local serverBestCount = 0
			for _, descendant in ipairs(Arena:GetDescendants()) do
				if descendant.Name == "ArenaAnnouncement" then announcementCount += 1 end
				if descendant.Name == "ServerBest" then serverBestCount += 1 end
			end
			expectEqual(announcementCount, 1)
			expectEqual(serverBestCount, 1)
		end,
	},
	{
		Name = "local adjacent and distant policies are deterministic",
		Run = function()
			expectEqual(WorldLabelController.ClassifyStation(1, 1, 8), "Local")
			expectEqual(WorldLabelController.ClassifyStation(1, 2, 8), "Adjacent")
			expectEqual(WorldLabelController.ClassifyStation(1, 8, 8), "Adjacent")
			expectEqual(WorldLabelController.ClassifyStation(1, 5, 8), "Distant")
			expectEqual(WorldLabelController.ClassifyStation(nil, 1, 8), "Distant")
			expect(WorldLabelController.ShouldShowForView("Local", 70, 0, 70))
			expect(not WorldLabelController.ShouldShowForView("Local", 70.01, 0, 70))
			expect(WorldLabelController.ShouldShowForView("Adjacent", 60, 0.10, 70))
			expect(not WorldLabelController.ShouldShowForView("Distant", 60, 0.30, 70))
			expect(WorldLabelController.ShouldShowForView("Distant", 60, 0.40, 70))
		end,
	},
	{
		Name = "camera-change policy is bounded and never requires a frame loop",
		Run = function()
			local initial = CFrame.lookAt(Vector3.new(0, 20, 20), Vector3.zero)
			local viewport = Vector2.new(1920, 1080)
			expect(WorldLabelController.IsMeaningfulCameraChange(nil, initial, nil, viewport))
			expect(not WorldLabelController.IsMeaningfulCameraChange(initial, initial * CFrame.new(0.1, 0, 0), viewport, viewport))
			expect(WorldLabelController.IsMeaningfulCameraChange(initial, initial * CFrame.new(0.4, 0, 0), viewport, viewport))
			expect(WorldLabelController.IsMeaningfulCameraChange(initial, initial * CFrame.Angles(0, math.rad(2), 0), viewport, viewport))
			expect(WorldLabelController.IsMeaningfulCameraChange(initial, initial, viewport, Vector2.new(1366, 768)))
		end,
	},
	{
		Name = "assignment reassignment release and destroy restore authored labels",
		Run = function()
			local first = stationAt(1)
			local ownerGui = requirePath(first, "OwnerDisplay.BillboardGui") :: BillboardGui
			local shelfGui = requirePath(first, "CollectionShelf.ShelfLabel.BillboardGui") :: BillboardGui
			local ownerEnabled = ownerGui.Enabled
			local ownerAlwaysOnTop = ownerGui.AlwaysOnTop
			local shelfEnabled = shelfGui.Enabled
			local shelfAlwaysOnTop = shelfGui.AlwaysOnTop
			local controller = WorldLabelController.new(Stations)
			controller:SetAssignedStation("station_01")
			expectEqual(stationAt(1):GetAttribute("WorldLabelTier"), "Local")
			expectEqual(stationAt(2):GetAttribute("WorldLabelTier"), "Adjacent")
			expectEqual(stationAt(8):GetAttribute("WorldLabelTier"), "Adjacent")
			expectEqual(stationAt(5):GetAttribute("WorldLabelTier"), "Distant")
			controller:SetAssignedStation("station_05")
			expectEqual(stationAt(5):GetAttribute("WorldLabelTier"), "Local")
			expectEqual(stationAt(1):GetAttribute("WorldLabelTier"), "Distant")
			controller:SetAssignedStation(nil)
			for _, station in ipairs(allStations()) do
				expectEqual(station:GetAttribute("WorldLabelTier"), "Distant")
			end
			controller:Destroy()
			controller:Refresh()
			controller:SetAssignedStation("station_01")
			for _, station in ipairs(allStations()) do
				expectEqual(station:GetAttribute("WorldLabelTier"), nil)
				expectEqual(station:GetAttribute("WorldLabelVisible"), nil)
			end
			expectEqual(ownerGui.Enabled, ownerEnabled)
			expectEqual(ownerGui.AlwaysOnTop, ownerAlwaysOnTop)
			expectEqual(shelfGui.Enabled, shelfEnabled)
			expectEqual(shelfGui.AlwaysOnTop, shelfAlwaysOnTop)
		end,
	},
})

addSuite("Arrival curtain", {
	{
		Name = "first-frame handoff releases visible coverage and stale hidden revealed coverage only when safe",
		Run = function()
			expect(FirstFrameHandoffPolicy.ShouldHandoff(true, true, "WAITING FOR STATION"))
			expect(FirstFrameHandoffPolicy.ShouldHandoff(false, true, "REVEALED"))
			expect(not FirstFrameHandoffPolicy.ShouldHandoff(false, true, "WAITING FOR STATION"))
			expect(not FirstFrameHandoffPolicy.ShouldHandoff(true, false, "WAITING FOR STATION"))
			expect(not FirstFrameHandoffPolicy.ShouldHandoff(false, false, "REVEALED"))
		end,
	},
	{
		Name = "ArrivalCurtain is permanent, visible by default, and contains the required authored presentation",
		Run = function()
			local screen = requireChild(StarterGui, "ONE_MORE_ITEM_Gameplay", "ScreenGui")
			local curtain = requireChild(screen, "ArrivalCurtain", "Frame") :: Frame
			expect(curtain.Visible)
			expectEqual(curtain.BackgroundTransparency, 1)
			expect(curtain.Size.X.Scale >= 1 and curtain.Size.Y.Scale >= 1)
			expect(curtain.ZIndex >= 100)
			for _, name in ipairs({ "Background", "GameTitle", "Subtitle", "LoadingStatus", "AccentLine" }) do
				expect(curtain:FindFirstChild(name) ~= nil, string.format("ArrivalCurtain missing %s", name))
			end
			local background = requirePath(curtain, "Background")
			expect(background:IsA("Frame"))
			local backgroundFrame = background :: Frame
			expectEqual(backgroundFrame.BackgroundTransparency, 0)
			expectEqual(backgroundFrame.BackgroundColor3, Color3.fromRGB(10, 15, 22))
			expect(backgroundFrame.Size.X.Scale >= 1 and backgroundFrame.Size.Y.Scale >= 1)
			local title = requirePath(curtain, "GameTitle")
			local subtitle = requirePath(curtain, "Subtitle")
			local status = requirePath(curtain, "LoadingStatus")
			expect(title:IsA("TextLabel") and title.Text == "ONE MORE ITEM!")
			expect(subtitle:IsA("TextLabel") and subtitle.Text == "PACK THE BOX")
			expect(status:IsA("TextLabel") and status.Text == "LOADING PROFILE")
		end,
	},
	{
		Name = "camera safety is mandatory before every reveal",
		Run = function()
			expect(not ArrivalCurtainController.ShouldReveal("Ready", false, nil, {
				Safe = false,
				Settled = true,
				StationId = nil,
			}))
			expect(not ArrivalCurtainController.ShouldReveal("Ready", false, nil, {
				Safe = true,
				Settled = false,
				StationId = nil,
			}))
		end,
	},
	{
		Name = "assigned and waiting flows reveal only at the correct safe camera",
		Run = function()
			local waiting = { Safe = true, Settled = true, StationId = nil }
			local assigned = { Safe = true, Settled = true, StationId = "station_03" }
			expect(ArrivalCurtainController.ShouldReveal("Ready", false, nil, waiting))
			expect(not ArrivalCurtainController.ShouldReveal("Ready", true, "station_03", waiting))
			expect(ArrivalCurtainController.ShouldReveal("Ready", true, "station_03", assigned))
			expect(not ArrivalCurtainController.ShouldReveal("Ready", true, "station_05", assigned))
		end,
	},
	{
		Name = "unavailable conflict and loading flows remain covered and deterministic",
		Run = function()
			local safeWaiting = { Safe = true, Settled = true, StationId = nil }
			expectEqual(ArrivalCurtainController.StatusForProfile("Unavailable"), "DATA UNAVAILABLE")
			expectEqual(ArrivalCurtainController.StatusForProfile("Conflict"), "PROFILE OPEN ELSEWHERE")
			expectEqual(ArrivalCurtainController.StatusForProfile("Loading"), "LOADING PROFILE")
			expectEqual(ArrivalCurtainController.StatusForProfile("Ready"), "WAITING FOR STATION")
			expect(not ArrivalCurtainController.ShouldReveal("Unavailable", false, nil, safeWaiting))
			expect(not ArrivalCurtainController.ShouldReveal("Conflict", false, nil, safeWaiting))
			local first = ArrivalCurtainController.ShouldReveal("Ready", false, nil, safeWaiting)
			local duplicate = ArrivalCurtainController.ShouldReveal("Ready", false, nil, safeWaiting)
			expectEqual(first, duplicate, "Duplicate state must not change reveal eligibility")
			expect(type(ArrivalCurtainController.new) == "function")
		end,
	},
})

addSuite("UI geometry", {
	{
		Name = "MetaBar and StarterMissionCard satisfy the complete density matrix",
		Run = function()
			local rootFrame = requirePath(StarterGui, "ONE_MORE_ITEM_Gameplay.Root")
			local metaBar = requirePath(rootFrame, "MetaBar")
			local missionCard = requirePath(rootFrame, "StarterMissionCard")
			expect(metaBar:IsA("GuiObject") and missionCard:IsA("GuiObject"))
			local mission = missionCard :: GuiObject
			expect(guiScaleArea(mission) <= 0.12, string.format("StarterMissionCard scale area %.4f exceeds 12%%", guiScaleArea(mission)))
			for _, currentProfile in ipairs(uiViewportProfiles) do
				local layout = ResponsiveLayout.Resolve(currentProfile.Width, currentProfile.Height, {
					Left = 0,
					Top = 0,
					Right = 0,
					Bottom = 0,
				})
				local missionBounds = ResponsiveLayout.BoundsForTarget(layout, "StarterMissionCard")
				local missionAreaRatio = missionBounds.Width * missionBounds.Height
					/ (layout.UsableBounds.Width * layout.UsableBounds.Height)
				expect(missionAreaRatio <= 0.12, string.format(
					"%s StarterMissionCard area ratio %.4f exceeds 12%%",
					currentProfile.Name,
					missionAreaRatio
				))
				local profileLayout = ProfileResponsiveLayout.Resolve(layout.Class)
				local metaScale = profileLayout.MetaBar.Size.Y.Scale
				local pixelHeight = metaScale * currentProfile.Height
				local maximumHeight = if layout.Class == "Wide" then 64 elseif layout.Class == "CompactLandscape" then 58 else 70
				expect(pixelHeight <= maximumHeight, string.format(
					"%s MetaBar height %.3f exceeds %d",
					currentProfile.Name,
					pixelHeight,
					maximumHeight
				))
			end
		end,
	},
	{
		Name = "gameplay modal and progression geometry remains contained balanced and state-separated",
		Run = function()
			for _, currentProfile in ipairs(uiViewportProfiles) do
				local layout = ResponsiveLayout.Resolve(currentProfile.Width, currentProfile.Height, {
					Left = 0,
					Top = 0,
					Right = 0,
					Bottom = 0,
				})
				for _, targetName in ipairs({
					"CurrentItemCard", "ShipmentCard", "PlacementControls", "DecisionPanel", "ResultsPanel",
					"OnboardingOverlay", "StarterMissionCard", "StarterPathPanel", "MissionCompleteBanner",
				}) do
					local bounds = ResponsiveLayout.BoundsForTarget(layout, targetName :: any)
					expect(ResponsiveLayout.IsContained(bounds, layout.UsableBounds), string.format(
						"%s %s escapes the safe viewport",
						currentProfile.Name,
						targetName
					))
				end

				local current = ResponsiveLayout.BoundsForTarget(layout, "CurrentItemCard")
				local shipment = ResponsiveLayout.BoundsForTarget(layout, "ShipmentCard")
				expectNear(current.Width, shipment.Width, 0.001)
				expectNear(current.Height, shipment.Height, 0.001)
				expectEqual(boundsOverlapArea(current, shipment), 0)
				for _, actionName in ipairs({ "PlacementControls", "DecisionPanel" }) do
					local action = ResponsiveLayout.BoundsForTarget(layout, actionName :: any)
					expectEqual(boundsOverlapArea(current, action), 0, string.format("%s CurrentItemCard overlaps %s", currentProfile.Name, actionName))
					expectEqual(boundsOverlapArea(shipment, action), 0, string.format("%s ShipmentCard overlaps %s", currentProfile.Name, actionName))
				end
				for _, pair in ipairs({
					{ "RotateButton", "PlaceButton" },
					{ "ShipButton", "OneMoreButton" },
				}) do
					local first = ResponsiveLayout.BoundsForTarget(layout, pair[1] :: any)
					local second = ResponsiveLayout.BoundsForTarget(layout, pair[2] :: any)
					expectEqual(boundsOverlapArea(first, second), 0, string.format(
						"%s %s overlaps %s",
						currentProfile.Name,
						pair[1],
						pair[2]
					))
				end

				local profileLayout = ProfileResponsiveLayout.Resolve(layout.Class)
				local collection = profileLayout.CollectionPanel
				local collectionWidth = collection.Size.X.Scale * currentProfile.Width
				local collectionHeight = collection.Size.Y.Scale * currentProfile.Height
				local collectionLeft = collection.Position.X.Scale * currentProfile.Width - collectionWidth * 0.5
				local collectionTop = collection.Position.Y.Scale * currentProfile.Height - collectionHeight * 0.5
				expect(collectionLeft >= 0 and collectionTop >= 0)
				expect(collectionLeft + collectionWidth <= currentProfile.Width)
				expect(collectionTop + collectionHeight <= currentProfile.Height)
			end
		end,
	},
	{
		Name = "packing-state cards and placement actions do not cover the projected crate interior",
		Run = function()
			local insetProfiles = {
				{ Left = 0, Top = 0, Right = 0, Bottom = 0 },
				{ Left = 0, Top = 24, Right = 0, Bottom = 0 },
				{ Left = 24, Top = 0, Right = 24, Bottom = 0 },
				{ Left = 0, Top = 0, Right = 0, Bottom = 24 },
				{ Left = 20, Top = 24, Right = 20, Bottom = 24 },
			}
			for _, stationIndex in ipairs({ 1, 5 }) do
				local station = stationAt(stationIndex)
				local crate = requirePath(station, "Crate")
				local gridOrigin = requirePart(crate, "GridOrigin")
				for _, currentProfile in ipairs(uiViewportProfiles) do
					local camera = cameraFor(station, currentProfile.Anchor)
					local viewport = { Width = currentProfile.Width, Height = currentProfile.Height }
					local interiorTransform, interiorSize = logicalInterior(station)
					local crateBounds = VisualFraming.ProjectObb(camera, interiorTransform, interiorSize, viewport, FIELD_OF_VIEW)
					expect(crateBounds ~= nil, "Logical crate interior must project for UI occlusion checks")
					for _, insets in ipairs(insetProfiles) do
						local layout = ResponsiveLayout.Resolve(currentProfile.Width, currentProfile.Height, insets)
						local rotateBounds = ResponsiveLayout.BoundsForTarget(layout, "RotateButton")
						local placeBounds = ResponsiveLayout.BoundsForTarget(layout, "PlaceButton")
						for _, targetName in ipairs({
							"CurrentItemCard",
							"ShipmentCard",
							"StarterMissionCard",
							"RotateButton",
							"PlaceButton",
						}) do
							local uiBounds = ResponsiveLayout.BoundsForTarget(layout, targetName :: any)
							expect(boundsOverlapArea(crateBounds :: any, uiBounds) == 0, string.format(
								"Station_%02d %s %s covers the projected crate interior",
								stationIndex,
								currentProfile.Name,
								targetName
							))
						end
						for gridZ = 0, 4 do
							for gridX = 0, 4 do
								local worldPoint = gridOrigin.CFrame:PointToWorldSpace(Vector3.new(gridX * 2, 0, gridZ * 2))
								local projected = VisualFraming.ProjectPoint(camera, worldPoint, viewport, FIELD_OF_VIEW)
								expect(projected ~= nil)
								local point = projected :: any
								local function inside(bounds: any): boolean
									return point.X >= bounds.Left and point.X <= bounds.Right
										and point.Y >= bounds.Top and point.Y <= bounds.Bottom
								end
								expect(not inside(rotateBounds) and not inside(placeBounds), string.format(
									"Station_%02d %s cell %d,%d is behind placement actions",
									stationIndex,
									currentProfile.Name,
									gridX,
									gridZ
								))
							end
						end
					end
				end
			end
		end,
	},
	{
		Name = "accepted gameplay and progression panels remain permanently authored",
		Run = function()
			local rootFrame = requirePath(StarterGui, "ONE_MORE_ITEM_Gameplay.Root")
			for _, name in ipairs({
				"CurrentItemCard", "ShipmentCard", "PlacementControls", "DecisionPanel", "ResultsPanel", "OnboardingOverlay",
				"MissionCompleteBanner", "CollectionPanel", "StarterPathPanel", "StarterMissionCard", "MetaBar",
			}) do
				expect(rootFrame:FindFirstChild(name) ~= nil, string.format("Gameplay UI missing %s", name))
			end
		end,
	},
	{
		Name = "screen-space Z-order remains below the ArrivalCurtain and world labels cannot render above it",
		Run = function()
			local screen = requirePath(StarterGui, "ONE_MORE_ITEM_Gameplay")
			local curtain = requirePath(screen, "ArrivalCurtain")
			expect(curtain:IsA("GuiObject"))
			local curtainZ = (curtain :: GuiObject).ZIndex
			for _, descendant in ipairs(screen:GetDescendants()) do
				if descendant:IsA("GuiObject") and not descendant:IsDescendantOf(curtain) and descendant ~= curtain then
					expect(descendant.ZIndex < curtainZ, string.format("%s may render over ArrivalCurtain", descendant:GetFullName()))
				end
			end
		end,
	},
})

addSuite("Presentation cleanup", {
	{
		Name = "ten world-label assignment cycles restore authored state and leave no runtime residue",
		Run = function()
			local showcaseRuntime = requirePath(Arena, "ShowcaseLoop.Runtime")
			local showcaseCount = #showcaseRuntime:GetChildren()
			local presentationCounts: { [Model]: number } = {}
			for _, station in ipairs(allStations()) do
				presentationCounts[station] = #requirePath(station, "RuntimePresentation"):GetChildren()
			end
			for cycle = 1, 10 do
				local controller = WorldLabelController.new(Stations)
				controller:SetAssignedStation(string.format("station_%02d", ((cycle - 1) % 8) + 1))
				controller:Refresh()
				controller:Destroy()
				controller:Destroy()
				for _, station in ipairs(allStations()) do
					expectEqual(station:GetAttribute("WorldLabelTier"), nil)
					expectEqual(station:GetAttribute("WorldLabelVisible"), nil)
					expectEqual(#requirePath(station, "RuntimePresentation"):GetChildren(), presentationCounts[station])
				end
				expectEqual(#showcaseRuntime:GetChildren(), showcaseCount)
			end
		end,
	},
	{
		Name = "temporary visual runtime folders start bounded and permanent folders contain no particles",
		Run = function()
			local showcaseRuntime = requirePath(Arena, "ShowcaseLoop.Runtime")
			expect(#showcaseRuntime:GetChildren() <= 3, "Showcase runtime exceeds the accepted active limit")
			for _, station in ipairs(allStations()) do
				local runtime = requirePath(station, "RuntimePresentation")
				expect(#runtime:GetChildren() == 0, string.format("%s presentation runtime did not return to baseline", station.Name))
			end
			for _, descendant in ipairs(World:GetDescendants()) do
				expect(not descendant:IsA("ParticleEmitter"), string.format("Phase 07 may not author particles: %s", descendant:GetFullName()))
			end
		end,
	},
	{
		Name = "development Phase 07 controls use a fixed seed and remain explicitly enabled",
		Run = function()
			expectEqual(RoundConfig.DEVELOPMENT.RUN_PHASE07_TESTS, true)
			expectEqual(RoundConfig.DEVELOPMENT.PHASE07_TEST_SEED, 17072026)
		end,
	},
})

function Phase07TestSuite.Run(): TestReport
	local startedAt = os.clock()
	local totalTests = 0
	local passed = 0
	local failures: { string } = {}
	local seed = RoundConfig.DEVELOPMENT.PHASE07_TEST_SEED
	if type(seed) ~= "number" or seed % 1 ~= 0 then
		error("RoundConfig.DEVELOPMENT.PHASE07_TEST_SEED must be a fixed integer", 2)
	end

	lineOfSightRays = 0
	print(string.format("[ONE_MORE_ITEM][Phase07Tests] Starting %d suites seed=%d losTarget=768", #suites, seed))
	for _, suite in ipairs(suites) do
		print(string.format("[ONE_MORE_ITEM][Phase07Tests] SUITE %s (%d tests)", suite.Name, #suite.Tests))
		for _, testCase in ipairs(suite.Tests) do
			totalTests += 1
			local ok, failure = pcall(testCase.Run)
			if ok then
				passed += 1
			else
				local message = string.format("%s > %s: %s", suite.Name, testCase.Name, tostring(failure))
				table.insert(failures, message)
				warn("[ONE_MORE_ITEM][Phase07Tests] FAIL " .. message)
			end
		end
	end

	local duration = os.clock() - startedAt
	local failed = #failures
	print(string.format(
		"[ONE_MORE_ITEM][Phase07Tests] RESULT suites=%d tests=%d passed=%d failed=%d duration=%.6fs seed=%d losRays=%d",
		#suites,
		totalTests,
		passed,
		failed,
		duration,
		seed,
		lineOfSightRays
	))
	if failed > 0 then
		for index, failure in ipairs(failures) do
			warn(string.format("[ONE_MORE_ITEM][Phase07Tests] FAILURE %d: %s", index, failure))
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
		LineOfSightRays = lineOfSightRays,
	}
end

return table.freeze(Phase07TestSuite)
