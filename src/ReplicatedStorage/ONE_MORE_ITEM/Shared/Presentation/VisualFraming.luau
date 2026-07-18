--!strict

export type NumericVector3 = {
	X: number,
	Y: number,
	Z: number,
}

export type Vector3Input = Vector3 | NumericVector3

export type Viewport = {
	Width: number,
	Height: number,
}

export type SafeInsets = {
	Left: number?,
	Top: number?,
	Right: number?,
	Bottom: number?,
}

export type ScreenRect = {
	Left: number,
	Top: number,
	Right: number,
	Bottom: number,
	Width: number,
	Height: number,
	CenterX: number,
	CenterY: number,
}

export type SafeRect = ScreenRect

export type NumericCamera = {
	Position: NumericVector3,
	Target: NumericVector3,
	Up: NumericVector3?,
}

export type CameraInput = CFrame | NumericCamera

export type NumericTransform = {
	Position: NumericVector3,
	AxisX: NumericVector3,
	AxisY: NumericVector3,
	AxisZ: NumericVector3,
}

export type TransformInput = CFrame | NumericTransform

export type ProjectedPoint = {
	X: number,
	Y: number,
	Depth: number,
	NdcX: number,
	NdcY: number,
	InsideViewport: boolean,
}

export type ProjectedBounds = ScreenRect & {
	MinimumDepth: number,
	MaximumDepth: number,
	Corners: { ProjectedPoint },
}

export type Occupancy = {
	WidthRatio: number,
	HeightRatio: number,
	CenterXRatio: number,
	CenterYRatio: number,
	AreaRatio: number,
	FullyContained: boolean,
}

export type Overlap = {
	Intersects: boolean,
	Width: number,
	Height: number,
	Area: number,
	RatioOfFirst: number,
	RatioOfSecond: number,
	HorizontalRatioOfFirst: number,
	VerticalRatioOfFirst: number,
}

export type FramingThresholds = {
	MinimumWidthRatio: number?,
	MaximumWidthRatio: number?,
	MinimumHeightRatio: number?,
	MaximumHeightRatio: number?,
	MinimumCenterXRatio: number?,
	MaximumCenterXRatio: number?,
	MinimumCenterYRatio: number?,
	MaximumCenterYRatio: number?,
	RequireContained: boolean,
}

export type FramingEvaluation = {
	Pass: boolean,
	WidthPass: boolean,
	HeightPass: boolean,
	CenterXPass: boolean,
	CenterYPass: boolean,
	ContainmentPass: boolean,
	Occupancy: Occupancy,
}

export type CameraEvaluation = {
	Pass: boolean,
	FieldOfViewPass: boolean,
	PitchPass: boolean,
	FieldOfView: number,
	DownwardPitchDegrees: number,
}

export type LineOfSightKind =
	"LayerZero"
	| "UpperCorner"
	| "CrateFocus"
	| "GridOrigin"
	| "GhostFixture"

export type LineOfSightFixture = {
	GridOrigin: TransformInput,
	CellSize: number,
	CrateFocus: Vector3Input,
	GhostFixtureCenter: Vector3Input,
}

export type LineOfSightSample = {
	Index: number,
	Name: string,
	Kind: LineOfSightKind,
	Position: NumericVector3,
	GridX: number?,
	GridY: number?,
	GridZ: number?,
}

type ResolvedCamera = {
	Position: NumericVector3,
	Right: NumericVector3,
	Up: NumericVector3,
	Forward: NumericVector3,
}

type ResolvedTransform = {
	Position: NumericVector3,
	AxisX: NumericVector3,
	AxisY: NumericVector3,
	AxisZ: NumericVector3,
}

local EPSILON = 1e-7
local DEFAULT_NEAR_PLANE = 0.01
local DEGREES_PER_RADIAN = 180 / math.pi

local function assertFiniteNumber(value: any, label: string): number
	if type(value) ~= "number"
		or value ~= value
		or value == math.huge
		or value == -math.huge
	then
		error(string.format("%s must be a finite number", label), 3)
	end
	return value
end

local function frozenVector(x: number, y: number, z: number): NumericVector3
	return table.freeze({
		X = x,
		Y = y,
		Z = z,
	}) :: NumericVector3
end

