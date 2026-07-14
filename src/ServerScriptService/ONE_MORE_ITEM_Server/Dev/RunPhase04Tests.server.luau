--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
if not RoundConfig.DEVELOPMENT.RUN_PHASE04_TESTS then
	print("[ONE_MORE_ITEM][Phase04Tests] Skipped: development flag is disabled")
	return
end

local Phase04TestSuite = require(script.Parent.Phase04TestSuite)
local report = Phase04TestSuite.Run()
if report.Failed > 0 then
	error(string.format(
		"[ONE_MORE_ITEM][Phase04Tests] FAILED: %d of %d tests failed",
		report.Failed,
		report.Tests
	))
end

print(string.format(
	"[ONE_MORE_ITEM][Phase04Tests] PASS: all %d tests passed seed=%d",
	report.Tests,
	report.Seed
))
