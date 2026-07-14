--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local RoundConfig = require(Root.Shared.Config.RoundConfig)
if not RoundConfig.DEVELOPMENT.RUN_PHASE03_TESTS then
	print("[ONE_MORE_ITEM][Phase03Tests] Skipped: development flag is disabled")
	return
end

local Phase03TestSuite = require(script.Parent.Phase03TestSuite)
local report = Phase03TestSuite.Run()
if report.Failed > 0 then
	error(string.format(
		"[ONE_MORE_ITEM][Phase03Tests] FAILED: %d of %d tests failed",
		report.Failed,
		report.Tests
	))
end

print(string.format("[ONE_MORE_ITEM][Phase03Tests] PASS: all %d tests passed", report.Tests))