local function readVector(input: Vector3Input, label: string): NumericVector3
	if typeof(input) == "Vector3" then
		local value = input :: Vector3
		return frozenVector(value.X, value.Y, value.Z)
	end

	local value = input :: any
	return frozenVector(
		assertFiniteNumber(value.X, label .. ".X"),
		assertFiniteNumber(value.Y, label .. ".Y"),
		assertFiniteNumber(value.Z, label .. ".Z")
	)
end

local function add(first: NumericVector3, second: NumericVector3): NumericVector3
	return frozenVector(first.X + second.X, first.Y + second.Y, first.Z + second.Z)
end

local function subtract(first: NumericVector3, second: NumericVector3): NumericVector3
	return frozenVector(first.X - second.X, first.Y - second.Y, first.Z - second.Z)
end

local function scale(vector: NumericVector3, amount: number): NumericVector3
	return frozenVector(vector.X * amount, vector.Y * amount, vector.Z * amount)
end

local function dot(first: NumericVector3, second: NumericVector3): number
	return first.X * second.X + first.Y * second.Y + first.Z * second.Z
end

local function cross(first: NumericVector3, second: NumericVector3): NumericVector3
	return frozenVector(
		first.Y * second.Z - first.Z * second.Y,
		first.Z * second.X - first.X * second.Z,
		first.X * second.Y - first.Y * second.X
	)
end

local function magnitude(vector: NumericVector3): number
	return math.sqrt(dot(vector, vector))
end

local function unit(vector: NumericVector3, label: string): NumericVector3
	local length = magnitude(vector)
	if length <= EPSILON then
		error(string.format("%s must have non-zero length", label), 3)
	end
	return scale(vector, 1 / length)
end

local function validateViewport(viewport: Viewport)
	local width = assertFiniteNumber(viewport.Width, "viewport.Width")
	local height = assertFiniteNumber(viewport.Height, "viewport.Height")
	if width <= 0 or height <= 0 then
		error("viewport dimensions must be positive", 3)
	end
end

local function validateFieldOfView(verticalFieldOfViewDegrees: number)
	local fieldOfView = assertFiniteNumber(verticalFieldOfViewDegrees, "verticalFieldOfViewDegrees")
	if fieldOfView <= 1 or fieldOfView >= 179 then
		error("verticalFieldOfViewDegrees must be between 1 and 179", 3)
	end
end

local function resolveCamera(camera: CameraInput): ResolvedCamera
	if typeof(camera) == "CFrame" then
		local frame = camera :: CFrame
		return {
			Position = readVector(frame.Position, "camera.Position"),
			Right = readVector(frame.RightVector, "camera.RightVector"),
			Up = readVector(frame.UpVector, "camera.UpVector"),
			Forward = readVector(frame.LookVector, "camera.LookVector"),
		}
	end

	local numeric = camera :: NumericCamera
	local position = readVector(numeric.Position, "camera.Position")
	local target = readVector(numeric.Target, "camera.Target")
	local forward = unit(subtract(target, position), "camera forward")
	local numericUp = numeric.Up
	local upHint = if numericUp ~= nil
		then unit(readVector(numericUp, "camera.Up"), "camera.Up")
		else frozenVector(0, 1, 0)

	if math.abs(dot(forward, upHint)) >= 0.999 then
		upHint = frozenVector(0, 0, 1)
		if math.abs(dot(forward, upHint)) >= 0.999 then
			upHint = frozenVector(1, 0, 0)
		end
	end

	local right = unit(cross(forward, upHint), "camera right")
	local up = unit(cross(right, forward), "camera up")
	return {
		Position = position,
		Right = right,
		Up = up,
		Forward = forward,
	}
end

local function resolveTransform(transform: TransformInput): ResolvedTransform
	if typeof(transform) == "CFrame" then
		local frame = transform :: CFrame
		return {
			Position = readVector(frame.Position, "transform.Position"),
			AxisX = readVector(frame.RightVector, "transform.AxisX"),
			AxisY = readVector(frame.UpVector, "transform.AxisY"),
			AxisZ = readVector(-frame.LookVector, "transform.AxisZ"),
		}
	end

	local numeric = transform :: NumericTransform
	local axisX = unit(readVector(numeric.AxisX, "transform.AxisX"), "transform.AxisX")
	local rawAxisY = readVector(numeric.AxisY, "transform.AxisY")
	local axisY = unit(subtract(rawAxisY, scale(axisX, dot(rawAxisY, axisX))), "transform.AxisY")
	local rawAxisZ = readVector(numeric.AxisZ, "transform.AxisZ")
	local axisZ = unit(
		subtract(subtract(rawAxisZ, scale(axisX, dot(rawAxisZ, axisX))), scale(axisY, dot(rawAxisZ, axisY))),
		"transform.AxisZ"
	)

	return {
		Position = readVector(numeric.Position, "transform.Position"),
		AxisX = axisX,
		AxisY = axisY,
		AxisZ = axisZ,
	}
