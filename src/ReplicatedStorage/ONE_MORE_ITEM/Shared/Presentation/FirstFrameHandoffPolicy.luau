--!strict

local FirstFrameHandoffPolicy = {}

function FirstFrameHandoffPolicy.ShouldHandoff(
	canonicalVisible: boolean,
	cameraSafe: boolean,
	presentationState: string?
): boolean
	return cameraSafe and (canonicalVisible or presentationState == "REVEALED")
end

return table.freeze(FirstFrameHandoffPolicy)
