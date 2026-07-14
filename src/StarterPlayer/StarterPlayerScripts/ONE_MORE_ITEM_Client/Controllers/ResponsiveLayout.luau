--!strict

export type LayoutClass = "Wide" | "CompactLandscape" | "Portrait"

export type TargetName =
	"CurrentItemCard"
	| "ShipmentCard"
	| "PlacementControls"
	| "DecisionPanel"
	| "ResultsPanel"
	| "StatusBanner"
	| "RotateButton"
	| "PlaceButton"
	| "ShipButton"
	| "OneMoreButton"
	| "PackAgainButton"

export type ParentName = "Root" | TargetName

export type SafeInsets = {
	Left: number,
	Top: number,
	Right: number,
	Bottom: number,
}

export type Viewport = {
	Width: number,
	Height: number,
}

export type TargetGeometry = {
	Parent: ParentName,
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
}

export type TargetMap = { [TargetName]: TargetGeometry }

export type Bounds = {
	Left: number,
	Top: number,
	Right: number,
	Bottom: number,
	Width: number,
	Height: number,
}

export type Layout = {
	Class: LayoutClass,
	Viewport: Viewport,
	Insets: SafeInsets,
	UsableBounds: Bounds,
	Targets: TargetMap,
}

local ResponsiveLayout = {}

local PORTRAIT_RATIO = 1.10
local COMPACT_RATIO = 1.45
local COMPACT_MAX_HEIGHT = 500

local ZERO_INSETS: SafeInsets = table.freeze({
	Left = 0,
	Top = 0,
	Right = 0,
	Bottom = 0,
}) :: SafeInsets

local function assertFiniteNumber(value: number, label: string)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(string.format("ResponsiveLayout requires finite %s", label), 3)
	end
end

local function geometry(
	parent: ParentName,
	positionX: number,
	positionY: number,
	sizeX: number,
	sizeY: number,
	anchorX: number,
	anchorY: number
): TargetGeometry
	return table.freeze({
		Parent = parent,
		Position = UDim2.fromScale(positionX, positionY),
		Size = UDim2.fromScale(sizeX, sizeY),
		AnchorPoint = Vector2.new(anchorX, anchorY),
	}) :: TargetGeometry
end

local WIDE_TARGETS: TargetMap = table.freeze({
	CurrentItemCard = geometry("Root", 0.025, 0.04, 0.22, 0.27, 0, 0),
	ShipmentCard = geometry("Root", 0.975, 0.04, 0.22, 0.27, 1, 0),
	PlacementControls = geometry("Root", 0.5, 0.97, 0.38, 0.10, 0.5, 1),
	DecisionPanel = geometry("Root", 0.5, 0.96, 0.50, 0.30, 0.5, 1),
	ResultsPanel = geometry("Root", 0.5, 0.5, 0.38, 0.38, 0.5, 0.5),
	StatusBanner = geometry("Root", 0.5, 0.035, 0.30, 0.065, 0.5, 0),
	RotateButton = geometry("PlacementControls", 0.05, 0.45, 0.43, 0.42, 0, 0),
	PlaceButton = geometry("PlacementControls", 0.52, 0.45, 0.43, 0.42, 0, 0),
	ShipButton = geometry("DecisionPanel", 0.30, 0.61, 0.30, 0.25, 0, 0),
	OneMoreButton = geometry("DecisionPanel", 0.64, 0.61, 0.32, 0.25, 0, 0),
	PackAgainButton = geometry("ResultsPanel", 0.15, 0.76, 0.70, 0.16, 0, 0),
}) :: TargetMap

local COMPACT_TARGETS: TargetMap = table.freeze({
	CurrentItemCard = geometry("Root", 0.03, 0.04, 0.28, 0.38, 0, 0),
	ShipmentCard = geometry("Root", 0.97, 0.04, 0.28, 0.38, 1, 0),
	PlacementControls = geometry("Root", 0.5, 0.98, 0.62, 0.28, 0.5, 1),
	DecisionPanel = geometry("Root", 0.5, 0.98, 0.76, 0.55, 0.5, 1),
	ResultsPanel = geometry("Root", 0.5, 0.52, 0.62, 0.70, 0.5, 0.5),
	StatusBanner = geometry("Root", 0.5, 0.03, 0.38, 0.10, 0.5, 0),
	RotateButton = geometry("PlacementControls", 0.05, 0.20, 0.43, 0.72, 0, 0),
	PlaceButton = geometry("PlacementControls", 0.52, 0.20, 0.43, 0.72, 0, 0),
	ShipButton = geometry("DecisionPanel", 0.05, 0.56, 0.42, 0.38, 0, 0),
	OneMoreButton = geometry("DecisionPanel", 0.53, 0.56, 0.42, 0.38, 0, 0),
	PackAgainButton = geometry("ResultsPanel", 0.15, 0.65, 0.70, 0.28, 0, 0),
}) :: TargetMap

