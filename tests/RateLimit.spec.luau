--!strict
local RateLimit = require("../src/shared/RateLimit")
local TestKit = require("./TestKit")

return {
	["a burst is allowed, then requests are dropped"] = function()
		local limiter = RateLimit.new(5)
		for _ = 1, 5 do
			TestKit.truthy(RateLimit.allow(limiter, "p", 0))
		end
		TestKit.equal(RateLimit.allow(limiter, "p", 0), false)
	end,

	["tokens refill over time"] = function()
		local limiter = RateLimit.new(5)
		for _ = 1, 5 do
			RateLimit.allow(limiter, "p", 0)
		end
		TestKit.truthy(RateLimit.allow(limiter, "p", 0.2))
	end,

	["each key has its own bucket"] = function()
		local limiter = RateLimit.new(1)
		TestKit.truthy(RateLimit.allow(limiter, "a", 0))
		TestKit.truthy(RateLimit.allow(limiter, "b", 0))
		TestKit.equal(RateLimit.allow(limiter, "a", 0), false)
	end,
}
