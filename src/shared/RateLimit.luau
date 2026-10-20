--!strict
--[[
	RateLimit

	A token bucket per key. Every remote handler asks `allow` before doing any work, so a client
	spamming requests costs the server almost nothing. Pure Luau; covered by tests/RateLimit.spec.luau.
]]

export type Limiter = {
	perSecond: number,
	burst: number,
	buckets: { [any]: { tokens: number, at: number } },
}

local RateLimit = {}

-- `burst` defaults to one second's worth of requests.
function RateLimit.new(perSecond: number, burst: number?): Limiter
	return { perSecond = perSecond, burst = burst or perSecond, buckets = {} }
end

function RateLimit.allow(limiter: Limiter, key: any, now: number): boolean
	local bucket = limiter.buckets[key]
	if not bucket then
		bucket = { tokens = limiter.burst, at = now }
		limiter.buckets[key] = bucket
	end
	bucket.tokens = math.min(limiter.burst, bucket.tokens + (now - bucket.at) * limiter.perSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimit.forget(limiter: Limiter, key: any)
	limiter.buckets[key] = nil
end

return RateLimit