local PORTRAIT_TARGETS: TargetMap = table.freeze({
	CurrentItemCard = geometry("Root", 0.03, 0.03, 0.46, 0.24, 0, 0),
	ShipmentCard = geometry("Root", 0.97, 0.03, 0.46, 0.24, 1, 0),
	PlacementControls = geometry("Root", 0.5, 0.98, 0.94, 0.20, 0.5, 1),
	DecisionPanel = geometry("Root", 0.5, 0.98, 0.94, 0.42, 0.5, 1),
	ResultsPanel = geometry("Root", 0.5, 0.54, 0.92, 0.52, 0.5, 0.5),
	StatusBanner = geometry("Root", 0.5, 0.29, 0.72, 0.08, 0.5, 0),
	RotateButton = geometry("PlacementControls", 0.04, 0.38, 0.44, 0.56, 0, 0),
	PlaceButton = geometry("PlacementControls", 0.52, 0.38, 0.44, 0.56, 0, 0),
	ShipButton = geometry("DecisionPanel", 0.04, 0.66, 0.44, 0.28, 0, 0),
	OneMoreButton = geometry("DecisionPanel", 0.52, 0.66, 0.44, 0.28, 0, 0),
	PackAgainButton = geometry("ResultsPanel", 0.15, 0.66, 0.70, 0.26, 0, 0),
}) :: TargetMap

local function validatedInsets(viewportWidth: number, viewportHeight: number, insets: SafeInsets?): (SafeInsets, number, number)
	assertFiniteNumber(viewportWidth, "viewport width")
	assertFiniteNumber(viewportHeight, "viewport height")
	if viewportWidth <= 0 or viewportHeight <= 0 then
		error("ResponsiveLayout requires positive viewport dimensions", 3)
	end

	local source = insets or ZERO_INSETS
	assertFiniteNumber(source.Left, "left inset")
	assertFiniteNumber(source.Top, "top inset")
	assertFiniteNumber(source.Right, "right inset")
	assertFiniteNumber(source.Bottom, "bottom inset")
	if source.Left < 0 or source.Top < 0 or source.Right < 0 or source.Bottom < 0 then
		error("ResponsiveLayout requires non-negative safe insets", 3)
	end

	local usableWidth = viewportWidth - source.Left - source.Right
	local usableHeight = viewportHeight - source.Top - source.Bottom
	if usableWidth <= 0 or usableHeight <= 0 then
		error("ResponsiveLayout safe insets must leave a positive usable viewport", 3)
	end

	local copied: SafeInsets = table.freeze({
		Left = source.Left,
		Top = source.Top,
		Right = source.Right,
		Bottom = source.Bottom,
	}) :: SafeInsets
	return copied, usableWidth, usableHeight
end

local function makeBounds(left: number, top: number, width: number, height: number): Bounds
	return table.freeze({
		Left = left,
		Top = top,
		Right = left + width,
		Bottom = top + height,
		Width = width,
		Height = height,
	}) :: Bounds
end

local function profileFor(layoutClass: LayoutClass): TargetMap
	if layoutClass == "Portrait" then
		return PORTRAIT_TARGETS
	elseif layoutClass == "CompactLandscape" then
		return COMPACT_TARGETS
	end
	return WIDE_TARGETS
end

local function adjustRootGeometry(
	target: TargetGeometry,
	viewportWidth: number,
	viewportHeight: number,
	insets: SafeInsets,
	usableWidth: number,
	usableHeight: number
): TargetGeometry
	if target.Parent ~= "Root" then
		return target
	end
	local widthScale = usableWidth / viewportWidth
	local heightScale = usableHeight / viewportHeight
	local leftScale = insets.Left / viewportWidth
	local topScale = insets.Top / viewportHeight
	return geometry(
		"Root",
		leftScale + target.Position.X.Scale * widthScale,
		topScale + target.Position.Y.Scale * heightScale,
		target.Size.X.Scale * widthScale,
		target.Size.Y.Scale * heightScale,
		target.AnchorPoint.X,
		target.AnchorPoint.Y
	)
end

