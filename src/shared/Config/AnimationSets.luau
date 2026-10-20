--!strict
--[[
	AnimationSets

	Which animation clip plays for which action, per weapon type. Only names and timings live
	here; the clips themselves are authored or captured motion kept outside the repository and
	loaded by name (see client Rig/ClipLibrary). A missing clip simply means that action has no
	animation, so a fresh checkout still plays.

	  clip     the clip's name
	  strike   the moment inside the clip where the blow lands, in seconds
	  lead     how much of the wind-up to keep before the strike (a combo hit cannot show a whole
	           wind-up; the damage lands as soon as the player presses the button)
	  speed    playback speed for the trimmed segment
]]

export type Move = {
	clip: string,
	strike: number,
	lead: number,
	speed: number,
}

local function move(clip: string, strike: number, lead: number?, speed: number?): Move
	return { clip = clip, strike = strike, lead = lead or 0.14, speed = speed or 1.25 }
end

export type Set = {
	chain: { Move },
	charged: Move,
	plunge: Move,
	technique: Move,
	finale: Move,
}

local sword: Set = {
	chain = {
		move("sns_cross_slash", 0.83),
		move("sns_downward_slash", 0.63),
		move("sns_high_attack", 0.67),
		move("sns_low_attack", 0.8),
		move("sns_power_slash", 1.3, 0.3, 1.1),
	},
	charged = move("sns_power_slash", 1.3, 0.4, 1),
	plunge = move("sns_jump_attack", 1.27, 0.3, 1),
	technique = move("sns_hilt_melee", 0.43, 0.2, 1.1),
	finale = move("sns_power_up", 0.47, 0.35, 0.9),
}

local greatsword: Set = {
	chain = {
		move("gs_high_spin", 0.87, 0.3, 1.3),
		move("gs_jump_attack", 0.5, 0.3, 1.2),
		move("gs_slide_attack", 0.03, 0, 1.3),
		move("gs_high_spin", 0.87, 0.3, 1.3),
	},
	charged = move("gs_jump_attack", 0.5, 0.4, 1),
	plunge = move("gs_jump_attack", 0.5, 0.4, 1),
	technique = move("gs_slide_attack", 0.03, 0, 1.1),
	finale = move("gs_high_spin", 0.87, 0.5, 1),
}

-- Casters and archers borrow the casting gesture until they have clips of their own.
local cast: Set = {
	chain = {
		move("sns_spell_cast", 0.33, 0.2, 1.5),
		move("sns_spell_cast", 0.33, 0.2, 1.5),
		move("sns_spell_cast", 0.33, 0.2, 1.5),
		move("sns_spell_cast", 0.33, 0.2, 1.5),
	},
	charged = move("sns_spell_cast", 0.33, 0.3, 1.1),
	plunge = move("sns_jump_attack", 1.27, 0.3, 1),
	technique = move("sns_spell_cast", 0.33, 0.3, 1.2),
	finale = move("sns_power_up", 0.47, 0.35, 0.9),
}

local AnimationSets: { [string]: Set } = {
	sword = sword,
	greatsword = greatsword,
	-- Spears reuse the sword's thrusting and low strikes.
	lance = {
		chain = {
			move("sns_hilt_melee", 0.43, 0.2, 1.3),
			move("sns_low_attack", 0.8),
			move("sns_hilt_melee", 0.43, 0.2, 1.3),
			move("sns_downward_slash", 0.63),
			move("sns_cross_slash", 0.83, 0.2, 1.1),
		},
		charged = sword.charged,
		plunge = sword.plunge,
		technique = sword.technique,
		finale = sword.finale,
	},
	bow = cast,
	focus = cast,
}

local Reactions = {
	hurt = "r_hit_body",
	hurtHead = "r_hit_head",
	hurtLarge = "r_hit_large",
	knockdown = "r_knockdown",
	getUp = "r_getup_back",
	deathBack = "r_death_back",
	deathForward = "r_death_fwd",
	dodge = "running_flip",
	dodgeBack = "stylish_backflip",
	sprint = "l_sprint",
}

return {
	Sets = AnimationSets :: { [string]: Set },
	Reactions = table.freeze(Reactions),
	-- The set for a weapon type, falling back to the sword's.
	forWeapon = function(weapon: string): Set
		return AnimationSets[weapon] or sword
	end,
}