end

local function pointOnTransform(
	transform: ResolvedTransform,
	localX: number,
	localY: number,
	localZ: number
): NumericVector3
	local position = transform.Position
	position = add(position, scale(transform.AxisX, localX))
	position = add(position, scale(transform.AxisY, localY))
	return add(position, scale(transform.AxisZ, localZ))
end

local function screenRect(left: number, top: number, right: number, bottom: number): ScreenRect
	return table.freeze({
		Left = left,
		Top = top,
		Right = right,
		Bottom = bottom,
		Width = right - left,
		Height = bottom - top,
		CenterX = (left + right) * 0.5,
		CenterY = (top + bottom) * 0.5,
	}) :: ScreenRect
end

local function passesRange(value: number, minimum: number?, maximum: number?): boolean
	return (minimum == nil or value >= minimum) and (maximum == nil or value <= maximum)
end

local desktopThresholds: FramingThresholds = table.freeze({
	MinimumWidthRatio = 0.42,
	MaximumWidthRatio = 0.58,
	MinimumHeightRatio = 0.36,
	MaximumHeightRatio = 0.56,
	MinimumCenterXRatio = 0.46,
	MaximumCenterXRatio = 0.54,
	MinimumCenterYRatio = 0.43,
	MaximumCenterYRatio = 0.61,
	RequireContained = true,
})

local touchPortraitThresholds: FramingThresholds = table.freeze({
	MinimumWidthRatio = 0.72,
	MaximumWidthRatio = 0.88,
	RequireContained = true,
})

local touchLandscapeThresholds: FramingThresholds = table.freeze({
	MinimumWidthRatio = 0.44,
	MaximumWidthRatio = 0.62,
	MinimumHeightRatio = 0.50,
	MaximumHeightRatio = 0.72,
	RequireContained = true,
})

local compactThresholds: FramingThresholds = table.freeze({
	RequireContained = true,
})

local VisualFraming = {
	MinimumFieldOfView = 48,
	MaximumFieldOfView = 52,
	MinimumDownwardPitchDegrees = 50,
	MaximumDownwardPitchDegrees = 58,
	MaximumFrontRimOverlapRatio = 0.08,
	LineOfSightSampleCount = 32,
	AcceptanceProfiles = table.freeze({
		Desktop = desktopThresholds,
		TouchPortrait = touchPortraitThresholds,
		TouchLandscape = touchLandscapeThresholds,
		Compact = compactThresholds,
	}),
}

function VisualFraming.NumericCameraFromCFrame(cameraCFrame: CFrame): NumericCamera
	local target = cameraCFrame.Position + cameraCFrame.LookVector
	return table.freeze({
		Position = readVector(cameraCFrame.Position, "cameraCFrame.Position"),
		Target = readVector(target, "cameraCFrame.Target"),
		Up = readVector(cameraCFrame.UpVector, "cameraCFrame.UpVector"),
	}) :: NumericCamera
end

function VisualFraming.NumericCameraFromLookAt(
	position: Vector3Input,
	target: Vector3Input,
	up: Vector3Input?
): NumericCamera
	local definition: NumericCamera = {
		Position = readVector(position, "position"),
		Target = readVector(target, "target"),
	}
	if up ~= nil then
		definition.Up = readVector(up, "up")
	end
	resolveCamera(definition)
	return table.freeze(definition) :: NumericCamera
end

function VisualFraming.NumericTransformFromCFrame(transformCFrame: CFrame): NumericTransform
	return table.freeze({
		Position = readVector(transformCFrame.Position, "transformCFrame.Position"),
		AxisX = readVector(transformCFrame.RightVector, "transformCFrame.AxisX"),
		AxisY = readVector(transformCFrame.UpVector, "transformCFrame.AxisY"),
		AxisZ = readVector(-transformCFrame.LookVector, "transformCFrame.AxisZ"),
	}) :: NumericTransform
