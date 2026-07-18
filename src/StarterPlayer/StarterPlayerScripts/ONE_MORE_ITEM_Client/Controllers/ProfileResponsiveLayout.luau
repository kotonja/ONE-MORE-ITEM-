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
		MetaBar = geometry(0.5, 0.028, 0.94, 0.044),
		ResultsMetaBar = geometry(0.5, 0.028, 0.94, 0.044),
		CollectionPanel = geometry(0.5, 0.52, 0.78, 0.74),
		DiscoveryReveal = geometry(0.5, 0.40, 0.34, 0.18),
		RankUpBanner = geometry(0.5, 0.17, 0.34, 0.09),
	}),
	CompactLandscape = table.freeze({
		MetaBar = geometry(0.5, 0.025, 0.94, 0.095),
		ResultsMetaBar = geometry(0.5, 0.875, 0.58, 0.095),
		CollectionPanel = geometry(0.5, 0.53, 0.90, 0.84),
		DiscoveryReveal = geometry(0.5, 0.42, 0.52, 0.22),
		RankUpBanner = geometry(0.5, 0.24, 0.48, 0.14),
	}),
	Portrait = table.freeze({
		MetaBar = geometry(0.5, 0.02, 0.94, 0.068),
		ResultsMetaBar = geometry(0.5, 0.86, 0.94, 0.068),
		CollectionPanel = geometry(0.5, 0.56, 0.94, 0.78),
		DiscoveryReveal = geometry(0.5, 0.52, 0.88, 0.16),
		RankUpBanner = geometry(0.5, 0.405, 0.78, 0.08),
	}),
})

local ProfileResponsiveLayout = {}

function ProfileResponsiveLayout.Resolve(layoutClass: LayoutClass): Layout
	return layouts[layoutClass] :: Layout
end

return table.freeze(ProfileResponsiveLayout)