local function resolvedTargets(
	profile: TargetMap,
	viewportWidth: number,
	viewportHeight: number,
	insets: SafeInsets,
	usableWidth: number,
	usableHeight: number
): TargetMap
	return table.freeze({
		CurrentItemCard = adjustRootGeometry(profile.CurrentItemCard, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		ShipmentCard = adjustRootGeometry(profile.ShipmentCard, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		PlacementControls = adjustRootGeometry(profile.PlacementControls, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		DecisionPanel = adjustRootGeometry(profile.DecisionPanel, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		ResultsPanel = adjustRootGeometry(profile.ResultsPanel, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		StatusBanner = adjustRootGeometry(profile.StatusBanner, viewportWidth, viewportHeight, insets, usableWidth, usableHeight),
		RotateButton = profile.RotateButton,
		PlaceButton = profile.PlaceButton,
		ShipButton = profile.ShipButton,
		OneMoreButton = profile.OneMoreButton,
		PackAgainButton = profile.PackAgainButton,
	}) :: TargetMap
end

function ResponsiveLayout.Classify(viewportWidth: number, viewportHeight: number, insets: SafeInsets?): LayoutClass
	local _validated, usableWidth, usableHeight = validatedInsets(viewportWidth, viewportHeight, insets)
	local ratio = usableWidth / usableHeight
	if ratio < PORTRAIT_RATIO then
		return "Portrait"
	elseif ratio < COMPACT_RATIO or usableHeight <= COMPACT_MAX_HEIGHT then
		return "CompactLandscape"
	end
	return "Wide"
end

function ResponsiveLayout.ClassifyViewport(viewport: Viewport, insets: SafeInsets?): LayoutClass
	return ResponsiveLayout.Classify(viewport.Width, viewport.Height, insets)
end

function ResponsiveLayout.Resolve(viewportWidth: number, viewportHeight: number, insets: SafeInsets?): Layout
	local resolvedInsets, usableWidth, usableHeight = validatedInsets(viewportWidth, viewportHeight, insets)
	local layoutClass = ResponsiveLayout.Classify(viewportWidth, viewportHeight, resolvedInsets)
	local viewport: Viewport = table.freeze({ Width = viewportWidth, Height = viewportHeight }) :: Viewport
	local usableBounds = makeBounds(resolvedInsets.Left, resolvedInsets.Top, usableWidth, usableHeight)
	return table.freeze({
		Class = layoutClass,
		Viewport = viewport,
		Insets = resolvedInsets,
		UsableBounds = usableBounds,
		Targets = resolvedTargets(profileFor(layoutClass), viewportWidth, viewportHeight, resolvedInsets, usableWidth, usableHeight),
	}) :: Layout
end

function ResponsiveLayout.ResolveForViewport(viewport: Viewport, insets: SafeInsets?): Layout
	return ResponsiveLayout.Resolve(viewport.Width, viewport.Height, insets)
end

function ResponsiveLayout.ResolveLayout(viewportWidth: number, viewportHeight: number, insets: SafeInsets?): Layout
	return ResponsiveLayout.Resolve(viewportWidth, viewportHeight, insets)
end

function ResponsiveLayout.GetLayout(viewportWidth: number, viewportHeight: number, insets: SafeInsets?): Layout
	return ResponsiveLayout.Resolve(viewportWidth, viewportHeight, insets)
end

function ResponsiveLayout.ViewportBounds(viewportWidth: number, viewportHeight: number): Bounds
	validatedInsets(viewportWidth, viewportHeight, nil)
	return makeBounds(0, 0, viewportWidth, viewportHeight)
end

function ResponsiveLayout.CalculateBounds(target: TargetGeometry, parentBounds: Bounds): Bounds
	for label, value in pairs({
		["parent left"] = parentBounds.Left,
		["parent top"] = parentBounds.Top,
		["parent width"] = parentBounds.Width,
		["parent height"] = parentBounds.Height,
	}) do
		assertFiniteNumber(value, label)
	end
	if parentBounds.Width <= 0 or parentBounds.Height <= 0 then
		error("ResponsiveLayout requires positive parent bounds", 2)
	end
	if target.Position.X.Offset ~= 0 or target.Position.Y.Offset ~= 0 or target.Size.X.Offset ~= 0 or target.Size.Y.Offset ~= 0 then
		error("ResponsiveLayout target geometry must use scale-only UDim2 values", 2)
	end

	local width = parentBounds.Width * target.Size.X.Scale
	local height = parentBounds.Height * target.Size.Y.Scale
	local anchorX = parentBounds.Left + parentBounds.Width * target.Position.X.Scale
	local anchorY = parentBounds.Top + parentBounds.Height * target.Position.Y.Scale
	return makeBounds(anchorX - width * target.AnchorPoint.X, anchorY - height * target.AnchorPoint.Y, width, height)
end

function ResponsiveLayout.BoundsForTarget(layout: Layout, targetName: TargetName): Bounds
	local cached: { [TargetName]: Bounds } = {}
	local visiting: { [TargetName]: boolean } = {}
	local viewportBounds = ResponsiveLayout.ViewportBounds(layout.Viewport.Width, layout.Viewport.Height)

	local function resolve(name: TargetName): Bounds
		local existing = cached[name]
		if existing ~= nil then
			return existing
		end
		if visiting[name] then
			error(string.format("ResponsiveLayout detected a parent cycle at %s", name), 3)
		end
		local target = layout.Targets[name]
		if target == nil then
			error(string.format("ResponsiveLayout has no geometry for %s", name), 3)
		end
		visiting[name] = true
		local parentBounds = if target.Parent == "Root" then viewportBounds else resolve(target.Parent :: TargetName)
		local result = ResponsiveLayout.CalculateBounds(target, parentBounds)
		visiting[name] = nil
		cached[name] = result
		return result
	end

	return resolve(targetName)
end

function ResponsiveLayout.IsContained(inner: Bounds, outer: Bounds): boolean
	return inner.Left >= outer.Left
		and inner.Top >= outer.Top
		and inner.Right <= outer.Right
		and inner.Bottom <= outer.Bottom
end

return table.freeze(ResponsiveLayout)
