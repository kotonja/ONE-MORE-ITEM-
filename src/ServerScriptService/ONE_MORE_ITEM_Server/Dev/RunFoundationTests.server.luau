--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Root = ReplicatedStorage:WaitForChild("ONE_MORE_ITEM")
local GameConfig = require(Root.Shared.Config.GameConfig)

if not GameConfig.DEVELOPMENT.RUN_FOUNDATION_TESTS then
	print("[ONE_MORE_ITEM][FoundationTests] Skipped: development flag is disabled")
	return
end

local FoundationTestSuite = require(script.Parent.FoundationTestSuite)
local report = FoundationTestSuite.Run()

if report.Failed > 0 then
	error(string.format(
		"[ONE_MORE_ITEM][FoundationTests] FAILED: %d of %d tests failed",
		report.Failed,
		report.Tests
	))
end

print(string.format("[ONE_MORE_ITEM][FoundationTests] PASS: all %d tests passed", report.Tests))
