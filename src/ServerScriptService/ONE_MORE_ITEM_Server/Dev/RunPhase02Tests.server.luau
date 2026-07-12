--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
if not RoundConfig.DEVELOPMENT.RUN_PHASE02_TESTS then
	print("[ONE_MORE_ITEM][Phase02Tests] Skipped: development flag is disabled")
	return
end

local Phase02TestSuite = require(script.Parent.Phase02TestSuite)
local report = Phase02TestSuite.Run()
if report.Failed > 0 then
	error(string.format(
		"[ONE_MORE_ITEM][Phase02Tests] FAILED: %d of %d tests failed",
		report.Failed,
		report.Tests
	))
end

print(string.format("[ONE_MORE_ITEM][Phase02Tests] PASS: all %d tests passed", report.Tests))
