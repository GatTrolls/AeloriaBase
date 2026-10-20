--!strict
--[[
	ActionLog

	When each player last attacked and dodged, and which defensive windows are open for them.
	Movement, combat and enemy code all read it, so it lives on its own with no dependencies.
	Times are server times (Workspace:GetServerTimeNow()).
]]

export type Entry = {
	lastAttackAt: number,
	lastDodgeAt: number,
	-- After a Slip: the next attack is a Slip counter until this time.
	slipCounterUntil: number,
	-- After a Slip: a swap is a Cover until this time.
	coverUntil: number,
	-- Plays the game with wider timing windows.
	assist: boolean,
}

local ActionLog = {}

local entries: { [Player]: Entry } = {}

function ActionLog.get(player: Player): Entry
	local entry = entries[player]
	if not entry then
		entry = {
			lastAttackAt = -math.huge,
			lastDodgeAt = -math.huge,
			slipCounterUntil = -math.huge,
			coverUntil = -math.huge,
			assist = false,
		}
		entries[player] = entry
	end
	return entry
end

function ActionLog.forget(player: Player)
	entries[player] = nil
end

return ActionLog
