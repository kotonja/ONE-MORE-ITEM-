--!strict

local ResponsiveLayout = require(script.Parent.ResponsiveLayout)

export type LayoutClass = ResponsiveLayout.LayoutClass

export type Geometry = {
	Position: UDim2,
	Size: UDim2,
}

export type Layout = {
	MetaBar: Geometry,
	ResultsMetaBar: Geometry,
	CollectionPanel: Geometry,
	DiscoveryReveal: Geometry,
	RankUpBanner: Geometry,
}

local function geometry(x: number, y: number, width: number, height: number): Geometry
	return table.freeze({
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(width, height),
	}) :: Geometry
end

local layouts: { [LayoutClass]: Layout } = table.freeze({
	Wide = table.freeze({
		MetaBar = geometry(0.5, 0.105, 0.50, 0.085),
		ResultsMetaBar = geometry(0.5, 0.105, 0.50, 0.085),
		CollectionPanel = geometry(0.5, 0.52, 0.78, 0.74),
		DiscoveryReveal = geometry(0.5, 0.40, 0.34, 0.18),
		RankUpBanner = geometry(0.5, 0.205, 0.38, 0.11),
	}),
	CompactLandscape = table.freeze({
		MetaBar = geometry(0.5, 0.13, 0.38, 0.12),
		ResultsMetaBar = geometry(0.5, 0.875, 0.38, 0.12),
		CollectionPanel = geometry(0.5, 0.53, 0.90, 0.84),
		DiscoveryReveal = geometry(0.5, 0.42, 0.52, 0.22),
		RankUpBanner = geometry(0.5, 0.27, 0.54, 0.15),
	}),
	Portrait = table.freeze({
		MetaBar = geometry(0.5, 0.38, 0.94, 0.11),
		ResultsMetaBar = geometry(0.5, 0.82, 0.94, 0.11),
		CollectionPanel = geometry(0.5, 0.56, 0.94, 0.78),
		DiscoveryReveal = geometry(0.5, 0.52, 0.88, 0.16),
		RankUpBanner = geometry(0.5, 0.50, 0.82, 0.11),
	}),
})

local ProfileResponsiveLayout = {}

function ProfileResponsiveLayout.Resolve(layoutClass: LayoutClass): Layout
	return layouts[layoutClass] :: Layout
end

return table.freeze(ProfileResponsiveLayout)
