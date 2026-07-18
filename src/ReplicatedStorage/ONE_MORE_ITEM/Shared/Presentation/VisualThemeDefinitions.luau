--!strict

export type ColorTokens = {
	Background: Color3,
	StructuralGraphite: Color3,
	SecondarySteel: Color3,
	Concrete: Color3,
	RubberDark: Color3,
	CrateWarm: Color3,
	CrateFloor: Color3,
	TextPrimary: Color3,
	TextSecondary: Color3,
	Cyan: Color3,
	Amber: Color3,
	Green: Color3,
	Red: Color3,
	Purple: Color3,
}

export type MaterialTokens = {
	Background: Enum.Material,
	Structure: Enum.Material,
	SecondaryStructure: Enum.Material,
	Concrete: Enum.Material,
	Rubber: Enum.Material,
	CrateShell: Enum.Material,
	CrateFloor: Enum.Material,
	Pane: Enum.Material,
	Grid: Enum.Material,
	Accent: Enum.Material,
}

export type TimingTokens = {
	Instant: number,
	Snap: number,
	Quick: number,
	Panel: number,
	Hero: number,
	ArrivalCurtainFade: number,
	CameraArrival: number,
	CameraRetarget: number,
	Layout: number,
	GhostMove: number,
	GhostRotate: number,
	GhostSettle: number,
	GhostAccepted: number,
	GhostRejected: number,
	PresentationTravel: number,
	PresentationSettle: number,
	PresentationHold: number,
	ButtonDown: number,
	ButtonReturn: number,
	LidClose: number,
	LidPause: number,
	Failure: number,
	FailureImpactPause: number,
	FailureBurst: number,
	LidOpen: number,
	GridSweepStep: number,
	PreviewReveal: number,
}

local color: ColorTokens = table.freeze({
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
})

-- Pane deliberately uses SmoothPlastic: gameplay panes must remain non-refractive.
-- Green and red are intentionally absent from ordinary environment material roles.
local material: MaterialTokens = table.freeze({
	Background = Enum.Material.SmoothPlastic,
	Structure = Enum.Material.Metal,
	SecondaryStructure = Enum.Material.Metal,
	Concrete = Enum.Material.Concrete,
	Rubber = Enum.Material.SmoothPlastic,
	CrateShell = Enum.Material.Wood,
	CrateFloor = Enum.Material.WoodPlanks,
	Pane = Enum.Material.SmoothPlastic,
	Grid = Enum.Material.SmoothPlastic,
	Accent = Enum.Material.Neon,
})

-- Existing accepted presentation timings are retained here so Phase 07 can share one
-- immutable source without introducing gameplay pacing or authority constants.
local timing: TimingTokens = table.freeze({
	Instant = 0.08,
	Snap = 0.14,
	Quick = 0.20,
	Panel = 0.30,
	Hero = 0.65,
	ArrivalCurtainFade = 0.25,
	CameraArrival = 0.60,
	CameraRetarget = 0.25,
	Layout = 0.25,
	GhostMove = 0.09,
	GhostRotate = 0.18,
	GhostSettle = 0.08,
	GhostAccepted = 0.10,
	GhostRejected = 0.12,
	PresentationTravel = 0.35,
	PresentationSettle = 0.06,
	PresentationHold = 0.04,
	ButtonDown = 0.06,
	ButtonReturn = 0.12,
	LidClose = 0.75,
	LidPause = 0.10,
	Failure = 1.00,
	FailureImpactPause = 0.14,
	FailureBurst = 0.64,
	LidOpen = 0.35,
	GridSweepStep = 0.025,
	PreviewReveal = 0.45,
})

local VisualThemeDefinitions = {
	Color = color,
	Material = material,
	Timing = timing,
}

return table.freeze(VisualThemeDefinitions)
