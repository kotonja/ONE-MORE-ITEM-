--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
if not RoundConfig.DEVELOPMENT.RUN_PHASE07_TESTS then
	print("[ONE_MORE_ITEM][Phase07Tests] Skipped: development flag is disabled")
	return
end

local Phase07TestSuite = require(script.Parent.Phase07TestSuite)
local report = Phase07TestSuite.Run()
if report.Failed > 0 then
	error(string.format(
		"[ONE_MORE_ITEM][Phase07Tests] FAILED: %d of %d tests failed losRays=%d",
		report.Failed,
		report.Tests,
		report.LineOfSightRays
	))
end

print(string.format(
	"[ONE_MORE_ITEM][Phase07Tests] PASS: all %d tests passed seed=%d losRays=%d",
	report.Tests,
	report.Seed,
	report.LineOfSightRays
))
