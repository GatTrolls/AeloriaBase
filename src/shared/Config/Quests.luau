--!strict
--[[
	Quests

	The quest log's data and rules. A quest is a chain of objectives; each objective is something
	the player does (talk to someone, reach a place, defeat enemies, interact with an object) with
	a target id and a count. Names and text live in Shared.Strings / private content under
	`quest.<id>.title`, `quest.<id>.summary` and `quest.<id>.obj<N>`, so the repository only holds
	generic ids.

	Pure Luau: ProgressionService-style callers (QuestService) change a profile through these
	functions and the Story page reads the same definitions, so the tests cover the real rules.
]]

export type Objective = {
	kind: "talk" | "reach" | "defeat" | "interact",
	target: string,
	count: number,
}

export type Reward = { glint: number?, starglass: number?, exp: number? }

export type Quest = {
	id: string,
	chapter: number,
	objectives: { Objective },
	reward: Reward,
	-- Quest ids that must be completed first.
	requires: { string },
}

export type QuestState = {
	active: { [string]: { step: number, progress: number } },
	completed: { [string]: boolean },
	tracked: string,
}

local Quests = {}

local list: { Quest } = {
	{
		id = "q_prologue_1",
		chapter = 1,
		objectives = {
			{ kind = "talk", target = "npc_pocket", count = 1 },
			{ kind = "reach", target = "spot_camp", count = 1 },
		},
		reward = { glint = 300, starglass = 160 },
		requires = {},
	},
	{
		id = "q_prologue_2",
		chapter = 1,
		objectives = {
			{ kind = "defeat", target = "grunt_melee", count = 5 },
			{ kind = "interact", target = "obj_lookout", count = 1 },
		},
		reward = { glint = 500, starglass = 160 },
		requires = { "q_prologue_1" },
	},
	{
		id = "q_prologue_3",
		chapter = 1,
		objectives = {
			{ kind = "talk", target = "npc_pocket", count = 1 },
		},
		reward = { glint = 800, starglass = 320 },
		requires = { "q_prologue_2" },
	},
}

Quests.list = table.freeze(list)

local byId: { [string]: Quest } = {}
for _, quest in list do
	byId[quest.id] = quest
end
Quests.byId = byId

function Quests.get(id: string): Quest?
	return byId[id]
end

function Quests.newState(): QuestState
	return { active = {}, completed = {}, tracked = "" }
end

-- Fills in anything an old save is missing.
function Quests.normalize(state: any): QuestState
	local s = if type(state) == "table" then state else {}
	s.active = if type(s.active) == "table" then s.active else {}
	s.completed = if type(s.completed) == "table" then s.completed else {}
	s.tracked = if type(s.tracked) == "string" then s.tracked else ""
	return s :: QuestState
end

local function available(state: QuestState, quest: Quest): boolean
	if state.completed[quest.id] or state.active[quest.id] then
		return false
	end
	for _, need in quest.requires do
		if not state.completed[need] then
			return false
		end
	end
	return true
end

-- Starts every quest whose requirements are met. Returns the ids started.
function Quests.unlock(state: QuestState): { string }
	local started = {}
	for _, quest in list do
		if available(state, quest) then
			state.active[quest.id] = { step = 1, progress = 0 }
			table.insert(started, quest.id)
		end
	end
	if state.tracked == "" or not state.active[state.tracked] then
		for _, quest in list do
			if state.active[quest.id] then
				state.tracked = quest.id
				break
			end
		end
	end
	return started
end

function Quests.track(state: QuestState, id: string): boolean
	if state.active[id] then
		state.tracked = id
		return true
	end
	return false
end

export type Result = { advanced: { string }, completed: { string } }

-- An event happened: advance every active quest whose current objective matches.
function Quests.report(state: QuestState, kind: string, target: string, amount: number?): Result
	local result: Result = { advanced = {}, completed = {} }
	local n = math.max(1, math.floor(amount or 1))
	for id, progress in state.active do
		local quest = byId[id]
		local objective = quest and quest.objectives[progress.step]
		if objective and objective.kind == kind and objective.target == target then
			progress.progress += n
			table.insert(result.advanced, id)
			while progress.progress >= objective.count do
				local overflow = progress.progress - objective.count
				progress.step += 1
				progress.progress = 0
				local nextObjective = (quest :: Quest).objectives[progress.step]
				if not nextObjective then
					state.active[id] = nil
					state.completed[id] = true
					table.insert(result.completed, id)
					break
				end
				objective = nextObjective
				if objective.kind == kind and objective.target == target then
					progress.progress = overflow
				else
					break
				end
			end
		end
	end
	if #result.completed > 0 then
		Quests.unlock(state)
	end
	return result
end

return Quests
