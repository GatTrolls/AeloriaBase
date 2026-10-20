--!strict
-- Tiny test helper for Lune. Each spec file returns { [testName]: () -> () }.

local TestKit = {}

function TestKit.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function TestKit.truthy(value: any, message: string?)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

-- Deterministic generator so test results never depend on luck.
function TestKit.seededRng(seed: number): () -> number
	-- 32-bit linear congruential generator. Lune has no Random class, and this is plenty for tests.
	local state = seed % 4294967296
	return function()
		state = (1664525 * state + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Generator that returns the given numbers in order, then repeats the last one.
function TestKit.scriptedRng(values: { number }): () -> number
	local index = 0
	return function()
		index = math.min(index + 1, #values)
		return values[index]
	end
end

return TestKit
