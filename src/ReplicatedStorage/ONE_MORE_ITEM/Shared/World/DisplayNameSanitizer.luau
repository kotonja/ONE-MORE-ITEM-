--!strict

local MAX_CODEPOINTS = 24
local FALLBACK_NAME = "PLAYER"

local DisplayNameSanitizer = {}

local function normalizeUtf8(value: string): string
	local length = utf8.len(value)
	if length ~= nil then
		return value
	end
	return string.gsub(value, "[^\32-\126]", "?")
end

function DisplayNameSanitizer.Sanitize(value: unknown): string
	if type(value) ~= "string" then
		return FALLBACK_NAME
	end

	local cleaned = string.gsub(value, "[%c]", " ")
	cleaned = string.gsub(cleaned, "[<>]", "")
	cleaned = string.gsub(cleaned, "%s+", " ")
	cleaned = string.match(cleaned, "^%s*(.-)%s*$") or ""
	cleaned = normalizeUtf8(cleaned)

	local length = utf8.len(cleaned) or #cleaned
	if length > MAX_CODEPOINTS then
		local endByte = utf8.offset(cleaned, MAX_CODEPOINTS + 1)
		if endByte ~= nil then
			cleaned = string.sub(cleaned, 1, endByte - 1)
		end
	end

	if cleaned == "" then
		return FALLBACK_NAME
	end
	return cleaned
end

DisplayNameSanitizer.MAX_CODEPOINTS = MAX_CODEPOINTS
DisplayNameSanitizer.FALLBACK_NAME = FALLBACK_NAME

return table.freeze(DisplayNameSanitizer)
