--!strict
-- Movement, Grip (stamina), defence, camera and combat tuning. Plain numbers only, so the pure
-- modules that read this file also run in the Lune tests.

local CombatConfig = {
	-- Grip: the stamina bar for sprinting, climbing and gliding. Dodging does not use it.
	Stamina = {
		Max = 240,
		-- Regeneration starts this long after the last spend or the end of a draining action.
		RegenDelaySeconds = 1,
		RegenPerSecond = 30,
		SprintPerSecond = 18,
		ClimbPerSecond = 12,
		GlidePerSecond = 8,
		ClimbLeapCost = 25,
	},

	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 26,
		ClimbSpeed = 7,
		ClimbLeapSpeed = 28,
		GlideFallSpeed = 5,
		GlideForwardSpeed = 22,
		-- Glide can only start this far above the ground.
		GlideMinHeight = 6,
		-- A plunge needs at least this much height to fall.
		PlungeMinHeight = 4,
		PlungeSpeed = 80,
		DodgeSpeed = 58,
		DodgeSeconds = 0.22,
		-- Holding the dodge input longer than this turns it into a sprint.
		SprintHoldSeconds = 0.22,
		-- The server logs players whose horizontal speed stays above this for a sample window.
		SuspiciousSpeed = 75,
	},

	Defense = {
		-- Three dodges in a row, then a short cooldown. A chain resets after a quiet moment.
		DodgeCharges = 3,
		DodgeChainResetSeconds = 1.2,
		DodgeLockoutSeconds = 1,
		DodgeMinGapSeconds = 0.25,
		-- Invulnerability granted by the server when it accepts a dodge.
		DodgeInvulnerableSeconds = 0.3,
		-- Slip: a dodge this close before a hit lands. Assist mode widens it.
		SlipWindow = 0.2,
		SlipWindowAssist = 0.3,
		SlipSlowSeconds = 1,
		SlipSlowRadius = 25,
		-- After a Slip, the next attack is a Slip counter.
		SlipCounterSeconds = 2,
		SlipCounterMultiplier = 1.5,
		SlipEnergy = 5,
		-- Cover: a swap within this long after a Slip.
		CoverSeconds = 1.2,
		-- Lift: an attack this close before a gold-flash attack lands interrupts it.
		LiftWindow = 0.15,
		LiftWindowAssist = 0.25,
		LiftEnergy = 8,
		LiftStaggerSeconds = 1,
		-- The server's clock sees a player's input late by about half their ping; windows are
		-- widened by this much so timing feels the same on every connection.
		LatencyAllowance = 0.12,
	},

	Camera = {
		Distance = 12,
		MinDistance = 5,
		MaxDistance = 22,
		ShoulderOffsetX = 1.6,
		FocusHeight = 2.2,
		MinPitchDegrees = -70,
		MaxPitchDegrees = 55,
		MouseSensitivity = 0.0035,
		GamepadDegreesPerSecond = 220,
		TouchSensitivity = 0.006,
		LockOnRange = 45,
		LockOnTurnSpeed = 10,
	},

	Combat = {
		-- A chain resets when the next attack comes later than this after the previous one.
		ComboResetSeconds = 1.1,
		-- Requests may arrive this much earlier than the cooldown allows, to absorb network jitter.
		TimingToleranceSeconds = 0.12,
		-- Benched heroes gain this share of the Finale energy the active hero earns.
		BenchEnergyShare = 0.4,
		-- A hero must rest this long on the bench before swapping in fires their Relay.
		RelayBenchSeconds = 6,
		-- Pile-On: Relay swaps allowed in a row on a Rattled enemy, ignoring the swap cooldown.
		PileOnMax = 3,
		PileOnRange = 25,
		-- Extra reach the server allows on every hitbox, because its copy of positions trails what
		-- the player saw by a few frames.
		ReachToleranceStuds = 1.5,
		-- A Geode crystal's shield, as a share of the hero's max HP. It absorbs more of its own
		-- element.
		GeodeShieldShare = 0.15,
		GeodeOwnElementBonus = 0.5,
		GeodePickupRadius = 3.5,
		-- Marked enemies take this much more critical damage.
		MarkedCritDamageBonus = 0.4,
		-- Slowed enemies move and act this much slower.
		SlowedFactor = 0.5,
		-- A Finale freezes enemies this close for its short cutscene.
		FinaleFreezeSeconds = 1.2,
		FinaleFreezeRadius = 30,
		-- Composure damage, for enemies that have a Composure bar.
		Composure = {
			HeavyHit = 25,
			Reaction = 30,
			Relay = 35,
			SlipCounter = 40,
			Lift = 120,
			Lock = 60,
		},
		RattledSeconds = 6,
		RattledDamageTaken = 0.3,
		-- Enemies that can wind up at the same time, per arena.
		MaxEnemyAttackers = 2,
		HitStopSeconds = 0.06,
		HeavyHitStopSeconds = 0.1,
	},

	-- Requests per second a player may send on each combat remote before the rest are dropped.
	RateLimits = {
		CombatAction = 12,
		MoveIntent = 20,
		PartySwap = 8,
	},
}

return CombatConfig