end

function VisualFraming.GetSafeRect(viewport: Viewport, insets: SafeInsets?): ScreenRect
	validateViewport(viewport)
	local source: SafeInsets = insets or {}
	local left = assertFiniteNumber(source.Left or 0, "insets.Left")
	local top = assertFiniteNumber(source.Top or 0, "insets.Top")
	local rightInset = assertFiniteNumber(source.Right or 0, "insets.Right")
	local bottomInset = assertFiniteNumber(source.Bottom or 0, "insets.Bottom")
	if left < 0 or top < 0 or rightInset < 0 or bottomInset < 0 then
		error("safe insets may not be negative", 2)
	end

	local right = viewport.Width - rightInset
	local bottom = viewport.Height - bottomInset
	if right <= left or bottom <= top then
		error("safe insets must leave a positive viewport rectangle", 2)
	end
	return screenRect(left, top, right, bottom)
end

function VisualFraming.ProjectPoint(
	camera: CameraInput,
	worldPoint: Vector3Input,
	viewport: Viewport,
	verticalFieldOfViewDegrees: number,
	nearPlane: number?
): ProjectedPoint?
	validateViewport(viewport)
	validateFieldOfView(verticalFieldOfViewDegrees)
	local minimumDepth = if nearPlane == nil
		then DEFAULT_NEAR_PLANE
		else assertFiniteNumber(nearPlane, "nearPlane")
	if minimumDepth <= 0 then
		error("nearPlane must be positive", 2)
	end

	local resolved = resolveCamera(camera)
	local relative = subtract(readVector(worldPoint, "worldPoint"), resolved.Position)
	local depth = dot(relative, resolved.Forward)
	if depth <= minimumDepth then
		return nil
	end

	local halfHeight = viewport.Height * 0.5
	local focalLength = halfHeight / math.tan(math.rad(verticalFieldOfViewDegrees) * 0.5)
	local x = viewport.Width * 0.5 + (dot(relative, resolved.Right) * focalLength / depth)
	local y = viewport.Height * 0.5 - (dot(relative, resolved.Up) * focalLength / depth)
	return table.freeze({
		X = x,
		Y = y,
		Depth = depth,
		NdcX = (x / (viewport.Width * 0.5)) - 1,
		NdcY = 1 - (y / (viewport.Height * 0.5)),
		InsideViewport = x >= 0 and x <= viewport.Width and y >= 0 and y <= viewport.Height,
	}) :: ProjectedPoint
end

function VisualFraming.GetObbCorners(transform: TransformInput, size: Vector3Input): { NumericVector3 }
	local resolved = resolveTransform(transform)
	local dimensions = readVector(size, "size")
	if dimensions.X <= 0 or dimensions.Y <= 0 or dimensions.Z <= 0 then
		error("OBB size components must be positive", 2)
	end

	local halfX = dimensions.X * 0.5
	local halfY = dimensions.Y * 0.5
	local halfZ = dimensions.Z * 0.5
	local corners: { NumericVector3 } = {}
	for _, signY in ipairs({ -1, 1 }) do
		for _, signZ in ipairs({ -1, 1 }) do
			for _, signX in ipairs({ -1, 1 }) do
				table.insert(corners, pointOnTransform(
					resolved,
					signX * halfX,
					signY * halfY,
					signZ * halfZ
				))
			end
		end
	end
	return table.freeze(corners) :: { NumericVector3 }
end

