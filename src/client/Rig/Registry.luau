--!strict
--[[
	Registry

	Which on-screen body stands for which player character. RigController registers the rig it
	builds for a character here; effects and combat feedback ask it for the model to flash, freeze
	or animate, without depending on RigController itself.
]]

local Registry = {}

export type Entry = {
	-- The model drawn for the character (a skinned mesh or an R15 body).
	model: Model,
	-- Plays a named animation: "attack", "hurt", ... (see RigController).
	play: (name: string, params: { [string]: any }?) -> (),
	-- Pauses the body's animation for a moment (hit-stop).
	freeze: (seconds: number) -> (),
}

local entries: { [Model]: Entry } = {}

function Registry.set(character: Model, entry: Entry?)
	entries[character] = entry
end

function Registry.get(character: Model?): Entry?
	return if character then entries[character] else nil
end

-- The model to flash or highlight for a character: its rig if it has one, else the character.
function Registry.visualModel(character: Model): Model
	local entry = entries[character]
	return if entry then entry.model else character
end

return Registry