function VisualFraming.ProjectWorldBounds(
	camera: CameraInput,
	worldPoints: { Vector3Input },
	viewport: Viewport,
	verticalFieldOfViewDegrees: number,
	nearPlane: number?
): ProjectedBounds?
	if #worldPoints == 0 then
		error("worldPoints must contain at least one point", 2)
	end

	local left = math.huge
	local top = math.huge
	local right = -math.huge
	local bottom = -math.huge
	local minimumDepth = math.huge
	local maximumDepth = -math.huge
	local projected: { ProjectedPoint } = {}

	for _, worldPoint in ipairs(worldPoints) do
		local point = VisualFraming.ProjectPoint(
			camera,
			worldPoint,
			viewport,
			verticalFieldOfViewDegrees,
			nearPlane
		)
		if point == nil then
			return nil
		end
		table.insert(projected, point)
		left = math.min(left, point.X)
		top = math.min(top, point.Y)
		right = math.max(right, point.X)
		bottom = math.max(bottom, point.Y)
		minimumDepth = math.min(minimumDepth, point.Depth)
		maximumDepth = math.max(maximumDepth, point.Depth)
	end

	return table.freeze({
		Left = left,
		Top = top,
		Right = right,
		Bottom = bottom,
		Width = right - left,
		Height = bottom - top,
		CenterX = (left + right) * 0.5,
		CenterY = (top + bottom) * 0.5,
		MinimumDepth = minimumDepth,
		MaximumDepth = maximumDepth,
		Corners = table.freeze(projected),
	}) :: ProjectedBounds
end

function VisualFraming.ProjectObb(
	camera: CameraInput,
	transform: TransformInput,
	size: Vector3Input,
	viewport: Viewport,
	verticalFieldOfViewDegrees: number,
	nearPlane: number?
): ProjectedBounds?
	local corners = VisualFraming.GetObbCorners(transform, size)
	local worldPoints: { Vector3Input } = {}
	for _, corner in ipairs(corners) do
		table.insert(worldPoints, corner)
	end
	return VisualFraming.ProjectWorldBounds(
		camera,
		worldPoints,
		viewport,
		verticalFieldOfViewDegrees,
		nearPlane
	)
end

function VisualFraming.GetOccupancy(bounds: ScreenRect, safeRect: ScreenRect): Occupancy
	if safeRect.Width <= 0 or safeRect.Height <= 0 then
		error("safeRect dimensions must be positive", 2)
	end
	local widthRatio = bounds.Width / safeRect.Width
	local heightRatio = bounds.Height / safeRect.Height
	return table.freeze({
		WidthRatio = widthRatio,
		HeightRatio = heightRatio,
		CenterXRatio = (bounds.CenterX - safeRect.Left) / safeRect.Width,
		CenterYRatio = (bounds.CenterY - safeRect.Top) / safeRect.Height,
		AreaRatio = widthRatio * heightRatio,
		FullyContained = bounds.Left >= safeRect.Left
			and bounds.Right <= safeRect.Right
			and bounds.Top >= safeRect.Top
			and bounds.Bottom <= safeRect.Bottom,
	}) :: Occupancy
end

function VisualFraming.GetOverlap(first: ScreenRect, second: ScreenRect): Overlap
	local width = math.max(0, math.min(first.Right, second.Right) - math.max(first.Left, second.Left))
	local height = math.max(0, math.min(first.Bottom, second.Bottom) - math.max(first.Top, second.Top))
	local area = width * height
	local firstArea = math.max(0, first.Width) * math.max(0, first.Height)
	local secondArea = math.max(0, second.Width) * math.max(0, second.Height)
	return table.freeze({
		Intersects = width > EPSILON and height > EPSILON,
		Width = width,
		Height = height,
		Area = area,
		RatioOfFirst = if firstArea > EPSILON then area / firstArea else 0,
		RatioOfSecond = if secondArea > EPSILON then area / secondArea else 0,
		HorizontalRatioOfFirst = if first.Width > EPSILON then width / first.Width else 0,
		VerticalRatioOfFirst = if first.Height > EPSILON then height / first.Height else 0,
	}) :: Overlap
end

function VisualFraming.GetDownwardPitchDegrees(camera: CameraInput): number
	local forward = resolveCamera(camera).Forward
	local horizontalLength = math.sqrt(forward.X * forward.X + forward.Z * forward.Z)
	return math.atan2(-forward.Y, horizontalLength) * DEGREES_PER_RADIAN
end

function VisualFraming.EvaluateCamera(
	verticalFieldOfViewDegrees: number,
	camera: CameraInput
): CameraEvaluation
	local fieldOfView = assertFiniteNumber(verticalFieldOfViewDegrees, "verticalFieldOfViewDegrees")
	local pitch = VisualFraming.GetDownwardPitchDegrees(camera)
	local fieldOfViewPass = fieldOfView >= VisualFraming.MinimumFieldOfView
		and fieldOfView <= VisualFraming.MaximumFieldOfView
	local pitchPass = pitch >= VisualFraming.MinimumDownwardPitchDegrees
		and pitch <= VisualFraming.MaximumDownwardPitchDegrees
	return table.freeze({
		Pass = fieldOfViewPass and pitchPass,
		FieldOfViewPass = fieldOfViewPass,
		PitchPass = pitchPass,
		FieldOfView = fieldOfView,
		DownwardPitchDegrees = pitch,
	}) :: CameraEvaluation
end

function VisualFraming.EvaluateFraming(
	bounds: ScreenRect,
	safeRect: ScreenRect,
	thresholds: FramingThresholds
): FramingEvaluation
	local occupancy = VisualFraming.GetOccupancy(bounds, safeRect)
	local widthPass = passesRange(
		occupancy.WidthRatio,
		thresholds.MinimumWidthRatio,
		thresholds.MaximumWidthRatio
	)
	local heightPass = passesRange(
		occupancy.HeightRatio,
		thresholds.MinimumHeightRatio,
		thresholds.MaximumHeightRatio
	)
	local centerXPass = passesRange(
		occupancy.CenterXRatio,
		thresholds.MinimumCenterXRatio,
		thresholds.MaximumCenterXRatio
	)
	local centerYPass = passesRange(
		occupancy.CenterYRatio,
		thresholds.MinimumCenterYRatio,
		thresholds.MaximumCenterYRatio
	)
	local containmentPass = not thresholds.RequireContained or occupancy.FullyContained
	return table.freeze({
		Pass = widthPass and heightPass and centerXPass and centerYPass and containmentPass,
		WidthPass = widthPass,
		HeightPass = heightPass,
		CenterXPass = centerXPass,
		CenterYPass = centerYPass,
		ContainmentPass = containmentPass,
		Occupancy = occupancy,
	}) :: FramingEvaluation
end

function VisualFraming.GenerateLineOfSightSamples(fixture: LineOfSightFixture): { LineOfSightSample }
	local cellSize = assertFiniteNumber(fixture.CellSize, "fixture.CellSize")
	if cellSize <= 0 then
		error("fixture.CellSize must be positive", 2)
	end

	local transform = resolveTransform(fixture.GridOrigin)
	local samples: { LineOfSightSample } = {}

	local function appendGridSample(
		name: string,
		kind: LineOfSightKind,
		gridX: number,
		gridY: number,
		gridZ: number
	)
		local position = pointOnTransform(
			transform,
			gridX * cellSize,
			gridY * cellSize,
			gridZ * cellSize
		)
		table.insert(samples, table.freeze({
			Index = #samples + 1,
			Name = name,
			Kind = kind,
			Position = position,
			GridX = gridX,
			GridY = gridY,
			GridZ = gridZ,
		}) :: LineOfSightSample)
	end

	for gridZ = 0, 4 do
		for gridX = 0, 4 do
			appendGridSample(
				string.format("LayerZero_%d_%d", gridX, gridZ),
				"LayerZero",
				gridX,
				0,
				gridZ
			)
		end
	end

	appendGridSample("UpperCorner_0_0", "UpperCorner", 0, 3, 0)
	appendGridSample("UpperCorner_4_0", "UpperCorner", 4, 3, 0)
	appendGridSample("UpperCorner_0_4", "UpperCorner", 0, 3, 4)
	appendGridSample("UpperCorner_4_4", "UpperCorner", 4, 3, 4)

	local function appendWorldSample(name: string, kind: LineOfSightKind, position: NumericVector3)
		table.insert(samples, table.freeze({
			Index = #samples + 1,
			Name = name,
			Kind = kind,
			Position = position,
		}) :: LineOfSightSample)
	end

	appendWorldSample("CrateFocus", "CrateFocus", readVector(fixture.CrateFocus, "fixture.CrateFocus"))
	appendWorldSample("GridOrigin", "GridOrigin", transform.Position)
	appendWorldSample(
		"GhostFixture",
		"GhostFixture",
		readVector(fixture.GhostFixtureCenter, "fixture.GhostFixtureCenter")
	)

	if #samples ~= VisualFraming.LineOfSightSampleCount then
		error("standard line-of-sight fixture must contain exactly 32 samples", 2)
	end
	return table.freeze(samples) :: { LineOfSightSample }
end

return table.freeze(VisualFraming)
